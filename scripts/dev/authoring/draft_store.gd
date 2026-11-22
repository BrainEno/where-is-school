extends RefCounted
## Author workspace: immutable shipped chapters, an operation log, and validated graphs.
## All mutations below build a candidate first. The runtime is never rebound to it.

const Patch := preload("res://scripts/dev/authoring/dialogue_patch.gd")
const Journal := preload("res://scripts/dev/authoring/draft_journal.gd")
const UNDO_LIMIT := 24
# Leave space for escaped journal/bridge envelopes and a separate unfinished field.
const LOG_LIMIT := 640 * 1024

var _base := {}
var _chapters_by_conversation := {}
var _graphs := {}
var _original_graphs := {}
var _entries := {}
var _data := {}
var _undo: Array[Dictionary] = []
var _journal: Journal
var _unapplied := {}
var blocked := ""
var error := ""
var buffer := {}
var exported_digest := ""


func _init(directory: String = Journal.DIRECTORY) -> void:
	_journal = Journal.new(directory)


func load_workspace() -> void:
	for chapter: String in DialogueLibrary.CHAPTERS:
		var data := Patch.read_json(DialogueLibrary.chapter_path(Patch.LOCALE, chapter))
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


func change_count() -> int:
	var total := 0
	for entry: Dictionary in _entries.values():
		total += entry["ops"].size()
	return total


func has_exportable_changes() -> bool:
	return not _entries.is_empty() or Patch.valid_envelope(_unapplied)


func can_undo() -> bool:
	return blocked.is_empty() and not _undo.is_empty()


func set_text(chapter: String, conversation: String, node: String, choice: String, value: String) -> bool:
	var slot := Patch.find_record(nodes_for(chapter, conversation), node)
	if not choice.is_empty():
		slot = Patch.find_record(slot.get("choices", []), choice)
	if slot.is_empty():
		error = "找不到这个字段。"
		return false
	var before: String = slot.get("text", "")
	if before == value:
		return true
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


func _commit(chapter: String, operation: Dictionary) -> bool:
	error = ""
	if not blocked.is_empty() or not _base.has(chapter):
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
	if not _install(all):
		return false
	_undo.push_back(before)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	return true


func _install(entries: Dictionary) -> bool:
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
		entry["result"] = Patch.digest(result["data"])
		parsed[chapter] = result
	for chapter: String in _data.keys():
		if not parsed.has(chapter):
			_graphs[chapter] = _original_graphs[chapter]
	_data.clear()
	for chapter: String in parsed:
		_data[chapter] = parsed[chapter]["data"]
		_graphs[chapter] = parsed[chapter]["graph"]
	_entries = installed
	return true


func undo() -> bool:
	if not can_undo() or not _install(_undo.back()):
		return false
	_undo.pop_back()
	return true


func reset() -> bool:
	if not blocked.is_empty():
		return false
	_undo.clear()
	buffer = {}
	return _install({})


func portable_draft() -> Dictionary:
	if not _unapplied.is_empty():
		return _unapplied
	return {"format": Patch.FORMAT, "version": Patch.VERSION, "locale": Patch.LOCALE,
		"base_commit": ProjectSettings.get_setting("authoring/base_commit", "local"), "chapters": _entries}


func save_editor_state() -> bool:
	if not blocked.is_empty():
		return false
	return _journal.save({"draft": portable_draft(), "buffer": buffer, "exported": exported_digest})


func export_json() -> String:
	return JSON.stringify(portable_draft(), "", true, true) + "\n"


func is_unexported() -> bool:
	return has_exportable_changes() and export_json().sha256_text() != exported_digest
