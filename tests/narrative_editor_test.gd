extends SceneTree
## Proves the narrative editor's data layer on the real content, without an editor.
##
## The dock needs a window and a human; everything the dock can *do* to a file goes through
## `addons/narrative_editor/core/`, and that layer is plain `RefCounted` code. So this test
## loads the shipped chapters through it, edits them in a `user://` copy, saves, and reads
## the result back — including save failures and external edits, which is where a content
## tool does its real damage if it is wrong.
##
## What it pins:
##
## - both languages of a chapter load, and a conversation and node can be located by id;
## - node text, choice text, inspection text and inner-voice text round-trip through a save;
## - text with Chinese punctuation, quotes, newlines and backslashes survives untouched;
## - the structure of the file — ids, order, branches, effects, conditions, checks, `once`,
##   unknown fields — is exactly what it was, and only the edited line changed;
## - a save where the two languages disagree fails, names the address, and writes nothing;
## - a save whose second file cannot be written restores the first and reports failure;
## - external edits, deletions and read failures conflict before either language is written;
## - a transaction rollback preserves a third-party edit and its backup for manual recovery;
## - stale .saving/.backup files are kept or recovered only when the target is missing;
## - a late .saving with candidate-identical content is never mistaken for this save's file;
## - every one of the shipped content files can be rewritten byte for byte unchanged, so the
##   span-level editor is not quietly reformatting them;
## - the chapter list is the one on disk, and it agrees with the library constants.
##
## Run it with:
##
##   godot --headless --path . --script res://tests/narrative_editor_test.gd

const Harness = preload("res://tests/test_harness.gd")
const Store = preload("res://addons/narrative_editor/core/narrative_store.gd")
const JsonText = preload("res://addons/narrative_editor/core/narrative_json_text.gd")
const Parity = preload("res://addons/narrative_editor/core/narrative_parity.gd")
const FailWriter = preload("res://tests/narrative_editor_fail_writer.gd")


## Simulates a read error without relying on chmod, which is not effective for every CI user.
class UnreadableWriter extends "res://addons/narrative_editor/core/narrative_file_writer.gd":
	var unreadable_path: String = ""

	func _read_text(target: String) -> Dictionary:
		if target == unreadable_path:
			return {"ok": false, "reason": "测试设定的读取错误"}
		return super._read_text(target)


## Simulates another editor saving after staging but before the first target replacement.
class MutateAfterStageWriter extends "res://addons/narrative_editor/core/narrative_file_writer.gd":
	var mutate_after_path: String = ""
	var external_path: String = ""
	var external_text: String = ""
	var mutated: bool = false

	func _write_bytes(target: String, text: String) -> String:
		var failure := super._write_bytes(target, text)
		if failure.is_empty() and not mutated and target == mutate_after_path:
			mutated = _write_external(external_path, external_text)
		return failure

	func _write_external(target: String, text: String) -> bool:
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(text)
		file.flush()
		file.close()
		return true


## Changes the first installed language while the second target's install is failing. The
## real writer must preserve that external edit and the original backup during rollback.
class RollbackConflictWriter extends "res://addons/narrative_editor/core/narrative_file_writer.gd":
	var fail_destination: String = ""
	var external_path: String = ""
	var external_text: String = ""
	var mutated: bool = false

	func _rename(from_path: String, to_path: String) -> Error:
		if not mutated and from_path.ends_with(".saving") and to_path == fail_destination:
			mutated = _write_external(external_path, external_text)
			if mutated:
				return ERR_BUSY
		return super._rename(from_path, to_path)

	func _write_external(target: String, text: String) -> bool:
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(text)
		file.flush()
		file.close()
		return true


## Injects a second-language .saving after preflight while the first file is staged.
class LateSavingArtifactWriter extends "res://addons/narrative_editor/core/narrative_file_writer.gd":
	var trigger_path: String = ""
	var artifact_path: String = ""
	var artifact_text: String = ""
	var injected: bool = false

	func _write_bytes(target: String, text: String) -> String:
		var failure := super._write_bytes(target, text)
		if failure.is_empty() and not injected and target == trigger_path:
			injected = _write_external(artifact_path, artifact_text)
		return failure

	func _write_external(target: String, text: String) -> bool:
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(text)
		file.flush()
		file.close()
		return true


## A `user://` copy of real content: the editor is pointed at it, so a bug in the tool can
## never touch `res://data/` from a test run.
const ROOT := "user://narrative_editor_fixture"
const DIALOGUE_CHAPTERS: Array[String] = ["prologue", "street", "alley"]
const INSPECTION_CHAPTERS: Array[String] = ["classroom"]
const ABILITY_FILES: Array[String] = ["abilities.json", "en.json", "zh-CN.json"]

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "narrative_editor_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "fixture"
	if not _build_fixture():
		Harness.finish(self, _failures, "")
		return

	Harness.stage = "load and locate"
	_case_load_and_locate()
	Harness.stage = "node text"
	_case_edit_node_text()
	Harness.stage = "choice text"
	_case_edit_choice_text()
	Harness.stage = "inspection text"
	_case_edit_inspection_text()
	Harness.stage = "ability text"
	_case_edit_ability_text()
	Harness.stage = "unicode"
	_case_unicode_roundtrip()
	Harness.stage = "structure"
	_case_structure_is_unchanged()
	Harness.stage = "parity"
	_case_parity_failure()
	Harness.stage = "failed save"
	_case_failed_save_keeps_both_languages()
	Harness.stage = "external edits"
	_case_external_edits_are_conflicts()
	Harness.stage = "deleted target"
	_case_deleted_target_is_a_conflict()
	Harness.stage = "unreadable target"
	_case_unreadable_target_is_a_conflict()
	Harness.stage = "recheck before replace"
	_case_rechecks_after_staging()
	Harness.stage = "late .saving artifact"
	_case_late_saving_artifact_is_preserved()
	Harness.stage = "external edit during rollback"
	_case_external_edit_survives_rollback()
	Harness.stage = "crash artifacts"
	_case_crash_artifacts_are_preserved_or_recovered()
	Harness.stage = "dirty"
	_case_dirty_state()
	Harness.stage = "search"
	_case_search()
	Harness.stage = "identity"
	_case_every_file_rewrites_byte_identical()
	Harness.stage = "chapters"
	_case_chapter_list_matches_the_tree()

	Harness.finish(self, _failures, "narrative editor: %d assertions passed." % _checks)


# --- cases ------------------------------------------------------------------


func _case_load_and_locate() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	var opened := store.open("dialogue", "prologue")
	_expect(opened, "prologue 打不开：%s" % store.describe_errors())
	if not opened:
		return
	_expect(store.is_loaded(), "打开成功但没有标记为已加载。")
	_expect(store.file_paths().size() == L10n.LOCALES.size(), "应该每个语言一个文件，实际 %s。" % str(store.file_paths()))
	for path: String in store.file_paths():
		_expect(path.begins_with(ROOT), "编辑器读到了 fixture 之外的文件：%s" % path)
	_expect(store.warnings.is_empty(), "加载时不该有警告：%s" % str(store.warnings))

	var conversations := store.list_ids()
	_expect(conversations.has("q_wake"), "prologue 里找不到 q_wake：%s" % str(conversations))
	if not conversations.has("q_wake"):
		return
	var entries := store.node_entries("q_wake")
	_expect(entries.size() > 4, "q_wake 的节点太少：%d" % entries.size())
	_expect(String(entries[0]["id"]) == "q_1", "第一个节点应该是 q_1，实际 %s" % str(entries[0]["id"]))
	_expect(store.errors.is_empty(), "定位节点时产生了错误：%s" % store.describe_errors())

	var model := store.node_model("q_wake", 0)
	_expect(String(model.get("title", "")) == "q_wake / q_1", "节点标题不对：%s" % str(model.get("title")))
	var structure := String(model.get("structure_text", ""))
	_expect(structure.contains("节点：q_1"), "只读结构里没有节点 id：%s" % structure.left(200))
	_expect(_header_value(model, "说话者") == "q", "只读栏没有显示说话者：%s" % _header_value(model, "说话者"))
	_expect(_header_value(model, "节点 ID") == "q_1", "只读栏没有显示节点 id。")
	var text_field := _field(model, "text")
	_expect(not text_field.is_empty(), "节点正文不是可编辑字段。")
	if text_field.is_empty():
		return
	var values: Dictionary = text_field["values"]
	_expect(values.size() == L10n.LOCALES.size(), "正文应该有两种语言的输入，实际 %d 个。" % values.size())
	for locale: String in L10n.LOCALES:
		_expect(not String(values.get(locale, "")).strip_edges().is_empty(), "%s 的正文是空的。" % locale)


func _case_edit_node_text() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	store.open("dialogue", "prologue")
	var model := store.node_model("q_wake", 0)
	var field := _field(model, "text")
	_expect(not field.is_empty(), "q_wake 的第一个节点没有正文，这个用例的前提不成立。")
	if field.is_empty():
		return
	var english := "A revised opening line."
	var chinese := "改写之后的第一句。"
	_expect(store.set_field(field, "en", english), "英文正文没有写进文档：%s" % store.describe_errors())
	_expect(store.set_field(field, "zh-CN", chinese), "中文正文没有写进文档：%s" % store.describe_errors())
	_expect(store.is_dirty(), "改过正文之后不是 dirty。")
	_expect(store.save(), "保存失败：%s" % store.describe_errors())
	_expect(not store.is_dirty(), "保存成功后仍然是 dirty。")
	_expect(_read(_dialogue_path("en", "prologue")).contains(english), "英文文件里没有新正文。")
	_expect(_read(_dialogue_path("zh-CN", "prologue")).contains(chinese), "中文文件里没有新正文。")

	var reloaded := Store.new(ROOT)
	_expect(reloaded.open("dialogue", "prologue"), "保存后重新打开失败：%s" % reloaded.describe_errors())
	var back := String(_field(reloaded.node_model("q_wake", 0), "text")["values"]["zh-CN"])
	_expect(back == chinese, "重新读出来的中文正文不对：%s" % back)
	var back_en := String(_field(reloaded.node_model("q_wake", 0), "text")["values"]["en"])
	_expect(back_en == english, "重新读出来的英文正文不对：%s" % back_en)


func _case_edit_choice_text() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	store.open("dialogue", "prologue")
	var index := _node_with_choices(store, "q_wake")
	_expect(index >= 0, "q_wake 里没有带选项的节点。")
	if index < 0:
		return
	var before := String(store.node_model("q_wake", index)["structure_text"])
	var field := _field_starting_with(store.node_model("q_wake", index), "choice.0.")
	_expect(not field.is_empty(), "选项文字不是可编辑字段。")
	if field.is_empty():
		return
	_expect(store.set_field(field, "en", "A rewritten option."), "英文选项没写进去。")
	_expect(store.set_field(field, "zh-CN", "改写后的选项。"), "中文选项没写进去。")
	_expect(store.save(), "选项保存失败：%s" % store.describe_errors())
	_expect(_read(_dialogue_path("en", "prologue")).contains("A rewritten option."), "英文文件里没有新选项。")
	_expect(_read(_dialogue_path("zh-CN", "prologue")).contains("改写后的选项。"), "中文文件里没有新选项。")

	var reloaded := Store.new(ROOT)
	reloaded.open("dialogue", "prologue")
	var after := String(reloaded.node_model("q_wake", index)["structure_text"])
	_expect(before == after, "改选项文字之后，只读结构变了。\n之前：%s\n之后：%s" % [before, after])
	var reloaded_field := _field_starting_with(reloaded.node_model("q_wake", index), "choice.0.")
	_expect(
		String(reloaded_field["values"]["zh-CN"]) == "改写后的选项。",
		"重新读出来的选项不对：%s" % String(reloaded_field.get("values", {}).get("zh-CN", ""))
	)


func _case_edit_inspection_text() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	var opened := store.open("inspections", "classroom")
	_expect(opened, "classroom 检视打不开：%s" % store.describe_errors())
	if not opened:
		return
	var ids := store.list_ids()
	_expect(ids.size() > 3, "classroom 的检视条目太少：%d" % ids.size())
	if ids.is_empty():
		return
	var inspection_id: String = ids[0]
	var model := store.inspection_model(inspection_id)
	var before := String(model.get("structure_text", ""))
	for required: String in ["title", "prompt", "text"]:
		_expect(not _field(model, required).is_empty(), "检视 %s 缺少可编辑字段 %s。" % [inspection_id, required])
	var title_field := _field(model, "title")
	_expect(store.set_field(title_field, "en", "Your bag, again"), "检视标题没写进去。")
	_expect(store.set_field(title_field, "zh-CN", "又是你的书包"), "检视中文标题没写进去。")
	var text_field := _field(model, "text")
	_expect(store.set_field(text_field, "en", "The bag is lighter than it should be."), "检视正文没写进去。")
	_expect(store.set_field(text_field, "zh-CN", "书包比它应该有的重量要轻。"), "检视中文正文没写进去。")
	_expect(store.save(), "检视保存失败：%s" % store.describe_errors())

	var reloaded := Store.new(ROOT)
	reloaded.open("inspections", "classroom")
	var after_model := reloaded.inspection_model(inspection_id)
	_expect(String(after_model.get("structure_text", "")) == before, "改检视文字之后，只读结构变了。")
	_expect(
		String(_field(after_model, "title")["values"]["zh-CN"]) == "又是你的书包",
		"重新读出来的检视标题不对。"
	)
	_expect(
		String(_field(after_model, "text")["values"]["en"]) == "The bag is lighter than it should be.",
		"重新读出来的检视正文不对。"
	)


func _case_edit_ability_text() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	var opened := store.open("abilities")
	_expect(opened, "内心声音文案打不开：%s" % store.describe_errors())
	if not opened:
		return
	var ids := store.list_ids()
	_expect(not ids.is_empty(), "没有读到任何内心声音。")
	if ids.is_empty():
		return
	var ability_id: String = ids[0]
	var structure_before := _read("%s/abilities/abilities.json" % ROOT)
	var model := store.ability_model(ability_id)
	_expect(not _field(model, "name").is_empty(), "声音名称不是可编辑字段。")
	_expect(not _field(model, "description").is_empty(), "声音说明不是可编辑字段。")
	var structure := String(model.get("structure_text", ""))
	_expect(structure.contains("数值"), "只读结构里没有数值：%s" % structure.left(160))
	_expect(
		store.set_field(_field(model, "name"), "en", "Orientation, revised"),
		"英文声音名称没写进去。"
	)
	_expect(
		store.set_field(_field(model, "name"), "zh-CN", "路感（改）"),
		"中文声音名称没写进去。"
	)
	_expect(
		store.set_field(_field(model, "description"), "en", "A revised description of the same sense."),
		"英文声音说明没写进去。"
	)
	_expect(
		store.set_field(_field(model, "description"), "zh-CN", "同一份感觉的改写说明。"),
		"中文声音说明没写进去。"
	)
	_expect(store.save(), "内心声音文案保存失败：%s" % store.describe_errors())
	_expect(
		_read("%s/abilities/abilities.json" % ROOT) == structure_before,
		"保存文案时改动了 abilities.json，数值和规则必须只读。"
	)
	var reloaded := Store.new(ROOT)
	reloaded.open("abilities")
	var reloaded_model := reloaded.ability_model(ability_id)
	_expect(
		String(_field(reloaded_model, "name")["values"]["zh-CN"]) == "路感（改）",
		"重新读出来的声音名称不对。"
	)
	# The same rule the registry enforces at start-up applies before a save: a Chinese
	# description that is the English one copied over is refused unless the field is
	# declared as intentionally untranslated.
	_expect(
		reloaded.set_field(
			_field(reloaded.ability_model(ability_id), "description"),
			"zh-CN",
			String(_field(reloaded.ability_model(ability_id), "description")["values"]["en"])
		),
		"照抄英文的说明没有写进文档。"
	)
	_expect(not reloaded.save(), "照抄英文的说明竟然保存成功。")
	_expect(
		reloaded.describe_errors().contains("没有通过校验"),
		"照抄英文的说明没有指向校验器：%s" % reloaded.describe_errors()
	)


func _case_unicode_roundtrip() -> void:
	_reset_fixture()
	var text := (
		"“双引号”‘单引号’——破折号…　全角空格\n"
		+ "第二行：中文标点，句号。问号？感叹号！\t制表符\n"
		+ "反斜杠 \\ 与斜杠 / 与花括号 {} 与冒号 与 \\\"转义引号\\\""
	)
	var store := Store.new(ROOT)
	store.open("dialogue", "alley")
	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	_expect(node_index >= 0, "alley 的第一个对话里没有带正文的节点。")
	if node_index < 0:
		return
	var model := store.node_model(conversation_id, node_index)
	var field := _field(model, "text")
	_expect(store.set_field(field, "en", text), "含特殊字符的英文正文没写进去。")
	_expect(store.set_field(field, "zh-CN", text), "含特殊字符的中文正文没写进去。")
	_expect(store.save(), "含特殊字符的正文保存失败：%s" % store.describe_errors())

	var reloaded := Store.new(ROOT)
	reloaded.open("dialogue", "alley")
	var back := String(_field(reloaded.node_model(conversation_id, node_index), "text")["values"]["en"])
	_expect(back == text, "特殊字符往返后不一致。\n期望：%s\n实际：%s" % [text, back])
	var raw := _read(_dialogue_path("en", "alley"))
	_expect(raw.contains("\\n"), "换行没有写成转义序列，文件里出现了裸换行。")
	_expect(not raw.contains("\\u"), "中文被转义成了 \\uXXXX，可读的 diff 就没了。")


func _case_structure_is_unchanged() -> void:
	_reset_fixture()
	var en_path := _dialogue_path("en", "street")
	var zh_path := _dialogue_path("zh-CN", "street")
	var before_en := _read(en_path)
	var before_zh := _read(zh_path)
	var store := Store.new(ROOT)
	store.open("dialogue", "street")
	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	_expect(node_index >= 0, "street 的第一个对话里没有带正文的节点。")
	if node_index < 0:
		return
	var field := _field(store.node_model(conversation_id, node_index), "text")
	store.set_field(field, "en", "Only this line changes.")
	store.set_field(field, "zh-CN", "只有这一行变了。")
	_expect(store.save(), "保存失败：%s" % store.describe_errors())
	var after_en := _read(en_path)
	var after_zh := _read(zh_path)
	_expect(
		_same_structure(before_en, after_en),
		"保存之后英文文件的结构变了（不只是文本）。"
	)
	_expect(
		_same_structure(before_zh, after_zh),
		"保存之后中文文件的结构变了（不只是文本）。"
	)
	var changed_en := _changed_lines(before_en, after_en)
	var changed_zh := _changed_lines(before_zh, after_zh)
	_expect(changed_en == 1, "英文文件应该只改一行，实际改了 %d 行。" % changed_en)
	_expect(changed_zh == 1, "中文文件应该只改一行，实际改了 %d 行。" % changed_zh)
	_expect(
		before_en.split("\n").size() == after_en.split("\n").size(),
		"保存之后行数变了，文件被重新排版了。"
	)


func _case_parity_failure() -> void:
	_reset_fixture()
	var zh_path := _dialogue_path("zh-CN", "street")
	var en_path := _dialogue_path("en", "street")
	# Break the Chinese file the way a person would: rename one node's id, so the two
	# languages no longer describe the same conversation.
	var parsed: Variant = JSON.parse_string(_read(zh_path))
	_expect(parsed is Dictionary, "street 的中文文件读不出来。")
	if not (parsed is Dictionary):
		return
	var conversations: Dictionary = (parsed as Dictionary)["conversations"]
	var first_id: String = String(conversations.keys()[0])
	var nodes: Array = conversations[first_id]["nodes"]
	_expect(nodes.size() > 2, "street 的对话节点太少，没法构造结构不一致。")
	nodes[1]["id"] = "renamed_by_the_test"
	_write(zh_path, JSON.stringify(parsed, "  "))
	var damaged := _read(zh_path)
	var before_en := _read(en_path)

	var store := Store.new(ROOT)
	var opened := store.open("dialogue", "street")
	_expect(opened, "结构已经被破坏的文件不该连打开都失败（需要让作者看见问题）：%s" % store.describe_errors())
	if not opened:
		return
	var node_index := _first_node_with_text(store, first_id)
	_expect(node_index >= 0, "street 里没有带正文的节点。")
	if node_index < 0:
		return
	var field := _field(store.node_model(first_id, node_index), "text")
	store.set_field(field, "en", "A perfectly innocent edit.")
	_expect(not store.save(), "两种语言结构不一致时，保存竟然成功了。")
	var errors := store.describe_errors()
	_expect(errors.contains("结构不一致"), "保存失败时没有说明结构不一致：%s" % errors)
	_expect(errors.contains("nodes/1/id"), "保存失败时没有点出具体位置：%s" % errors)
	_expect(_read(en_path) == before_en, "保存失败时英文文件被改动了。")
	_expect(_read(zh_path) == damaged, "保存失败时中文文件被改动了。")


func _case_failed_save_keeps_both_languages() -> void:
	var en_probe := _dialogue_path("en", "alley")
	var zh_probe := _dialogue_path("zh-CN", "alley")
	var scenarios: Array[Dictionary] = [
		{"label": "临时文件写不进去", "write": "/dialogue/zh-CN"},
		{"label": "第二个文件被移开时失败", "destination": "/dialogue/zh-CN/", "exact": false},
		{"label": "第二个文件被换入时失败", "destination": zh_probe, "exact": true},
	]
	for scenario: Dictionary in scenarios:
		_reset_fixture()
		var en_path := en_probe
		var zh_path := zh_probe
		var before_en := _read(en_path)
		var before_zh := _read(zh_path)
		var writer := FailWriter.new()
		var store := Store.new(ROOT, writer)
		store.open("dialogue", "alley")
		var conversation_id := String(store.list_ids()[0])
		var node_index := _first_node_with_text(store, conversation_id)
		var field := _field(store.node_model(conversation_id, maxi(node_index, 0)), "text")
		store.set_field(field, "en", "This edit must not survive a failed save.")
		store.set_field(field, "zh-CN", "这次修改不应该在保存失败后留下来。")
		writer.rename_calls = 0
		writer.rename_failures = 0
		if scenario.has("write"):
			writer.fail_write_fragment = String(scenario["write"])
		if scenario.has("destination"):
			writer.fail_rename_destination = String(scenario["destination"])
			writer.fail_rename_exact = bool(scenario["exact"])
		var saved := store.save()
		var label := String(scenario["label"])
		_expect(not saved, "%s：save() 竟然返回成功。" % label)
		_expect(store.describe_errors().contains("保存失败"), "%s：没有明确说明保存失败。" % label)
		_expect(_read(en_path) == before_en, "%s：英文文件被写坏了。" % label)
		_expect(_read(zh_path) == before_zh, "%s：中文文件被写坏了。" % label)
		_expect(store.is_dirty(), "%s：保存失败之后 dirty 状态丢了。" % label)
		for suffix: String in [".saving", ".backup"]:
			_expect(
				not FileAccess.file_exists(en_path + suffix) and not FileAccess.file_exists(zh_path + suffix),
				"%s：失败之后留下了 %s 文件。" % [label, suffix]
			)


func _case_external_edits_are_conflicts() -> void:
	for locale: String in L10n.LOCALES:
		_reset_fixture()
		var en_path := _dialogue_path("en", "alley")
		var zh_path := _dialogue_path("zh-CN", "alley")
		var before_en := _read(en_path)
		var before_zh := _read(zh_path)
		var store := Store.new(ROOT)
		if not _prepare_bilingual_edit(
			store, "Pending English edit.", "未保存的中文修改。", "外部修改 %s" % locale
		):
			continue
		var conflict_path := en_path if locale == "en" else zh_path
		var external_text := (before_en if locale == "en" else before_zh) + " \n"
		_write(conflict_path, external_text)

		_expect(not store.save(), "%s 文件被磁盘内容变更后竟然保存成功。" % locale)
		var errors := store.describe_errors()
		_expect(errors.contains("保存已停止"), "%s：没有明确说明保存已停止：%s" % [locale, errors])
		_expect(errors.contains(conflict_path), "%s：错误没有点出变化的文件：%s" % [locale, errors])
		_expect(_read(conflict_path) == external_text, "%s：外部版本被改写。" % locale)
		_expect(
			_read(zh_path if locale == "en" else en_path)
			== (before_zh if locale == "en" else before_en),
			"%s 文件变化时另一种语言的文件被部分保存。" % locale
		)
		_expect(store.is_dirty(), "%s 文件变化后编辑器里的未保存修改丢失。" % locale)
		var conversation_id := String(store.list_ids()[0])
		var node_index := _first_node_with_text(store, conversation_id)
		var pending := _field(store.node_model(conversation_id, node_index), "text")
		var pending_values: Dictionary = pending.get("values", {})
		_expect(
			String(pending_values.get("en", "")) == "Pending English edit."
				and String(pending_values.get("zh-CN", "")) == "未保存的中文修改。",
			"%s 文件变化后内存中的双语编辑没有保留。" % locale
		)
		_expect(
			not FileAccess.file_exists(en_path + ".saving")
				and not FileAccess.file_exists(zh_path + ".saving"),
			"%s 的预检检测不应新建 .saving 文件。" % locale
		)


func _case_deleted_target_is_a_conflict() -> void:
	for locale: String in L10n.LOCALES:
		_reset_fixture()
		var en_path := _dialogue_path("en", "alley")
		var zh_path := _dialogue_path("zh-CN", "alley")
		var missing_path := en_path if locale == "en" else zh_path
		var other_path := zh_path if locale == "en" else en_path
		var other_before := _read(other_path)
		var store := Store.new(ROOT)
		if not _prepare_bilingual_edit(
			store, "Pending English edit.", "未保存的中文修改。", "删除文件 %s" % locale
		):
			continue
		DirAccess.remove_absolute(ProjectSettings.globalize_path(missing_path))

		_expect(not store.save(), "%s 目标文件被删除后竟然保存成功。" % locale)
		var errors := store.describe_errors()
		_expect(errors.contains("保存已停止"), "%s 删除后没有明确说明保存已停止：%s" % [locale, errors])
		_expect(errors.contains(missing_path), "%s 删除后的错误没有点出文件：%s" % [locale, errors])
		_expect(not FileAccess.file_exists(missing_path), "保存尝试新建了已删除的 %s 文件。" % locale)
		_expect(_read(other_path) == other_before, "%s 删除时另一语言不应部分保存。" % locale)
		_expect(store.is_dirty(), "%s 删除文件变化后编辑器里的未保存修改丢失。" % locale)
		_expect(
			not FileAccess.file_exists(en_path + ".saving")
				and not FileAccess.file_exists(zh_path + ".saving"),
			"%s 删除后不应新建 .saving 文件。" % locale
		)


func _case_unreadable_target_is_a_conflict() -> void:
	_reset_fixture()
	var en_path := _dialogue_path("en", "alley")
	var zh_path := _dialogue_path("zh-CN", "alley")
	var before_en := _read(en_path)
	var before_zh := _read(zh_path)
	var writer := UnreadableWriter.new()
	writer.unreadable_path = zh_path
	var store := Store.new(ROOT, writer)
	if not _prepare_bilingual_edit(store, "Pending English edit.", "未保存的中文修改。", "不可读文件"):
		return

	_expect(not store.save(), "无法读取中文文件时竟然保存成功。")
	var errors := store.describe_errors()
	_expect(errors.contains("保存已停止"), "无法读取目标后没有明确说明保存已停止：%s" % errors)
	_expect(errors.contains(zh_path), "无法读取目标的错误没有点出文件名：%s" % errors)
	_expect(errors.contains("无法读取"), "无法读取目标的错误原因不明确：%s" % errors)
	_expect(_read(en_path) == before_en, "中文目标不可读时英文文件不应部分保存。")
	_expect(_read(zh_path) == before_zh, "测试设定的读取失败不应改动中文磁盘内容。")
	_expect(store.is_dirty(), "目标不可读后编辑器里的未保存修改丢失。")


func _case_rechecks_after_staging() -> void:
	_reset_fixture()
	var en_path := _dialogue_path("en", "alley")
	var zh_path := _dialogue_path("zh-CN", "alley")
	var before_en := _read(en_path)
	var before_zh := _read(zh_path)
	var writer := MutateAfterStageWriter.new()
	writer.mutate_after_path = zh_path + ".saving"
	writer.external_path = en_path
	writer.external_text = before_en + " \n"
	var store := Store.new(ROOT, writer)
	if not _prepare_bilingual_edit(store, "Pending English edit.", "未保存的中文修改。", "暂存期间修改"):
		return

	_expect(not store.save(), "暂存期间英文文件被磁盘内容变更后竟然保存成功。")
	_expect(writer.mutated, "测试没有在暂存阶段注入外部修改。")
	var errors := store.describe_errors()
	_expect(errors.contains(en_path), "替换前复检没有点出英文目标文件名：%s" % errors)
	_expect(_read(en_path) == writer.external_text, "替换前复检仍改写了暂存期间的外部修改。")
	_expect(_read(zh_path) == before_zh, "暂存期间的变化后不应让中文文件部分保存。")
	_expect(store.is_dirty(), "替换前文件变化后未保存编辑没有保留。")
	for suffix: String in [".saving", ".backup"]:
		_expect(
			not FileAccess.file_exists(en_path + suffix)
				and not FileAccess.file_exists(zh_path + suffix),
			"替换前文件变化后不应留下 %s。" % suffix
		)


func _case_late_saving_artifact_is_preserved() -> void:
	_reset_fixture()
	var first_locale := L10n.LOCALES[0]
	var second_locale := L10n.LOCALES[1]
	var first_path := _dialogue_path(first_locale, "alley")
	var second_path := _dialogue_path(second_locale, "alley")
	var before_first := _read(first_path)
	var before_second := _read(second_path)
	var english_edit := "Pending English edit."
	var chinese_edit := "未保存的中文修改。"
	var writer := LateSavingArtifactWriter.new()
	var store := Store.new(ROOT, writer)
	if not _prepare_bilingual_edit(store, english_edit, chinese_edit, "暂存期间出现 .saving"):
		return

	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	var field := _field(store.node_model(conversation_id, node_index), "text")
	var expected_doc := JsonText.new()
	var loaded := expected_doc.load_file(second_path)
	_expect(loaded, "测试无法读取中文 fixture 来构造并发 .saving。")
	if not loaded:
		return
	var address: Array = field.get("address", [])
	var edited := expected_doc.set_string(address, chinese_edit)
	_expect(edited, "测试无法构造预期的中文暂存内容。")
	if not edited:
		return

	writer.trigger_path = first_path + ".saving"
	writer.artifact_path = second_path + ".saving"
	writer.artifact_text = expected_doc.build_text()
	_expect(not store.save(), "保存期间出现 .saving 文件后竟然保存成功。")
	_expect(writer.injected, "测试没有在双语保存预检后注入第二语言 .saving。")
	var errors := store.describe_errors()
	_expect(errors.contains(writer.artifact_path), "错误没有指出并发出现的 .saving 文件：%s" % errors)
	_expect(_read(first_path) == before_first, "并发 .saving 出现后第一种语言不应部分保存。")
	_expect(_read(second_path) == before_second, "并发 .saving 出现后第二种语言目标不应改变。")
	_expect(not FileAccess.file_exists(writer.trigger_path), "失败后本次暂存文件应清理。")
	_expect(FileAccess.file_exists(writer.artifact_path), "清理误删了并发出现的 .saving 文件。")
	_expect(
		_read(writer.artifact_path) == writer.artifact_text,
		"清理改写或删除了与候选文本相同的并发 .saving 文件。"
	)
	_expect(store.is_dirty(), "并发 .saving 出现后编辑器中的未保存修改丢失。")


func _case_external_edit_survives_rollback() -> void:
	_reset_fixture()
	var first_locale := L10n.LOCALES[0]
	var second_locale := L10n.LOCALES[1]
	var first_path := _dialogue_path(first_locale, "alley")
	var second_path := _dialogue_path(second_locale, "alley")
	var before_first := _read(first_path)
	var before_second := _read(second_path)
	var writer := RollbackConflictWriter.new()
	writer.fail_destination = second_path
	writer.external_path = first_path
	writer.external_text = before_first + " \n"
	var store := Store.new(ROOT, writer)
	if not _prepare_bilingual_edit(store, "Pending English edit.", "未保存的中文修改。", "事务恢复期间修改"):
		return

	_expect(not store.save(), "恢复期间发生磁盘内容变更后竟然保存成功。")
	_expect(writer.mutated, "测试没有在事务后半段注入外部修改。")
	var errors := store.describe_errors()
	_expect(errors.contains("恢复时检测到外部变化"), "错误没有报告安全恢复中的外部修改：%s" % errors)
	_expect(errors.contains(first_path), "恢复说明没有指出被外部修改的目标：%s" % errors)
	_expect(errors.contains(first_path + ".backup"), "恢复说明没有指出保留的备份：%s" % errors)
	_expect(errors.contains("手工比对恢复"), "恢复说明缺少人工恢复指引：%s" % errors)
	_expect(_read(first_path) == writer.external_text, "恢复改写了事务期间第三方写入的内容。")
	_expect(_read(first_path + ".backup") == before_first, "安全恢复没有保留原始备份。")
	_expect(_read(second_path) == before_second, "第二种语言应安全恢复成原文。")
	_expect(not FileAccess.file_exists(second_path + ".backup"), "已安全恢复的第二种语言不应留下备份。")
	_expect(store.is_dirty(), "发生恢复文件变化后编辑器里的未保存修改丢失。")
	for suffix: String in [".saving"]:
		_expect(
			not FileAccess.file_exists(first_path + suffix)
				and not FileAccess.file_exists(second_path + suffix),
			"安全恢复后不应留下本次临时文件。"
		)


func _case_crash_artifacts_are_preserved_or_recovered() -> void:
	_reset_fixture()
	var en_path := _dialogue_path("en", "alley")
	var zh_path := _dialogue_path("zh-CN", "alley")
	var before_en := _read(en_path)
	var before_zh := _read(zh_path)
	_write(en_path + ".backup", before_en)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(en_path))
	_write(en_path + ".saving", "staged text from an interrupted save")
	_write(zh_path + ".backup", before_zh)

	var store := Store.new(ROOT)
	var opened := store.open("dialogue", "alley")
	_expect(opened, "存在中断保存留下的文件时，能恢复的内容仍应可打开：%s" % store.describe_errors())
	if not opened:
		return
	_expect(_read(en_path) == before_en, "目标缺失时没有从 .backup 恢复英文原文。")
	_expect(not FileAccess.file_exists(en_path + ".backup"), "已恢复的英文 .backup 应被移回目标。")
	_expect(FileAccess.file_exists(en_path + ".saving"), "打开时不应擅自删除旧的 .saving。")
	_expect(FileAccess.file_exists(zh_path + ".backup"), "目标仍存在时不应擅自删除不确定的 .backup。")
	var warned_saving := false
	var warned_backup := false
	var warned_recovery := false
	for warning: String in store.warnings:
		warned_saving = warned_saving or warning.contains(en_path + ".saving")
		warned_backup = warned_backup or warning.contains(zh_path + ".backup")
		warned_recovery = warned_recovery or warning.contains("已经把备份还原")
	_expect(warned_saving, "打开时没有警告旧的 .saving。")
	_expect(warned_backup, "打开时没有警告目标仍存在的 .backup。")
	_expect(warned_recovery, "打开时没有报告自动恢复的 .backup。")

	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	var field := _field(store.node_model(conversation_id, node_index), "text")
	store.set_field(field, "en", "This remains an unsaved edit.")
	store.set_field(field, "zh-CN", "这条修改仍然留在内存中。")
	_expect(not store.save(), "旧的 .saving 存在时不应开始新保存。")
	_expect(store.describe_errors().contains(en_path + ".saving"), "保存没有指出旧的 .saving。")
	_expect(FileAccess.file_exists(en_path + ".saving"), "保存删除了旧的 .saving。")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(en_path + ".saving"))
	_expect(not store.save(), "目标存在且有不确定的 .backup 时不应开始新保存。")
	_expect(store.describe_errors().contains(zh_path + ".backup"), "保存没有指出不确定的 .backup。")
	_expect(FileAccess.file_exists(zh_path + ".backup"), "保存删除了目标仍存在时的 .backup。")
	_expect(store.is_dirty(), "旧的事务文件存在时，编辑器里的修改仍应保留。")


func _prepare_bilingual_edit(
	store: Store, english: String, chinese: String, label: String
) -> bool:
	var opened := store.open("dialogue", "alley")
	_expect(opened, "%s：alley 打不开：%s" % [label, store.describe_errors()])
	if not opened:
		return false
	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	_expect(node_index >= 0, "%s：找不到带正文的对话节点。" % label)
	if node_index < 0:
		return false
	var field := _field(store.node_model(conversation_id, node_index), "text")
	_expect(not field.is_empty(), "%s：节点正文不是可编辑字段。" % label)
	if field.is_empty():
		return false
	var en_set := store.set_field(field, "en", english)
	var zh_set := store.set_field(field, "zh-CN", chinese)
	_expect(en_set and zh_set, "%s：没有设置好双语编辑：%s" % [label, store.describe_errors()])
	return en_set and zh_set


func _case_dirty_state() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	store.open("dialogue", "alley")
	_expect(not store.is_dirty(), "刚打开就是 dirty。")
	var conversation_id := String(store.list_ids()[0])
	var node_index := _first_node_with_text(store, conversation_id)
	var model := store.node_model(conversation_id, maxi(node_index, 0))
	var field := _field(model, "text")
	var original := String(field["values"]["en"])
	store.set_field(field, "en", "An unsaved change.")
	_expect(store.is_dirty(), "改过之后不是 dirty。")
	_expect(store.edit_count() == 1, "应该只记录一处修改，实际%d。" % store.edit_count())
	_expect(store.dirty_summary().size() == 1, "未保存清单里应该有 1 条。")
	store.set_field(field, "en", original)
	_expect(not store.is_dirty(), "把改动改回原样之后仍然是 dirty。")
	store.set_field(field, "en", "Another change.")
	store.set_field(field, "zh-CN", "另一处修改。")
	_expect(store.edit_count() == 2, "两种语言各改一处，应该记录 2 处，实际 %d。" % store.edit_count())
	store.discard_edits()
	_expect(not store.is_dirty(), "放弃修改之后仍然是 dirty。")
	_expect(_read(_dialogue_path("en", "alley")) == _read("res://data/dialogue/en/alley.json"), "放弃修改改动了文件。")


func _case_search() -> void:
	_reset_fixture()
	var store := Store.new(ROOT)
	store.open("dialogue", "prologue")
	var entries := store.node_entries("q_wake")
	_expect(entries.size() > 3, "节点太少，搜索没法证明什么。")
	if entries.size() < 3:
		return
	var id_needle := String(entries[2]["id"])
	var id_hits := store.search(id_needle)
	_expect(not id_hits.is_empty(), "用节点 id「%s」搜不到任何东西。" % id_needle)

	var english_value := String(_field(store.node_model("q_wake", 0), "text")["values"]["en"])
	var english_needle := english_value.substr(0, mini(12, english_value.length()))
	var english_hits := store.search(english_needle)
	_expect(not english_hits.is_empty(), "用英文正文「%s」搜不到任何东西。" % english_needle)

	var chinese_value := String(_field(store.node_model("q_wake", 0), "text")["values"]["zh-CN"])
	var chinese_needle := chinese_value.substr(0, mini(4, chinese_value.length()))
	var chinese_hits := store.search(chinese_needle)
	_expect(not chinese_hits.is_empty(), "用中文正文「%s」搜不到任何东西。" % chinese_needle)
	for hit: Dictionary in chinese_hits:
		_expect(
			(hit["locales"] as Array).has("zh-CN"),
			"中文命中没有标明语言：%s" % str(hit.get("locales"))
		)

	var hit_fields: Array[String] = []
	for hit: Dictionary in id_hits:
		hit_fields.append(String(hit.get("field_id", "")))
	_expect(not hit_fields.is_empty(), "命中没有指明字段，界面就没法跳过去。")
	_expect(
		String(id_hits[0].get("conversation", "")) == "q_wake",
		"命中没有指明对话：%s" % str(id_hits[0].get("conversation"))
	)


func _case_every_file_rewrites_byte_identical() -> void:
	var files := _content_files()
	_expect(files.size() > 20, "内容文件太少（%d），这个断言没意义。" % files.size())
	for path: String in files:
		var doc := JsonText.new()
		_expect(doc.load_file(path), "%s 读不进来：%s" % [path, doc.error])
		if not doc.error.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(doc.text)
		var touched := _set_every_string_to_itself(doc, parsed, [])
		_expect(touched > 0, "%s 里没有找到任何字符串。" % path)
		_expect(not doc.is_dirty(), "%s：把所有字符串写回原值之后仍然是 dirty。" % path)
		_expect(doc.build_text() == doc.text, "%s：原样写回之后字节变了。" % path)


func _case_chapter_list_matches_the_tree() -> void:
	var store := Store.new()
	var dialogue_chapters := store.available_chapters("dialogue")
	_expect(
		dialogue_chapters == _sorted(DialogueLibrary.CHAPTERS),
		"章节清单和磁盘不一致：磁盘 %s，DialogueLibrary.CHAPTERS %s"
		% [str(dialogue_chapters), str(DialogueLibrary.CHAPTERS)]
	)
	_expect(
		store.paths.chapter_warnings("dialogue").is_empty(),
		"DialogueLibrary.CHAPTERS 和磁盘上的章节对不上：%s" % str(store.paths.chapter_warnings("dialogue"))
	)
	var inspection_chapters := store.available_chapters("inspections")
	_expect(
		inspection_chapters == _sorted(InspectionLibrary.CHAPTERS),
		"检视频道章节清单和磁盘不一致：%s" % str(inspection_chapters)
	)
	_expect(
		store.paths.chapter_warnings("inspections").is_empty(),
		"InspectionLibrary.CHAPTERS 和磁盘上的章节对不上：%s"
		% str(store.paths.chapter_warnings("inspections"))
	)
	_expect(store.available_chapters("abilities").is_empty(), "内心声音文案不该有章节。")


# --- fixture ----------------------------------------------------------------


func _build_fixture() -> bool:
	_clear_dir(ROOT)
	var ok := true
	for chapter: String in DIALOGUE_CHAPTERS:
		for locale: String in L10n.LOCALES:
			ok = _copy(
				"res://data/dialogue/%s/%s.json" % [locale, chapter],
				_dialogue_path(locale, chapter)
			) and ok
	for chapter: String in INSPECTION_CHAPTERS:
		for locale: String in L10n.LOCALES:
			ok = _copy(
				"res://data/inspections/%s/%s.json" % [locale, chapter],
				_inspection_path(locale, chapter)
			) and ok
	for file: String in ABILITY_FILES:
		ok = _copy("res://data/abilities/%s" % file, "%s/abilities/%s" % [ROOT, file]) and ok
	if not ok:
		_failures.append("fixture 没有准备好：真实内容文件缺失。")
	return ok


func _reset_fixture() -> void:
	_build_fixture()


func _dialogue_path(locale: String, chapter: String) -> String:
	return "%s/dialogue/%s/%s.json" % [ROOT, locale, chapter]


func _inspection_path(locale: String, chapter: String) -> String:
	return "%s/inspections/%s/%s.json" % [ROOT, locale, chapter]


func _content_files() -> Array[String]:
	var files: Array[String] = []
	for locale: String in L10n.LOCALES:
		for kind: String in ["dialogue", "inspections"]:
			var dir := "res://data/%s/%s" % [kind, locale]
			for name: String in DirAccess.get_files_at(dir):
				if name.ends_with(".json"):
					files.append("%s/%s" % [dir, name])
		files.append("res://data/abilities/%s.json" % locale)
	files.append("res://data/abilities/abilities.json")
	files.sort()
	return files


func _set_every_string_to_itself(doc: JsonText, value: Variant, address: Array) -> int:
	var touched := 0
	if value is Dictionary:
		var data: Dictionary = value
		for key: Variant in data.keys():
			touched += _set_every_string_to_itself(doc, data[key], address + [String(key)])
		return touched
	if value is Array:
		var items: Array = value
		for index in items.size():
			touched += _set_every_string_to_itself(doc, items[index], address + [index])
		return touched
	if value is String:
		var original := String(value)
		_expect(doc.get_string(address) == original, "%s：扫描得到的字符串和解析结果不一致。" % doc.pointer_of(address))
		_expect(doc.set_string(address, original), "%s：写回原值被拒绝。" % doc.pointer_of(address))
		return 1
	return 0


# --- assertions and small helpers -------------------------------------------


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _header_value(model: Dictionary, label: String) -> String:
	for row: Dictionary in model.get("header", []):
		if String(row.get("label", "")) == label:
			return String(row.get("value", ""))
	return ""


func _field(model: Dictionary, field_id: String) -> Dictionary:
	for field: Dictionary in model.get("fields", []):
		if String(field.get("field_id", "")) == field_id:
			return field
	return {}


func _field_starting_with(model: Dictionary, prefix: String) -> Dictionary:
	for field: Dictionary in model.get("fields", []):
		if String(field.get("field_id", "")).begins_with(prefix):
			return field
	return {}


## The first node of a conversation that actually carries a `text` field. A hub node can
## be choices-only, and the editor deliberately does not add a key the file does not have.
func _first_node_with_text(store: Store, conversation_id: String) -> int:
	for entry: Dictionary in store.node_entries(conversation_id):
		var model := store.node_model(conversation_id, int(entry["index"]))
		if not _field(model, "text").is_empty():
			return int(entry["index"])
	return -1


func _node_with_choices(store: Store, conversation_id: String) -> int:
	for entry: Dictionary in store.node_entries(conversation_id):
		if bool(entry.get("has_choices", false)):
			return int(entry["index"])
	return -1


func _sorted(source: Array) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in source:
		out.append(String(item))
	out.sort()
	return out


## Structure comparison that ignores the leaves a translation owns. Two versions of the
## same file must agree on everything else: ids, order, branches, effects, conditions,
## checks, numbers and unknown fields.
func _same_structure(before_text: String, after_text: String) -> bool:
	var before: Variant = JSON.parse_string(before_text)
	var after: Variant = JSON.parse_string(after_text)
	if before == null or after == null:
		return false
	var problems := Parity.compare(
		before,
		after,
		"保存前",
		"保存后",
		func(address: PackedStringArray) -> bool:
			if address.is_empty():
				return false
			var leaf := address[address.size() - 1]
			return ["text", "title", "prompt", "repeat_text", "name", "description"].has(leaf)
	)
	if problems.is_empty():
		return true
	_failures.append("结构比较发现问题：%s" % "；".join(PackedStringArray(problems)))
	return false


func _changed_lines(before_text: String, after_text: String) -> int:
	var before_lines := before_text.split("\n")
	var after_lines := after_text.split("\n")
	if before_lines.size() != after_lines.size():
		return maxi(before_lines.size(), after_lines.size())
	var changed := 0
	for index in before_lines.size():
		if before_lines[index] != after_lines[index]:
			changed += 1
	return changed


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("读不到 %s（错误码 %d）。" % [path, FileAccess.get_open_error()])
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("写不了 %s（错误码 %d）。" % [path, FileAccess.get_open_error()])
		return
	file.store_string(text)
	file.close()


func _copy(source: String, target: String) -> bool:
	if not FileAccess.file_exists(source):
		_failures.append("真实内容文件不存在：%s" % source)
		return false
	var text := _read(source)
	if text.is_empty():
		return false
	_write(target, text)
	return FileAccess.file_exists(target)


func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [path, name]))
	for name: String in DirAccess.get_directories_at(path):
		_clear_dir("%s/%s" % [path, name])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
