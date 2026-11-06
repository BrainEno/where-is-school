extends RefCounted
class_name DialogueSession
## Plays a [DialogueScript] one step at a time and reports everything through
## signals. It owns no UI and never touches world nodes, so it can be driven
## headlessly by tests in a few lines.
##
## Effects are *emitted*, not applied. Whoever owns story state — in this
## project, PrologueFlow — decides what a flag or a ledger record means.

signal line_presented(line: DialogueLine, history: Array)
signal choices_presented(choices: Array[DialogueChoice])
signal flags_requested(flags: Dictionary)
signal records_requested(record_ids: Array[StringName])
signal cue_requested(cue: StringName)
signal session_finished(script_id: StringName)
signal choice_selected(choice: DialogueChoice)

var _script: DialogueScript
var _node: DialogueNode
var _line_index: int = 0
var _history: Array = []
var _awaiting_choice: bool = false
var _finished: bool = false
var _flag_reader: Callable
var _imagination_depth: int = 0
var _imagined_nodes_entered: int = 0


func start(script: DialogueScript, flag_reader: Callable = Callable()) -> bool:
	if script == null:
		push_error("DialogueSession.start received a null script.")
		return false
	var problems: PackedStringArray = script.validate()
	if not problems.is_empty():
		for problem in problems:
			push_error("Dialogue content error: %s" % problem)
		return false

	_script = script
	_flag_reader = flag_reader
	_node = null
	_line_index = 0
	_history.clear()
	_awaiting_choice = false
	_finished = false
	_imagination_depth = 0
	_imagined_nodes_entered = 0
	_enter_node(script.first_node())
	return true


func script_id() -> StringName:
	return _script.id if _script != null else &""


func current_node_id() -> StringName:
	return _node.id if _node != null else &""


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func is_finished() -> bool:
	return _finished


func is_imagining() -> bool:
	return _imagination_depth > 0


## True while the current line belongs to a rehearsal/expectation.
func current_line_is_imagined() -> bool:
	if _node == null:
		return false
	return _node.imagined


func history() -> Array:
	return _history.duplicate()


func available_choices() -> Array[DialogueChoice]:
	if not _awaiting_choice or _node == null:
		return []
	var result: Array[DialogueChoice] = []
	for choice in _node.choices:
		if _flag_reader.is_valid():
			if choice.is_available(_flag_reader):
				result.append(choice)
		else:
			result.append(choice)
	return result


## Advances to the next line, presents choices, or ends the conversation.
## Safe to call when a choice is pending — it does nothing then.
func advance() -> void:
	if _finished or _awaiting_choice or _node == null:
		return
	if _line_index + 1 < _node.lines.size():
		_line_index += 1
		_present_current_line()
		return
	if _node.has_choices():
		_show_choices()
		return
	if String(_node.next_id).is_empty():
		_finish()
		return
	_enter_node(_script.get_node(_node.next_id))


func choose(index: int) -> void:
	if not _awaiting_choice or _node == null:
		push_error("DialogueSession.choose called with no pending choices.")
		return
	var options: Array[DialogueChoice] = available_choices()
	if index < 0 or index >= options.size():
		push_error("DialogueSession.choose index %d out of range (%d options)." % [index, options.size()])
		return

	var choice: DialogueChoice = options[index]
	_awaiting_choice = false
	choice_selected.emit(choice)

	if not choice.flags.is_empty():
		flags_requested.emit(choice.flags.duplicate())
	if not choice.records.is_empty():
		records_requested.emit(choice.records.duplicate())

	# The reply lines are appended to history under the same speaker identity as
	# authored lines, so the backlog stays a faithful transcript.
	for line in choice.reply_lines:
		_history.append(_history_entry(line))
		line_presented.emit(line, _history.duplicate())

	if String(choice.goto).is_empty():
		_finish()
		return
	var next_node: DialogueNode = _script.get_node(choice.goto)
	if next_node == null:
		push_error(
			"DialogueSession: choice '%s' jumped to missing node '%s'."
			% [String(choice.id), String(choice.goto)]
		)
		_finish()
		return
	_enter_node(next_node)


## Selects a choice by its stable id. Used by tests and by save/restore tooling.
func choose_by_id(choice_id: StringName) -> bool:
	var options: Array[DialogueChoice] = available_choices()
	for index in options.size():
		if options[index].id == choice_id:
			choose(index)
			return true
	push_warning("DialogueSession.choose_by_id: no available choice '%s'." % String(choice_id))
	return false


func _enter_node(node: DialogueNode) -> void:
	if node == null:
		push_error("DialogueSession entered a null node.")
		_finish()
		return
	_node = node
	_line_index = 0
	_awaiting_choice = false
	if node.imagined:
		_imagination_depth = 1 + _imagined_nodes_entered
		_imagined_nodes_entered += 1
	if not node.on_enter_flags.is_empty():
		flags_requested.emit(node.on_enter_flags.duplicate())
	if not node.on_enter_records.is_empty():
		records_requested.emit(node.on_enter_records.duplicate())
	if not String(node.enter_cue).is_empty():
		cue_requested.emit(node.enter_cue)
	_present_current_line()


func _present_current_line() -> void:
	if _node == null or _node.lines.is_empty():
		return
	var line: DialogueLine = _node.lines[_line_index]
	_history.append(_history_entry(line))
	line_presented.emit(line, _history.duplicate())


func _show_choices() -> void:
	var options: Array[DialogueChoice] = available_choices_snapshot()
	if options.is_empty():
		_finish()
		return
	_awaiting_choice = true
	choices_presented.emit(options)


func available_choices_snapshot() -> Array[DialogueChoice]:
	var result: Array[DialogueChoice] = []
	for choice in _node.choices:
		if not _flag_reader.is_valid() or choice.is_available(_flag_reader):
			result.append(choice)
	return result


func _history_entry(line: DialogueLine) -> Dictionary:
	return {
		"speaker": line.speaker,
		"name": CharacterDirectory.display_name(line.speaker),
		"text": line.text,
		"imagined": line.imagined or is_imagining(),
	}


func _finish() -> void:
	_finished = true
	_awaiting_choice = false
	session_finished.emit(script_id())
