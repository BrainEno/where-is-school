extends Node
class_name DialogueRunner
## Advances validated content and records provenance-tagged narrative data.
## It never moves actors, changes scenes, or records objective observations.

signal conversation_started(id: StringName)
signal line_presented(entry: Dictionary)
signal conversation_finished(id: StringName)
signal history_changed

const CONTENT_PATH: String = "res://data/dialogue/biology_class.json"

var conversations: Dictionary = {}
var history: Array[Dictionary] = []
var active: bool = false
var conversation_id: StringName = &""
var current_node_id: String = ""
var current_node: Dictionary = {}


func _ready() -> void:
	load_content(CONTENT_PATH)


func load_content(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Dialogue content is missing: %s" % path)
		return false
	var json: JSON = JSON.new()
	var result: Error = json.parse(FileAccess.get_file_as_string(path))
	if result != OK:
		push_error("Dialogue content %s, line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return false
	var errors: PackedStringArray = DialogueContent.validate(json.data, path)
	if not errors.is_empty():
		for message: String in errors:
			push_error(message)
		return false
	conversations = json.data["conversations"]
	return true


func start(id: StringName) -> bool:
	if active:
		push_error("Cannot start dialogue '%s': '%s' is still active." % [id, conversation_id])
		return false
	if not conversations.has(String(id)):
		push_error("Dialogue '%s' was not found in %s." % [id, CONTENT_PATH])
		return false
	conversation_id = id
	active = true
	conversation_started.emit(id)
	var conversation: Dictionary = conversations[String(id)]
	_enter(str(conversation["start"]))
	return true


func advance() -> void:
	if not active or current_node.get("kind") == "choice":
		return
	if current_node.has("next"):
		_enter(str(current_node["next"]))
	else:
		_finish()


func choose(index: int) -> void:
	if not active or current_node.get("kind") != "choice":
		return
	var options: Array = current_node["choices"]
	if index < 0 or index >= options.size():
		push_error("Invalid choice index %d in dialogue '%s', node '%s'." % [index, conversation_id, current_node_id])
		return
	var selected: Dictionary = options[index]
	_apply_effects(selected.get("effects", []))
	history.append({"speaker": "YOU", "kind": "choice_answer", "text": selected["text"]})
	history_changed.emit()
	_enter(str(selected["next"]))


func _enter(node_id: String) -> void:
	var conversation: Dictionary = conversations[String(conversation_id)]
	var nodes: Dictionary = conversation["nodes"]
	var hops: int = 0
	while true:
		if not nodes.has(node_id):
			push_error("Dialogue '%s' references missing node '%s'." % [conversation_id, node_id])
			_finish()
			return
		var node: Dictionary = nodes[node_id]
		if node.get("kind") != "branch":
			current_node_id = node_id
			current_node = node
			_apply_effects(node.get("effects", []))
			var entry: Dictionary = node.duplicate(true)
			entry["id"] = node_id
			history.append({"speaker": node["speaker"], "kind": node["kind"], "text": node["text"]})
			history_changed.emit()
			line_presented.emit(entry)
			return
		hops += 1
		if hops > 128:
			push_error("Dialogue '%s' contains a branch-only cycle near '%s'." % [conversation_id, node_id])
			_finish()
			return
		var destination: String = str(node["default"])
		for item: Dictionary in node["cases"]:
			if GameState.get_flag(StringName(item["flag"])) == item["equals"]:
				destination = str(item["next"])
				break
		node_id = destination


func _apply_effects(effects: Array) -> void:
	for effect: Dictionary in effects:
		var id: StringName = StringName(effect["id"])
		var value: Variant = effect["value"]
		match effect["category"]:
			"statement":
				GameState.record_statement(StringName(effect["source"]), id, value)
			"recollection":
				GameState.record_recollection(id, value)
			"imagination":
				GameState.record_imagination(id, value)
			"choice":
				GameState.record_choice(id, value)


func _finish() -> void:
	var finished_id: StringName = conversation_id
	active = false
	conversation_id = &""
	current_node_id = ""
	current_node = {}
	conversation_finished.emit(finished_id)
