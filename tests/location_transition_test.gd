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
## 4b. a refused `LocationFlow.transition_to()` runs the caller's `on_failure` exactly once,
##    behind the black, with the beat still held and the old room current; it awaits a
##    coroutine recovery, gives the room back even when the recovery never finishes, never
##    writes `arrival_flags`, and a successful transition never calls it (issue #148);
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
	Harness.stage = "failure recovery contract"
	await _check_failure_recovery_contract()
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
	# A rejected instance that was instantiated and then abandoned is an orphan: no
	# parent, outside the tree, still alive. That is exactly the leak to catch, and it
	# does not move when a legitimate scene is added or freed.
	var orphans := int(after["orphans"]) - int(before["orphans"])
	if orphans != 0:
		_failures.append(
			"A transition with %s left %d unfreed node(s) behind." % [label, orphans]
		)
	if int(after["roots"]) != int(before["roots"]):
		_failures.append(
			"A transition with %s left %d LocationRoot instance(s) in the tree."
			% [label, int(after["roots"])]
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


# --- failure recovery (issue #148) -------------------------------------------


## `on_failure` against the real flow, fade and beat. Starts in the corridor (the director
## transition above left the player there) and ends back in the classroom.
func _check_failure_recovery_contract() -> void:
	var flow: LocationFlow = _sequence.get("_flow") as LocationFlow
	var ui := _main.get_node_or_null("GameUI") as GameUI
	if flow == null or ui == null or _host.get_current() == null:
		_failures.append("The failure-recovery contract has no flow, UI or current room.")
		return
	var marker := &"test_arrival_marker_148"
	var missing := "%s/missing_destination.tscn" % FIXTURE_DIR

	# 1. A plain callback: once, behind the black, inside the beat, in the old room.
	var calls: Array[Dictionary] = []
	var spy := func() -> void:
		calls.append(
			{
				"beat": _sequence.is_beat_active(),
				"alpha": ui.fade.color.a,
				"room": _host.get_current(),
				"flag": _game_state.get_flag(StoryFlags.CURRENT_LOCATION, &""),
			}
		)
	var before := _snapshot()
	var entered: bool = await flow.transition_to(
		missing, &"Nowhere", &"nowhere",
		{"label": "the #148 contract", "on_failure": spy, "arrival_flags": {marker: true}}
	)
	await _frames(2)
	_expect_untouched("a missing scene and an on_failure", before)
	if entered:
		_failures.append("transition_to() reported success for a scene that does not exist.")
	if calls.size() != 1:
		_failures.append("A refused transition called on_failure %d time(s), not once." % calls.size())
	else:
		var seen: Dictionary = calls[0]
		if not bool(seen["beat"]):
			_failures.append("on_failure ran after the transition beat was released.")
		if float(seen["alpha"]) < 0.99:
			_failures.append(
				"on_failure ran with the screen already %.2f opaque, not black." % float(seen["alpha"])
			)
		if seen["room"] != before["location"]:
			_failures.append("on_failure ran when the old room was no longer current.")
		if seen["flag"] != before["flag"]:
			_failures.append("CURRENT_LOCATION had changed by the time on_failure ran.")
	_expect_returned("a refused transition with on_failure", ui)
	if _game_state.has_flag(marker):
		_failures.append("A refused transition wrote its arrival_flags.")

	# 2. A coroutine recovery is awaited: the screen stays black until it has finished.
	var finished_at: Array[float] = []
	var slow := func() -> void:
		await create_timer(0.4, false).timeout
		finished_at.append(ui.fade.color.a)
	entered = await flow.transition_to(missing, &"Nowhere", &"nowhere", {"on_failure": slow})
	await _frames(2)
	if entered or finished_at.size() != 1:
		_failures.append(
			"A coroutine on_failure finished %d time(s) (transition %s)." % [finished_at.size(), entered]
		)
	elif finished_at[0] < 0.99:
		_failures.append(
			"The room faded back in (%.2f opaque) before a coroutine on_failure finished."
			% finished_at[0]
		)
	_expect_returned("a coroutine on_failure", ui)

	# 3. A recovery that never finishes (what a coroutine stopped by an error after its
	#    first await looks like from outside) cannot keep the beat or the black.
	var never := Timer.new()
	root.add_child(never)
	var stuck := func() -> void:
		await never.timeout
	var started := Time.get_ticks_msec()
	entered = await flow.transition_to(missing, &"Nowhere", &"nowhere", {"on_failure": stuck})
	await _frames(2)
	var waited := (Time.get_ticks_msec() - started) / 1000.0
	never.queue_free()
	if entered:
		_failures.append("A stuck on_failure turned a refused transition into a success.")
	_expect_returned("an on_failure that never finishes", ui)
	if waited > (LocationFlow.FAILURE_RECOVERY_LIMIT + 4.0):
		_failures.append("A stuck on_failure held the room for %.1f s of real time." % waited)

	# 4. No on_failure: the ordinary refusal, and still no arrival flags.
	before = _snapshot()
	entered = await flow.transition_to(
		missing, &"Nowhere", &"nowhere", {"arrival_flags": {marker: true}}
	)
	await _frames(2)
	_expect_untouched("a missing scene without on_failure", before)
	_expect_returned("a refused transition without on_failure", ui)
	if entered or _game_state.has_flag(marker):
		_failures.append("A plain refused transition succeeded or wrote its arrival_flags.")

	# 5. A transition that succeeds never calls it.
	var success_calls: Array[int] = []
	entered = await flow.transition_to(
		CLASSROOM, &"FromCorridor", &"classroom",
		{"on_failure": func() -> void: success_calls.append(1)}
	)
	await _wait_for_rest()
	if not entered or _host.get_current() == null or _host.get_current().location_id != &"classroom":
		_failures.append("The corridor -> classroom transition used by the contract failed.")
	if not success_calls.is_empty():
		_failures.append("A successful transition called on_failure.")


## After a refused transition: no beat, control back, the screen clear.
func _expect_returned(label: String, ui: GameUI) -> void:
	if _sequence.is_beat_active():
		_failures.append("After %s the transition beat is still held." % label)
	if not _player.is_control_enabled():
		_failures.append("After %s the player has no control." % label)
	if ui.fade.color.a > 0.01:
		_failures.append("After %s the screen is still %.2f black." % [label, ui.fade.color.a])


## Waits for the arrival line and the checkpoint that follow a successful transition.
func _wait_for_rest() -> void:
	var dialogue := _main.get_node_or_null("DialogueController") as DialogueController
	for _index in 1200:
		if dialogue != null and dialogue.is_busy():
			if dialogue.has_pending_choices():
				dialogue.select_choice(0)
			else:
				dialogue.advance_presentation()
		elif not _sequence.is_beat_active():
			break
		await process_frame
	await _frames(2)


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
	await _check_the_flats_and_the_lane_connect()
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
	# Read before any frame runs: this is the transform the host handed the body.
	var landed := _player.global_position
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
	if landed.distance_to(marker.global_position) > 0.01:
		_failures.append(
			"%s: the player was placed at %s, not at the marker %s."
			% [label, str(landed), str(marker.global_position)]
		)
	# Once a couple of frames have run the body has settled onto the floor, which may sit
	# a few centimetres below the marker; what must not happen is sliding somewhere else.
	var settled := _player.global_position
	var drift := Vector2(settled.x - marker.global_position.x, settled.z - marker.global_position.z).length()
	if drift > 0.3:
		_failures.append(
			"%s: after arriving the player drifted %.2f m from the marker." % [label, drift]
		)
	if absf(settled.y - marker.global_position.y) > 0.6:
		_failures.append(
			"%s: the player is %.2f m %s the marker vertically."
			% [label, absf(settled.y - marker.global_position.y), "below" if settled.y < marker.global_position.y else "above"]
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
	_arrival_offsets[label] = await _settled_offset(map, marker.global_position)


## How far a point sits off the map, measured once the server has stopped changing its
## mind about what the map contains.
##
## The server rebuilds a map on its own schedule, and a query taken while it is rebuilding
## answers from the surface that was there before the last change - right after a location
## swap, the room that was just freed. Sampling that window produced arrivals reported 5,
## 9 and 25 m off the mesh on runs where the same marker measured 0.00 m on the next one.
##
## This waits for the answer to stop moving, which is the same number a second later; it
## does not wait for the answer to be *good*. A marker that really is off the mesh settles
## at its real distance and fails, and the failure carries the distance it settled on.
func _settled_offset(map: RID, point: Vector3) -> float:
	var previous := -1.0
	var stable := 0
	var offset := _offset_of(map, point)
	for _frame in 180:
		if absf(offset - previous) < 0.001:
			stable += 1
			if stable >= 3:
				return offset
		else:
			stable = 0
		previous = offset
		await physics_frame
		offset = _offset_of(map, point)
	return offset


func _offset_of(map: RID, point: Vector3) -> float:
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length()


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


## The courtyard and the lane behind the flats, walked between each other (issue #33).
##
## The pair used to be connected only in the story: the way out of the courtyard ran
## across a mesh-only strip of asphalt with no collider under it, and the way back out of
## the lane dropped the player on the same dead strip. Both directions are checked here
## as routes, not as markers within tolerance of something: a route from the point the
## player arrives on to the exit they leave through, long enough to be a route.
func _check_the_flats_and_the_lane_connect() -> void:
	# Through the mouth in the north block: the courtyard spawn is ~43 m from the exit,
	# so a closed way shows up as a path that stops short of it.
	await _check_one_route("residential", &"FromStreet", &"res_alley_end", 30.0)
	# And back out of the lane, which is the direction that used to land off the mesh.
	await _check_one_route("alley", &"FromCourtyard", &"alley_back_to_courtyard", 1.0)


func _check_one_route(
	location_name: String, spawn_id: StringName, exit_id: StringName, minimum: float
) -> void:
	var label := "%s/%s" % [location_name, String(exit_id)]
	var scene := "res://scenes/locations/%s/%s.tscn" % [location_name, location_name]
	if not _host.load_location(scene, spawn_id, _player, StringName(location_name)):
		_failures.append("%s: could not enter the %s at '%s'." % [label, location_name, String(spawn_id)])
		return
	var location := _host.get_current()
	if location == null:
		_failures.append("%s: the %s did not become the current location." % [label, location_name])
		return
	var exit := _find_exit(location, exit_id)
	if exit == null:
		_failures.append("%s: the %s has no exit '%s'." % [label, location_name, String(exit_id)])
		return
	if not await _wait_for_navigation(location):
		_failures.append("%s: the %s never baked a routable mesh." % [label, location_name])
		return
	var map := _player.navigation_agent.get_navigation_map()
	var away := await _settled_offset(map, exit.global_position)
	var from := NavigationServer3D.map_get_closest_point(map, _player.global_position)
	var to := NavigationServer3D.map_get_closest_point(map, exit.global_position)
	if away > 1.5:
		_failures.append(
			"%s: the exit sits %.2f m off the %s's navigation mesh." % [label, away, location_name]
		)
		return
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	print("DIAG walk %s: %.2f m over %d point(s)" % [label, length, path.size()])
	if path.size() < 2 or length < minimum:
		_failures.append(
			"%s: the route from the arrival point to that exit is %.2f m over %d point(s), "
			% [label, length, path.size()]
			+ "so the two spaces are not walkable between each other."
		)


## One verdict for the whole sweep, with the numbers in it: a failure names every
## arrival that is too far off the mesh or too far from the way back.
func _report_arrival_geometry() -> void:
	var lines: Array[String] = []
	for label: String in _arrival_offsets:
		lines.append("%s off-mesh %.2f m" % [label, float(_arrival_offsets[label])])
	print("DIAG arrival geometry: %s" % "; ".join(lines))
	# No allowlist: an arrival that lands off the mesh fails here, whatever its reason.
	# The one entry this test used to carry was the way back out of the alley, and it
	# went away with the alley mouth itself (issue #33).
	for label: String in _arrival_offsets:
		var offset := float(_arrival_offsets[label])
		if offset > ENTRY_TOLERANCE:
			_failures.append(
				"%s lands %.2f m off the navigation mesh (limit %.1f m); all arrivals: %s"
				% [label, offset, ENTRY_TOLERANCE, "; ".join(lines)]
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
		# Persistent: a group added at run time is not serialized unless it is marked so,
		# and a fixture whose marker is not in the group has no spawn at all.
		marker.add_to_group("spawn_point", true)
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


## The player stands on `target`. Horizontal placement is exact; vertically a couple of
## frames of gravity may have settled the body onto a floor a few centimetres lower.
func _expect_at(label: String, target: Transform3D) -> void:
	var here := _player.global_position
	var horizontal := Vector2(here.x - target.origin.x, here.z - target.origin.z).length()
	var vertical := absf(here.y - target.origin.y)
	if horizontal > 0.05 or vertical > 0.6:
		_failures.append(
			"%s: the player stands %.3f m from the spawn at %s (player at %s)."
			% [label, Vector2(horizontal, vertical).length(), str(target.origin), str(here)]
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
		"roots": _count_location_roots(),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
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


## Every LocationRoot currently in the tree under the main scene: a refused transition
## must leave exactly the one that was already there.
func _count_location_roots() -> int:
	var count := 0
	for node in _descendants(_main):
		if node is LocationRoot:
			count += 1
	return count


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


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
	# One readiness rule for the whole project: `LocationNavigation.is_synchronized()`,
	# which is baked + the map has synchronized once + this region is on it + the map
	# answers for a spread of this mesh's own vertices. The old test asked `is_routable()`,
	# which answers "a route exists somewhere on this map" - and on the frame of a swap the
	# map is still answering about the room that was just freed.
	if await nav.wait_until_synchronized():
		return true
	_failures.append(
		"the %s's navigation map never synchronized with its baked mesh: %s"
		% [String(location.location_id), nav.describe_sync()]
	)
	return false


func _describe_spawn(spawn: StringName) -> String:
	return "<default>" if String(spawn).is_empty() else String(spawn)
