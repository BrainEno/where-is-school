class_name NPresence
extends RefCounted
## Puts the substitute teacher N back at the lectern whenever a room is built after the story
## has brought her in (#166).
##
## The opening walks N in (`OpeningSequence._beat_substitute()`): she starts hidden in the
## classroom scene, is shown at the door, walks `NEntryPath` and ends at its last marker -
## the lectern's TeacherStand - facing the room, and only then is `n_arrived` written. All of
## that is state on one node of one *instance* of the room. `LocationHost` frees the room
## the player leaves and instantiates the scene again when they come back, and a continued
## save loads a fresh instance too, so before this the classroom came back with N exactly as
## the scene authors her: hidden, at her off-stage spot. Nothing read `n_arrived` again.
##
## `n_arrived` is the only memory, as for B (`BPresence`): whenever a room is entered (and
## when the flags are replaced, or `n_arrived` is written) the room's N - if it has one - is
## shown at the end of its `NEntryPath`, turned the way the walk's last leg turns her. The
## spot is read from the room's own markers every time, so it follows the current lectern
## and classroom layout instead of keeping a copy of coordinates.
##
## What this deliberately does not do:
##
## - **Hide N before `n_arrived`.** The scene already does, and the beat shows her at the door
##   *before* it writes the flag (she is seen walking in); hiding her then would cut the walk.
## - **Move a visible N.** A visible N is the beat's, or was already put back; moving her
##   would be a teleport on screen. A fresh room's N is always hidden, so this only ever
##   places an N nobody can see yet.
## - **Create an N.** It uses the actor the room authors; a room without one is left alone.

const ACTOR_ID: StringName = &"n"
## The marker path N walks in on; its last marker is where she teaches from.
const ENTRY_PATH: StringName = &"NEntryPath"

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


## True once the story has walked N in.
func is_on_stage() -> bool:
	return _game_state != null and bool(_game_state.get_flag(StoryFlags.N_ARRIVED, false))


## The current room's N, or null (every room but the classroom).
func find_actor() -> NpcActor:
	var location: LocationRoot = _locations.get_current() if _locations != null else null
	return location.find_actor(ACTOR_ID) if location != null else null


## Makes the room's N (if it has one) match the story: shown at the lectern once she has
## arrived. Returns true when it placed her.
func sync() -> bool:
	if not is_on_stage():
		return false
	var actor := find_actor()
	if actor == null or actor.visible:
		return false
	var location := _locations.get_current()
	var points := location.get_waypoint_path(ENTRY_PATH)
	if points.size() < 2:
		push_error(
			"NPresence: '%s' has an N but its '%s' has fewer than two markers; N stays hidden."
			% [location.location_id, ENTRY_PATH]
		)
		return false
	var stand := points[points.size() - 1]
	var last_leg := stand - points[points.size() - 2]
	actor.place_at(stand, stand + last_leg)
	return true


func _on_story_flag_changed(flag: StringName, _previous: Variant, _value: Variant) -> void:
	if flag == StoryFlags.N_ARRIVED:
		sync()


func _on_location_entered(_location: LocationRoot, _spawn_id: StringName) -> void:
	sync()


func _on_story_state_replaced() -> void:
	sync()
