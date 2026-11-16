extends SceneTree
## Photographs the visual experiments lab (`scenes/dev/visual_experiments/`) and measures
## what each experiment costs. Not an assertion suite and not part of the headless checks:
##
##   xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_visual_experiments.gd -- label=compatibility probes=1
##
## Forward+ and Mobile are the same command with `--rendering-driver vulkan` (plus
## `--rendering-method mobile`); the project setting is not touched.
##
## Every frame shows the lab the way it is played: the protagonist standing where a person
## exploring the lab could stand, and the third-person follow camera in the room's own
## framing (or a framing given here). A few frames use a free camera ("eye"/"look") for
## a detail; the character is still in the scene. The rooms' environments and the medium
## switch respond to where the character stands, exactly as they do by hand. The HUD is
## hidden.
##
## Output: res://docs/screenshots/visual_experiments/<label>/NN_<name>.jpg and FRAMES.md.
## `docs/` is not imported by the engine.
##
## With `perf=1` the run also prints, per frame, the renderer's own monitors
## (`VISUAL_LAB_PERF`); `probes=1` adds four A/B probes that switch one experiment off and on in the
## same view (`VISUAL_LAB_PROBE`): the medium switch, the SubViewport window, the paper
## sheets, the Decal. On CI the rasteriser is software (llvmpipe / lavapipe), so frame
## times are CPU-bound and only comparable within one run; draw calls, primitives and
## memory are the renderer's own counts and do carry over.

const Harness = preload("res://tests/test_harness.gd")

const LAB := "res://scenes/dev/visual_experiments/visual_experiments.tscn"
const OUT_ROOT := "res://docs/screenshots/visual_experiments"
const CAMERA := "Observer/CameraRig/Camera3D"

## name, feet, face (where the character looks), and either a framing (yaw, pitch,
## distance; omitted = the room's own) or a free camera eye/look; fov, settle, note.
const FRAMES := [
	{
		"name": "overview", "feet": Vector3(0.0, 0.0, 4.2), "face": Vector3(0.0, 0.0, -6.0),
		"eye": Vector3(-14.0, 30.0, 14.0), "look": Vector3(22.0, 0.0, -28.0), "fov": 50.0,
		"note": "The whole lab from the flies: collage room (front), the 44 m corridor, the staff room, the classroom and the stage of flats (far right). The protagonist waits at the start.",
	},
	{
		"name": "collage_room", "feet": Vector3(0.0, 0.0, -2.6), "face": Vector3(0.0, 0.0, -11.0),
		"fov": 58.0,
		"note": "A - The follow camera's framing for the collage room: the protagonist among walls of torn paper, the reprinted clock and timetable, cut-out desks and pupils.",
	},
	{
		"name": "collage_detail", "feet": Vector3(3.6, 0.0, -4.4), "face": Vector3(1.6, 0.0, -4.6),
		"eye": Vector3(5.2, 2.6, -0.8), "look": Vector3(1.8, 0.5, -4.6), "fov": 55.0,
		"note": "A - Mixed media up close: the real 3D desk and chair among paper desks drawn in oblique projection, the Decal seal stamped across desk and floor, the reprinted window; the protagonist is a real model among them.",
	},
	{
		"name": "collage_flatness", "feet": Vector3(-3.8, 0.0, -6.6), "face": Vector3(3.0, 0.0, -6.4),
		"eye": Vector3(-5.6, 2.0, -5.2), "look": Vector3(3.0, 0.8, -6.4), "fov": 60.0,
		"note": "A - From the side the paper desks vanish to a line; the Y-billboard pupils have turned to face the camera.",
	},
	{
		"name": "corridor_long", "feet": Vector3(0.0, 0.0, -16.5), "face": Vector3(0.0, 0.0, -56.0),
		"fov": 60.0,
		"note": "B - The corridor's low chase framing: every door numbered 2-3, each 85% of the last, fog swallowing the far end.",
	},
	{
		"name": "corridor_giant_door", "feet": Vector3(-0.3, 0.0, -37.0), "face": Vector3(1.3, 0.0, -40.0),
		"framing": Vector3(-10.0, 18.0, 4.6), "fov": 64.0,
		"note": "B - The one doorway taller than the wall it is cut into, beside the character for scale.",
	},
	{
		"name": "corridor_window", "feet": Vector3(0.5, 0.0, -24.2), "face": Vector3(-1.3, 0.0, -26.0),
		"framing": Vector3(8.0, 16.0, 3.6), "fov": 58.0,
		"note": "B - A window in the corridor that looks down into the collage room (a live SubViewport, rendered only while you are in the corridor).",
	},
	{
		"name": "expression_room", "feet": Vector3(10.5, 0.0, -37.2), "face": Vector3(15.0, 0.0, -41.0),
		"fov": 55.0,
		"note": "C - The staff room from its framing, through the ceiling that is culled from above: viridian and ochre floor, Prussian blue and cadmium walls leaning in, one barred light, twelve chairs and one.",
	},
	{
		"name": "expression_shadow", "feet": Vector3(13.2, 0.0, -38.6), "face": Vector3(15.5, 0.0, -40.6),
		"framing": Vector3(-30.0, 62.0, 6.0), "fov": 55.0,
		"note": "C - The single chair: its real shadow falls west, its painted shadow runs east toward the light; painted sunlight on the wall from no window.",
	},
	{
		"name": "threshold_3d", "feet": Vector3(31.5, 0.0, -40.0), "face": Vector3(40.0, 0.0, -40.0),
		"framing": Vector3(-90.0, 18.0, 4.8), "fov": 60.0,
		"note": "D - The ordinary classroom (the game's own desks and chairs), and through the doorway ahead of the protagonist, the stage of flats - still in 3D.",
	},
	{
		"name": "threshold_painted", "feet": Vector3(41.0, 0.0, -39.6), "face": Vector3(48.0, 0.0, -40.5),
		"fov": 58.0, "settle": 1.4,
		"note": "D - One step past the threshold: the same 3D world, protagonist included, now rendered at half size and painted onto a crooked paper mount. Q stands in the painting; the flats are still solid.",
	},
	{
		"name": "classroom_picture", "feet": Vector3(30.2, 0.0, -36.2), "face": Vector3(30.0, 0.0, -34.0),
		"framing": Vector3(180.0, 28.0, 3.8), "fov": 55.0,
		"note": "D - The picture on the classroom wall is a live view of the stage next door, banded like a cheap print.",
	},
	{
		"name": "backstage", "feet": Vector3(51.4, 0.0, -45.2), "face": Vector3(45.0, 0.0, -39.0),
		"framing": Vector3(110.0, 40.0, 6.0), "fov": 60.0,
		"note": "D - Behind the painting: plywood backs, braces and stage weights, back in 3D (the backstage station's framing, from the east).",
	},
]

var _lab: Node3D = null
var _label := "capture"
var _width := 0
var _quality := 0.86
var _probes := false
var _perf := false
var _only: Array[String] = []
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 900.0, "capture_visual_experiments.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("label="):
			_label = arg.substr(6).strip_edges()
		elif arg.begins_with("width="):
			_width = maxi(0, int(arg.substr(6)))
		elif arg.begins_with("quality="):
			_quality = clampf(float(arg.substr(8)), 0.3, 1.0)
		elif arg.begins_with("probes="):
			_probes = arg.substr(7).strip_edges() == "1"
		elif arg.begins_with("perf="):
			_perf = arg.substr(5).strip_edges() == "1"
		elif arg.begins_with("only="):
			for frame_name: String in arg.substr(5).strip_edges().split(",", false):
				_only.append(frame_name.strip_edges())
	_perf = _perf or _probes
	call_deferred("_run")


func _run() -> void:
	var out_dir := "%s/%s" % [OUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var packed := load(LAB) as PackedScene
	if packed == null:
		_finish(["The visual experiments lab could not be loaded."])
		return
	_lab = packed.instantiate() as Node3D
	root.add_child(_lab)
	_lab.call("set_hud_visible", false)
	await _wait(0.8)
	var renderer := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	print("VISUAL_LAB_CAPTURE renderer=%s driver=%s adapter=%s" % [
		renderer, driver, RenderingServer.get_video_adapter_name()
	])
	_lines.append("# Visual experiments frames: %s" % _label)
	_lines.append("")
	_lines.append(
		"Captured by `tests/capture_visual_experiments.gd` under Xvfb at %s, renderer `%s` (%s, %s)."
		% [str(root.size), renderer, driver, RenderingServer.get_video_adapter_name()]
	)
	_lines.append("")
	for index in FRAMES.size():
		var frame: Dictionary = FRAMES[index]
		if not _only.is_empty() and not _only.has(String(frame["name"])):
			continue
		var shot_name := "%02d_%s" % [index, String(frame["name"])]
		await _shoot(frame, out_dir, shot_name)
		_lines.append("- `%s.jpg` - %s" % [shot_name, String(frame["note"])])
	if _probes:
		await _run_probes()
	var file := FileAccess.open("%s/FRAMES.md" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	_finish(_failures)


func _shoot(frame: Dictionary, out_dir: String, shot_name: String) -> void:
	var camera := _lab.get_node(CAMERA) as Camera3D
	camera.fov = float(frame.get("fov", 55.0))
	var framing: Vector3 = frame.get("framing", Vector3.ZERO)
	_lab.call("observe", frame["feet"], frame["face"], framing)
	if frame.has("eye"):
		_lab.call("look_from", frame["eye"], frame["look"])
	await _physics(4)
	await _wait(float(frame.get("settle", 0.6)))
	_save(out_dir, shot_name)
	var painted := bool(_lab.get_node("MediumSwitch").call("is_painted"))
	_lines.append(
		"  - character at %s, camera at %s (%s), fov %.0f, zone `%s`, medium %s"
		% [str(frame["feet"]), str(camera.global_position.snapped(Vector3.ONE * 0.01)),
			"free camera" if frame.has("eye") else "follow camera", camera.fov,
			String(_lab.call("current_zone")), "painted" if painted else "3D"]
	)
	if _perf:
		var sample: Dictionary = await _lab.call("sample_performance", 20)
		print("VISUAL_LAB_PERF %s %s" % [shot_name, JSON.stringify(sample)])
	camera.fov = 55.0


## Switches one experiment off and on in the same view and reports both samples.
func _run_probes() -> void:
	var switch := _lab.get_node("MediumSwitch")
	var collage := _lab.get_node("Zones/Collage")
	var corridor := _lab.get_node("Zones/Corridor")
	# The medium switch, standing on the stage.
	_lab.call("observe", Vector3(41.0, 0, -39.6), Vector3(48.0, 0, -40.5))
	await _physics(4)
	await _wait(1.2)
	var toggle_medium := func(enabled: bool) -> void: switch.call("set_painted", enabled, true)
	await _probe("medium_switch", "painted", "3d", toggle_medium)
	# The corridor window's SubViewport.
	_lab.call("observe", Vector3(0.5, 0, -24.2), Vector3(-1.3, 0, -26.0), Vector3(8.0, 16.0, 3.6))
	await _physics(2)
	var toggle_window := func(enabled: bool) -> void: corridor.call("set_window_live", enabled)
	await _probe("corridor_window", "live", "frozen", toggle_window)
	# The paper sheets, from the collage room's doorway.
	_lab.call("observe", Vector3(0.0, 0, 4.2), Vector3(0.0, 0, -6.0))
	await _physics(2)
	var sheets: Array = collage.get("sheets")
	var toggle_sheets := func(enabled: bool) -> void:
		for sheet: MeshInstance3D in sheets:
			sheet.visible = enabled
	await _probe("paper_sheets_%d" % sheets.size(), "shown", "hidden", toggle_sheets)
	# The Decal, where it lands on the real desk.
	_lab.call("observe", Vector3(3.6, 0, -4.4), Vector3(1.6, 0, -4.6))
	_lab.call("look_from", Vector3(4.6, 1.8, -1.6), Vector3(1.6, 0.5, -4.6))
	await _physics(2)
	var decal := collage.get("decal") as Decal
	var toggle_decal := func(enabled: bool) -> void: decal.visible = enabled
	await _probe("decal", "shown", "hidden", toggle_decal)


func _probe(probe_name: String, on_label: String, off_label: String, toggle: Callable) -> void:
	toggle.call(true)
	await _wait(0.3)
	var on_sample: Dictionary = await _lab.call("sample_performance", 20)
	toggle.call(false)
	await _wait(0.3)
	var off_sample: Dictionary = await _lab.call("sample_performance", 20)
	toggle.call(true)
	print(
		"VISUAL_LAB_PROBE %s %s: draw %s prims %s ms %s vmem %s | %s: draw %s prims %s ms %s vmem %s"
		% [
			probe_name,
			on_label, on_sample["draw_calls"], on_sample["primitives"], on_sample["frame_ms"],
			on_sample["video_mem_mib"],
			off_label, off_sample["draw_calls"], off_sample["primitives"], off_sample["frame_ms"],
			off_sample["video_mem_mib"],
		]
	)


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
	print("VISUAL_LAB_FRAME %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _physics(count: int) -> void:
	for _index in count:
		await physics_frame
	await process_frame


func _finish(failures: Array) -> void:
	Harness.finish(self, failures, "visual experiments frames written for %s" % _label)
