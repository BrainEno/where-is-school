class_name DialogueRunner
extends RefCounted
## UI-agnostic conversation engine.
## Owns the current entry, applies story effects to the injected state node
## (a GameState-compatible object), tracks the backlog, and emits signals.
## The dialogue UI renders what this object exposes; it never decides story state.
##
## Flag namespaces (set by content, enforced here for imagination):
##   observed.*    — directly observed by the player in the scene
##   claim.q.*     — said by Q (unverified statement)
##   claim.n.*     — said by N (unverified statement)
##   recollection.*— the protagonist's uncertain recollection
##   imagination.* — subjective imagination; never objective world state
##   flow.*        — internal sequencing flags (lesson progress etc.)

signal line_shown(entry: DialogueEntry)
signal choices_shown(choices: Array)
signal conversation_finished(conversation_id: StringName)
signal effect_applied(flag: StringName, value: Variant)

const NARRATION_KINDS: PackedStringArray = ["narrator", "inner", "imagination"]

var state: Node = null
var conversation: DialogueConversation = null
var current_entry: DialogueEntry = null
var backlog: Array[Dictionary] = []
var _finished: bool = false


func _init(state_node: Node = null) -> void:
	state = state_node


func start(conversation_resource: DialogueConversation, start_override: StringName = &"") -> bool:
	if conversation_resource == null:
		push_error("DialogueRunner.start: null conversation")
		return false
	var errors := conversation_resource.validate()
	if not errors.is_empty():
		for error in errors:
			push_error("DialogueRunner.start: %s" % error)
		return false
	conversation = conversation_resource
	backlog = []
	_finished = false
	var entry_id: StringName = start_override if str(start_override) != "" else conversation.start_id
	_enter(conversation.get_entry(entry_id))
	return current_entry != null


func advance() -> void:
	if conversation == null or _finished:
		return
	if current_entry == null:
		return
	if not current_entry.choices.is_empty():
		# Choices must be picked explicitly; advancing does nothing.
		return
	if str(current_entry.next_id) == "":
		_finish()
		return
	_enter(conversation.get_entry(current_entry.next_id))


func choose(choice: DialogueChoice) -> void:
	if conversation == null or _finished or current_entry == null:
		return
	if choice == null or not current_entry.choices.has(choice):
		push_error("DialogueRunner.choose: choice not offered by current entry")
		return
	_apply_flag(choice.set_flag, choice.set_value)
	if str(choice.next_id) == "":
		_finish()
		return
	_enter(conversation.get_entry(choice.next_id))


func visible_choices() -> Array[DialogueChoice]:
	var result: Array[DialogueChoice] = []
	if current_entry == null:
		return result
	for choice in current_entry.choices:
		if choice == null:
			continue
		if str(choice.condition_flag) == "":
			result.append(choice)
			continue
		if state != null and _condition_met(choice.condition_flag, choice.condition_equals):
			result.append(choice)
	return result


func is_finished() -> bool:
	return _finished


func _condition_met(flag: StringName, equals_value: Variant) -> bool:
	if state == null:
		return false
	return state.get_flag(flag, null) == equals_value


func _enter(entry: DialogueEntry) -> void:
	if entry == null:
		push_error("DialogueRunner: conversation '%s' jumped to a missing entry" % (conversation.id if conversation else "?"))
		_finish()
		return
	current_entry = entry
	_apply_flag(entry.set_flag, entry.set_value)
	backlog.append({
		"speaker_id": entry.speaker_id,
		"text": entry.text,
		"presentation": conversation.presentation,
	})
	line_shown.emit(entry)
	var offered := visible_choices()
	if not offered.is_empty():
		choices_shown.emit(offered)


func _apply_flag(flag: StringName, value: Variant) -> void:
	if str(flag) == "":
		return
	if conversation != null and conversation.presentation == "imagination":
		if not String(flag).begins_with("imagination."):
			push_error("DialogueRunner: imagination conversation '%s' tried to set non-imagination flag '%s'; blocked" % [conversation.id, flag])
			return
	if state == null:
		push_error("DialogueRunner: no state node; flag '%s' not applied" % flag)
		return
	state.set_flag(flag, value)
	effect_applied.emit(flag, value)


func _finish() -> void:
	_finished = true
	var conversation_id: StringName = conversation.id if conversation else &""
	conversation_finished.emit(conversation_id)
