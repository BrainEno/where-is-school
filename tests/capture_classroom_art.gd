extends SceneTree
## Reproducible, real-viewport evidence for the classroom art pass only.
## Run with a window (never --headless):
## godot --path . --resolution 1600x900 --script res://tests/capture_classroom_art.gd \
##   -- --output=build/classroom-evidence/after
## The same script/camera/fixtures are used against the unmodified base and PR head.
## Output stays outside the shipped assets. No post-processing or paintover is applied.
## Ten views include live gameplay, wall fade/restoration, and framing of the full room,
## board/platform, both east-wall doors, the front window and the blackout curtain, all
## twelve student desks, the projection screen rolled down and the back window's opening
## with its curtain drawn aside (issue #159).
## CI passes `--expect-renderer=<method> --expect-driver=<driver>`; a run on any other
## renderer or driver (for example after Godot's own Vulkan-to-OpenGL fallback) fails.
## CAPTURE.txt ends with `verdict=PASS|FAIL` and any failure lines.

const Harness = preload("res://tests/test_harness.gd")

var _main: Node3D = null
var _room: LocationRoot = null
var _player: PlayerController = null
var _rig: CameraRig = null
var _out := "res://build/classroom-evidence/after"
var _expect_renderer := ""
var _expect_driver := ""
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_classroom_art.gd")
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
		Harness.finish(self, ["A real display/renderer is required; headless is not evidence."], "")
		return
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := root.get_node_or_null("Loc")
	if loc != null:
		loc.set_locale("zh-CN")
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_main = packed.instantiate() as Node3D
	_main.get_node("OpeningSequence").set("autostart", false)
	root.add_child(_main)
	await _frames(5)
	_player = _main.get_node("Player") as PlayerController
	_rig = _main.get_node("CameraRig") as CameraRig
	_room = (_main.get_node("LocationHost") as LocationHost).get_current()
	_main.get_node("OpeningSequence").allow_player_control()
	# Autostart is off, so complete only the wake's presentation half in this
	# fixture. Otherwise the still-opaque FadeLayer would conceal a live room.
	(_main.get_node("GameUI") as GameUI).fade.set_clear()
	_player.set_wake_pose(0.0)
	_player.set_camera_roll(0.0)
	var navigation := _room.get_node("Navigation") as LocationNavigation
	if not await navigation.wait_until_synchronized():
		_failures.append("Classroom navigation did not synchronize.")
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if error != OK:
		Harness.finish(self, ["Cannot create evidence directory: %s" % error_string(error)], "")
		return
	_note(
		(
			"engine=%s renderer=%s display=%s"
			% [
				Engine.get_version_info().string,
				RenderingServer.get_current_rendering_method(),
				DisplayServer.get_name(),
			]
		)
	)
	_note("adapter=%s" % RenderingServer.get_video_adapter_name())
	var driver := ""
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		driver = String(RenderingServer.call("get_current_rendering_driver_name"))
	_note("driver=%s" % driver)
	var method := RenderingServer.get_current_rendering_method()
	if not _expect_renderer.is_empty() and method != _expect_renderer:
		_failures.append("The renderer is '%s', not the expected '%s'." % [method, _expect_renderer])
	if not _expect_driver.is_empty() and driver != _expect_driver:
		_failures.append("The rendering driver is '%s', not the expected '%s'." % [driver, _expect_driver])
	_note("viewport=%s" % str(root.size))

	# The game's camera, lens and player location; N is staged at its existing front
	# marker solely in this fixture, so all three characters can be assessed together.
	# That marker is the lectern's TeacherStand (#172): N stands behind the lectern and,
	# as the last step of its walk leaves it, faces the room.
	var teacher := _room.find_actor(&"n")
	teacher.visible = true
	teacher.global_position = _room.get_node("NEntryPath/AtFront").global_position
	teacher.face_towards(teacher.global_position + Vector3.BACK)
	await _stand(Vector3(0.0, 0.0, 0.25), Vector3.FORWARD)
	await _shot("01_gameplay.png")

	# The original #115 south-wall interaction route: camera occlusion is intentional
	# here. Capture the material state as well as the actual pixels, then walk away.
	await _stand(Vector3(1.6, 0.0, 2.7), Vector3.BACK)
	await _shot("02_wall_occlusion.png")
	_wall_state("occlusion")
	await _stand(Vector3(0.0, 0.0, 0.25), Vector3.FORWARD)
	await _shot("03_walls_restored.png")
	_wall_state("restored")

	# Fixed art-review framing supplements the production-camera captures; it does not
	# alter the gameplay rig, navigation, collision, or story.
	var review := Camera3D.new()
	review.name = "ClassroomEvidenceCamera"
	review.fov = 58.0
	_main.add_child(review)
	await _review_shot(review, Vector3(0.0, 8.2, 14.0), Vector3(0.0, 0.9, -0.1), "04_full_classroom.png")
	await _review_shot(review, Vector3(0.8, 3.2, 2.0), Vector3(0.0, 1.0, -3.7), "05_blackboard_platform_lectern.png")
	await _review_shot(review, Vector3(0.6, 2.6, 0.0), Vector3(6.9, 1.1, 0.0), "06_east_doors.png")
	await _review_shot(review, Vector3(-0.4, 2.7, 0.1), Vector3(-6.7, 1.7, 0.0), "07_window_and_blackout_curtain.png")
	await _review_shot(review, Vector3(0.0, 6.5, 8.8), Vector3(0.0, 0.35, 0.7), "08_twelve_student_desks.png")
	# The screen pulled down over the board, then put back as the room is built.
	var screen := _room.get_node("WallNorth/ProjectorScreen") as ProjectorScreen
	screen.set_unroll_amount(1.0)
	await _review_shot(review, Vector3(0.2, 2.4, 1.2), Vector3(-2.4, 1.3, -4.6), "09_projector_screen_down.png")
	screen.set_unroll_amount(0.0)
	# The curtain drawn aside on the hole in the west wall, then closed again.
	var curtain := _room.get_node("Anomalies/BackCurtain") as WindowCurtain
	curtain.set_open_amount(1.0)
	await _review_shot(review, Vector3(-2.2, 2.3, 2.2), Vector3(-6.9, 1.5, 2.2), "10_back_window_opening.png")
	curtain.set_open_amount(0.0)
	# The teacher's lectern with N at it (#172): from the room, from the side, and from
	# the teacher's side with its open shelves.
	await _review_shot(review, Vector3(0.7, 1.45, -1.25), Vector3(0.7, 0.85, -3.8), "11_lectern_front.png")
	await _review_shot(review, Vector3(3.1, 1.25, -3.75), Vector3(0.7, 0.8, -3.85), "12_lectern_side.png")
	await _review_shot(review, Vector3(2.2, 1.6, -4.55), Vector3(0.7, 0.6, -3.7), "13_lectern_teacher_side.png")
	review.queue_free()
	_rig.camera.current = true
	await _frames(2)
	# And through the game's own camera and lens, the player below the platform.
	await _stand(Vector3(1.0, 0.0, -1.5), Vector3.FORWARD)
	await _shot("14_lectern_gameplay.png")
	var log_file := FileAccess.open(_out.path_join("CAPTURE.txt"), FileAccess.WRITE)
	if log_file == null:
		_failures.append("Cannot write capture manifest.")
	else:
		for failure in _failures:
			_lines.append("failure=" + failure)
		_lines.append("verdict=" + ("PASS" if _failures.is_empty() else "FAIL"))
		log_file.store_string("\n".join(_lines) + "\n")
		log_file.close()
	_main.queue_free()
	await _frames(3)
	Harness.finish(
		self, _failures, "captured fourteen unmodified classroom viewport images and wall states."
	)


func _stand(at: Vector3, facing: Vector3) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	if is_zero_approx(yaw):
		yaw = 0.0001
	_player.teleport(Transform3D(Basis(Vector3.UP, yaw), at))
	await _frames(35)


func _review_shot(camera: Camera3D, at: Vector3, target: Vector3, file_name: String) -> void:
	camera.position = at
	camera.look_at(target, Vector3.UP)
	camera.current = true
	await _frames(15)
	await _shot(file_name)


func _wall_state(label: String) -> void:
	for wall_name: String in [
		"WallNorth", "WallWest", "WallEast", "WallSouthLeft", "WallSouthRight"
	]:
		var wall := _room.get_node(NodePath(wall_name))
		for node in wall.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var material := mesh.material_override as BaseMaterial3D
			if material != null:
				_note(
					(
						"%s %s instance_transparency=%.4f material_mode=%d alpha=%.4f material=%s"
						% [
							label,
							_room.get_path_to(mesh),
							mesh.transparency,
							material.transparency,
							material.albedo_color.a,
							material.resource_path,
						]
					)
				)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() != 1600 or image.get_height() != 900:
		_failures.append("%s is not a rendered 1600x900 frame." % file_name)
		return
	# A dimension-correct fade/loading panel is not visual evidence. Reject a
	# nearly uniform frame instead of giving a successful verdict over black PNGs.
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
		_failures.append("%s is blank/covered, not classroom evidence." % file_name)
		return
	var path := _out.path_join(file_name)
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		_failures.append("%s: %s" % [path, error_string(error)])
	else:
		_note("shot=%s sha256=%s" % [file_name, FileAccess.get_sha256(path)])


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _note(line: String) -> void:
	_lines.append(line)
	print("CLASSROOM_CAPTURE " + line)
