class_name DialogueSession
extends RefCounted
## A live traversal of one DialogueScript.
##
## Owns only: which node we are on, which line within it, and the backlog. Every
## state change (flags, ledger, camera, world presentation) is applied by
## PrologueFlow when the session reports it, so this class stays testable without
## a scene tree.

var graph: DialogueScript
var node: DialogueNode
var line_index: int = -1
## Every line the player has already seen, newest last: {speaker_zh, speaker_en,
## text_zh, text_en, kind}
var backlog: Array[Dictionary] = []
var finished: bool = false

var _line_pushed: bool = false


func _init(p_script: DialogueScript) -> void:
	graph = p_script


## Returns the array of validation problems. An invalid script must not be played.
func start() -> Array[String]:
	if graph == null:
		return ["DialogueSession.start received a null script."]
	var problems: Array[String] = graph.validate()
	if not problems.is_empty():
		return problems
	return enter_node(graph.start_id)


func enter_node(node_id: StringName) -> Array[String]:
	var next: DialogueNode = graph.get_node_by_id(node_id)
	if next == null:
		return ["Dialogue node '%s' does not exist in '%s'." % [node_id, graph.id]]
	node = next
	line_index = -1
	_line_pushed = false
	return []


func has_pending_line() -> bool:
	return node != null and line_index + 1 < node.lines.size()


## Advances to the next line of the current node and returns it, or null when the
## node is exhausted.
func advance() -> DialogueLine:
	if node == null:
		return null
	if not has_pending_line():
		return null
	line_index += 1
	var line: DialogueLine = node.lines[line_index]
	_push_backlog(line)
	return line


func current_line() -> DialogueLine:
	if node == null or line_index < 0 or line_index >= node.lines.size():
		return null
	return node.lines[line_index]


func choices() -> Array[DialogueChoice]:
	if node == null:
		return []
	return node.choices


## True when the current node has been fully read and offers choices.
func awaiting_choice() -> bool:
	return node != null and not has_pending_line() and not node.choices.is_empty()


## True when the current node has been fully read and simply continues.
func awaiting_continue() -> bool:
	return node != null and not has_pending_line() and node.choices.is_empty()


func speaker_label_zh(character_id: StringName) -> String:
	var info: Dictionary = graph.character(character_id)
	if info.is_empty():
		return ""
	return str(info.get("name_zh", ""))


func speaker_label_en(character_id: StringName) -> String:
	var info: Dictionary = graph.character(character_id)
	if info.is_empty():
		return ""
	return str(info.get("name_en", ""))


func speaker_note_zh(character_id: StringName) -> String:
	var info: Dictionary = graph.character(character_id)
	return str(info.get("note_zh", "")) if not info.is_empty() else ""


func speaker_note_en(character_id: StringName) -> String:
	var info: Dictionary = graph.character(character_id)
	return str(info.get("note_en", "")) if not info.is_empty() else ""


func speaker_tint(character_id: StringName) -> Color:
	var info: Dictionary = graph.character(character_id)
	if info.is_empty():
		return Color(0.72, 0.72, 0.70)
	return info.get("tint", Color(0.72, 0.72, 0.70))


## Follows a choice's continuation. Does not apply flags or ledger records; the
## caller does that first, using the choice data, then calls this.
func follow(choice: DialogueChoice) -> Array[String]:
	return enter_node(choice.next_id)


func follow_current() -> Array[String]:
	if node == null:
		return ["No active dialogue node."]
	if node.next_id == &"":
		return end()
	return enter_node(node.next_id)


func end() -> Array[String]:
	finished = true
	return []


func _push_backlog(line: DialogueLine) -> void:
	backlog.append({
		"speaker_zh": speaker_label_zh(line.speaker) if line.speaker != &"" else "",
		"speaker_en": speaker_label_en(line.speaker) if line.speaker != &"" else "",
		"text_zh": line.text_zh,
		"text_en": line.text_en,
		"kind": line.kind,
	})
