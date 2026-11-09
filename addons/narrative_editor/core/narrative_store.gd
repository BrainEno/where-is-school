extends RefCounted
## Editor-only: one content session — load a chapter in both languages, edit text, save.
##
## This is the whole data layer of the narrative editor, and it knows nothing about
## Control nodes, the editor or the dock: it is a `RefCounted` that takes a data root and a
## writer, so the tests drive it headlessly against a `user://` copy of the real files.
##
## Three rules decide its shape.
##
## 1. **Only text is writable.** There is a setter per text field and no setter for
##    anything else — node ids, speakers, branches, conditions, effects, checks, `once`
##    flags and the ability numbers are read out of the parsed file and never written. A
##    tool that cannot express an edit cannot make one by accident.
## 2. **A save is all or nothing.** Both languages are validated (JSON, structure, field
##    rules, then the runtime's own loader) before either file is staged, and the writer
##    rolls back if the second file refuses. A save that reports failure has written
##    nothing.
## 3. **A save is minimal.** Edits are applied to the spans of the strings that changed,
##    so the file keeps its formatting, its field order and every field the tool does not
##    know about, and the diff is the line the author edited.
##
## All messages are shown to the author inside the dock, so they are written in Chinese
## with the file, the address and the field spelled out; everything else in the codebase
## reports errors in English and this class is the exception on purpose.

const JsonText := preload("res://addons/narrative_editor/core/narrative_json_text.gd")
const NarrativePaths := preload("res://addons/narrative_editor/core/narrative_paths.gd")
const Parity := preload("res://addons/narrative_editor/core/narrative_parity.gd")
const FileWriter := preload("res://addons/narrative_editor/core/narrative_file_writer.gd")
const DialogueGraphScript := preload("res://scripts/dialogue/dialogue_graph.gd")
const InnerAbilitiesScript := preload("res://scripts/rpg/inner_abilities.gd")

const KIND_DIALOGUE := "dialogue"
const KIND_INSPECTIONS := "inspections"
const KIND_ABILITIES := "abilities"
const KINDS: Array[String] = [KIND_DIALOGUE, KIND_INSPECTIONS, KIND_ABILITIES]

## The leaves a translation may differ on. Everything else has to match between the two
## language files, which is what the save-time structure check enforces.
const DIALOGUE_TEXT_LEAVES: Array[String] = ["text", "title", "prompt", "repeat_text"]
const ABILITY_TEXT_LEAVES: Array[String] = ["name", "description"]

## Inspection fields the author may edit, in the order the dock shows them. The label is
## what the dock puts above the two text boxes.
const INSPECTION_FIELDS: Array[Dictionary] = [
	{"field_id": "title", "key": "title", "label": "标题（检视栏里的小标题）"},
	{"field_id": "prompt", "key": "prompt", "label": "提示（交互键旁边的那句话）"},
	{"field_id": "text", "key": "text", "label": "第一次查看时的正文"},
	{"field_id": "repeat_text", "key": "repeat_text", "label": "再看一次时的正文（可留空）"},
	{"field_id": "recall.text", "key": "recall", "sub": "text", "label": "紧接着的一句回忆（可留空）"},
	{"field_id": "record.text", "key": "record", "sub": "text", "label": "记进回忆录的那段文字（可留空）"},
]

const VALIDATION_DIR := "user://narrative_editor_validation"

var errors: Array[String] = []
var warnings: Array[String] = []

var paths: NarrativePaths = null
var writer: FileWriter = null

var kind: String = KIND_DIALOGUE
var chapter: String = ""
var locales: Array[String] = []
var reference_locale: String = "en"

var _docs: Dictionary = {}
var _saved_text: Dictionary = {}
var _structure: Dictionary = {}
var _candidate: Dictionary = {}
var _parsed_candidates: Dictionary = {}
var _loaded: bool = false


func _init(data_root: String = NarrativePaths.DEFAULT_DATA_ROOT, file_writer: Variant = null) -> void:
	paths = NarrativePaths.new(data_root)
	writer = file_writer if file_writer != null else FileWriter.new()
	locales = L10n.LOCALES.duplicate()
	if not locales.is_empty():
		reference_locale = locales[0]


# --- opening ----------------------------------------------------------------


## Loads both languages of one unit. `chapter` is ignored for the ability text, which is
## one file per language rather than one per chapter.
func open(unit_kind: String, unit_chapter: String = "") -> bool:
	errors.clear()
	warnings.clear()
	_docs.clear()
	_saved_text.clear()
	_structure.clear()
	_candidate.clear()
	_parsed_candidates.clear()
	_loaded = false
	kind = unit_kind
	chapter = unit_chapter
	if not KINDS.has(kind):
		errors.append("未知的内容类型：%s。" % kind)
		return false
	if locales.is_empty():
		errors.append("项目没有登记任何语言（L10n.LOCALES 是空的）。")
		return false
	_recover_incomplete_save()
	for locale: String in locales:
		var file := _file_for(locale)
		var doc := JsonText.new()
		if not doc.load_file(file):
			errors.append(doc.error)
			continue
		_docs[locale] = doc
		_saved_text[locale] = doc.text
		var parsed: Variant = JSON.parse_string(doc.text)
		if parsed == null:
			errors.append("%s 不是合法的 JSON。" % file)
			continue
		_structure[locale] = parsed
	if not errors.is_empty():
		return false
	_loaded = true
	if kind != KIND_ABILITIES:
		for missing: String in paths.missing_files(kind):
			warnings.append("缺少文件：%s（另一种语言有，这一种没有）。" % missing)
		for message: String in paths.chapter_warnings(kind):
			warnings.append(message)
	return true


## A save that was interrupted — the editor closed, the machine stopped — leaves a
## `.backup` next to the content instead of a hole. If the file it belongs to is gone, the
## backup is the only copy of that language and is put back; if both exist, the save had
## finished and the leftover is reported rather than deleted, because deleting a file
## nobody asked about is how a tool loses text.
func _recover_incomplete_save() -> void:
	var targets: Array[String] = []
	for locale: String in locales:
		targets.append(_file_for(locale))
	for recovered: String in writer.recover_missing(targets):
		warnings.append("上次保存没有完成，已经把备份还原成 %s。" % recovered)
	for leftover: String in writer.leftovers(targets):
		warnings.append("上次保存留下了 %s；它不属于内容，确认后可以删除。" % leftover)


## Re-reads what is on disk, throwing away unsaved edits. The dock asks before it is
## allowed to do this; the store itself has no opinion about confirmation.
func reload() -> bool:
	return open(kind, chapter)


func is_loaded() -> bool:
	return _loaded


func file_paths() -> Array[String]:
	var files: Array[String] = []
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			files.append((doc as JsonText).path)
	return files


func describe_errors() -> String:
	if errors.is_empty():
		return ""
	return "\n".join(errors)


## Chapters the open kind has files for. Dialogue and inspections have different chapter
## lists on disk, and the ability text has no chapters at all.
func available_chapters(unit_kind: String) -> Array[String]:
	if unit_kind == KIND_ABILITIES:
		return []
	return paths.chapters_on_disk(unit_kind)


# --- listing ----------------------------------------------------------------


func list_ids() -> Array[String]:
	var ids: Array[String] = []
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return ids
	var data: Dictionary = root
	match kind:
		KIND_DIALOGUE:
			var conversations: Variant = data.get("conversations", null)
			if conversations is Dictionary:
				for key: Variant in (conversations as Dictionary).keys():
					ids.append(String(key))
		KIND_INSPECTIONS:
			for key: Variant in data.keys():
				if _is_inspection_entry(key, data):
					ids.append(String(key))
		KIND_ABILITIES:
			var abilities: Variant = data.get("abilities", null)
			if abilities is Dictionary:
				for key: Variant in (abilities as Dictionary).keys():
					ids.append(String(key))
	return ids


## Every node of a conversation, in file order, with enough text to recognise it in a list.
func node_entries(conversation_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return entries
	var node_list: Array = nodes
	for index in node_list.size():
		var node: Variant = node_list[index]
		if not (node is Dictionary):
			continue
		var data: Dictionary = node
		var node_id := String(data.get("id", ""))
		var speaker := String(data.get("speaker", ""))
		var text := _effective([
			"conversations",
			conversation_id,
			"nodes",
			index,
			"text",
		], reference_locale, "")
		var choices: Variant = data.get("choices", [])
		var has_choices := choices is Array and (choices as Array).size() > 0
		var has_check := data.get("check") is Dictionary
		entries.append(
			{
				"index": index,
				"id": node_id,
				"speaker": speaker,
				"label": _list_label(index, node_id, speaker, text, has_choices, has_check),
				"text": text,
				"has_choices": has_choices,
				"has_check": has_check,
			}
		)
	return entries


func conversation_defaults(conversation_id: String) -> Dictionary:
	return {
		"default_source": String(_conversation_value(conversation_id, "default_source", "observed")),
		"subjective": bool(_conversation_value(conversation_id, "subjective", false)),
		"start": String(_conversation_value(conversation_id, "start", "")),
	}


# --- models -----------------------------------------------------------------


## Read-only summary plus the editable text fields of one dialogue node.
func node_model(conversation_id: String, node_index: int) -> Dictionary:
	var model := _empty_model("对话节点")
	var node := _node_value(conversation_id, node_index)
	if node.is_empty():
		errors.append("找不到节点：%s 里的第 %d 个节点。" % [conversation_id, node_index])
		return model
	var defaults := conversation_defaults(conversation_id)
	var node_id := String(node.get("id", ""))
	var speaker := String(node.get("speaker", ""))
	var source := String(node.get("source", ""))
	if source.is_empty():
		source = "（跟随对话的默认值：%s）" % String(defaults["default_source"])
	model["title"] = "%s / %s" % [conversation_id, node_id]
	model["header"] = [
		{"label": "节点 ID", "value": node_id},
		{"label": "说话者", "value": speaker},
		{"label": "叙述来源", "value": source},
	]
	model["fields"] = _node_fields(conversation_id, node_index)
	model["structure_text"] = _describe_node(conversation_id, node_index, node, defaults)
	model["context"] = {"conversation": conversation_id, "node_index": node_index, "node_id": node_id}
	return model


func inspection_model(inspection_id: String) -> Dictionary:
	var model := _empty_model("检视内容")
	var entry := _inspection_value(inspection_id)
	if entry.is_empty():
		errors.append("找不到检视内容：%s。" % inspection_id)
		return model
	model["title"] = inspection_id
	model["header"] = [
		{"label": "检视 ID", "value": inspection_id},
		{"label": "说话者（只读）", "value": String(entry.get("speaker", "protagonist"))},
		{"label": "叙述来源（只读）", "value": String(entry.get("source", ""))},
	]
	model["fields"] = _inspection_fields(inspection_id)
	model["structure_text"] = _describe_inspection(entry)
	model["context"] = {"inspection_id": inspection_id}
	return model


func ability_model(ability_id: String) -> Dictionary:
	var model := _empty_model("内心声音文案")
	var entry := _ability_value(ability_id)
	if entry.is_empty():
		errors.append("找不到内心声音：%s。" % ability_id)
		return model
	model["title"] = ability_id
	model["header"] = [
		{"label": "声音 ID（只读）", "value": ability_id},
		{"label": "数值（只读）", "value": str(entry.get("value", 0))},
		{"label": "说话者（只读）", "value": String(entry.get("speaker", ""))},
		{"label": "被动上限（只读）", "value": str(entry.get("max_passive", ""))},
	]
	model["fields"] = _ability_fields(ability_id)
	model["structure_text"] = _describe_ability(ability_id, entry)
	model["context"] = {"ability_id": ability_id}
	return model


func _empty_model(title: String) -> Dictionary:
	return {"title": title, "header": [], "fields": [], "structure_text": "", "context": {}}


# --- editing ----------------------------------------------------------------


## Applies one field of a model. This is the only write path the dock has, and it can only
## reach addresses the model itself produced.
func set_field(field: Dictionary, locale: String, value: String) -> bool:
	var address: Variant = field.get("address", null)
	if not (address is Array):
		errors.append("内部错误：字段没有地址。")
		return false
	return set_text_at(address as Array, locale, value)


## Writes a string at a JSON address in one language. Used by the tests directly and by
## `set_field()` for the dock.
func set_text_at(address: Array, locale: String, value: String) -> bool:
	var doc: Variant = _docs.get(locale, null)
	if doc == null:
		errors.append("没有 %s 语言的文档。" % locale)
		return false
	var text_doc: JsonText = doc
	if not _is_editable_address(address):
		errors.append(
			"%s：%s 不是可以编辑的文本字段（结构信息一律只读）。"
			% [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	if not text_doc.has_path(address):
		errors.append(
			"%s：找不到字段 %s。" % [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	if text_doc.kind_at(address) != "string":
		errors.append(
			"%s：%s 不是文本字段，编辑器不能改它。" % [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	return text_doc.set_string(address, value)


func is_dirty() -> bool:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null and (doc as JsonText).is_dirty():
			return true
	return false


func edit_count() -> int:
	var total := 0
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			total += (doc as JsonText).edit_count()
	return total


## One line per edited field, for the dock's status strip.
func dirty_summary() -> Array[String]:
	var summary: Array[String] = []
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc == null:
			continue
		var text_doc: JsonText = doc
		if not text_doc.is_dirty():
			continue
		for pointer: String in text_doc.edited_pointers():
			summary.append("%s：%s" % [locale, pointer])
	return summary


func discard_edits() -> void:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			(doc as JsonText).discard_edits()


# --- saving -----------------------------------------------------------------


## Runs every check a save would run, and writes nothing. `save()` is this plus the write.
func validate() -> bool:
	errors.clear()
	_candidate.clear()
	_parsed_candidates.clear()
	if not _loaded:
		errors.append("还没有打开任何内容。")
		return false
	if not is_dirty():
		return true
	for locale: String in locales:
		var doc: JsonText = _docs[locale]
		var text := doc.build_text()
		var json := JSON.new()
		if json.parse(text) != OK:
			errors.append(
				"%s：改写后的文本不是合法 JSON（第 %d 行：%s）。没有写入任何文件。"
				% [doc.path, json.get_error_line(), json.get_error_message()]
			)
			continue
		_candidate[locale] = text
		_parsed_candidates[locale] = json.data
	if not errors.is_empty():
		return false
	_check_parity()
	_check_field_rules()
	_check_with_runtime_validator()
	return errors.is_empty()


func save() -> bool:
	if not validate():
		return false
	if not is_dirty():
		return true
	var targets: Array[String] = []
	var texts: Array[String] = []
	var originals: Array[String] = []
	for locale: String in locales:
		var doc: JsonText = _docs[locale]
		targets.append(doc.path)
		texts.append(String(_candidate[locale]))
		originals.append(String(_saved_text.get(locale, "")))
	var failure := writer.save_pair(targets, texts, originals)
	if not failure.is_empty():
		errors.append("保存失败，两个语言文件都保持原样：%s" % failure)
		return false
	for index in locales.size():
		var locale := locales[index]
		var doc: JsonText = _docs[locale]
		if not doc.scan_text(texts[index]):
			errors.append(doc.error)
			return false
		_saved_text[locale] = texts[index]
		_structure[locale] = _parsed_candidates[locale]
	_candidate.clear()
	_parsed_candidates.clear()
	return true


# --- searching --------------------------------------------------------------


## Finds `query` in the ids, speakers and text of the open unit, in both languages, and
## leaves one hit per field with the languages that matched. The dock turns a hit into a
## selection.
func search(query: String) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var needle := query.strip_edges().to_lower()
	if needle.is_empty() or not _loaded:
		return hits
	for field: Dictionary in _all_fields():
		var matched: Array[String] = []
		var snippet := ""
		for locale: String in locales:
			var value := String((field["values"] as Dictionary).get(locale, ""))
			var context_text := String(field.get("search_context", "")).to_lower()
			if value.to_lower().contains(needle) or context_text.contains(needle):
				matched.append(locale)
				if snippet.is_empty():
					snippet = _snippet(value, needle)
		if matched.is_empty():
			continue
		var hit: Dictionary = field.duplicate(true)
		hit.erase("values")
		hit["locales"] = matched
		hit["snippet"] = snippet
		hits.append(hit)
	return hits


func _snippet(value: String, needle: String) -> String:
	var flat := " ".join(value.split("\n", false))
	if flat.length() <= 80:
		return flat
	var at := flat.to_lower().find(needle)
	if at < 0:
		return flat.substr(0, 80) + "…"
	var start := maxi(0, at - 30)
	var end := mini(flat.length(), at + 50)
	return ("…" if start > 0 else "") + flat.substr(start, end - start) + ("…" if end < flat.length() else "")


# --- field construction -----------------------------------------------------


func _all_fields() -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	match kind:
		KIND_DIALOGUE:
			for conversation_id: String in list_ids():
				for field: Dictionary in _conversation_fields(conversation_id):
					fields.append(field)
		KIND_INSPECTIONS:
			for inspection_id: String in list_ids():
				for field: Dictionary in _inspection_fields(inspection_id):
					fields.append(field)
		KIND_ABILITIES:
			for ability_id: String in list_ids():
				for field: Dictionary in _ability_fields(ability_id):
					fields.append(field)
	return fields


func _conversation_fields(conversation_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return fields
	var node_list: Array = nodes
	for index in node_list.size():
		for field: Dictionary in _node_fields(conversation_id, index):
			fields.append(field)
	return fields


func _node_fields(conversation_id: String, node_index: int) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var node := _node_value(conversation_id, node_index)
	if node.is_empty():
		return fields
	var node_id := String(node.get("id", ""))
	var speaker := String(node.get("speaker", ""))
	var base := ["conversations", conversation_id, "nodes", node_index]
	# A hub node may have no `text` at all: a field the file does not carry is not offered,
	# because the editor never adds a key to a node.
	if _has_address(base + ["text"]):
		fields.append(
			_make_field(
				"text",
				"正文（%s · %s）" % [node_id, speaker],
				base + ["text"],
				"node",
				{
					"conversation": conversation_id,
					"node_index": node_index,
					"node_id": node_id,
					"choice_index": -1,
					"search_context": "%s %s" % [node_id, speaker],
				}
			)
		)
	var choices: Variant = node.get("choices", [])
	if choices is Array:
		var choice_list: Array = choices
		for choice_index in choice_list.size():
			var choice: Variant = choice_list[choice_index]
			if not (choice is Dictionary):
				continue
			var choice_id := "选项 %d" % choice_index
			var choice_data: Dictionary = choice
			fields.append(
				_make_field(
					"choice.%d.text" % choice_index,
					"选项「%s」的文字" % String(choice_data.get("id", choice_id)),
					base + ["choices", choice_index, "text"],
					"choice",
					{
						"conversation": conversation_id,
						"node_index": node_index,
						"node_id": node_id,
						"choice_index": choice_index,
						"choice_id": String(choice_data.get("id", "")),
						"search_context": String(choice_data.get("id", "")),
					}
				)
			)
	return fields


func _inspection_fields(inspection_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	if _inspection_value(inspection_id).is_empty():
		return fields
	for spec: Dictionary in INSPECTION_FIELDS:
		var address: Array = [inspection_id, String(spec["key"])]
		if spec.has("sub"):
			address.append(String(spec["sub"]))
		if not _has_address(address):
			continue
		fields.append(
			_make_field(
				String(spec["field_id"]),
				String(spec["label"]),
				address,
				"inspection",
				{"inspection_id": inspection_id, "search_context": inspection_id}
			)
		)
	return fields


func _ability_fields(ability_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	if _ability_value(ability_id).is_empty():
		return fields
	for leaf: String in ABILITY_TEXT_LEAVES:
		var address: Array = ["abilities", ability_id, leaf]
		if not _has_address(address):
			continue
		var label := "名称" if leaf == "name" else "说明"
		fields.append(
			_make_field(
				leaf,
				"%s（%s）" % [label, ability_id],
				address,
				"ability",
				{"ability_id": ability_id, "search_context": ability_id}
			)
		)
	return fields


func _make_field(
	field_id: String,
	label: String,
	address: Array,
	field_kind: String,
	context: Dictionary
) -> Dictionary:
	var values: Dictionary = {}
	for locale: String in locales:
		values[locale] = _effective(address, locale, "")
	var field := {
		"field_id": field_id,
		"label": label,
		"address": address,
		"kind": field_kind,
		"values": values,
		"multiline": true,
	}
	field.merge(context, true)
	return field


## The text as the author currently sees it in one language, which is the pending edit
## while there is one and the file on disk otherwise. Lists and search read through this,
## so an unsaved line is searchable and the node list does not lag behind the text box.
##
## The language is a parameter and not `reference_locale`, because the dock shows both
## languages side by side: reading the reference document for every language put the
## English line in the Chinese box, and the author would have been editing English text
## that was labelled Chinese.
func _effective(address: Array, locale: String, fallback: String) -> String:
	var doc: Variant = _docs.get(locale, null)
	if doc == null:
		return fallback
	return (doc as JsonText).effective_string(address, fallback)


# --- structure text ---------------------------------------------------------


func _describe_node(
	conversation_id: String, node_index: int, node: Dictionary, defaults: Dictionary
) -> String:
	var lines: Array[String] = []
	lines.append("对话：%s" % conversation_id)
	lines.append("默认叙述来源：%s" % String(defaults["default_source"]))
	lines.append("主观想象对话：%s" % ("是" if bool(defaults["subjective"]) else "否"))
	lines.append("对话起点：%s" % String(defaults["start"]))
	lines.append("")
	lines.append("节点：%s（文件里的第 %d 个）" % [String(node.get("id", "")), node_index + 1])
	lines.append("说话者：%s" % String(node.get("speaker", "")))
	lines.append("叙述来源：%s" % String(node.get("source", "（跟随默认值）")))
	lines.append("下一节点：%s" % _describe_next(node))
	lines.append("条件：%s" % _describe_conditions(node.get("conditions", null)))
	lines.append("效果：%s" % _describe_effects(node.get("effects", [])))
	lines.append("检定：%s" % _describe_check(node.get("check", null)))
	var tags: Variant = node.get("tags", null)
	if tags is Array and (tags as Array).size() > 0:
		lines.append("标签：%s" % ", ".join(PackedStringArray(tags)))
	lines.append("")
	var choices: Variant = node.get("choices", [])
	if choices is Array and (choices as Array).size() > 0:
		lines.append("选项（只读）：")
		var index := 0
		for choice: Variant in (choices as Array):
			if choice is Dictionary:
				var data: Dictionary = choice
				lines.append(
					"  %d. id=%s → %s%s%s"
					% [
						index,
						String(data.get("id", "")),
						String(data.get("next", "")),
						"  [once]" if bool(data.get("once", false)) else "",
						"" if not data.has("conditions") else "  [有条件]",
					]
				)
				if data.has("effects"):
					lines.append("     效果：%s" % _describe_effects(data.get("effects", [])))
			index += 1
	else:
		lines.append("选项：无")
	return "\n".join(lines)


func _describe_inspection(entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("说话者：%s" % String(entry.get("speaker", "protagonist")))
	lines.append("叙述来源：%s" % String(entry.get("source", "")))
	lines.append("回忆条目 ID：%s" % _entry_id(entry, "recall"))
	lines.append("记录条目 ID：%s" % _entry_id(entry, "record"))
	lines.append("记录来源：%s" % _record_source(entry))
	lines.append("效果（只读）：%s" % _describe_effects(entry.get("effects", [])))
	return "\n".join(lines)


func _describe_ability(ability_id: String, entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("声音 ID：%s" % ability_id)
	lines.append("数值：%s（只读）" % str(entry.get("value", 0)))
	lines.append("说话者：%s（只读）" % String(entry.get("speaker", "")))
	lines.append("每局被动上限：%s（只读）" % str(entry.get("max_passive", "")))
	lines.append("")
	lines.append("被动规则（只读）：")
	var rules := _ability_rules(ability_id)
	if rules.is_empty():
		lines.append("  无")
	for rule: Dictionary in rules:
		lines.append(
			"  %s：%s:%s → %s（%s%s）"
			% [
				String(rule["id"]),
				String(rule["trigger_kind"]),
				String(rule["trigger_id"]),
				String(rule["conversation"]),
				"只触发一次" if bool(rule["once"]) else "可重复触发",
				"" if (rule["requires"] as Array).is_empty() else "，需要 " + ", ".join(PackedStringArray(rule["requires"])),
			]
		)
	return "\n".join(lines)


func _describe_next(node: Dictionary) -> String:
	if not node.has("next"):
		return "（不写：接着文件里的下一条）"
	var raw: Variant = node["next"]
	if raw == null:
		return "null（对话到这里结束）"
	return String(raw)


func _describe_conditions(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "无"
	var data: Dictionary = raw
	var parts: Array[String] = []
	for key: Variant in data.keys():
		parts.append("%s=%s" % [String(key), JSON.stringify(data[key])])
	if parts.is_empty():
		return "无"
	return "；".join(PackedStringArray(parts))


func _describe_effects(raw: Variant) -> String:
	if not (raw is Array) or (raw as Array).is_empty():
		return "无"
	var parts: Array[String] = []
	for effect: Variant in (raw as Array):
		if not (effect is Dictionary):
			parts.append(str(effect))
			continue
		var data: Dictionary = effect
		var effect_type := String(data.get("type", ""))
		match effect_type:
			"set_flag":
				parts.append("设为 %s=%s" % [String(data.get("flag", "")), JSON.stringify(data.get("value", true))])
			"set_objective":
				parts.append("目标 → %s" % String(data.get("key", "")))
			"record":
				parts.append(
					"记录 %s（%s）" % [String(data.get("entry_id", "")), String(data.get("source", ""))]
				)
			_:
				parts.append(JSON.stringify(data))
	return "；".join(PackedStringArray(parts))


func _describe_check(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "无"
	var data: Dictionary = raw
	var parts: Array[String] = [
		"能力=%s" % String(data.get("ability", "")),
		"难度=%s" % str(data.get("difficulty", "")),
		"类型=%s" % String(data.get("kind", "")),
		"成功→%s" % String(data.get("success", "")),
		"失败→%s" % String(data.get("failure", "")),
	]
	if data.has("modifiers"):
		parts.append("修正=%s" % JSON.stringify(data.get("modifiers")))
	if bool(data.get("repeatable", false)):
		parts.append("可重复")
	return "，".join(PackedStringArray(parts))


func _entry_id(entry: Dictionary, key: String) -> String:
	var block: Variant = entry.get(key, null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("entry_id", "（无）"))


func _record_source(entry: Dictionary) -> String:
	var block: Variant = entry.get("record", null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("source", ""))


func _list_label(
	index: int,
	node_id: String,
	speaker: String,
	text: String,
	has_choices: bool,
	has_check: bool
) -> String:
	var marks: Array[String] = []
	if has_choices:
		marks.append("选项")
	if has_check:
		marks.append("检定")
	var suffix := "" if marks.is_empty() else "  【%s】" % "、".join(PackedStringArray(marks))
	var flat := " ".join(text.split("\n", false))
	if flat.length() > 34:
		flat = flat.substr(0, 34) + "…"
	return "%d. %s · %s：%s%s" % [index + 1, node_id, speaker, flat, suffix]


# --- validation -------------------------------------------------------------


func _check_parity() -> void:
	var reference: Variant = _parsed_candidates.get(reference_locale, null)
	if reference == null:
		errors.append("没有 %s 语言的文档可以比较。" % reference_locale)
		return
	for locale: String in locales:
		if locale == reference_locale:
			continue
		var translated: Variant = _parsed_candidates.get(locale, null)
		if translated == null:
			errors.append("没有 %s 语言的文档可以比较。" % locale)
			continue
		var problems := Parity.compare(
			reference,
			translated,
			reference_locale,
			locale,
			func(address: PackedStringArray) -> bool:
				return _is_parity_ignored(address)
		)
		for problem: String in problems:
			errors.append("%s 与 %s 的结构不一致：%s" % [reference_locale, locale, problem])


## Which addresses the author owns, per content type. This is the second half of "structure
## is read-only": the dock only offers fields the store built, and the store refuses
## anything that is not on this list even when it is called directly. A node id, a branch,
## a condition or an ability number is a string or a number in the same JSON and would
## otherwise be indistinguishable from a line.
func _is_editable_address(address: Array) -> bool:
	if address.is_empty():
		return false
	var leaf := str(address[address.size() - 1])
	match kind:
		KIND_DIALOGUE:
			if leaf != "text" or address.size() < 5:
				return false
			if str(address[0]) != "conversations" or str(address[2]) != "nodes":
				return false
			# conversations/<id>/nodes/<i>/text
			if address.size() == 5:
				return true
			# conversations/<id>/nodes/<i>/choices/<j>/text
			return address.size() == 7 and str(address[4]) == "choices"
		KIND_INSPECTIONS:
			if address.size() == 2:
				return ["title", "prompt", "text", "repeat_text"].has(leaf)
			if address.size() == 3:
				return ["recall", "record"].has(str(address[1])) and leaf == "text"
			return false
		KIND_ABILITIES:
			return (
				address.size() == 3
				and str(address[0]) == "abilities"
				and ABILITY_TEXT_LEAVES.has(leaf)
			)
	return false


## The only addresses two languages are allowed to differ on: the declared locale, the
## player-visible text each language owns, and the per-language exception list in the
## ability text.
func _is_parity_ignored(address: PackedStringArray) -> bool:
	if address.is_empty():
		return false
	var leaf := address[address.size() - 1]
	if address.size() == 1 and leaf == "locale":
		return true
	if kind == KIND_ABILITIES:
		return ABILITY_TEXT_LEAVES.has(leaf) or leaf == "untranslated_fields"
	return DIALOGUE_TEXT_LEAVES.has(leaf)


func _check_field_rules() -> void:
	match kind:
		KIND_DIALOGUE:
			_check_dialogue_rules()
		KIND_INSPECTIONS:
			_check_inspection_rules()
		KIND_ABILITIES:
			_check_ability_rules()


func _check_dialogue_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var conversations: Variant = (root as Dictionary).get("conversations", null)
		if not (conversations is Dictionary):
			continue
		for conversation_id: Variant in (conversations as Dictionary).keys():
			var conversation: Variant = (conversations as Dictionary)[conversation_id]
			if not (conversation is Dictionary):
				continue
			var nodes: Variant = (conversation as Dictionary).get("nodes", null)
			if not (nodes is Array):
				continue
			var node_index := 0
			for node: Variant in (nodes as Array):
				if node is Dictionary:
					var data: Dictionary = node
					var where := "%s：%s/%s" % [path, String(conversation_id), String(data.get("id", "#%d" % node_index))]
					var text := String(data.get("text", "")).strip_edges()
					var choices: Variant = data.get("choices", [])
					var has_choices := choices is Array and (choices as Array).size() > 0
					if text.is_empty() and not has_choices:
						errors.append("%s：正文是空的，而且这个节点没有选项，玩家会看到一片空白。" % where)
					if choices is Array:
						var choice_index := 0
						for choice: Variant in (choices as Array):
							if choice is Dictionary:
								var choice_text := String((choice as Dictionary).get("text", "")).strip_edges()
								if choice_text.is_empty():
									errors.append(
										"%s：第 %d 个选项（%s）的文字是空的。"
										% [where, choice_index + 1, String((choice as Dictionary).get("id", ""))]
									)
							choice_index += 1
				node_index += 1


func _check_inspection_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var data: Dictionary = root
		for key: Variant in data.keys():
			if not _is_inspection_entry(key, data):
				continue
			var entry: Variant = data[key]
			if not (entry is Dictionary):
				continue
			var entry_data: Dictionary = entry
			for required: String in ["title", "prompt", "text"]:
				if String(entry_data.get(required, "")).strip_edges().is_empty():
					errors.append(
						"%s：检视 %s 的 %s 是空的。" % [path, String(key), required]
					)


func _check_ability_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var abilities: Variant = (root as Dictionary).get("abilities", null)
		if not (abilities is Dictionary):
			continue
		for ability_id: Variant in (abilities as Dictionary).keys():
			var entry: Variant = (abilities as Dictionary)[ability_id]
			if not (entry is Dictionary):
				continue
			for leaf: String in ABILITY_TEXT_LEAVES:
				if String((entry as Dictionary).get(leaf, "")).strip_edges().is_empty():
					errors.append("%s：内心声音 %s 的 %s 是空的。" % [path, String(ability_id), leaf])


## Runs the loader the game itself uses on the candidate text, so a file that would fail at
## start-up is caught before it is written. Dialogue and ability text both have a loader
## that takes a path or a directory; inspection text does not, and is covered by the
## structure check and the field rules above instead.
func _check_with_runtime_validator() -> void:
	if kind == KIND_DIALOGUE:
		_check_with_dialogue_graph()
	elif kind == KIND_ABILITIES:
		_check_with_inner_abilities()


func _check_with_dialogue_graph() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VALIDATION_DIR))
	for locale: String in locales:
		if not _candidate.has(locale):
			continue
		var temp := "%s/%s-%s.json" % [VALIDATION_DIR, locale, chapter]
		var doc: JsonText = _docs[locale]
		var failure := writer.write_atomic(temp, String(_candidate[locale]))
		if not failure.is_empty():
			errors.append("无法写校验用的临时文件：%s" % failure)
			continue
		var graph: Variant = DialogueGraphScript.load_from_file(temp)
		for message: String in graph.errors:
			errors.append(
				"%s：%s" % [doc.path, String(message).replace(temp, doc.path)]
			)
		_remove_file(temp)


func _check_with_inner_abilities() -> void:
	var folder := "%s/abilities" % VALIDATION_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var structure := paths.ability_structure_file()
	var structure_failure := writer.write_atomic(
		"%s/abilities.json" % folder, _read_file_text(structure)
	)
	if not structure_failure.is_empty():
		errors.append("无法写校验用的临时文件：%s" % structure_failure)
		return
	for locale: String in locales:
		if not _candidate.has(locale):
			continue
		var temp := "%s/%s.json" % [folder, locale]
		var failure := writer.write_atomic(temp, String(_candidate[locale]))
		if not failure.is_empty():
			errors.append("无法写校验用的临时文件：%s" % failure)
			return
	var abilities: InnerAbilities = InnerAbilitiesScript.load_all(folder)
	if abilities.is_valid():
		return
	for message: String in abilities.errors:
		errors.append("内心声音文案没有通过校验：%s" % _devalidate_path(message, folder))


func _devalidate_path(message: String, folder: String) -> String:
	var cleaned := message.replace("%s/abilities.json" % folder, paths.ability_structure_file())
	for locale: String in locales:
		cleaned = cleaned.replace(
			"%s/%s.json" % [folder, locale], paths.ability_text_file(locale)
		)
	return cleaned


# --- lookups ----------------------------------------------------------------


func _file_for(locale: String) -> String:
	match kind:
		KIND_INSPECTIONS:
			return paths.inspection_file(locale, chapter)
		KIND_ABILITIES:
			return paths.ability_text_file(locale)
		_:
			return paths.dialogue_file(locale, chapter)


func _is_inspection_entry(key: Variant, data: Dictionary) -> bool:
	if String(key) in ["format_version", "locale"]:
		return false
	var value: Variant = data[key]
	if not (value is Dictionary):
		return false
	return (value as Dictionary).has("text") or (value as Dictionary).has("title")


func _has_address(address: Array) -> bool:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null and (doc as JsonText).has_path(address):
			return true
	return false


func _conversation_value(conversation_id: String, key: String, fallback: Variant = null) -> Variant:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return fallback
	var conversations: Variant = (root as Dictionary).get("conversations", null)
	if not (conversations is Dictionary):
		return fallback
	var conversation: Variant = (conversations as Dictionary).get(conversation_id, null)
	if not (conversation is Dictionary):
		return fallback
	if not (conversation as Dictionary).has(key):
		return fallback
	return (conversation as Dictionary)[key]


func _node_value(conversation_id: String, node_index: int) -> Dictionary:
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return {}
	var node_list: Array = nodes
	if node_index < 0 or node_index >= node_list.size():
		return {}
	var node: Variant = node_list[node_index]
	if not (node is Dictionary):
		return {}
	return node


func _inspection_value(inspection_id: String) -> Dictionary:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return {}
	var data: Dictionary = root
	if not data.has(inspection_id):
		return {}
	var entry: Variant = data[inspection_id]
	if not (entry is Dictionary):
		return {}
	return entry


func _ability_value(ability_id: String) -> Dictionary:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return {}
	var abilities: Variant = (root as Dictionary).get("abilities", null)
	if not (abilities is Dictionary):
		return {}
	var entry: Variant = (abilities as Dictionary).get(ability_id, null)
	if not (entry is Dictionary):
		return {}
	return entry


## The passive rules that point at this voice, read from `abilities.json`. Read-only.
func _ability_rules(ability_id: String) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	var text := _read_file_text(paths.ability_structure_file())
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return rules
	var raw: Variant = (parsed as Dictionary).get("passives", [])
	if not (raw is Array):
		return rules
	for rule: Variant in (raw as Array):
		if not (rule is Dictionary):
			continue
		var data: Dictionary = rule
		if String(data.get("ability", "")) != ability_id:
			continue
		var trigger: Variant = data.get("trigger", {})
		var trigger_data: Dictionary = trigger if trigger is Dictionary else {}
		var requires: Array[String] = []
		var raw_requires: Variant = data.get("requires", [])
		if raw_requires is Array:
			for flag: Variant in (raw_requires as Array):
				requires.append(String(flag))
		rules.append(
			{
				"id": String(data.get("id", "")),
				"trigger_kind": String(trigger_data.get("kind", "")),
				"trigger_id": String(trigger_data.get("id", "")),
				"conversation": String(data.get("conversation", "")),
				"once": bool(data.get("once", true)),
				"requires": requires,
			}
		)
	return rules


func _read_file_text(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _remove_file(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
