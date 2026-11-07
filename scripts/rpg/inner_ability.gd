class_name InnerAbility
extends Resource
## Definition of one inner ability (inner voice).
##
## Each ability is a distinct narrative persona, not a stat stick.
## It has a bilingual name/description, a numeric contribution, and
## rules for when it speaks passively vs when it can be actively invoked.
##
## Abilities are authored in data/abilities/<id>.json and loaded by
## AbilityRegistry. This Resource is the runtime shape.

## Stable id, e.g. "keen_eye", "recollection", "gut_feeling", "steadiness".
@export var ability_id: StringName = &""
## Display name keys for UI (locale lookups).
## e.g. "ability.keen_eye.name"
@export var name_key: String = ""
@export var description_key: String = ""
## Base value contributed to checks (before level ups; current slice: 1-3).
@export var base_value: int = 2
## Current level (may be modified later, but not in this slice).
@export var level: int = 1
## Tags describing narrative tone, for tooling only.
@export var tone: String = ""
## Whether this ability can be chosen actively in dialogue.
@export var active_allowed: bool = true
## Whether this ability can trigger passively.
@export var passive_allowed: bool = true

## Total contribution: base_value + (level - 1). Kept simple for testability.
func get_value() -> int:
	return base_value + maxi(0, level - 1)


func get_display_name() -> String:
	if name_key.is_empty():
		return String(ability_id)
	if L10n.has_key(name_key):
		return L10n.t(name_key)
	return name_key


func get_description() -> String:
	if description_key.is_empty():
		return ""
	if L10n.has_key(description_key):
		return L10n.t(description_key)
	return description_key


func to_dict() -> Dictionary:
	return {
		"ability_id": String(ability_id),
		"name_key": name_key,
		"description_key": description_key,
		"base_value": base_value,
		"level": level,
		"tone": tone,
		"active_allowed": active_allowed,
		"passive_allowed": passive_allowed,
		"value": get_value(),
	}
