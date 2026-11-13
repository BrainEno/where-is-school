extends SceneTree
## A pixel regression for the classroom's shared fader dependency.
## Run with a real renderer, both --rendering-method forward_plus and gl_compatibility.
## A fader-driven white wall must match a control wall at the same 18% opacity.
## The old Forward+ path multiplies 18% material alpha by 18% instance opacity.
## A headless run explicitly fails rather than pretending to have checked pixels.

const Harness = preload("res://tests/test_harness.gd")
const FaderScript = preload("res://scripts/world/camera_occluder_fader.gd")
const EXPECTED_OPACITY := 0.18

var _out := "res://build/classroom-evidence/wall-probe"
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "classroom_wall_render_test.gd")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		Harness.finish(
			self, ["Pixel assertions require a window/real renderer, not --headless."], ""
		)
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
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
	var log_file := FileAccess.open(_out.path_join("RESULT.txt"), FileAccess.WRITE)
	if log_file != null:
		log_file.store_line("engine=" + Engine.get_version_info().string)
		log_file.store_line("adapter=" + RenderingServer.get_video_adapter_name())
		log_file.store_line(line)
		log_file.close()
	reference.queue_free()
	faded.queue_free()
	await process_frame
	await process_frame
	Harness.finish(self, _failures, "the real wall fade matches the single-alpha opacity control.")


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
