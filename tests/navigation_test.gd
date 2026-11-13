extends SceneTree
## Navigation data and click-to-move movement.
##
## The claims under test:
##
## 1. every playable location bakes a navigation mesh from its own geometry, and the
##    player's spawn is standing on it — a location with an empty mesh cannot be
##    navigated at all and that is a content error, not a runtime accident;
## 2. from the spawn you can actually reach *every* way out of the location, not just
##    "some point" and not just one door: a mesh that only covers the corner you spawn in
##    is useless, and an exit that stands off the mesh is a door painted on a wall;
## 3. an accepted destination is walked to with the real physics body, arrives, and
##    then stops — no drift and no oscillation once the character is there;
## 4. a point off the mesh is refused instead of being snapped or walked at;
## 5. an isolated island of floor (disconnected, no ramp) never lifts the character
##    onto it;
## 6. geometry added between the player and the destination is walked *around*: the
##    route bends and the body keeps its distance from the obstacle;
## 7. manual input cancels a walk, and a second destination replaces the first;
## 8. a location swap cancels everything, so nothing from the old room can be
##    activated later;
## 9. a body the map cannot help - pressed against something physical the map does not
##    know about - re-routes once and then gives up: one `path_cancelled`, no
##    `path_finished`, no budget handed back by the re-route itself, and a new request
##    gets its own re-route (#145);
## 10. a walk following a route that no longer fits the room (the map was re-baked under
##    it) stalls, re-routes once from where the body stands, and arrives.

const Harness = preload("res://tests/test_harness.gd")

const LOCATIONS: Array[Dictionary] = [
	{"scene": "res://scenes/locations/classroom/classroom.tscn", "spawn": &"PlayerStart", "name": "classroom"},
	{"scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": &"FromClassroom", "name": "corridor"},
	{"scene": "res://scenes/locations/street/street.tscn", "spawn": &"FromCorridor", "name": "street"},
	{"scene": "res://scenes/locations/residential/residential.tscn", "spawn": &"FromStreet", "name": "residential"},
	{"scene": "res://scenes/locations/alley/alley.tscn", "spawn": &"FromCourtyard", "name": "alley"},
	{"scene": "res://scenes/locations/playground/playground.tscn", "spawn": &"FromAlley", "name": "playground"},
]

const WALK_LIMIT_SECONDS := 14.0
## A physics layer the player collides with (`player.tscn`: mask 5 = layers 1 and 3) that
## neither the navigation bake (`LocationNavigation.geometry_collision_mask`, 25), the
## interaction occluders (9) nor the click ground ray (1) reads: a body on it is a wall
## for the character and nothing at all for the map.
const PHYSICS_ONLY_LAYER := 4

var _failures: Array[String] = []
## Where the body was during the last walk, sampled for failure messages.
var _walk_trail: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null
var _finished := 0
var _cancelled := 0
var _rerouted := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 260.0, "navigation_test.gd")
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
	await _frames(2)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _host == null or _player == null:
		Harness.finish(self, ["Main did not expose the host and the player."], "")
		return
	if _sequence != null:
		_sequence.allow_player_control()

	# The passive inner voice can open its own conversation at any time, which would
	# lock the player mid-walk and make these timings a race. It is switched off here;
	# it has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	_player.path_finished.connect(func() -> void: _finished += 1)
	_player.path_cancelled.connect(func() -> void: _cancelled += 1)
	# Connected by name: the signal is what this file asks the controller to report, and a
	# controller without it is a failure to name, not a script error to crash on.
	if _player.has_signal(&"path_rerouted"):
		_player.connect(&"path_rerouted", func() -> void: _rerouted += 1)
	Engine.time_scale = 4.0
	await _frames(2)

	await _check_every_location_has_a_usable_mesh()
	await _check_walk_arrives_and_stops()
	await _check_off_mesh_is_refused()
	await _check_isolated_island_is_not_reached()
	await _check_obstacle_is_walked_around()
	await _check_manual_input_cancels()
	await _check_second_destination_replaces_the_first()
	await _check_location_swap_clears_the_walk()
	await _check_permanent_block_gives_up()
	await _check_stale_route_recovers_with_one_reroute()

	Harness.finish(
		self, _failures,
		"every location bakes a usable mesh, and clicked movement walks, arrives, stops and yields to input."
	)


# --- cases ------------------------------------------------------------------


func _check_every_location_has_a_usable_mesh() -> void:
	for entry: Dictionary in LOCATIONS:
		var location := await _enter(String(entry["scene"]), entry["spawn"])
		var label := String(entry["name"])
		if location == null:
			_failures.append("The %s could not be loaded." % label)
			continue
		var nav := _nav_of(location)
		if nav == null:
			_failures.append("The %s has no Navigation region." % label)
			continue
		if not nav.is_baked():
			_failures.append(
				"The %s never finished baking (%s) %s" % [label, nav.get_bake_error(), _report(nav)]
			)
			continue
		if nav.get_polygon_count() <= 0:
			_failures.append("The %s baked no walkable polygons %s" % [label, _report(nav)])
			continue
		# A baked mesh is useless unless the map actually holds it; zero regions means
		# every path query in this room will come back empty.
		var registered := nav.get_map_region_count() > 0
		var wait_frames := 0
		while not registered and wait_frames < 30:
			await process_frame
			wait_frames += 1
			registered = nav.get_map_region_count() > 0
		if not registered:
			_failures.append(
				"In the %s the baked mesh never reached the navigation map %s" % [label, _report(nav)]
			)
			continue
		var closest := _closest_point(_player.global_position)
		var offset := Vector2(closest.x - _player.global_position.x, closest.z - _player.global_position.z).length()
		if offset > 1.2:
			_failures.append(
				"In the %s the spawn %s is %.2f m off the navigation mesh (closest %s) %s"
				% [label, str(_player.global_position), offset, str(closest), _report(nav)]
			)
		# Every way out, not just one: a location whose only reachable exit is the way back
		# is a room the player can get stuck in. This is also what holds the courtyard's
		# alley exit to being walkable rather than merely present (issue #33).
		for exit in _exits_of(location):
			if exit.is_milestone_end:
				continue
			var snapped := _closest_point(exit.global_position)
			var away := Vector2(
				snapped.x - exit.global_position.x, snapped.z - exit.global_position.z
			).length()
			if away > 1.5:
				_failures.append(
					"In the %s the exit '%s' at %s is %.2f m off the navigation mesh (closest %s) %s"
					% [
						label, String(exit.interact_id), str(exit.global_position), away,
						str(snapped), _report(nav)
					]
				)
				continue
			var route := NavigationServer3D.map_get_path(
				_player.navigation_agent.get_navigation_map(),
				_closest_point(_player.global_position), snapped, true
			)
			if route.size() < 2:
				_failures.append(
					"In the %s the exit '%s' at %s cannot be walked to from the spawn %s %s"
					% [
						label, String(exit.interact_id), str(exit.global_position),
						str(_player.global_position), _report(nav)
					]
				)


## The walk itself, in the classroom: pick the farthest reachable destination within
## 6 m, walk there with the real body, and check it arrives, stops, and stays put.
func _check_walk_arrives_and_stops() -> void:
	var location := await _enter(LOCATIONS[0]["scene"], LOCATIONS[0]["spawn"])
	if location == null:
		return
	var destination: Variant = _farthest_reachable(_player.global_position, 6.0)
	if destination == null:
		_failures.append("No reachable destination within 6 m of the classroom spawn.")
		return
	var start := _player.global_position
	if not _player.request_path_to(destination):
		_failures.append("A reachable destination was refused.")
		return
	if not _player.is_path_active():
		_failures.append("An accepted destination did not start a walk.")
		return
	var arrived := await _walk_until_settled(WALK_LIMIT_SECONDS)
	if not arrived:
		_failures.append(
			"The walk did not finish within %.0f s: from %s to %s, position %s, %s"
			% [
				WALK_LIMIT_SECONDS, str(start), str(destination), str(_player.global_position),
				_walk_state(_nav_of(_location))
			]
		)
		return
	var travelled := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	if travelled < 2.0:
		_failures.append("The character only moved %.2f m to a destination 6 m away." % travelled)
	var gap := Vector2(
		_player.global_position.x - destination.x, _player.global_position.z - destination.z
	).length()
	if gap > 1.0:
		_failures.append("The character stopped %.2f m short of the destination." % gap)
	if _player.global_position.y < -1.0:
		_failures.append("The character left the floor while walking (y = %.2f)." % _player.global_position.y)
	# Let the body come to rest first: slowing to a stop after arrival is stopping, not
	# drift. Then standing still has to mean standing still.
	await _physics_frames(10)
	var before := _player.global_position
	var largest := 0.0
	for _index in 20:
		await physics_frame
		largest = maxf(largest, _player.global_position.distance_to(before))
		before = _player.global_position
	if largest > 0.05:
		_failures.append("The character kept drifting %.3f m per step after arriving." % largest)
	if _player.is_path_active():
		_failures.append("The walk stayed active after arriving.")


func _check_off_mesh_is_refused() -> void:
	var location := await _enter(LOCATIONS[0]["scene"], LOCATIONS[0]["spawn"])
	if location == null:
		return
	await _frames(2)
	var before := _player.global_position
	for offset: Vector3 in [
		Vector3(0.0, 12.0, 0.0),   # in the air above the room
		Vector3(40.0, 0.0, 0.0),   # outside the building
	]:
		if _player.request_path_to(_player.global_position + offset):
			_failures.append("A destination %.0f m off the mesh was accepted." % offset.length())
	if _player.is_path_active():
		_failures.append("A refused destination still started a walk.")
	if _player.global_position.distance_to(before) > 0.2:
		_failures.append("A refused destination moved the character.")


## A disconnected slab of floor three metres up: walkable in principle, unreachable in
## practice. Whatever the path query answers, the character must not end up on it.
func _check_isolated_island_is_not_reached() -> void:
	var location := await _enter(LOCATIONS[3]["scene"], LOCATIONS[3]["spawn"])
	if location == null:
		return
	var nav := _nav_of(location)
	if nav == null:
		return
	var island_center := _player.global_position + Vector3(4.0, 3.0, 0.0)
	_add_slab(location, island_center, Vector3(3.0, 0.2, 3.0), "IslandSlab")
	await _rebake(nav)
	_player.request_path_to(island_center + Vector3(0.0, 0.9, 0.0))
	await _frames(2)
	var deadline := Time.get_ticks_msec() + 6000
	while _player.is_path_active() and Time.get_ticks_msec() < deadline:
		await physics_frame
	if _player.global_position.y > 1.6:
		_failures.append(
			"The character climbed onto an island it cannot reach (y = %.2f)." % _player.global_position.y
		)
	if _player.is_path_active():
		var legs := _player.get_path_legs()
		var stuck_at := _player.global_position
		_player.cancel_path()
		_failures.append(
			"The walk to an unreachable island never stopped: island at %s, body at %s, route %s."
			% [str(island_center), str(stuck_at), str(legs)]
		)
	_remove_node(location, "IslandSlab")
	await _rebake(nav)


## A wall straight between the player and a destination. The route has to bend, and the
## body has to keep clear of the wall instead of grinding through it.
func _check_obstacle_is_walked_around() -> void:
	var location := await _enter(LOCATIONS[2]["scene"], LOCATIONS[2]["spawn"])
	if location == null:
		return
	var nav := _nav_of(location)
	if nav == null:
		_failures.append("The street has no navigation region.")
		return
	var destination: Variant = _farthest_reachable(_player.global_position, 8.0)
	if destination == null:
		_failures.append("The street offered no reachable destination 8 m away.")
		return
	var start := _player.global_position
	var dest: Vector3 = destination
	var to_target := dest - start
	to_target.y = 0.0
	if to_target.length() < 4.0:
		_failures.append("The street destination was too close to test a detour.")
		return
	var direction := to_target.normalized()
	var wall_center := start + direction * (to_target.length() * 0.5)
	var across := Vector3(-direction.z, 0.0, direction.x)
	var wall_half_length := 2.5
	var wall := _add_slab(location, wall_center + Vector3.UP * 1.0, Vector3(0.3, 2.0, wall_half_length * 2.0), "ProbeWall")
	# The slab is thin across and long along its own Z; turning it so that long axis
	# lies across the route makes it a wall, not a kerb beside the path.
	wall.rotation.y = atan2(across.x, across.z)
	await _rebake(nav)
	if not _player.request_path_to(destination):
		_failures.append("The destination behind a wall with room around it was refused.")
		_remove_node(location, "ProbeWall")
		await _rebake(nav)
		return
	var path := NavigationServer3D.map_get_path(
		nav.get_navigation_map(), _player.global_position, destination, true
	)
	if path.size() < 3:
		_failures.append("The route past an obstacle had only %d waypoint(s); it did not bend." % path.size())
	var closest := INF
	var deadline := Time.get_ticks_msec() + int(WALK_LIMIT_SECONDS * 1000.0)
	while _player.is_path_active() and Time.get_ticks_msec() < deadline:
		await physics_frame
		closest = minf(closest, _distance_to_wall(_player.global_position, wall_center, across, wall_half_length))
	var gap := Vector2(
		_player.global_position.x - destination.x, _player.global_position.z - destination.z
	).length()
	if gap > 1.2:
		# Two different faults look the same from here: a wall the bake sealed the route
		# behind, and a body that could not follow a route the map is still happy to hand
		# out. Asking the map for the same route now separates them, so the next run does
		# not have to guess which half lied.
		var map := _player.navigation_agent.get_navigation_map()
		var from_now := NavigationServer3D.map_get_closest_point(map, _player.global_position)
		var to_now := NavigationServer3D.map_get_closest_point(map, destination)
		var now_path := NavigationServer3D.map_get_path(map, from_now, to_now, true)
		var now_end := from_now
		if not now_path.is_empty():
			now_end = now_path[now_path.size() - 1]
		var now_short := now_end.distance_to(destination)
		_failures.append(
			"The character did not reach the far side of the obstacle (%.2f m short, map "
			% gap
			+ "path now: %d point(s) ending %.2f m from the target) %s"
			% [now_path.size(), now_short, _walk_state(nav)]
		)
	if closest < 0.45:
		_failures.append("The character walked %.2f m from the wall's face instead of around it." % closest)
	_remove_node(location, "ProbeWall")
	await _rebake(nav)


func _check_manual_input_cancels() -> void:
	var location := await _enter(LOCATIONS[0]["scene"], LOCATIONS[0]["spawn"])
	if location == null:
		return
	var destination: Variant = _farthest_reachable(_player.global_position, 6.0)
	if destination == null or not _player.request_path_to(destination):
		_failures.append("Could not start a walk for the cancel check.")
		return
	_cancelled = 0
	Input.action_press("move_forward")
	await _physics_frames(2)
	Input.action_release("move_forward")
	if _player.is_path_active():
		_failures.append("Holding a movement key did not cancel the automatic walk.")
	if _cancelled == 0:
		_failures.append("Cancelling the walk emitted no path_cancelled signal.")
	await _frames(2)


func _check_second_destination_replaces_the_first() -> void:
	var location := await _enter(LOCATIONS[0]["scene"], LOCATIONS[0]["spawn"])
	if location == null:
		return
	var first: Variant = _farthest_reachable(_player.global_position, 6.0)
	if first == null or not _player.request_path_to(first):
		_failures.append("Could not start the first walk.")
		return
	var second: Variant = _farthest_reachable(_player.global_position, 6.0, first)
	if second == null:
		_failures.append("No second destination existed for the replace check.")
		return
	if not _player.request_path_to(second):
		_failures.append("A second destination was refused while a walk was running.")
		return
	var target := _player.get_path_target()
	if Vector2(target.x - second.x, target.z - second.z).length() > 1.0:
		_failures.append("The second destination did not replace the first.")
		return
	await _walk_until_settled(WALK_LIMIT_SECONDS)
	var gap := Vector2(
		_player.global_position.x - second.x, _player.global_position.z - second.z
	).length()
	if gap > 1.2:
		_failures.append("The character walked towards the replaced destination (%.2f m short)." % gap)


func _check_location_swap_clears_the_walk() -> void:
	var location := await _enter(LOCATIONS[0]["scene"], LOCATIONS[0]["spawn"])
	if location == null:
		return
	var destination: Variant = _farthest_reachable(_player.global_position, 6.0)
	if destination != null:
		_player.request_path_to(destination)
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	var moved := await _enter(LOCATIONS[2]["scene"], LOCATIONS[2]["spawn"])
	if moved == null:
		_failures.append("The street could not be entered for the swap check.")
		return
	if _player.is_path_active():
		_failures.append("A walk survived a location change.")
	if navigator != null and navigator.get_pending_target() != null:
		_failures.append("A clicked target survived a location change.")
	await _physics_frames(4)
	if _player.global_position.y < -1.0:
		_failures.append("The character fell through the street floor after the swap.")


## A wall across a straight route that only physics knows about. The map keeps handing
## out the same straight route through it - before and after the wall, from the start and
## from the wall's face - and the body really walks into it with `move_and_slide()`.
## The walk may re-route once, and the fresh route stalls the same way; then it has to end,
## however long it is left to run.
func _check_permanent_block_gives_up() -> void:
	var location := await _enter(LOCATIONS[2]["scene"], LOCATIONS[2]["spawn"])
	if location == null:
		return
	var nav := _nav_of(location)
	if nav == null:
		_failures.append("permanent block: the street has no navigation region.")
		return
	var map := _player.navigation_agent.get_navigation_map()
	var start := _player.global_position
	var destination: Variant = _straight_destination(start, 5.0, 8.0)
	if destination == null:
		_failures.append("permanent block: the street has no straight 5-8 m route from the spawn.")
		return
	var dest: Vector3 = destination
	var direction := Vector3(dest.x - start.x, 0.0, dest.z - start.z).normalized()
	var wall_center := start + direction * 2.2
	var wall := _add_slab(location, wall_center + Vector3.UP * 1.0, Vector3(0.3, 2.0, 4.0), "PhysicsOnlyWall")
	wall.rotation.y = atan2(direction.x, direction.z)
	wall.collision_layer = PHYSICS_ONLY_LAYER
	wall.collision_mask = 0
	await _physics_frames(3)

	# The fixture, proved before the walk: the wall is a wall for the body, the map does
	# not know it is there, and the route still runs straight through it.
	if (_player.collision_mask & PHYSICS_ONLY_LAYER) == 0:
		_failures.append("permanent block: the player does not collide with the probe wall's layer.")
	if (nav.geometry_collision_mask & PHYSICS_ONLY_LAYER) != 0:
		_failures.append("permanent block: the bake would read the probe wall's layer.")
	var route := NavigationServer3D.map_get_path(map, start, dest, true)
	if route.size() != 2:
		_failures.append(
			"permanent block: with the wall in place the map's route has %d points; it is "
			% route.size() + "supposed to run straight through a wall the map does not know."
		)
	var ray := PhysicsRayQueryParameters3D.create(
		start + Vector3.UP * 0.9, dest + Vector3.UP * 0.9, _player.collision_mask
	)
	ray.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.get("collider") != wall:
		_failures.append("permanent block: the wall does not stand across the route (%s)." % str(hit))

	for attempt in ["the first request", "a new request after giving up"]:
		var report := await _walk_into_block(dest, wall_center, direction, String(attempt))
		if report.is_empty():
			break
	_remove_node(location, "PhysicsOnlyWall")
	await _physics_frames(2)


## One requested walk into the probe wall, watched for four stall timeouts and then some.
## Returns an empty Dictionary when the walk could not even start.
func _walk_into_block(
	dest: Vector3, wall_center: Vector3, direction: Vector3, attempt: String
) -> Dictionary:
	var label := "permanent block, %s" % attempt
	_finished = 0
	_cancelled = 0
	_rerouted = 0
	if not _player.request_path_to(dest):
		_failures.append("%s: the map's straight route was refused." % label)
		return {}
	if not _player.is_path_active():
		_failures.append("%s: the accepted request started no walk." % label)
		return {}
	var budget := int(_player.get("_stall_repaths_left"))
	if budget != 1:
		_failures.append("%s: a requested walk starts with %d re-route(s), not 1." % [label, budget])

	var watch := _player.stall_timeout * 4.0 + 2.0
	var timer := create_timer(watch, true, true)
	var real_deadline := Time.get_ticks_msec() + 20000
	var started_ms := Time.get_ticks_msec()
	var cancelled_after := -1.0
	# Re-routes are also counted from the outside, without the signal: a stalled body's
	# no-progress clock only climbs, so a clock that drops back while the body has not
	# moved is the stall branch starting a fresh route. Each one is checked for what it
	# left in the budget - nobody asks for a new walk inside this loop, so anything
	# above zero is a re-route that paid for itself.
	var stall_restarts := 0
	var refills := 0
	var previous_clock := 0.0
	var previous_position := _player.global_position
	var deepest := -INF
	while timer.time_left > 0.0 and Time.get_ticks_msec() < real_deadline:
		await physics_frame
		var active := _player.is_path_active()
		var clock := float(_player.get("_path_progress_elapsed"))
		var still := _player.global_position.distance_to(previous_position) <= 0.01
		if active and still and previous_clock > _player.stall_timeout * 0.5 and clock < previous_clock:
			stall_restarts += 1
			if int(_player.get("_stall_repaths_left")) > 0:
				refills += 1
		previous_clock = clock if active else 0.0
		previous_position = _player.global_position
		var along := (_player.global_position - wall_center).dot(direction)
		deepest = maxf(deepest, along)
		if cancelled_after < 0.0 and _cancelled > 0:
			cancelled_after = float(Time.get_ticks_msec() - started_ms) / 1000.0 * Engine.time_scale

	var still_walking := _player.is_path_active()
	var legs := _player.get_path_legs()
	var index := _player.get_path_index()
	var left := int(_player.get("_stall_repaths_left"))
	var agent_gap := Vector2(
		_player.navigation_agent.target_position.x - _player.global_position.x,
		_player.navigation_agent.target_position.z - _player.global_position.z
	).length()
	var to_target := Vector2(
		_player.global_position.x - dest.x, _player.global_position.z - dest.z
	).length()
	var state := "rerouted=%d stall_restarts=%d cancelled=%d finished=%d refills=%d active=%s at %s" % [
		_rerouted, stall_restarts, _cancelled, _finished, refills, str(still_walking),
		str(_player.global_position)
	]

	# It really walked into the wall, and the wall really held.
	if deepest < -0.9:
		_failures.append("%s: the body never reached the wall (closest %.2f m from it). %s" % [
			label, -deepest, state
		])
	if deepest > 0.0:
		_failures.append("%s: the body got %.2f m past the wall's middle. %s" % [label, deepest, state])
	if to_target < 1.0:
		_failures.append("%s: the body reached a target behind a wall. %s" % [label, state])
	# The contract: one re-route, then the walk ends - once, as a cancellation.
	if still_walking:
		_failures.append(
			"%s: the walk was still running %.1f s (four stall timeouts) after it started. %s"
			% [label, watch, state]
		)
		_player.cancel_path()
	if stall_restarts != 1:
		_failures.append(
			"%s: the stalled walk started %d fresh route(s); one is allowed. %s"
			% [label, stall_restarts, state]
		)
	if refills > 0:
		_failures.append("%s: the re-route handed the budget back %d time(s). %s" % [label, refills, state])
	if not _player.has_signal(&"path_rerouted"):
		_failures.append("%s: PlayerController reports no re-route (no path_rerouted signal)." % label)
	elif _rerouted != 1:
		_failures.append("%s: %d re-routes instead of exactly one. %s" % [label, _rerouted, state])
	if _cancelled != 1 and not still_walking:
		_failures.append("%s: path_cancelled fired %d times. %s" % [label, _cancelled, state])
	if _finished != 0:
		_failures.append("%s: a walk that never arrived reported path_finished. %s" % [label, state])
	if cancelled_after >= 0.0 and cancelled_after < _player.stall_timeout * 1.8:
		_failures.append(
			"%s: the walk ended %.2f s in, before it could have stalled twice. %s"
			% [label, cancelled_after, state]
		)
	if not still_walking:
		if not legs.is_empty() or index != 0 or left != 0:
			_failures.append("%s: the ended walk kept legs=%d index=%d re-routes=%d." % [
				label, legs.size(), index, left
			])
		if agent_gap > 0.3:
			_failures.append(
				"%s: the agent still aims %.2f m away from the body after the walk ended." % [label, agent_gap]
			)
	# And nothing keeps pushing the body into the wall afterwards.
	var before := _player.global_position
	await _physics_frames(20)
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
	if horizontal > 0.05 or _player.global_position.distance_to(before) > 0.05:
		_failures.append("%s: the body still moves (%.2f m/s) after the walk ended." % [label, horizontal])
	if _cancelled > 1:
		_failures.append("%s: path_cancelled fired again after the walk ended (%d)." % [label, _cancelled])
	return {"rerouted": _rerouted, "cancelled": _cancelled}


## A walk whose route the room has outgrown: the request is answered with a straight
## route, then - before the body takes a step - a wall goes up across it and the map is
## re-baked around the wall. The body walks the old route into the wall, stalls, asks the
## map again from where it stands, and the fresh route goes round. One re-route, then
## `path_finished`; no cancellation. This is what the re-route is for, and the fix for
## #145 must not take it away.
func _check_stale_route_recovers_with_one_reroute() -> void:
	var location := await _enter(LOCATIONS[2]["scene"], LOCATIONS[2]["spawn"])
	if location == null:
		return
	var nav := _nav_of(location)
	if nav == null:
		return
	var start := _player.global_position
	var destination: Variant = _straight_destination(start, 5.0, 8.0)
	if destination == null:
		_failures.append("stale route: the street has no straight 5-8 m route from the spawn.")
		return
	var dest: Vector3 = destination
	var direction := Vector3(dest.x - start.x, 0.0, dest.z - start.z).normalized()
	var across := Vector3(-direction.z, 0.0, direction.x)
	var wall_center := start + direction * 2.2
	var half_length := 1.5
	_finished = 0
	_cancelled = 0
	_rerouted = 0
	if not _player.request_path_to(dest):
		_failures.append("stale route: the straight route was refused.")
		return
	# Held in place while the room changes, so the walk is following the old route.
	_player.set_physics_process(false)
	var wall := _add_slab(
		location, wall_center + Vector3.UP * 1.0, Vector3(0.3, 2.0, half_length * 2.0), "StaleRouteWall"
	)
	wall.rotation.y = atan2(direction.x, direction.z)
	await _rebake(nav)
	var fresh := NavigationServer3D.map_get_path(
		_player.navigation_agent.get_navigation_map(), _player.global_position, dest, true
	)
	if fresh.size() < 3:
		_failures.append("stale route: the re-baked map still routes straight (%d points)." % fresh.size())
	if _player.get_path_legs().size() != 2:
		_failures.append(
			"stale route: the walk is not following the old straight route (%d legs)."
			% _player.get_path_legs().size()
		)
	_player.set_physics_process(true)
	var closest := INF
	var deadline := Time.get_ticks_msec() + int(WALK_LIMIT_SECONDS * 1000.0)
	while _player.is_path_active() and Time.get_ticks_msec() < deadline:
		await physics_frame
		closest = minf(closest, _distance_to_wall(_player.global_position, wall_center, across, half_length))
	var state := "rerouted=%d cancelled=%d finished=%d at %s" % [
		_rerouted, _cancelled, _finished, str(_player.global_position)
	]
	if _player.is_path_active():
		_player.cancel_path()
		_failures.append("stale route: the walk did not end within %.0f s. %s" % [WALK_LIMIT_SECONDS, state])
	var gap := Vector2(_player.global_position.x - dest.x, _player.global_position.z - dest.z).length()
	if gap > 1.2:
		_failures.append("stale route: the body stopped %.2f m short of the target. %s" % [gap, state])
	if _finished != 1 or _cancelled != 0:
		_failures.append("stale route: the recovered walk did not end with one path_finished. %s" % state)
	if not _player.has_signal(&"path_rerouted"):
		_failures.append("stale route: PlayerController reports no re-route (no path_rerouted signal).")
	elif _rerouted != 1:
		_failures.append("stale route: %d re-routes instead of exactly one. %s" % [_rerouted, state])
	if closest < 0.3:
		_failures.append("stale route: the body went %.2f m from the wall's middle, i.e. through it." % closest)
	_remove_node(location, "StaleRouteWall")
	await _rebake(nav)


# --- helpers ----------------------------------------------------------------


func _enter(scene: String, spawn: StringName) -> LocationRoot:
	if not _host.load_location(scene, spawn, _player):
		return null
	await _frames(3)
	await _physics_frames(2)
	# The bake is deferred to the end of the load; wait for it rather than guessing. A baked
	# mesh is not enough: the map has to be answering for *this* room's geometry, which is
	# what `is_synchronized()` decides - baked, synchronized at least once, this region on
	# the map, and every spread probe of the mesh answered by it.
	_location = _host.get_current()
	var nav := _nav_of(_location)
	if nav == null:
		return _location
	if not await nav.wait_until_synchronized():
		_failures.append(
			"the %s's navigation map never synchronized with its baked mesh: %s"
			% [String(_location.location_id), nav.describe_sync()]
		)
	return _location


## Bakes the region and waits until the map is answering from the *new* polygons.
##
## Two conditions, because they are two different facts: the map must have been rebuilt
## since the bake (`map_get_iteration_id()` moved), and it must be answering for this
## room's mesh (`is_synchronized()`). A re-bake changes the surface under the same region,
## so an iteration that has not moved is the server still holding the wall-less mesh.
func _rebake(nav: LocationNavigation) -> void:
	if nav == null:
		return
	var map := _player.navigation_agent.get_navigation_map()
	var before := nav.get_map_iteration_id()
	nav.bake_region()
	for _frame in 90:
		await physics_frame
		if nav.get_map_iteration_id() > before and nav.is_synchronized():
			return
	if not nav.is_synchronized():
		_failures.append(
			"the %s's re-baked mesh never became the map's surface: %s"
			% [String(_location.location_id) if _location != null else "<none>", nav.describe_sync()]
		)


func _nav_of(location: LocationRoot) -> LocationNavigation:
	if location == null:
		return null
	return location.get_node_or_null("Navigation") as LocationNavigation


## A compact description of a location's navigation state, included in failure
## messages so a CI log says *why* a mesh is unusable without a second run.
func _report(nav: LocationNavigation) -> String:
	if nav == null:
		return "[no navigation region]"
	var map := nav.get_navigation_map()
	var mesh: NavigationMesh = nav.navigation_mesh
	var polygons := nav.get_polygon_count()
	var vertices := 0
	var bounds := "none"
	if mesh != null:
		var points := mesh.get_vertices()
		vertices = points.size()
		if vertices > 0:
			var box := AABB(points[0], Vector3.ZERO)
			for point in points:
				box = box.expand(point)
			bounds = "%s..%s" % [str(box.position), str(box.end)]
	var regions := NavigationServer3D.map_get_regions(map).size() if map.is_valid() else -1
	var cell := "?"
	if map.is_valid() and NavigationServer3D.has_method("map_get_cell_size"):
		cell = str(NavigationServer3D.map_get_cell_size(map))
	var mesh_cell := str(mesh.cell_size) if mesh != null else "?"
	return "[faces=%d region_pos=%s polygons=%d vertices=%d bounds=%s map_regions=%d map_cell=%s mesh_cell=%s agent_radius=%.2f]" % [
		nav.get_geometry_face_count(), str(nav.global_position), polygons, vertices, bounds,
		regions, cell, mesh_cell, nav.agent_radius
	]


func _closest_point(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(_player.navigation_agent.get_navigation_map(), point)


## The farthest point that is both on the mesh and has a real route to it. Layout
## independent on purpose: the test does not encode where the furniture is.
func _farthest_reachable(origin: Vector3, max_distance: float, avoid: Variant = null) -> Variant:
	var map := _player.navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_regions(map).is_empty():
		return null
	var best: Vector3 = Vector3.ZERO
	var best_distance := 0.0
	# The mesh's own height where the player stands, so "the same floor" is measured in the
	# mesh's terms rather than in the body's: a bake puts polygons a little above the
	# collider they were made from, and that offset is the same everywhere in a room.
	var floor_y := NavigationServer3D.map_get_closest_point(map, origin).y
	for radius in [max_distance, max_distance * 0.75, max_distance * 0.5]:
		for index in 24:
			var angle := TAU * float(index) / 24.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.4:
				continue
			# Same floor: the navigation mesh is allowed to promise a 0.3 m climb (a kerb,
			# a fire step), and the body has no step-up, so a destination behind a kerb is
			# a route the character walks into and grinds against - which is a different
			# claim from the one this file makes about walking around obstacles. Picking a
			# destination on the ground the player already stands on keeps every walk here
			# about the walk.
			if absf(snapped.y - floor_y) > 0.15:
				continue
			if avoid != null and Vector2(snapped.x - avoid.x, snapped.z - avoid.z).length() < 1.5:
				continue
			var path := NavigationServer3D.map_get_path(map, origin, snapped, true)
			if path.size() < 2:
				continue
			var reach := Vector2(snapped.x - origin.x, snapped.z - origin.z).length()
			if reach > best_distance:
				best_distance = reach
				best = snapped
		if best_distance > 0.5:
			return Vector3(best.x, origin.y + 0.05, best.z)
	return null


## The farthest on-mesh point, on the same floor, that the map reaches in one straight
## leg (a two-point route) from `origin`, between `min_distance` and `max_distance` away.
## A straight route is what makes a wall across it a wall across *the* route.
func _straight_destination(origin: Vector3, min_distance: float, max_distance: float) -> Variant:
	var map := _player.navigation_agent.get_navigation_map()
	var floor_y := NavigationServer3D.map_get_closest_point(map, origin).y
	var best: Variant = null
	var best_distance := 0.0
	for index in 48:
		var angle := TAU * float(index) / 48.0
		for radius in [max_distance, (min_distance + max_distance) * 0.5, min_distance]:
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.3:
				continue
			if absf(snapped.y - floor_y) > 0.1:
				continue
			var path := NavigationServer3D.map_get_path(map, origin, snapped, true)
			if path.size() != 2:
				continue
			var reach := Vector2(snapped.x - origin.x, snapped.z - origin.z).length()
			if reach >= min_distance and reach > best_distance:
				best_distance = reach
				best = Vector3(snapped.x, origin.y + 0.05, snapped.z)
			break
	return best


## Every exit the location declares, in tree order.
func _exits_of(location: LocationRoot) -> Array[LocationExit]:
	var found: Array[LocationExit] = []
	for node in location.get_tree().get_nodes_in_group("location_exit"):
		var exit := node as LocationExit
		if exit != null and location.is_ancestor_of(exit):
			found.append(exit)
	return found


func _walk_until_settled(limit_seconds: float) -> bool:
	_walk_trail.clear()
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	var frames := 0
	while _player.is_path_active():
		await physics_frame
		frames += 1
		if frames % 40 == 0:
			_walk_trail.append(
				"(%0.1f,%0.1f|legs=%d|leg=%d)"
				% [
					_player.global_position.x, _player.global_position.z,
					_player.get_path_legs().size(), _player.get_path_index()
				]
			)
		if Time.get_ticks_msec() > deadline:
			_player.cancel_path()
			return false
	return true


## What the walk was doing when it went wrong: the agent's next point, whether it
## thinks it is finished, the first waypoints, and where the body actually went.
func _walk_state(nav: LocationNavigation) -> String:
	var path := _player.get_path_legs()
	var waypoints := ""
	for index in mini(path.size(), 5):
		waypoints += "(%.1f,%.1f,%.1f)" % [path[index].x, path[index].y, path[index].z]
	var trail := ""
	for entry in _walk_trail:
		trail += entry
	return "[target=%s leg=%d path=%d %s active=%s trail=%s %s]" % [
		str(_player.get_path_target()), _player.get_path_index(), path.size(), waypoints,
		str(_player.is_path_active()), trail, _report(nav)
	]


func _add_slab(location: LocationRoot, center: Vector3, size: Vector3, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	location.add_child(body)
	body.global_position = center
	return body


func _remove_node(location: LocationRoot, node_name: String) -> void:
	var node := location.get_node_or_null(NodePath(node_name))
	if node != null:
		location.remove_child(node)
		node.queue_free()


## Distance from a point to the face of the probe wall, measured across the wall's
## width. A body that went through the wall reports a value near zero.
func _distance_to_wall(point: Vector3, center: Vector3, across: Vector3, half_length: float) -> float:
	var offset := point - center
	offset.y = 0.0
	var along := absf(offset.dot(across))
	var through := absf(offset.dot(Vector3(across.z, 0.0, -across.x)))
	if along > half_length:
		return 0.45  # past the end of the wall: the body legitimately went around
	return through


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
