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
		# MET_Q is set on the first line, but interaction stays locked until the
		# conversation ends. Legal checkpoints are after that beat, never mid-line.
		# Keep the older flag/save contract; bag and dismissal still win above it.
		{
			"conversation": &"q_studying",
			"requires": {StoryFlags.MET_Q: true},
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
	# The biology classroom's back-window curtain. Before N lets the class go it is only
	# looked at; afterwards it can be drawn aside (the conversation sets the provisional
	# `curtain_fall_pending`, and the classroom stages the fall); once it hangs open, a
	# visit is a look at what is still there. The room's StagedInteractable plays the
	# conversation this route selects.
	&"classroom_curtain": [
		{
			"conversation": &"classroom_curtain_drawn",
			"requires": {StoryFlags.CURTAIN_DRAWN: true},
		},
		{
			"conversation": &"classroom_curtain",
			"requires": {StoryFlags.CLASS_DISMISSED: true},
		},
		{
			"conversation": &"classroom_curtain_lesson",
			"requires": {},
		},
	],
	# Outside the school the routes are things, not people: a wall, a notice, a
	# staircase. Same table, same rules.
	# The companion only ever says one thing when asked along, and it is not advice.
	&"q_ask_along": [{"conversation": &"q_ask_along", "requires": {}}],
	# The walkway's optional activities. They are conversations rather than plain
	# inspections because Q has something to say in them when it is there, and the
	# `conditions` on those lines are content, not a special case in code.
	&"corridor_speaker": [{"conversation": &"corridor_speaker", "requires": {}}],
	&"corridor_trolley": [{"conversation": &"corridor_trolley", "requires": {}}],
	&"corridor_wait": [{"conversation": &"corridor_wait", "requires": {}}],
	&"street_wall": [{"conversation": &"street_wall", "requires": {}}],
	&"street_notice": [{"conversation": &"street_notice", "requires": {}}],
	&"residential_stair": [{"conversation": &"residential_stair", "requires": {}}],
	# The yard's two attempts are conversations with a choice (and then a check), not
	# inspections: the player has to commit to an approach before dice are involved.
	&"pg_shed": [{"conversation": &"pg_shed", "requires": {}}],
	&"pg_ball": [{"conversation": &"pg_ball", "requires": {}}],
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
