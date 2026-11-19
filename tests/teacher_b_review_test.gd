extends SceneTree
## Import the real GLB, verify skinning, and sample the B-only library on its
## imported skeleton. With --capture, also render the isolated classroom stage.

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
	_check.expect(stage.motion.current_animation == &"teacher_b/idle", "running the dev scene opens on B's moving idle")
	stage.motion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	stage.show_shot("body")
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
	if _check.failures.is_empty():
		_check_b_motion(stage, parts)
	stage.show_shot("body")
	if "--capture" in OS.get_cmdline_user_args():
		if _check.expect(DisplayServer.get_name() != "headless", "capture needs a rendered window"):
			await _capture(stage)
			if _check.failures.is_empty():
				await _capture_motion(stage)
	stage.queue_free()
	await process_frame
	Harness.finish(self, _check.failures, "Teacher B: real skin, native idle, short walk and explanation in the dev stage")


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
			var original := part.mesh.surface_get_material(surface) as BaseMaterial3D
			if not _check.expect(original != null and original.vertex_color_use_as_albedo, "%s retains vertex paint in the imported material" % part.name):
				continue
			var material := original.resource_name
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
	_check.expect(stage.look.get_report()["replaced"] == 12, "opaque pieces keep their vertex paint; the transparent lenses stay separate")
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


func _sample_motion(stage: Stage, time: float) -> void:
	stage.motion.seek(time, true, true)
	stage.skeleton.force_update_all_bone_transforms()


func _check_b_motion(stage: Stage, parts: Array[Dictionary]) -> void:
	var player := stage.motion
	var skeleton := stage.skeleton
	_check.expect(player.get_node_or_null(player.root_node) == skeleton, "the B library binds directly to the imported skeleton")
	_check.expect(player.get_animation_list() == PackedStringArray(["teacher_b/explain", "teacher_b/idle", "teacher_b/walk"]), "the dev controls play only the three B-authored clips")
	var reset_paths: Dictionary = {}
	for name in Stage.CLIPS:
		var animation := player.get_animation("teacher_b/" + name)
		if not _check.expect(animation != null, "native animation %s exists" % name):
			return
		_check.expect(animation.loop_mode == (Animation.LOOP_LINEAR if name == "idle" else Animation.LOOP_NONE), "%s has the intended loop/one-shot setting" % name)
		var paths := {}
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var bone := path.get_concatenated_subnames()
			_check.expect(String(path.get_concatenated_names()) == "." and skeleton.find_bone(bone) >= 0, "%s track resolves to %s" % [name, path])
			paths[path] = true
		if reset_paths.is_empty():
			reset_paths = paths
		_check.expect(paths == reset_paths, "all clips write the same set of joints, including hands and Root")
		_check.expect(paths.has(^".:Root") and paths.has(^".:Middle02_L"), "root travel and individual fingers are keyed")

	var root_joint := skeleton.find_bone("Root")
	var head := skeleton.find_bone("Head")
	var hand := skeleton.find_bone("Hand_L")
	var finger := skeleton.find_bone("Middle02_L")
	_check.expect(stage.play_motion("idle"), "the idle button plays B's own animation")
	_sample_motion(stage, 0.0)
	var idle_root := skeleton.get_bone_pose_position(root_joint)
	var idle_head := skeleton.get_bone_pose_rotation(head)
	var hand_rest := skeleton.get_bone_global_pose(hand).origin
	var relaxed_finger := skeleton.get_bone_pose_rotation(finger)
	_sample_motion(stage, 1.8)
	_check.expect(idle_head.angle_to(skeleton.get_bone_pose_rotation(head)) > deg_to_rad(2.0), "B's idle includes her own look up from the floor")
	_sample_motion(stage, player.current_animation_length)
	_check.expect(idle_head.angle_to(skeleton.get_bone_pose_rotation(head)) < .001 and idle_root.distance_to(skeleton.get_bone_pose_position(root_joint)) < .0003, "idle returns to the same pose at the loop seam")
	var soles := _shoe_probes(parts)
	if not _check.expect(soles.size() == 2, "tests found both real outsole vertex sets"):
		return
	_check.expect(stage.play_motion("walk"), "B's walk starts in its wide, side-on view")
	_check.expect(stage.shot == "walk", "walk inspection fits the whole path")
	var walk := _check_walk(stage, soles, root_joint)
	stage.play_motion("explain")
	_sample_motion(stage, 1.22)
	var hand_range := skeleton.get_bone_global_pose(hand).origin.distance_to(hand_rest)
	var finger_range := rad_to_deg(relaxed_finger.angle_to(skeleton.get_bone_pose_rotation(finger)))
	_check.expect(hand_range > .29 and finger_range > 17.0, "the explanation lifts the left hand and curls its middle finger separately")
	_check.expect(idle_root.distance_to(skeleton.get_bone_pose_position(root_joint)) < .02, "switching from the last walk key to explanation drops travel")
	var standing_drift := 0.0
	for part in soles:
		standing_drift = maxf(standing_drift, _planted_drift(stage, part, Vector2(0.0, 3.2)))
	_check.expect(standing_drift < .003, "both shoes stay planted during the explanation")
	_check.expect(skeleton.get_bone_global_pose(hand).origin.distance_to(hand_rest) < .002 and relaxed_finger.angle_to(skeleton.get_bone_pose_rotation(finger)) < .002, "the gesture returns to the relaxed hand before it ends")
	stage.show_shot("game", true)
	_check.expect(stage.is_lead and not player.is_playing(), "Tab comparison can end B's playback and reveal the lead")
	stage.play_motion("idle")
	_check.expect(not stage.is_lead and stage.game_camera.current, "a B clip plays in the game view without introducing story actors")
	_sample_motion(stage, 1.1)
	stage.pause_button.pressed.emit()
	var paused_at := player.current_animation_position
	player.advance(.5)
	_check.expect(not player.is_playing() and is_equal_approx(player.current_animation_position, paused_at), "pause keeps the same frame")
	stage.pause_button.pressed.emit()
	player.advance(.3)
	_check.expect(player.is_playing() and player.current_animation_position > paused_at, "continue starts from the paused frame")
	stage.restart_button.pressed.emit()
	_check.expect(player.is_playing() and player.current_animation_position < .01, "restart goes to the first key")
	print("::notice title=Teacher B original motion::walk %.3f m, shoe lift L/R %.3f/%.3f m, peak plant drift %.4f m; explanation hand %.3f m, curl %.1f deg, stance drift %.4f m" % [
		walk.x, walk.y, walk.z, walk.w, hand_range, finger_range, standing_drift])


func _shoe_probes(parts: Array[Dictionary]) -> Array[Dictionary]:
	var probes: Array[Dictionary] = []
	for part in parts:
		if part["material"] != "b_rubber_and_horn":
			continue
		var source: PackedVector3Array = part["points"]
		for side in [1.0, -1.0]:
			var points := PackedVector3Array()
			var indices := PackedInt32Array()
			var weights := PackedFloat32Array()
			for i in source.size():
				if source[i].x * side <= .05 or source[i].y >= .025:
					continue
				points.append(source[i])
				for j in 4:
					indices.append(part["indices"][i*4+j])
					weights.append(part["weights"][i*4+j])
			if not points.is_empty():
				probes.append({"points": points, "indices": indices, "weights": weights,
					"joints": part["joints"], "inverse": part["inverse"]})
	return probes


func _planted_drift(stage: Stage, probe: Dictionary, interval: Vector2) -> float:
	_sample_motion(stage, interval.x)
	var at_plant := _posed(probe, stage.skeleton)
	var samples := ceili((interval.y - interval.x) * 60.0)
	var drift := 0.0
	for frame in range(1, samples + 1):
		_sample_motion(stage, lerpf(interval.x, interval.y, float(frame) / samples))
		var current := _posed(probe, stage.skeleton)
		for i in current.size():
			drift = maxf(drift, current[i].distance_to(at_plant[i]))
	return drift


func _check_walk(stage: Stage, soles: Array[Dictionary], root_joint: int) -> Vector4:
	var swing_height := Vector2.ZERO
	var lowest := INF
	var length := stage.motion.current_animation_length
	var last_z := INF
	var travel := 0.0
	var monotone := true
	for frame in range(ceili(length * 60.0) + 1):
		_sample_motion(stage, minf(frame / 60.0, length))
		var z := stage.skeleton.get_bone_pose_position(root_joint).z
		if frame == 0:
			travel = z
		monotone = monotone and z <= last_z + .00001
		last_z = z
		for i in soles.size():
			var bottom := INF
			for v in _posed(soles[i], stage.skeleton):
				bottom = minf(bottom, v.y)
			lowest = minf(lowest, bottom)
			swing_height[i] = maxf(swing_height[i], bottom)
	travel -= last_z
	_check.expect(monotone and absf(travel - .90) < .002, "a finite four-step pass travels .90 m toward -Z without snapping back")
	_check.expect(lowest > -.003 and swing_height.x > .042 and swing_height.y > .042, "shoe geometry lifts on both sides and does not go below the floor")
	var stance := [
		[Vector2(0.0, .20), Vector2(.74, 1.44), Vector2(1.98, 2.90)],
		[Vector2(0.0, .82), Vector2(1.36, 2.06), Vector2(2.60, 2.90)],
	]
	var drift := 0.0
	for side in soles.size():
		for interval: Vector2 in stance[side]:
			drift = maxf(drift, _planted_drift(stage, soles[side], interval))
	_check.expect(drift < .004, "planted soles stay in place through all six contact windows (max %.4f m)" % drift)
	stage.motion.advance(.10)
	_check.expect(stage.clip_finished and not stage.motion.is_playing(), "the walk stops on its last key rather than teleporting to its start")
	return Vector4(travel, swing_height.x, swing_height.y, drift)


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


func _capture_motion(stage: Stage) -> void:
	var output := ProjectSettings.globalize_path("res://builds/teacher-b-review/motion")
	for name: String in Stage.CLIPS:
		stage.show_shot("body")
		stage.play_motion(name)
		var folder := output.path_join(name)
		DirAccess.make_dir_recursive_absolute(folder)
		var length := stage.motion.current_animation_length
		var saved := true
		var frames := ceili(length * 12.0)
		for i in frames:
			_sample_motion(stage, minf(i / 12.0, length))
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.resize(560, 360, Image.INTERPOLATE_LANCZOS)
			saved = (image.save_png(folder.path_join("%03d.png" % i)) == OK) and saved
		_check.expect(saved, "saved %d rendered frames of B's %s" % [frames, name])
