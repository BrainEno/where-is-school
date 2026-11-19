extends SceneTree
## Headless: import the real GLB, verify rest and posed skin data, then bind the
## project's walk clip. With --capture, also render the isolated classroom stage.

const Harness := preload("res://tests/test_harness.gd")
const Stage := preload("res://scenes/dev/teacher_b/teacher_b_review.gd")
const REVIEW := preload("res://scenes/dev/teacher_b/teacher_b_review.tscn")
const OUT := "res://builds/teacher-b-review/classroom"

var _check := Harness.Checker.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Harness.arm_watchdog(self, 120.0, "teacher_b_review_test.gd")
	var stage := REVIEW.instantiate() as Stage
	root.add_child(stage)
	var skeleton := stage.skeleton
	if not _check.expect(skeleton != null, "B's GLB imported with a Skeleton3D"):
		Harness.finish(self, _check.failures, "Teacher B review")
		return
	var room := stage.get_node("Classroom")
	_check.expect(not room.has_node("Actors") and not room.has_node("Interactables"), "the stage did not add story actors or interactables")
	var anomalies := room.get_node_or_null(^"Anomalies")
	_check.expect(anomalies != null and anomalies.get_script() == null, "the curtain remains scenery and cannot wire story handlers")
	_check.expect(stage.lead.is_bound(), "the review uses the current protagonist wrapper")
	_check.expect(skeleton.get_bone_count() == 57, "57 deform joints imported")
	var bones := CharacterAnimation.resolve_rig(skeleton, true, true)
	_check.expect(bones["missing"].is_empty(), "all shared clip aliases resolve: %s" % [bones["missing"]])
	var parts := _surfaces(stage.teacher, skeleton)
	if not parts.is_empty():
		_check_skin(parts, stage)
	_check_animation(stage.teacher, skeleton)
	stage.show_shot("body")
	if "--capture" in OS.get_cmdline_user_args():
		if _check.expect(DisplayServer.get_name() != "headless", "capture needs a rendered window"):
			await _capture(stage)
	stage.queue_free()
	await process_frame
	Harness.finish(self, _check.failures, "Teacher B: imported, weighted and posed in the isolated review stage")


func _surfaces(teacher: Node3D, skeleton: Skeleton3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child in teacher.find_children("*", "MeshInstance3D", true, false):
		var part := child as MeshInstance3D
		if not _check.expect(part.skin != null and part.get_node_or_null(part.skeleton) == skeleton, "%s uses B's imported skin and skeleton" % part.name):
			continue
		var joints := PackedInt32Array()
		var inverse_binds: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var joint := skeleton.find_bone(part.skin.get_bind_name(bind))
			if part.skin.get_bind_name(bind).is_empty():
				joint = part.skin.get_bind_bone(bind)
			joints.append(joint)
			inverse_binds.append(part.skin.get_bind_pose(bind))
			_check.expect(joint >= 0 and joint < skeleton.get_bone_count(), "valid skin joint %d" % bind)
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if not _check.expect(not points.is_empty() and weights.size() == 4 * points.size() and indices.size() == weights.size() and colors.size() == points.size(), "%s retains positions, four weights and vertex paint" % part.name):
				continue
			var material := part.mesh.surface_get_material(surface).resource_name
			result.append({"points": points, "weights": weights, "indices": indices,
				"joints": joints, "inverse": inverse_binds, "material": material})
			var invalid := 0
			for vertex in points.size():
				var sum_weights := 0.0
				for i in 4:
					var index := 4 * vertex + i
					var w := weights[index]
					sum_weights += w
					if w < 0.0 or (w > 0.0 and (indices[index] < 0 or indices[index] >= joints.size())):
						invalid += 1
				if not is_finite(sum_weights) or absf(sum_weights - 1.0) > .001 or not points[vertex].is_finite():
					invalid += 1
			_check.expect(invalid == 0, "%s has normalized, in-range weights at every vertex" % part.name)
	_check.expect(result.size() == 13, "batching left thirteen skinned draw surfaces")
	return result


## CPU evaluation of Godot's imported skin, allowed in the headless renderer.
func _posed(part: Dictionary, skeleton: Skeleton3D) -> PackedVector3Array:
	var mats: Array[Transform3D] = []
	for bind in part["joints"].size():
		var joint: int = part["joints"][bind]
		mats.append(skeleton.get_bone_global_pose(joint) * part["inverse"][bind])
	var points: PackedVector3Array = part["points"]
	var weights: PackedFloat32Array = part["weights"]
	var indices: PackedInt32Array = part["indices"]
	var out := PackedVector3Array()
	out.resize(points.size())
	for vertex in points.size():
		var result := Vector3.ZERO
		for i in 4:
			var index := vertex * 4 + i
			if weights[index] > 0.0:
				result += (mats[indices[index]] * points[vertex]) * weights[index]
		out[vertex] = result
	return out


func _check_skin(parts: Array[Dictionary], stage: Stage) -> void:
	if not _check.failures.is_empty():
		return
	var skeleton := stage.skeleton
	var rest_error := 0.0
	var floor_y := INF
	var crown_y := -INF
	for part in parts:
		var baked := _posed(part, skeleton)
		var points: PackedVector3Array = part["points"]
		for i in baked.size():
			floor_y = minf(floor_y, baked[i].y)
			crown_y = maxf(crown_y, baked[i].y)
			rest_error = maxf(rest_error, baked[i].distance_to(points[i]))
	_check.expect(absf(floor_y) < .0005 and absf(crown_y - 1.64) < .0005 and rest_error < .0005, "1.640 m +Y, soles at zero and inverse binds agree with rest")
	var eye := skeleton.get_bone_global_rest(skeleton.find_bone("Eye_L")).origin
	var head := skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin
	var toe := skeleton.get_bone_global_rest(skeleton.find_bone("Toes_L")).origin
	var ankle := skeleton.get_bone_global_rest(skeleton.find_bone("Foot_L")).origin
	_check.expect(eye.z < head.z - .040 and toe.z < ankle.z - .09 and absf(ankle.z) < .001, "eyes/toes confirm -Z and the foot axis is centered")
	_check.expect(stage.look.get_report()["replaced"] == 6, "six painted surfaces use the opt-in finish; lenses and rims remain separate")
	var changes := {}
	var glasses_error := 0.0
	var head_index := skeleton.find_bone("Head")
	_check.expect(stage.apply_pose("demonstrate"), "demonstration pose applied")
	var head_motion := skeleton.get_bone_global_pose(head_index) * skeleton.get_bone_global_rest(head_index).affine_inverse()
	for part in parts:
		var label: String = part["material"]
		var baked := _posed(part, skeleton)
		var points: PackedVector3Array = part["points"]
		for i in baked.size():
			changes[label] = maxf(float(changes.get(label, 0.0)), baked[i].distance_to(points[i]))
			if label in ["b_tortoiseshell", "b_optical_glass", "b_swept_silver"]:
				glasses_error = maxf(glasses_error, baked[i].distance_to(head_motion * points[i]))
	_check.expect(float(changes.get("b_charcoal_wool", 0.0)) > .20 and float(changes.get("b_skin", 0.0)) > .28, "wool sleeves and bare hand vertices move when the elbow bends")
	_check.expect(float(changes.get("b_optical_glass", 0.0)) > .02 and glasses_error < .0005, "rim, lenses and hair stay rigidly attached to the turning head")
	var finger := skeleton.find_bone("Middle02_L")
	var flex := skeleton.get_bone_pose_rotation(finger).angle_to(skeleton.get_bone_rest(finger).basis.get_rotation_quaternion())
	_check.expect(rad_to_deg(flex) > 30.0, "a middle-finger joint has its own curl, not just wrist rotation")
	_check.expect(stage.apply_pose("stride"), "stride pose applied")
	var trouser_motion := 0.0
	var stride_floor := INF
	for part in parts:
		var baked := _posed(part, skeleton)
		var points: PackedVector3Array = part["points"]
		for i in baked.size():
			stride_floor = minf(stride_floor, baked[i].y)
			if part["material"] == "b_twill":
				trouser_motion = maxf(trouser_motion, baked[i].distance_to(points[i]))
	_check.expect(trouser_motion > .16 and absf(stride_floor - .01934) < .002, "a posed knee deforms trousers and the held stride has its measured ground offset")
	print("::notice title=Teacher B rig::57 bones; 13 surfaces; floor/crown %.5f / %.5f m; rest error %.6f m; peak wool/skin %.3f / %.3f m; rigid head pieces %.6f m; finger %.1f deg; stride trouser %.3f m; stride floor +%.5f m" % [
		floor_y, crown_y, rest_error, changes.get("b_charcoal_wool", 0.0), changes.get("b_skin", 0.0), glasses_error, rad_to_deg(flex), trouser_motion, stride_floor])
	stage.apply_pose("bind")


func _check_animation(teacher: Node3D, skeleton: Skeleton3D) -> void:
	var player := AnimationPlayer.new()
	teacher.add_child(player)
	var report := CharacterAnimation.bind(teacher, player, true)
	if _check.expect(bool(report.get("ok", false)) and report["missing"].is_empty(), "the project's existing clip library binds to B without an alias fork"):
		var ankle := skeleton.find_bone("Foot_L")
		var before := skeleton.get_bone_global_pose(ankle).origin
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_check.expect(CharacterAnimation.play(player, "walk"), "the bound walk starts")
		player.seek(.25, true, true)
		skeleton.force_update_all_bone_transforms()
		_check.expect(before.distance_to(skeleton.get_bone_global_pose(ankle).origin) > .04, "walk track changes the imported ankle pose")
	player.free()
	skeleton.reset_bone_poses()


func _capture(stage: Stage) -> void:
	var output := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(output)
	stage.get_node("Help").hide()
	for key in ["body", "face", "game", "back", "demonstrate", "stride"]:
		for lead in ([false, true] if key in ["body", "face", "game"] else [false]):
			stage.show_shot(key, lead)
			var subject: Node3D = stage.lead if lead else stage.teacher
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			subject.hide()
			await RenderingServer.frame_post_draw
			var room_only := root.get_texture().get_image()
			subject.show()
			var id := ("lead_" if lead else "b_") + String(key)
			var changed := 0
			for y in range(0, image.get_height(), 3):
				for x in range(0, image.get_width(), 3):
					var a := image.get_pixel(x, y)
					var b := room_only.get_pixel(x, y)
					if absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b) > .09:
						changed += 1
			_check.expect(changed > 120, "%s shows the subject rather than just the room (%d samples)" % [id, changed])
			_check.expect(image.save_png(output.path_join(id + ".png")) == OK, "saved %s" % id)
			print("%s: %dx%d; %d changed samples" % [id, image.get_width(), image.get_height(), changed])
