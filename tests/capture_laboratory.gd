extends SceneTree
## Photographs the laboratory for issue #163: the seven frames the acceptance asks for,
## from the game's own camera and from a framed camera, under Xvfb.
##
## Not an assertion suite and not part of the headless checks:
##
##   xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_laboratory.gd -- label=forward_plus
##
## Two kinds of frame, and the difference matters when they are read as evidence:
##
## - **standing** frames put the *player* on a floor position and let the real follow
##   camera (`CameraRig`) do the framing. They are what a player sees standing there, so
##   they are also the proof that the place they show can be walked to.
## - **framed** frames add a temporary camera on the game's own bearing and look straight
##   at one subject, for the close-ups the follow camera cannot take. They are still the
##   real scene, rendered by the real renderer; only the lens is chosen.
##
## Output: res://docs/screenshots/laboratory/<label>/NN_<name>.jpg and FRAMES.md beside
## them. `docs/` is not imported by the engine.
##
## Every frame is listed with the position it was taken from, so a reviewer can walk the
## same route in the editor instead of trusting the caption.

const Harness = preload("res://tests/test_harness.gd")

const LABORATORY := "res://scenes/locations/laboratory/laboratory.tscn"
const OUT_ROOT := "res://docs/screenshots/laboratory"

## Each frame: name, kind ("standing" or "framed"), where the eye or the player stands,
## what it looks at, and what the frame is evidence for.
const FRAMES := [
	{
		"name": "room_wide",
		"kind": "framed",
		"eye": Vector3(14.5, 12.6, 14.5),
		"look": Vector3(-0.4, 0.9, -0.6),
		"fov": 44.0,
		"note": "The whole room: wet bench and tile west, hood and cabinet north, island and drum centre, instrument bank east, the partition and its narrow door in the north-east.",
	},
	{
		"name": "entrance_view",
		"kind": "standing",
		"feet": Vector3(-4.4, 0.0, 4.4),
		"look": Vector3(0.7, 1.5, 1.0),
		"note": "Standing on the entrance spawn, facing the drum: the first second of the room.",
	},
	{
		"name": "wet_bench",
		"kind": "standing",
		"feet": Vector3(-6.0, 0.0, -3.3),
		"look": Vector3(-7.1, 1.0, -3.3),
		"note": "The wet bench: two sinks, the drying rack, the one flask still wet.",
	},
	{
		"name": "bench_detail",
		"kind": "framed",
		"eye": Vector3(-4.6, 2.3, -2.0),
		"look": Vector3(-6.9, 0.95, -2.4),
		"fov": 40.0,
		"note": "Bench detail: resin top, steel underframe, glassware, the tiled splashback.",
	},
	{
		"name": "cable_origin",
		"kind": "framed",
		"eye": Vector3(4.1, 1.9, 2.4),
		"look": Vector3(6.9, 0.7, 2.6),
		"fov": 42.0,
		"note": "Cable origins: the four machines on the instrument bench, each with a cable leaving the back of it.",
	},
	{
		"name": "cable_knot",
		"kind": "framed",
		"eye": Vector3(-0.6, 2.2, 2.6),
		"look": Vector3(1.4, 0.1, 0.1),
		"fov": 46.0,
		"note": "The knot: every run in the room meets on the floor here and leaves as one bundle.",
	},
	{
		"name": "route_aisle",
		"kind": "standing",
		"feet": Vector3(1.7, 0.0, 3.4),
		"look": Vector3(1.7, 0.9, -2.6),
		"note": "The main aisle: from the entrance side of the room, straight up to the partition, nothing in the way.",
	},
	{
		"name": "annex_door",
		"kind": "standing",
		"feet": Vector3(1.2, 0.0, -2.7),
		"look": Vector3(2.6, 1.1, -2.85),
		"note": "The narrow door in the partition, standing open, with the bundle going through it.",
	},
	{
		"name": "annex_inside",
		"kind": "framed",
		"eye": Vector3(2.9, 1.65, -1.9),
		"look": Vector3(6.4, 1.9, -3.6),
		"fov": 52.0,
		"note": "Inside the room the cables lead to: a lower ceiling, one bulb, the shaft climbing past the roof, the hatch.",
	},
	{
		"name": "explore_to_unknown",
		"kind": "standing",
		"feet": Vector3(3.3, 0.0, -2.4),
		"look": Vector3(5.6, 1.6, -4.2),
		"fov_standing": 62.0,
		"note": "The actual walk: past the door, into the annex, with the laboratory still visible behind.",
	},
	{
		"name": "far_corridor",
		"kind": "framed",
		"eye": Vector3(4.3, 1.5, -5.9),
		"look": Vector3(4.3, 1.2, -8.3),
		"fov": 55.0,
		"note": "The corridor behind the annex: the floor runs on past the north wall and ends in black.",
	},
	{
		"name": "drum_close",
		"kind": "framed",
		"eye": Vector3(3.4, 1.9, 2.9),
		"look": Vector3(0.7, 1.6, 1.0),
		"fov": 40.0,
		"note": "The running drum: motor, the vane turning on its shaft, the control box with its green light and the plate where a switch should be.",
	},
]

var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _rig: Node3D = null
var _room: LocationRoot = null
var _label := "capture"
var _width := 0
var _quality := 0.9
## Comma separated frame names to render; empty means all of them. A run that publishes
## its frames inline (`::notice` annotations) needs a small batch per job, because GitHub
## keeps 50 annotations per job and one JPEG does not fit in one annotation.
var _only: Array[String] = []
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 600.0, "capture_laboratory.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("label="):
			_label = arg.substr(6).strip_edges()
		elif arg.begins_with("width="):
			_width = maxi(0, int(arg.substr(6)))
		elif arg.begins_with("quality="):
			_quality = clampf(float(arg.substr(8)), 0.3, 1.0)
		elif arg.begins_with("only="):
			for name: String in arg.substr(5).strip_edges().split(",", false):
				_only.append(name.strip_edges())
	call_deferred("_run")


func _run() -> void:
	var out_dir := "%s/%s" % [OUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		_finish(["State autoloads are unavailable."])
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_finish(["main.tscn could not be loaded."])
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _wait(0.4)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_rig = _main.get_node_or_null("CameraRig") as Node3D
	if _host == null or _player == null or _rig == null:
		_finish(["main.tscn did not expose LocationHost, Player and CameraRig."])
		return
	# The frames are about the space; the HUD is the same in every location.
	var ui := _main.get_node_or_null("GameUI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	if not _host.load_location(LABORATORY, &"Entry", _player, &"laboratory"):
		_finish(["The laboratory did not load."])
		return
	await _wait(1.2)
	_room = _host.get_current()
	if _room == null:
		_finish(["The host reports laboratory but has no location."])
		return
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	await _wait(0.3)

	_lines.append("# Laboratory frames: %s" % _label)
	_lines.append("")
	_lines.append(
		"Captured by `tests/capture_laboratory.gd` under Xvfb (1600x900, opengl3) from "
		+ "`scenes/locations/laboratory/laboratory.tscn`. HUD hidden."
	)
	_lines.append("")
	for index in FRAMES.size():
		var frame: Dictionary = FRAMES[index]
		if not _only.is_empty() and not _only.has(String(frame["name"])):
			continue
		var shot_name := "%02d_%s" % [index, String(frame["name"])]
		if String(frame["kind"]) == "standing":
			await _standing(frame, out_dir, shot_name)
		else:
			await _framed(frame, out_dir, shot_name)
		_lines.append("- `%s.jpg` - %s" % [shot_name, String(frame["note"])])
	var file := FileAccess.open("%s/FRAMES.md" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	_finish(_failures)


## The player stands there, and the game's follow camera frames it.
func _standing(frame: Dictionary, out_dir: String, shot_name: String) -> void:
	var feet: Vector3 = frame["feet"]
	_player.teleport(Transform3D(Basis(Vector3.UP, _yaw_towards(feet, frame["look"])), feet))
	if _rig.has_method("snap"):
		_rig.call("snap")
	await _wait(0.6)
	_save(out_dir, shot_name)
	_lines.append("%s: eye at %s, looking at %s" % [shot_name, str(feet), str(frame["look"])])


## A temporary camera on the game's own bearing, framing one subject.
func _framed(frame: Dictionary, out_dir: String, shot_name: String) -> void:
	var camera := Camera3D.new()
	camera.name = "LaboratoryCaptureCamera"
	camera.fov = float(frame.get("fov", 46.0))
	camera.far = 400.0
	_main.add_child(camera)
	camera.global_position = frame["eye"]
	camera.look_at(frame["look"], Vector3.UP)
	camera.current = true
	await _wait(0.5)
	_save(out_dir, shot_name)
	_lines.append("%s: camera at %s, looking at %s" % [shot_name, str(frame["eye"]), str(frame["look"])])
	camera.queue_free()
	await _wait(0.2)


func _yaw_towards(from: Vector3, target: Vector3) -> float:
	var direction := target - from
	return atan2(-direction.x, -direction.z)


func _save(out_dir: String, name: String) -> void:
	RenderingServer.force_draw(true)
	var image: Image = root.get_texture().get_image()
	if image == null:
		_failures.append("no image for %s" % name)
		return
	if _width > 0 and image.get_width() > _width:
		var height := int(round(float(image.get_height()) * _width / image.get_width()))
		image.resize(_width, height, Image.INTERPOLATE_LANCZOS)
	var err := image.save_jpg("%s/%s.jpg" % [out_dir, name], _quality)
	if err != OK:
		_failures.append("%s could not be saved (error %d)" % [name, err])
		return
	print("LABORATORY_CAPTURE %s (%dx%d)" % [name, image.get_width(), image.get_height()])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _finish(failures: Array) -> void:
	Harness.finish(self, failures, "laboratory frames written for %s" % _label)
