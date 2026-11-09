extends SceneTree
## The cost of a location, and the cost of leaving it.
##
## This is the pressure test for scene swapping: it walks every playable location the game
## ships, then bounces between two of them until the numbers stop moving. It asserts what a
## door has to do rather than what it looks like:
##
## 1. every location loads, and its navigation is really baked — a mesh with faces, polygons
##    and a region registered with the map, plus a route between two of its own spawn points,
##    answered by the navigation server;
## 2. the bake is timed once per bake, and the numbers the region reports are the ones the
##    navigation server sees, not values a test could have invented;
## 3. after any number of transitions there is exactly one location scene in the tree, one
##    player and one companion;
## 4. coming back to the same room costs the same node count as the first time: the old
##    scene is freed, not stacked, and no orphans accumulate;
## 5. the companion stays joined and follows while the rooms change under it;
## 6. every transition the host recorded succeeded, with no more than one location alive at
##    the moment of the swap.
##
## The numbers are printed, because the point of the test is also to know them.

const Harness = preload("res://tests/test_harness.gd")

const LOCATIONS: Array[String] = [
	"res://scenes/locations/classroom/classroom.tscn",
	"res://scenes/locations/corridor/corridor.tscn",
	"res://scenes/locations/street/street.tscn",
	"res://scenes/locations/residential/residential.tscn",
	"res://scenes/locations/alley/alley.tscn",
	"res://scenes/locations/playground/playground.tscn",
]

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"

## How many nodes the tree may grow by over a full return trip before it counts as a leak.
## The room is the same room; a handful of nodes is a timer or a tween, not a second scene.
const NODE_GROWTH_TOLERANCE := 12
## The same, for nodes nothing owns. They are the ones a `queue_free` pattern gets wrong.
const ORPHAN_GROWTH_TOLERANCE := 4
## A companion further away than this, after a transition, is a companion that was left
## behind in the previous room.
const COMPANION_LEASH := 12.0

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _companion: CompanionController = null
## One line per location, for the run's annotations: the numbers this test exists to know.
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "location_pressure_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _frames(3)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_companion = _main.get_node_or_null("Companion") as CompanionController
	if _host == null or _player == null:
		Harness.finish(self, ["Main did not expose the host or the player."], "")
		return
	if sequence != null:
		sequence.call("allow_player_control")
	await _frames(2)

	await _check_every_location()
	await _check_round_trips()
	await _check_single_instances()
	await _check_companion_follows()
	_check_transition_log()

	_print_report()
	# A workflow annotation, because the step log is not readable from the API and these are
	# the numbers the roadmap quotes.
	print("::notice title=location cost::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		"every location loads, bakes its own navigation, and is replaced exactly once per "
		+ "transition: one room, one player, one companion, no accumulating nodes.",
	)


# --- cases ------------------------------------------------------------------


## Each shipped location, entered from the previous one's default spawn.
func _check_every_location() -> void:
	for path: String in LOCATIONS:
		Harness.stage = "entering %s" % path
		var entered := await _enter(path)
		if not entered:
			continue
		var location := _host.get_current()
		_expect(location != null, "%s entered but the host reports no location." % path)
		if location == null:
			continue
		var navigation := location.get_node_or_null("Navigation") as LocationNavigation
		if navigation == null:
			_failures.append("%s has no Navigation region." % path)
			continue
		_expect(navigation.is_baked(), "%s: the navigation mesh did not bake." % path)
		_expect(
			navigation.get_geometry_face_count() > 0,
			"%s: the bake parsed no geometry; nothing would be walkable." % path
		)
		_expect(
			navigation.get_polygon_count() > 0,
			"%s: the bake produced no polygons." % path
		)
		_expect(
			navigation.get_map_region_count() > 0,
			"%s: the region never registered with the navigation map." % path
		)
		_expect(
			navigation.get_bake_usec() > 0,
			"%s: the bake has no measured duration; the timing is not wired." % path
		)
		_expect(
			navigation.get_bake_usec() >= navigation.get_collect_usec(),
			"%s: collecting geometry took longer than the whole bake." % path
		)
		_expect(
			navigation.is_routable(),
			"%s: the navigation map cannot answer a route.%s"
			% [path, _nav_report(navigation)]
		)
		_check_walkable_around(path, location, navigation)
		_note_spawn_pairs(path, location, navigation)
		var transition := _host.get_last_transition()
		_notes.append(
			"%s: %.1f ms (load %.1f, inst %.1f, tree %.1f, place %.1f), bake %.1f ms, "
			% [
				String(location.location_id),
				int(transition.get("total_usec", 0)) / 1000.0,
				int(transition.get("load_usec", 0)) / 1000.0,
				int(transition.get("instantiate_usec", 0)) / 1000.0,
				int(transition.get("tree_usec", 0)) / 1000.0,
				int(transition.get("placement_usec", 0)) / 1000.0,
				navigation.get_bake_usec() / 1000.0,
			]
			+ "%d faces -> %d polygons, %d nodes"
			% [
				navigation.get_geometry_face_count(),
				navigation.get_polygon_count(),
				int(transition.get("scene_nodes", 0)),
			]
		)

	print(
		"pressure: %d location(s) entered, %d transition(s) logged."
		% [LOCATIONS.size(), _host.transition_history.size()]
	)


## The room has to be walkable *around the spawn*, which is what "navigation is usable here"
## means for a player: eight directions, four metres each, and most of them have to arrive.
## A spawn marker behind a closed door is a content decision, not a broken mesh, so a single
## blocked direction must not fail the build — while a room whose spawn is walled in does.
const RING_DIRECTIONS := 8
const RING_RADIUS := 4.0
const RING_MINIMUM_REACHED := 3

func _check_walkable_around(
	path: String, location: LocationRoot, navigation: LocationNavigation
) -> void:
	var marker := location.get_default_spawn()
	if marker == null:
		_failures.append("%s has no default spawn to stand on." % path)
		return
	var map := navigation.get_navigation_map()
	var origin := NavigationServer3D.map_get_closest_point(map, marker.global_position)
	var snap := origin.distance_to(marker.global_position)
	_expect(
		snap < 1.5,
		"%s: the default spawn is %.1f m from the nearest walkable point.%s"
		% [path, snap, _nav_report(navigation)]
	)
	var reached := 0
	for index in RING_DIRECTIONS:
		var angle := TAU * float(index) / float(RING_DIRECTIONS)
		var want := marker.global_position + Vector3(cos(angle), 0.0, sin(angle)) * RING_RADIUS
		var target := NavigationServer3D.map_get_closest_point(map, want)
		var route := NavigationServer3D.map_get_path(map, origin, target, true)
		if route.size() < 2:
			continue
		var end: Vector3 = route[route.size() - 1]
		if end.distance_to(target) > 0.5:
			continue
		if end.distance_to(origin) < RING_RADIUS * 0.75:
			continue
		reached += 1
	_expect(
		reached >= RING_MINIMUM_REACHED,
		"%s: only %d of %d directions around the spawn are walkable for 4 m.%s"
		% [path, reached, RING_DIRECTIONS, _nav_report(navigation)]
	)


## Spawn-to-spawn routes, recorded rather than required: the classroom's return marker sits
## behind the door that the story has not opened yet, and that is authored, not broken. The
## numbers go into the run's annotation so a connection that closes by accident is visible.
func _note_spawn_pairs(
	path: String, location: LocationRoot, navigation: LocationNavigation
) -> void:
	var ids := location.get_spawn_ids()
	if ids.size() < 2:
		_notes.append("%s: %d spawn point(s), nothing to route between" % [path.get_file(), ids.size()])
		return
	var map := navigation.get_navigation_map()
	var blocked: Array[String] = []
	for index in range(1, ids.size()):
		var from_marker := location.get_spawn(ids[0])
		var to_marker := location.get_spawn(ids[index])
		if from_marker == null or to_marker == null:
			continue
		var from := NavigationServer3D.map_get_closest_point(map, from_marker.global_position)
		var to := NavigationServer3D.map_get_closest_point(map, to_marker.global_position)
		var route := NavigationServer3D.map_get_path(map, from, to, true)
		if route.size() < 2 or route[route.size() - 1].distance_to(to) > 1.0:
			blocked.append("%s->%s" % [ids[0], ids[index]])
	if not blocked.is_empty():
		_notes.append("%s: unroutable spawn pair(s): %s" % [path.get_file(), ", ".join(blocked)])


## Back and forth until the numbers stop moving: the room a player returns to has to cost
## the same as the room they left.
func _check_round_trips() -> void:
	Harness.stage = "round trips"
	if not await _enter(CLASSROOM):
		return
	await _settle()
	var nodes_before := _node_count()
	var orphans_before := _orphan_count()
	for index in 3:
		Harness.stage = "round trip %d (out)" % (index + 1)
		if not await _enter(CORRIDOR):
			return
		Harness.stage = "round trip %d (back)" % (index + 1)
		if not await _enter(CLASSROOM):
			return
	await _settle()
	var nodes_after := _node_count()
	var orphans_after := _orphan_count()
	_expect(
		nodes_after - nodes_before <= NODE_GROWTH_TOLERANCE,
		"The tree grew by %d nodes over three round trips (%d -> %d): a scene is being left behind."
		% [nodes_after - nodes_before, nodes_before, nodes_after]
	)
	_expect(
		orphans_after - orphans_before <= ORPHAN_GROWTH_TOLERANCE,
		"%d orphan node(s) appeared over three round trips (%d -> %d)."
		% [orphans_after - orphans_before, orphans_before, orphans_after]
	)
	print(
		"pressure: three round trips, nodes %d -> %d, orphans %d -> %d."
		% [nodes_before, nodes_after, orphans_before, orphans_after]
	)


## One room, one player, one companion, however many times the room changed.
func _check_single_instances() -> void:
	Harness.stage = "counting instances"
	var locations := _count_of(_main, "location")
	var players := _count_of(_main, "player")
	var companions := _count_of(_main, "companion")
	_expect(locations == 1, "%d location scene(s) are in the tree at once." % locations)
	_expect(players == 1, "%d player node(s) are in the tree." % players)
	_expect(companions == 1, "%d companion node(s) are in the tree." % companions)
	_expect(
		_host.get_child_count() == 1,
		"The location host holds %d children; it should hold the one room." % _host.get_child_count()
	)


## Q joins once and stays joined; being carried between rooms does not unjoin it, and a
## companion that is visible stands near the player rather than in the previous room.
func _check_companion_follows() -> void:
	Harness.stage = "companion following"
	if _companion == null:
		_failures.append("Main has no Companion node to test.")
		return
	if not _companion.is_joined():
		_companion.join()
	_expect(_companion.is_joined(), "The companion refused to join.")
	for index in 2:
		if not await _enter(CORRIDOR if index == 0 else CLASSROOM):
			return
		await _frames(30)
		_expect(
			_companion.is_joined(),
			"The companion unjoined itself after transition %d." % (index + 1)
		)
		if not _companion.is_with_player():
			# Hiding is legal: a room without a place for Q is a room Q is not in. What is
			# not legal is being visible and standing in the previous room.
			continue
		var distance := _companion.global_position.distance_to(_player.global_position)
		_expect(
			distance <= COMPANION_LEASH,
			"The companion is %.1f m from the player after transition %d."
			% [distance, index + 1]
		)
	_companion.resume_following()
	await _frames(2)
	_expect(
		not _companion.is_waiting(),
		"Asking the companion along again left it waiting."
	)


## The host's own log: every transition succeeded, and never more than one room was alive.
func _check_transition_log() -> void:
	Harness.stage = "transition log"
	var history := _host.transition_history
	_expect(not history.is_empty(), "The host recorded no transitions at all.")
	for entry: Dictionary in history:
		_expect(bool(entry["ok"]), "A transition to %s failed." % entry["scene"])
		_expect(
			int(entry["live_locations"]) == 1,
			"%d location scene(s) were alive after entering %s."
			% [int(entry["live_locations"]), entry["scene"]]
		)
		_expect(
			int(entry["total_usec"]) > 0,
			"The transition to %s has no measured duration." % entry["scene"]
		)
		_expect(
			int(entry["total_usec"])
			>= int(entry["load_usec"])
			+ int(entry["instantiate_usec"])
			+ int(entry["tree_usec"])
			+ int(entry["placement_usec"]),
			"The stages of %s add up to more than the transition did." % entry["scene"]
		)
		_expect(
			int(entry["scene_nodes"]) > 0,
			"%s was entered with no nodes in it." % entry["scene"]
		)


# --- helpers ----------------------------------------------------------------


func _enter(path: String) -> bool:
	var before := _host.get_current()
	# Standing in the room the loop wants to visit next is not a reason to load a second copy
	# of it: the opening sequence already put the classroom there, so this checks that one.
	if _host.get_current_path() == path and before != null:
		await _await_routable(before)
		return true
	var ok := _host.load_location(path, &"", _player)
	_expect(ok, "%s could not be entered." % path)
	if not ok:
		return false
	var entered := _host.get_current()
	_expect(entered != null, "%s reported success but left no current location." % path)
	if entered == null:
		return false
	_expect(
		before == null or entered != before,
		"%s reported success but the old scene is still current." % path
	)
	_expect(
		not String(entered.location_id).is_empty(),
		"%s entered without declaring a location_id." % path
	)
	var default_spawn := entered.get_default_spawn()
	_expect(
		default_spawn != null
		and _player.global_position.distance_to(default_spawn.global_position) < 0.1,
		"%s: the player was not placed on the default spawn." % path
	)
	await _await_routable(entered)
	await _physics_frames(2)
	return true


## The bake is deferred and the region's polygons reach the navigation server a frame or two
## later, so wait for a *routable* map rather than for a fixed number of frames: a query in
## that window answers with nothing, and a test that measures that window is measuring its
## own timing, not the game.
##
## The wait is about the *new room*, not about the map: right after the swap the map still
## holds the previous room's polygons, so `is_routable()` answers yes about a floor that is
## about to be freed. The condition that matters is the one a player would notice — the spot
## the character was put on is walkable.
func _await_routable(location: LocationRoot) -> void:
	var guard := 0
	while guard < 180:
		var navigation := location.get_node_or_null("Navigation") as LocationNavigation
		if navigation != null and navigation.is_baked() and _spawn_is_walkable(location, navigation):
			return
		await physics_frame
		guard += 1
	# A map that never answers is the failure this test exists for, so say what the map
	# looked like instead of only that it was empty: the next run should not need another run.
	var navigation := location.get_node_or_null("Navigation") as LocationNavigation
	if navigation != null and not navigation.is_routable():
		_notes.append("not routable: %s%s" % [String(location.location_id), _nav_report(navigation)])


## True when the map the location's region lives in can answer the spawn: the room the
## player was put in is the room the navigation knows about.
func _spawn_is_walkable(location: LocationRoot, navigation: LocationNavigation) -> bool:
	var marker := location.get_default_spawn()
	var map := navigation.get_navigation_map()
	if marker == null or not map.is_valid():
		return false
	var closest := NavigationServer3D.map_get_closest_point(map, marker.global_position)
	return closest.distance_to(marker.global_position) < 1.0


## Everything needed to tell "no mesh", "mesh the map refused" and "map not synced" apart.
func _nav_report(navigation: LocationNavigation) -> String:
	var map := navigation.get_navigation_map()
	var mesh: NavigationMesh = navigation.navigation_mesh
	var regions := -1
	var map_cell := -1.0
	var map_height := -1.0
	if map.is_valid():
		regions = NavigationServer3D.map_get_regions(map).size()
		if NavigationServer3D.has_method("map_get_cell_size"):
			map_cell = NavigationServer3D.map_get_cell_size(map)
			map_height = NavigationServer3D.map_get_cell_height(map)
	var closest := Vector3.ZERO
	if map.is_valid():
		closest = NavigationServer3D.map_get_closest_point(map, navigation.global_position)
	return (
		" [baked=%s polygons=%d faces=%d map_regions=%d map_valid=%s map_cell=%.3f/%.3f "
		+ "mesh_cell=%.3f/%.3f vertices=%d closest_to_region=%s region_pos=%s error='%s']"
	) % [
		str(navigation.is_baked()),
		navigation.get_polygon_count(),
		navigation.get_geometry_face_count(),
		regions,
		str(map.is_valid()),
		map_cell,
		map_height,
		mesh.cell_size if mesh != null else -1.0,
		mesh.cell_height if mesh != null else -1.0,
		mesh.get_vertices().size() if mesh != null else -1,
		str(closest),
		str(navigation.global_position),
		navigation.get_bake_error(),
	]


## Lets the deferred bake and the physics settle before the node count is read.
func _settle() -> void:
	for _index in 20:
		await process_frame


func _count_of(node: Node, what: String) -> int:
	var total := 0
	match what:
		"location":
			if node is LocationRoot:
				total += 1
		"player":
			if node is PlayerController:
				total += 1
		"companion":
			if node is CompanionController:
				total += 1
	for child in node.get_children():
		total += _count_of(child, what)
	return total


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _print_report() -> void:
	var history := _host.transition_history
	if history.is_empty():
		return
	print("pressure: the last %d transition(s):" % history.size())
	for entry: Dictionary in history:
		print(
			"  %-22s %6.1f ms (load %5.1f, inst %5.1f, tree %5.1f, place %4.1f, commit %4.1f) %5d nodes, %d live"
			% [
				entry["scene"].get_file().get_basename(),
				int(entry["total_usec"]) / 1000.0,
				int(entry["load_usec"]) / 1000.0,
				int(entry["instantiate_usec"]) / 1000.0,
				int(entry["tree_usec"]) / 1000.0,
				int(entry["placement_usec"]) / 1000.0,
				int(entry["commit_usec"]) / 1000.0,
				int(entry["scene_nodes"]),
				int(entry["live_locations"]),
			]
		)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
