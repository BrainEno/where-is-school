extends SceneTree
## Exercises the imported model and clips, not the offline sculpt or studio images.

const Harness := preload("res://tests/test_harness.gd")
const Stage := preload("res://scenes/dev/classmates/classmates_review.gd")
const SCENE := preload("res://scenes/dev/classmates/classmates_review.tscn")
const OUT := "res://builds/classmates-review/godot"

var checks := Harness.Checker.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Harness.arm_watchdog(self, 120.0, "classmates_review_test.gd")
	var stage := SCENE.instantiate() as Stage
	root.add_child(stage)
	await process_frame
	checks.expect(stage.selection == Stage.LINEUP and not stage.reference_q.visible, "review opens on the three independent assets")
	for i in Stage.IDS.size():
		_verify_member(stage, i)
	stage.select_cast(Stage.COMPARE_Q)
	checks.expect(stage.reference_q.visible and stage.performers[1].visible and not stage.performers[0].visible and not stage.performers[2].visible, "comparison uses the current Q wrapper beside the friend")
	if checks.failures.is_empty() and "--capture" in OS.get_cmdline_user_args():
		if checks.expect(DisplayServer.get_name() != "headless", "a real renderer is required for capture"):
			await _capture(stage)
	stage.queue_free()
	await process_frame
	Harness.finish(self, checks.failures, "Three classmates: imported paint, 57-joint rigs, independently authored gestures")


func _verify_member(stage: Stage, i: int) -> void:
	stage.select_cast(i)
	var label := String(Stage.IDS[i])
	var skeleton := stage.rig(i)
	var player := stage.player(i)
	if not checks.expect(skeleton != null and player != null, label + " imported a skeleton and native animation player"):
		return
	checks.expect(skeleton.get_bone_count() == 57, label + " retains 57 bones")
	var semantic := CharacterAnimation.resolve_rig(skeleton, true, true)
	checks.expect(semantic["missing"].is_empty(), "%s resolves the shared bone semantics (%s)" % [label, semantic["missing"]])
	var face: MeshInstance3D = null
	var soles := 0
	var surface_count := 0
	var painted := 0
	var optics := 0
	for node in stage.performers[i].find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not checks.expect(part.skin != null and part.get_node_or_null(part.skeleton) == skeleton, "%s binds %s to the imported skin" % [label, part.name]):
			continue
		checks.expect(part.skin.get_bind_count() == 57, label + " retains every inverse bind")
		if part.get_blend_shape_count() > 0:
			face = part
		for surface in part.mesh.get_surface_count():
			surface_count += 1
			var material := part.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb:
				painted += 1
			if material != null and material.resource_name == "optics":
				optics += 1
				checks.expect(material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, label + " retains a clear lens surface")
			if material != null and material.resource_name == "shoe_sole":
				soles += 1
				checks.expect(absf(part.mesh.get_aabb().position.y) < 0.001, label + " shoe sole remains on ground in bind pose")
			var arrays := part.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if not checks.expect(points.size() == colors.size() and weights.size() == 4 * points.size() and joints.size() == weights.size(), label + " keeps paint and four stored influences on " + String(part.name)):
				continue
			var invalid := 0
			for n in points.size():
				var total := 0.0
				for j in range(4 * n, 4 * n + 4):
					total += weights[j]
					if weights[j] < 0.0 or joints[j] < 0 or joints[j] >= part.skin.get_bind_count():
						invalid += 1
				if absf(total - 1.0) > 0.001 or not points[n].is_finite():
					invalid += 1
			checks.expect(invalid == 0, label + " has normalized, finite skin data on " + String(part.name))
	checks.expect(surface_count == [12, 13, 12][i] and painted == surface_count and soles == 1 and optics == (0 if i == 2 else 1), "%s imported %d painted surfaces; soles and optics kept" % [label, painted])
	checks.expect(face != null and face.get_blend_shape_count() == 4, label + " keeps four independent facial controls")
	var look := stage.performers[i].get_node(^"Look") as CharacterLookApplier
	checks.expect(look != null and int(look.get_report().get("replaced", 0)) >= 5, label + " uses the existing painterly treatment in this stage")
	for clip in [&"idle", &"walk_in_place", Stage.GESTURES[i]]:
		if not checks.expect(player.has_animation(clip), "%s has the %s native clip" % [label, clip]):
			return
		var animation := player.get_animation(clip)
		checks.expect(animation.length > 1.0 and animation.loop_mode == (Animation.LOOP_NONE if clip == Stage.GESTURES[i] else Animation.LOOP_LINEAR), "%s/%s duration and loop mode" % [label, clip])
	for name in [&"Foot_L", &"Hand_L", &"Hand_R", &"Head", &"Middle02_L"]:
		if not checks.expect(skeleton.find_bone(name) >= 0, "%s has %s" % [label, name]):
			return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var hand := skeleton.find_bone(&"Hand_L" if i == 1 else &"Hand_R")
	var head := skeleton.find_bone(&"Head")
	var foot := skeleton.find_bone(&"Foot_L")
	stage.play_clip(Stage.GESTURES[i])
	var start := skeleton.get_bone_global_pose(hand).origin
	var rest_head := skeleton.get_bone_pose_rotation(head)
	player.seek(Stage.BEATS[i], true, true)
	skeleton.force_update_all_bone_transforms()
	var moved := start.distance_to(skeleton.get_bone_global_pose(hand).origin)
	var turned := rad_to_deg(rest_head.angle_to(skeleton.get_bone_pose_rotation(head)))
	checks.expect(moved > [0.23, 0.31, 0.05][i] and turned > [4.0, 2.0, 10.0][i], "%s signature moved hand %.3f m, head %.1f deg" % [label, moved, turned])
	if i == 1 and face != null:
		var smile := face.find_blend_shape_by_name(&"SoftSmile")
		checks.expect(smile >= 0 and face.get_blend_shape_value(smile) > 0.25, "friend opens his hand with a separately keyed smile")
	stage.play_clip(&"walk_in_place")
	var before := skeleton.get_bone_global_pose(foot).origin
	player.seek(0.45, true, true)
	skeleton.force_update_all_bone_transforms()
	var step := before.distance_to(skeleton.get_bone_global_pose(foot).origin)
	checks.expect(step > 0.24, "%s walk moves the foot %.3f m" % [label, step])
	print("::notice title=Classmate imported action::%s: %d painted surfaces, gesture %.3f m / %.1f deg, walk foot %.3f m" % [label, painted, moved, turned, step])
	stage.bind(i)


func _save(stage: Stage, leaf: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := stage.get_viewport().get_texture().get_image()
	checks.expect(not img.is_empty() and img.save_png(OUT.path_join(leaf + ".png")) == OK, "rendered frame " + leaf)


func _capture(stage: Stage) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage.select_cast(Stage.LINEUP)
	await _save(stage, "00_lineup")
	stage.select_cast(Stage.COMPARE_Q)
	stage.set_view(15.0)
	await _save(stage, "01_friend_and_current_q")
	stage.hud.visible = false
	for i in Stage.IDS.size():
		stage.select_cast(i)
		stage.set_view(33.0, true)
		await _save(stage, "%s_face" % Stage.IDS[i])
		stage.set_view(26.0 if i == 1 else -27.0, false, true)
		if stage.play_clip(Stage.GESTURES[i]):
			stage.player(i).seek(Stage.BEATS[i], true, true)
			await _save(stage, "%s_%s" % [Stage.IDS[i], Stage.GESTURES[i]])
