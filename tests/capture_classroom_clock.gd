extends SceneTree
## Photographs the classroom clock and reads the time back off the frames (#173).
##
## Q says biology starts at nine; PR #176 set the clock's hands to nine and
## `classroom_visual_slice` reads that from the scene's transforms. Issue #173 also asks for
## what a transform cannot show: a close-up of the face and frames through the game's own
## camera, in which the clock **reads** about nine from where a player actually stands. This
## capture takes three views of the running game and, for each, reads the hands off the
## rendered pixels:
##
## - `clock_closeup`        a camera square to the dial, the face filling most of the frame;
## - `clock_gameplay_rows`  the game camera from the aisle beside the front row of desks;
## - `clock_gameplay_aisle` the game camera from the spot in the aisle under the board where
##                          the face is largest (the same grid `classroom_visual_slice` uses).
##
## (The game camera hangs high behind the player. Whether the clock is in the frame at all
## from where a new game starts is recorded as a `start` note in CLOCK.txt - a diagnostic,
## not a verdict: nothing in #173 promises the clock can be read from the first desk.)
##
## For each view the same frame is rendered four more times - with both hands hidden, with
## only the hour hand, with only the minute hand, and with both hidden again. A hand's pixels
## are exactly the pixels that change when it appears, so nothing painted on the dial can be
## read as a hand; the two hands-hidden renders must agree inside the dial, or the room moved
## between renders and the reading is retried. `tests/clock_reading.gd` maps those pixels back
## onto the dial (through the projected twelve- and three-o'clock radii, so a dial seen at an
## angle is read as a dial) and reports where each hand points, how long it looks, how much
## it stands out, and whether it is a line rather than a smudge.
##
## The capture fails when a view does not read nine o'clock within its slack, when a hand is
## too faint or too short to read, when the minute hand does not look the longer of the two,
## or when the frame is not a real render. The unmodified view is saved as `<name>.png` (and,
## when `WIS_EVIDENCE_JPEG_QUALITY` is set, a full-size `<name>.jpg`), and each view prints an
## `EVIDENCE {json}` record of what it shows, which `tools/evidence_relay.py` carries into
## `docs/screenshots/MANIFEST.json`. No pixel is retouched.
##
## Run with a window, never --headless:
##   godot --path . --resolution 1600x900 --script res://tests/capture_classroom_clock.gd \
##     -- --output=build/clock-evidence [--expect-renderer=<method>] [--expect-driver=<driver>]

const Harness = preload("res://tests/test_harness.gd")
const ClockReading = preload("res://tests/clock_reading.gd")
const EvidenceContract = preload("res://tests/evidence_contract.gd")

const SCENE := "scenes/locations/classroom/classroom.tscn"
const DIAL_PATH := ^"WallNorth/FrontWallDressing/ClockDial"
const HOUR_HAND_PATH := ^"ClockHourPivot/ClockHandHour"
const MINUTE_HAND_PATH := ^"ClockMinutePivot/ClockHandMinute"
## What the story needs the clock to say: nine o'clock, minutes past twelve on the dial.
const TARGET_MINUTES := 540.0
const TARGET_TEXT := "9:00"
const FRAME_SIZE := Vector2i(1600, 900)
## How far each hand may point from nine o'clock, in degrees, by view. Square on, a hand is
## hundreds of pixels long and a degree is visible. Through the game camera the face is a few
## dozen pixels across and a pixel of the hand is several degrees, so the slack is what still
## reads as "nine" at a glance: a quarter of an hour on the hour hand, two minutes and a half
## on the minute hand.
const CLOSEUP_SLACK := 3.0
const GAMEPLAY_SLACK := 15.0
## A hand stands out from the dial behind it by at least this much (0..1, the largest channel).
const MIN_CONTRAST := 0.2
## The minute hand looks this much longer than the hour hand, or the two are mistaken.
const MIN_LENGTH_RATIO := 1.1
## A hand shorter than this on screen is a dot, not a direction.
const MIN_HAND_PIXELS := 5.0
## The face is at least this many pixels across from the aisle (as `classroom_visual_slice`).
const MIN_AISLE_FACE := 30.0
## Two renders of the same view may differ in this many pixels inside the dial and still be
## the same moment (antialiasing settling); more, and the room moved.
const STILL_PIXELS := 3
const ATTEMPTS := 3
## The aisle grid, in room coordinates, from `classroom_visual_slice_test.gd` (section 10).
const STAND_X: Array[float] = [0.45, 1.45, 2.45]
const STAND_Z: Array[float] = [-3.9, -3.4, -2.9, -2.4]
## The aisle between the second and third columns of desks, level with the front row
## (room coordinates; snapped onto the navigation mesh).
const ROWS_STAND := Vector3(0.0, 0.0, -0.8)

var _main: Node3D = null
var _room: LocationRoot = null
var _player: PlayerController = null
var _rig: CameraRig = null
var _dial: MeshInstance3D = null
var _hour: MeshInstance3D = null
var _minute: MeshInstance3D = null
var _hand_shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
var _out := "res://build/clock-evidence"
var _expect_renderer := ""
var _expect_driver := ""
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_classroom_clock.gd")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
		elif argument.begins_with("--expect-renderer="):
			_expect_renderer = argument.trim_prefix("--expect-renderer=")
		elif argument.begins_with("--expect-driver="):
			_expect_driver = argument.trim_prefix("--expect-driver=")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		Harness.finish(self, ["A real display and renderer are required; a headless frame is not evidence."], "")
		return
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_main = packed.instantiate() as Node3D
	_main.get_node("OpeningSequence").set("autostart", false)
	root.add_child(_main)
	await _physics(5)
	_player = _main.get_node("Player") as PlayerController
	_rig = _main.get_node("CameraRig") as CameraRig
	_room = (_main.get_node("LocationHost") as LocationHost).get_current()
	var start := _player.global_transform
	_main.get_node("OpeningSequence").allow_player_control()
	# Autostart is off, so only the presentation half of the wake is completed here;
	# otherwise the still-opaque fade would hide a live room.
	(_main.get_node("GameUI") as GameUI).fade.set_clear()
	_player.set_wake_pose(0.0)
	_player.set_camera_roll(0.0)
	var navigation := _room.get_node("Navigation") as LocationNavigation
	if not await navigation.wait_until_synchronized():
		_failures.append("Classroom navigation did not synchronize.")
	_dial = _room.get_node_or_null(DIAL_PATH) as MeshInstance3D
	_hour = _room.get_node_or_null(HOUR_HAND_PATH) as MeshInstance3D
	_minute = _room.get_node_or_null(MINUTE_HAND_PATH) as MeshInstance3D
	if (
		_dial == null or _hour == null or _minute == null
		or not _dial.mesh is QuadMesh or not _hour.mesh is BoxMesh or not _minute.mesh is BoxMesh
	):
		await _end(["The classroom clock is no longer a painted dial with two box hands; nothing to read."])
		return
	_hand_shadows = _minute.cast_shadow
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if error != OK:
		await _end(["Cannot create %s: %s" % [_out, error_string(error)]])
		return
	_record_renderer()

	# What the scene says, read the same way the frames will be.
	var basis := _dial.global_transform.basis
	var normal := _dial_normal()
	var scene_hour := ClockReading.scene_hand_degrees(
		_hour, (_hour.mesh as BoxMesh).size.y, _dial.global_position, basis.y, normal
	)
	var scene_minute := ClockReading.scene_hand_degrees(
		_minute, (_minute.mesh as BoxMesh).size.y, _dial.global_position, basis.y, normal
	)
	var scene_reading := ClockReading.reading(scene_hour, scene_minute)
	_note("scene reads %s (hour %.2f, minute %.2f)" % [scene_reading["text"], scene_hour, scene_minute])
	if String(scene_reading["text"]) != TARGET_TEXT:
		_failures.append(
			"The clock's nodes read %s, not %s; Q's biology class is at nine." % [scene_reading["text"], TARGET_TEXT]
		)

	# 1. Square on to the dial.
	var closeup := Camera3D.new()
	closeup.name = "ClockEvidenceCamera"
	closeup.fov = 40.0
	_main.add_child(closeup)
	var radius := (_dial.mesh as QuadMesh).size.x * 0.5
	closeup.global_position = _dial.global_position + normal * radius * 3.6
	closeup.look_at(_dial.global_position, basis.y.normalized())
	closeup.current = true
	await _physics(15)
	await _view("clock_closeup", "closeup", closeup, CLOSEUP_SLACK, 0.0, scene_reading)
	closeup.current = false
	closeup.queue_free()
	_rig.camera.current = true

	# Diagnostic only: how the clock looks from where a new game puts the player.
	_player.teleport(start)
	_rig.snap()
	await _physics(2)
	var from_start := _face_pixels(_rig.camera)
	_note(
		"start=%s clock=%s" % [
			str(start.origin),
			"in the frame, %.0f px across" % from_start if from_start > 0.0 else "out of the frame",
		]
	)

	# 2. Through the game camera, from the aisle beside the front row of desks: further back,
	# where a player walking up to the board first has the clock in view.
	var rows := _room.to_global(ROWS_STAND)
	var rows_map := navigation.get_navigation_map()
	if rows_map.is_valid():
		rows = NavigationServer3D.map_get_closest_point(rows_map, rows)
	_player.teleport(Transform3D(Basis(), rows))
	_rig.snap()
	await _physics(35)
	await _view("clock_gameplay_rows", "rows", _rig.camera, GAMEPLAY_SLACK, 0.0, scene_reading)

	# 3. Through the game camera, from the best place in the aisle under the board.
	var best := -1.0
	var stand := Vector3.ZERO
	var map := navigation.get_navigation_map()
	for x in STAND_X:
		for z in STAND_Z:
			var point := _room.to_global(Vector3(x, 0.0, z))
			if map.is_valid():
				point = NavigationServer3D.map_get_closest_point(map, point)
			_player.teleport(Transform3D(Basis(), point))
			_rig.snap()
			var face := _face_pixels(_rig.camera)
			if face > best:
				best = face
				stand = point
	if best <= 0.0:
		_failures.append("From no standing spot in the aisle does the game camera see the clock.")
	else:
		_player.teleport(Transform3D(Basis(), stand))
		_rig.snap()
		await _physics(35)
		await _view("clock_gameplay_aisle", "aisle", _rig.camera, GAMEPLAY_SLACK, MIN_AISLE_FACE, scene_reading)
	await _end(_failures)


## Renders one view, reads both hands off it, saves the unmodified frame and prints its record.
func _view(
	frame: String, view: String, camera: Camera3D, slack: float, min_face: float, scene_reading: Dictionary
) -> void:
	var centre_3d := _dial.global_position
	if not camera.is_position_in_frustum(centre_3d):
		_failures.append("%s: the clock is not in the frame." % frame)
		return
	var geometry := _dial_on_screen(camera)
	var centre: Vector2 = geometry["centre"]
	var twelve: Vector2 = geometry["twelve"]
	var three: Vector2 = geometry["three"]
	var face := _face_pixels(camera)
	var shot: Image = null
	var hour := {}
	var minute := {}
	var still := false
	for attempt in ATTEMPTS:
		_show_hands(true, true, false)
		shot = await _render()
		_show_hands(false, false)
		var bare := await _render()
		_show_hands(true, false)
		var hour_only := await _render()
		_show_hands(false, true)
		var minute_only := await _render()
		_show_hands(false, false)
		var bare_again := await _render()
		_show_hands(true, true, false)
		if shot == null or bare == null or hour_only == null or minute_only == null or bare_again == null:
			_failures.append("%s: a render came back empty." % frame)
			return
		var drift := ClockReading.dial_change(bare, bare_again, centre, twelve, three)
		if int(drift["pixels"]) > STILL_PIXELS:
			_note("%s attempt %d: the dial changed in %d pixels between two identical renders; again" % [frame, attempt + 1, drift["pixels"]])
			continue
		hour = ClockReading.measure_hand(bare, hour_only, centre, twelve, three)
		minute = ClockReading.measure_hand(bare, minute_only, centre, twelve, three)
		still = true
		break
	if not still:
		_failures.append("%s: the dial would not hold still across %d attempts; nothing was read." % [frame, ATTEMPTS])
		return
	if not _real_frame(frame, shot):
		return
	var path := _out.path_join(frame + ".png")
	var saved := shot.save_png(ProjectSettings.globalize_path(path))
	if saved != OK:
		_failures.append("%s: %s" % [path, error_string(saved)])
		return
	EvidenceContract.write_jpeg_copy(shot, ProjectSettings.globalize_path(path))
	_note("shot=%s sha256=%s" % [frame + ".png", FileAccess.get_sha256(path)])

	var wanted := ClockReading.hand_degrees_at(TARGET_MINUTES)
	var problems: Array[String] = []
	for entry: Array in [["hour", hour, float(wanted["hour"])], ["minute", minute, float(wanted["minute"])]]:
		var measured: Dictionary = entry[1]
		if not bool(measured.get("ok", false)):
			problems.append("the %s hand cannot be found (%s)" % [entry[0], measured.get("error", "no reading")])
			continue
		var off := ClockReading.degrees_off(float(measured["degrees"]), entry[2])
		if off > slack:
			problems.append(
				"the %s hand points %.1f degrees from where nine o'clock puts it (slack %.0f)" % [entry[0], off, slack]
			)
		if float(measured["contrast"]) < MIN_CONTRAST:
			problems.append(
				"the %s hand stands out from the dial by only %.2f (needs %.2f)" % [entry[0], measured["contrast"], MIN_CONTRAST]
			)
		if float(measured["length_px"]) < MIN_HAND_PIXELS:
			problems.append("the %s hand is %.1f px long, a dot rather than a direction" % [entry[0], measured["length_px"]])
		if float(measured["concentration"]) < 0.6:
			problems.append("the %s hand reads as a smudge, not a line (%.2f)" % [entry[0], measured["concentration"]])
	var shown := {"text": "?"}
	if problems.is_empty():
		shown = ClockReading.reading(float(hour["degrees"]), float(minute["degrees"]))
		if float(minute["length_px"]) < float(hour["length_px"]) * MIN_LENGTH_RATIO:
			problems.append(
				"the minute hand looks %.1f px long and the hour hand %.1f px; they cannot be told apart"
				% [minute["length_px"], hour["length_px"]]
			)
		if String(shown["text"]) != TARGET_TEXT:
			problems.append("the frame reads %s, not %s" % [shown["text"], TARGET_TEXT])
	if min_face > 0.0 and face < min_face:
		problems.append("the face is %.0f px across; it cannot be read from here (needs %.0f)" % [face, min_face])
	for problem in problems:
		_failures.append("%s: %s." % [frame, problem])

	# A hand that was not found has no angle: null in the record, not NaN (JSON has none).
	var hour_angle: Variant = null
	if bool(hour.get("ok", false)):
		hour_angle = snappedf(float(hour["degrees"]), 0.01)
	var minute_angle: Variant = null
	if bool(minute.get("ok", false)):
		minute_angle = snappedf(float(minute["degrees"]), 0.01)
	var measured_record := {
		"reads": String(shown["text"]),
		"face_px": snappedf(face, 0.1),
		"hour_degrees": hour_angle,
		"minute_degrees": minute_angle,
		"hour_length_px": snappedf(float(hour.get("length_px", 0.0)), 0.1),
		"minute_length_px": snappedf(float(minute.get("length_px", 0.0)), 0.1),
		"hour_contrast": snappedf(float(hour.get("contrast", 0.0)), 0.001),
		"minute_contrast": snappedf(float(minute.get("contrast", 0.0)), 0.001),
		"slack_degrees": slack,
	}
	var engine := Engine.get_version_info()
	var record := {
		"frame": frame,
		"size": [shot.get_width(), shot.get_height()],
		"godot": "%d.%d.%d" % [int(engine.get("major", 0)), int(engine.get("minor", 0)), int(engine.get("patch", 0))],
		"renderer": RenderingServer.get_current_rendering_method(),
		"shows": {
			"kind": "clock",
			"scene": SCENE,
			"view": view,
			"reads": String(scene_reading["text"]),
			"measured": measured_record,
		},
	}
	print(EvidenceContract.evidence_line(record))
	_note(
		"reading=%s reads=%s hour=%s minute=%s face=%.1f"
		% [frame, shown["text"], measured_record["hour_degrees"], measured_record["minute_degrees"], face]
	)
	_note(
		"%s: reads %s off the pixels (hour %s, minute %s), face %.0f px, hands %.1f / %.1f px, contrast %.2f / %.2f%s"
		% [
			frame, shown["text"], measured_record["hour_degrees"], measured_record["minute_degrees"], face,
			measured_record["hour_length_px"], measured_record["minute_length_px"],
			measured_record["hour_contrast"], measured_record["minute_contrast"],
			"" if problems.is_empty() else " - FAILED",
		]
	)


## The dial's centre on screen and the screen offsets from it to the rim at twelve and three.
func _dial_on_screen(camera: Camera3D) -> Dictionary:
	var basis := _dial.global_transform.basis
	var radius := (_dial.mesh as QuadMesh).size.x * 0.5
	var up := basis.y.normalized()
	var right := up.cross(_dial_normal()).normalized()
	var centre_3d := _dial.global_position
	var scale := _screen_scale()
	var centre := camera.unproject_position(centre_3d) * scale
	return {
		"centre": centre,
		"twelve": camera.unproject_position(centre_3d + up * radius) * scale - centre,
		"three": camera.unproject_position(centre_3d + right * radius) * scale - centre,
	}


## The direction out of the face, towards whoever reads it: the side of the dial the hands
## are on, whichever way the quad itself happens to be turned.
func _dial_normal() -> Vector3:
	var normal := _dial.global_transform.basis.z.normalized()
	if (_minute.global_position - _dial.global_position).dot(normal) < 0.0:
		normal = -normal
	return normal


## How many pixels across the face is on screen (the larger of its two projected diameters).
func _face_pixels(camera: Camera3D) -> float:
	if not camera.is_position_in_frustum(_dial.global_position):
		return 0.0
	var geometry := _dial_on_screen(camera)
	return 2.0 * maxf((geometry["twelve"] as Vector2).length(), (geometry["three"] as Vector2).length())


## Viewport coordinates to image pixels, in case the window and the viewport ever differ.
func _screen_scale() -> Vector2:
	var shown_size := root.get_visible_rect().size
	if shown_size.x <= 0.0 or shown_size.y <= 0.0:
		return Vector2.ONE
	return Vector2(float(root.size.x) / shown_size.x, float(root.size.y) / shown_size.y)


## Shows the hands asked for. In the measuring renders (`measuring`) a hand casts no shadow,
## so the pixels that change when it appears are the hand itself and not its shadow on the
## dial; the saved frame is rendered with the scene's own shadow settings.
func _show_hands(hour: bool, minute: bool, measuring: bool = true) -> void:
	_hour.visible = hour
	_minute.visible = minute
	var casting := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if measuring else _hand_shadows
	)
	_hour.cast_shadow = casting
	_minute.cast_shadow = casting


func _render() -> Image:
	for _index in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return image


## A frame of the right size that is not one flat colour (a fade, a loading panel).
func _real_frame(frame: String, image: Image) -> bool:
	if image.get_width() != FRAME_SIZE.x or image.get_height() != FRAME_SIZE.y:
		_failures.append("%s is %dx%d, not a rendered %dx%d frame." % [frame, image.get_width(), image.get_height(), FRAME_SIZE.x, FRAME_SIZE.y])
		return false
	var sample := image.duplicate() as Image
	sample.resize(40, 24, Image.INTERPOLATE_BILINEAR)
	var lowest := 1.0
	var highest := 0.0
	for y in sample.get_height():
		for x in sample.get_width():
			var pixel := sample.get_pixel(x, y)
			var value := (pixel.r + pixel.g + pixel.b) / 3.0
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	if highest - lowest < 0.15:
		_failures.append("%s is blank or covered, not a picture of the room." % frame)
		return false
	return true


func _record_renderer() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var driver := ""
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		driver = String(RenderingServer.call("get_current_rendering_driver_name"))
	# The same lines, in the same form, as CAPTURE.txt: tools/classroom_render_evidence.py
	# reads both the same way.
	_note("engine=%s renderer=%s display=%s" % [Engine.get_version_info().string, method, DisplayServer.get_name()])
	_note("adapter=%s" % RenderingServer.get_video_adapter_name())
	_note("driver=%s" % driver)
	_note("viewport=%s" % str(root.size))
	if not _expect_renderer.is_empty() and method != _expect_renderer:
		_failures.append("The renderer is '%s', not the expected '%s'." % [method, _expect_renderer])
	if not _expect_driver.is_empty() and driver != _expect_driver:
		_failures.append("The rendering driver is '%s', not the expected '%s'." % [driver, _expect_driver])


func _end(failures: Array) -> void:
	var log_file := FileAccess.open(_out.path_join("CLOCK.txt"), FileAccess.WRITE)
	if log_file != null:
		for failure: Variant in failures:
			_lines.append("failure=%s" % String(failure))
		_lines.append("verdict=" + ("PASS" if failures.is_empty() else "FAIL"))
		log_file.store_string("\n".join(_lines) + "\n")
		log_file.close()
	if _main != null:
		_main.queue_free()
	await _physics(3)
	Harness.finish(self, failures, "the classroom clock reads %s off the pixels from every view." % TARGET_TEXT)


func _physics(count: int) -> void:
	for _index in count:
		await physics_frame


func _note(line: String) -> void:
	_lines.append(line)
	print("CLOCK_CAPTURE " + line)
