extends SceneTree
## A pixel regression for the classroom's shared fader dependency.
## Run with a real renderer, both --rendering-method forward_plus and gl_compatibility.
## A fader-driven white wall must match a control wall at the same 18% opacity.
## The old Forward+ path multiplies 18% material alpha by 18% instance opacity.
## A headless run explicitly fails rather than pretending to have checked pixels.
##
## CI (`.github/workflows/classroom-art-evidence.yml`, through tests/run_classroom_checks.sh)
## passes `--expect-renderer=<method> --expect-driver=<driver>`. Godot falls back from
## Vulkan to OpenGL on its own when Vulkan cannot start, so without this a failed Forward+
## run would be measured on Compatibility and reported as a Forward+ pass. A run on any
## other renderer or driver fails; a run with no expectation fails too, because it cannot
## say which renderer its verdict is about. Evidence is written either way.
##
## `RESULT.txt` is written after the verdict and carries it (`verdict=PASS|FAIL`), the
## measured values, the renderer/driver/adapter actually used, and every failure line;
## tools/classroom_render_evidence.py re-measures the saved PNGs against the same limits.

const Harness = preload("res://tests/test_harness.gd")
const FaderScript = preload("res://scripts/world/camera_occluder_fader.gd")
const EXPECTED_OPACITY := 0.18
## A frame whose coarse brightness range is below this is blank (a fade panel, a cleared
## target, a driver that drew nothing) - the same rule capture_classroom_art.gd applies.
const BLANK_RANGE := 0.15

var _out := "res://build/classroom-evidence/wall-probe"
var _expect_renderer := ""
var _expect_driver := ""
var _failures: Array[String] = []
var _facts: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "classroom_wall_render_test.gd")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
		elif argument.begins_with("--expect-renderer="):
			_expect_renderer = argument.trim_prefix("--expect-renderer=")
		elif argument.begins_with("--expect-driver="):
			_expect_driver = argument.trim_prefix("--expect-driver=")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_check_renderer()
	if DisplayServer.get_name() == "headless":
		_failures.append("Pixel assertions require a window/real renderer, not --headless.")
		_write_result()
		Harness.finish(self, _failures, "")
		return
	var reference := _fixture(false)
	var faded := _fixture(true)
	for _index in 35:
		await physics_frame
	await RenderingServer.frame_post_draw
	var reference_image := reference.get_texture().get_image()
	var faded_image := faded.get_texture().get_image()
	var expected := _centre_mean(reference_image)
	var actual := _centre_mean(faded_image)
	var error := absf(expected - actual)
	for pair: Array in [["reference", reference_image], ["fader", faded_image]]:
		var spread := _brightness_range(pair[1] as Image)
		_facts.append("%s_range=%.5f" % [pair[0], spread])
		if spread < BLANK_RANGE:
			_failures.append(
				(
					"The %s frame is blank (brightness range %.5f), not a rendered wall."
					% [pair[0], spread]
				)
			)
	if expected < 0.1 or expected > 0.7:
		_failures.append("The opacity control is not a usable rendered frame (%.5f)." % expected)
	if error > 0.025:
		(
			_failures
			. append(
				(
					"The real fader wall differs from 18%% opacity control by %.5f (reference %.5f, actual %.5f)."
					% [error, expected, actual]
				)
			)
		)
	var mesh := faded.get_node("Fixture/Wall/Mesh") as MeshInstance3D
	if absf(mesh.transparency - (1.0 - EXPECTED_OPACITY)) > 0.001:
		_failures.append("The real fader never reached its requested fade.")
	if (
		(
			reference_image.save_png(
				ProjectSettings.globalize_path(_out.path_join("reference.png"))
			)
			!= OK
		)
		or faded_image.save_png(ProjectSettings.globalize_path(_out.path_join("fader.png"))) != OK
	):
		_failures.append("Could not write pixel-regression evidence.")
	var material := mesh.material_override as BaseMaterial3D
	var line := (
		"renderer=%s reference=%.5f actual=%.5f error=%.5f instance_transparency=%.4f material_alpha=%.4f material_mode=%d"
		% [
			RenderingServer.get_current_rendering_method(),
			expected,
			actual,
			error,
			mesh.transparency,
			material.albedo_color.a,
			material.transparency,
		]
	)
	print("CLASSROOM_WALL_PIXELS " + line)
	_facts.append(line)
	_facts.append("reference=%.5f" % expected)
	_facts.append("actual=%.5f" % actual)
	_facts.append("error=%.5f" % error)
	_write_result()
	reference.queue_free()
	faded.queue_free()
	await process_frame
	await process_frame
	Harness.finish(self, _failures, "the real wall fade matches the single-alpha opacity control.")


## Fails unless the renderer and driver actually running are the ones this run was asked
## to measure. Never switches renderer itself; it only reports what Godot started.
func _check_renderer() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var driver := _driver_name()
	print(
		(
			"CLASSROOM_WALL_RENDERER method=%s driver=%s display=%s adapter=%s"
			% [method, driver, DisplayServer.get_name(), RenderingServer.get_video_adapter_name()]
		)
	)
	if _expect_renderer.is_empty() or _expect_driver.is_empty():
		_failures.append(
			"No --expect-renderer/--expect-driver given; a pixel verdict must name its renderer."
		)
	if not _expect_renderer.is_empty() and method != _expect_renderer:
		_failures.append(
			(
				"The renderer is '%s', not the expected '%s' (Godot may have fallen back)."
				% [method, _expect_renderer]
			)
		)
	if not _expect_driver.is_empty() and driver != _expect_driver:
		_failures.append(
			"The rendering driver is '%s', not the expected '%s'." % [driver, _expect_driver]
		)


func _driver_name() -> String:
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		return String(RenderingServer.call("get_current_rendering_driver_name"))
	return ""


## The evidence record, written once the verdict is known so it can carry it.
func _write_result() -> void:
	var path := ProjectSettings.globalize_path(_out.path_join("RESULT.txt"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write %s." % path)
		return
	file.store_line("engine=" + Engine.get_version_info().string)
	file.store_line("renderer=" + RenderingServer.get_current_rendering_method())
	file.store_line("driver=" + _driver_name())
	file.store_line("expected_renderer=" + _expect_renderer)
	file.store_line("expected_driver=" + _expect_driver)
	file.store_line("display=" + DisplayServer.get_name())
	file.store_line("adapter=" + RenderingServer.get_video_adapter_name())
	file.store_line("adapter_vendor=" + RenderingServer.get_video_adapter_vendor())
	file.store_line("adapter_api=" + RenderingServer.get_video_adapter_api_version())
	for fact in _facts:
		file.store_line(fact)
	for failure in _failures:
		file.store_line("failure=" + failure)
	file.store_line("verdict=" + ("PASS" if _failures.is_empty() else "FAIL"))
	file.close()


func _fixture(use_fader: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Faded" if use_fader else "Reference"
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fixture := Node3D.new()
	fixture.name = "Fixture"
	viewport.add_child(fixture)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	fixture.add_child(world_environment)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0.0, 1.1, 4.0)
	fixture.add_child(camera)
	camera.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
	camera.current = true
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.position = Vector3(0.0, 1.1, 2.0)
	if use_fader:
		wall.add_to_group("camera_occluder")
	fixture.add_child(wall)
	var box := BoxMesh.new()
	box.size = Vector3(2.8, 2.8, 0.1)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	if not use_fader:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = EXPECTED_OPACITY
	mesh.material_override = material
	wall.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	wall.add_child(collision)
	if use_fader:
		var fader := FaderScript.new() as CameraOccluderFader
		fader.name = "Fader"
		fader.faded_transparency = 1.0 - EXPECTED_OPACITY
		camera.add_child(fader)
	return viewport


func _centre_mean(image: Image) -> float:
	if image == null or image.is_empty():
		_failures.append("The viewport did not produce an image.")
		return -1.0
	var value := 0.0
	for y in range(112, 144):
		for x in range(112, 144):
			value += image.get_pixel(x, y).r
	return value / 1024.0


## Brightness spread of a coarse 32 x 32 resample: low means one flat colour.
func _brightness_range(image: Image) -> float:
	if image == null or image.is_empty():
		return 0.0
	var sample := image.duplicate() as Image
	sample.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var lowest := 1.0
	var highest := 0.0
	for y in sample.get_height():
		for x in sample.get_width():
			var pixel := sample.get_pixel(x, y)
			var value := (pixel.r + pixel.g + pixel.b) / 3.0
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	return highest - lowest
