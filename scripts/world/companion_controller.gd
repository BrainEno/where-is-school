class_name CompanionController
extends CharacterBody3D
## Q walks with the player between locations.
##
## The companion is deliberately **not** part of any location scene. A location
## swap frees everything under `LocationRoot`, so anything authored inside a
## location would disappear the moment the player walks through a door. This node
## lives on the main scene instead, next to the player, and only ever reports
## itself to the current location.
##
## What Q does, and what Q deliberately does not do:
##
## - follows at a natural distance, speeding up only to catch up;
## - walks the **navigation route** to the player, not the straight line: the route
##   comes from the same baked mesh the player's click-to-move uses, so Q goes around
##   a desk, a fence or a wall instead of through it;
## - is a `CharacterBody3D`, so even a route that is wrong cannot push Q through
##   solid geometry — the body stops against the wall and the stall watchdog notices;
## - stops when the player stops, and looks around rather than staring;
## - waits instead of teleporting when left far behind, when there is no route at all,
##   or when the route stops making progress, and can be asked along again through one
##   ordinary interaction;
## - never points at anything, never opens a conversation on its own, never
##   comments on a check result. It is company, not a guide or a quest log.
##
## If the current location already has an authored Q (the classroom does), this
## companion hides itself, so two Qs are never visible at once.
##
## The parts are kept apart on purpose:
##
## - **appearance** — the `NpcActor` child (`Actor`), which only turns and is drawn;
## - **collision** — this body's capsule, on its own layer (4) so the player's ground
##   picking and line-of-sight probes do not mistake Q for a wall or for floor;
## - **navigation and movement** — map path queries plus `move_and_slide()`, both here,
##   both written once;
## - **waiting and resuming** — the `_waiting` band and the `AskAlong` interactable;
## - **the location seam** — `_on_location_entered()` / `_settle_after_transition()`,
##   which place Q behind the player and check that the new scene's navigation is
##   answering before Q tries to walk on it.

signal joined()
signal waiting_changed(waiting: bool)

@export_category("Wiring")
@export var player_path: NodePath = ^"../Player"
@export var host_path: NodePath = ^"../LocationHost"
@export var actor_path: NodePath = ^"Actor"
@export var ask_along_path: NodePath = ^"AskAlong"
## The actor id this companion stands in for.
@export var npc_id: StringName = &"q"
## Story flag written on the first join, so later visits know Q came along.
@export var joined_flag: StringName = StoryFlags.Q_COMPANION

@export_category("Following")
## Past this separation Q starts walking; closer than `stop_distance` Q stops again.
## The two together are the hysteresis that keeps Q from shuffling in place.
@export var follow_distance: float = 2.6
## Q stops here, so it does not walk into the player's back.
@export var stop_distance: float = 1.8
## Faster than the player's walk (3.6) so being left behind is recoverable.
@export var catch_up_speed: float = 4.4
@export_range(1.0, 40.0, 0.5) var acceleration: float = 14.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8
## Past this separation Q gives up chasing and waits.
@export var give_up_distance: float = 11.0
## Once Q has stopped and is waiting, it tries again when the player has moved this far
## since. Without it a wall that the mesh does not know about is walked into forever:
## stop, press, stop, press.
@export var resume_move_distance: float = 1.5
## A route longer than the straight line by more than this is a detour — around a desk,
## through a doorway — and Q walks it even when the player looks close enough to stop.
@export var detour_slack: float = 0.75
## How often Q looks somewhere else while standing still.
@export var idle_look_interval: float = 5.0

@export_category("Navigation")
## The route to the player is rebuilt at most this often. Walking does not need a new
## route every frame, and asking for one every frame is wasted work in every language.
@export_range(0.05, 2.0, 0.05) var repath_interval: float = 0.4
## ...and at once when the player has moved this far since the last request, which is
## what keeps Q's route to a walking player from going stale between intervals.
@export_range(0.2, 4.0, 0.1) var repath_distance: float = 0.8
## How close to a corner of the route counts as having reached it.
@export_range(0.1, 1.5, 0.05) var waypoint_radius: float = 0.35
## How close to the end of the route counts as arrived.
@export_range(0.1, 1.5, 0.05) var arrival_radius: float = 0.5
## No route, or no movement along one, for this long ends the chase: Q stops and waits
## instead of pressing into whatever is in the way.
@export_range(0.2, 10.0, 0.1) var stall_timeout: float = 2.0
## How long a location change may take to answer navigation queries before Q is placed
## by hand on the plain geometry instead.
@export_range(0.5, 15.0, 0.5) var navigation_ready_timeout: float = 5.0
## Which physics layer the body occupies. Layer 4 is not world geometry, so the
## navigation bake, the ground pick and the line-of-sight probe all ignore it.
@export_flags_3d_physics var body_collision_layer: int = 4

var _player: Node3D = null
var _host: LocationHost = null
var _actor: NpcActor = null
var _ask: Interactable = null
var _joined := false
var _waiting := false
## True between "asked along" and "caught up". While catching up, the give-up rule
## does not apply: a player who deliberately walks far away and then asks Q along
## expects Q to arrive, not to give up again immediately.
var _catching_up := false
## Between "wants to follow" and "is close enough to stop".
var _moving := false
var _look_timer := 0.0
var _look_aside := false
## The route currently being walked, in order, and which corner of it is next.
var _route := PackedVector3Array()
var _route_index := 0
## The end of the route the map gave, and the point the map considers the player's
## ground position. When those differ the map cannot reach the player at all.
var _route_target: Vector3 = Vector3.ZERO
var _route_goal: Vector3 = Vector3.ZERO
## True while Q is waiting because a chase went wrong (a wall, a gap it could not
## cross), and where the player stood when that happened.
var _stuck := false
var _stuck_player_position: Vector3 = Vector3.ZERO
var _repath_timer := 0.0
var _last_repath_player_position: Vector3 = Vector3.ZERO
var _stall_elapsed := 0.0
var _no_route_elapsed := 0.0
var _last_body_position: Vector3 = Vector3.ZERO
## True once the current location can answer a path query. Q does not walk on a map
## that has not finished loading.
var _navigation_ready := false
## Diagnostics, read by tests: how many routes were requested and why the last chase
## ended, in words.
var _repath_count := 0
var _last_chase_note := ""


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		push_error("CompanionController: player_path '%s' did not resolve." % player_path)
	_host = get_node_or_null(host_path) as LocationHost
	if _host == null:
		push_error("CompanionController: host_path '%s' did not resolve." % host_path)
	else:
		_host.location_entered.connect(_on_location_entered)
	_actor = get_node_or_null(actor_path) as NpcActor
	_ask = get_node_or_null(ask_along_path) as Interactable
	if _actor == null:
		push_error("CompanionController: actor_path did not resolve to an NpcActor.")
	_last_body_position = global_position
	_refresh_visibility(null)


## Called by the director when the player has actually left the classroom during
## the free period. Idempotent: joining twice does not duplicate anything.
func join() -> void:
	if _joined:
		return
	_joined = true
	_look_timer = 0.0
	_set_waiting(false)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null and not String(joined_flag).is_empty():
		game_state.set_flag(joined_flag, true)
	_refresh_visibility(_host.get_current() if _host != null else null)
	joined.emit()


func is_joined() -> bool:
	return _joined


func is_waiting() -> bool:
	return _waiting


func is_with_player() -> bool:
	return _joined and visible


## True when the companion is far enough behind to be worth asking along.
func can_ask_along() -> bool:
	return _joined and visible and _waiting


## True while Q is walking a route rather than standing.
func is_walking_route() -> bool:
	return not _route.is_empty()


## Diagnostics for tests and logs.
func get_route() -> PackedVector3Array:
	return _route


func get_route_length() -> float:
	var total := 0.0
	for index in range(1, _route.size()):
		total += Vector2(
			_route[index].x - _route[index - 1].x, _route[index].z - _route[index - 1].z
		).length()
	return total


func get_repath_count() -> int:
	return _repath_count


func get_last_chase_note() -> String:
	return _last_chase_note


## Whether Q is allowed to walk yet. False only between a location change and the new
## scene's navigation answering.
func is_navigation_ready() -> bool:
	return _navigation_ready


## How many navigation regions the map Q is querying holds. Zero means every path
## query answers with nothing, however good the mesh is.
func get_navigation_region_count() -> int:
	var map := _navigation_map()
	if not map.is_valid():
		return -1
	return NavigationServer3D.map_get_regions(map).size()


## Resumes following. The interaction that calls this is an ordinary conversation;
## afterwards Q simply catches up again, along a fresh route.
func resume_following() -> void:
	if not _joined:
		return
	_catching_up = true
	_stuck = false
	_clear_route()
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_set_waiting(false)


# --- Movement ---------------------------------------------------------------


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	if _can_follow():
		_update_navigation_readiness()
		direction = _follow_direction(delta)
	else:
		_clear_route()
	_apply_movement(direction, delta)


func _can_follow() -> bool:
	return _joined and visible and _player != null and _actor != null


## Readiness is a live question — "can the map answer a path query right now" — not a
## state that only the location signal may set. A missed signal must not leave Q frozen
## for the rest of the scene.
func _update_navigation_readiness() -> void:
	if _navigation_ready:
		return
	_navigation_ready = _map_has_geometry(_navigation_map())


## The one place the chase decides anything: whether to walk, where to walk, and when
## to stop and wait. Returns the direction to ask for this frame.
##
## The decision follows the **route**, not the straight line. A player standing 2 m away
## across a wall is not "close enough": the route to them is either a detour Q has to
## walk or it does not exist, and in the second case pressing forward is the bug this
## whole class was rewritten for.
func _follow_direction(delta: float) -> Vector3:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	if _waiting:
		if _should_resume(distance):
			_release_waiting()
		else:
			_face_player()
			_idle_look(delta)
			return Vector3.ZERO

	if distance > give_up_distance and not _catching_up:
		_enter_waiting("the player is %.1f m away, past the give-up distance" % distance, false)
		_face_player()
		return Vector3.ZERO

	if distance <= stop_distance and not _waiting:
		# Close enough to stand beside without walking into their back.
		_moving = false
		_catching_up = false
		_no_route_elapsed = 0.0
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	if not _navigation_ready:
		# The new location's mesh is not answering yet. Standing still is the only
		# honest thing to do on a map that cannot say where a wall is.
		return Vector3.ZERO

	if _repath_due(delta):
		if not _rebuild_route():
			_face_player()
			_no_route_elapsed += delta
			if _no_route_elapsed >= stall_timeout:
				_enter_waiting("no route to the player from %s" % str(global_position))
			return Vector3.ZERO
		_no_route_elapsed = 0.0

	if not _route_reaches_the_player():
		# The map answered with a route that stops somewhere else: the player is on the
		# far side of something with no way round. Walking the rest is walking into it.
		_enter_waiting(
			"the route ends %.1f m short of the player" % _flat_length(_route_target - _route_goal)
		)
		_face_player()
		return Vector3.ZERO

	var remaining := _remaining_route_length()
	var detour := remaining > distance + detour_slack
	if not _moving and not detour and distance <= follow_distance:
		# Inside the band, on a route that is the straight line: stay put. Moving here is
		# what produces the shuffle.
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	if remaining <= stop_distance:
		_moving = false
		_catching_up = false
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	_moving = true
	var direction := _route_direction()
	if direction.length_squared() > 0.0001:
		_actor.face_towards(_player.global_position)
		_look_timer = 0.0
		_look_aside = false
	return direction


## Path queries are throttled on two clocks: the interval, and how far the player has
## moved since the last one. Standing still must not cost a query per frame.
func _repath_due(delta: float) -> bool:
	_repath_timer -= delta
	if _route.size() < 2:
		return true
	if _repath_timer <= 0.0:
		return true
	return _player.global_position.distance_to(_last_repath_player_position) > repath_distance


## Nobody gets up from waiting for no reason. Q waits because the chase failed, and
## tries again when the player has moved somewhere that might make a difference — or
## when the player walks back into arm's reach, or after being asked along.
func _should_resume(distance: float) -> bool:
	if _catching_up:
		return true
	if _player == null:
		return false
	if not _stuck:
		# Waiting because the player went too far: coming back into reach is enough.
		return distance <= follow_distance
	if distance > give_up_distance:
		return false
	# A chase that ended against something: only a player who has actually moved, so that
	# the retry is a new situation rather than the same wall from the same angle.
	return _player.global_position.distance_to(_stuck_player_position) > resume_move_distance


func _release_waiting() -> void:
	_stuck = false
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_set_waiting(false)


## Ends a chase that cannot work, and records where the player was so the retry has a
## reason to happen later. `stuck` separates the two kinds of waiting: a player who
## walked too far away is worth following again the moment they come back, while a chase
## that ended against a wall only makes sense to retry once something has changed.
func _enter_waiting(note: String, stuck: bool = true) -> void:
	if not note.is_empty():
		_last_chase_note = note
	_moving = false
	_catching_up = false
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_clear_route()
	_stuck = stuck
	if _player != null:
		_stuck_player_position = _player.global_position
	_set_waiting(true)


func _apply_movement(direction: Vector3, delta: float) -> void:
	var target := direction * catch_up_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	_watch_progress(delta)


## The stall watchdog counts what the *body* did, not what the route wanted: a route
## through a wall that has since been built ends with the body pressed against it, and
## that has to end the chase, not continue forever.
func _watch_progress(delta: float) -> void:
	var moved := global_position.distance_to(_last_body_position)
	_last_body_position = global_position
	if not _moving or _route.is_empty() or _waiting:
		_stall_elapsed = 0.0
		return
	if moved > 0.01:
		_stall_elapsed = 0.0
		return
	_stall_elapsed += delta
	if _stall_elapsed >= stall_timeout:
		_enter_waiting("no progress for %.1f s; stopped at %s" % [stall_timeout, str(global_position)])


## How much walking the route still asks for, from where Q stands to its last point.
func _remaining_route_length() -> float:
	if _route.size() < 2:
		return 0.0
	var previous := Vector3(global_position.x, 0.0, global_position.z)
	var total := 0.0
	var from := maxi(_route_index, 0)
	for index in range(from, _route.size()):
		var point := Vector3(_route[index].x, 0.0, _route[index].z)
		total += previous.distance_to(point)
		previous = point
	return total


## Whether the route the map gave actually ends at the player, as opposed to stopping at
## the edge of the walkable island the player is not standing on.
func _route_reaches_the_player() -> bool:
	if _route.size() < 2:
		return false
	return _flat_length(_route_target - _route_goal) <= arrival_radius + 0.3


func _flat_length(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _route_direction() -> Vector3:
	if _route.size() < 2:
		return Vector3.ZERO
	var here := Vector3(global_position.x, 0.0, global_position.z)
	while _route_index < _route.size() - 1:
		var leg := Vector3(_route[_route_index].x, 0.0, _route[_route_index].z)
		if leg.distance_to(here) <= waypoint_radius:
			_route_index += 1
		else:
			break
	var next := _route[_route_index]
	var to_next := next - global_position
	to_next.y = 0.0
	if to_next.length() < 0.05:
		var to_target := _route_target - global_position
		to_target.y = 0.0
		if to_target.length() <= arrival_radius:
			# The route is finished but the player is still far away: this is the
			# nearest place the map can take Q, and pressing on would be walking into
			# whatever blocks the rest.
			_enter_waiting("the route ends %.1f m short of the player" % (
				_player.global_position.distance_to(global_position)
			))
			return Vector3.ZERO
		return to_target.normalized()
	return to_next.normalized()


# --- Navigation -------------------------------------------------------------


func _navigation_map() -> RID:
	if not is_inside_tree():
		return RID()
	return get_world_3d().navigation_map


func _map_has_geometry(map: RID) -> bool:
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_regions(map).size() > 0


## Asks the map for a route from Q to the player. Returns false when there is no route
## — the player off the mesh, a wall with no way around, navigation not loaded yet —
## and leaves the caller to decide what that means.
func _rebuild_route() -> bool:
	if _player == null:
		return false
	_repath_timer = repath_interval
	_last_repath_player_position = _player.global_position
	var map := _navigation_map()
	if not _map_has_geometry(map):
		return false
	var goal := NavigationServer3D.map_get_closest_point(map, _player.global_position)
	if Vector2(goal.x - _player.global_position.x, goal.z - _player.global_position.z).length() > 1.0:
		# The player is not standing on walkable ground. There is nothing to path to,
		# and walking at them would be walking at a wall.
		return false
	var path := NavigationServer3D.map_get_path(map, global_position, goal, true)
	if path.size() < 2:
		return false
	_route = path
	_route_index = 1
	_route_goal = goal
	# The map may answer with a path that stops at the edge of a different island. Where
	# it actually ends is what says whether the player can be reached at all.
	_route_target = path[path.size() - 1]
	_repath_count += 1
	return true


func _clear_route() -> void:
	_route = PackedVector3Array()
	_route_index = 0


# --- Waiting, joining, looking ----------------------------------------------


## Q does not stare. Every few seconds it looks off to one side and comes back,
## which is enough to read as a person standing with you rather than a statue.
func _idle_look(delta: float) -> void:
	_look_timer += delta
	if _look_timer < idle_look_interval:
		return
	_look_timer = 0.0
	_look_aside = not _look_aside
	if _look_aside:
		var aside := global_position + global_basis.x * 2.0
		_actor.face_towards(aside)
	else:
		_face_player()


func _face_player() -> void:
	if _player != null and _actor != null:
		_actor.face_towards(_player.global_position)


func _set_waiting(value: bool) -> void:
	if _waiting == value:
		return
	_waiting = value
	if _ask != null:
		_ask.interaction_enabled = value
	waiting_changed.emit(_waiting)


# --- The location seam ------------------------------------------------------


## Places Q just behind the player without a walk animation: a location change is
## not something the player can see, so walking Q across the seam would be a lie.
func _place_behind_player() -> void:
	if _player == null or _actor == null:
		return
	var back := _player.global_basis.z
	back.y = 0.0
	if back.length_squared() <= 0.0001:
		back = Vector3.BACK
	var spot := _player.global_position + back.normalized() * stop_distance
	spot.y = _player.global_position.y
	spot = _snap_to_the_mesh(spot)
	global_position = spot
	velocity = Vector3.ZERO
	_last_body_position = spot
	_clear_route()
	_face_player()


## The new location's own mesh decides where a person can actually stand: behind the
## player may be inside a desk, against a wall, or off the floor entirely. A map that
## cannot answer leaves the spot alone rather than guessing.
func _snap_to_the_mesh(spot: Vector3) -> Vector3:
	var map := _navigation_map()
	if not _map_has_geometry(map):
		return spot
	var snapped := NavigationServer3D.map_get_closest_point(map, spot)
	if Vector2(snapped.x - spot.x, snapped.z - spot.z).length() > 1.5:
		return spot
	return Vector3(snapped.x, spot.y, snapped.z)


func _on_location_entered(location: LocationRoot, _spawn_id: StringName) -> void:
	_refresh_visibility(location)
	# Deferred: while the signal runs, the new location is still being assembled and
	# its navigation has not been baked yet.
	call_deferred("_settle_after_transition")


## A location change is the one moment where Q legitimately stands still on a map that
## is not there yet. Wait for the new scene's navigation to answer, then snap Q onto it
## — but only while Q is still standing where it was put. Once Q has walked, moving it
## again would be a teleport the player can see.
func _settle_after_transition() -> void:
	_navigation_ready = false
	_clear_route()
	_moving = false
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	if not visible:
		_navigation_ready = true
		return
	var placed_at := global_position
	# Counted in physics frames, not milliseconds: a test (or a slow frame) can make
	# wall-clock time mean nothing here.
	var budget := maxi(1, int(minf(navigation_ready_timeout, 0.5) * 60.0))
	while is_inside_tree() and budget > 0:
		if _map_has_geometry(_navigation_map()):
			break
		await get_tree().physics_frame
		budget -= 1
	_navigation_ready = true
	if global_position.distance_to(placed_at) > 0.5:
		# Q has already walked on the new floor; the mesh is good enough.
		return
	# Q was already put behind the player when the location changed. What may still be
	# wrong is the floor under it: snapping the place Q is standing, and nothing else, is
	# the only correction that cannot teleport it across a room the player has since
	# walked through.
	var snapped := _snap_to_the_mesh(placed_at)
	if snapped.distance_to(placed_at) <= 0.01:
		return
	global_position = snapped
	velocity = Vector3.ZERO
	_last_body_position = snapped


## Q is visible only where it belongs: joined, and not standing in a location that
## already has its own authored Q.
func _refresh_visibility(location: LocationRoot) -> void:
	var authored := location.find_actor(npc_id) if location != null else null
	var should_show := _joined and authored == null
	visible = should_show
	# A hidden Q is not a wall either: the body leaves the collision world entirely, so
	# nothing the player does can bump into an invisible classmate.
	collision_layer = body_collision_layer if should_show else 0
	collision_mask = 1
	_catching_up = false
	_moving = false
	_stuck = false
	_clear_route()
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_set_waiting(false)
	if _ask != null:
		_ask.interaction_enabled = false
	if should_show:
		_place_behind_player()
