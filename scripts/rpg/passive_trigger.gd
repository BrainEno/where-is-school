class_name PassiveTrigger
extends RefCounted
## Evaluates whether a passive inner ability should speak.
##
## Passive triggers are lightweight rules evaluated on:
## - entering a location
## - inspecting an object
## - starting/ending a conversation
##
## They do NOT roll for success/failure themselves; they decide whether
## to run a (usually hidden) check or to present a line.

## How often a passive trigger may fire
enum Frequency {
	ALWAYS = 0,       ## Every time condition met
	ONCE_PER_SESSION = 1, ## Once per game session
	ONCE_EVER = 2,    ## Once ever (stored flag)
	COOLDOWN = 3,     ## Once per cooldown window (not yet implemented)
}

var trigger_id: StringName = &""
var ability_id: StringName = &""
var condition_flags: Array[StringName] = []
var not_flags: Array[StringName] = []
var location_ids: Array[StringName] = []
var inspection_ids: Array[StringName] = []
var frequency: Frequency = Frequency.ONCE_PER_SESSION
## If true, run a hidden check; otherwise direct line.
var use_hidden_check: bool = false
var check_difficulty: int = 10
var check_modifier: int = 0
## Lines shown on check success/failure (or direct if no check)
var success_line_key: String = ""
var failure_line_key: String = ""
var direct_line_key: String = ""

## Runtime flag for once tracking
func get_flag_key() -> StringName:
	return StringName("passive_trigger:%s" % String(trigger_id))


## Whether conditions are satisfied given current flags.
func conditions_met(game_state: Node) -> bool:
	if game_state == null:
		return false
	for flag: StringName in condition_flags:
		if not bool(game_state.get_flag(flag, false)):
			return false
	for flag: StringName in not_flags:
		if bool(game_state.get_flag(flag, false)):
			return false
	return true


## Whether frequency allows firing.
func can_fire(game_state: Node) -> bool:
	match frequency:
		Frequency.ALWAYS:
			return true
		Frequency.ONCE_PER_SESSION, Frequency.ONCE_EVER:
			var key := get_flag_key()
			if bool(game_state.get_flag(key, false)):
				return false
			return true
		Frequency.COOLDOWN:
			return true # simplified
	return true


func mark_fired(game_state: Node) -> void:
	if game_state == null:
		return
	if frequency == Frequency.ONCE_PER_SESSION or frequency == Frequency.ONCE_EVER:
		game_state.set_flag(get_flag_key(), true)
