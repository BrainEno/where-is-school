extends SceneTree
## Photographs the biology classroom art experiment
## (`scenes/dev/visual_experiments/biology_classroom/`) and measures what it costs. Not an
## assertion suite:
##
##   xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_biology_classroom.gd -- label=compatibility perf=1
##
## Every frame is set up through the scene's own public calls (the same ones its keys and
## the test use): start over, jump to a beat, stand somewhere, open the door, draw the
## curtain, lean out. Where a frame needs Q somewhere it would take him a while to walk
## to, he is put there with `set_place_instant`, and the frame's note says so. The HUD is
## hidden; the dialogue strip is not (it is part of what is proposed).
##
## Output: res://docs/screenshots/visual_experiments/biology_classroom/<label>/NN_<name>.jpg
## and FRAMES.md. `docs/` is not imported by the engine.

const Harness = preload("res://tests/test_harness.gd")

const SCENE := "res://scenes/dev/visual_experiments/biology_classroom/biology_classroom.tscn"
const OUT_ROOT := "res://docs/screenshots/visual_experiments/biology_classroom"
const CAMERA := "Observer/CameraRig/Camera3D"

## Each frame: `feet` and `face` (omitted = left seated at the desk), optional `framing`
## (yaw, pitch, distance) or free camera `eye`/`look`; then what to do before the shot:
## `beat` (1-4), `door`, `q` (a Place, put there instantly), `curtain` ("instant" or
## "animate"), `fall`, `note_line` (show the beat's stage note); `settle` seconds.
const FRAMES := [
	{
		"name": "overview", "beat": 1, "feet": Vector3(-1.6, 0.0, 2.25),
		"face": Vector3(-1.6, 0.0, 0.0),
		"eye": Vector3(13.5, 15.0, 13.0), "look": Vector3(-3.0, -1.2, -0.6), "fov": 52.0,
		"note": "The whole set from above the missing corner: the classroom with its south and east walls stopped at the dado and drawn in pen above, the platform and the tall lectern at the window end, the open corridor (right) and the yard one floor down (left).",
	},
	{
		"name": "waking", "beat": 1, "fov": 55.0, "settle": 1.0,
		"note": "Beat 1. Seated at his desk, slumped; the room beyond the next desk is lost in the dark (the focus register). Q sits across the aisle.",
	},
	{
		"name": "lectern_set", "beat": 3, "feet": Vector3(-1.2, 0.0, -0.9),
		"face": Vector3(-4.7, 0.0, -2.55),
		"eye": Vector3(-1.4, 2.0, 0.2), "look": Vector3(-4.9, 1.0, -2.9), "fov": 55.0,
		"note": "The high lectern where the low desk stood: on the platform, at the window end, the set square (taped across its crack), the register and red pencil, the chalk box, the pointer leaning on it; the board, the wing chart and the clock behind.",
	},
	{
		"name": "lesson_b", "beat": 2, "feet": Vector3(-3.4, 0.0, -1.2),
		"face": Vector3(-4.7, 0.0, -2.55), "note_line": true, "settle": 1.0,
		"note": "Beat 2, near the lectern. B is not there; the impression of B is: the room turns ink blue, a shadow nobody casts climbs the front wall, the lectern stands taller than it is, the set square's shadow crosses the floor toward his desk, and its wedge cuts into the dialogue strip.",
	},
	{
		"name": "curtain_closed", "beat": 3, "feet": Vector3(-5.2, 0.0, 2.2),
		"face": Vector3(-7.0, 0.0, 2.2),
		"note": "Beat 3, at the curtain: deep blue pleats over the west opening, Q's desk beside it.",
	},
	{
		"name": "curtain_tearing", "beat": 3, "feet": Vector3(-5.9, 0.0, 2.2),
		"face": Vector3(-7.0, 0.0, 2.2), "curtain": "animate", "settle": 0.3,
		"note": "Drawing it: behind the curtain is a blank sheet, and the picture starts turning into a pencil drawing on an answer sheet, torn open from the window outward.",
	},
	{
		"name": "curtain_paper", "beat": 3, "feet": Vector3(-5.9, 0.0, 2.2),
		"face": Vector3(-7.0, 0.0, 2.2), "curtain": "instant", "settle": 1.2,
		"note": "On paper: blue rules, red margin, graphite; only red survives - the ring drawn round where he stands, the zero. Q (walking over to the window) is drawn too.",
	},
	{
		"name": "yard_landing", "beat": 3, "feet": Vector3(-5.9, 0.0, 2.2),
		"face": Vector3(-7.0, 0.0, 2.2), "curtain": "instant", "fall": true, "settle": 0.4,
		"note": "Leaning out: the blank gives way, the paper lifts, and he lands in colour in the yard below, getting up. The opening is a white rectangle in the face of the building; Q is still upstairs.",
	},
	{
		"name": "corridor_q", "beat": 3, "feet": Vector3(8.6, 0.0, -1.4),
		"face": Vector3(8.6, 0.0, 3.0), "door": true, "q": 2, "settle": 1.0,
		"note": "Out of the front door into the open corridor. Q has come to the doorway (put there for the frame; in play he walks) and stays on the classroom side; he does not follow.",
	},
	{
		"name": "bell_n", "beat": 4, "feet": Vector3(2.4, 0.0, 0.6),
		"face": Vector3(0.6, 0.0, -3.2), "q": 3, "settle": 1.6,
		"note": "Beat 4. The bell: the fluorescent tubes come on and drain the colour, the clock reads 11:00, and N stands on the platform beside the lectern, not at it. Q is back in his seat.",
	},
]

var _scene: Node3D = null
var _label := "capture"
var _width := 0
var _quality := 0.86
var _perf := false
var _only: Array[String] = []
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 900.0, "capture_biology_classroom.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("label="):
			_label = arg.substr(6).strip_edges()
		elif arg.begins_with("width="):
			_width = maxi(0, int(arg.substr(6)))
		elif arg.begins_with("quality="):
			_quality = clampf(float(arg.substr(8)), 0.3, 1.0)
		elif arg.begins_with("perf="):
			_perf = arg.substr(5).strip_edges() == "1"
		elif arg.begins_with("only="):
			for frame_name: String in arg.substr(5).strip_edges().split(",", false):
				_only.append(frame_name.strip_edges())
	call_deferred("_run")


func _run() -> void:
	var out_dir := "%s/%s" % [OUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_finish(["The biology classroom experiment could not be loaded."])
		return
	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	_scene.call("set_hud_visible", false)
	await _wait(0.8)
	var renderer := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var adapter := RenderingServer.get_video_adapter_name()
	print("BIOLOGY_CLASSROOM_CAPTURE renderer=%s driver=%s adapter=%s" % [renderer, driver, adapter])
	_lines.append("# Biology classroom experiment frames: %s" % _label)
	_lines.append("")
	_lines.append(
		"Captured by `tests/capture_biology_classroom.gd` under Xvfb at %s, renderer `%s` (%s, %s)."
		% [str(root.size), renderer, driver, adapter]
	)
	_lines.append("")
	for index in FRAMES.size():
		var frame: Dictionary = FRAMES[index]
		if not _only.is_empty() and not _only.has(String(frame["name"])):
			continue
		var shot_name := "%02d_%s" % [index, String(frame["name"])]
		await _shoot(frame, out_dir, shot_name)
		_lines.append("- `%s.jpg` - %s" % [shot_name, String(frame["note"])])
	var file := FileAccess.open("%s/FRAMES.md" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	_finish(_failures)


func _shoot(frame: Dictionary, out_dir: String, shot_name: String) -> void:
	var camera := _scene.get_node(CAMERA) as Camera3D
	var q := _scene.get_node("QPresence")
	_scene.call("reset_experiment")
	await _physics(2)
	_scene.call("set_beat", int(frame.get("beat", 1)), true)
	if frame.has("feet"):
		_scene.call("observe", frame["feet"], frame["face"], frame.get("framing", Vector3.ZERO))
	if bool(frame.get("door", false)):
		_scene.call("open_door", true)
	if frame.has("q"):
		q.call("set_place_instant", int(frame["q"]))
	_scene.call("snap_registers")
	await _physics(4)
	var curtain := String(frame.get("curtain", ""))
	if curtain == "instant":
		_scene.call("open_curtain", true)
	elif curtain == "animate":
		_scene.call("open_curtain", false)
	if bool(frame.get("fall", false)):
		await _wait(0.4)
		_scene.call("_fall")
		await _wait(3.4)
	if bool(frame.get("note_line", false)):
		_scene.call("show_note_for_beat")
	camera.fov = float(frame.get("fov", 55.0))
	if frame.has("eye"):
		_scene.call("look_from", frame["eye"], frame["look"])
	await _physics(4)
	await _wait(float(frame.get("settle", 0.6)))
	_save(out_dir, shot_name)
	var paper := _scene.get_node("PaperSwitch")
	_lines.append(
		"  - character at %s, camera at %s (%s), fov %.0f, zone `%s`, beat %d, paper %s"
		% [
			str((_scene.get_node("Observer") as Node3D).global_position.snapped(Vector3.ONE * 0.01)),
			str(camera.global_position.snapped(Vector3.ONE * 0.01)),
			"free camera" if frame.has("eye") else "follow camera", camera.fov,
			String(_scene.call("current_zone")), int(_scene.get("beat")),
			"on" if bool(paper.call("is_on")) else "off",
		]
	)
	if _perf:
		var sample: Dictionary = await _scene.call("sample_performance", 20)
		print("BIOLOGY_CLASSROOM_PERF %s %s" % [shot_name, JSON.stringify(sample)])
	camera.fov = 55.0


func _save(out_dir: String, shot_name: String) -> void:
	RenderingServer.force_draw(true)
	var image: Image = root.get_texture().get_image()
	if image == null:
		_failures.append("no image for %s" % shot_name)
		return
	if _width > 0 and image.get_width() > _width:
		var height := int(round(float(image.get_height()) * _width / image.get_width()))
		image.resize(_width, height, Image.INTERPOLATE_LANCZOS)
	var err := image.save_jpg("%s/%s.jpg" % [out_dir, shot_name], _quality)
	if err != OK:
		_failures.append("%s could not be saved (error %d)" % [shot_name, err])
		return
	print("BIOLOGY_CLASSROOM_FRAME %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _physics(count: int) -> void:
	for _index in count:
		await physics_frame
	await process_frame


func _finish(failures: Array) -> void:
	Harness.finish(self, failures, "biology classroom frames written for %s" % _label)
