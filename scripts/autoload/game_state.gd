extends Node
## Runtime story flags shared by the active game session.
##
## This node holds them and emits changes; it does not know about files. `Save`
## (autoload `SaveManager`) captures `get_snapshot()` and restores it through
## `replace_snapshot()`; the encoding that keeps an `int` an `int` lives in
## `SaveCodec` (ADR 0005).

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


func get_snapshot() -> Dictionary:
	return _story_flags.duplicate(true)


func replace_snapshot(snapshot: Dictionary) -> void:
	_story_flags = snapshot.duplicate(true)
	story_state_replaced.emit()


func clear() -> void:
	_story_flags.clear()
	story_state_replaced.emit()
