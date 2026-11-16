extends SceneTree
## Checks the character art review experiments (issue #188) before they are photographed.
## Development only; nothing here is part of the game.
##
##   xvfb-run godot --path . --rendering-driver opengl3 \
##     --script res://tests/character_art_review_test.gd
##
## Needs a real renderer (Xvfb + OpenGL), not `--headless`: the dummy renderer does not parse
## shaders, and the first check is that every parameter the review looks set is a uniform the
## review shaders actually declare (a typo would otherwise be silently ignored).
##
## 1. The six review looks load, every material is a ShaderMaterial on a review shader, and
##    every `shader_parameter/*` they set is a uniform of that shader (or of its next pass).
## 2. Each look, applied to the production wrapper, replaces every surface (nothing kept).
## 3. The pose overlay at intensity 0 leaves every bone exactly where the production clip put
##    it; at intensity 1 it moves the bones it is meant to (and only by plausible amounts):
##    the protagonist's shoulders up, hands nearer the body, fingers curled; Q's raised right
##    forearm lowered. Stopping after a walk starts the protagonist's hesitation.
## 4. Softening the hair moves vertices and lowers the hair's reach from the cranium.
## 5. Restoring gives back the shipped look and the GLB hair.

const ReviewStage = preload("res://scenes/dev/character_art_review/review_stage.gd")
const PROTAGONIST := "res://scenes/environment/characters/protagonist.tscn"
const Q := "res://scenes/environment/characters/q.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_looks()
	var stage := Node3D.new()
	stage.name = "ReviewTestStage"
	root.add_child(stage)
	var protagonist := (load(PROTAGONIST) as PackedScene).instantiate() as CharacterVisualAnimation
	var q := (load(Q) as PackedScene).instantiate() as CharacterVisualAnimation
	stage.add_child(protagonist)
	stage.add_child(q)
	q.position = Vector3(1.0, 0.0, 0.0)
	for frame in 4:
		await process_frame
	if protagonist == null or q == null or protagonist.get_skeleton() == null or q.get_skeleton() == null:
		_failures.append("The production wrappers did not instance with skeletons.")
		_finish()
		return
	await _check_applied(protagonist, q)
	await _check_pose(protagonist, "protagonist_withdrawn")
	await _check_pose(q, "q_overfamiliar")
	await _check_hesitation(protagonist)
	_check_hair(protagonist)
	_check_restore(protagonist)
	_finish()


# --- 1. looks -------------------------------------------------------------------


func _check_looks() -> void:
	for id: String in ReviewStage.ORDER:
		if id == "c":
			continue
		for who: String in ["protagonist", "q"]:
			var path := String(ReviewStage.DIRECTIONS[id][who])
			var look := load(path) as CharacterLook
			if look == null:
				_failures.append("%s is not a CharacterLook." % path)
				continue
			if look.materials.is_empty():
				_failures.append("%s has no materials." % path)
			for key: String in look.materials:
				var material := look.materials[key] as ShaderMaterial
				if material == null or material.shader == null:
					_failures.append("%s: %s is not a ShaderMaterial with a shader." % [path, key])
					continue
				if not material.shader.resource_path.begins_with(ReviewStage.HERE):
					_failures.append("%s: %s uses %s, not a review shader." % [path, key, material.shader.resource_path])
				_check_parameters(path, key, material)
				var outline := material.next_pass as ShaderMaterial
				if outline != null:
					_check_parameters(path, key + " (outline)", outline)
			print("look %s: %d materials checked" % [path, look.materials.size()])


func _check_parameters(path: String, key: String, material: ShaderMaterial) -> void:
	var declared := {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		declared[String(uniform["name"])] = true
	if declared.is_empty():
		_failures.append("%s: %s's shader declares no uniforms (did it compile?)." % [path, key])
		return
	# A parameter the shader does not declare is dropped on load without a word, so the
	# names are read back from the file: the material's own section, or the shared outline's.
	var outline := key.ends_with("(outline)")
	var section := "id=\"outline\"" if outline else "id=\"m_%s\"" % key.replace("/", "__")
	var text := FileAccess.get_file_as_string(path)
	var at := text.find(section)
	if at < 0:
		_failures.append("%s: no section %s for %s." % [path, section, key])
		return
	var end := text.find("[sub_resource", at + 1)
	if end < 0:
		end = text.find("[resource]", at)
	var named := 0
	for line in text.substr(at, end - at).split("\n"):
		if line.begins_with("shader_parameter/"):
			named += 1
			var uniform := line.get_slice(" = ", 0).trim_prefix("shader_parameter/")
			if not declared.has(uniform):
				_failures.append("%s: %s sets %s, which its shader does not declare." % [path, key, uniform])
	if named == 0:
		_failures.append("%s: %s sets no parameters." % [path, key])


# --- 2. applying ----------------------------------------------------------------


func _check_applied(protagonist: Node, q: Node) -> void:
	for id: String in ReviewStage.ORDER:
		var report := ReviewStage.apply(protagonist, q, id, true, true)
		for who: String in ["protagonist", "q"]:
			var look: Dictionary = report[who]
			if look.has("error"):
				_failures.append("%s on %s: %s" % [id, who, String(look["error"])])
				continue
			var kept: Array = look.get("kept", [])
			if not kept.is_empty():
				_failures.append("%s on %s kept GLB materials: %s" % [id, who, str(kept)])
			print("%s on %s: %d of %d surfaces replaced, %d outlined" % [
				id, who, int(look.get("replaced", 0)), int(look.get("surfaces", 0)),
				(look.get("outlined", []) as Array).size(),
			])
		await process_frame
	ReviewStage.restore(protagonist, "protagonist")
	ReviewStage.restore(q, "q")
	await process_frame


# --- 3. pose --------------------------------------------------------------------


func _check_pose(animator: CharacterVisualAnimation, profile: String) -> void:
	var skeleton := animator.get_skeleton()
	_hold(animator, "idle", 0.5)
	var production := await _poses(skeleton)
	var pose := ReviewStage.set_pose(animator, profile, 0.0)
	var at_zero := await _poses(skeleton)
	pose.set("active", false)
	var production_again := await _poses(skeleton)
	pose.set("active", true)
	# Some bones move a little between frames even with the clip paused (the protagonist's
	# IK targets drift by under a millimetre): what each bone does with no overlay at all is
	# the tolerance, and the overlay at intensity 0 must stay inside it.
	var worst := 0.0
	var worst_bone := ""
	var worst_noise := 0.0
	for index in production.size():
		var noise := _drift(production[index], production_again[index])
		var drift := minf(_drift(production[index], at_zero[index]), _drift(production_again[index], at_zero[index]))
		if drift - noise > worst:
			worst = drift - noise
			worst_bone = skeleton.get_bone_name(index)
			worst_noise = noise
	print("%s at intensity 0: largest excess over the clip's own frame-to-frame drift %.6f (%s)" % [profile, worst, worst_bone])
	if worst > 0.0005:
		_failures.append(
			"%s at intensity 0 moved %s by %.5f beyond its own drift of %.5f (should be the production pose)."
			% [profile, worst_bone, worst + worst_noise, worst_noise]
		)
	pose.set("intensity", 1.0)
	var posed := await _poses(skeleton)
	var applied: Dictionary = pose.call("get_last_applied")
	print("%s: %d bones turned: %s" % [profile, applied.size(), str(applied)])
	for bone: String in applied:
		if float(applied[bone]) > 60.0:
			_failures.append("%s turned %s by %.1f°, more than 60°." % [profile, bone, float(applied[bone])])
	if profile == "protagonist_withdrawn":
		for side: String in ["L", "R"]:
			var clavicle := skeleton.find_bone("Clavicle_" + side)
			var upper := skeleton.find_bone("UpperArm_" + side)
			var hand := skeleton.find_bone("Hand_" + side)
			var finger := skeleton.find_bone("Index_02_" + side)
			if clavicle < 0 or upper < 0 or hand < 0 or finger < 0:
				_failures.append("The protagonist's %s arm bones are not where expected." % side)
				continue
			var rise := (posed[upper] as Transform3D).origin.y - (production[upper] as Transform3D).origin.y
			if rise < 0.004:
				_failures.append("The protagonist's %s shoulder rose only %.3f m." % [side, rise])
			var out_before := absf((production[hand] as Transform3D).origin.x)
			var out_after := absf((posed[hand] as Transform3D).origin.x)
			if out_after > out_before - 0.03:
				_failures.append("The protagonist's %s hand came in only %.3f m (%.3f -> %.3f)." % [side, out_before - out_after, out_before, out_after])
			var curl := rad_to_deg((production[finger] as Transform3D).basis.get_rotation_quaternion().angle_to(
				(posed[finger] as Transform3D).basis.get_rotation_quaternion()
			))
			if curl < 20.0:
				_failures.append("The protagonist's %s fingers curled only %.1f°." % [side, curl])
			print("protagonist %s: shoulder +%.3f m, hand %.3f -> %.3f m from the midline, index finger %.1f°" % [side, rise, out_before, out_after, curl])
	else:
		var hand := skeleton.find_bone("Hand.R")
		if hand < 0:
			_failures.append("Q has no Hand.R.")
		else:
			var before := (production[hand] as Transform3D).origin
			var after := (posed[hand] as Transform3D).origin
			print("Q right hand: %s -> %s" % [str(before), str(after)])
			if after.y > before.y - 0.08:
				_failures.append("Q's raised right hand came down only %.3f m." % (before.y - after.y))
	ReviewStage.set_pose(animator, "", 0.0)
	_release(animator)
	await process_frame


func _check_hesitation(animator: CharacterVisualAnimation) -> void:
	var pose := ReviewStage.set_pose(animator, "protagonist_withdrawn", 1.0)
	animator.report_velocity(Vector3(0.0, 0.0, 1.1))
	await create_timer(0.8).timeout
	animator.report_velocity(Vector3.ZERO)
	await create_timer(0.3).timeout
	var left := float(pose.get("_hesitate_left"))
	print("hesitation after stopping: %.2f s left, state %s" % [left, animator.get_locomotion_state()])
	if left <= 0.0:
		_failures.append("Stopping after a walk did not start the protagonist's hesitation.")
	animator.clear_reported_velocity()
	ReviewStage.set_pose(animator, "", 0.0)
	await process_frame


func _drift(a: Transform3D, b: Transform3D) -> float:
	return a.origin.distance_to(b.origin) + a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())


func _hold(animator: CharacterVisualAnimation, clip: String, fraction: float) -> void:
	animator.set_process(false)
	var player := animator.get_animation_player()
	var full := "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip]
	player.play(full, 0.0)
	player.seek(player.get_animation(full).length * fraction, true)
	player.pause()


func _release(animator: CharacterVisualAnimation) -> void:
	animator.get_animation_player().play("%s/idle" % String(CharacterAnimation.LIBRARY_NAME), 0.0)
	animator.set_process(true)


## Every bone's final global pose (after the modifiers), read when the skeleton reports its
## final pose. A skeleton with nothing to update (a paused clip, no modifier) may not report,
## and then its pose is read directly: it is the clip's pose.
func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var captured: Array[Transform3D] = []
	var grab := func() -> void:
		captured.clear()
		for index in skeleton.get_bone_count():
			captured.append(skeleton.get_bone_global_pose(index))
	skeleton.skeleton_updated.connect(grab)
	for frame in 3:
		await process_frame
	skeleton.skeleton_updated.disconnect(grab)
	if captured.is_empty():
		grab.call()
	return captured


# --- 4-5. hair and restore ----------------------------------------------------------


func _check_hair(protagonist: Node) -> void:
	ReviewStage.apply_look(protagonist, "protagonist", "c")
	var hair := _hair(protagonist)
	if hair == null:
		_failures.append("The protagonist has no %s mesh." % ReviewStage.HAIR_MESH)
		return
	var before := _reach(hair.mesh)
	var moved := ReviewStage.wilt_hair(protagonist)
	var after := _reach(hair.mesh)
	print("hair: %d vertices moved, reach from the cranium %.3f -> %.3f m" % [moved, before, after])
	if moved < 100 or after > before - 0.02:
		_failures.append("Softening the hair moved %d vertices, reach %.3f -> %.3f m." % [moved, before, after])
	if hair.get_surface_override_material(0) == null:
		_failures.append("Softening the hair lost the look's material.")


func _check_restore(protagonist: Node) -> void:
	ReviewStage.restore(protagonist, "protagonist")
	var hair := _hair(protagonist)
	var applier := protagonist.get_node(^"Look") as CharacterLookApplier
	if applier.look.resource_path != String(ReviewStage.DIRECTIONS["c"]["protagonist"]):
		_failures.append("Restoring did not put the shipped look back.")
	if hair != null and hair.mesh.resource_name.ends_with("(review wilt)"):
		_failures.append("Restoring did not put the hair mesh back.")


func _hair(protagonist: Node) -> MeshInstance3D:
	for node in protagonist.find_children(ReviewStage.HAIR_MESH, "MeshInstance3D", true, false):
		return node as MeshInstance3D
	return null


func _reach(mesh: Mesh) -> float:
	var far := 0.0
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			far = maxf(far, vertex.distance_to(ReviewStage.HAIR_CENTER))
	return far


func _finish() -> void:
	for failure in _failures:
		print("FAILURE: %s" % failure)
	print("RESULT: %s" % ("FAILURE" if not _failures.is_empty() else "SUCCESS"))
	quit(1 if not _failures.is_empty() else 0)
