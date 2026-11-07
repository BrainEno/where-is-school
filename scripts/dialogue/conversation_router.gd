class_name ConversationRouter
extends RefCounted
## Picks which conversation an NPC anchor should play, from story flags.
##
## This is a lookup table, not a quest system: rules are ordered, the first match
## wins, and an empty `requires` map is the fallback. Keeping it declarative means
## the routing can be tested without instantiating a scene.

const ROUTES: Dictionary = {
	# Q: the opening conversation happens automatically; later visits change tone.
	&"q": [
		{
			"conversation": &"q_after_dismissal",
			"requires": {StoryFlags.CLASS_DISMISSED: true},
		},
		{
			"conversation": &"q_after_bag",
			"requires": {StoryFlags.TEXTBOOK_MISSING: true},
		},
		{
			"conversation": &"q_wake",
			"requires": {},
		},
	],
	# N only speaks once, from the front of the room.
	&"n": [
		{
			"conversation": &"n_class",
			"requires": {},
		},
	],
	# Outside the school the routes are things, not people: a wall, a notice, a
	# staircase. Same table, same rules.
	&"street_wall": [{"conversation": &"street_wall", "requires": {}}],
	&"street_notice": [{"conversation": &"street_notice", "requires": {}}],
	&"residential_stair": [{"conversation": &"residential_stair", "requires": {}}],
	# The animal is met, not summoned: the first visit is the discovery, every
	# later visit is a shorter look. Neither one explains what it is.
	&"green_animal": [
		{
			"conversation": &"animal_again",
			"requires": {StoryFlags.ANIMAL_SEEN: true},
		},
		{
			"conversation": &"animal_sighting",
			"requires": {},
		},
	],
}


## Returns an empty StringName when the anchor has no rule at all.
static func select(route_id: StringName, flags: Dictionary) -> StringName:
	var rules: Variant = ROUTES.get(route_id, null)
	if not (rules is Array):
		return &""
	for rule: Variant in (rules as Array):
		if not (rule is Dictionary):
			continue
		var rule_data: Dictionary = rule
		if matches(rule_data.get("requires", {}), flags):
			return StringName(String(rule_data.get("conversation", "")))
	return &""


static func matches(requires: Dictionary, flags: Dictionary) -> bool:
	for flag: Variant in requires.keys():
		if flags.get(flag, null) != requires[flag]:
			return false
	return true


static func has_route(route_id: StringName) -> bool:
	return ROUTES.has(route_id)
