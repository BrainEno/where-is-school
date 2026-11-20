class_name QIntroApproach
extends RefCounted
## Q walking over to the protagonist's desk before his first line (the `q_wake` beat).
##
## Split out of `OpeningSequence._approach_q_for_intro()` (issue #223); the beat still
## decides *when* Q comes over and holds the beat lock while he does. This is *how*: a
## native navigation route fed to the actor's existing staging/animation API, exactly as
## N's entry uses `walk_along()` - no new locomotion system and no classroom coordinates.
##
## The room owns Q's initial placement and may provide a `QOpeningTalk` marker for the
## final composition (#159). Without one, an authored spot that is already close in front
## of the player is respected; otherwise Q stops 1.25 m in front of the player's facing.
## The approach never changes the protagonist's wake/seat pose, camera or location (#121).
##
## Every refusal is an authoring problem (no Q, no `q_talk`, a navigation map that never
## synchronizes, a landing out of reach) and is logged as one; the beat then skips the
## conversation rather than playing it with Q across the room.

## Where Q stops when the room authors no landing, in front of the player's facing.
const DEFAULT_REACH := 1.25
## How long the room's navigation map may take to synchronize, in story seconds.
const SYNC_LIMIT_SECONDS := 3.0
const SYNC_POLL_SECONDS := 0.05
## A landing must be within this band of the player (horizontal metres) ...
const MIN_REACH := 0.85
const MAX_REACH := 1.65
## ... and the navigation mesh must reach within this distance of it.
const MAX_LANDING_GAP := 0.3
## How close the route's last point must come to the landing.
const ROUTE_END_TOLERANCE := 0.15


## Walks the room's Q to his landing, turns him to the player and carries `q_talk` with
## him. True when he arrived. `clock.wait_seconds()` is the director's story clock, so a
## pause stops the wait for the navigation map too.
func run(location: LocationRoot, player: PlayerController, clock: Node) -> bool:
	var actor: NpcActor = location.find_actor(QPresence.ACTOR_ID) if location != null else null
	var talk: Interactable = location.find_interactable(QPresence.TALK_ID) if location != null else null
	if actor == null or talk == null:
		push_error("OpeningSequence: Q's introduction needs the room's Q actor and q_talk anchor.")
		return false
	var navigation := _navigation_of(location)
	# A room's bake and server map synchronize after it enters the tree. Wait in
	# story time (including pauses), with a bound, before issuing any path query.
	var waited := 0.0
	while navigation != null and not navigation.is_synchronized() and waited < SYNC_LIMIT_SECONDS:
		await clock.wait_seconds(SYNC_POLL_SECONDS)
		waited += SYNC_POLL_SECONDS
	if navigation == null or not navigation.is_synchronized():
		push_error("OpeningSequence: Q cannot approach before the classroom navigation is synchronized.")
		return false

	var initial := actor.global_position
	var target := landing_target(location, player, initial)
	var map := navigation.get_navigation_map()
	var snapped := NavigationServer3D.map_get_closest_point(map, target)
	var gap := Vector2(snapped.x - target.x, snapped.z - target.z).length()
	var reach := Vector2(snapped.x - player.global_position.x, snapped.z - player.global_position.z).length()
	if gap > MAX_LANDING_GAP or reach < MIN_REACH or reach > MAX_REACH:
		push_error("OpeningSequence: QOpeningTalk must be reachable ground close to the protagonist.")
		return false
	var route := NavigationServer3D.map_get_path(map, initial, snapped, true)
	if route.size() < 2 or route[-1].distance_to(snapped) > ROUTE_END_TOLERANCE:
		push_error("OpeningSequence: no complete navigation route for Q's introduction.")
		return false
	var points := _grounded(route, actor)
	if points.is_empty():
		push_error("OpeningSequence: Q's introduction route has no supporting floor.")
		return false
	await actor.walk_along(points)
	actor.face_towards(player.global_position)
	# QTalk is a sibling in the current scene and moves by the same amount as Q (a
	# future scene may parent it to Q, in which case it followed naturally). The same
	# helper puts it back in a room built later, so the two cannot disagree (#160).
	# Its pick boxes are rebuilt once, while interaction is still locked.
	QPresence.carry_talk(location, actor, initial)
	return true


## Where Q should end up: the room's `QOpeningTalk`, or his authored spot when it is
## already a close, in-front position, or `DEFAULT_REACH` in front of the player.
static func landing_target(location: LocationRoot, player: PlayerController,
		initial: Vector3) -> Vector3:
	var landing := location.find_child(String(QPresence.LANDING), true, false) as Marker3D
	if landing != null:
		return landing.global_position
	# Respect an already-authored close/front position instead of moving Q to
	# an old world coordinate when #159 changes the desk composition.
	var offset := initial - player.global_position
	offset.y = 0.0
	if offset.length() >= 0.9 and offset.length() <= MAX_REACH \
			and offset.normalized().dot(player.get_facing_direction()) > 0.25:
		return initial
	return player.global_position + player.get_facing_direction() * DEFAULT_REACH


static func _navigation_of(location: LocationRoot) -> LocationNavigation:
	for child in location.get_children():
		if child is LocationNavigation:
			return child as LocationNavigation
	return null


## The route's points dropped onto the actual floor, or empty when one has none under it.
## Recast's floor is voxel-offset; the actor has no gravity of its own, so its feet go on
## the physics floor rather than tweening above the navigation mesh.
static func _grounded(route: PackedVector3Array, actor: NpcActor) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var space := actor.get_world_3d().direct_space_state
	for point in route:
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN * 2.0, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return []
		points.append(hit["position"])
	return points
