class_name CheckResult
extends RefCounted
## Result of a single dice check.
##
## Returned by CheckEngine.roll() for both visible and hidden checks.
## Success/failure is the only branching needed by content; margin and
## roll are kept for presentation and for tests that assert deterministic
## behaviour.

## Stable id of the check (from the content, e.g. "playground_shed_search").
## Empty for ad-hoc checks made only by tests.
var check_id: StringName = &""
## Ability that was used, e.g. "keen_eye".
var ability_id: StringName = &""
## Was the roll considered visible to the player (UI shows dice)?
var visible: bool = false
## Raw dice roll (1-20).
var roll: int = 0
## Ability contribution (level/value).
var ability_value: int = 0
## Situational modifier (from content or passive state).
var modifier: int = 0
## Sum: roll + ability + modifier.
var total: int = 0
## Difficulty the total is compared against.
var difficulty: int = 0
## Whether total >= difficulty.
var success: bool = false
## Total - difficulty (positive on success, negative on failure).
var margin: int = 0
## Was this already attempted before (spam guard)?
var already_attempted: bool = false

func _init(
	p_check_id: StringName = &"",
	p_ability: StringName = &"",
	p_visible: bool = false,
	p_roll: int = 0,
	p_ability_value: int = 0,
	p_modifier: int = 0,
	p_total: int = 0,
	p_difficulty: int = 0,
	p_success: bool = false,
	p_margin: int = 0,
	p_already: bool = false
) -> void:
	check_id = p_check_id
	ability_id = p_ability
	visible = p_visible
	roll = p_roll
	ability_value = p_ability_value
	modifier = p_modifier
	total = p_total
	difficulty = p_difficulty
	success = p_success
	margin = p_margin
	already_attempted = p_already


func to_dict() -> Dictionary:
	return {
		"check_id": String(check_id),
		"ability_id": String(ability_id),
		"visible": visible,
		"roll": roll,
		"ability_value": ability_value,
		"modifier": modifier,
		"total": total,
		"difficulty": difficulty,
		"success": success,
		"margin": margin,
		"already_attempted": already_attempted,
	}


func describe() -> String:
	return "Check[%s:%s] d20=%d + ability %d + mod %d = %d vs %d -> %s (margin %d)%s" % [
		check_id, ability_id, roll, ability_value, modifier, total, difficulty,
		"SUCCESS" if success else "FAIL", margin,
		" (repeat)" if already_attempted else ""
	]
