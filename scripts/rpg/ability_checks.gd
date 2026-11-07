class_name AbilityChecks
extends RefCounted
## One 1d12 core for active and passive checks. GameState stores the first result;
## revisiting a target or re-entering a scene never grants another roll.
const DATA_PATH := "res://data/abilities/abilities.json"

var abilities: Dictionary = {}
var passive: Dictionary = {}
var errors: Array[String] = []
var _rng: RandomNumberGenerator
var _state: Node


func _init(state: Node = null, rng: RandomNumberGenerator = null) -> void:
	_state = state
	_rng = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		_rng.randomize()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		errors.append("Missing abilities data: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		errors.append("Invalid abilities JSON: %s" % DATA_PATH)
		return
	abilities = parsed.get("abilities", {})
	passive = parsed.get("passive", {})
	for id: String in abilities:
		var data: Dictionary = abilities[id]
		if int(data.get("level", -1)) < 0:
			errors.append("Ability '%s' needs a nonnegative level." % id)
		for locale: String in L10n.LOCALES:
			for field: String in ["name", "description", "voice"]:
				if String(data.get(field, {}).get(locale, "")).is_empty():
					errors.append("Ability '%s' missing %s.%s." % [id, field, locale])
	for id: String in passive:
		if not _valid_spec(passive[id]):
			errors.append("Passive '%s' needs an ability, difficulty and two conversation ids." % id)


func _valid_spec(spec: Dictionary) -> bool:
	return abilities.has(String(spec.get("ability", ""))) and int(spec.get("difficulty", 0)) >= 1 \
		and not String(spec.get("success", "")).is_empty() and not String(spec.get("failure", "")).is_empty()


func check_spec(spec: Dictionary) -> bool:
	return _valid_spec(spec)


func name_of(id: String, locale: String) -> String:
	return String(abilities.get(id, {}).get("name", {}).get(locale, id))


func level_of(id: String) -> int:
	return int(abilities.get(id, {}).get("level", 0))


func resolve(check_id: StringName, spec: Dictionary, visible: bool) -> Dictionary:
	if _state == null or String(check_id).is_empty() or not _valid_spec(spec):
		push_error("AbilityChecks: invalid check '%s' or missing GameState." % check_id)
		return {}
	var key := StringName("check." + String(check_id))
	var cached: Variant = _state.get_flag(key, null)
	if cached is Dictionary:
		return (cached as Dictionary).duplicate(true)
	var ability := String(spec["ability"])
	var die := _rng.randi_range(1, 12)
	var bonus := level_of(ability)
	var modifier := int(spec.get("modifier", 0))
	var difficulty := int(spec["difficulty"])
	var result := {
		"id": String(check_id), "ability": ability, "die": die,
		"bonus": bonus, "modifier": modifier, "difficulty": difficulty,
		"total": die + bonus + modifier,
		"success": die + bonus + modifier >= difficulty,
		"visible": visible,
	}
	_state.set_flag(key, result.duplicate(true))
	return result


func passive_conversation(interact_id: StringName) -> StringName:
	var key := String(interact_id)
	if not passive.has(key) or _state == null:
		return &""
	var seen := StringName("passive_shown." + key)
	if bool(_state.get_flag(seen, false)):
		return &""
	var spec: Dictionary = passive[key]
	var result := resolve(interact_id, spec, false)
	if result.is_empty():
		return &""
	_state.set_flag(seen, true)
	return StringName(String(spec["success"] if result["success"] else spec["failure"]))


func visible_report(result: Dictionary, locale: String) -> String:
	if result.is_empty() or not bool(result.get("visible", false)):
		return ""
	var outcome := "SUCCESS" if result["success"] else "FAILURE"
	if locale == "zh-CN":
		outcome = "成功" if result["success"] else "失败"
		return "【%s：1d12=%d + %d %+d = %d / 难度 %d · %s】" % [
			name_of(result["ability"], locale), result["die"], result["bonus"],
			result["modifier"], result["total"], result["difficulty"], outcome]
	return "[%s: 1d12=%d + %d %+d = %d / DC %d · %s]" % [
		name_of(result["ability"], locale), result["die"], result["bonus"],
		result["modifier"], result["total"], result["difficulty"], outcome]
