extends RefCounted
## Author workspace: immutable shipped chapters, an operation log, and validated graphs.
## All mutations build a candidate first. The live path also proves bilingual parity
## and writes the journal before publishing a replacement to the same game session.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const Journal := preload("res://scripts/story_editor/draft_journal.gd")
const NativeChapter := preload("res://scripts/story_editor/native_chapter.gd")
const UNDO_LIMIT := 24
# Leave space for escaped journal/bridge envelopes and a separate unfinished field.
const LOG_LIMIT := 640 * 1024

var _base := {}
var _chapters_by_conversation := {}
var _graphs := {}
var _original_graphs := {}
var _entries := {}
var _data := {}
var _followups := {}
var _undo: Array[Dictionary] = []
var _journal: Journal
var _unapplied := {}
var _live: bool
var _sources := {}
var _mirrors := {}
var live_buffer := {}
var blocked := ""
var error := ""
var buffer := {}
var exported_digest := ""


func _init(directory: String = "", live: bool = false) -> void:
	_journal = Journal.new(Journal.DIRECTORY if directory.is_empty() else directory)
	_live = live


func load_workspace() -> void:
	for chapter: String in DialogueLibrary.CHAPTERS:
		var path := DialogueLibrary.chapter_path(Patch.LOCALE, chapter)
		var data: Dictionary
		if _live:
			var zh := NativeChapter.read_source(path)
			var en := NativeChapter.read_source(DialogueLibrary.chapter_path(NativeChapter.ENGLISH, chapter))
			if zh.is_empty() or en.is_empty():
				blocked = "无法读取双语基础章节：%s" % chapter
				return
			_sources[chapter] = {Patch.LOCALE: zh, NativeChapter.ENGLISH: en}
			data = zh["data"]
		else:
			data = Patch.read_json(path)
		var graph := DialogueGraph.load_from_data(data, chapter)
		if not graph.is_valid() or graph.chapter != chapter or graph.locale != Patch.LOCALE:
			blocked = "无法读取游戏对白：%s" % chapter
			return
		_base[chapter] = data
		_graphs[chapter] = graph
		_original_graphs[chapter] = graph
		for id: StringName in graph.get_conversation_ids():
			_chapters_by_conversation[String(id)] = chapter
	var saved: Dictionary = _journal.recover()
	if not _journal.problem.is_empty():
		blocked = _journal.problem
		return
	if saved.is_empty():
		return
	_unapplied = saved["draft"]
	if not Patch.valid_envelope(_unapplied) or not _install(_unapplied["chapters"]):
		blocked = "旧草稿未应用。可以先导出原草稿到电脑核对。%s" % error
		return
	_unapplied = {}
	if saved.get("buffer") is Dictionary:
		buffer = saved["buffer"]
	if saved.get("live_buffer") is Dictionary:
		live_buffer = saved["live_buffer"]
	if saved.get("exported") is String:
		exported_digest = saved["exported"]


func chapter_for(conversation: String) -> String:
	return _chapters_by_conversation.get(conversation, "")


func chapter_ids() -> Array:
	return _base.keys()


func conversation_ids(chapter: String) -> Array:
	var data: Dictionary = _base.get(chapter, {})
	return data.get("conversations", {}).keys()


func nodes_for(chapter: String, conversation: String) -> Array:
	return Patch.get_conversation(_data.get(chapter, _base.get(chapter, {})), conversation).get("nodes", [])


func graph_for(chapter: String, original: bool = false) -> DialogueGraph:
	return (_original_graphs if original else _graphs).get(chapter)


## Search the validated draft, including new lines and choices. Results carry IDs, not
## a menu index or a copy of the whole field, so a jump always opens the real field.
func find_fields(query: String, limit: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var needle := query.strip_edges().to_lower()
	if needle.is_empty() or limit <= 0:
		return found
	for chapter: String in chapter_ids():
		for conversation: String in conversation_ids(chapter):
			for row: Dictionary in nodes_for(chapter, conversation):
				var node: String = row["id"]
				var text: String = row.get("text", "")
				var keys := "%s %s %s %s" % [chapter, conversation, node, row["speaker"]]
				if keys.to_lower().contains(needle) or text.to_lower().contains(needle):
					found.append(_match_field(chapter, conversation, node, "", text, needle))
					if found.size() >= limit:
						return found
				for option: Dictionary in Patch.choices_at(row):
					var id: String = option["id"]
					text = option["text"]
					if id.to_lower().contains(needle) or text.to_lower().contains(needle):
						found.append(_match_field(chapter, conversation, node, id, text, needle))
						if found.size() >= limit:
							return found
	return found


func _match_field(chapter: String, conversation: String, node: String, choice: String,
		text: String, needle: String) -> Dictionary:
	var plain := text.replace("\n", " ")
	var offset := maxi(0, plain.to_lower().find(needle) - 8)
	var excerpt := plain.substr(offset, 34)
	return {"chapter": chapter, "conversation": conversation, "node": node, "choice": choice,
		"sample": ("…" if offset > 0 else "") + excerpt}


func choice_targets(chapter: String, conversation: String, hub: String) -> Array:
	var graph := graph_for(chapter)
	var entry := graph.get_conversation(StringName(conversation)) if graph != null else null
	if entry == null:
		return []
	var followups: Patch.Followups = _followups.get(chapter)
	var targets := []
	for row: Dictionary in nodes_for(chapter, conversation):
		if followups != null and followups.owns_line(conversation, row["id"]):
			continue
		var reachable := DialogueGraph.reachable_nodes(entry, StringName(row["id"]))
		if not reachable.has(StringName(hub)):
			targets.append(row)
	return targets


func change_count() -> int:
	var total := 0
	for entry: Dictionary in _entries.values():
		total += entry["ops"].size()
	return total


func has_exportable_changes() -> bool:
	return not _entries.is_empty() or Patch.valid_envelope(_unapplied)


func can_undo() -> bool:
	return blocked.is_empty() and not _undo.is_empty()


func _text_slot(chapter: String, conversation: String, node: String, choice: String) -> Dictionary:
	var slot := Patch.find_record(nodes_for(chapter, conversation), node)
	return slot if choice.is_empty() else Patch.find_record(Patch.choices_at(slot), choice)


func first_followup(chapter: String, conversation: String, hub: String, choice: String) -> String:
	var followups: Patch.Followups = _followups.get(chapter)
	return followups.first(conversation, hub, choice) if followups != null else ""


func is_placeholder(chapter: String, conversation: String, node: String) -> bool:
	var followups: Patch.Followups = _followups.get(chapter)
	return followups != null and followups.is_placeholder(conversation, node)


func placeholder_count() -> int:
	var count := 0
	for followups: Patch.Followups in _followups.values():
		count += followups.placeholders.size()
	return count


func editable_text(chapter: String, conversation: String, node: String, choice: String) -> String:
	if choice.is_empty() and is_placeholder(chapter, conversation, node):
		return "" # The prompt/note is never prefilled as if it were an authored line.
	return _text_slot(chapter, conversation, node, choice).get("text", "")


func set_text(chapter: String, conversation: String, node: String, choice: String, value: String) -> bool:
	var slot := _text_slot(chapter, conversation, node, choice)
	if slot.is_empty():
		error = "找不到这个字段。"
		return false
	var before: String = slot.get("text", "")
	if choice.is_empty() and is_placeholder(chapter, conversation, node) and value.begins_with(Patch.PLACEHOLDER):
		error = "请填写正文，不要保留占位标记。"
		return false
	if before == value:
		return true
	if not Patch.authored_text(value):
		error = "请输入 1–8000 字符，不能只留空白。"
		return false
	return _commit(chapter, {"kind": "text", "conversation": conversation, "node": node,
		"choice": choice, "before": before, "text": value})


func insert_line(chapter: String, conversation: String, anchor: String, speaker: String, text: String) -> String:
	var nodes := nodes_for(chapter, conversation)
	var target: Variant = Patch.continuation(nodes, Patch.find_record(nodes, anchor))
	var id := Patch.new_id()
	var reply := {"id": id, "speaker": speaker, "text": text, "next": target}
	var ok := _commit(chapter, {"kind": "insert", "conversation": conversation, "node": anchor,
		"before": target, "reply": reply})
	return id if ok else ""


func add_choice(chapter: String, conversation: String, anchor: String, text: String,
			target: Variant, reply_speaker: String = "", reply_text: String = "") -> String:
	var id := Patch.new_id()
	var reply: Variant = null
	if not reply_speaker.is_empty():
		reply = {"id": Patch.new_id(), "speaker": reply_speaker, "text": reply_text, "next": target}
		target = reply["id"]
	var node := Patch.find_record(nodes_for(chapter, conversation), anchor)
	var ok := _commit(chapter, {"kind": "choice", "conversation": conversation, "node": anchor,
		"before": Patch.choice_signature(node), "id": id, "text": text, "next": target, "reply": reply})
	return id if ok else ""


func append_followup(chapter: String, conversation: String, node: String, choice: String, lines: Array) -> String:
	if lines.is_empty() or lines.size() > Patch.MAX_ROUND_LINES:
		error = "每轮后续需要 1–12 句。"
		return ""
	var followups: Patch.Followups = _followups.get(chapter)
	var tail := followups.tail(conversation, node, choice) if followups != null else ""
	var nodes := nodes_for(chapter, conversation)
	var option := Patch.find_record(Patch.choices_at(Patch.find_record(nodes, node)), choice)
	var edge := Patch.followup_edge(nodes, option, tail)
	if option.is_empty() or not edge.has("next"):
		error = "先选中一个已有选项。"
		return ""
	var draft_lines: Array[Dictionary] = []
	for line: Variant in lines:
		if not line is Dictionary:
			error = "后续对白格式无效。"
			return ""
		draft_lines.append({"id": Patch.new_id(), "speaker": line.get("speaker"),
			"text": line.get("text"), "placeholder": line.get("placeholder", false)})
	var applied := _commit(chapter, {"kind": "followup", "conversation": conversation,
		"node": node, "choice": choice, "guard": Patch.option_signature(option),
		"after": tail, "before": edge["next"], "lines": draft_lines})
	return draft_lines[0]["id"] if applied else ""


## Confirm a completed form against the same guard/validation path as imported drafts.
## Keep a follow-up's option selected so another round can be appended immediately.
func apply_structure(mode: String, chapter: String, conversation: String, node: String,
		choice: String, values: Dictionary) -> Dictionary:
	match mode:
		"insert":
			var id := insert_line(chapter, conversation, node, values["speaker"], values["text"])
			return {} if id.is_empty() else {"node": id, "choice": ""}
		"choice":
			var id := ""
			var target: Variant = values["target"]
			if values["new_reply"]:
				id = add_choice(chapter, conversation, node, values["text"],
					null if target == "" else target, values["speaker"], values["reply"])
			else:
				id = add_choice(chapter, conversation, node, values["text"], target)
			return {} if id.is_empty() else {"node": node, "choice": id}
		"followup":
			var first := append_followup(chapter, conversation, node, choice, values["lines"])
			return {} if first.is_empty() else {"node": node, "choice": choice}
	return {}


## Only the isolated author process asks for these overrides. Unchanged chapters still
## come from DialogueLibrary, as do the other game's lookups of shipped content.
func graph_override(chapter: String, locale: String) -> DialogueGraph:
	if not _live or not blocked.is_empty() or not _data.has(chapter):
		return null
	if locale == Patch.LOCALE:
		return _graphs[chapter]
	if locale == NativeChapter.ENGLISH:
		return _mirrors[chapter]["graph"]
	return null


func save_live_buffer(values: Dictionary) -> bool:
	if not _live or not blocked.is_empty() or not _save_state(_entries, values):
		return false
	live_buffer = values.duplicate(true)
	return true


func live_body_anchor(address: Dictionary) -> String:
	return _text_slot(address["chapter"], address["conversation"], address["node"], "").get("text", "")


func apply_live_text(address: Dictionary, before: String, text: String) -> bool:
	var slot := _text_slot(address["chapter"], address["conversation"], address["node"], "")
	if slot.is_empty() or slot.get("text") != before:
		error = "当前原文已改变；保留输入，没有覆盖。"
		return false
	return _commit(address["chapter"], {"kind": "text", "conversation": address["conversation"],
		"node": address["node"], "choice": "", "before": before, "text": text}, true)


func round_anchor(address: Dictionary) -> Dictionary:
	var chapter: String = address["chapter"]
	var conversation: String = address["conversation"]
	var node: String = address["node"]
	var choice: String = address["choice"]
	var option := _text_slot(chapter, conversation, node, choice)
	var followups: Patch.Followups = _followups.get(chapter)
	var tail := followups.tail(conversation, node, choice) if followups != null else ""
	var edge := Patch.followup_edge(nodes_for(chapter, conversation), option, tail)
	if choice.is_empty() or option.is_empty() or not edge.get("next") is String or edge["next"].is_empty():
		return {}
	return {"guard": Patch.option_signature(option), "after": tail, "before": edge["next"]}


func apply_live_round(address: Dictionary, anchor: Dictionary, values: Dictionary) -> bool:
	if anchor.is_empty() or anchor != round_anchor(address):
		error = "选项的去向已改变，或已接入带选项的下一轮。没有覆盖连接。"
		return false
	var lines: Array[Dictionary] = []
	var choices: Array[Dictionary] = []
	if not values.get("lines") is Array or not values.get("choices") is Array:
		error = "后续表单格式无效。"
		return false
	for row: Variant in values["lines"]:
		if not row is Dictionary:
			error = "后续对白格式无效。"
			return false
		lines.append({"id": Patch.new_id(), "speaker": row.get("speaker"), "text": row.get("text"), "placeholder": false})
	for row: Variant in values["choices"]:
		if not row is Dictionary:
			error = "新选项格式无效。"
			return false
		choices.append({"id": Patch.new_id(), "text": row.get("text"), "next": row.get("next")})
	var operation := anchor.merged({"kind": "round", "conversation": address["conversation"],
		"node": address["node"], "choice": address["choice"], "lines": lines, "choices": choices})
	return _commit(address["chapter"], operation, true)


func export_chapter(chapter: String) -> Dictionary:
	if not _live or not blocked.is_empty() or not _data.has(chapter) or _data[chapter] == _base[chapter]:
		return {"error": "这一章还没有可导出的已应用修改。"}
	var followups: Patch.Followups = _followups.get(chapter)
	if followups != null and not followups.placeholders.is_empty():
		return {"error": "这一章仍有占位对白，请先补写。可从草稿抽屉导出原草稿。"}
	return NativeChapter.files(chapter, _data[chapter], _mirrors[chapter], _sources[chapter])


func _commit(chapter: String, operation: Dictionary, persist_live: bool = false) -> bool:
	error = ""
	if not blocked.is_empty() or not _base.has(chapter) or (persist_live and not _live):
		error = "修改目标不可用。"
		return false
	var all := _entries.duplicate(true)
	var entry: Dictionary = all.get(chapter, {"base": Patch.digest(_base[chapter]), "ops": []})
	entry.erase("result")
	var ops: Array = entry["ops"]
	var previous: Dictionary = ops.back() if not ops.is_empty() else {}
	if operation["kind"] == "text" and previous.get("kind") == "text" \
			and previous["conversation"] == operation["conversation"] and previous["node"] == operation["node"] \
			and previous["choice"] == operation["choice"]:
		operation["before"] = previous["before"]
		ops.pop_back()
	if operation["kind"] != "text" or operation["before"] != operation["text"]:
		ops.append(operation)
	if ops.is_empty():
		all.erase(chapter)
	else:
		all[chapter] = entry
	if JSON.stringify(all).to_utf8_buffer().size() > LOG_LIMIT:
		error = "草稿已到容量上限，请先导出。"
		return false
	var before := _entries
	if not _install(all, persist_live):
		return false
	_remember_undo(before)
	return true


func _remember_undo(before: Dictionary) -> void:
	_undo.push_back(before)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _install(entries: Dictionary, persist_live: bool = false) -> bool:
	var parsed := {}
	var installed := entries.duplicate(true)
	for chapter: Variant in installed:
		if not _base.has(chapter) or not installed[chapter] is Dictionary:
			error = "草稿引用了未知章节。"
			return false
		var entry: Dictionary = installed[chapter]
		var result := Patch.apply_chapter(_base[chapter], chapter, entry)
		if result.has("error"):
			error = result["error"]
			return false
		var followups: Patch.Followups = result.get("followups")
		if followups == null or followups.placeholders.is_empty():
			entry["result"] = Patch.digest(result["data"])
		else:
			entry.erase("result") # An unfinished chapter cannot be treated as published.
		if _live:
			var pair := NativeChapter.compile_pair(result["data"], result["graph"], _sources[chapter])
			if pair.has("error"):
				error = pair["error"]
				return false
			result["mirror"] = pair
		parsed[chapter] = result
	# A failed write cannot publish even a valid new edge. Keep the last accepted
	# graph and the un-applied input intact; the author can try again.
	if persist_live and not _save_state(installed, {}):
		error = save_problem()
		return false
	for chapter: String in _data.keys():
		if not parsed.has(chapter):
			_graphs[chapter] = _original_graphs[chapter]
	_data.clear()
	_followups.clear()
	_mirrors.clear()
	for chapter: String in parsed:
		_data[chapter] = parsed[chapter]["data"]
		_graphs[chapter] = parsed[chapter]["graph"]
		if _live:
			_mirrors[chapter] = parsed[chapter]["mirror"]
		if parsed[chapter].has("followups"):
			_followups[chapter] = parsed[chapter]["followups"]
	_entries = installed
	if persist_live:
		live_buffer = {}
	return true


func undo() -> bool:
	if not can_undo() or not _install(_undo.back()):
		return false
	_undo.pop_back()
	return true


func reset() -> bool:
	if blocked.is_empty() and not _entries.is_empty():
		var before := _entries
		if _install({}):
			_remember_undo(before)
			buffer = {}
			live_buffer = {}
			return true
	return false


func portable_draft() -> Dictionary:
	if not _unapplied.is_empty():
		return _unapplied
	return _envelope(_entries)


func _envelope(entries: Dictionary) -> Dictionary:
	return {"format": Patch.FORMAT, "version": Patch.VERSION, "locale": Patch.LOCALE,
		"base_commit": ProjectSettings.get_setting("authoring/base_commit", "local"), "chapters": entries}


func save_editor_state() -> bool:
	return blocked.is_empty() and _save_state(_entries, live_buffer)


func _save_state(entries: Dictionary, input: Dictionary) -> bool:
	return _journal.save({"draft": _envelope(entries), "buffer": buffer, "live_buffer": input, "exported": exported_digest})


func recovery_notice() -> String:
	return _journal.recovery_notice


func has_save_error() -> bool:
	return _journal.last_error != OK


func save_problem() -> String:
	if _journal.last_error == ERR_INVALID_PARAMETER:
		return "草稿超出本机保存上限。"
	return "草稿未写入本机（错误 %d）。" % _journal.last_error


func export_json() -> String:
	return JSON.stringify(portable_draft(), "", true, true) + "\n"


func is_unexported() -> bool:
	return has_exportable_changes() and export_json().sha256_text() != exported_digest
