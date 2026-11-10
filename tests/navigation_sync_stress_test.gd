extends SceneTree
## Ten rounds of switching between all six locations, measuring the navigation map after
## every single switch.
##
## The two flakes this file exists for were both about *when* a query is asked, not about
## what it answers: a room whose mesh was baked but whose map had not caught up answered
## from the room that had just been freed, and an exit "24.97 m off the mesh" was really an
## exit measured against the previous room's floor. Retrying the CI run made them go away
## and told nobody anything.
##
## So the rule is measured here instead of trusted: after each switch the room must reach
## `LocationNavigation.is_synchronized()` - baked, the map has synchronized at least once,
## this region is registered on it, and every spread probe of this mesh is answered by it -
## and only then is anything projected onto it. What the test reports per hop is the number
## of physics frames that took and the map's iteration id either side of it.
##
## The claims:
##
## 1. every one of the six locations loads with its own mesh, and its spawn projects onto
##    that mesh;
## 2. a rapid switch never answers from the room that was just left: the map holds one
##    region after every hop, and it is the new room's;
## 3. every exit a room ships sits on that room's mesh;
## 4. residential and alley stay walkable between each other in both directions;
## 5. a walk cancelled by a switch does not keep running afterwards;
## 6. ten rounds leave nothing behind: one location, one player, one companion, one region.

const Harness = preload("res://tests/test_harness.gd")

const LOCATIONS: Array[Dictionary] = [
	{"scene": "res://scenes/locations/classroom/classroom.tscn", "spawn": &"PlayerStart", "name": "classroom"},
	{"scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": &"FromClassroom", "name": "corridor"},
	{"scene": "res://scenes/locations/street/street.tscn", "spawn": &"FromCorridor", "name": "street"},
	{"scene": "res://scenes/locations/residential/residential.tscn", "spawn": &"FromStreet", "name": "residential"},
	{"scene": "res://scenes/locations/alley/alley.tscn", "spawn": &"FromCourtyard", "name": "alley"},
	{"scene": "res://scenes/locations/playground/playground.tscn", "spawn": &"FromAlley", "name": "playground"},
]

## Ten rounds of six switches is sixty loads; each one bakes a room.
const ROUNDS := 10
## How far a spawn marker may sit from the mesh it is meant to stand on.
const SPAWN_TOLERANCE := 1.2
## How far an exit may sit from the mesh it is meant to be reachable from.
const EXIT_TOLERANCE := 1.5
## The lane behind the flats is ~43 m from the courtyard spawn; a route that stops short of
## that is a closed way, not a measurement wobble.
const FLATS_TO_LANE := 30.0
const LANE_TO_FLATS := 1.0
## Physics frames a room may take to reach the map before the run calls it stalled. The
## budget is only a ceiling: the number actually used is reported.
const SYNC_FRAMES := 120

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
## Every hop of every round: {"round", "location", "frames", "iteration_before",
## "iteration_after", "regions", "spawn_offset", "exits"}.
var _hops: Array[Dictionary] = []
var _worst_spawn_offset := 0.0
var _worst_exit_offset := 0.0
var _worst_frames := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 900.0, "navigation_sync_stress_test.gd")
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
	await _frames(3)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	if _host == null or _player == null:
		Harness.finish(self, ["Main did not expose the host and the player."], "")
		return
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	# The passive inner voice can open a conversation of its own and lock the player
	# mid-switch; it has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	Engine.time_scale = 3.0
	await _frames(2)

	Harness.stage = "rounds"
	for round in ROUNDS:
		# Every round starts one room further along, so no round repeats the previous
		# round's hop order and the swap direction alternates.
		for step in LOCATIONS.size():
			await _hop(round, LOCATIONS[(round + step) % LOCATIONS.size()])

	Harness.stage = "the flats and the lane"
	await _check_flats_and_lane()
	Harness.stage = "a cancelled walk"
	await _check_cancelled_walk()
	Harness.stage = "leftovers"
	await _check_leftovers()

	_report()
	Harness.finish(
		self, _failures,
		"the navigation map answers for the room the player is in after every one of "
		+ "%d switches, and nothing is left behind." % (ROUNDS * LOCATIONS.size())
	)


## One switch: load the room, wait for its map, then measure everything that depends on
## that map having caught up.
func _hop(round: int, entry: Dictionary) -> void:
	var label := "%s (round %d)" % [String(entry["name"]), round + 1]
	var map := _player.navigation_agent.get_navigation_map()
	var iteration_before := _map_iteration(map)
	if not _host.load_location(
		String(entry["scene"]), entry["spawn"] as StringName, _player,
		StringName(entry["name"])
	):
		_failures.append("%s: the switch was refused." % label)
		return
	var location := _host.get_current()
	if location == null or String(location.location_id) != String(entry["name"]):
		_failures.append("%s: the current location is not the one that was entered." % label)
		return
	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("%s: the room has no navigation region." % label)
		return

	# The measurement this whole file is about: how many frames until the map answers for
	# *this* mesh, and no query is asked before that is true.
	var frames := 0
	while frames < SYNC_FRAMES and not nav.is_synchronized():
		await physics_frame
		frames += 1
	var iteration_after := _map_iteration(map)
	if not nav.is_synchronized():
		_failures.append(
			"%s: the map never synchronized with the room's mesh (%s)" % [label, nav.describe_sync()]
		)
		return
	_worst_frames = maxi(_worst_frames, frames)

	var regions := NavigationServer3D.map_get_regions(map)
	if regions.size() != 1 or not regions.has(nav.get_rid()):
		_failures.append(
			"%s: the map holds %d region(s) after the switch, and %s"
			% [label, regions.size(), "not the new room's" if not regions.has(nav.get_rid()) else "the new room's"]
		)

	var spawn := location.get_spawn(entry["spawn"] as StringName)
	if spawn == null:
		_failures.append("%s: the room has no spawn '%s'." % [label, String(entry["spawn"])])
		return
	var projected := nav.project_point(spawn.global_position)
	if not bool(projected["ok"]):
		_failures.append(
			"%s: the spawn could not be projected onto the mesh (%s)" % [label, projected["reason"]]
		)
		return
	var spawn_offset := float(projected["offset"])
	_worst_spawn_offset = maxf(_worst_spawn_offset, spawn_offset)
	if spawn_offset > SPAWN_TOLERANCE:
		_failures.append(
			"%s: the spawn sits %.2f m off the room's mesh (limit %.1f m)"
			% [label, spawn_offset, SPAWN_TOLERANCE]
		)

	var exits := _exits_of(location)
	var worst_exit := 0.0
	for exit: Node3D in exits:
		var exit_projected := nav.project_point(exit.global_position)
		if not bool(exit_projected["ok"]):
			_failures.append(
				"%s: exit %s could not be projected onto the mesh (%s)"
				% [label, String(exit.name), exit_projected["reason"]]
			)
			continue
		worst_exit = maxf(worst_exit, float(exit_projected["offset"]))
		if float(exit_projected["offset"]) > EXIT_TOLERANCE:
			_failures.append(
				"%s: exit %s sits %.2f m off the room's mesh (limit %.1f m)"
				% [label, String(exit.name), float(exit_projected["offset"]), EXIT_TOLERANCE]
			)
	_worst_exit_offset = maxf(_worst_exit_offset, worst_exit)

	_hops.append({
		"round": round + 1,
		"location": String(entry["name"]),
		"frames": frames,
		"iteration_before": iteration_before,
		"iteration_after": iteration_after,
		"regions": regions.size(),
		"spawn_offset": spawn_offset,
		"exits": exits.size(),
		"worst_exit": worst_exit,
	})
	print(
		"::notice title=navigation sync::%s: synchronized in %d frame(s), iteration %d -> %d, "
		% [label, frames, iteration_before, iteration_after]
		+ "%d region(s), spawn %.2f m off, %d exit(s) worst %.2f m"
		% [regions.size(), spawn_offset, exits.size(), worst_exit]
	)


## The courtyard and the lane behind the flats, walked between each other - the pair the
## arrival sweep used to blame for a 24.97 m exit.
func _check_flats_and_lane() -> void:
	await _check_route("residential", &"FromStreet", &"res_alley_end", FLATS_TO_LANE)
	await _check_route("alley", &"FromCourtyard", &"alley_back_to_courtyard", LANE_TO_FLATS)
	# And back again, so the pair is connected both ways in one run rather than in two.
	await _check_route("residential", &"FromStreet", &"res_alley_end", FLATS_TO_LANE)


func _check_route(
	location_name: String, spawn_id: StringName, exit_id: StringName, minimum: float
) -> void:
	var label := "%s/%s" % [location_name, String(exit_id)]
	var scene := "res://scenes/locations/%s/%s.tscn" % [location_name, location_name]
	if not _host.load_location(scene, spawn_id, _player, StringName(location_name)):
		_failures.append("%s: could not enter the %s." % [label, location_name])
		return
	var location := _host.get_current()
	if location == null:
		_failures.append("%s: the %s did not become current." % [label, location_name])
		return
	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("%s: the %s has no navigation region." % [label, location_name])
		return
	var synchronized: bool = await nav.wait_until_synchronized()
	if not synchronized:
		_failures.append(
			"%s: the %s never synchronized (%s)"
			% [label, location_name, nav.describe_sync()]
		)
		return
	var exit := _find_exit(location, exit_id)
	if exit == null:
		_failures.append("%s: the %s has no exit '%s'." % [label, location_name, String(exit_id)])
		return
	var from := nav.project_point(_player.global_position)
	var to := nav.project_point(exit.global_position)
	if not bool(from["ok"]) or not bool(to["ok"]):
		_failures.append(
			"%s: a route end could not be projected (%s / %s)"
			% [label, from["reason"], to["reason"]]
		)
		return
	if float(to["offset"]) > EXIT_TOLERANCE:
		_failures.append(
			"%s: the exit sits %.2f m off the mesh (limit %.1f m)"
			% [label, float(to["offset"]), EXIT_TOLERANCE]
		)
		return
	var map := _player.navigation_agent.get_navigation_map()
	var path := NavigationServer3D.map_get_path(
		map, from["point"] as Vector3, to["point"] as Vector3, true
	)
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	if path.size() < 2 or length < minimum:
		_failures.append(
			"%s: the route from the arrival point to that exit is %.2f m over %d point(s), "
			% [label, length, path.size()]
			+ "so the two spaces are not walkable between each other."
		)
	print("::notice title=navigation sync::%s: route %.2f m over %d point(s)" % [label, length, path.size()])


## A walk that a switch interrupts must not continue in the new room.
func _check_cancelled_walk() -> void:
	if not _host.load_location(
		"res://scenes/locations/classroom/classroom.tscn", &"PlayerStart", _player, &"classroom"
	):
		_failures.append("the classroom could not be entered to start the cancelled walk.")
		return
	var classroom := _host.get_current()
	if classroom == null:
		_failures.append("the classroom did not stay current before the cancelled walk.")
		return
	var nav := classroom.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("the classroom has no navigation region before the cancelled walk.")
		return
	var synchronized: bool = await nav.wait_until_synchronized()
	if not synchronized:
		_failures.append("the classroom never synchronized before the cancelled walk.")
		return
	var ahead := _player.global_position + Vector3(2.0, 0.0, 0.0)
	if not _player.request_path_to(ahead):
		_failures.append("a two-metre walk could not be started to cancel it.")
		return
	if not _player.is_path_active():
		_failures.append("the accepted walk did not start.")
		return
	# The switch itself is the cancellation: nothing calls `cancel_path()` first.
	if not _host.load_location(
		"res://scenes/locations/corridor/corridor.tscn", &"FromClassroom", _player, &"corridor"
	):
		_failures.append("the corridor could not be entered to cancel the walk.")
		return
	await _frames(3)
	if _player.is_path_active():
		_failures.append("a walk cancelled by a location switch kept running in the new room.")
	var legs := _player.get_path_legs()
	if not legs.is_empty():
		_failures.append(
			"a walk cancelled by a location switch kept %d leg(s) of the old room's route." % legs.size()
		)
	if _player.global_position.distance_to(Vector3.ZERO) > 200.0:
		_failures.append("the player ended up outside the world after the cancelled walk.")


## Ten rounds of switching must leave exactly one of everything.
func _check_leftovers() -> void:
	var locations := 0
	for node in _descendants(_main):
		if node is LocationRoot:
			locations += 1
	if locations != 1:
		_failures.append("%d location(s) are alive after %d rounds; one is expected." % [locations, ROUNDS])
	var players := 0
	for node in _descendants(_main):
		if node is PlayerController:
			players += 1
	if players != 1:
		_failures.append("%d player(s) are alive after %d rounds; one is expected." % [players, ROUNDS])
	var companions := 0
	for node in _descendants(_main):
		if node is CompanionController:
			companions += 1
	if companions > 1:
		_failures.append("%d companion(s) are alive after %d rounds." % [companions, ROUNDS])
	var regions := NavigationServer3D.map_get_regions(_player.navigation_agent.get_navigation_map())
	if regions.size() != 1:
		_failures.append(
			"%d navigation region(s) are on the map after %d rounds; one is expected."
			% [regions.size(), ROUNDS]
		)
	var nav_items := get_nodes_in_group("location_navigation")
	if nav_items.size() != 1:
		_failures.append(
			"%d navigation region node(s) are in the tree after %d rounds; one is expected."
			% [nav_items.size(), ROUNDS]
		)


func _report() -> void:
	print(
		"::notice title=navigation sync::%d hop(s) over %d round(s); slowest synchronization "
		% [_hops.size(), ROUNDS]
		+ "%d frame(s), worst spawn offset %.2f m, worst exit offset %.2f m"
		% [_worst_frames, _worst_spawn_offset, _worst_exit_offset]
	)
	for hop: Dictionary in _hops:
		if int(hop["frames"]) > SYNC_FRAMES / 2:
			print("::notice title=navigation sync::slow hop %s" % str(hop))


# --- helpers ----------------------------------------------------------------


func _map_iteration(map: RID) -> int:
	if not map.is_valid() or not NavigationServer3D.has_method("map_get_iteration_id"):
		return 0
	return NavigationServer3D.map_get_iteration_id(map)


func _exits_of(location: LocationRoot) -> Array[Node3D]:
	var exits: Array[Node3D] = []
	for interactable in location.get_interactables():
		var exit := interactable as LocationExit
		if exit != null:
			exits.append(exit)
	return exits


func _find_exit(location: LocationRoot, exit_id: StringName) -> LocationExit:
	for interactable in location.get_interactables():
		var exit := interactable as LocationExit
		if exit != null and exit.interact_id == exit_id:
			return exit
	return null


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
			found.append(child)
	return found


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame
