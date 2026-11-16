extends SceneTree
## Photographs the prologue's biology classroom from the game's own camera, so the art
## migration of the approved biology-classroom experiment can be judged on real frames:
## the room and its light, Q and the protagonist in it, the curtained back window, the
## camera's focus on an important interaction, and the ceiling-to-floor void with the
## local paper anomaly around it - from near, from across the room and from a third
## standing spot, to show that the paper stays where it is while the player moves.
##
## It runs the real main scene (`main.tscn`): the player, the camera rig, the occluder
## fader, the interaction controller and the location host are all the game's own. Only
## the HUD is hidden (it carries the boot fade, black until the opening lifts it), and the
## frame `void_inside` uses a camera of its own at eye height, because the game camera
## never stands inside the room.
##
## It needs a display (Xvfb in CI):
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" \
##     godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_prologue_art.gd -- only=start,window_wall
##
## Frames land in `docs/screenshots/prologue_art/` as PNGs (the artifact) and are printed
## as JPEGs (`CROP: <file> <base64>`) for the workflow's annotations.

const Harness = preload("res://tests/test_harness.gd")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const OUT_DIR := "res://docs/screenshots/prologue_art"
const INLINE_SIZE := Vector2i(640, 360)
## Frames in story order: `void_*` frames need the curtain drawn, so they come last.
const FRAMES: Array[String] = [
	"start", "window_wall", "front", "q", "q_close", "focus_window", "focus_curtain",
	"void_near", "void_far", "void_walk", "void_inside",
]
const CURTAIN_SPOT := Vector3(-5.9, 0.0, 2.2)

var _failures: Array[String] = []
var _shots: Array[String] = []
var _only: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _room: Node3D = null
var _curtain_drawn := false
## A frame's own camera and the one to give the view back to, once the frame is taken.
var _pending_restore: Array = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "capture_prologue_art.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			for frame_name: String in arg.substr(5).strip_edges().split(",", false):
				_only.append(frame_name.strip_edges())
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
	var ui := _main.get_node_or_null("GameUI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	if _host.get_current_path() != CLASSROOM or _host.get_current() == null:
		if not _host.load_location(CLASSROOM, &"PlayerStart", _player):
			_finish(["The classroom could not be entered."])
			return
	game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	if sequence_node != null and sequence_node.has_method("allow_player_control"):
		sequence_node.call("allow_player_control")
	await _quiet(20.0)
	_room = _host.get_current()
	print(
		"PROLOGUE_ART_CAPTURE renderer=%s driver=%s size=%s"
		% [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name(),
			str(root.size),
		]
	)
	for frame_name: String in FRAMES:
		if not _only.is_empty() and not _only.has(frame_name):
			continue
		await Callable(self, "_frame_" + frame_name).call()
		await _shot("%02d_%s.png" % [FRAMES.find(frame_name), frame_name])
	_finish(_failures)


# --- The frames -----------------------------------------------------------------------


## Where the prologue starts: the protagonist's desk, the room around it.
func _frame_start() -> void:
	await _stand(Vector3(-1.6, 0.0, 1.95), Vector3.FORWARD)


## The window wall: the ordinary front window and the curtained back opening.
func _frame_window_wall() -> void:
	await _stand(Vector3(-4.6, 0.0, 0.6), Vector3.LEFT)


## The teacher's corner: the platform, the lectern, the board.
func _frame_front() -> void:
	await _stand(Vector3(-2.2, 0.0, -1.3), Vector3.FORWARD)


## Q at his desk, from where the protagonist would speak to him.
func _frame_q() -> void:
	await _stand(Vector3(-2.4, 0.0, 2.3), Vector3(-0.8, 0.0, 0.6))


## Q close up, at eye height (a camera of its own): the model, its materials, its light.
func _frame_q_close() -> void:
	await _stand(Vector3(-1.4, 0.0, 1.95), Vector3.LEFT)
	var q := _room.get_node_or_null(^"Actors/Q") as Node3D
	var centre := q.global_position if q != null else Vector3(-3.3, 0.0, 3.1)
	await _with_camera(centre + Vector3(1.55, 1.45, 0.9), centre + Vector3(0.0, 1.05, 0.0), 45.0)


## Standing at the ordinary front window: an important interaction, so the camera
## settles into its focus framing.
func _frame_focus_window() -> void:
	await _stand(Vector3(-5.4, 0.0, -0.4), Vector3.LEFT)
	await create_timer(1.6).timeout


## Standing at the curtain: the most important interaction in the room.
func _frame_focus_curtain() -> void:
	await _stand(CURTAIN_SPOT, Vector3.LEFT)
	await create_timer(1.6).timeout


## The curtain drawn: the cut through the wall, the paper anomaly round it.
func _frame_void_near() -> void:
	await _draw_curtain()
	await _stand(Vector3(-5.2, 0.0, 0.7), Vector3.LEFT)


## From the middle of the room: the paper stays at the window; the rest of the room keeps
## its materials.
func _frame_void_far() -> void:
	await _draw_curtain()
	await _stand(Vector3(-0.6, 0.0, 1.9), Vector3.LEFT)


## From the back row, another angle on the same patch: no seam, no swimming.
func _frame_void_walk() -> void:
	await _draw_curtain()
	await _stand(Vector3(-3.2, 0.0, 4.2), Vector3.LEFT)


## At eye height inside the room: the void runs from the floor to the top of the wall.
func _frame_void_inside() -> void:
	await _draw_curtain()
	await _stand(Vector3(-1.6, 0.0, 1.95), Vector3.LEFT)
	await _with_camera(Vector3(-1.9, 1.55, 3.6), Vector3(-6.9, 1.35, 2.0), 60.0)


# --- Helpers --------------------------------------------------------------------------


func _draw_curtain() -> void:
	if _curtain_drawn:
		return
	_curtain_drawn = true
	var anomalies := _room.get_node_or_null(^"Anomalies")
	if anomalies == null:
		_failures.append("The classroom has no Anomalies node.")
		return
	await anomalies.call("draw_curtain", true)
	# Long enough for any reveal that follows the cloth to finish.
	await create_timer(3.0).timeout


func _stand(where: Vector3, facing: Vector3) -> void:
	_player.teleport(Transform3D(Basis(), where))
	_player.face_toward(facing)
	# Long enough for the occlusion fader, the projector's see-through and any camera
	# glide to settle.
	await _frames(45)
	await create_timer(0.6).timeout


## Takes the frame from a camera of its own (the scene's camera is restored afterwards).
func _with_camera(eye: Vector3, look: Vector3, fov: float) -> void:
	var player_camera := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = fov
	camera.far = 80.0
	_room.add_child(camera)
	camera.global_position = eye
	camera.look_at(look, Vector3.UP)
	camera.current = true
	await _frames(12)
	await RenderingServer.frame_post_draw
	_pending_restore = [camera, player_camera]


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


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_restore_camera()
	if image == null or image.is_empty():
		_failures.append("The %s frame came back empty." % file_name)
		return
	var path := "%s/%s" % [OUT_DIR, file_name]
	var error := image.save_png(path)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [path, error])
		return
	_shots.append(file_name)
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(INLINE_SIZE.x, INLINE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	var samples := 0
	for y in range(0, small.get_height(), 9):
		for x in range(0, small.get_width(), 9):
			total += small.get_pixel(x, y).get_luminance()
			samples += 1
	var mean := total / maxf(1.0, float(samples))
	if mean < 0.04:
		_failures.append("The %s frame is black (mean luminance %.3f)." % [file_name, mean])
	var encoded := Marshalls.raw_to_base64(small.save_jpg_to_buffer(0.6))
	print("CROP: %s %s" % [file_name.get_basename() + ".jpg", encoded])
	print("SHOT %s %dx%d mean=%.3f" % [file_name, image.get_width(), image.get_height(), mean])


func _restore_camera() -> void:
	if _pending_restore.is_empty():
		return
	var camera := _pending_restore[0] as Camera3D
	var previous := _pending_restore[1] as Camera3D
	_pending_restore = []
	if camera != null:
		camera.current = false
		camera.queue_free()
	if previous != null:
		previous.current = true


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _finish(failures: Array) -> void:
	var expected := FRAMES.size() if _only.is_empty() else _only.size()
	if failures.is_empty() and _shots.size() == expected:
		print("PASS: captured %d prologue frames." % _shots.size())
		quit(0)
		return
	if _shots.size() != expected:
		print("FAILURE: captured %d of %d frames." % [_shots.size(), expected])
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
