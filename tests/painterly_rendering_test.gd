extends SceneTree
## Painterly rendering — lab prototype (ADR 0004 painterly)
## Validates:
## - ADR 0004-painterly-rendering.md exists and evaluates route/camera/character
## - 5 shader files exist and compile (no parse error)
## - Preview scene loads, is independent of classroom, uses perspective baseline
## - Different material complexities are present and measurable
## - Prohibitions: project.godot and classroom not touched

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "painterly_rendering_test.gd")
	call_deferred("_run")

func _run() -> void:
	Harness.stage = "adr"
	_check_adr()
	Harness.stage = "shaders"
	_check_shaders()
	Harness.stage = "preview_scene"
	await _check_preview_scene()
	Harness.stage = "prohibitions"
	_check_prohibitions()
	Harness.stage = "performance"
	await _check_performance()
	Harness.finish(self, _failures, "painterly ADR, 5 shaders, lab scene at 3 complexities, perf guard, and prohibitions hold.")

# --- ADR ---

func _check_adr() -> void:
	var path := "res://docs/adr/0004-painterly-rendering.md"
	if not FileAccess.file_exists(path):
		_failures.append("ADR not found: %s" % path)
		return
	_expect_file_exists(path)
	var text := FileAccess.open(path, FileAccess.READ).get_as_text()
	# Required evaluations
	_expect(text.contains("Environment rendering route") or text.contains("Environment route") or text.contains("Material-only"), "ADR must evaluate environment rendering route (material vs screen vs hybrid).")
	_expect(text.contains("Camera") and (text.contains("perspective") or text.contains("Perspective")), "ADR must evaluate camera projection and state perspective baseline.")
	_expect(text.contains("Character") and (text.contains("character") or text.contains("Character shading")), "ADR must separately evaluate character shading.")
	_expect(text.contains("irregular") or text.contains("Irregular") or text.contains("color blocks"), "ADR must mention irregular color blocks / graphic planes.")
	_expect(text.contains("contour") or text.contains("outline") or text.contains("轮廓"), "ADR must mention hand-drawn contour / outline.")
	_expect(text.contains("brush") or text.contains("Brush") or text.contains("笔触"), "ADR must mention brushwork / paper texture.")
	_expect(text.contains("Performance") or text.contains("performance") or text.contains("Budget"), "ADR must record performance measurement or budget.")
	# Must state that classroom is untouched and perspective is baseline, not project setting change.
	_expect(text.contains("perspective") and text.contains("baseline") or text.contains("Perspective") and text.contains("baseline"), "ADR must state perspective baseline as per brief (保留透视相机作为基准).")
	_expect(text.contains("not modify") or text.contains("not modified") or text.contains("project.godot") or text.contains("classroom") or text.contains("Classroom"), "ADR should note prohibitions (no project.godot / classroom change).")
	# Date and status
	_expect(text.contains("Status:") or text.contains("Status："), "ADR must have Status field.")
	_expect(text.contains("2026"), "ADR must be dated.")

func _expect_file_exists(path: String) -> void:
	if not FileAccess.file_exists(path):
		_failures.append("Missing file: %s" % path)
	else:
		_checks += 1

# --- Shaders ---

func _check_shaders() -> void:
	var shaders := [
		"res://assets/shaders/painterly/painterly_env_simple.gdshader",
		"res://assets/shaders/painterly/painterly_env.gdshader",
		"res://assets/shaders/painterly/painterly_env_full.gdshader",
		"res://assets/shaders/painterly/painterly_character.gdshader",
		"res://assets/shaders/painterly/painterly_outline.gdshader",
	]
	for path in shaders:
		_expect_file_exists(path)
		if FileAccess.file_exists(path):
			var shader: Shader = load(path) as Shader
			if shader == null:
				_failures.append("Shader failed to load (parse error?): %s" % path)
			else:
				var code := shader.code
				if code.strip_edges().is_empty():
					_failures.append("Shader code empty: %s" % path)
				# Basic content checks
				if path.contains("painterly_env"):
					_expect(code.contains("poster") or code.contains("poster_levels") or code.contains("stepped"), "%s should contain posterization for color blocks." % path)
				if path.contains("_full"):
					_expect(code.contains("brush") or code.contains("paper"), "%s (full) should sample brush/paper texture." % path)
				if path.contains("character"):
					_expect(code.contains("wrap") or code.contains("hue") or code.contains("shadow_hue"), "%s should have separate character logic (wrap/hue shift), not sharing env effect." % path)
				if path.contains("outline"):
					_expect(code.contains("outline_width") and code.contains("NORMAL"), "%s outline should use inverted hull (NORMAL expansion)." % path)
				# Try to create a ShaderMaterial from it to ensure it compiles.
				var mat := ShaderMaterial.new()
				mat.shader = shader
				# If shader has compile error, Godot will push SCRIPT ERROR — but load would have already failed.
				_checks += 1

	var materials := [
		"res://assets/shaders/painterly/mat_env_simple.tres",
		"res://assets/shaders/painterly/mat_env_medium.tres",
		"res://assets/shaders/painterly/mat_env_full.tres",
		"res://assets/shaders/painterly/mat_character_skin.tres",
		"res://assets/shaders/painterly/mat_character_cloth.tres",
	]
	for mpath in materials:
		_expect_file_exists(mpath)
		if FileAccess.file_exists(mpath):
			var mat: Material = load(mpath) as Material
			if mat == null:
				_failures.append("Material failed to load: %s" % mpath)
			else:
				_checks += 1

	var readme := "res://assets/shaders/painterly/README.md"
	_expect_file_exists(readme)
	var tex := "res://assets/shaders/painterly/brush_paper.png"
	_expect_file_exists(tex)

# --- Preview scene ---

func _check_preview_scene() -> void:
	var scene_path := "res://scenes/dev/painterly_lab/painterly_lab.tscn"
	_expect_file_exists(scene_path)
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_failures.append("Lab scene failed to load as PackedScene: %s" % scene_path)
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		_failures.append("Lab scene could not be instantiated: %s" % scene_path)
		return
	add_child(instance)
	await process_frame
	await process_frame

	# Must be independent: root must not be LocationRoot, must not reference classroom scene.
	if instance is LocationRoot:
		_failures.append("Lab scene root must not be LocationRoot; it must be independent dev scene.")
	var script_path := instance.get_script()
	if script_path != null:
		# Ensure it has its own script, not opening_sequence
		var spath := String(script_path.resource_path)
		_expect(spath.contains("painterly_lab"), "Lab root script should be painterly_lab.gd, got %s" % spath)

	# Check required nodes exist
	_expect(instance.get_node_or_null("Camera3D") != null, "Lab must contain its own Camera3D (perspective baseline).")
	_expect(instance.get_node_or_null("Sun") != null, "Lab must contain a DirectionalLight for the painterly light.")
	_expect(instance.get_node_or_null("Ground") != null, "Lab must contain Ground.")
	_expect(instance.get_node_or_null("Props/PropSimple") != null, "Lab must contain PropSimple (simple complexity).")
	_expect(instance.get_node_or_null("Props/PropMedium") != null, "Lab must contain PropMedium (medium complexity).")
	_expect(instance.get_node_or_null("Props/PropFull") != null, "Lab must contain PropFull (full complexity).")
	_expect(instance.get_node_or_null("CharacterProxy") != null, "Lab must contain CharacterProxy for independent character shading evaluation.")
	_expect(instance.get_node_or_null("CharacterProxy/Body") != null, "CharacterProxy must have Body.")
	_expect(instance.get_node_or_null("CharacterProxy/Head") != null, "CharacterProxy must have Head.")

	# Camera must be perspective baseline, not orthographic, and FOV ~60
	var cam: Camera3D = instance.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		_expect(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "Lab camera must be perspective baseline (orthographic is only a local toggle, not default).")
		_expect(is_equal_approx(cam.fov, 60.0), "Lab camera baseline FOV must be 60.0 (same as CameraRig), got %f" % cam.fov)
		# Ensure it is not the Main CameraRig (which has offset etc); just check fov.

	# Check materials on props are ShaderMaterials with correct shaders (not StandardMaterial)
	for prop_name in ["Props/PropSimple", "Props/PropMedium", "Props/PropFull"]:
		var mi: MeshInstance3D = instance.get_node_or_null(prop_name) as MeshInstance3D
		if mi == null:
			continue
		var mat: Material = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		_expect(mat is ShaderMaterial, "%s must use ShaderMaterial (painterly), got %s" % [prop_name, mat])
		if mat is ShaderMaterial:
			var sm: ShaderMaterial = mat as ShaderMaterial
			_expect(sm.shader != null, "%s ShaderMaterial must have a shader." % prop_name)
			_expect(String(sm.shader.resource_path).contains("painterly_env"), "%s should use a painterly_env shader, got %s" % [prop_name, sm.shader.resource_path])

	# Character proxy must use painterly_character, not env shader
	for cname in ["CharacterProxy/Head", "CharacterProxy/Body"]:
		var cmi: MeshInstance3D = instance.get_node_or_null(cname) as MeshInstance3D
		if cmi == null:
			continue
		var cmat: Material = cmi.material_override
		_expect(cmat is ShaderMaterial, "%s must use ShaderMaterial (character)." % cname)
		if cmat is ShaderMaterial:
			var path := String((cmat as ShaderMaterial).shader.resource_path)
			_expect(path.contains("painterly_character"), "%s must use painterly_character.gdshader (separate evaluation), got %s" % [cname, path])

	# Verify lab is not using navigation (no NavigationRegion3D)
	_expect(instance.get_node_or_null("Navigation") == null and _find_navigation(instance) == null, "Lab must not contain NavigationRegion3D (it is not a playable location).")

	# Check lab script API exists
	if instance.has_method("get_shader_material_count"):
		var cnt: int = instance.get_shader_material_count()
		_expect(cnt >= 5, "Lab should have at least 5 ShaderMaterials (3 env complexities + 2 character), got %d" % cnt)
		_expect(cnt <= 32, "Lab ShaderMaterial count %d exceeds guard (32) — would break perf budget." % cnt)
	if instance.has_method("get_camera_mode"):
		_expect(String(instance.get_camera_mode()) == "perspective", "Lab camera mode must be perspective baseline, got %s" % instance.get_camera_mode())

	instance.queue_free()
	await process_frame

func _find_navigation(node: Node) -> Node:
	if node is NavigationRegion3D:
		return node
	for child in node.get_children():
		var found := _find_navigation(child)
		if found != null:
			return found
	return null

# --- Prohibitions ---

func _check_prohibitions() -> void:
	# Classroom must not be modified — it should still use StandardMaterial3D, not painterly shaders.
	var classroom_path := "res://scenes/locations/classroom/classroom.tscn"
	if FileAccess.file_exists(classroom_path):
		var text := FileAccess.open(classroom_path, FileAccess.READ).get_as_text()
		_expect(not text.contains("painterly"), "Classroom scene must not reference painterly shaders (task forbids modifying formal classroom).")
		_expect(text.contains("StandardMaterial3D") or text.contains("floor_concrete") or text.contains("wall_paint"), "Classroom should still use its StandardMaterial3D palette.")
	# project.godot must not be modified by this task's concerns (rendering method and window size)
	# We check that the file still declares Forward+ and 1600x900 design size, and does not contain painterly autoload.
	var pgodot_path := "res://project.godot"
	if FileAccess.file_exists(pgodot_path):
		var pgodot := FileAccess.open(pgodot_path, FileAccess.READ).get_as_text()
		_expect(pgodot.contains("forward_plus"), "project.godot must still use forward_plus (prohibited to modify).")
		_expect(pgodot.contains("viewport_width=1600") or pgodot.contains("viewport_width = 1600"), "project.godot window width must remain 1600 (prohibited to modify).")
		_expect(not pgodot.contains("painterly"), "project.godot must not contain painterly references (prohibited).")
		_expect(pgodot.contains("CameraRig") == false, "project.godot should not have been edited to add painterly camera; CameraRig stays in main.tscn.")
	# CameraRig script must be unchanged in its core contract (follow player, FOV single source)
	var camera_rig_path := "res://scripts/world/camera_rig.gd"
	if FileAccess.file_exists(camera_rig_path):
		var cr_text := FileAccess.open(camera_rig_path, FileAccess.READ).get_as_text()
		_expect(cr_text.contains("class_name CameraRig"), "CameraRig script must still exist (prohibited to refactor).")
		_expect(cr_text.contains("fov"), "CameraRig must still own FOV (prohibited to refactor).")
		_expect(not cr_text.contains("painterly"), "CameraRig must not have been refactored for painterly.")

# --- Performance ---

func _check_performance() -> void:
	# Measure different material complexities: instantiate each mat and time.
	var mat_paths := [
		"res://assets/shaders/painterly/mat_env_simple.tres",
		"res://assets/shaders/painterly/mat_env_medium.tres",
		"res://assets/shaders/painterly/mat_env_full.tres",
	]
	var times: Dictionary = {}
	for mpath in mat_paths:
		var start := Time.get_ticks_usec()
		var mat: Material = load(mpath)
		var elapsed := Time.get_ticks_usec() - start
		times[mpath] = elapsed
		_expect(mat != null, "Performance check: failed to load %s" % mpath)
		_expect(elapsed < 50000, "Material load %s took %d usec (should be < 50ms headless)." % [mpath, elapsed])

	# Lab scene load timing as proxy for complexity.
	var lab_path := "res://scenes/dev/painterly_lab/painterly_lab.tscn"
	var start_lab := Time.get_ticks_usec()
	var packed: PackedScene = load(lab_path) as PackedScene
	var lab_load_usec := Time.get_ticks_usec() - start_lab
	_expect(packed != null, "Lab scene must load for perf measurement.")
	_expect(lab_load_usec < 200000, "Lab scene load %d usec should be < 200ms headless." % lab_load_usec)

	# Instance timing
	if packed != null:
		var inst_start := Time.get_ticks_usec()
		var inst: Node = packed.instantiate()
		add_child(inst)
		await process_frame
		await process_frame
		var inst_usec := Time.get_ticks_usec() - inst_start
		_expect(inst_usec < 300000, "Lab instantiate %d usec should be < 300ms." % inst_usec)
		# Count ShaderMaterials as complexity metric
		var lab_script: Node = inst
		if lab_script.has_method("get_shader_material_count"):
			var cnt: int = lab_script.get_shader_material_count()
			_expect(cnt == 7 or cnt == 6 or cnt == 8, "Lab perf: expected ~7 ShaderMaterials (3 env + 2 character + ground), got %d" % cnt)
			print("::notice title=painterly perf::lab_materials=%d load=%dusec inst=%dusec simple=%dusec medium=%dusec full=%dusec" % [cnt, lab_load_usec, inst_usec, int(times[mat_paths[0]]), int(times[mat_paths[1]]), int(times[mat_paths[2]])])
		else:
			print("::notice title=painterly perf::load=%dusec materials measured" % lab_load_usec)
		inst.queue_free()
		await process_frame

	# Cross-resolution note (cannot measure GPU here, but verify viewport config exists)
	var disp_path := "res://project.godot"
	if FileAccess.file_exists(disp_path):
		var txt := FileAccess.open(disp_path, FileAccess.READ).get_as_text()
		_expect(txt.contains("1600") and txt.contains("900"), "project.godot must declare 1600x900 design size for resolution comparison.")

# --- helpers ---

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
	else:
		_checks += 1
