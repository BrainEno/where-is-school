extends SceneTree
## Dev-only geometry/input checks and optional captures from the running Godot viewport.
## Camera presets and all lighting are the same whether run with F6 or through this script.

const PREVIEW := preload("res://scenes/dev/folded_drum/preview.tscn")
const FRAMES := [
	"folded_drum_01_reference_angle",
	"folded_drum_02_roof_and_returns",
	"folded_drum_03_tubes_and_arcade",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_review")


func _review() -> void:
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			output = argument.trim_prefix("capture=")
	if not output.is_empty() and DisplayServer.get_name() == "headless":
		push_error("Folded Drum capture needs a window; omit --headless and use a display.")
		quit(1)
		return

	var scene := PREVIEW.instantiate()
	root.add_child(scene)
	var building: Node3D = scene.get_node("FoldedDrum")
	var aabb := _test_meshes(building)
	var screen: MeshInstance3D = building.get_node("ScreenWing/ScreenWallAndFoldedBays")
	_expect((screen.global_transform * screen.get_aabb()).end.z < 3.41,
		"the side return must stay behind the +Z facade's ribs")
	_check_tube(scene, "LongTube")
	_check_tube(scene, "ShortTube")
	var camera: Camera3D = scene.get_node("Camera3D")
	_test_camera(camera)

	if _failures.is_empty() and not output.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		_expect(error == OK, "cannot create screenshot directory: %s" % error_string(error))
		if error == OK:
			await _capture(scene, output)
	if _failures.is_empty():
		print("PASS: Folded Drum geometry %s; both tube interiors; orbit, zoom and reset%s" % [
			aabb.size, "; three viewport frames" if not output.is_empty() else "",
		])
	else:
		for failure: String in _failures:
			push_error("Folded Drum: " + failure)
	quit(0 if _failures.is_empty() else 1)


func _test_meshes(building: Node3D) -> AABB:
	var meshes := building.find_children("*", "MeshInstance3D", true, false)
	var bounds := AABB()
	var first := true
	_expect(meshes.size() >= 12, "expected separate site, roofs, tower, tubes and facade meshes")
	for child: Node in meshes:
		var part := child as MeshInstance3D
		_expect(part.mesh != null and part.mesh.get_surface_count() > 0, "%s has no mesh surfaces" % part.name)
		if part.mesh != null:
			var box := part.global_transform * part.get_aabb()
			_expect(box.is_finite() and box.has_volume(), "%s has an invalid 3D extent" % part.name)
			bounds = box if first else bounds.merge(box)
			first = false
	_expect(bounds.size.x >= 20.0 and bounds.size.y > 14.0 and bounds.size.z >= 20.0,
		"model should have a full footprint and height, got %s" % bounds.size)
	return bounds


func _check_tube(scene: Node, tube: String) -> void:
	var part := scene.get_node_or_null("FoldedDrum/FrontWing/%s/OpenCardboardBarrel" % tube) as MeshInstance3D
	if part == null or part.mesh == null:
		_expect(false, tube + " is missing")
		return
	var box := part.mesh.get_aabb()
	var vertices := part.mesh.get_faces()
	var open := true
	var has_rim := false
	var probe := box.size.x * 0.472
	var start := Vector3(0.0, box.end.y + 0.2, 0.0)
	var end := Vector3(0.0, box.position.y + 0.28, 0.0)
	for i: int in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		if Geometry3D.segment_intersects_triangle(start, end, a, b, c) != null:
			open = false
		if Geometry3D.segment_intersects_triangle(start + Vector3(probe, 0, 0.017),
				end + Vector3(probe, 0, 0.017), a, b, c) != null:
			has_rim = true
	_expect(open and has_rim and box.size.y > 4.0, tube + " must have a deep cavity and a real rim")


func _test_camera(camera: Camera3D) -> void:
	var start := camera.global_transform
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(94, 27)
	root.push_input(drag, true)
	_expect(camera.position.distance_to(start.origin) > 3.0, "mouse drag did not orbit")
	var before := camera.position
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel, true)
	_expect(camera.position.distance_to(before) > 1.0, "wheel did not zoom")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	root.push_input(key, true)
	_expect(camera.position.distance_to(start.origin) > 24.0, "rear preset did not change viewpoint")
	key = InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	root.push_input(key, true)
	_expect(camera.global_transform.is_equal_approx(start), "reset did not restore the hero view")


func _capture(scene: Node, output: String) -> void:
	for i: int in FRAMES.size():
		scene.call("show_view", i)
		# Wait for rendering after moving the camera, not for a guessed wall-clock delay.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			_expect(false, "viewport produced no image")
			return
		var size := image.get_size()
		var shades: Dictionary[Color, bool] = {}
		for y: int in range(int(size.y * 0.25), int(size.y * 0.75), 17):
			for x: int in range(int(size.x * 0.25), int(size.x * 0.75), 17):
				shades[image.get_pixel(x, y)] = true
		_expect(size == Vector2i(1600, 1000) and shades.size() > 100,
			"%s: expected a 1600x1000 drawn frame, got %s (%d sampled colours)" % [FRAMES[i], size, shades.size()])
		var file: String = FRAMES[i] + ".jpg"
		var error := image.save_jpg(output.path_join(file), 0.94)
		_expect(error == OK, "cannot save %s: %s" % [file, error_string(error)])
		if error == OK:
			print("EVIDENCE " + JSON.stringify({"frame": file, "size": [size.x, size.y], "shows": {
				"kind": "folded_drum", "view": FRAMES[i], "renderer": RenderingServer.get_current_rendering_method(),
			}}))


func _expect(condition: bool, problem: String) -> void:
	if not condition:
		_failures.append(problem)
