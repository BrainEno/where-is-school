extends SceneTree
## Save a session, throw the world away, and build it again from the file.
##
## This is the end-to-end half of #60's acceptance: a real `main.tscn` is played into a
## known state, `autosave()` writes it, the scene is freed, the state nodes are wiped,
## and a second `main.tscn` is instantiated. If the second one comes back in the right
## room, on the right marker, at the right spot, with the flags, knowledge and dice
## seed of the first, then "quit and come back" works - which is the only thing a
## player will ever test.
##
## The companion section (#94) plays Q's whole save life through the same real scene:
## leave the classroom through its door so the real arrival joins Q and writes the
## real checkpoint, quit, and come back in the corridor; then save and come back in the
## yard and in the classroom. Q has to be there as soon as the restored session is up -
## joined, visible, solid, beside the player, and following a player who walks away along
## the navigation route - without one more door. In the classroom the room's
## own Q is the only one on screen. A save from before Q joined must not produce one.
##
## The last section is the other half: a file nobody can read must not silently reset
## the run, so the game is expected to refuse it, keep a copy, say so on screen, and
## start a new game.

const Harness = preload("res://tests/test_harness.gd")
const MAIN_SCENE := "res://scenes/main/main.tscn"
const SAVE_PATH := "user://save.json"
const BROKEN_PATH := "user://save.broken.json"
const CLASSROOM_SCENE := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR_SCENE := "res://scenes/locations/corridor/corridor.tscn"
const PLAYGROUND_SCENE := "res://scenes/locations/playground/playground.tscn"
## Where the yard save stands the player: on the court, three metres in from the school
## door, so that walking back towards the door is open ground the yard's own spawn uses.
const YARD_STANDING := Vector3(-3.0, 0.0, -12.0)
## How far behind a walking player Q may be once it has had time to catch up. The same
## slack as `companion_route_test.gd`.
const FOLLOW_TOLERANCE := 0.6
## Physics frames Q gets to report that the room's navigation answers, and to close the
## gap after the walk. Counted in physics frames because that is what Q moves on.
const NAVIGATION_WAIT_FRAMES := 240
const CATCH_UP_FRAMES := 300

var _failures: Array[String] = []

var _game_state: Node = null
var _narrative: Node = null
var _save: Node = null
## One line per restored room, printed as a notice: what was measured, not just that it
## passed.
var _companion_notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "save_roundtrip_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_save = autoloads["save"]
	if _game_state == null or _narrative == null or _save == null:
		Harness.finish(self, ["The state or save autoload could not be created."], "")
		return
	Harness.clear_session_state(self)

	await _check_round_trip()
	await _check_failed_write_keeps_the_run()
	await _check_companion_restore()
	await _check_save_without_companion()
	if not _companion_notes.is_empty():
		print("::notice title=companion restore::%s" % " | ".join(_companion_notes))
	await _check_refusal_at_boot()

	Harness.finish(
		self,
		_failures,
		"a saved run comes back whole, a write that cannot land costs nothing, Q comes back"
		+ " with it in the corridor, the yard and the classroom, and a broken save is refused"
		+ " out loud."
	)


# --- The round trip ---------------------------------------------------------


func _check_round_trip() -> void:
	Harness.stage = "the first run"
	var main := await _enter_main()
	if main == null:
		return
	var sequence := main.get_node_or_null("OpeningSequence")
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var player := main.get_node_or_null("Player") as PlayerController
	var dialogue := main.get_node_or_null("DialogueController")
	if sequence == null or host == null or player == null or dialogue == null:
		_failures.append("main.tscn is missing a node the save system needs.")
		main.free()
		return
	if host.get_current() == null:
		_failures.append("The classroom did not load, so there is nothing to save.")
		main.free()
		return

	# A session in a known state: the prologue behind it, knowledge recorded, a seed
	# chosen, and a body somewhere that is not the spawn marker.
	for flag in [
		StoryFlags.MET_Q,
		StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED,
		StoryFlags.BELL_RUNG,
		StoryFlags.CLASS_DISMISSED,
	]:
		_game_state.set_flag(flag, true)
	_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.leave_classroom")
	_narrative.record(
		&"seen_board", NarrativeEntry.Source.OBSERVED, &"protagonist", "The board, read."
	)
	_narrative.record(
		&"claim_b_strict", NarrativeEntry.Source.REPORTED, &"q", "Q says B is strict."
	)
	dialogue.set_session_seed(31337)
	var standing := Transform3D(Basis.IDENTITY, Vector3(1.4, 0.6, -2.2))
	player.teleport(standing)
	await _physics_frames(2)
	var saved_position := player.global_position
	var saved_location := host.get_current().location_id
	var saved_spawn := host.get_current_spawn()

	Harness.stage = "writing the file"
	var written: Dictionary = sequence.call("autosave", "test")
	_expect(written.get("ok", false) == true, "autosave() did not write a file: %s" % str(written))
	_expect(_save.has_save(), "autosave() reported success but there is no save file.")
	var read: Dictionary = _save.read_save()
	_expect(read["ok"] == true, "The file just written does not read back: %s" % str(read))
	_expect(int(read.get("version", 0)) == SaveCodec.VERSION, "The file's version is wrong.")

	# Tear the world down. The state nodes are wiped by hand, not through the harness:
	# `clear_session_state()` deletes the save file too, and that is the thing under test.
	main.queue_free()
	await _frames(3)
	_game_state.clear()
	_narrative.clear()
	_expect(
		not is_instance_valid(dialogue),
		"The scene was freed but its dialogue controller is still alive."
	)
	dialogue = null

	Harness.stage = "the second run"
	var again := await _enter_main()
	if again == null:
		return
	var sequence_again := again.get_node_or_null("OpeningSequence")
	var host_again := again.get_node_or_null("LocationHost") as LocationHost
	var player_again := again.get_node_or_null("Player") as PlayerController
	var dialogue_again := again.get_node_or_null("DialogueController")

	_expect(
		_game_state.get_flag(StoryFlags.MET_Q, false) == true,
		"The prologue flags did not come back."
	)
	_expect(
		_game_state.get_flag(StoryFlags.CLASS_DISMISSED, false) == true,
		"The last prologue step's flag did not come back."
	)
	_expect(
		String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.leave_classroom",
		"The objective line did not come back."
	)
	_expect(
		String(sequence_again.next_step()).is_empty(),
		"The director wants to replay '%s' after a finished prologue."
		% String(sequence_again.next_step())
	)
	_expect(
		_narrative.get_entries().size() == 2,
		"Expected 2 knowledge entries after the restore, found %d."
		% _narrative.get_entries().size()
	)
	_expect(
		_narrative.get_entry(&"claim_b_strict") != null
		and _narrative.get_entry(&"claim_b_strict").source == NarrativeEntry.Source.REPORTED,
		"A reported claim came back as something else."
	)
	_expect(
		dialogue_again != null and dialogue_again.get_session_seed() == 31337,
		"The dice seed did not come back, so checks would reroll after a load."
	)
	if host_again == null or player_again == null:
		_failures.append("The restored scene has no LocationHost or Player.")
		again.free()
		return
	var restored_location := host_again.get_current()
	_expect(restored_location != null, "The restored scene has no current location.")
	if restored_location != null:
		_expect(
			restored_location.location_id == saved_location,
			"Restored into '%s', was in '%s'."
			% [String(restored_location.location_id), String(saved_location)]
		)
	_expect(
		host_again.get_current_spawn() == saved_spawn,
		"Restored spawn '%s', saved '%s'."
		% [String(host_again.get_current_spawn()), String(saved_spawn)]
	)
	await _physics_frames(2)
	var drift := player_again.global_position.distance_to(saved_position)
	_expect(
		drift < 0.25,
		"The body came back %.2f m from where it stood (saved %s, restored %s)."
		% [drift, str(saved_position), str(player_again.global_position)]
	)

	# Saving again from the restored session must produce a file that still reads.
	Harness.stage = "saving the restored session"
	var rewritten: Dictionary = sequence_again.call("autosave", "after_restore")
	_expect(rewritten.get("ok", false) == true, "The restored session could not be saved again.")

	again.queue_free()
	await _frames(3)


# --- A write that cannot land (#122) -------------------------------------------


## The other half of "never lose a save": a write that cannot be installed must cost
## nothing. The run on disk stays exactly as it was, byte for byte, and the next boot
## resumes *it* — not an empty game, and not half of a new one.
##
## The failure is injected rather than provoked: a real disk will not refuse a rename on
## request, and the window this has to survive is the middle of a replacement.
func _check_failed_write_keeps_the_run() -> void:
	_reset_session()
	Harness.stage = "a write that cannot land"
	var main := await _enter_main()
	if main == null:
		return
	var sequence := main.get_node_or_null("OpeningSequence")
	var host := main.get_node_or_null("LocationHost") as LocationHost
	if sequence == null or host == null or host.get_current() == null:
		_failures.append("main.tscn is missing a node the save system needs.")
		main.free()
		return
	_game_state.set_flag(StoryFlags.MET_Q, true)
	_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")
	_narrative.record(
		&"kept_entry", NarrativeEntry.Source.OBSERVED, &"", "A line a failed write must not lose."
	)
	var first: Dictionary = sequence.call("autosave", "before")
	_expect(first.get("ok", false) == true, "the first autosave did not write a file: %s" % str(first))
	var before := FileAccess.get_file_as_bytes(SAVE_PATH)
	var location := host.get_current().location_id
	_expect(not before.is_empty(), "the first autosave left no bytes on disk.")

	# Every rename fails, so nothing can be installed: this is the replacement giving up.
	var faults := FaultyIO.new()
	faults.fail_renames = [0, 1, 2, 3, 4, 5]
	_save.set("io", faults)
	var refused: Dictionary = sequence.call("autosave", "after")
	_save.set("io", null)

	_expect(
		refused.get("ok", true) == false,
		"a write that could not be installed was reported as written: %s" % str(refused)
	)
	_expect(
		String(refused.get("reason", "")) == "write",
		"the failed write was reported as '%s'." % refused.get("reason")
	)
	_expect(
		not String(refused.get("detail", "")).is_empty(),
		"the failed write does not say what happened."
	)
	_expect(
		not String(refused.get("recovery_path", "")).is_empty(),
		"the failed write names no recovery path."
	)
	_expect(
		FileAccess.get_file_as_bytes(SAVE_PATH) == before,
		"a write that could not be installed changed the save on disk."
	)
	_expect(_read_back_flags().has(&"kept_entry"), "the knowledge entry vanished from the file.")
	_expect(_strays().is_empty(), "the failed write left %s behind." % str(_strays()))

	# Now the boot that matters: the world is gone, the state is wiped, and only the file
	# can bring the run back. It has to be the run that was there before the failure.
	main.queue_free()
	await _frames(3)
	_game_state.clear()
	_narrative.clear()
	var again := await _enter_main()
	if again == null:
		return
	var host_again := again.get_node_or_null("LocationHost") as LocationHost
	_expect(
		_game_state.get_flag(StoryFlags.MET_Q, false) == true,
		"the run that survived the failed write did not come back."
	)
	_expect(
		String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.check_bag",
		"the objective did not come back after a failed write."
	)
	_expect(
		_narrative.get_entry(&"kept_entry") != null,
		"the knowledge entry did not come back after a failed write."
	)
	_expect(
		host_again != null and host_again.get_current() != null
		and host_again.get_current().location_id == location,
		"the restored session is not in the room it was saved in."
	)
	again.queue_free()
	await _frames(3)


## The real file layer, with every rename refused: the replacement cannot be installed
## and cannot fall back either.
class FaultyIO:
	var fail_renames: Array = []
	var renames := 0

	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> PackedByteArray:
		return FileAccess.get_file_as_bytes(path)

	func write_bytes(path: String, data: PackedByteArray) -> int:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(data)
		var error := file.get_error()
		file.close()
		return error

	func rename(from: String, to: String) -> int:
		var index := renames
		renames += 1
		if fail_renames.has(index):
			return ERR_FILE_CANT_WRITE
		var dir := DirAccess.open("user://")
		if dir == null:
			return DirAccess.get_open_error()
		return dir.rename(from, to)

	func remove(path: String) -> int:
		var dir := DirAccess.open("user://")
		if dir == null:
			return DirAccess.get_open_error()
		return dir.remove(path)

	func list() -> PackedStringArray:
		var dir := DirAccess.open("user://")
		if dir == null:
			return PackedStringArray()
		return dir.get_files()


## The flags the save on disk holds, read without touching the session.
func _read_back_flags() -> Dictionary:
	var read: Dictionary = _save.read_save()
	if read.get("ok", false) != true:
		_failures.append("the save on disk cannot be read: %s" % str(read))
		return {}
	var decoded: Dictionary = SaveCodec.decode_flags(read["payload"].get("flags", {}))
	return decoded.get("flags", {})


## Every file the save system may leave beside the save, by name.
func _strays() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open("user://")
	if dir == null:
		return found
	for name: String in dir.get_files():
		if name.begins_with("save.json."):
			found.append(name)
	found.sort()
	return found


# --- Q after a restore (#94) --------------------------------------------------


## Q's save life, one real session at a time: joined by the real door, restored in the
## corridor, carried into the yard and restored there, carried into the classroom and
## restored there.
func _check_companion_restore() -> void:
	_reset_session()

	# --- 1. The real way Q joins: the classroom door, and the arrival checkpoint.
	Harness.stage = "companion: leaving the classroom with Q"
	var first := await _enter_settled()
	if first == null:
		return
	var sequence := first.get_node_or_null("OpeningSequence") as OpeningSequence
	var host := first.get_node_or_null("LocationHost") as LocationHost
	var player := first.get_node_or_null("Player") as PlayerController
	var companion := first.get_node_or_null("Companion") as CompanionController
	if sequence == null or host == null or player == null or companion == null \
			or host.get_current() == null:
		_failures.append("companion: main.tscn is missing a node this section needs.")
		first.free()
		return
	var interaction := player.get_node_or_null("InteractionController") as InteractionController
	for flag in [
		StoryFlags.MET_Q,
		StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED,
		StoryFlags.BELL_RUNG,
		StoryFlags.N_ARRIVED,
		StoryFlags.CLASS_DISMISSED,
	]:
		_game_state.set_flag(flag, true)
	# The beats are skipped, so control is handed over the supported way.
	sequence.allow_player_control()
	_expect(not companion.is_joined(), "companion: Q joined before the player left the classroom.")
	var door := host.get_current().find_interactable(&"classroom_door") as LocationExit
	if interaction == null or door == null or not door.is_open():
		_failures.append("companion: the classroom door is missing or still shut after dismissal.")
		first.free()
		return
	interaction.request_activation(door)
	var corridor_save := await _wait_for_checkpoint(&"corridor", 20.0)
	if corridor_save.is_empty():
		first.queue_free()
		await _frames(3)
		return
	_expect(
		_saved_flag(corridor_save, StoryFlags.Q_COMPANION),
		"companion: the corridor checkpoint does not record that Q came along."
	)
	_expect(
		companion.is_with_player(),
		"companion: Q is not with the player in the corridor the first time round."
	)
	await _settle_room(first)
	await _tear_down(first)

	# --- 2. Quit, come back in the corridor.
	Harness.stage = "companion: restoring in the corridor"
	var corridor_run := await _enter_settled()
	if corridor_run == null:
		return
	var restored := _expect_companion_restored(corridor_run, &"corridor")
	if restored:
		await _expect_companion_follows(corridor_run, "corridor")

	# --- 3. Into the yard with the restored Q, save there, come back there.
	Harness.stage = "companion: saving in the yard"
	var yard_save := await _save_in(
		corridor_run, PLAYGROUND_SCENE, &"FromCorridor", &"playground", YARD_STANDING
	)
	await _tear_down(corridor_run)
	if yard_save.is_empty():
		return
	_expect(
		_saved_flag(yard_save, StoryFlags.Q_COMPANION),
		"companion: the yard save does not record that Q came along."
	)
	Harness.stage = "companion: restoring in the yard"
	var yard_run := await _enter_settled()
	if yard_run == null:
		return
	if _expect_companion_restored(yard_run, &"playground"):
		await _expect_companion_follows(yard_run, "yard")

	# --- 4. Back into the classroom, save there, come back there.
	Harness.stage = "companion: saving in the classroom"
	var classroom_save := await _save_in(
		yard_run, CLASSROOM_SCENE, &"FromCorridor", &"classroom", Vector3.INF
	)
	await _tear_down(yard_run)
	if classroom_save.is_empty():
		return
	_expect(
		_saved_flag(classroom_save, StoryFlags.Q_COMPANION),
		"companion: the classroom save lost the companion flag."
	)
	Harness.stage = "companion: restoring in the classroom"
	var classroom_run := await _enter_settled()
	if classroom_run == null:
		return
	await _expect_companion_hidden_by_authored_q(classroom_run)
	await _tear_down(classroom_run)


## A save written before Q ever joined - the corridor reached without the door that
## starts the companion, so the flag is not in the file - must come back without Q, and
## must stay without Q while the session runs.
func _check_save_without_companion() -> void:
	_reset_session()
	Harness.stage = "companion: a save without the flag"
	var first := await _enter_settled()
	if first == null:
		return
	for flag in [
		StoryFlags.MET_Q,
		StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED,
		StoryFlags.BELL_RUNG,
		StoryFlags.N_ARRIVED,
		StoryFlags.CLASS_DISMISSED,
	]:
		_game_state.set_flag(flag, true)
	var saved := await _save_in(first, CORRIDOR_SCENE, &"FromClassroom", &"corridor", Vector3.INF)
	await _tear_down(first)
	if saved.is_empty():
		return
	_expect(
		not _saved_flag(saved, StoryFlags.Q_COMPANION),
		"companion: the fixture meant to have no companion flag has one."
	)

	Harness.stage = "companion: restoring a save without the flag"
	var again := await _enter_settled()
	if again == null:
		return
	var host := again.get_node_or_null("LocationHost") as LocationHost
	var companion := again.get_node_or_null("Companion") as CompanionController
	if host == null or companion == null or host.get_current() == null:
		_failures.append("companion: the flagless restore has no room or no companion node.")
		await _tear_down(again)
		return
	_expect(
		host.get_current().location_id == &"corridor",
		"companion: the flagless save came back in '%s'." % String(host.get_current().location_id)
	)
	await _physics_frames(30)
	_expect(not companion.is_joined(), "companion: a save without Q's flag produced a joined Q.")
	_expect(not companion.visible, "companion: a save without Q's flag shows the companion.")
	_expect(
		companion.collision_layer == 0,
		"companion: a hidden companion still occupies collision layer %d." % companion.collision_layer
	)
	_expect(
		_visible_qs().is_empty(),
		"companion: Q is on screen in a corridor Q never came to (%s)." % ", ".join(_visible_qs())
	)
	_companion_notes.append("no flag: corridor restored without Q")
	await _tear_down(again)


## The restored session before anything has happened in it: no door has been used and no
## room has changed, so anything true here came from the restore alone.
func _expect_companion_restored(main: Node, location_id: StringName) -> bool:
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var player := main.get_node_or_null("Player") as PlayerController
	var companion := main.get_node_or_null("Companion") as CompanionController
	if host == null or player == null or companion == null or host.get_current() == null:
		_failures.append("companion: the %s restore has no room, player or companion." % location_id)
		return false
	if host.get_current().location_id != location_id:
		_failures.append(
			"companion: expected to come back in '%s', came back in '%s'."
			% [String(location_id), String(host.get_current().location_id)]
		)
		return false
	var where := String(location_id)
	var ok := true
	if not companion.is_joined():
		_failures.append(
			"companion: restored in the %s with Q's flag set, but Q is not joined"
			% where + " (it would wait for the next door). %s" % _q_state(companion, player)
		)
		ok = false
	if not companion.is_with_player():
		_failures.append(
			"companion: restored in the %s, but Q is not with the player. %s"
			% [where, _q_state(companion, player)]
		)
		ok = false
	if companion.collision_layer != companion.body_collision_layer:
		_failures.append(
			"companion: restored Q in the %s has collision layer %d, expected %d."
			% [where, companion.collision_layer, companion.body_collision_layer]
		)
		ok = false
	var qs := _visible_qs()
	if qs.size() != 1:
		_failures.append(
			"companion: restored in the %s with %d visible Q(s) (%s)." % [where, qs.size(), ", ".join(qs)]
		)
		ok = false
	if companion.is_waiting():
		_failures.append("companion: restored Q in the %s starts out waiting." % where)
		ok = false
	var gap := _flat(companion.global_position - player.global_position)
	if gap > companion.follow_distance + 1.0:
		_failures.append(
			"companion: restored Q stands %.1f m from the player in the %s. %s"
			% [gap, where, _q_state(companion, player)]
		)
		ok = false
	return ok


## Walks the player away from Q in six half-metre steps, each onto the room's own
## walkable mesh, and asks Q to keep up on its own: along a route, without being placed.
func _expect_companion_follows(main: Node, where: String) -> void:
	var player := main.get_node_or_null("Player") as PlayerController
	var companion := main.get_node_or_null("Companion") as CompanionController
	if player == null or companion == null:
		return
	if not await _physics_until(
		func() -> bool: return companion.is_navigation_ready(), NAVIGATION_WAIT_FRAMES
	):
		_failures.append(
			"companion: the %s's navigation never answered for the restored Q. %s"
			% [where, _q_state(companion, player)]
		)
		return
	await _physics_frames(5)
	var map := companion.get_world_3d().navigation_map
	var player_start := player.global_position
	var q_start := companion.global_position
	var away := player_start - q_start
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()
	var placements_before := _placement_count(companion)
	var routes_before := companion.get_repath_count()
	for index in range(1, 7):
		var wanted := player_start + away * (0.5 * float(index))
		var onto := NavigationServer3D.map_get_closest_point(map, wanted)
		player.teleport(Transform3D(Basis.IDENTITY, Vector3(onto.x, player_start.y, onto.z)))
		await _physics_frames(15)
	var walked := _flat(player.global_position - player_start)
	var limit := companion.follow_distance + FOLLOW_TOLERANCE
	await _physics_until(
		func() -> bool: return _caught_up(companion, player, limit), CATCH_UP_FRAMES
	)
	var gap := _flat(companion.global_position - player.global_position)
	var moved := _flat(companion.global_position - q_start)
	var routes := companion.get_repath_count() - routes_before
	var placements := _placement_count(companion) - placements_before
	_expect(
		walked >= 2.0,
		"companion: the test could only walk the player %.1f m in the %s." % [walked, where]
	)
	_expect(
		moved >= 1.0,
		"companion: restored Q did not follow in the %s (moved %.2f m). %s"
		% [where, moved, _q_state(companion, player)]
	)
	_expect(
		gap <= companion.follow_distance + FOLLOW_TOLERANCE,
		"companion: restored Q fell %.1f m behind in the %s. %s"
		% [gap, where, _q_state(companion, player)]
	)
	_expect(
		routes > 0,
		"companion: restored Q moved in the %s without asking for a route." % where
	)
	_expect(
		placements == 0,
		"companion: restored Q was placed by hand %d time(s) while following in the %s."
		% [placements, where]
	)
	_expect(not companion.is_waiting(), "companion: restored Q gave up in the %s." % where)
	_companion_notes.append(
		"%s: joined and visible at boot, player walked %.1f m, Q followed %.1f m over %d route(s),"
		% [where, walked, moved, routes] + " gap %.2f m, %d placement(s) while following" % [
			gap, placements
		]
	)


## The classroom has its own Q. The restored companion keeps the story (joined) but is
## not drawn and not solid, so exactly one Q is visible: the room's.
func _expect_companion_hidden_by_authored_q(main: Node) -> void:
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var companion := main.get_node_or_null("Companion") as CompanionController
	if host == null or companion == null or host.get_current() == null:
		_failures.append("companion: the classroom restore has no room or no companion node.")
		return
	_expect(
		host.get_current().location_id == &"classroom",
		"companion: the classroom save came back in '%s'." % String(host.get_current().location_id)
	)
	var authored := host.get_current().find_actor(&"q")
	_expect(authored != null, "companion: the classroom has no authored Q to hand over to.")
	await _physics_frames(30)
	_expect(companion.is_joined(), "companion: the classroom restore forgot that Q came along.")
	_expect(not companion.visible, "companion: the roaming Q is visible in the classroom.")
	_expect(
		companion.collision_layer == 0,
		"companion: the hidden roaming Q still occupies collision layer %d." % companion.collision_layer
	)
	var qs := _visible_qs()
	_expect(
		qs.size() == 1 and authored != null and qs[0] == String(authored.get_path()),
		"companion: expected only the classroom's own Q on screen, found %d (%s)."
		% [qs.size(), ", ".join(qs)]
	)
	_companion_notes.append(
		"classroom: joined %s, roaming Q visible %s, visible Qs %d (%s)"
		% [str(companion.is_joined()), str(companion.visible), qs.size(), ", ".join(qs)]
	)


## Moves the session into `location_id` through `LocationHost` (the companion hears the
## same `location_entered` a door would send), optionally stands the player somewhere,
## and writes a checkpoint. Returns the payload read back from disk, or {}.
func _save_in(
	main: Node, scene: String, spawn: StringName, location_id: StringName, standing: Vector3
) -> Dictionary:
	var sequence := main.get_node_or_null("OpeningSequence") as OpeningSequence
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var player := main.get_node_or_null("Player") as PlayerController
	var companion := main.get_node_or_null("Companion") as CompanionController
	if sequence == null or host == null or player == null or companion == null:
		_failures.append("companion: cannot save in '%s'; main is missing nodes." % location_id)
		return {}
	if not host.load_location(scene, spawn, player, location_id):
		_failures.append("companion: '%s' did not load." % location_id)
		return {}
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, location_id)
	await _settle_room(main)
	await _physics_until(
		func() -> bool: return companion.is_navigation_ready(), NAVIGATION_WAIT_FRAMES
	)
	if standing != Vector3.INF:
		var map := player.get_world_3d().navigation_map
		var onto := NavigationServer3D.map_get_closest_point(map, standing)
		player.teleport(Transform3D(Basis.IDENTITY, Vector3(onto.x, standing.y, onto.z)))
	await _physics_frames(3)
	var written: Dictionary = sequence.autosave("companion_%s" % location_id)
	if written.get("ok", false) != true:
		_failures.append("companion: the save in '%s' was not written: %s" % [location_id, str(written)])
		return {}
	var read: Dictionary = _save.read_save()
	if read.get("ok", false) != true:
		_failures.append("companion: the save in '%s' does not read back." % location_id)
		return {}
	var payload: Dictionary = read["payload"]
	var world: Dictionary = payload.get("world", {})
	if String(world.get("location_id", "")) != String(location_id):
		_failures.append(
			"companion: the save meant for '%s' names '%s'."
			% [location_id, String(world.get("location_id", ""))]
		)
		return {}
	return payload


## Waits for the checkpoint the real arrival writes, and returns its payload.
func _wait_for_checkpoint(location_id: StringName, timeout_seconds: float) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		await _frames(5)
		if not _save.has_save():
			continue
		var read: Dictionary = _save.read_save()
		if read.get("ok", false) != true:
			continue
		var payload: Dictionary = read["payload"]
		var world: Dictionary = payload.get("world", {})
		if String(world.get("location_id", "")) == String(location_id):
			return payload
	_failures.append(
		"companion: no checkpoint in '%s' was written within %.0f s." % [location_id, timeout_seconds]
	)
	return {}


func _saved_flag(payload: Dictionary, flag: StringName) -> bool:
	var decoded := SaveCodec.decode_flags(payload.get("flags", {}))
	if decoded["ok"] != true:
		_failures.append("companion: the saved flags do not decode: %s" % String(decoded["detail"]))
		return false
	var flags: Dictionary = decoded["flags"]
	var value: Variant = flags.get(flag, false)
	return value is bool and value


## Every Q actor currently drawn, by path. Exactly one is the rule everywhere.
func _visible_qs() -> Array[String]:
	var found: Array[String] = []
	for node: Node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor == null or actor.npc_id != &"q" or actor.is_queued_for_deletion():
			continue
		if actor.is_visible_in_tree():
			found.append(String(actor.get_path()))
	return found


## Close enough to stand, and standing: the follow has finished rather than paused.
func _caught_up(companion: CompanionController, player: Node3D, limit: float) -> bool:
	if _flat(companion.velocity) > 0.1:
		return false
	return _flat(companion.global_position - player.global_position) <= limit


func _placement_count(companion: CompanionController) -> int:
	return int(companion.get_placement_report().get_slice(":", 0))


func _q_state(companion: CompanionController, player: Node3D) -> String:
	return "[q=%s player=%s joined=%s visible=%s waiting=%s nav=%s route=%d repath=%d note='%s' place='%s']" % [
		str(companion.global_position), str(player.global_position), str(companion.is_joined()),
		str(companion.visible), str(companion.is_waiting()), str(companion.is_navigation_ready()),
		companion.get_route().size(), companion.get_repath_count(),
		companion.get_last_chase_note(), companion.get_placement_report(),
	]


func _reset_session() -> void:
	_game_state.clear()
	_narrative.clear()
	_save.forget_all()


## Frees a session the way quitting would, and wipes the in-memory state so only the
## file can bring anything back.
func _tear_down(main: Node) -> void:
	main.queue_free()
	await _frames(3)
	# Quitting ends the process; here the next session shares the world and its
	# navigation map, so the freed room gets a few physics frames to leave it first.
	await _physics_frames(10)
	_game_state.clear()
	_narrative.clear()


## `_enter_main()`, then the frames a player spends looking at the room before doing
## anything: the room's navigation answers for its own mesh.
func _enter_settled() -> Node:
	var main := await _enter_main()
	if main != null:
		await _settle_room(main)
	return main


## Waits until the current room's navigation answers from its own mesh, the way a player
## arrives and looks around before doing anything. Q's follow checks need that mesh, and a
## room saved or left a few frames after it loaded is not a situation a player can make.
func _settle_room(main: Node) -> void:
	var host := main.get_node_or_null("LocationHost") as LocationHost
	if host == null or host.get_current() == null:
		return
	var navigation := host.get_current().get_node_or_null("Navigation") as LocationNavigation
	if navigation == null:
		return
	var synchronized: bool = await navigation.wait_until_synchronized(NAVIGATION_WAIT_FRAMES)
	if not synchronized:
		_failures.append(
			"companion: the %s's navigation never synchronised: %s"
			% [String(host.get_current().location_id), navigation.describe_sync()]
		)


func _physics_until(predicate: Callable, max_frames: int) -> bool:
	for _index in max_frames:
		if bool(predicate.call()):
			return true
		await physics_frame
	return bool(predicate.call())


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


# --- A file nobody can read -------------------------------------------------


func _check_refusal_at_boot() -> void:
	Harness.stage = "a broken save at boot"
	_game_state.clear()
	_narrative.clear()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write a broken save fixture.")
		return
	file.store_string("{\"format\": \"where-is-school/save\", \"version\": 1, \"payload\": ")
	file.close()

	var main := await _enter_main()
	if main == null:
		return
	var sequence := main.get_node_or_null("OpeningSequence")
	var result: Dictionary = _save.get_last_result()
	_expect(result.get("ok", true) != true, "A truncated save was loaded without complaint.")
	_expect(
		not String(result.get("detail", "")).is_empty(),
		"The refusal does not say anything actionable."
	)
	_expect(
		FileAccess.file_exists(BROKEN_PATH),
		"The unreadable save was not copied aside before the new run started."
	)
	_expect(
		_game_state.get_flag(StoryFlags.MET_Q, false) == false,
		"A broken save left half a session behind."
	)
	_expect(
		sequence != null and not String(sequence.next_step()).is_empty(),
		"After a refused save the director should start the prologue from its first step."
	)

	# The player is told, on the card this build already has.
	await _frames(2)
	var ui := main.get_node_or_null("GameUI")
	var card: EndCard = ui.get_node("EndCard") if ui != null and ui.has_node("EndCard") else null
	if card != null:
		_expect(card.visible, "The save problem was not shown on screen.")
		_expect(
			not card.get_title().is_empty(),
			"The card reporting the save problem has no title."
		)
	else:
		_failures.append("main.tscn has no EndCard to report a save problem on.")

	main.queue_free()
	await _frames(3)


# --- Helpers ----------------------------------------------------------------


func _enter_main() -> Node:
	Harness.stage = "loading main.tscn"
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return null
	var main := packed.instantiate()
	var sequence := main.get_node_or_null("OpeningSequence")
	if sequence != null:
		# The beats are not what this test is about: the save system must work with the
		# director holding still.
		sequence.set("autostart", false)
	root.add_child(main)
	await _frames(3)
	return main


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
