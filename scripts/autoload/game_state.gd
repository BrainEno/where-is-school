extends Node
## Runtime story flags shared by the active game session.
##
## This node holds them and emits changes; it does not know about files. The `Save`
## autoload, whose script is `save_manager.gd`, captures `get_snapshot()` and restores
## it through `replace_snapshot()`; the encoding that keeps an `int` an `int` lives in
## `SaveCodec` (ADR 0005).

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")
const VoiceMigration := preload("res://scripts/rpg/inner_voice_migration.gd")

signal story_flag_changed(flag: StringName, previous_value: Variant, new_value: Variant)
signal story_state_replaced

var _story_flags: Dictionary = {}


func has_flag(flag: StringName) -> bool:
	return _story_flags.has(flag)


func get_flag(flag: StringName, default_value: Variant = null) -> Variant:
	return _story_flags.get(flag, default_value)


func set_flag(flag: StringName, value: Variant) -> void:
	var change := _store_flag(flag, value)
	if change.is_empty():
		return
	story_flag_changed.emit(flag, change["previous"], value)


## Stores a flag without announcing it: the value is read, saved and replaced exactly like
## any other flag, but `story_flag_changed` is not emitted. For a value that a single owner
## changes many times a second and that the owner itself displays (the concussion countdown,
## #348), so the journal and the presence nodes are not woken for every tick. Anything that
## needs to react to a change of such a flag must be the owner, or must read it on its own.
func set_flag_quiet(flag: StringName, value: Variant) -> void:
	_store_flag(flag, value)


## Writes the flag and returns `{"previous": old_value}` when the value changed, or `{}` when
## the flag was refused or already held `value`. Both setters share it, so the refusal and
## the no-change rules stay the same whether a change is announced or not.
func _store_flag(flag: StringName, value: Variant) -> Dictionary:
	if String(flag).is_empty():
		OfflineDiagnostics.note("state.flag_refused")
		push_error("GameState.set_flag received an empty flag identifier.")
		return {}

	var had_previous: bool = _story_flags.has(flag)
	var previous_value: Variant = _story_flags.get(flag)
	if had_previous and previous_value == value:
		return {}

	_story_flags[flag] = value
	return {"previous": previous_value}


func get_snapshot() -> Dictionary:
	return _story_flags.duplicate(true)


func replace_snapshot(snapshot: Dictionary) -> void:
	_story_flags = VoiceMigration.migrate_flags(snapshot)
	story_state_replaced.emit()


func clear() -> void:
	_story_flags.clear()
	story_state_replaced.emit()
