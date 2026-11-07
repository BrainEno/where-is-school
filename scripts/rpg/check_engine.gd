class_name CheckEngine
extends RefCounted
## Unified dice check engine for visible and hidden checks.
##
## Formula: total = d20(1..20) + ability_value + modifier
##          success = total >= difficulty
##
## - One RNG core for both modes (visible vs hidden differ only in presentation).
## - RNG is injectable: tests provide a seeded RandomNumberGenerator; production
##   may provide the default or a deterministic replay seed.
## - Anti-spam: same check_id cannot be re-rolled freely; result is stored in
##   GameState and reused unless caller forces it.

## d20 bounds
const DIE_MIN := 1
const DIE_MAX := 20

## GameState flag prefix for attempted checks
const CHECK_FLAG_PREFIX := "check:"

var _rng: RandomNumberGenerator = null
var _game_state: Node = null
## Last results by check_id (memory mirror of flags, for quick reuse)
var _last_results: Dictionary = {}

func _init(rng: RandomNumberGenerator = null, game_state: Node = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	if _rng != null and _rng.seed == 0:
		_rng.randomize()
	_game_state = game_state
	if _game_state == null:
		_game_state = _find_autoload("GameState")


static func _find_autoload(node_name: String) -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root: Window = (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(NodePath(node_name))


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


func set_game_state(game_state: Node) -> void:
	_game_state = game_state


## Perform a check. If already_attempted is set in GameState and
## allow_reroll is false, the stored result is returned instead of re-rolling.
func roll(
	check_id: StringName,
	ability_id: StringName,
	ability_value: int,
	difficulty: int,
	modifier: int = 0,
	visible: bool = true,
	allow_reroll: bool = false
) -> CheckResult:
	var already := _has_attempted(check_id)
	if already and not allow_reroll:
		var stored: Variant = _game_state.get_flag(StringName(CHECK_FLAG_PREFIX + String(check_id)), null) if _game_state != null else null
		if stored is Dictionary and stored.has("roll"):
			# Rebuild from stored snapshot
			var prev := _result_from_dict(check_id, stored)
			prev.already_attempted = true
			return prev
		# Fallback: if no snapshot, return a marker failure rather than re-rolling
		var marker := CheckResult.new(check_id, ability_id, visible, 0, ability_value, modifier, 0, difficulty, false, 0, true)
		return marker

	var die := _rng.randi_range(DIE_MIN, DIE_MAX)
	var total := die + ability_value + modifier
	var ok := total >= difficulty
	var margin := total - difficulty
	var result := CheckResult.new(check_id, ability_id, visible, die, ability_value, modifier, total, difficulty, ok, margin, already)
	_record_attempt(check_id, result)
	_last_results[check_id] = result
	return result


## Check from an ability lookup directly.
func roll_for_ability(
	check_id: StringName,
	ability: InnerAbility,
	difficulty: int,
	modifier: int = 0,
	visible: bool = true,
	allow_reroll: bool = false
) -> CheckResult:
	var val := 0
	var abil_id := &""
	if ability != null:
		val = ability.get_value()
		abil_id = ability.ability_id
	return roll(check_id, abil_id, val, difficulty, modifier, visible, allow_reroll)


## Query whether a check was already attempted.
func has_been_attempted(check_id: StringName) -> bool:
	return _has_attempted(check_id)


## Clear stored attempt (for testing).
func clear_attempt(check_id: StringName) -> void:
	_last_results.erase(check_id)
	if _game_state != null:
		# Clear flag by setting to null variant, or removing if we can
		if _game_state.has_method("get_snapshot"):
			# Use set_flag null to indicate cleared, but keep API stable
			_game_state.set_flag(StringName(CHECK_FLAG_PREFIX + String(check_id)), null)


## Force-set RNG seed for deterministic tests.
func reseed(seed_value: int) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


func _has_attempted(check_id: StringName) -> bool:
	if String(check_id).is_empty():
		return false
	if _last_results.has(check_id):
		return true
	if _game_state != null:
		var key := StringName(CHECK_FLAG_PREFIX + String(check_id))
		# get_flag with default null - if stored non-null, it was attempted
		var v: Variant = _game_state.get_flag(key, null)
		if v != null:
			return true
	return false


func _record_attempt(check_id: StringName, result: CheckResult) -> void:
	if _game_state == null or String(check_id).is_empty():
		return
	var key := StringName(CHECK_FLAG_PREFIX + String(check_id))
	_game_state.set_flag(key, result.to_dict())


func _result_from_dict(check_id: StringName, data: Dictionary) -> CheckResult:
	return CheckResult.new(
		StringName(String(data.get("check_id", String(check_id)))),
		StringName(String(data.get("ability_id", ""))),
		bool(data.get("visible", false)),
		int(data.get("roll", 0)),
		int(data.get("ability_value", 0)),
		int(data.get("modifier", 0)),
		int(data.get("total", 0)),
		int(data.get("difficulty", 0)),
		bool(data.get("success", false)),
		int(data.get("margin", 0)),
		true
	)
