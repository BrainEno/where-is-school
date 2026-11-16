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
const CAMERA := "ShotCamera"

## Each frame: `feet` and `face` (omitted = left seated at the desk); then what to do before
## the shot: `beat` (1-4), `door`, `q` (a Place, put there instantly), `curtain` ("instant"
## or "animate"), `fall`, `note_line` (show the beat's stage note), `keys` (movement keys
## held for so many seconds, as a player would); `settle` seconds. A frame with `eye`/`look`
## is an authored detail shot (`look_from`, the kind a story beat would ask for); every
## other frame is the fixed shot the room itself gives for where he stands. The lens is the
## camera's own (60 degrees) in every frame.
const FRAMES := [
	{
		"name": "overview", "beat": 2, "feet": Vector3(1.0, 0.0, 0.9),
		"face": Vector3(-0.4, 0.0, -4.0), "settle": 1.0,
		"note": "Beat 2, the classroom's own fixed shot (from the rear door corner): four closed walls and a ceiling, the cast-concrete floor, the projector hanging over the front with its picture on the board, the high concrete lectern at the window end, the cut-paper class at their desks, the curtain (right of the lectern, west wall) the only opening.",
	},
	{
		"name": "projector", "beat": 2, "feet": Vector3(0.2, 0.0, -1.7),
		"face": Vector3(-0.4, 0.0, -5.0),
		"eye": Vector3(3.4, 1.75, 1.6), "look": Vector3(-1.4, 1.75, -3.6), "settle": 1.0,
		"note": "Detail (authored): the projector on its ceiling rod in front of the board, tipped down at the front wall; its beam, the screen half pulled down and the picture spilling past it onto the blackboard; the cable down the front wall to the switch on the lectern.",
	},
	{
		"name": "floor_lectern", "beat": 3, "feet": Vector3(1.0, 0.0, 0.9),
		"face": Vector3(1.0, 0.0, -2.0),
		"eye": Vector3(-1.5, 1.55, -0.2), "look": Vector3(-4.6, 0.55, -2.5), "settle": 0.8,
		"note": "Detail (authored): the poured floor - aggregate, pores, warm and cool drift, the joints, the ruled lines and red margin cast into it - and the board-formed concrete lectern on the platform, set square, register, red pencil, chalk, pointer and projector switch on it.",
	},
	{
		"name": "classmates", "beat": 1, "feet": Vector3(0.6, 0.0, 1.0),
		"face": Vector3(0.6, 0.0, -2.0),
		"eye": Vector3(3.25, 1.45, -2.3), "look": Vector3(3.1, 0.8, 1.8), "settle": 0.8,
		"note": "Detail (authored): the class from the front, cut paper in layers - dyed, kraft, newsprint, graph, magazine and sugar paper, torn and cut edges, the white core showing, folded at the shoulder; one asleep, one turned round, one with a hand up, one standing at the back board pinning a sheet.",
	},
	{
		"name": "waking", "beat": 1, "settle": 1.0,
		"note": "Beat 1. Seated at his desk, slumped: the seated shot. The room beyond the next desk is lost in the dark (the focus register). Q sits across the aisle.",
	},
	{
		"name": "lesson_b", "beat": 2, "feet": Vector3(-3.4, 0.0, -1.2),
		"face": Vector3(-4.7, 0.0, -2.55), "note_line": true, "settle": 1.0,
		"note": "Beat 2, near the lectern: the lectern zone's fixed shot. B is not there; the impression of B is: the room turns ink blue, a shadow nobody casts climbs the front wall, the lectern stands taller than it is, the set square's shadow crosses the floor toward his desk, and its wedge cuts into the dialogue strip.",
	},
	{
		"name": "curtain_closed", "beat": 3, "feet": Vector3(-5.2, 0.0, 2.2),
		"face": Vector3(-7.0, 0.0, 2.2), "settle": 0.8,
		"note": "Beat 3, the curtain zone's fixed shot: deep blue pleats over the west opening, daylight leaking round their edges onto the floor - the one part of the room that is not wall.",
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
		"note": "Leaning out: the blank gives way, the paper lifts, and he lands in colour in the yard below, getting up; the yard's fixed shot. The opening is a white rectangle in the face of the building; Q is still upstairs.",
	},
	{
		"name": "walk_start", "beat": 2, "feet": Vector3(-0.4, 0.0, 0.4),
		"face": Vector3(-0.4, 0.0, -2.0), "settle": 0.6,
		"note": "Runtime, fixed camera 1/3: standing in the aisle, the classroom shot.",
	},
	{
		"name": "walk_moved", "beat": 2, "feet": Vector3(-0.4, 0.0, 0.4),
		"face": Vector3(-0.4, 0.0, -2.0), "keys": [[KEY_D, 0.45], [KEY_W, 0.3]], "settle": 0.1,
		"note": "Runtime, fixed camera 2/3: the same start, then A and W held (as a player would): he has walked about two metres across the aisle; the camera has not moved, turned or zoomed (compare its position in the line below with frame 1/3).",
	},
	{
		"name": "walk_east", "beat": 2, "feet": Vector3(3.0, 0.0, 0.2),
		"face": Vector3(4.0, 0.0, 1.0), "keys": [[KEY_S, 0.7]], "settle": 2.0,
		"note": "Runtime, fixed camera 3/3: walking on into the east side of the room crosses into another zone; the camera cut once (a short dip) to that zone's fixed shot, from the window wall, and is still again.",
	},
	{
		"name": "corridor_q", "beat": 3, "feet": Vector3(8.6, 0.0, -1.4),
		"face": Vector3(8.6, 0.0, 3.0), "door": true, "q": 2, "settle": 1.0,
		"note": "Out of the front door into the open corridor: the corridor's fixed shot. Q has come to the doorway (put there for the frame; in play he walks) and stays on the classroom side; he does not follow.",
	},
	{
		"name": "bell_n", "beat": 4, "feet": Vector3(2.4, 0.0, 0.6),
		"face": Vector3(0.6, 0.0, -3.2), "q": 3, "settle": 1.6,
		"note": "Beat 4. The bell: the fluorescent tubes come on and drain the colour, the projector drops to standby, the clock reads 11:00, and N stands on the platform beside the lectern, not at it. Q is back in his seat.",
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
		_scene.call("observe", frame["feet"], frame["face"])
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
	if frame.has("eye"):
		_scene.call("look_from", frame["eye"], frame["look"])
	await _physics(4)
	var camera_before := camera.global_transform
	for held: Array in frame.get("keys", []):
		_press(int(held[0]), true)
		await _wait(float(held[1]))
		_press(int(held[0]), false)
		await _physics(1)
	await _wait(float(frame.get("settle", 0.6)))
	_save(out_dir, shot_name)
	var paper := _scene.get_node("PaperSwitch")
	_lines.append(
		"  - character at %s, camera at %s looking %s (shot `%s`%s), fov %.0f, zone `%s`, beat %d, paper %s%s"
		% [
			str((_scene.get_node("Visitor") as Node3D).global_position.snapped(Vector3.ONE * 0.01)),
			str(camera.global_position.snapped(Vector3.ONE * 0.01)),
			str((-camera.global_basis.z).snapped(Vector3.ONE * 0.01)),
			String(_scene.call("current_shot")), ", authored detail" if frame.has("eye") else "",
			camera.fov, String(_scene.call("current_zone")), int(_scene.get("beat")),
			"on" if bool(paper.call("is_on")) else "off",
			"" if not frame.has("keys") else (", camera unmoved while walking" if camera.global_transform.is_equal_approx(camera_before) else ", camera changed shot"),
		]
	)
	print("BIOLOGY_CLASSROOM_SHOT %s %s" % [shot_name, _lines[_lines.size() - 1].strip_edges().trim_prefix("- ")])
	if _perf:
		var sample: Dictionary = await _scene.call("sample_performance", 20)
		print("BIOLOGY_CLASSROOM_PERF %s %s" % [shot_name, JSON.stringify(sample)])


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


func _press(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.physical_keycode = keycode as Key
	event.pressed = pressed
	Input.parse_input_event(event)


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
