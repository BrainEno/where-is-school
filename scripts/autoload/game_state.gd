extends Node
## Runtime story flags shared by the active game session.
## Persistence is intentionally handled by a future SaveManager, not this node.

signal story_flag_changed(flag: StringName, previous_value: Variant, new_value: Variant)
signal story_state_replaced

var _story_flags: Dictionary = {}


func has_flag(flag: StringName) -> bool:
	return _story_flags.has(flag)


func get_flag(flag: StringName, default_value: Variant = null) -> Variant:
	return _story_flags.get(flag, default_value)


func count_flags_with_prefix(prefix: String) -> int:
	var count: int = 0
	for key in _story_flags:
		if String(key).begins_with(prefix):
			count += 1
	return count


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
