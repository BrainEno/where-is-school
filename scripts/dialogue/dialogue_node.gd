extends RefCounted
class_name DialogueNode
## One step of a conversation graph: a run of lines, then either choices or a
## single automatic transition.

var id: StringName = &""
var lines: Array[DialogueLine] = []
var choices: Array[DialogueChoice] = []
## Automatic continuation after [member lines] when there are no choices.
var next_id: StringName = &""
## Flags written when this node is entered.
var on_enter_flags: Dictionary = {}
## Ledger records appended when this node is entered.
var on_enter_records: Array[StringName] = []
## Optional presentation cue (room tone changes, camera emphasis) handled by the
## flow owner; the session itself never touches the scene.
var enter_cue: StringName = &""
## When true the node is part of a subjective sequence.
var imagined: bool = false


static func create(node_id: StringName) -> DialogueNode:
	var node := DialogueNode.new()
	node.id = node_id
	return node


func with_line(line: DialogueLine) -> DialogueNode:
	lines.append(line)
	return self


func with_speaker_line(line_speaker: StringName, line_text: String) -> DialogueNode:
	lines.append(DialogueLine.create(line_speaker, line_text))
	return self


func with_imagined_by(line_speaker: StringName, line_text: String) -> DialogueNode:
	imagined = true
	lines.append(DialogueLine.imagined_by(line_speaker, line_text))
	return self


func with_aside(line_text: String) -> DialogueNode:
	lines.append(DialogueLine.aside(line_text))
	return self


func with_choice(choice: DialogueChoice) -> DialogueNode:
	choices.append(choice)
	return self


func with_next(node_id: StringName) -> DialogueNode:
	next_id = node_id
	return self


func with_flag(flag: StringName, value: Variant) -> DialogueNode:
	on_enter_flags[flag] = value
	return self


func with_record(record_id: StringName) -> DialogueNode:
	if not on_enter_records.has(record_id):
		on_enter_records.append(record_id)
	return self


func with_cue(cue: StringName) -> DialogueNode:
	enter_cue = cue
	return self


func with_imagined() -> DialogueNode:
	imagined = true
	return self


func has_choices() -> bool:
	return not choices.is_empty()
