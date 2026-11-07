class_name InnerCheckEngine
extends RefCounted
## One mechanism for visible choices and hidden reactions. Rolls are cached by
## stable check ID in GameState, so re-entering a scene cannot fish for success.
## A RandomNumberGenerator (or test double with randi_range) can be injected.

const SIDES := 6
const MIN_DIFFICULTY := 2
const MAX_DIFFICULTY := 10

var _state: Node
var _rng: Variant


func _init(state: Node, rng: Variant = null) -> void:
	_state = state
	if rng == null:
		var fresh := RandomNumberGenerator.new()
		fresh.randomize()
		_rng = fresh
	else:
		_rng = rng


static func flag_for(check_id: StringName) -> StringName:
	return StringName("inner:check:%s" % check_id)


## Output: id, ability, rating, difficulty, roll, total, success, visibility,
## reused. Passive callers must not show the numeric fields to the player.
func attempt(check_id: StringName, ability_id: StringName, difficulty: int, visibility: String) -> Dictionary:
	if _state == null or String(check_id).is_empty() or not InnerAbilities.has_ability(ability_id) \
			or difficulty < MIN_DIFFICULTY or difficulty > MAX_DIFFICULTY \
			or visibility not in ["active", "passive"] or _rng == null \
			or not _rng.has_method("randi_range"):
		push_error("InnerCheckEngine: invalid check '%s'." % check_id)
		return {}
	var flag := flag_for(check_id)
	var cached: Variant = _state.get_flag(flag, null)
	if cached is Dictionary:
		var previous: Dictionary = cached
		if String(previous.get("ability", "")) != String(ability_id) \
				or int(previous.get("difficulty", -1)) != difficulty \
				or String(previous.get("visibility", "")) != visibility:
			push_error("InnerCheckEngine: check id '%s' was reused with different rules." % check_id)
			return {}
		var replay := previous.duplicate(true)
		replay["reused"] = true
		return replay
	var rating := InnerAbilities.get_rating(_state, ability_id)
	var roll := int(_rng.randi_range(1, SIDES))
	if roll < 1 or roll > SIDES:
		push_error("InnerCheckEngine: injected RNG returned %d outside 1..%d." % [roll, SIDES])
		return {}
	var total := roll + rating
	var result := {
		"id": String(check_id), "ability": String(ability_id), "rating": rating,
		"difficulty": difficulty, "roll": roll, "total": total,
		"success": total >= difficulty, "visibility": visibility, "reused": false,
	}
	_state.set_flag(flag, result.duplicate(true))
	return result
