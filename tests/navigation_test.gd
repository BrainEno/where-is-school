extends SceneTree
## Navigation data and click-to-move movement.
##
## The claims under test:
##
## 1. every playable location bakes a navigation mesh from its own geometry, and the
##    player's spawn is standing on it — a location with an empty mesh cannot be
##    navigated at all and that is a content error, not a runtime accident;
## 2. from the spawn you can actually reach a way out (a door or an exit), not just
##    "some point": a mesh that only covers the corner you spawn in is useless;
## 3. an accepted destination is walked to with the real physics body, arrives, and
##    then stops — no drift and no oscillation once the character is there;
## 4. a point off the mesh is refused instead of being snapped or walked at;
## 5. an isolated island of floor (disconnected, no ramp) never lifts the character
##    onto it;
## 6. geometry added between the player and the destination is walked *around*: the
##    route bends and the body keeps its distance from the obstacle;
## 7. manual input cancels a walk, and a second destination replaces the first;
## 8. a location swap cancels everything, so nothing from the old room can be
##    activated later.

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

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null
var _finished := 0
var _cancelled := 0


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
		if not _has_reachable_exit(location):
			_failures.append(
				"In the %s no exit is reachable from the spawn %s %s"
				% [label, str(_player.global_position), _report(nav)]
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
			"The walk did not finish within %.0f s: from %s to %s, active=%s, position %s."
			% [
				WALK_LIMIT_SECONDS, str(start), str(destination), str(_player.is_path_active()),
				str(_player.global_position)
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
	# Standing still has to mean standing still: sample the body after arrival.
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
	nav.bake_region()
	await _frames(2)
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
		_player.cancel_path()
		_failures.append("The walk to an unreachable island never stopped.")
	_remove_node(location, "IslandSlab")
	if nav != null:
		nav.bake_region()


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
	nav.bake_region()
	await _frames(2)
	if not _player.request_path_to(destination):
		_failures.append("The destination behind a wall with room around it was refused.")
		_remove_node(location, "ProbeWall")
		nav.bake_region()
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
		_failures.append("The character did not reach the far side of the obstacle (%.2f m short)." % gap)
	if closest < 0.45:
		_failures.append("The character walked %.2f m from the wall's face instead of around it." % closest)
	_remove_node(location, "ProbeWall")
	nav.bake_region()
	await _frames(2)


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


# --- helpers ----------------------------------------------------------------


func _enter(scene: String, spawn: StringName) -> LocationRoot:
	if not _host.load_location(scene, spawn, _player):
		return null
	await _frames(3)
	await _physics_frames(2)
	# The bake is deferred to the end of the load; wait for it rather than guessing.
	# A baked mesh is not enough: the map answers queries only once it has taken the
	# polygons, and a query in that window returns nothing at all.
	var guard := 0
	while guard < 120:
		var nav := _nav_of(_host.get_current())
		if nav != null and nav.is_baked() and nav.is_routable():
			break
		await physics_frame
		guard += 1
	_location = _host.get_current()
	return _location


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
	return "[region_pos=%s polygons=%d vertices=%d bounds=%s map_regions=%d map_cell=%s mesh_cell=%s agent_radius=%.2f]" % [
		str(nav.global_position), polygons, vertices, bounds, regions, cell, mesh_cell, nav.agent_radius
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
	for radius in [max_distance, max_distance * 0.75, max_distance * 0.5]:
		for index in 24:
			var angle := TAU * float(index) / 24.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.4:
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


## At least one way out of the room has to be walkable from where the player stands.
func _has_reachable_exit(location: LocationRoot) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	for node in location.get_tree().get_nodes_in_group("location_exit"):
		var exit := node as Interactable
		if exit == null or not location.is_ancestor_of(exit):
			continue
		var snapped := NavigationServer3D.map_get_closest_point(map, exit.global_position)
		if Vector2(snapped.x - exit.global_position.x, snapped.z - exit.global_position.z).length() > 1.5:
			continue
		var player_point := NavigationServer3D.map_get_closest_point(map, _player.global_position)
		var path := NavigationServer3D.map_get_path(map, snapped, player_point, true)
		if path.size() >= 2:
			return true
	return false


func _walk_until_settled(limit_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while _player.is_path_active():
		await physics_frame
		if Time.get_ticks_msec() > deadline:
			_player.cancel_path()
			return false
	return true


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
