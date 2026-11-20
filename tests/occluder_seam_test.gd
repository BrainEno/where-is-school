extends SceneTree
## Hold the real fader on alternate sides of a seam, then leave both walls behind.

const Harness = preload("res://tests/test_harness.gd")


func _initialize() -> void:
	Harness.arm_watchdog(self, 12.0, "occluder_seam_test.gd")
	call_deferred("_run")


func _wall(x: float, material: StandardMaterial3D) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.position = Vector3(x, 1, 0)
	body.add_to_group("camera_occluder")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.99, 3, .20)
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	root.add_child(body)
	return visual


func _run() -> void:
	var check := Harness.Checker.new()
	var original := StandardMaterial3D.new()
	var west := _wall(-1, original)
	var east := _wall(1, original)
	var target := Node3D.new()
	target.name = "RayTarget"
	root.add_child(target)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(-.065, 2.4, 4)
	target.position = Vector3(-.065, 1, -3)
	var fader := CameraOccluderFader.new()
	fader.target_path = ^"../../RayTarget"
	fader.target_eye_height = 0.0
	fader.facing_reach = 0.0
	camera.add_child(fader)
	check.expect(await Harness.wait_until(func() -> bool: return west.transparency > .81, 2.0), "The first occluder never faded.")
	# Alternate easy, unambiguous ray hits a few centimetres either side of the joint.
	# On the old fader the west wall restores a step on every missed tick, while the
	# east wall repeatedly goes from opaque to one step faded and back to opaque.
	var worst_west := 1.0
	for i in 26:
		await physics_frame
		worst_west = minf(worst_west, west.transparency)
		var x := -.065 if i % 2 else .065
		camera.position.x = x
		target.position.x = x
	await physics_frame
	check.expect(worst_west > .81 and east.transparency > .81,
		"An alternating first blocker pulsed at the seam (minimum west %.3f, final east %.3f)." % [worst_west, east.transparency])
	print("occlusion at seam: west minimum %.3f, east settles at %.3f" % [worst_west, east.transparency])
	camera.position.x = 3.5
	target.position.x = 3.5
	check.expect(await Harness.wait_until(func() -> bool:
		return west.transparency == 0.0 and east.transparency == 0.0, .85), "The grace kept an old wall faded after the camera moved away.")
	check.expect(west.material_override == original and east.material_override == original,
		"Cleared blockers did not get back their exact authored material.")
	Harness.finish(self, check.failures, "alternating blockers stay stable at the seam and restore after clearing it.")
