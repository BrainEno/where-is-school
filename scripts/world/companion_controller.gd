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
var _route_target: Vector3 = Vector3.ZERO
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


## Resumes following. The interaction that calls this is an ordinary conversation;
## afterwards Q simply catches up again, along a fresh route.
func resume_following() -> void:
	if not _joined:
		return
	_catching_up = true
	_clear_route()
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_set_waiting(false)


# --- Movement ---------------------------------------------------------------


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	if _can_follow() and _navigation_ready:
		direction = _follow_direction(delta)
	else:
		_clear_route()
	_apply_movement(direction, delta)


func _can_follow() -> bool:
	return _joined and visible and _player != null and _actor != null


## The one place the chase decides anything: whether to walk, where to walk, and when
## to stop and wait. Returns the direction to ask for this frame.
func _follow_direction(delta: float) -> Vector3:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	if distance > give_up_distance and not _catching_up:
		if not _waiting:
			_last_chase_note = "the player is %.1f m away, past the give-up distance" % distance
			_set_waiting(true)
		_clear_route()
		_face_player()
		return Vector3.ZERO

	if _waiting:
		_clear_route()
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	if distance <= stop_distance:
		_moving = false
		_catching_up = false
		_clear_route()
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	if not _moving and distance <= follow_distance:
		# Inside the band: stay put. Moving here is what produces the shuffle.
		_clear_route()
		_face_player()
		_idle_look(delta)
		return Vector3.ZERO

	_moving = true
	if not _route_is_current(delta):
		if not _rebuild_route():
			_clear_route()
			_face_player()
			_no_route_elapsed += delta
			if _no_route_elapsed >= stall_timeout:
				_last_chase_note = "no route to the player from %s" % str(global_position)
				_set_waiting(true)
			return Vector3.ZERO
		_no_route_elapsed = 0.0

	var direction := _route_direction()
	if direction.length_squared() > 0.0001:
		_actor.face_towards(_player.global_position)
		_look_timer = 0.0
		_look_aside = false
	return direction


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
	if not _moving or _route.is_empty():
		_stall_elapsed = 0.0
		return
	if moved > 0.01:
		_stall_elapsed = 0.0
		return
	_stall_elapsed += delta
	if _stall_elapsed >= stall_timeout:
		_last_chase_note = "no progress for %.1f s; stopped at %s" % [stall_timeout, str(global_position)]
		_clear_route()
		_moving = false
		_set_waiting(true)


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
			_last_chase_note = "the route ends %.1f m short of the player" % (
				_player.global_position.distance_to(global_position)
			)
			_clear_route()
			_moving = false
			_set_waiting(true)
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


func _route_is_current(delta: float) -> bool:
	if _route.size() < 2:
		return false
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		return false
	return _player.global_position.distance_to(_last_repath_player_position) <= repath_distance


## Asks the map for a route from Q to the player. Returns false when there is no route
## — the player off the mesh, a wall with no way around, navigation not loaded yet —
## and leaves the caller to decide what that means.
func _rebuild_route() -> bool:
	_repath_timer = repath_interval
	_last_repath_player_position = _player.global_position
	if _player == null:
		return false
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
	_route_target = goal
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
	# The new location's own mesh decides where a person can actually stand: behind
	# the player may be inside a desk, against a wall, or off the floor entirely.
	var map := _navigation_map()
	if _map_has_geometry(map):
		var snapped := NavigationServer3D.map_get_closest_point(map, spot)
		if Vector2(snapped.x - spot.x, snapped.z - spot.z).length() <= 1.5:
			spot = Vector3(snapped.x, _player.global_position.y, snapped.z)
	global_position = spot
	velocity = Vector3.ZERO
	_last_body_position = spot
	_clear_route()
	_face_player()


func _on_location_entered(location: LocationRoot, _spawn_id: StringName) -> void:
	_refresh_visibility(location)
	# Deferred: while the signal runs, the new location is still being assembled and
	# its navigation has not been baked yet.
	call_deferred("_settle_after_transition")


## A location change is the one moment where Q legitimately stands still on a map that
## is not there yet. Wait for the new scene's navigation to answer, then place Q on it.
func _settle_after_transition() -> void:
	_navigation_ready = false
	_clear_route()
	_moving = false
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	if not visible:
		_navigation_ready = true
		return
	var deadline := Time.get_ticks_msec() + int(navigation_ready_timeout * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		if _map_has_geometry(_navigation_map()):
			break
		await get_tree().physics_frame
	_navigation_ready = true
	_place_behind_player()


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
	_clear_route()
	_stall_elapsed = 0.0
	_no_route_elapsed = 0.0
	_set_waiting(false)
	if _ask != null:
		_ask.interaction_enabled = false
	if should_show:
		_place_behind_player()
