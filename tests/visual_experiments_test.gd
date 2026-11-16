extends SceneTree
## Checks the standalone visual experiments lab (`scenes/dev/visual_experiments/`).
##
## Run under a real renderer so the four experiment shaders are actually parsed:
##
##   xvfb-run -a godot --resolution 1280x720 --rendering-driver opengl3 --path . \
##     --script res://tests/visual_experiments_test.gd
##
## (Under `--headless` the shader stage reports itself skipped; everything else runs.)
##
## What it holds the lab to:
##
## 1. **Shaders.** Each experiment shader loads and, under a real renderer, exposes the
##    uniforms the lab sets — a parse error leaves the list empty.
## 2. **It stays out of the game.** Both export presets exclude `scenes/dev/`; no production
##    scene, script or data file names the lab; the lab does not reach for the player
##    controller, camera rig, dialogue, locations or production shaders.
## 3. **Structure.** A visitor of its own (not the player), four zones, the switch.
## 3b. **Third person.** The visitor is the game's protagonist scene, animated by the
##    visitor's own body; the follow camera stands behind and above it and looks at it;
##    the character turns to face where it is going; WASD walks relative to the camera;
##    each room (and each narrow passage) has its own framing, the corridor's staying
##    under the beams; a free camera can take over and hands back; the corridor's loop
##    moves the camera with the character.
## 4. **A — collage.** Paper sheets in at least six patterns, four reprinted game textures,
##    flat and Y-billboard cut-outs with alpha-cut edges, a Decal, generated textures
##    within budget.
## 5. **B — corridor.** Doors that shrink monotonically along both walls, two MultiMeshes for
##    all of them, a doorway taller than the wall, a live window only while you are there,
##    and the loop: walk into the far door and arrive at the near end.
## 6. **C — staff room.** Vertex-colour fields, a shadowed spot outside the room, a ceiling
##    that casts shadow from both sides but is culled from above.
## 7. **D — the switch.** Crossing the threshold paints the view: root 3D off, SubViewport
##    on, camera copied, canvas shown, the tear completes. The stage is still solid while it
##    is painted (a body sweep stops at the back flat). Coming back restores 3D.
## 8. **Per-room environments**, a performance sample, and a clean teardown that leaves the
##    window rendering 3D even if the lab is freed while painted.

const Harness = preload("res://tests/test_harness.gd")
const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const LAB_SCENE := "res://scenes/dev/visual_experiments/visual_experiments.tscn"
const LAB_DIR := "res://scenes/dev/visual_experiments/"
const PAPER_SHADER := "res://scenes/dev/visual_experiments/shaders/paper_cutout.gdshader"
const FIELD_SHADER := "res://scenes/dev/visual_experiments/shaders/colour_field.gdshader"
const BACKDROP_SHADER := "res://scenes/dev/visual_experiments/shaders/painted_backdrop.gdshader"
const FILTER_SHADER := "res://scenes/dev/visual_experiments/shaders/painting_filter.gdshader"
const SHADER_UNIFORMS := {
	PAPER_SHADER: ["pattern", "paper_color", "source_texture", "tear_depth", "posterize_levels"],
	FIELD_SHADER: ["base_color", "terminator", "streak_strength"],
	BACKDROP_SHADER: ["vanishing_point", "far_half", "aspect"],
	FILTER_SHADER: ["reveal", "posterize_levels", "texel", "screen_aspect"],
}
const CAPTURE_SCRIPTS: Array[String] = [
	"res://tests/capture_visual_experiments.gd",
	"res://tests/capture_visual_experiments_walkthrough.gd",
]
## Production code the lab must not depend on.
const FORBIDDEN_IN_LAB: Array[String] = [
	"res://scripts/actors/player/",
	"res://scripts/world/camera_rig.gd",
	"res://scripts/dialogue/",
	"res://scenes/locations/",
	"res://scenes/main/",
	"res://assets/shaders/",
]
## Where a reference to the lab would mean it leaked into the game.
const PRODUCTION_ROOTS: Array[String] = [
	"res://scenes/", "res://scripts/", "res://data/", "res://assets/", "res://addons/"
]
const PROTAGONIST_SCENE := "res://scenes/environment/characters/protagonist.tscn"
const CAMERA_PATH := "Observer/CameraRig/Camera3D"
const STAGE_FEET := Vector3(40.0, 0.0, -40.0)
const CLASSROOM_FEET := Vector3(29.0, 0.0, -40.0)
## The corridor starts at z -12; its loop trigger is 42.6 m in.
const LOOP_FEET := Vector3(0.0, 0.0, -54.6)

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "visual_experiments_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "shaders"
	_check_shaders()
	Harness.stage = "release exclusion"
	_check_release_exclusion()
	Harness.stage = "isolation"
	_check_isolation()
	Harness.stage = "capture scripts"
	_check_capture_scripts()

	Harness.stage = "instantiate"
	var packed := ResourceLoader.load(LAB_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_failures.append("The visual experiments lab scene could not be loaded.")
		_finish("")
		return
	var lab: Node3D = packed.instantiate() as Node3D
	packed = null
	if lab == null:
		_failures.append("The visual experiments lab scene could not be instantiated.")
		_finish("")
		return
	root.add_child(lab)
	await _frames(3)

	Harness.stage = "structure"
	_check_structure(lab)
	Harness.stage = "third person"
	await _check_third_person(lab)
	Harness.stage = "collage"
	_check_collage(lab.get_node("Zones/Collage") as Node3D)
	Harness.stage = "corridor"
	await _check_corridor(lab)
	Harness.stage = "expression"
	_check_expression(lab.get_node("Zones/Expression") as Node3D)
	Harness.stage = "threshold"
	await _check_threshold(lab)
	Harness.stage = "environments"
	_check_environments(lab)
	Harness.stage = "performance"
	var sample: Dictionary = await lab.call("sample_performance", 5)
	for key: String in ["draw_calls", "primitives", "frame_ms", "video_mem_mib", "renderer"]:
		_expect(sample.has(key), "The performance sample has no '%s'." % key)
	print("VISUAL_LAB_TEST sample %s" % JSON.stringify(sample))

	Harness.stage = "teardown"
	# Free it while painted: the window must still render 3D afterwards.
	var switch := lab.get_node("MediumSwitch")
	switch.call("set_painted", true, true)
	_expect(root.disable_3d, "Forcing the medium switch did not stop root 3D rendering.")
	var lab_reference: WeakRef = weakref(lab)
	lab.queue_free()
	lab = null
	switch = null
	await _frames(3)
	_expect(lab_reference.get_ref() == null, "The lab survived queue_free().")
	_expect(not root.disable_3d, "Freeing the lab while painted left the window without 3D.")
	_finish("the visual experiments lab builds, switches medium, loops and tears down cleanly")


# --- Static checks ----------------------------------------------------------------------


func _check_shaders() -> void:
	var real_renderer := DisplayServer.get_name() != "headless"
	for path: String in SHADER_UNIFORMS:
		var shader := load(path) as Shader
		if shader == null:
			_failures.append("Experiment shader %s does not load." % path)
			continue
		if not real_renderer:
			continue
		var names: Array[String] = []
		for uniform: Dictionary in shader.get_shader_uniform_list():
			names.append(String(uniform.get("name", "")))
		for wanted: String in SHADER_UNIFORMS[path]:
			_expect(names.has(wanted), "%s does not expose '%s' (did it fail to parse?)." % [path, wanted])
	if not real_renderer:
		print("VISUAL_LAB_TEST shader uniforms skipped: no renderer under --headless")


func _check_release_exclusion() -> void:
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(not presets.is_empty(), "export_presets.cfg could not be read.")
	var filters := 0
	for line: String in presets.split("\n"):
		if line.begins_with("exclude_filter="):
			filters += 1
			_expect(line.contains("scenes/dev/*"), "An export preset does not exclude scenes/dev/*.")
	_expect(filters >= 2, "Expected an exclude_filter in each export preset, found %d." % filters)


func _check_isolation() -> void:
	for path: String in _files_under(LAB_DIR, ["gd", "tscn", "gdshader", "tres"]):
		var text := FileAccess.get_file_as_string(path)
		for forbidden: String in FORBIDDEN_IN_LAB:
			_expect(not text.contains(forbidden), "%s references production code %s." % [path, forbidden])
	for production_root: String in PRODUCTION_ROOTS:
		for path: String in _files_under(production_root, ["gd", "tscn", "tres", "json", "cfg"]):
			if path.begins_with("res://scenes/dev/"):
				continue
			var text := FileAccess.get_file_as_string(path)
			_expect(not text.contains("visual_experiments"), "%s references the visual lab." % path)
	_expect(
		not FileAccess.get_file_as_string("res://project.godot").contains("visual_experiments"),
		"project.godot references the visual lab."
	)


func _files_under(directory: String, extensions: Array) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	dir.include_hidden = false
	for file_name: String in dir.get_files():
		if extensions.has(file_name.get_extension()):
			found.append(directory.path_join(file_name))
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		found.append_array(_files_under(directory.path_join(sub), extensions))
	return found


func _check_capture_scripts() -> void:
	for path: String in CAPTURE_SCRIPTS:
		var script := load(path) as GDScript
		_expect(script != null and script.can_instantiate(), "Capture script %s does not compile." % path)


# --- The lab ----------------------------------------------------------------------------


func _check_structure(lab: Node3D) -> void:
	for node_path: String in [
		"Observer", CAMERA_PATH, "Observer/Visual/Character", "Zones/Collage", "Zones/Corridor",
		"Zones/Expression", "Zones/Threshold", "MediumSwitch", "WorldEnvironment", "HUD", "Ground",
	]:
		_expect(lab.get_node_or_null(node_path) != null, "The lab has no %s." % node_path)
	var observer := lab.get_node_or_null("Observer") as CharacterBody3D
	if observer != null:
		var script := observer.get_script() as Script
		_expect(
			script != null and script.resource_path.begins_with(LAB_DIR),
			"The lab's visitor is not its own (it must not be the game's player)."
		)
	var camera := lab.get_node_or_null(CAMERA_PATH) as Camera3D
	_expect(camera != null and camera.current, "The observer's camera is not current.")


func _check_third_person(lab: Node3D) -> void:
	var observer := lab.get_node("Observer") as CharacterBody3D
	var camera := lab.get_node(CAMERA_PATH) as Camera3D
	var character := lab.get_node_or_null("Observer/Visual/Character") as Node3D
	_expect(
		character != null and character.scene_file_path == PROTAGONIST_SCENE,
		"The visitor is not the game's protagonist scene."
	)
	if character == null:
		return
	_expect(bool(character.call("is_bound")), "The protagonist's animation did not bind.")
	# Its locomotion reads the visitor's body.
	observer.velocity = Vector3(2.0, 0.0, 0.0)
	var planar: Vector3 = character.call("get_planar_velocity")
	_expect(planar.is_equal_approx(Vector3(2.0, 0.0, 0.0)), "The protagonist does not animate from the visitor's body.")
	observer.velocity = Vector3.ZERO

	# Standing at the start: the camera is behind and above, looking at the character.
	_expect(bool(lab.call("go_to_station", &"start")), "There is no start station.")
	await _physics(2)
	var head := observer.global_position + Vector3(0.0, 1.1, 0.0)
	var to_head := head - camera.global_position
	_expect(camera.current, "The follow camera is not the current camera.")
	_expect(
		to_head.length() > 3.0,
		"The camera is %.1f m from the character; expected a third-person distance." % to_head.length()
	)
	_expect(camera.global_position.y > head.y + 1.0, "The follow camera is not above the character.")
	_expect(
		(-camera.global_basis.z).dot(to_head.normalized()) > 0.98,
		"The follow camera does not look at the character."
	)
	var facing: Vector3 = observer.call("facing")
	_expect(facing.dot(Vector3(0.0, 0.0, -1.0)) > 0.98, "The character does not face where it was placed to look.")
	var framing: Vector3 = observer.call("get_framing")
	_expect(
		framing == lab.call("framing_at", observer.global_position),
		"The start station is not in the room's framing."
	)

	# WASD walks relative to the camera: W goes where the camera looks.
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var before := observer.global_position
	_press(KEY_W, true)
	await _physics(12)
	_press(KEY_W, false)
	await _physics(2)
	var walked := observer.global_position - before
	walked.y = 0.0
	_expect(walked.length() > 0.3, "Holding W moved the character only %.2f m." % walked.length())
	if walked.length() > 0.0:
		_expect(walked.normalized().dot(forward) > 0.95, "W does not walk the way the camera looks.")
	facing = observer.call("facing")
	_expect(facing.dot(forward) > 0.8, "The character did not turn toward where it walked.")

	# Rooms ask for their own framing; the corridor's is a low chase under the beams.
	lab.call("go_to_station", &"corridor")
	await _physics(2)
	var corridor_framing: Vector3 = lab.call("framing_at", observer.global_position)
	_expect(observer.call("get_framing") == corridor_framing, "The corridor did not set its framing.")
	_expect(
		camera.global_position.y < float(lab.get_node("Zones/Corridor").call("wall_height")),
		"The corridor camera is above the corridor's walls (%.2f m)." % camera.global_position.y
	)
	_expect(camera.global_position.z > observer.global_position.z + 2.0, "The corridor camera is not behind the character.")
	var collage_framing: Vector3 = lab.call("framing_at", Vector3(0.0, 0.0, -6.0))
	var passage_framing: Vector3 = lab.call("framing_at", Vector3(5.0, 0.0, -40.0))
	_expect(collage_framing != corridor_framing, "The collage room and the corridor share a framing.")
	_expect(passage_framing.y < 30.0, "The passage into the staff room is not framed low along it.")

	# A free camera takes over and hands back.
	lab.call("look_from", Vector3(0.0, 20.0, 10.0), Vector3(0.0, 0.0, -20.0))
	await _physics(2)
	_expect(bool(observer.get("free_camera")), "look_from() did not free the camera.")
	_expect(camera.global_position.distance_to(Vector3(0.0, 20.0, 10.0)) < 0.05, "The free camera is not where it was put.")
	lab.call("go_to_station", &"start")
	await _physics(2)
	_expect(not bool(observer.get("free_camera")), "A station did not hand the camera back to the character.")


func _press(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _check_collage(collage: Node3D) -> void:
	var sheets: Array = collage.get("sheets")
	_expect(sheets.size() >= 40, "The collage room has %d paper sheets, expected 40+." % sheets.size())
	var patterns := {}
	for sheet: MeshInstance3D in sheets:
		var material := sheet.material_override as ShaderMaterial
		if material == null or material.shader == null or material.shader.resource_path != PAPER_SHADER:
			_failures.append("Sheet %s is not on the paper shader." % sheet.name)
			continue
		patterns[int(material.get_shader_parameter("pattern"))] = true
	_expect(patterns.size() >= 6, "Only %d paper patterns are in use, expected 6+." % patterns.size())
	var photos: Array = collage.get("photo_sheets")
	_expect(photos.size() == 4, "Expected 4 reprinted game textures, found %d." % photos.size())
	for photo: MeshInstance3D in photos:
		var material := photo.material_override as ShaderMaterial
		var texture: Texture2D = null
		if material != null:
			texture = material.get_shader_parameter("source_texture") as Texture2D
		_expect(
			texture != null and texture.resource_path.begins_with("res://assets/materials/"),
			"Reprint %s does not sample a game texture." % photo.name
		)
	var billboards := 0
	var flat_cut_outs := 0
	for sprite: Sprite3D in collage.get("cut_outs"):
		_expect(sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "%s is not alpha-cut." % sprite.name)
		if sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y:
			billboards += 1
		elif sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
			flat_cut_outs += 1
	_expect(billboards >= 3, "Expected 3+ Y-billboard figures, found %d." % billboards)
	_expect(flat_cut_outs >= 7, "Expected 7+ flat cut-out furniture sprites, found %d." % flat_cut_outs)
	var decal := collage.get("decal") as Decal
	_expect(decal != null and decal.texture_albedo != null, "The collage room has no textured Decal.")
	_expect(collage.get_node_or_null("Furniture/RealDesk") != null, "The real 3D desk is missing from the collage.")
	var generated := Kit.generated_bytes()
	_expect(
		generated > 0 and generated < 8 * 1024 * 1024,
		"Generated textures total %d bytes; expected between 0 and 8 MiB." % generated
	)


func _check_corridor(lab: Node3D) -> void:
	var corridor := lab.get_node("Zones/Corridor") as Node3D
	for side: String in ["west_door_heights", "east_door_heights"]:
		var heights: PackedFloat32Array = corridor.get(side)
		_expect(heights.size() >= 9, "%s has %d doors, expected 9+." % [side, heights.size()])
		for index in range(1, heights.size()):
			_expect(heights[index] < heights[index - 1], "%s does not shrink at door %d." % [side, index])
		if heights.size() > 1:
			_expect(heights[heights.size() - 1] / heights[0] < 0.35, "%s barely changes scale." % side)
	var total: int = (corridor.get("west_door_heights") as PackedFloat32Array).size()
	total += (corridor.get("east_door_heights") as PackedFloat32Array).size()
	var slabs := corridor.get("door_slabs") as MultiMeshInstance3D
	var frames := corridor.get("door_frames") as MultiMeshInstance3D
	_expect(slabs != null and slabs.multimesh.instance_count == total, "Door slabs are not one MultiMesh of every door.")
	_expect(frames != null and frames.multimesh.instance_count == total, "Door frames are not one MultiMesh of every door.")
	_expect(
		float(corridor.call("giant_door_height")) > float(corridor.call("wall_height")) * 1.5,
		"The giant door is not taller than the wall it is cut into."
	)
	var view := corridor.get("elsewhere_view") as SubViewport
	var window := corridor.get_node_or_null("WindowOntoElsewhere") as MeshInstance3D
	var window_material: ShaderMaterial = null
	if window != null:
		window_material = window.material_override as ShaderMaterial
	_expect(
		window_material != null and window_material.get_shader_parameter("source_texture") is ViewportTexture,
		"The corridor window does not show a ViewportTexture."
	)
	var observer := lab.get_node("Observer") as CharacterBody3D
	lab.call("observe", Vector3(0, 0, -20), Vector3(0, 1.4, -40))
	await _frames(2)
	_expect(lab.call("current_zone") == &"corridor", "Standing in the corridor does not report the corridor.")
	_expect(view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "The corridor window is not live in the corridor.")
	var loops_before := int(corridor.get("loop_count"))
	var teleports_before := int(observer.get("teleports"))
	lab.call("observe", LOOP_FEET, LOOP_FEET + Vector3(0, 1.4, -5))
	await _physics(8)
	_expect(int(corridor.get("loop_count")) == loops_before + 1, "Walking into the far door did not trigger the loop.")
	_expect(int(observer.get("teleports")) == teleports_before + 1, "The loop did not move the observer.")
	_expect(
		observer.global_position.z > -20.0 and observer.global_position.z < -12.0,
		"The loop left the observer at z %.2f, not at the corridor's near end." % observer.global_position.z
	)
	var loop_camera := lab.get_node(CAMERA_PATH) as Camera3D
	_expect(
		loop_camera.global_position.distance_to(observer.global_position) < 8.0,
		"The loop moved the character but left the camera %.1f m away."
		% loop_camera.global_position.distance_to(observer.global_position)
	)
	lab.call("go_to_station", &"start")
	await _frames(2)
	_expect(view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The corridor window keeps rendering after you leave.")


func _check_expression(expression: Node3D) -> void:
	var fields: Array = expression.get("fields")
	_expect(fields.size() >= 5, "The staff room has %d colour-field meshes, expected 5+." % fields.size())
	for field: MeshInstance3D in fields:
		var mesh := field.mesh as ArrayMesh
		_expect(
			mesh != null and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0,
			"%s has no vertex colours." % field.name
		)
		var material := field.material_override as ShaderMaterial
		_expect(
			material != null and material.shader.resource_path == FIELD_SHADER,
			"%s is not on the colour-field shader." % field.name
		)
	var floor_mesh := expression.get_node("Floor") as MeshInstance3D
	var colours: PackedColorArray = (floor_mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var distinct := {}
	for colour: Color in colours:
		distinct[colour.to_html()] = true
	_expect(distinct.size() >= 2, "The staff room floor is one colour; expected separate fields.")
	var spot := expression.get("spot") as SpotLight3D
	_expect(spot != null and spot.shadow_enabled, "The staff room's hard light casts no shadow.")
	_expect(spot != null and spot.position.x > 6.0, "The hard light is inside the room, not behind the slot.")
	var ceiling := expression.get("ceiling") as MeshInstance3D
	_expect(
		ceiling != null and ceiling.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
		"The staff room ceiling does not cast shadow from both sides."
	)
	var ceiling_material: BaseMaterial3D = null
	if ceiling != null:
		ceiling_material = ceiling.material_override as BaseMaterial3D
	_expect(
		ceiling_material != null and ceiling_material.cull_mode == BaseMaterial3D.CULL_BACK,
		"The staff room ceiling is not culled from above."
	)
	var chairs := 0
	for child: Node in expression.get_node("Table").get_children():
		if child.name.begins_with("Chair") or child.name == "TheChair":
			chairs += 1
	_expect(chairs == 13, "Expected twelve chairs and one, found %d." % chairs)


func _check_threshold(lab: Node3D) -> void:
	var threshold := lab.get_node("Zones/Threshold") as Node3D
	var switch := lab.get_node("MediumSwitch")
	var observer := lab.get_node("Observer") as CharacterBody3D
	var observer_camera := lab.get_node(CAMERA_PATH) as Camera3D
	var view := switch.call("get_view") as SubViewport
	var canvas := switch.call("get_canvas") as CanvasLayer
	var painted_camera := switch.call("get_painted_camera") as Camera3D
	_expect(not bool(switch.call("is_painted")), "The lab starts painted.")
	_expect(not root.disable_3d, "The lab starts with root 3D disabled.")
	_expect(not canvas.visible, "The painting canvas is visible before the threshold.")
	var filter := switch.call("get_filter_material") as ShaderMaterial
	_expect(filter != null and filter.shader.resource_path == FILTER_SHADER, "The switch does not use the painting filter.")

	lab.call("observe", CLASSROOM_FEET, Vector3(40, 1.4, -40))
	await _frames(2)
	var stage_window := threshold.get("stage_window") as SubViewport
	_expect(
		stage_window.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"The picture of the stage is not live in the classroom."
	)

	var switches_before := int(switch.call("get_switch_count"))
	lab.call("observe", STAGE_FEET, Vector3(48, 1.6, -40))
	await _physics(6)
	await _frames(2)
	_expect(bool(threshold.call("is_on_painted_side")), "Standing on the stage is not the painted side.")
	_expect(bool(switch.call("is_painted")), "Crossing the threshold did not switch the medium.")
	_expect(int(switch.call("get_switch_count")) == switches_before + 1, "The crossing switched more or less than once.")
	_expect(root.disable_3d, "Painted mode still renders 3D straight to the window.")
	_expect(canvas.visible, "Painted mode does not show the painting canvas.")
	_expect(view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Painted mode does not render the SubViewport.")
	_expect(
		painted_camera.global_position.distance_to(observer_camera.global_position) < 0.01,
		"The painted camera does not follow the observer."
	)
	_expect(view.size.x >= 64 and view.size.y >= 64, "The painted view has no size.")
	await create_timer(1.0).timeout
	_expect(is_equal_approx(float(switch.call("get_reveal")), 1.0), "The painting did not finish tearing in.")

	# Painted, and still solid: the observer's capsule, swept toward the back flat a hand
	# above the floor, stops at the flat.
	var space := lab.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = capsule
	sweep.transform = Transform3D(Basis.IDENTITY, STAGE_FEET + Vector3(0, 1.0, 0))
	sweep.motion = Vector3(12, 0, 0)
	sweep.exclude = [observer.get_rid()]
	var fractions := space.cast_motion(sweep)
	var hit_flat := false
	if fractions.size() == 2 and fractions[1] < 1.0:
		sweep.transform.origin += sweep.motion * fractions[1]
		sweep.motion = Vector3.ZERO
		var rest := space.get_rest_info(sweep)
		var collider := instance_from_id(int(rest.get("collider_id", 0))) as Node
		while collider != null and collider != lab:
			if collider.name == "BackFlat":
				hit_flat = true
				break
			collider = collider.get_parent()
	_expect(hit_flat, "In painted mode the observer's body passes through the back flat.")
	var query := PhysicsRayQueryParameters3D.create(Vector3(40, 1.6, -40), Vector3(53, 1.6, -40))
	query.exclude = [observer.get_rid()]
	var hit := space.intersect_ray(query)
	_expect(not hit.is_empty(), "A ray across the painted stage hits nothing.")

	lab.call("observe", CLASSROOM_FEET, Vector3(20, 1.4, -40))
	await _physics(6)
	_expect(not bool(threshold.call("is_on_painted_side")), "Leaving the stage still reads as the painted side.")
	_expect(not bool(switch.call("is_painted")), "Leaving the stage did not switch back.")
	await create_timer(1.0).timeout
	await _frames(2)
	_expect(not canvas.visible, "The painting canvas stays up after switching back.")
	_expect(not root.disable_3d, "Switching back did not restore root 3D rendering.")
	_expect(view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The painted SubViewport keeps rendering in 3D mode.")


func _check_environments(lab: Node3D) -> void:
	var world := lab.get_node("WorldEnvironment") as WorldEnvironment
	var seen := {}
	for station: Array in [
		[&"collage", &"collage"], [&"corridor", &"corridor"], [&"expression", &"expression"],
		[&"threshold", &"classroom"], [&"stage", &"stage"],
	]:
		_expect(bool(lab.call("go_to_station", station[0])), "Station %s is unknown." % station[0])
		var zone: StringName = lab.call("current_zone")
		_expect(zone == station[1], "Station %s is in zone %s, expected %s." % [station[0], zone, station[1]])
		var expected := lab.call("environment_for", zone) as Environment
		_expect(world.environment == expected and expected != null, "Zone %s did not get its own environment." % zone)
		seen[expected] = true
	_expect(seen.size() == 5, "Five rooms share %d environments; each should have its own." % seen.size())
	var corridor_environment := lab.call("environment_for", &"corridor") as Environment
	_expect(corridor_environment.fog_enabled, "The corridor has no fog to lose its far end in.")
	lab.call("go_to_station", &"start")


# --- Helpers ----------------------------------------------------------------------------


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics(count: int) -> void:
	for _index in count:
		await physics_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(success_message: String) -> void:
	var watchdog := root.get_node_or_null(^"TestWatchdog") as Timer
	if watchdog != null:
		watchdog.stop()
		watchdog.queue_free()
	Harness.finish(self, _failures, success_message)
