extends SceneTree
## Q follows the navigation route, and the walls are real.
##
## The bug this test was written for: the companion moved by writing `global_position`
## towards the player, so it walked through walls, fences and buildings. Following is now
## a route on the location's own navigation mesh, walked by a `CharacterBody3D`.
##
## The corridor is used because it is a long, straight walkway with a floor and two side
## walls: a wall placed across it cannot be mistaken for anything else. Every wall is
## built **before** Q starts walking, and the navigation mesh is re-baked when the case
## needs the map to know about it.
##
## Cases:
##  1. a wall across the walkway that the mesh does not know about → Q's route runs
##     straight at it, the body stops, and Q ends up waiting rather than through it;
##  2. a wall with a gap, baked into the mesh → Q goes around through the gap;
##  3. a wall with no gap, baked in → there is no route, so Q stops and waits;
##  4. asked along afterwards → a fresh route is built and Q closes the gap;
##  5. Q never overlaps the player;
##  6. crossing locations keeps exactly one visible Q.

const Harness = preload("res://tests/test_harness.gd")

const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const TIME_SCALE := 4.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _companion: CompanionController = null
var _location: LocationRoot = null
var _walls: Array[StaticBody3D] = []
var _closest_approach := INF
## A short position trace, so a failed case can say what Q actually did instead of
## leaving it to be guessed from where it ended up.
var _trace: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 260.0, "companion_obstacle_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await process_frame
	await process_frame

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_companion = _main.get_node_or_null("Companion") as CompanionController
	if _host == null or _player == null or _sequence == null or _dialogue == null \
			or _companion == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_sequence.allow_player_control()
	Engine.time_scale = TIME_SCALE
	await _frames(4)

	if not _companion is CharacterBody3D:
		_failures.append("The companion is not a physics body, so nothing stops it entering a wall.")
	_location = await _enter(CORRIDOR, &"FromClassroom")
	if _location == null:
		Harness.finish(self, ["The corridor did not load."], "")
		return
	_companion.join()
	await _physics_frames(6)
	if not _companion.is_with_player():
		_failures.append("Q did not appear after joining in the corridor: %s." % _state())
		return

	await _check_unknown_wall_stops_the_body()
	await _check_gap_is_walked_around()
	await _check_no_route_means_waiting()
	await _check_asked_along_rebuilds_the_route()
	await _check_one_q_across_locations()
	_clean_up_walls()

	Harness.finish(
		self, _failures,
		"Q walks the navigation route, is stopped by real walls, and waits when there is no way."
	)


# --- case 1: a wall the mesh does not know about -----------------------------


## The wall is added *after* the location baked, so the navigation mesh still believes
## the walkway is clear and Q's route runs straight through it. Only the body stops Q —
## which is the whole point of following a route with a physics body.
func _check_unknown_wall_stops_the_body() -> void:
	await _stage(3.0, 6.0, [Vector3(0.0, 1.5, 4.5)], Vector3(4.4, 3.0, 0.2), false)
	var crossed := await _wait_until(
		func() -> bool: return _companion.global_position.z < 4.3, 8.0
	)
	if crossed:
		_failures.append("Q crossed a wall the body should have stopped it at: %s." % _state())
	if _companion.global_position.z < 4.35:
		_failures.append("Q ended up on the far side of the wall: %s." % _state())
	await _wait_until(func() -> bool: return _companion.is_waiting(), 10.0)
	if not _companion.is_waiting():
		_failures.append("Q kept pressing at a wall instead of waiting: %s." % _state())
	_clean_up_walls()


# --- case 2: a wall with a gap, baked into the mesh --------------------------


## Two wall segments with a 1.6 m gap, baked into the navigation mesh: the route has to
## bend through the gap. Crossing the wall line inside the gap is the assertion; a route
## with corners in it is the evidence that it was not a straight line.
func _check_gap_is_walked_around() -> void:
	await _stage(
		1.0, 6.0,
		[Vector3(-1.5, 1.5, 3.0), Vector3(1.5, 1.5, 3.0)],
		Vector3(1.4, 3.0, 0.2),
		true
	)
	var longest_route := 0
	var crossed_at_x := INF
	var crossed := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		longest_route = maxi(longest_route, _companion.get_route().size())
		if not crossed and _companion.global_position.z < 3.0:
			crossed = true
			crossed_at_x = _companion.global_position.x
		if _flat_distance(_companion.global_position, _player.global_position) <= 1.4:
			break
	var gap := _flat_distance(_companion.global_position, _player.global_position)
	if gap > _companion.follow_distance + 0.6:
		_failures.append(
			"Q did not walk around the wall through the gap (%.1f m from the player): %s."
			% [gap, _state()]
		)
	if not crossed:
		_failures.append("Q never reached the player's side of the wall: %s." % _state())
	elif absf(crossed_at_x) > 1.0:
		_failures.append("Q crossed the wall line at x=%.2f, outside the 1.6 m gap." % crossed_at_x)
	if longest_route < 3:
		_failures.append(
			"The longest route Q held had %d point(s), so it walked a straight line rather"
			% longest_route + " than through the gap: %s." % _state()
		)
	_clean_up_walls()


# --- case 3: no route at all -------------------------------------------------


## The wall goes all the way across and is baked in: the two halves of the walkway are
## separate islands, so there is no route. Q must stop and wait, not lean on the wall.
func _check_no_route_means_waiting() -> void:
	await _stage(1.0, 6.0, [Vector3(0.0, 1.5, 3.0)], Vector3(4.4, 3.0, 0.2), true)
	var waited := await _wait_until(func() -> bool: return _companion.is_waiting(), 15.0)
	if not waited:
		_failures.append("With no route to the player, Q never settled into waiting: %s." % _state())
	if _companion.global_position.z < 3.0:
		_failures.append("Q got through a wall with no gap in it: %s." % _state())
	if _companion.is_walking_route() and _companion.is_waiting():
		_failures.append("Q is waiting while still holding a route: %s." % _state())


# --- case 4: asked along afterwards -----------------------------------------


## Taking the wall out and asking Q along again has to rebuild the route: waiting is a
## pause, not a state Q is stuck in.
func _check_asked_along_rebuilds_the_route() -> void:
	var before := _companion.get_repath_count()
	_clean_up_walls()
	# `queue_free()` takes the wall out at the end of the frame: baking before that bakes
	# the wall it was supposed to remove, and Q then reports a route that ends short.
	await _physics_frames(2)
	if not await _rebake():
		_failures.append("The corridor's navigation could not be restored.")
		return
	# Removing the wall has to reach the map before the invitation can mean anything:
	# otherwise Q is asked along into a mesh that still believes the walkway is divided.
	if not await _wait_for_a_route():
		_failures.append(
			"The corridor's mesh still cannot join the two halves after the wall was"
			+ " removed: %s." % _state()
		)
		return
	var ask := _main.get_node_or_null(^"Companion/AskAlong") as Interactable
	if ask == null:
		_failures.append("The companion has no 'ask along' interaction.")
		return
	if not _companion.is_waiting():
		_failures.append("Q is not waiting, so the invitation cannot be tested: %s." % _state())
	if not ask.can_interact():
		_failures.append("Q cannot be asked along while it is waiting: %s." % _state())
	_interaction().request_activation(ask)
	var waited := 0
	while _companion.is_waiting() and waited < 600:
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		waited += 1
	if _companion.is_waiting():
		_failures.append("Q stayed in waiting mode after being asked along: %s." % _state())
		return
	var arrived := await _wait_until(
		func() -> bool:
			return _flat_distance(_companion.global_position, _player.global_position) \
				<= _companion.follow_distance + 0.6,
		15.0
	)
	if not arrived:
		_failures.append(
			"Q did not close the gap after being asked along: %s." % _state()
		)
	if _companion.get_repath_count() <= before:
		_failures.append("No new route was requested after being asked along: %s." % _state())
	if _closest_approach < 0.5:
		_failures.append(
			"Q and the player overlapped (closest approach %.2f m)." % _closest_approach
		)


# --- case 5: one Q ----------------------------------------------------------


## The authored Q in the classroom and the companion everywhere else, never both.
func _check_one_q_across_locations() -> void:
	await _enter(CLASSROOM, &"PlayerStart")
	var in_classroom := _count_visible_q()
	if in_classroom != 1:
		_failures.append("The classroom shows %d visible Q(s) instead of one." % in_classroom)
	if _companion.visible:
		_failures.append("The companion is visible in the classroom, where Q is authored.")
	await _enter(CORRIDOR, &"FromClassroom")
	if _count_visible_q() != 1:
		_failures.append("The corridor shows %d visible Q(s) instead of one." % _count_visible_q())
	if not _companion.visible:
		_failures.append("The companion did not come back in the corridor.")
	var gap := _flat_distance(_companion.global_position, _player.global_position)
	if gap > _companion.follow_distance + 1.0:
		_failures.append("Q is %.1f m behind after the transition instead of beside the player." % gap)


# --- helpers ----------------------------------------------------------------


func _interaction() -> InteractionController:
	return _player.get_node_or_null("InteractionController") as InteractionController


## Puts the player and Q on the walkway, builds the walls first, and only then lets Q
## start walking. Order matters: a wall that appears halfway through a chase has already
## been walked around.
func _stage(
	player_z: float,
	q_z: float,
	wall_positions: Array,
	wall_size: Vector3,
	bake_walls: bool
) -> void:
	_clean_up_walls()
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, player_z)))
	await _physics_frames(2)
	for position: Vector3 in wall_positions:
		_make_wall(position, wall_size)
	await _physics_frames(2)
	if bake_walls and not await _rebake():
		_failures.append("The corridor's navigation could not be re-baked around the walls.")
	_companion.global_position = Vector3(0.0, 0.0, q_z)
	_companion.velocity = Vector3.ZERO
	_trace.clear()
	_closest_approach = INF
	if _companion.is_waiting():
		_companion.resume_following()
	await _physics_frames(1)
	_record()


func _make_wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CompanionTestWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_location.add_child(body)
	body.global_position = position
	_walls.append(body)
	return body


## Re-bakes the current location's mesh so it knows about the walls just added. Without
## this, cases 1 and 2 would be the same test.
func _rebake() -> bool:
	var nav := _location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		return false
	if not nav.bake_region():
		return false
	var guard := 0
	while guard < 240:
		if nav.is_baked() and nav.is_routable():
			return true
		await physics_frame
		guard += 1
	return false


## Waits until the map can actually take Q to the player, rather than until the bake
## call returned: a path that ends short is the bake not having reached the map yet.
func _wait_for_a_route() -> bool:
	var guard := 0
	while guard < 240:
		var map := _companion.get_world_3d().navigation_map
		if map.is_valid():
			var path := NavigationServer3D.map_get_path(
				map, _companion.global_position, _player.global_position, true
			)
			if path.size() >= 2:
				var end: Vector3 = path[path.size() - 1]
				if _flat_distance(end, _player.global_position) <= 0.8:
					return true
		await physics_frame
		guard += 1
	return false


func _clean_up_walls() -> void:
	for wall: StaticBody3D in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()


func _count_visible_q() -> int:
	var count := 0
	for node: Node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor == null or String(actor.npc_id) != "q":
			continue
		if actor.is_visible_in_tree():
			count += 1
	return count


func _enter(scene: String, spawn: StringName) -> LocationRoot:
	if not _host.load_location(scene, spawn, _player):
		return null
	await _frames(3)
	await _physics_frames(2)
	var waited := 0
	while _player != null and not _player.is_control_enabled() and waited < 40:
		await _frames(1)
		waited += 1
	if _player != null and not _player.is_control_enabled():
		_sequence.allow_player_control()
		await _frames(3)
	var guard := 0
	while guard < 180:
		var current := _host.get_current()
		var nav: LocationNavigation = null
		if current != null:
			nav = current.get_node_or_null("Navigation") as LocationNavigation
		if nav != null and nav.is_baked() and nav.is_routable():
			break
		await physics_frame
		guard += 1
	_location = _host.get_current()
	return _location


func _record() -> void:
	if _trace.size() >= 16:
		return
	_trace.append(
		"z=%.2f d=%.2f route=%d v=%.2f"
		% [
			_companion.global_position.z,
			_flat_distance(_companion.global_position, _player.global_position),
			_companion.get_route().size(),
			_companion.velocity.z,
		]
	)


func _state() -> String:
	var walls := ""
	for wall: StaticBody3D in _walls:
		if is_instance_valid(wall):
			walls += " wall@%s" % str(wall.global_position)
	return (
		"q=(%.2f,%.2f) player=(%.2f,%.2f) visible=%s waiting=%s route=%d repath=%d"
		+ " nav=%s regions=%d walls=[%s] note='%s' trace=%s"
	) % [
		_companion.global_position.x, _companion.global_position.z,
		_player.global_position.x, _player.global_position.z,
		str(_companion.visible), str(_companion.is_waiting()),
		_companion.get_route().size(), _companion.get_repath_count(),
		str(_companion.is_navigation_ready()), _companion.get_navigation_region_count(),
		walls, _companion.get_last_chase_note(), str(_trace),
	]


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _wait_until(condition: Callable, limit_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	var sampled := 0
	while not condition.call():
		_closest_approach = minf(
			_closest_approach,
			_flat_distance(_companion.global_position, _player.global_position)
		)
		sampled += 1
		if sampled % 3 == 0:
			_record()
		await physics_frame
		if Time.get_ticks_msec() > deadline:
			return false
	return true


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
