class_name PassiveVoices
extends RefCounted
## Contextual, private reactions. Each rule is evaluated only after an explicit
## playground interaction, only after its observation has been read, and at most
## once per session. A two-interaction gap prevents voices crowding the player.
## Rolls use the shared check engine but never appear in the player-facing UI.

const TICK_FLAG: StringName = &"inner:interaction_serial"
const LAST_FLAG: StringName = &"inner:last_passive_serial"
const MIN_GAP := 3
const RULES := {
	&"pg_track": {
		"check_id": &"passive_track", "ability": &"pattern", "difficulty": 6,
		"requires": &"seen:pg_track", "success": &"inner_track_success", "failure": &"inner_track_failure",
	},
	&"pg_hoop": {
		"check_id": &"passive_hoop", "ability": &"resonance", "difficulty": 6,
		"requires": &"seen:pg_hoop", "success": &"inner_hoop_success", "failure": &"inner_hoop_failure",
	},
}

var _state: Node
var _checks: InnerCheckEngine


func _init(state: Node, checks: InnerCheckEngine) -> void:
	_state = state
	_checks = checks


## Returns a dialogue conversation id, or empty when ineligible/cooling down.
func after_interaction(interact_id: StringName) -> StringName:
	if _state == null or _checks == null or not String(interact_id).begins_with("pg_"):
		return &""
	var serial := int(_state.get_flag(TICK_FLAG, 0)) + 1
	_state.set_flag(TICK_FLAG, serial)
	if not RULES.has(interact_id):
		return &""
	var rule: Dictionary = RULES[interact_id]
	if not bool(_state.get_flag(rule["requires"], false)):
		return &""
	if _state.has_flag(InnerCheckEngine.flag_for(rule["check_id"])):
		return &""
	var last := int(_state.get_flag(LAST_FLAG, -MIN_GAP))
	if serial - last < MIN_GAP:
		return &""
	var result := _checks.attempt(rule["check_id"], rule["ability"], int(rule["difficulty"]), "passive")
	if result.is_empty():
		return &""
	_state.set_flag(LAST_FLAG, serial)
	return rule["success"] if bool(result["success"]) else rule["failure"]
