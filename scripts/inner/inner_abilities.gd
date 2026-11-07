class_name InnerAbilities
extends RefCounted
## The first three possible viewpoints, not objective narrators. Stable IDs are
## stored in GameState; display names and functions are translated locale keys.
## Adding a viewpoint only needs a definition, translations and authored lines.

const MIN_RATING := 0
const MAX_RATING := 4
const DEFINITIONS := {
	&"pattern": {"default": 2, "name_key": "ability.pattern", "role_key": "role.pattern"},
	&"resonance": {"default": 1, "name_key": "ability.resonance", "role_key": "role.resonance"},
	&"guard": {"default": 2, "name_key": "ability.guard", "role_key": "role.guard"},
}


static func has_ability(ability_id: StringName) -> bool:
	return DEFINITIONS.has(ability_id)


static func rating_flag(ability_id: StringName) -> StringName:
	return StringName("inner:ability:%s" % ability_id)


static func get_rating(state: Node, ability_id: StringName) -> int:
	if not has_ability(ability_id):
		push_error("Unknown inner ability '%s'." % ability_id)
		return -1
	var default_rating := int(DEFINITIONS[ability_id]["default"])
	if state == null:
		return default_rating
	return clampi(int(state.get_flag(rating_flag(ability_id), default_rating)), MIN_RATING, MAX_RATING)


static func set_rating(state: Node, ability_id: StringName, value: int) -> bool:
	if state == null or not has_ability(ability_id) or value < MIN_RATING or value > MAX_RATING:
		return false
	state.set_flag(rating_flag(ability_id), value)
	return true


static func display_name(ability_id: StringName) -> String:
	if not has_ability(ability_id):
		return String(ability_id)
	return L10n.t(String(DEFINITIONS[ability_id]["name_key"]))
