class_name AbilityRegistry
extends RefCounted
## Loads inner abilities from data.
##
## In this slice the abilities are defined in data/abilities/abilities.json
## (one file, per-ability bilingual keys). Future expansion may split into
## per-ability files.

const ABILITIES_PATH := "res://data/abilities/abilities.json"

var errors: Array[String] = []
var _abilities: Dictionary = {}
var _by_id: Dictionary = {}

static func load_all() -> AbilityRegistry:
	var registry := AbilityRegistry.new()
	registry._load()
	return registry


func _load() -> void:
	if not FileAccess.file_exists(ABILITIES_PATH):
		errors.append("Ability file not found: %s" % ABILITIES_PATH)
		return
	var file := FileAccess.open(ABILITIES_PATH, FileAccess.READ)
	if file == null:
		errors.append("Could not open %s (error %d)" % [ABILITIES_PATH, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [ABILITIES_PATH, json.get_error_line(), json.get_error_message()])
		return
	var root: Variant = json.data
	if not (root is Dictionary):
		errors.append("%s: root must be object" % ABILITIES_PATH)
		return
	var data: Dictionary = root
	var raw: Variant = data.get("abilities", [])
	if not (raw is Array):
		errors.append("%s: 'abilities' must be array" % ABILITIES_PATH)
		return
	for idx in (raw as Array).size():
		var entry: Variant = (raw as Array)[idx]
		if not (entry is Dictionary):
			errors.append("%s ability #%d: must be object" % [ABILITIES_PATH, idx])
			continue
		var ability := _parse_ability(entry as Dictionary, idx)
		if ability == null:
			continue
		if _by_id.has(ability.ability_id):
			errors.append("%s: duplicate ability id '%s'" % [ABILITIES_PATH, ability.ability_id])
			continue
		_by_id[ability.ability_id] = ability
		_abilities[ability.ability_id] = ability


func _parse_ability(data: Dictionary, idx: int) -> InnerAbility:
	var ctx := "%s ability #%d" % [ABILITIES_PATH, idx]
	var ability := InnerAbility.new()
	var id_str := String(data.get("id", "")).strip_edges()
	if id_str.is_empty():
		errors.append("%s: missing 'id'" % ctx)
		return null
	ability.ability_id = StringName(id_str)
	var fmt := int(data.get("format_version", 1))
	if fmt != 1:
		errors.append("%s: unsupported format_version %d" % [ctx, fmt])
	ability.name_key = String(data.get("name_key", ""))
	ability.description_key = String(data.get("description_key", ""))
	ability.base_value = int(data.get("base_value", 2))
	ability.level = int(data.get("level", 1))
	ability.tone = String(data.get("tone", ""))
	ability.active_allowed = bool(data.get("active_allowed", true))
	ability.passive_allowed = bool(data.get("passive_allowed", true))
	if ability.name_key.is_empty():
		errors.append("%s '%s': missing name_key" % [ctx, id_str])
	if ability.base_value < 0 or ability.base_value > 10:
		errors.append("%s '%s': base_value %d out of range 0..10" % [ctx, id_str, ability.base_value])
	return ability


func is_valid() -> bool:
	return errors.is_empty()


func describe_errors() -> String:
	if errors.is_empty():
		return "Abilities loaded without errors."
	return "Abilities has %d error(s):\n%s" % [errors.size(), "\n".join(errors)]


func has_ability(ability_id: StringName) -> bool:
	return _by_id.has(ability_id)


func get_ability(ability_id: StringName) -> InnerAbility:
	return _by_id.get(ability_id, null)


func get_all() -> Array[InnerAbility]:
	var result: Array[InnerAbility] = []
	for key in _by_id.keys():
		result.append(_by_id[key])
	return result


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _by_id.keys():
		ids.append(k)
	return ids
