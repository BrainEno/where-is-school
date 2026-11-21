class_name QPresence
extends ActorPresence
## Puts Q back where the opening left him whenever a room is built after Q's first talk
## has begun.
##
## The opening's Q beat (`OpeningSequence._beat_q_wake()`) walks the classroom's Q from his
## authored spot to the room's `QOpeningTalk` marker, turns him to the protagonist's seat
## and carries the `q_talk` hotspot with him; `met_q` is written by the first line of the
## conversation that follows. All of that is state on one node of one *instance* of the
## room. `LocationHost` frees the room the player leaves and instantiates the scene again
## when they come back, and a continued save loads a fresh instance too, so before this
## the classroom came back with Q at his authored spot - about 1.3 m from where the player
## last saw him - and his hotspot with him. Nothing read `met_q` to undo that.
##
## No NPC is serialised (ADR 0005 §3). On entry or flag replacement, the room's own
## QOpeningTalk and PlayerStart restore the opening composition after `met_q`. After
## `bell_rung`, the classroom's chair controller places Q back at his desk instead.
## In both cases `q_talk` moves with him; a rebuilt room does not replay a performance.
##
## What this deliberately does not do:
##
## - **React to `met_q` being written.** It is written on Q's first line, after the beat has
##   already walked him over; moving him then would at best do nothing and at worst be a
##   teleport on screen if some other path wrote the flag. A room that is already built is
##   left to the beat.
## - **Move a Q that is already there.** A Q within `AT_LANDING_METRES` of the marker is the
##   beat's, or was already placed; he and his hotspot are left alone, so a repeated
##   `location_entered` cannot carry the hotspot away from him.
## - **Invent a landing.** Without a `QOpeningTalk` the beat chooses a point in front of
##   wherever the player happened to stand, which a later room cannot know. Such a room
##   keeps its authored Q, and says so once in the log.
## - **Touch the companion.** The roaming Q (`CompanionController`) hides itself in a room
##   that authors its own Q; which of the two is drawn is its decision, not this one's.

const ACTOR_ID: StringName = &"q"
## The interaction that talks to Q; it moves with him.
const TALK_ID: StringName = &"q_talk"
## The marker the opening walks Q to. Optional per room, as it is for the beat.
const LANDING: StringName = &"QOpeningTalk"
## Where the protagonist sits during the opening: what Q faces when the talk begins.
const SEAT_SPAWN: StringName = &"PlayerStart"
## How close to the marker counts as already standing on it.
const AT_LANDING_METRES := 0.05

## Rooms already reported as having a Q but no landing, so the log says it once per room.
var _reported_without_landing: Dictionary = {}


func _init(game_state: Node, locations: LocationHost) -> void:
	super(game_state, locations)


## Rooms and loads re-place Q; `met_q` being written does not (see the header).
func _actor_id() -> StringName:
	return ACTOR_ID


## True once Q's first conversation has begun (its first line writes `met_q`).
func has_met() -> bool:
	return _flag(StoryFlags.MET_Q)


## Where the opening leaves Q in `location`: `{point, facing}`, or `{}` when the room
## authors no landing. `facing` is a point to turn towards, not a direction; it is
## `Vector3.ZERO` (keep the current facing) when the room has no seat marker either.
static func landing_in(location: LocationRoot) -> Dictionary:
	if location == null:
		return {}
	var marker := location.find_child(String(LANDING), true, false) as Node3D
	if marker == null:
		return {}
	# Asked for by name only when the room declares it: `get_spawn()` reports a missing
	# name as a content error, and a room without a seat is allowed here.
	var seat: Node3D = null
	if location.get_spawn_ids().has(SEAT_SPAWN):
		seat = location.get_spawn(SEAT_SPAWN)
	return {
		"point": marker.global_position,
		"facing": seat.global_position if seat != null else Vector3.ZERO,
	}


## Moves `location`'s `q_talk` by however far `actor` moved from `from`, and refreshes its
## pointer boxes. Shared with the opening beat so the hotspot follows Q the same way
## whether he walked there or was put there.
##
## A hotspot authored *under* Q has already followed him and is left alone.
static func carry_talk(location: LocationRoot, actor: NpcActor, from: Vector3) -> void:
	if location == null or actor == null:
		return
	var talk := location.find_interactable(TALK_ID)
	if talk == null or actor.is_ancestor_of(talk):
		return
	talk.global_position += actor.global_position - from
	# Its outline meshes are Q's, and they moved and turned (a turn on the spot changes
	# their bounds too): the pick boxes are rebuilt around them once, rather than
	# leaving a ghost hotspot where Q used to stand.
	talk.rebuild_pick_shapes()


## Run the room's seating performance under the director's lock. Like the intro
## approach, this carries Q's talk target only once the movement has ended.
func return_to_classroom_seats(player: PlayerController) -> void:
	var location := _current()
	var chairs := ClassroomChairControl.in_room(location)
	if chairs == null:
		return
	var actor := find_actor()
	var before := actor.global_position if actor != null else Vector3.ZERO
	await chairs.seat_for_class(player, actor)
	if actor != null and not actor.global_position.is_equal_approx(before):
		carry_talk(location, actor, before)


## Makes a rebuilt Q match the story: at his desk after the bell, or at the talk
## marker after his introduction. Returns true when it moved him.
func sync() -> bool:
	var location := _current()
	var actor := find_actor()
	if location == null or actor == null:
		return false
	var chairs := ClassroomChairControl.in_room(location)
	if chairs != null and _flag(StoryFlags.BELL_RUNG) and not _flag(StoryFlags.SKIPPED_CLASS):
		var before := actor.global_position
		if not chairs.restore_q_seat(actor):
			return false
		carry_talk(location, actor, before)
		return true
	if not has_met():
		return false
	var landing := landing_in(location)
	if landing.is_empty():
		var room_id := String(location.location_id)
		if not _reported_without_landing.has(room_id):
			_reported_without_landing[room_id] = true
			print_verbose(
				"QPresence: '%s' has a Q but no '%s'; he stays where the room authors him."
				% [room_id, LANDING]
			)
		return false
	var point: Vector3 = landing["point"]
	if actor.global_position.distance_to(point) <= AT_LANDING_METRES:
		return false
	var from := actor.global_position
	actor.place_at(point, landing["facing"])
	carry_talk(location, actor, from)
	return true
