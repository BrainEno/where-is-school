extends SceneTree
## Q follows the navigation route, and the walls are real.
##
## The bug this test was written for: the companion moved by writing `global_position`
## towards the player, so it walked through walls, fences and buildings. Following is now
## a route on the location's own navigation mesh, walked by a `CharacterBody3D`.
##
## The corridor is used because it is a long, straight walkway with a floor and two side
## walls: a wall placed across it cannot be mistaken for anything else.
##
## Cases:
##  1. a wall across the walkway that the mesh does not know about → Q's route runs
##     straight at it, the body stops, and Q ends up waiting rather than through it;
##  2. a wall with a gap, baked into the mesh → Q walks around and reaches the player,
##     and its route is longer than the straight line (proof that it went around);
##  3. a wall with no gap, baked in → there is no route, so Q stops and waits;
##  4. asked along afterwards → a fresh route is built and Q closes the gap;
##  5. Q never stands inside the player, and never both of them at once;
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
## guessing from where it ended up.
var _trace: Array[String] = []
var _trace_timer := 0.0


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
	_clean_up()

	Harness.finish(
		self, _failures,
		"Q walks the navigation route, is stopped by real walls, and waits when there is no way."
	)


# --- case 1: a wall the mesh does not know about -----------------------------


## The wall is added *after* the location baked, so the navigation mesh still believes
## the walkway is clear and Q's route runs straight through it. Only the body stops Q —
## which is the whole point of following a route with a physics body.
func _check_unknown_wall_stops_the_body() -> void:
	await _stage(6.0, 3.0)
	_make_wall(Vector3(0.0, 1.5, 4.5), Vector3(4.4, 3.0, 0.2))
	await _physics_frames(2)
	var crossed := await _wait_until(
		func() -> bool: return _companion.global_position.z < 4.4, 6.0
	)
	if crossed:
		_failures.append(
			"Q crossed a wall the body should have stopped it at: %s." % _state()
		)
	if _companion.global_position.z < 4.4:
		_failures.append("Q ended up on the far side of the wall (z=%.2f)." % _companion.global_position.z)
	if _companion.global_position.z > 4.4 and _companion.global_position.z < 4.6:
		_failures.append("Q is standing inside the wall (z=%.2f)." % _companion.global_position.z)
	await _wait_until(func() -> bool: return _companion.is_waiting(), 10.0)
	if not _companion.is_waiting():
		_failures.append("Q kept pressing at a wall instead of waiting: %s." % _state())
	_clean_up_walls()


# --- case 2: a wall with a gap, baked into the mesh --------------------------


## Two wall segments with a 1.6 m gap, baked into the navigation mesh: the route has to
## bend through the gap. Q reaching the player is the assertion; the measured route being
## longer than the straight line is the evidence that it did not go through the wall.
func _check_gap_is_walked_around() -> void:
	await _stage(5.0, 1.0)
	_make_wall(Vector3(-1.5, 1.5, 3.0), Vector3(1.4, 3.0, 0.2))
	_make_wall(Vector3(1.5, 1.5, 3.0), Vector3(1.4, 3.0, 0.2))
	if not await _rebake():
		_failures.append("The corridor's navigation could not be re-baked around the gap.")
		return
	await _physics_frames(2)
	var straight := _flat_distance(_companion.global_position, _player.global_position)
	var longest_route := 0.0
	var crossed_at_x := INF
	var crossed := false
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		longest_route = maxf(longest_route, _companion.get_route_length())
		if not crossed and _companion.global_position.z < 3.0:
			crossed = true
			crossed_at_x = _companion.global_position.x
		if _flat_distance(_companion.global_position, _player.global_position) <= 1.2:
			break
	var gap := _flat_distance(_companion.global_position, _player.global_position)
	if gap > _companion.follow_distance + 0.6:
		_failures.append(
			"Q did not walk around the wall through the gap (%.1f m from the player): %s."
			% [gap, _state()]
		)
	if not crossed:
		_failures.append("Q never reached the player's side of the wall.")
	elif absf(crossed_at_x) > 1.0:
		_failures.append(
			"Q crossed the wall line at x=%.2f, outside the 1.6 m gap." % crossed_at_x
		)
	if longest_route <= straight + 0.5:
		_failures.append(
			"The route Q walked was %.1f m for a %.1f m straight line: it was not a detour."
			% [longest_route, straight]
		)
	_clean_up_walls()


# --- case 3: no route at all -------------------------------------------------


## The wall goes all the way across and is baked in: the two halves of the walkway are
## separate islands, so there is no route. Q must stop and wait, not lean on the wall.
func _check_no_route_means_waiting() -> void:
	await _stage(5.0, 1.0)
	_make_wall(Vector3(0.0, 1.5, 3.0), Vector3(4.4, 3.0, 0.2))
	if not await _rebake():
		_failures.append("The corridor's navigation could not be re-baked around the wall.")
		return
	_companion.resume_following()
	var waited := await _wait_until(
		func() -> bool: return _companion.is_waiting(), 12.0
	)
	if not waited:
		_failures.append("With no route to the player, Q never settled into waiting: %s." % _state())
	if _companion.global_position.z < 3.0:
		_failures.append("Q got through a wall with no gap in it (z=%.2f)." % _companion.global_position.z)
	if _companion.is_walking_route():
		_failures.append("Q is still holding a route through a wall with no gap.")


# --- case 4: asked along afterwards -----------------------------------------


## Taking the wall out and asking Q along again has to rebuild the route: waiting is a
## pause, not a state Q is stuck in.
func _check_asked_along_rebuilds_the_route() -> void:
	var before := _companion.get_repath_count()
	_clean_up_walls()
	if not await _rebake():
		_failures.append("The corridor's navigation could not be restored.")
		return
	var ask := _main.get_node_or_null(^"Companion/AskAlong") as Interactable
	if ask == null:
		_failures.append("The companion has no 'ask along' interaction.")
		return
	if not ask.can_interact():
		_failures.append("Q cannot be asked along while it is waiting.")
	_interaction_for_ask().request_activation(ask)
	var waited := 0
	while _companion.is_waiting() and waited < 400:
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		waited += 1
	if _companion.is_waiting():
		_failures.append("Q stayed in waiting mode after being asked along.")
		return
	var arrived := await _wait_until(
		func() -> bool:
			return _flat_distance(_companion.global_position, _player.global_position) \
				<= _companion.follow_distance + 0.6,
		15.0
	)
	if not arrived:
		_failures.append(
			"Q did not close the gap after being asked along (%.1f m): %s."
			% [_flat_distance(_companion.global_position, _player.global_position), _state()]
		)
	if _companion.get_repath_count() <= before:
		_failures.append("No new route was requested after being asked along.")
	# The capsule keeps Q out of the player: two bodies cannot share a space.
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
	var in_corridor := _count_visible_q()
	if in_corridor != 1:
		_failures.append("The corridor shows %d visible Q(s) instead of one." % in_corridor)
	if not _companion.visible:
		_failures.append("The companion did not come back in the corridor.")
	await _enter(CORRIDOR, &"FromClassroom")
	if _count_visible_q() != 1:
		_failures.append("Coming back to the corridor left %d visible Q(s)." % _count_visible_q())


# --- helpers ----------------------------------------------------------------


func _interaction_for_ask() -> InteractionController:
	return _player.get_node_or_null("InteractionController") as InteractionController


## Puts Q behind the player, both standing on the walkway, with the player looking
## north so "behind" is a known direction.
func _stage(q_z: float, player_z: float) -> void:
	_clean_up_walls()
	_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(0.0, 0.0, player_z)))
	_companion.global_position = Vector3(0.0, 0.0, q_z)
	_companion.velocity = Vector3.ZERO
	_closest_approach = INF
	_trace.clear()
	if _companion.is_waiting():
		_companion.resume_following()
	await _physics_frames(3)
	# The player stands still for the wall cases: this is about the route, not about
	# the player running away.
	await _sample_approach(6)


func _sample_approach(frames: int) -> void:
	for _index in frames:
		await physics_frame
		_closest_approach = minf(
			_closest_approach,
			_flat_distance(_companion.global_position, _player.global_position)
		)


func _record() -> void:
	if _trace.size() >= 18:
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
## this, case 1 and case 2 would be the same test.
func _rebake() -> bool:
	var nav := _location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		return false
	if not nav.bake_region():
		return false
	var guard := 0
	while guard < 180:
		if nav.is_baked() and nav.is_routable():
			return true
		await physics_frame
		guard += 1
	return false


func _clean_up_walls() -> void:
	for wall: StaticBody3D in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()


func _clean_up() -> void:
	_clean_up_walls()


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


func _state() -> String:
	var walls := ""
	for wall: StaticBody3D in _walls:
		if not is_instance_valid(wall):
			continue
		var shape := wall.get_child(0) as CollisionShape3D
		var box := shape.shape as BoxShape3D if shape != null else null
		walls += " wall@%s size=%s" % [str(wall.global_position), str(box.size if box else Vector3.ZERO)]
	return (
		"q=(%.2f,%.2f) player=(%.2f,%.2f) visible=%s joined=%s waiting=%s route=%d repath=%d vel=(%.2f,%.2f) layer=%d mask=%d note='%s'"
		% [
			_companion.global_position.x, _companion.global_position.z,
			_player.global_position.x, _player.global_position.z,
			str(_companion.visible), str(_companion.is_joined()), str(_companion.is_waiting()),
			_companion.get_route().size(), _companion.get_repath_count(),
			_companion.velocity.x, _companion.velocity.z,
			_companion.collision_layer, _companion.collision_mask,
			_companion.get_last_chase_note(),
		]
	) + " nav_ready=%s regions=%d" % [
		str(_companion.is_navigation_ready()), _companion.get_navigation_region_count()
	] + walls + " trace=" + str(_trace)


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
		if sampled % 4 == 0:
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
