extends SceneTree
## Location transitions are transactions, and a failed one changes nothing.
##
## The claims under test (issue #19):
##
## 1. a spawn id that names nothing is refused; only an empty id means "use the
##    location's default spawn", and the default is the first marker in tree order;
## 2. every way a load can fail — empty path, missing scene, a root that is not a
##    `LocationRoot`, no `location_id`, an id other than the one expected, no spawn,
##    no player — returns false *before* the old scene is touched;
## 3. after a failed load the old scene is still the current one, the player is
##    standing exactly where they were, facing the same way, `CURRENT_LOCATION` is
##    unchanged, `location_entered` was not emitted, and the rejected instance is gone;
## 4. the same holds on the director's own path: a door whose spawn is mistyped leaves
##    the room, the player, Q and the story flag alone and gives control back;
## 5. every exit the game ships really works: the scene, the `location_id`, the spawn
##    marker, the arrival point on the navigation mesh, and a return marker that sits
##    by the exit it comes back through.
##
## Broken scenes are packed at run time into `user://`, so the repository never carries
## content that a careless `load()` could pick up.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const LOCATIONS: Array[String] = [
	"classroom", "corridor", "street", "residential", "alley", "playground"
]
const FIXTURE_DIR := "user://location_fixtures"

## How far an arrival point may sit from the navigation mesh. `navigation_test.gd`
## already holds each location's *primary* spawn to 1.2 m; this test covers every
## exit's own marker, where the question is whether the player is dropped into walkable
## ground at all rather than through a wall. The measured distances are printed, so a
## marker that creeps outward is visible long before it fails.
const ENTRY_TOLERANCE := 3.0
## How far the marker a return trip lands on may sit from the exit it comes back
## through: arriving has to put the player by the door they just used.
const RETURN_PROXIMITY := 6.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null
var _game_state: Node = null
## Every `location_entered` the host emitted, in order.
var _entered: Array[Dictionary] = []
## Arrival geometry per exit, checked together at the end so one failure message
## carries every measurement instead of only the first one.
var _arrival_offsets: Dictionary = {}
var _return_distances: Dictionary = {}


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "location_transition_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	_game_state = autoloads["game_state"]

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
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _host == null or _player == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the host, the player and the director."], "")
		return
	_sequence.allow_player_control()
	_host.location_entered.connect(
		func(location: LocationRoot, spawn_id: StringName) -> void:
			_entered.append({"location_id": location.location_id, "spawn_id": spawn_id})
	)
	# The passive inner voice can open a conversation on its own and lock the player
	# mid-transition; it has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	# Fades and navigation settling are wall-clock; the assertions do not care how long
	# they take.
	Engine.time_scale = 3.0
	await _frames(2)

	Harness.stage = "spawn contract"
	await _check_spawn_contract()
	Harness.stage = "refused transitions"
	await _check_refused_transitions()
	Harness.stage = "director refusal"
	await _check_director_refusal()
	Harness.stage = "director transition"
	await _check_director_transition()
	Harness.stage = "every shipped exit"
	await _check_every_shipped_exit()

	Harness.finish(
		self, _failures,
		"a location transition commits only when its scene, id and spawn all exist, "
		+ "and every shipped exit lands on a real spawn."
	)


# --- spawn contract ----------------------------------------------------------


func _check_spawn_contract() -> void:
	# An empty id is the documented default: the first spawn marker in tree order.
	if not await _enter(CLASSROOM, &""):
		return
	var classroom := _host.get_current()
	var default_spawn := classroom.get_default_spawn()
	if default_spawn == null:
		_failures.append("The classroom has no default spawn.")
		return
	if String(default_spawn.name) != "PlayerStart":
		_failures.append(
			"An empty spawn id should use the first marker in tree order, got '%s'."
			% default_spawn.name
		)
	_expect_at("an empty spawn id", default_spawn.global_transform)

	# A named id is matched exactly, and it does not have to be the first marker.
	if not await _enter(CLASSROOM, &"FromCorridor"):
		return
	var named := _host.get_current().get_spawn(&"FromCorridor")
	if named == null:
		_failures.append("The classroom no longer has its 'FromCorridor' spawn.")
		return
	_expect_at("a named spawn id", named.global_transform)

	# A name nobody authored is a failure, not a silent default.
	var ids := _host.get_current().get_spawn_ids()
	for expected: StringName in [&"PlayerStart", &"FromCorridor"]:
		if not ids.has(expected):
			_failures.append("get_spawn_ids() lost '%s' (got %s)." % [expected, str(ids)])
	var missing := _host.get_current().get_spawn(&"PlayerStart_Mistyped")
	if missing != null:
		_failures.append(
			"A spawn id that does not exist still resolved to '%s'." % missing.name
		)

	# A marker's rotation is what sets the arrival heading; the classroom markers are
	# position-only, so this is pinned on a fixture instead of on content.
	var path := _pack_fixture("rotated", &"fixture", true, [
		{"name": "Turned", "position": Vector3(1.0, 0.0, 2.0), "basis": Basis(Vector3.UP, PI * 0.5)},
	])
	if not path.is_empty():
		if await _enter(path, &"Turned", &"fixture"):
			var expected_facing := -Basis(Vector3.UP, PI * 0.5).z
			var facing := _player.get_facing_direction()
			if facing.distance_to(expected_facing) > 0.01:
				_failures.append(
					"A rotated spawn marker was not applied: facing %s, expected %s."
					% [str(facing), str(expected_facing)]
				)


# --- refused transitions -----------------------------------------------------


func _check_refused_transitions() -> void:
	if not await _enter(CLASSROOM, &"PlayerStart"):
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	await _frames(1)

	var not_a_location := _pack_fixture("plain_root", &"", false, [
		{"name": "Somewhere", "position": Vector3.ZERO},
	])
	var no_id := _pack_fixture("no_id", &"", true, [
		{"name": "Anywhere", "position": Vector3.ZERO},
	])
	var wrong_id := _pack_fixture("wrong_id", &"corridor", true, [
		{"name": "Anywhere", "position": Vector3.ZERO},
	])

	# A typo in an exit is the case this whole task exists for.
	await _expect_refused(
		"a spawn id that does not exist", CORRIDOR, &"PlayerStart_Mistyped", &"corridor"
	)
	await _expect_refused("a scene that does not exist",
		"res://scenes/locations/nowhere/nowhere.tscn", &"FromClassroom", &"corridor")
	await _expect_refused("an empty scene path", "", &"FromClassroom", &"corridor")
	await _expect_refused("a root that is not a LocationRoot",
		not_a_location, &"Somewhere", &"")
	await _expect_refused("a scene without a location_id", no_id, &"Anywhere", &"")
	await _expect_refused("a location_id other than the expected one",
		wrong_id, &"Anywhere", &"classroom")
	await _expect_refused_without_player("no player to place", CORRIDOR, &"FromClassroom")


## Snapshots the world, performs the load, and requires that *nothing* happened.
func _expect_refused(
	label: String, scene: String, spawn: StringName, expected: StringName
) -> void:
	var before := _snapshot()
	var result := _host.load_location(scene, spawn, _player, expected)
	await _frames(2)
	if result:
		_failures.append("A transition with %s returned true." % label)
	_expect_untouched(label, before)


func _expect_refused_without_player(
	label: String, scene: String, spawn: StringName
) -> void:
	var before := _snapshot()
	var result := _host.load_location(scene, spawn, null)
	await _frames(2)
	if result:
		_failures.append("A transition with %s returned true." % label)
	_expect_untouched(label, before)


## Requires that the world still looks exactly like `before`.
func _expect_untouched(label: String, before: Dictionary) -> void:
	var after := _snapshot()
	if after["location"] != before["location"]:
		_failures.append("A transition with %s replaced the current location." % label)
	if after["path"] != before["path"]:
		_failures.append("A transition with %s changed the current scene path." % label)
	var was: Vector3 = before["position"]
	var is_now: Vector3 = after["position"]
	var moved := is_now.distance_to(was)
	if moved > 0.001:
		_failures.append("A transition with %s moved the player %.3f m." % [label, moved])
	var was_facing: Vector3 = before["facing"]
	var is_facing: Vector3 = after["facing"]
	var turned := is_facing.angle_to(was_facing)
	if turned > 0.001:
		_failures.append("A transition with %s turned the player %.3f rad." % [label, turned])
	if after["flag"] != before["flag"]:
		_failures.append(
			"A transition with %s changed CURRENT_LOCATION from '%s' to '%s'."
			% [label, str(before["flag"]), str(after["flag"])]
		)
	if after["signals"] != before["signals"]:
		_failures.append("A transition with %s emitted location_entered." % label)
	if after["children"] != before["children"]:
		_failures.append(
			"A transition with %s left %d child(ren) under the host instead of %d."
			% [label, after["children"], before["children"]]
		)
	var leaked := int(after["nodes"]) - int(before["nodes"])
	if leaked > 0:
		_failures.append(
			"A transition with %s leaked %d temporary node(s)." % [label, leaked]
		)


# --- the director's own failure path ----------------------------------------


## A real door, a mistyped spawn: the director's path has to fail the same way the host
## does, and hand control back instead of leaving the player behind a black fade.
func _check_director_refusal() -> void:
	if not await _enter(CLASSROOM, &"PlayerStart"):
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	await _frames(1)
	var classroom := _host.get_current()
	var door := _find_exit(classroom, &"classroom_door")
	if door == null:
		_failures.append("The classroom has no 'classroom_door' exit any more.")
		return
	var q_actor := classroom.find_actor(&"q")
	if q_actor == null:
		_failures.append("The classroom has no Q to keep alive across a failed transition.")
	var q_count := _count_q()
	var saved_required := door.required_flag
	var saved_spawn := door.destination_spawn
	# Open the door regardless of the story and give it a spawn nobody authored. The
	# instance is a local copy; the scene file is untouched.
	door.required_flag = &""
	door.destination_spawn = &"FromClassroom_Mistyped"

	var before := _snapshot()
	await _sequence._handle_exit(door)
	await _frames(2)
	_expect_untouched("a mistyped door spawn", before)
	if is_instance_valid(q_actor) and not q_actor.is_inside_tree():
		_failures.append("Q left the tree when a mistyped door spawn was refused.")
	if _count_q() != q_count:
		_failures.append(
			"A refused transition changed the number of Q actors: %d, was %d."
			% [_count_q(), q_count]
		)
	if not _player.is_control_enabled():
		_failures.append("A refused transition never gave control back to the player.")
	# Leave the door as the scene shipped it, in case later checks look at it.
	if is_instance_valid(door):
		door.destination_spawn = saved_spawn
		door.required_flag = saved_required


## The same door, this time with the spawn it ships with: the director's success path
## must leave the story flag describing the room the player is actually standing in.
func _check_director_transition() -> void:
	var classroom := _host.get_current()
	if classroom == null or classroom.location_id != &"classroom":
		_failures.append("The director transition did not start from the classroom.")
		return
	var door := _find_exit(classroom, &"classroom_door")
	if door == null:
		_failures.append("The classroom has no 'classroom_door' exit any more.")
		return
	var destination_spawn := door.destination_spawn
	var signal_count := _entered.size()
	door.required_flag = &""
	await _sequence._handle_exit(door)
	await _frames(2)

	var entered := _host.get_current()
	if entered == null or entered.location_id != &"corridor":
		_failures.append("Walking through the classroom door did not enter the corridor.")
		return
	if _entered.size() != signal_count + 1:
		_failures.append(
			"One successful transition emitted location_entered %d time(s)."
			% (_entered.size() - signal_count)
		)
	elif _entered[signal_count]["spawn_id"] != destination_spawn:
		_failures.append(
			"The transition reported spawn '%s', expected '%s'."
			% [str(_entered[signal_count]["spawn_id"]), str(destination_spawn)]
		)
	var flag: Variant = _game_state.get_flag(StoryFlags.CURRENT_LOCATION, &"")
	if String(flag) != "corridor":
		_failures.append(
			"After entering the corridor CURRENT_LOCATION is '%s', not the room the "
			% str(flag)
			+ "player is in."
		)
	var spawn := entered.get_spawn(destination_spawn)
	if spawn == null:
		_failures.append("The corridor lost its '%s' spawn." % str(destination_spawn))
		return
	_expect_at("the classroom door", spawn.global_transform)


# --- every shipped exit ------------------------------------------------------


## Every exit the game ships, taken for real: the destination exists, declares the id
## the exit claims, has the named marker, and that marker is walkable ground by the door
## the player comes back through.
func _check_every_shipped_exit() -> void:
	var checked := 0
	for source: String in LOCATIONS:
		var source_scene := "res://scenes/locations/%s/%s.tscn" % [source, source]
		var exits := _read_exits(source_scene)
		if exits.is_empty():
			_failures.append("The %s has no exits at all." % source)
			continue
		for exit_data: Dictionary in exits:
			if bool(exit_data["milestone"]):
				continue
			checked += 1
			await _check_one_exit(source, source_scene, exit_data)
	if checked < 12:
		_failures.append(
			"Only %d exit(s) were exercised; the game ships more than that." % checked
		)
	_report_arrival_geometry()


func _check_one_exit(source: String, source_scene: String, exit_data: Dictionary) -> void:
	var label := "%s/%s" % [source, exit_data["interact_id"]]
	var scene := String(exit_data["scene"])
	var spawn_id := StringName(exit_data["spawn"])
	var location_id := StringName(exit_data["id"])
	if not ResourceLoader.exists(scene):
		_failures.append("%s: the destination scene '%s' does not exist." % [label, scene])
		return
	if String(location_id).is_empty():
		_failures.append("%s: the exit declares no destination_id." % label)
		return
	if not _host.load_location(scene, spawn_id, _player, location_id):
		_failures.append(
			"%s: entering '%s' at spawn '%s' failed." % [label, scene, String(spawn_id)]
		)
		return
	await _frames(2)
	var entered := _host.get_current()
	if entered == null or entered.location_id != location_id:
		_failures.append(
			"%s: entered '%s' but the current location is '%s'."
			% [label, str(location_id), str(entered.location_id) if entered != null else "none"]
		)
		return
	if _host.get_current_path() != scene:
		_failures.append(
			"%s: the current path is '%s', expected '%s'."
			% [label, _host.get_current_path(), scene]
		)
	var marker := entered.get_spawn(spawn_id)
	if marker == null:
		_failures.append("%s: '%s' has no spawn '%s'." % [label, scene, String(spawn_id)])
		return
	if _player.global_position.distance_to(marker.global_position) > 0.01:
		_failures.append(
			"%s: the player arrived at %s, not at the marker %s."
			% [label, str(_player.global_position), str(marker.global_position)]
		)
	await _check_walkable(label, entered, marker)
	_check_return_marker(label, source_scene, entered, marker)


## The arrival point has to be on the navigation mesh, or the player is dropped
## somewhere they cannot walk out of.
func _check_walkable(label: String, location: LocationRoot, marker: Node3D) -> void:
	var routable := await _wait_for_navigation(location)
	if not routable:
		# navigation_test.gd fails a location that never becomes routable; here the
		# missing mesh only makes this particular check impossible.
		return
	var map := _player.navigation_agent.get_navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map, marker.global_position)
	var offset := Vector2(
		closest.x - marker.global_position.x, closest.z - marker.global_position.z
	).length()
	_arrival_offsets[label] = offset


## Coming back has to put the player by the door they came back through, not across the
## room: the arrival marker and the exit back to the same place are compared where both
## live, in the destination scene.
func _check_return_marker(
	label: String, source_scene: String, location: LocationRoot, marker: Node3D
) -> void:
	var back := _find_exit_to(location, source_scene)
	if back == null:
		return
	var marker_point := location.global_transform.affine_inverse() * marker.global_position
	var back_point := location.global_transform.affine_inverse() * back.global_position
	var distance := Vector2(marker_point.x - back_point.x, marker_point.z - back_point.z).length()
	_return_distances[label] = distance


## One verdict for the whole sweep, with the numbers in it: a failure names every
## arrival that is too far off the mesh or too far from the way back.
func _report_arrival_geometry() -> void:
	var lines: Array[String] = []
	for label: String in _arrival_offsets:
		lines.append("%s off-mesh %.2f m" % [label, float(_arrival_offsets[label])])
	print("DIAG arrival geometry: %s" % "; ".join(lines))
	var worst_label := ""
	var worst := 0.0
	for label: String in _arrival_offsets:
		var offset := float(_arrival_offsets[label])
		if offset > worst:
			worst = offset
			worst_label = label
	if worst > ENTRY_TOLERANCE:
		_failures.append(
			"%s lands %.2f m off the navigation mesh (limit %.1f m); all arrivals: %s"
			% [worst_label, worst, ENTRY_TOLERANCE, "; ".join(lines)]
		)
	var farthest_label := ""
	var farthest := 0.0
	for label: String in _return_distances:
		var distance := float(_return_distances[label])
		if distance > farthest:
			farthest = distance
			farthest_label = label
	if farthest > RETURN_PROXIMITY:
		var details: Array[String] = []
		for label: String in _return_distances:
			details.append("%s %.1f m" % [label, float(_return_distances[label])])
		_failures.append(
			"%s arrives %.1f m from the exit that leads back (limit %.1f m): %s"
			% [farthest_label, farthest, RETURN_PROXIMITY, "; ".join(details)]
		)


# --- fixtures ----------------------------------------------------------------


## Packs a tiny location into `user://` and returns its path ("" when packing failed).
##
## `use_location_root` false packs a plain Node3D, which is the "wrong root" case; an
## empty `location_id` is the "missing id" case. Markers are real `spawn_point` members,
## so the loader sees exactly what it would see in an authored scene.
func _pack_fixture(
	name: String, location_id: StringName, use_location_root: bool, markers: Array
) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	var root_node: Node3D = LocationRoot.new() if use_location_root else Node3D.new()
	root_node.name = "Fixture" + name.to_pascal_case()
	if use_location_root:
		(root_node as LocationRoot).location_id = location_id
	for spec: Dictionary in markers:
		var marker := Marker3D.new()
		marker.name = String(spec["name"])
		marker.position = spec.get("position", Vector3.ZERO)
		marker.basis = spec.get("basis", Basis.IDENTITY)
		marker.add_to_group("spawn_point")
		root_node.add_child(marker)
		marker.owner = root_node
	var packed := PackedScene.new()
	var error := packed.pack(root_node)
	root_node.free()
	if error != OK:
		_failures.append("Could not pack the '%s' fixture (error %d)." % [name, error])
		return ""
	var path := "%s/%s.tscn" % [FIXTURE_DIR, name]
	error = ResourceSaver.save(packed, path)
	if error != OK:
		_failures.append("Could not save the '%s' fixture (error %d)." % [name, error])
		return ""
	return path


# --- helpers ----------------------------------------------------------------


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


## Loads `scene` at `spawn` and reports whether it succeeded; failures are recorded once
## by the caller.
func _enter(scene: String, spawn: StringName, expected: StringName = &"") -> bool:
	if not _host.load_location(scene, spawn, _player, expected):
		_failures.append(
			"Entering '%s' at spawn '%s' failed." % [scene, _describe_spawn(spawn)]
		)
		return false
	await _frames(2)
	return true


func _expect_at(label: String, target: Transform3D) -> void:
	var offset := _player.global_position.distance_to(target.origin)
	if offset > 0.01:
		_failures.append(
			"%s: the player stands %.3f m from the spawn at %s (player at %s)."
			% [label, offset, str(target.origin), str(_player.global_position)]
		)


func _snapshot() -> Dictionary:
	return {
		"location": _host.get_current(),
		"path": _host.get_current_path(),
		"position": _player.global_position,
		"facing": _player.get_facing_direction(),
		"flag": _game_state.get_flag(StoryFlags.CURRENT_LOCATION, &""),
		"signals": _entered.size(),
		"children": _host.get_child_count(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


## Exits as plain data, read from a detached instance: no `_ready()`, no groups, no side
## effects — the scene file is the only source.
func _read_exits(scene_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("Could not load '%s'." % scene_path)
		return result
	var instance := packed.instantiate() as LocationRoot
	if instance == null:
		_failures.append("'%s' is not a LocationRoot." % scene_path)
		return result
	var exits := _exits_of(instance)
	instance.free()
	return exits


func _exits_of(location: LocationRoot) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for interactable in location.get_interactables():
		var exit := interactable as LocationExit
		if exit == null:
			continue
		result.append({
			"interact_id": String(exit.interact_id),
			"scene": exit.destination_scene,
			"spawn": String(exit.destination_spawn),
			"id": String(exit.destination_id),
			"milestone": exit.is_milestone_end,
		})
	return result


func _find_exit(location: LocationRoot, exit_id: StringName) -> LocationExit:
	for interactable in location.get_interactables():
		var exit := interactable as LocationExit
		if exit != null and exit.interact_id == exit_id:
			return exit
	return null


func _find_exit_to(location: LocationRoot, scene_path: String) -> LocationExit:
	for interactable in location.get_interactables():
		var exit := interactable as LocationExit
		if exit != null and exit.destination_scene == scene_path:
			return exit
	return null


func _count_q() -> int:
	var count := 0
	for node: Node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor != null and String(actor.npc_id) == "q" and actor.is_inside_tree():
			count += 1
	return count


## Waits until the location's navigation answers queries, so a mesh query means
## something. Bounded: a location that never becomes routable is navigation_test's
## failure, not this test's.
func _wait_for_navigation(location: LocationRoot) -> bool:
	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		return false
	var budget := 0
	while budget < 120:
		if nav.is_baked() and nav.is_routable():
			return true
		await physics_frame
		budget += 1
	return false


func _describe_spawn(spawn: StringName) -> String:
	return "<default>" if String(spawn).is_empty() else String(spawn)
