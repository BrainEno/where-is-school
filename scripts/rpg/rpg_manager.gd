extends Node
## Central facade for inner abilities + checks.
##
## Autoload `Rpg` (optional) or scene-owned node. It owns the AbilityRegistry
## and a CheckEngine. Tests can create it directly without autoload.
##
## The manager is deliberately small: it resolves ability values, runs visible
## and hidden checks through the same engine, and emits signals for UI.

signal check_completed(result: CheckResult)
signal passive_triggered(trigger_id: StringName, ability_id: StringName, text_key: String)

var _abilities: AbilityRegistry = null
var _engine: CheckEngine = null
var _passive_triggers: Array[PassiveTrigger] = []

var _game_state: Node = null
var _narrative: Node = null


func _ready() -> void:
	_game_state = get_node_or_null("/root/GameState")
	_narrative = get_node_or_null("/root/NarrativeState")
	# Also try local tree parent if autoload not present yet (tests)
	if _game_state == null and get_parent() != null:
		_game_state = get_parent().get_node_or_null("GameState")
	abilities_load()
	_init_passive_triggers()


func abilities_load() -> void:
	_abilities = AbilityRegistry.load_all()
	if not _abilities.is_valid():
		for e in _abilities.errors:
			push_error("RpgManager: %s" % e)
	_engine = CheckEngine.new(null, _game_state)


func get_registry() -> AbilityRegistry:
	return _abilities


func get_engine() -> CheckEngine:
	return _engine


func get_ability(ability_id: StringName) -> InnerAbility:
	if _abilities == null:
		return null
	return _abilities.get_ability(ability_id)


## Run a visible check (player chose it).
func do_visible_check(check_id: StringName, ability_id: StringName, difficulty: int, modifier: int = 0, allow_reroll: bool = false) -> CheckResult:
	var ability := get_ability(ability_id)
	var val := ability.get_value() if ability != null else 0
	var result := _engine.roll(check_id, ability_id, val, difficulty, modifier, true, allow_reroll)
	check_completed.emit(result)
	return result


## Run a hidden check (passive ability).
func do_hidden_check(check_id: StringName, ability_id: StringName, difficulty: int, modifier: int = 0, allow_reroll: bool = false) -> CheckResult:
	var ability := get_ability(ability_id)
	var val := ability.get_value() if ability != null else 0
	var result := _engine.roll(check_id, ability_id, val, difficulty, modifier, false, allow_reroll)
	check_completed.emit(result)
	return result


## Install custom engine for tests.
func set_engine(engine: CheckEngine) -> void:
	_engine = engine


func set_abilities(registry: AbilityRegistry) -> void:
	_abilities = registry


## Called when player enters a location or inspects an object.
## Evaluates passive triggers and returns lines to present.
func evaluate_passives(context: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if _abilities == null or _game_state == null:
		return lines
	var loc: String = String(context.get("location_id", ""))
	var insp: String = String(context.get("inspection_id", ""))
	for trig in _passive_triggers:
		if not trig.location_ids.is_empty() and not trig.location_ids.has(StringName(loc)):
			continue
		if not trig.inspection_ids.is_empty() and not trig.inspection_ids.has(StringName(insp)):
			continue
		if not trig.conditions_met(_game_state):
			continue
		if not trig.can_fire(_game_state):
			continue
		var result: CheckResult = null
		if trig.use_hidden_check:
			result = do_hidden_check(StringName("passive:%s" % trig.trigger_id), trig.ability_id, trig.check_difficulty, trig.check_modifier)
			var key := trig.failure_line_key if not result.success else trig.success_line_key
			if not key.is_empty():
				lines.append(key)
		else:
			if not trig.direct_line_key.is_empty():
				lines.append(trig.direct_line_key)
		trig.mark_fired(_game_state)
		passive_triggered.emit(trig.trigger_id, trig.ability_id, lines[-1] if not lines.is_empty() else "")
	return lines


func _init_passive_triggers() -> void:
	# Built-in passive rules for the playground slice.
	# Keep small: 3 triggers covering the 3 anchors.
	var t1 := PassiveTrigger.new()
	t1.trigger_id = &"playground_shed_noticed"
	t1.ability_id = &"keen_eye"
	t1.location_ids = [&"playground"]
	t1.frequency = PassiveTrigger.Frequency.ONCE_PER_SESSION
	t1.direct_line_key = "passive.keen_eye.hook"
	_passive_triggers.append(t1)

	var t2 := PassiveTrigger.new()
	t2.trigger_id = &"playground_wall_memory"
	t2.ability_id = &"recollection"
	t2.location_ids = [&"playground"]
	t2.use_hidden_check = true
	t2.check_difficulty = 11
	t2.success_line_key = "passive.recollection.hook"
	t2.failure_line_key = "passive.steadiness.hook"
	_passive_triggers.append(t2)

	var t3 := PassiveTrigger.new()
	t3.trigger_id = &"playground_equipment_feeling"
	t3.ability_id = &"gut_feeling"
	t3.location_ids = [&"playground"]
	t3.use_hidden_check = true
	t3.check_difficulty = 12
	t3.success_line_key = "passive.gut_feeling.hook"
	t3.failure_line_key = "passive.steadiness.hook"
	_passive_triggers.append(t3)


## For testing: clear all passive fired flags.
func reset_passives() -> void:
	if _game_state == null:
		return
	for t in _passive_triggers:
		_game_state.set_flag(t.get_flag_key(), null)
