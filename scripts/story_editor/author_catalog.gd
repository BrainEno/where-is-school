extends RefCounted
## Stable addresses for the drawer's pickers and search. Looking at results never
## changes the selected field; the overlay commits a jump only after flushing it.

const Form := preload("res://scripts/story_editor/author_form.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const SEARCH_LIMIT := 60

var chapter := ""
var conversation := ""
var node := ""
var choice := ""
var store: Store
var live := {}
var query := ""
var _form: Form
var _matches: Array[Dictionary] = []


func _init(form: Form) -> void:
	_form = form


func address() -> Dictionary:
	return {"chapter": chapter, "conversation": conversation, "node": node, "choice": choice}


func select_address(value: Dictionary) -> void:
	chapter = String(value.get("chapter", ""))
	conversation = String(value.get("conversation", ""))
	node = String(value.get("node", ""))
	choice = String(value.get("choice", ""))


func locate_live(controller: DialogueController) -> void:
	live = {}
	if controller.get_mode() != DialogueController.Mode.CONVERSATION:
		return
	var line := controller.get_current_line()
	var conversation_id := String(line.get("conversation_id", ""))
	var chapter_id := store.chapter_for(conversation_id)
	var node_id := String(line.get("node_id", ""))
	if not Patch.find_record(store.nodes_for(chapter_id, conversation_id), node_id).is_empty():
		live = {"chapter": chapter_id, "conversation": conversation_id, "node": node_id, "choice": ""}


func pick(field: String, value: String) -> void:
	match field:
		"chapter":
			chapter = value
			conversation = ""
			node = ""
			choice = ""
		"conversation":
			conversation = value
			node = ""
			choice = ""
		"node":
			node = value
			choice = ""
		"field": choice = value


func sync() -> void:
	var chapters := store.chapter_ids()
	if chapter not in chapters:
		chapter = chapters[0] if not chapters.is_empty() else ""
	var conversations := store.conversation_ids(chapter)
	if conversation not in conversations:
		conversation = conversations[0] if not conversations.is_empty() else ""
	var rows := nodes()
	if selected_node().is_empty():
		node = rows[0]["id"] if not rows.is_empty() else ""
	if not choice.is_empty() and Patch.find_record(Patch.choices_at(selected_node()), choice).is_empty():
		choice = ""
	_form.replace_options("chapter", Form.id_options(chapters), chapter)
	_form.replace_options("conversation", Form.id_options(conversations), conversation)
	var options := []
	for index in rows.size():
		var row: Dictionary = rows[index]
		var label := "%d. %s · %s" % [index + 1, row["speaker"], snippet(row.get("text", ""))]
		options.append({"id": row["id"], "label": label, "hint": row["id"]})
	_form.replace_options("node", options, node)
	var fields := [{"id": "", "label": "正文"}]
	for option: Dictionary in Patch.choices_at(selected_node()):
		fields.append({"id": option["id"], "label": "选项 · " + snippet(option["text"]), "hint": option["id"]})
	_form.replace_options("field", fields, choice)
	if _form.is_search_open():
		search(query)


func nodes() -> Array:
	return store.nodes_for(chapter, conversation)


func selected_node() -> Dictionary:
	return Patch.find_record(nodes(), node)


func stored_text() -> String:
	return store.editable_text(chapter, conversation, node, choice)


func search(text: String) -> void:
	query = text.replace("\n", " ").replace("\r", " ").left(Form.SEARCH_LENGTH)
	_form.set_query(query)
	_matches = store.find_fields(query, SEARCH_LIMIT + 1)
	var caption := "输入关键词查找" if query.strip_edges().is_empty() else "没有匹配的台词或选项"
	if _matches.size() > SEARCH_LIMIT:
		_matches.pop_back()
		caption = "前 %d 条结果 · 可缩小范围" % SEARCH_LIMIT
	elif not _matches.is_empty():
		caption = "%d 条结果 · 请选择" % _matches.size()
	var entries := [{"id": "", "label": caption}]
	for index in _matches.size():
		var result := _matches[index]
		var path := "%s / %s" % [result["chapter"], result["conversation"]]
		var field := "正文" if result["choice"].is_empty() else "选项"
		entries.append({"id": str(index), "label": "%s · %s · %s" % [field, result["sample"], path],
			"hint": "%s / %s %s" % [path, result["node"], result["choice"]]})
	_form.replace_options("match", entries, "")


func search_address(id: String) -> Dictionary:
	var index := id.to_int()
	return _matches[index] if id.is_valid_int() and index >= 0 and index < _matches.size() else {}


static func snippet(text: String) -> String:
	return text.replace("\n", " ").left(34)
