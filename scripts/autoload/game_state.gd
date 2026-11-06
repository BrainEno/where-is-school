extends Node
## Runtime story flags shared by the active game session.
## Persistence is intentionally handled by a future SaveManager, not this node.
## Prefixes are evidence boundaries, not interchangeable versions of the truth:
## observed.*, statement.<speaker>.*, recollection.*, imagination.*, choice.*.

signal story_flag_changed(flag: StringName, previous_value: Variant, new_value: Variant)
signal story_state_replaced

var _story_flags: Dictionary = {}


func has_flag(flag: StringName) -> bool:
	return _story_flags.has(flag)


func get_flag(flag: StringName, default_value: Variant = null) -> Variant:
	return _story_flags.get(flag, default_value)


func set_flag(flag: StringName, value: Variant) -> void:
	if String(flag).is_empty():
		push_error("GameState.set_flag received an empty flag identifier.")
		return

	var had_previous: bool = _story_flags.has(flag)
	var previous_value: Variant = _story_flags.get(flag)
	if had_previous and previous_value == value:
		return

	_story_flags[flag] = value
	story_flag_changed.emit(flag, previous_value, value)


func record_observation(id: StringName, value: Variant = true) -> void:
	_record(&"observed", id, value)


func record_statement(speaker: StringName, id: StringName, value: Variant = true) -> void:
	if not String(speaker).is_valid_identifier():
		push_error("GameState.record_statement received an invalid speaker identifier: %s" % speaker)
		return
	_record(StringName("statement.%s" % speaker), id, value)


func record_recollection(id: StringName, value: Variant) -> void:
	_record(&"recollection", id, value)


func record_imagination(id: StringName, value: Variant = true) -> void:
	_record(&"imagination", id, value)


func record_choice(id: StringName, value: Variant) -> void:
	_record(&"choice", id, value)


func _record(category: StringName, id: StringName, value: Variant) -> void:
	if not String(id).is_valid_identifier():
		push_error("GameState received an invalid %s identifier: %s" % [category, id])
		return
	set_flag(StringName("%s.%s" % [category, id]), value)


func get_snapshot() -> Dictionary:
	return _story_flags.duplicate(true)


func replace_snapshot(snapshot: Dictionary) -> void:
	_story_flags = snapshot.duplicate(true)
	story_state_replaced.emit()


func clear() -> void:
	_story_flags.clear()
	story_state_replaced.emit()
