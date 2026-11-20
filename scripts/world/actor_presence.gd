class_name ActorPresence
extends RefCounted
## The shared skeleton of "put a character back where the story left them" (issue #213).
##
## Q, N and B each have a presence object (`QPresence`, `NPresence`, `BPresence`). Every one
## of them answers the same three events - a room was entered, the whole flag table was
## replaced (a continued save, a new game), and a story flag changed - by re-deriving the
## current room's actor from the flags. That wiring, the lookup of the room's actor and the
## flag reads used to be written out three times; a fix to one (re-syncing after a load,
## #94) could miss the others. It lives here once.
##
## **What stays per character, on purpose.** *When* a character appears, where, and what a
## sync is allowed to do are different rules, and they are kept exactly as they were:
##
## - Q is moved onto `QOpeningTalk` once `met_q` is set, but never in reaction to the flag
##   itself (the beat is already walking him), and never if he already stands there.
## - N is shown at the end of `NEntryPath` once `n_arrived` is set, and only while hidden.
## - B is shown or hidden on every sync, gated on Q's first talk having *ended* and on an
##   explicit `present()`.
##
## A subclass names its actor (`_actor_id()`), implements `sync()` and lists the flags whose
## change should re-sync it (`_watched_flags()`), or overrides `_on_story_flag_changed()`
## when a flag change needs more than a sync (B writes `q_first_talk_done`).
##
## No NPC is serialised (ADR 0005 §3): the flags are the only memory, and every sync reads
## the room's own markers again, so a change to a room's layout moves this with it.

var _game_state: Node = null
var _locations: LocationHost = null


func _init(game_state: Node, locations: LocationHost) -> void:
	_game_state = game_state
	_locations = locations
	if _game_state != null:
		_game_state.story_flag_changed.connect(_on_story_flag_changed)
		_game_state.story_state_replaced.connect(_on_story_state_replaced)
	if _locations != null:
		_locations.location_entered.connect(_on_location_entered)


## The `npc_id` of the actor this object places. Every subclass overrides it.
func _actor_id() -> StringName:
	return &""


## The flags whose change re-syncs the room. Empty: only rooms and loads do.
func _watched_flags() -> Array[StringName]:
	return []


## Makes the current room's actor match the story. Returns true when it changed the actor.
func sync() -> bool:
	return false


## The current room's actor, or null (most rooms author none).
func find_actor() -> NpcActor:
	var location := _current()
	return location.find_actor(_actor_id()) if location != null else null


func _current() -> LocationRoot:
	return _locations.get_current() if _locations != null else null


func _flag(flag: StringName) -> bool:
	return _game_state != null and bool(_game_state.get_flag(flag, false))


func _on_story_flag_changed(flag: StringName, _previous: Variant, _value: Variant) -> void:
	if _watched_flags().has(flag):
		sync()


func _on_location_entered(_location: LocationRoot, _spawn_id: StringName) -> void:
	sync()


func _on_story_state_replaced() -> void:
	sync()
