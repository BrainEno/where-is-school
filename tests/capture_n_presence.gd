extends SceneTree
## #166 evidence: the classroom from the game camera before substitute teacher N comes in,
## once she has, and after the player has left the room and come back.
##
## Needs a real display and renderer (the playthrough workflow runs it under Xvfb); a
## headless run is refused, because a frame from the dummy renderer proves nothing. The
## frames go to `N_PRESENCE_EVIDENCE_DIR` (default `user://n_presence`), and a small JPEG of
## each is printed as a `CROP: <name> <base64>` line for the run's annotations.
##
## The story is driven as `tests/n_presence_test.gd` drives it - the real main scene, the
## bell already rung, lines continued and doors used through the same calls the UI makes -
## and each frame is taken from the same spot in the room, looking at the lectern.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const TIME_SCALE := 4.0
## Where the player stands for every frame: the aisle in front of the stage, facing it.
const VIEW_FROM := Vector3(0.0, 0.0, 0.25)
const CROP_SIZE := Vector2i(320, 180)

var _failures: Array[String] = []
var _out := "user://n_presence"
var _state: Node = null
var _world: Node = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_n_presence.gd")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		Harness.finish(self, ["A real display/renderer is required; headless is not evidence."], "")
		return
	var from_env := OS.get_environment("N_PRESENCE_EVIDENCE_DIR")
	if not from_env.is_empty():
		_out = from_env
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if error != OK:
		Harness.finish(self, ["Cannot create the evidence folder: %s" % error_string(error)], "")
		return
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	Harness.clear_session_state(self)
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")
	for flag: StringName in [
		StoryFlags.MET_Q, StoryFlags.Q_FIRST_TALK_DONE, StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG,
	]:
		_state.set_flag(flag, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.bell")

	_world = (load(MAIN) as PackedScene).instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_world)
	await _frames(3)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	var voices := _world.get_node_or_null(^"InnerVoiceDirector")
	if voices != null:
		voices.set_process(false)
	_sequence.allow_player_control()
	_sequence.sync_player_locks()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()

	# 1. Before: the bell has rung, the substitute has not come in.
	await _view_the_lectern()
	_report("before", false)
	await _shot("n166_1_before.png")

	# 2. She has come in, taken the register and let the class go.
	Engine.time_scale = TIME_SCALE
	_sequence.start()
	await _pump_until(
		func() -> bool: return bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false)) \
			and not _dialogue.is_busy() and _player.is_control_enabled(),
		120.0, "N to come in and dismiss the class"
	)
	Engine.time_scale = 1.0
	await _view_the_lectern()
	_report("arrived", true)
	await _shot("n166_2_arrived.png")

	# 3. Out to the walkway and back in: a new instance of the classroom.
	Engine.time_scale = TIME_SCALE
	await _use_exit(&"classroom_door", &"corridor")
	await _use_exit(&"back_to_classroom", &"classroom")
	Engine.time_scale = 1.0
	await _view_the_lectern()
	_report("re-entered", true)
	await _shot("n166_3_reentered.png")

	_world.queue_free()
	await _frames(3)
	Harness.clear_session_state(self)
	Harness.finish(self, _failures, "N's frames: before, arrived, re-entered (%s)." % _out)


func _view_the_lectern() -> void:
	_player.teleport(Transform3D(Basis(Vector3.UP, 0.0001), VIEW_FROM))
	await _frames(40)


## Prints where N is and whether she is shown, and holds the frame to what it must show.
func _report(moment: String, expect_shown: bool) -> void:
	var room := _host.get_current()
	var n := room.find_actor(&"n") if room != null else null
	if n == null:
		_failures.append("%s: the classroom has no N." % moment)
		return
	var points := room.get_waypoint_path(&"NEntryPath")
	var stand: Vector3 = points[points.size() - 1] if not points.is_empty() else Vector3.INF
	var distance := n.global_position.distance_to(stand)
	print("N_PRESENCE %s: room %s, N visible %s at %s, %.3f m from the lectern's stand, %d N(s)" % [
		moment, str(room.get_instance_id()), str(n.is_visible_in_tree()), str(n.global_position),
		distance, _count_n()
	])
	if n.is_visible_in_tree() != expect_shown:
		_failures.append("%s: N is %s." % [moment, "hidden" if expect_shown else "already shown"])
	if expect_shown and distance > 0.05:
		_failures.append("%s: N is %.2f m from the lectern's stand." % [moment, distance])


func _count_n() -> int:
	var count := 0
	for node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == &"n" and not actor.is_queued_for_deletion():
			count += 1
	return count


func _use_exit(exit_id: StringName, destination: StringName) -> void:
	var room := _host.get_current()
	var exit := room.find_interactable(exit_id) if room != null else null
	if exit == null:
		_failures.append("No '%s' to take." % exit_id)
		return
	_interaction.request_activation(exit)
	await _pump_until(
		func() -> bool:
			var current := _host.get_current()
			return current != null and current.location_id == destination \
				and not _dialogue.is_busy() and _player.is_control_enabled(),
		60.0, "'%s' to reach the %s" % [exit_id, destination]
	)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s: no frame was rendered." % file_name)
		return
	var path := ProjectSettings.globalize_path(_out.path_join(file_name))
	var error := image.save_png(path)
	if error != OK:
		_failures.append("%s could not be written: %s" % [file_name, error_string(error)])
		return
	var small := image.duplicate() as Image
	small.resize(CROP_SIZE.x, CROP_SIZE.y, Image.INTERPOLATE_LANCZOS)
	print("CROP: %s %s" % [
		file_name.get_basename() + ".jpg", Marshalls.raw_to_base64(small.save_jpg_to_buffer(0.6))
	])


func _pump_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while not bool(predicate.call()):
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			_failures.append("Timed out waiting for %s." % label)
			return false
	return true


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame
