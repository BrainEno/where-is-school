extends SceneTree
## Photographs the biology-classroom anomalies from the game's own camera, so the round
## can be judged on frames: the two windows (one ordinary, one curtained), the rear door
## with the staircase it put in the room, the window once the curtain is drawn, and the
## body going over the sill.
##
## `classroom_anomaly_test.gd` proves the behaviour headless; this script only takes the
## pictures. It needs a display (Xvfb in CI):
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" \
##     godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_classroom_anomalies.gd
##
## Frames land in `docs/screenshots/classroom_anomalies/` as PNGs (the artifact) and are
## printed as small JPEGs (`CROP: <file> <base64>`) for the workflow's annotations.

const Harness = preload("res://tests/test_harness.gd")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const OUT_DIR := "res://docs/screenshots/classroom_anomalies"
const LOG_PATH := "res://docs/screenshots/classroom_anomalies/CAPTURE.log"
const INLINE_SIZE := Vector2i(480, 270)
const EXPECTED_SHOTS := 5

var _failures: Array[String] = []
var _shots: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_classroom_anomalies.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	var game_state: Node = autoloads["game_state"]
	Harness.clear_session_state(self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_finish(["main.tscn could not be loaded."])
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(3)
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	if _host == null or _player == null or _dialogue == null or game_state == null:
		_finish(["Main did not expose the nodes this capture needs."])
		return
	if _host.get_current_path() != CLASSROOM or _host.get_current() == null:
		if not _host.load_location(CLASSROOM, &"PlayerStart", _player):
			_finish(["The classroom could not be entered."])
			return
	game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	await _quiet(20.0)
	var room := _host.get_current()
	var anomalies := room.get_node_or_null(^"Anomalies")
	var stair := room.get_node_or_null(^"Anomalies/Staircase") as SuspendedStair
	if anomalies == null or stair == null:
		_finish(["The classroom has no Anomalies/Staircase."])
		return

	# 1. Both windows: the front one ordinary (the washing), the back one curtained.
	await _stand(Vector3(-2.7, 0.0, 0.2), Vector3.LEFT)
	await _shot("01-windows.png")

	# 2. The rear door open, from inside the room by the back wall.
	await anomalies.call("open_rear_door", false)
	stair.reveal(false)
	await _stand(Vector3(-2.6, 0.0, 2.3), Vector3.BACK)
	await _shot("02-rear-door.png")

	# 3. The staircase over the teacher's desk, with the framing the beat uses.
	await _stand(Vector3(0.0, 0.0, 0.85), Vector3.FORWARD)
	var rig := _player.camera_rig
	if rig != null:
		await rig.frame_point(Vector3.ZERO, 0.3)
		await _frames(20)
	await _shot("03-staircase.png")
	if rig != null:
		await rig.release_frame(0.2)

	# 4. The back window once the curtain is drawn: no glass, no view.
	await anomalies.call("draw_curtain", false)
	await _stand(Vector3(-2.9, 0.0, 1.0), Vector3.LEFT)
	await _shot("04-void.png")

	# 5. Going over the sill (the beat's own departure, photographed part-way).
	await _stand(Vector3(-3.6, 0.0, 1.3), Vector3.LEFT)
	anomalies.call("_fall", _player)
	await create_timer(1.1).timeout
	await _shot("05-fall.png")

	_finish(_failures)


func _stand(where: Vector3, facing: Vector3) -> void:
	_player.teleport(Transform3D(Basis(), where))
	_player.face_toward(facing)
	# Long enough for the occlusion fader and the staircase's see-through to settle.
	await _frames(45)


func _quiet(timeout_seconds: float) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if not _dialogue.is_busy():
			return
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("The %s frame came back empty." % name)
		return
	var path := "%s/%s" % [OUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [path, error])
		return
	_shots.append(name)
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(INLINE_SIZE.x, INLINE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var encoded := Marshalls.raw_to_base64(small.save_jpg_to_buffer(0.62))
	print("CROP: %s %s" % [name.get_basename() + ".jpg", encoded])
	print("SHOT %s %dx%d" % [name, image.get_width(), image.get_height()])


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _finish(failures: Array) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		for name in _shots:
			file.store_line("SHOT: %s" % name)
		for failure in failures:
			file.store_line("FAILURE: %s" % failure)
		if failures.is_empty():
			file.store_line("RESULT: %d anomaly frames captured." % _shots.size())
		file.close()
	if failures.is_empty() and _shots.size() == EXPECTED_SHOTS:
		print("PASS: captured %d anomaly frames." % _shots.size())
		quit(0)
		return
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
