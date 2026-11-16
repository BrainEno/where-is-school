extends SceneTree
## Checks the biology classroom art experiment
## (`scenes/dev/visual_experiments/biology_classroom/`).
##
## Run under a real renderer so its shaders are parsed:
##
##   xvfb-run -a godot --resolution 1280x720 --rendering-driver opengl3 --path . \
##     --script res://tests/biology_classroom_experiment_test.gd
##
## (Under `--headless` the shader stage reports itself skipped; everything else runs.)
##
## What it holds the experiment to:
##
## 1. **Shaders** load and, under a real renderer, expose the uniforms the scene drives.
## 2. **It stays out of the game**: nothing in it reaches for the player controller, camera
##    rig, dialogue, locations or production shaders; nothing in the game names it.
## 3. **The set**: no low teacher's desk; a tall lectern at the window end of the front,
##    where the low desk stood, on the platform, with the set square, the register and the
##    chalk on its top; the board on the north wall, the curtain over the west opening, the
##    exit door in the east wall; the desks clear of the platform and of each other.
## 4. **Playable**: the protagonist starts seated, a movement key stands him up and walks
##    him; desks and walls stop a body; the front door stops a body shut and lets it
##    through open; the stairs and the yard door are reachable interactions.
## 5. **The registers**: in the lesson beat, near the lectern, the room chills, the shadow
##    climbs the wall, the lectern grows; away from it in the wake beat it does not.
## 6. **The curtain**: drawing it puts the picture on paper (root 3D off, SubViewport on)
##    and the red ring is drawn where the protagonist stands; the fall lands him in the
##    yard and brings the colour back.
## 7. **Q is a person**: every change of place is walked (no step longer than a stride);
##    he comes to the doorway when the protagonist goes out and stays on the classroom
##    side; he does not come to the fall's landing.
## 8. **The bell**: N walks in and stands on the platform beside the lectern, not at it.
## 9. **Closed**: every ordinary wall and the ceiling stop a body and a line of sight up to
##    the ceiling; the only way to see out is the curtained opening (and the open door).
## 10. **The projector** hangs from the ceiling in front of the board, aimed at a screen
##    over the board, its cable running to the lectern; it switches on and off.
## 11. **The class is cut paper**: one mesh per pupil, no board behind them, different
##    papers; one pupil stands at the back wall.
## 12. **The camera is fixed**: walking inside a zone does not move it at all (position,
##    angle, lens); it changes only with the zone or a story beat, and every place in a zone
##    is inside its shot's frame.
## 13. A performance sample, and a teardown that leaves the window rendering 3D even if the
##    scene is freed while the paper is down.

const Harness = preload("res://tests/test_harness.gd")

const SCENE := "res://scenes/dev/visual_experiments/biology_classroom/biology_classroom.tscn"
const DIR := "res://scenes/dev/visual_experiments/biology_classroom/"
const ROOM_SCRIPT := "res://scenes/dev/visual_experiments/biology_classroom/room.gd"
const SHADER_DIR := "res://scenes/dev/visual_experiments/biology_classroom/shaders/"
const SHADER_UNIFORMS := {
	"room_tone.gdshader": ["chill", "dull", "focus_point", "focus_amount", "terminator"],
	"ink_hull.gdshader": ["ink", "width"],
	"ink_mark.gdshader": ["mark", "tint", "amount", "opacity", "mode"],
	"blank_paper.gdshader": ["reveal", "origin", "texel", "screen_aspect"],
	"concrete.gdshader": ["base_color", "aggregate_density", "formwork", "ruled_lines", "chill", "focus_amount"],
	"cut_paper.gdshader": ["paper_sheet", "reverse_color", "grain", "chill", "focus_amount"],
}
const CAPTURE_SCRIPTS: Array[String] = ["res://tests/capture_biology_classroom.gd"]
const FORBIDDEN: Array[String] = [
	"res://scripts/actors/player/",
	"res://scripts/world/camera_rig.gd",
	"res://scenes/dev/visual_experiments/observer.gd",
	"res://scripts/dialogue/",
	"res://scenes/locations/",
	"res://scenes/main/",
	"res://assets/shaders/",
]
const PRODUCTION_ROOTS: Array[String] = [
	"res://scenes/", "res://scripts/", "res://data/", "res://assets/", "res://addons/"
]
## Where the production room's low teacher's desk stood (FrontDesk).
const OLD_LOW_DESK := Vector3(-4.65, 0.0, -2.2)

var _failures: Array[String] = []
var _room_script: GDScript = null
## Bodies a sweep ignores: the visitor itself, and Q (who walks).
var _sweep_exclude: Array[RID] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "biology_classroom_experiment_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "shaders"
	_check_shaders()
	Harness.stage = "isolation"
	_check_isolation()
	Harness.stage = "capture scripts"
	for path: String in CAPTURE_SCRIPTS:
		var script := load(path) as GDScript
		_expect(script != null and script.can_instantiate(), "Capture script %s does not compile." % path)

	Harness.stage = "instantiate"
	_room_script = load(ROOM_SCRIPT) as GDScript
	var packed := ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_failures.append("The biology classroom experiment could not be loaded.")
		_finish("")
		return
	var scene := packed.instantiate() as Node3D
	packed = null
	if scene == null:
		_failures.append("The biology classroom experiment could not be instantiated.")
		_finish("")
		return
	root.add_child(scene)
	await _frames(4)
	_sweep_exclude.append((scene.get_node("Visitor") as CollisionObject3D).get_rid())
	var q_body := scene.get_node_or_null("QPresence/Body") as CollisionObject3D
	if q_body != null:
		_sweep_exclude.append(q_body.get_rid())

	Harness.stage = "set"
	_check_set(scene)
	Harness.stage = "closed"
	_check_closed(scene)
	Harness.stage = "projector"
	_check_projector(scene)
	Harness.stage = "classmates"
	_check_classmates(scene)
	Harness.stage = "fixed camera"
	await _check_fixed_camera(scene)
	Harness.stage = "playable"
	await _check_playable(scene)
	Harness.stage = "registers"
	await _check_registers(scene)
	Harness.stage = "door and Q"
	await _check_door_and_q(scene)
	Harness.stage = "curtain and fall"
	await _check_curtain_and_fall(scene)
	Harness.stage = "bell"
	await _check_bell(scene)

	Harness.stage = "performance"
	var sample: Dictionary = await scene.call("sample_performance", 5)
	for key: String in ["draw_calls", "primitives", "frame_ms", "video_mem_mib", "renderer"]:
		_expect(sample.has(key), "The performance sample has no '%s'." % key)
	print("BIOLOGY_CLASSROOM_TEST sample %s" % JSON.stringify(sample))

	Harness.stage = "teardown"
	var paper := scene.get_node("PaperSwitch")
	paper.call("set_paper", true, true)
	_expect(root.disable_3d, "Forcing the paper did not stop root 3D rendering.")
	var reference: WeakRef = weakref(scene)
	scene.queue_free()
	scene = null
	paper = null
	await _frames(3)
	_expect(reference.get_ref() == null, "The experiment survived queue_free().")
	_expect(not root.disable_3d, "Freeing the experiment on paper left the window without 3D.")
	_finish("the biology classroom experiment builds, plays, draws its curtain and tears down cleanly")


# --- Static checks ----------------------------------------------------------------------


func _check_shaders() -> void:
	var real_renderer := DisplayServer.get_name() != "headless"
	for file_name: String in SHADER_UNIFORMS:
		var path := SHADER_DIR + file_name
		var shader := load(path) as Shader
		if shader == null:
			_failures.append("Experiment shader %s does not load." % path)
			continue
		if not real_renderer:
			continue
		var names: Array[String] = []
		for uniform: Dictionary in shader.get_shader_uniform_list():
			names.append(String(uniform.get("name", "")))
		for wanted: String in SHADER_UNIFORMS[file_name]:
			_expect(names.has(wanted), "%s does not expose '%s' (did it fail to parse?)." % [path, wanted])
	if not real_renderer:
		print("BIOLOGY_CLASSROOM_TEST shader uniforms skipped: no renderer under --headless")


func _check_isolation() -> void:
	var files := _files_under(DIR, ["gd", "tscn", "gdshader", "tres"])
	_expect(files.size() >= 9, "Expected the experiment's scripts, scene and shaders, found %d files." % files.size())
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for forbidden: String in FORBIDDEN:
			_expect(not text.contains(forbidden), "%s references production code %s." % [path, forbidden])
	for production_root: String in PRODUCTION_ROOTS:
		for path: String in _files_under(production_root, ["gd", "tscn", "tres", "json", "cfg"]):
			if path.begins_with("res://scenes/dev/"):
				continue
			_expect(not FileAccess.get_file_as_string(path).contains("biology_classroom/"), "%s references the experiment." % path)
	_expect(not FileAccess.get_file_as_string("res://project.godot").contains("biology_classroom"), "project.godot references the experiment.")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	for line: String in presets.split("\n"):
		if line.begins_with("exclude_filter="):
			_expect(line.contains("scenes/dev/*"), "An export preset does not exclude scenes/dev/*.")


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


# --- The set ----------------------------------------------------------------------------


func _check_set(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	_expect(scene.get_node_or_null("Visitor") is CharacterBody3D, "No visitor body.")
	_expect(scene.get_node_or_null("Visitor/Visual/Character") != null, "The visitor is not the protagonist.")
	_expect(scene.get_node_or_null("QPresence") != null, "No Q.")
	_expect(scene.get_node_or_null("PaperSwitch") != null, "No paper switch.")
	# No low teacher's desk anywhere in the scene.
	for node: Node in _all_nodes(scene):
		_expect(not node.scene_file_path.contains("teacher_desk"), "A low teacher's desk is instanced: %s." % node.get_path())
		var lowered := String(node.name).to_lower()
		_expect(not (lowered.contains("frontdesk") or lowered.contains("teacherdesk")), "A node is named like the low desk: %s." % node.get_path())
	# The tall lectern: at the window end of the front, on the platform, where the low desk was.
	var lectern := room.get("lectern") as Node3D
	_expect(lectern != null, "No lectern.")
	if lectern == null:
		return
	var at := lectern.global_position
	var room_min: Vector2 = _room_const("ROOM_MIN")
	var window: Rect2 = _room_const("FRONT_WINDOW")
	var platform_height: float = _room_const("PLATFORM_HEIGHT")
	_expect(at.x < -3.5, "The lectern is not on the left of the room (x %.2f)." % at.x)
	_expect(at.x - room_min.x < 3.0, "The lectern is not near the window wall (%.2f m)." % (at.x - room_min.x))
	var window_z := window.position.x + window.size.x * 0.5
	_expect(absf(at.z - window_z) < 1.2, "The lectern is not by the front window (dz %.2f)." % absf(at.z - window_z))
	_expect(Vector2(at.x - OLD_LOW_DESK.x, at.z - OLD_LOW_DESK.z).length() < 0.8, "The lectern is not where the low desk stood.")
	_expect(is_equal_approx(at.y, platform_height), "The lectern does not stand on the platform (y %.2f)." % at.y)
	var top_height: float = room.call("lectern_top_height")
	_expect(top_height >= 1.2, "The lectern is not a tall one (top %.2f m)." % top_height)
	# B's things on its top.
	for item: String in ["SetSquare", "Register", "RedPencil", "ChalkBox"]:
		var node := lectern.get_node_or_null("Top/%s" % item) as Node3D
		_expect(node != null, "The lectern has no %s on its top." % item)
		if node == null:
			continue
		var offset := node.global_position - at
		_expect(absf(offset.x) < 0.6 and absf(offset.z) < 0.4, "%s is not over the lectern's top." % item)
		_expect(node.global_position.y >= top_height - 0.02 and node.global_position.y < top_height + 0.1, "%s does not lie on the lectern's top (y %.2f)." % [item, node.global_position.y])
	_expect(lectern.get_node_or_null("Pointer") != null, "The pointer is not leaning on the lectern.")
	# The other main objects, where they work.
	var board := room.get_node_or_null("Board") as Node3D
	_expect(board != null, "No blackboard.")
	var curtain := room.get("curtain") as Node3D
	var opening: Rect2 = _room_const("BACK_OPENING")
	_expect(curtain != null and curtain.global_position.x < room_min.x + 0.3, "The curtain is not against the west wall.")
	_expect(curtain != null and curtain.global_position.z >= opening.end.x and curtain.global_position.z < opening.end.x + 0.5, "The curtain does not hang from the back opening's end.")
	var door := room.get("door_pivot") as Node3D
	var room_max: Vector2 = _room_const("ROOM_MAX")
	_expect(door != null and door.global_position.x > room_max.x, "The exit door is not in the east wall.")
	var rows: Array[float] = _room_const("DESK_ROWS")
	var platform_max: Vector2 = _room_const("PLATFORM_MAX")
	var ramp: float = _room_const("RAMP")
	_expect(rows[0] - 0.275 - (platform_max.y + ramp) >= 0.6, "The front desks leave no aisle before the platform.")
	var columns: Array[float] = _room_const("DESK_COLUMNS")
	for index in range(1, columns.size()):
		_expect(columns[index] - columns[index - 1] - 1.2 >= 0.8, "Desk columns %d and %d leave no aisle." % [index - 1, index])
	var solids: Array = room.get("solids")
	_expect(solids.size() >= 30, "Expected the room's box colliders, found %d." % solids.size())


func _all_nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_all_nodes(child))
	return found


# --- Closed walls -----------------------------------------------------------------------


## Every ordinary wall and the ceiling are solid to the eye and to a body: from inside, a
## line of sight to any point just beyond a wall or the ceiling meets the room's own
## surfaces. The curtained opening is the one way to see out (the doors are shut here).
func _check_closed(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var wall_height: float = _room_const("WALL_HEIGHT")
	var room_min: Vector2 = _room_const("ROOM_MIN")
	var room_max: Vector2 = _room_const("ROOM_MAX")
	var opening: Rect2 = _room_const("BACK_OPENING")
	var door_width: float = _room_const("DOOR_WIDTH")
	var door_height: float = _room_const("DOOR_HEIGHT")
	var doors: Array[float] = []
	doors.append(float(_room_const("FRONT_DOOR_Z")))
	doors.append(float(_room_const("REAR_DOOR_Z")))
	# The colliders reach the ceiling.
	for body: StaticBody3D in room.get("solids"):
		if not String(body.name).begins_with("Wall"):
			continue
		var shape := (body.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var top := body.global_position.y + shape.size.y * 0.5
		_expect(top >= wall_height - 0.01, "%s stops at %.2f m, short of the ceiling." % [body.name, top])
	# The surfaces: the shell, the near walls, the ceiling, the painted front window.
	var occluder := StaticBody3D.new()
	occluder.name = "ClosureProbe"
	occluder.collision_layer = 1 << 20
	occluder.collision_mask = 0
	var found := 0
	for part: String in ["Shell", "ShellNear", "Ceiling", "WindowView"]:
		var instance := room.get_node_or_null(part) as MeshInstance3D
		_expect(instance != null and instance.mesh != null, "The room has no %s surface." % part)
		if instance == null or instance.mesh == null:
			continue
		found += 1
		var faces := instance.mesh.get_faces()
		var world := PackedVector3Array()
		world.resize(faces.size())
		for index in faces.size():
			world[index] = instance.global_transform * faces[index]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(world)
		var holder := CollisionShape3D.new()
		holder.shape = shape
		occluder.add_child(holder)
	var near := room.get_node_or_null("ShellNear") as GeometryInstance3D
	if near != null:
		_expect(near.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "The near walls shade the corridor.")
		# Lit at full gain through the shadowless ceiling, the near walls went as pale as the
		# sky and read as open.
		var near_material := near.material_override as ShaderMaterial
		_expect(near_material != null and float(near_material.get_shader_parameter("light_gain")) <= 0.5, "The near walls take the full sun and read as sky.")
	if found == 0:
		occluder.free()
		return
	scene.add_child(occluder)
	var space := room.get_world_3d().direct_space_state
	var eyes: Array[Vector3] = [Vector3(0.0, 1.6, 0.0), Vector3(-5.0, 1.6, -3.6), Vector3(5.0, 2.4, 4.0)]
	var targets: Array[Vector3] = []
	for x in range(-13, 14):
		for y: float in [0.3, 1.2, 2.1, 3.0]:
			targets.append(Vector3(x * 0.5, y, room_min.y - 0.6))
			targets.append(Vector3(x * 0.5, y, room_max.y + 0.6))
	for z in range(-9, 10):
		for y: float in [0.3, 1.2, 2.1, 3.0]:
			var along := z * 0.5
			targets.append(Vector3(room_min.x - 0.6, y, along) if absf(along - opening.get_center().x) > opening.size.x * 0.5 + 0.7 else Vector3.INF)
			var by_door := false
			for door_z: float in doors:
				by_door = by_door or (absf(along - door_z) < door_width * 0.5 + 0.4 and y < door_height + 0.2)
			targets.append(Vector3.INF if by_door else Vector3(room_max.x + 0.6, y, along))
	for x in range(-6, 7):
		for z in range(-4, 5):
			targets.append(Vector3(x * 1.1, wall_height + 0.6, z * 1.1))
	var leaks: Array[String] = []
	var tested := 0
	for eye: Vector3 in eyes:
		for target: Vector3 in targets:
			if target == Vector3.INF:
				continue
			# Only targets whose line leaves through a wall, not the opening's hole.
			var query := PhysicsRayQueryParameters3D.create(eye, target, 1 << 20)
			query.hit_back_faces = true
			tested += 1
			if space.intersect_ray(query).is_empty() and not _through_opening(eye, target, room_min.x, opening):
				leaks.append("%s -> %s" % [str(eye), str(target)])
	_expect(tested > 400, "The closure probe tested only %d lines." % tested)
	_expect(leaks.is_empty(), "Lines of sight out of the closed room: %d, e.g. %s." % [leaks.size(), ", ".join(leaks.slice(0, 4))])
	# The opening itself is open: the one place the outside shows.
	var through := opening.get_center()
	var out := PhysicsRayQueryParameters3D.create(Vector3(-4.0, 1.7, through.x), Vector3(room_min.x - 1.0, 1.7, through.x), 1 << 20)
	out.hit_back_faces = true
	_expect(space.intersect_ray(out).is_empty(), "The curtained opening is walled up.")
	occluder.queue_free()


## Whether the line from `eye` to `target` crosses the west wall's plane inside the opening.
func _through_opening(eye: Vector3, target: Vector3, wall_x: float, opening: Rect2) -> bool:
	if (eye.x - wall_x) * (target.x - wall_x) > 0.0:
		return false
	var t := (wall_x - eye.x) / (target.x - eye.x)
	var at := eye.lerp(target, t)
	return at.z >= opening.position.x - 0.25 and at.z <= opening.end.x + 0.25 and at.y >= opening.position.y - 0.25 and at.y <= opening.end.y + 0.25


# --- The projector ----------------------------------------------------------------------


func _check_projector(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var projector := room.get("projector") as Node3D
	_expect(projector != null, "No projector.")
	if projector == null:
		return
	var wall_height: float = _room_const("WALL_HEIGHT")
	var room_min: Vector2 = _room_const("ROOM_MIN")
	var platform_max: Vector2 = _room_const("PLATFORM_MAX")
	var projection: Rect2 = _room_const("PROJECTION")
	var at := projector.global_position
	# Hung from the ceiling over the front of the room, between the platform's edge and the
	# board, in line with the board; aimed down at the picture on the front wall.
	_expect(at.y > wall_height - 0.9 and at.y < wall_height, "The projector does not hang under the ceiling (y %.2f)." % at.y)
	_expect(at.z > room_min.y + 1.5 and at.z < platform_max.y + 1.2, "The projector is not over the front of the room (z %.2f)." % at.z)
	_expect(room.get_node_or_null("ProjectorMount") != null, "The projector has no ceiling mount.")
	var board := room.get_node_or_null("Board") as Node3D
	if board != null:
		_expect(absf(at.x - projection.get_center().x) < 0.05, "The projector is not in line with its picture.")
	var aim := -projector.global_basis.z
	_expect(aim.z < -0.9 and aim.y < -0.05, "The projector does not point down at the front wall (aim %s)." % str(aim))
	var t := (room_min.y - at.z) / aim.z
	var hit := at + aim * t
	_expect(absf(hit.x - projection.get_center().x) < 0.2 and absf(hit.y - projection.get_center().y) < 0.2, "The projector is not aimed at its picture (hits %s)." % str(hit))
	_expect(projection.position.y > 0.9 and projection.end.y < wall_height, "The picture is off the front wall.")
	_expect(room.get_node_or_null("ProjectionScreen/ProjectedImage") != null, "No picture on the front wall.")
	_expect(room.get_node_or_null("ProjectorCable0") != null and room.get_node_or_null("ProjectorTrunking") != null, "The projector is not wired to anything.")
	var lectern_top := room.get("lectern_top") as Node3D
	_expect(lectern_top != null and lectern_top.get_node_or_null("ProjectorSwitch") != null, "The projector's switch is not on the lectern.")
	var beam := room.get("projector_beam") as Node3D
	var image := room.get("projected_image") as Node3D
	room.call("set_projector", true)
	_expect(beam.visible and image.visible and bool(room.get("projector_on")), "Switching the projector on shows no picture.")
	room.call("set_projector", false)
	_expect(not beam.visible and not image.visible, "Switching the projector off leaves the picture.")
	scene.call("set_beat", 2, true)
	_expect(bool(room.get("projector_on")), "The projector is off in the lesson.")
	scene.call("set_beat", 1, true)
	_expect(not bool(room.get("projector_on")), "The projector is on before the lesson.")
	# The hook for another medium: whatever it is given is what the picture shows.
	var picture := room.get("projection_material") as StandardMaterial3D
	var slide := picture.albedo_texture
	var other := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	room.call("set_projection", other)
	_expect(picture.albedo_texture == other, "set_projection does not change the picture.")
	room.call("set_projection", slide)


# --- The class --------------------------------------------------------------------------


func _check_classmates(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var pupils: Array = room.get("classmates")
	_expect(pupils.size() >= 6, "Expected the cut-paper class, found %d pupils." % pupils.size())
	var sheets: Array[RID] = []
	var standing := 0
	var room_max: Vector2 = _room_const("ROOM_MAX")
	for pupil: MeshInstance3D in pupils:
		_expect(pupil.mesh is ArrayMesh, "%s is a card, not a cut-paper figure." % pupil.name)
		var material := pupil.material_override as ShaderMaterial
		_expect(material != null and material.shader != null and material.shader.resource_path.ends_with("cut_paper.gdshader"), "%s is not on the cut-paper shader." % pupil.name)
		if material != null:
			var sheet := material.get_shader_parameter("paper_sheet") as Texture2D
			_expect(sheet != null, "%s has no paper." % pupil.name)
			if sheet != null:
				_expect(not sheets.has(sheet.get_rid()), "%s shares its paper with another pupil." % pupil.name)
				sheets.append(sheet.get_rid())
		var box := pupil.get_aabb()
		# Layers in depth, not one flat board.
		_expect(box.size.z > 0.08 and box.size.x > 0.25, "%s is flat (%s)." % [pupil.name, str(box.size)])
		_expect(box.size.y > 0.6 and box.size.y < 1.9, "%s is not a pupil's height (%.2f m)." % [pupil.name, box.size.y])
		for child: Node in pupil.get_children():
			_expect(not String(child.name).to_lower().contains("board"), "%s still stands on a board." % pupil.name)
		if pupil.global_position.z > room_max.y - 0.6:
			standing += 1
	_expect(standing == 1, "Expected one pupil standing at the back wall, found %d." % standing)
	var materials: Array = room.get("register_materials")
	_expect(materials.size() >= 4 + pupils.size(), "The class and the concrete do not take the registers (%d materials)." % materials.size())


# --- The fixed camera -------------------------------------------------------------------


func _check_fixed_camera(scene: Node3D) -> void:
	var camera := scene.get_node_or_null("ShotCamera") as Camera3D
	var visitor := scene.get_node("Visitor") as CharacterBody3D
	_expect(camera != null and camera.current, "No current ShotCamera.")
	if camera == null:
		return
	_expect(camera.get_parent() == scene, "The camera hangs off something that moves.")
	for node: Node in _all_nodes(visitor):
		_expect(not (node is Camera3D), "The visitor carries a camera: %s." % node.get_path())
	var lens: float = _script_const(camera, "LENS_FOV")
	scene.call("reset_experiment")
	await _physics(3)
	_expect(String(scene.call("current_shot")) == "seated", "Seated, the shot is %s." % String(scene.call("current_shot")))
	# Walking about inside one zone: the camera does not move, turn or zoom at all.
	scene.call("observe", Vector3(0.6, 0.0, 0.6), Vector3(0.6, 0.0, -2.0))
	await _physics(3)
	_expect(String(scene.call("current_shot")) == "classroom", "The middle of the room is not the classroom shot.")
	var moves := int(camera.get("moves"))
	var still := camera.global_transform
	var start := visitor.global_position
	var steps: Array[Key] = [KEY_A, KEY_D, KEY_S]
	for key: Key in steps:
		_press(key, true)
		for _index in 12:
			await physics_frame
			_expect(camera.global_transform.is_equal_approx(still), "The camera moved while he walked inside one zone (%s)." % OS.get_keycode_string(key))
			_expect(is_equal_approx(camera.fov, lens), "The lens changed (%.1f)." % camera.fov)
		_press(key, false)
		await _physics(2)
	var walked := visitor.global_position.distance_to(start)
	_expect(walked > 0.3, "The keys did not walk him under the fixed camera (%.2f m)." % walked)
	_expect(int(camera.get("moves")) == moves, "The camera reframed inside one zone (%d moves)." % (int(camera.get("moves")) - moves))
	_expect(String(scene.call("current_shot")) == "classroom", "Walking inside the classroom zone changed the shot.")
	# Walking into another zone: one change of shot, then still again.
	scene.call("observe", Vector3(3.0, 0.0, 0.2), Vector3(4.0, 0.0, 1.0))
	await _physics(3)
	moves = int(camera.get("moves"))
	_press(KEY_S, true)
	var waited := 0.0
	while visitor.global_position.x < 4.4 and waited < 3.0:
		await _wait(0.1)
		waited += 0.1
	_press(KEY_S, false)
	await _wait(0.8)
	_expect(String(scene.call("current_shot")) == "east", "Walking to the east side did not change to its shot (%s, at %s)." % [String(scene.call("current_shot")), str(visitor.global_position)])
	_expect(int(camera.get("moves")) - moves == 1, "Changing zone moved the camera %d times." % (int(camera.get("moves")) - moves))
	await _wait(1.8)
	var settled := camera.global_transform
	await _physics(10)
	_expect(camera.global_transform.is_equal_approx(settled), "The camera keeps moving after the change of shot.")
	_expect(is_equal_approx(camera.fov, lens), "The lens changed with the shot (%.1f)." % camera.fov)
	# Everywhere he can stand, he is inside the frame of the shot he gets there.
	var minimum: float = _script_const(scene, "FRAME_MARGIN")
	var points: Array[Vector3] = []
	for x in range(-13, 14, 2):
		for z in range(-9, 10, 2):
			var feet := Vector3(x * 0.5, 0.0, z * 0.5)
			if feet.x < 3.6 and feet.z < -2.1:
				feet.y = 0.15
			points.append(feet)
	for x in range(0, 7):
		for z in range(0, 9):
			points.append(Vector3(7.6 + x * 0.4, 0.0, -5.2 + z * 1.8))
	for x in range(0, 9):
		for z in range(0, 6):
			points.append(Vector3(-19.5 + x * 1.45, -3.4, -4.7 + z * 1.88))
	var outside: Array[String] = []
	for feet: Vector3 in points:
		scene.call("observe", feet, feet + Vector3(0.0, 0.0, -1.0))
		var shot := StringName(scene.call("current_shot"))
		var margin := float(scene.call("frame_margin", shot, feet))
		if margin < minimum:
			outside.append("%s in %s (%.3f)" % [str(feet), shot, margin])
	_expect(outside.is_empty(), "Out of frame in %d places, e.g. %s." % [outside.size(), ", ".join(outside.slice(0, 4))])
	# A story beat's shot: an authored camera holds until he moves.
	scene.call("observe", Vector3(0.6, 0.0, 0.6), Vector3(0.6, 0.0, -2.0))
	scene.call("look_from", Vector3(0.0, 2.6, 4.6), Vector3(-1.0, 1.2, -5.0))
	await _physics(6)
	_expect(String(scene.call("current_shot")) == "authored", "An authored shot was overridden at once.")
	_press(KEY_A, true)
	await _physics(4)
	_press(KEY_A, false)
	await _wait(0.8)
	_expect(String(scene.call("current_shot")) != "authored", "An authored shot outlasted his moving.")
	await _wait(1.8)


# --- Playable ---------------------------------------------------------------------------


func _check_playable(scene: Node3D) -> void:
	var visitor := scene.get_node("Visitor") as CharacterBody3D
	scene.call("reset_experiment")
	await _physics(3)
	_expect(bool(scene.get("seated")), "The protagonist does not start seated at his desk.")
	var seat := visitor.global_position
	_press(KEY_D, true)
	await _wait(2.2)
	_press(KEY_D, false)
	await _physics(3)
	_expect(not bool(scene.get("seated")), "A movement key did not stand the protagonist up.")
	var walked := Vector2(visitor.global_position.x - seat.x, visitor.global_position.z - seat.z).length()
	_expect(walked > 0.4, "Holding a movement key did not walk the protagonist (%.2f m)." % walked)
	# Bodies stop at desks and walls.
	var space := visitor.get_world_3d().direct_space_state
	_expect(_sweep(space, Vector3(-1.6, 0.0, 2.6), Vector3(-1.6, 0.0, 0.6)) < 0.9, "A body walks through the protagonist's desk.")
	_expect(_sweep(space, Vector3(0.0, 0.0, 4.0), Vector3(0.0, 0.0, 6.0)) < 0.9, "A body walks through the south wall.")
	_expect(_sweep(space, Vector3(-5.5, 0.0, -1.0), Vector3(-8.5, 0.0, -1.0)) < 0.9, "A body walks through the window wall.")
	_expect(_sweep(space, Vector3(-3.4, 0.16, -2.55), Vector3(-6.0, 0.16, -2.55)) < 0.4, "A body on the platform walks through the lectern.")
	# The platform is reachable up its ramp.
	scene.call("observe", Vector3(-1.0, 0.0, -1.4), Vector3(-1.0, 0.0, -4.0))
	await _physics(2)
	_press(KEY_W, true)
	await _wait(1.0)
	_press(KEY_W, false)
	await _physics(4)
	_expect(visitor.global_position.z < -2.0 and visitor.global_position.y > 0.1, "The protagonist cannot step up onto the platform (at %s)." % str(visitor.global_position))


func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3(0.0, 0.9, 0.0))
	query.motion = to - from
	query.exclude = _sweep_exclude
	var result := space.cast_motion(query)
	return result[0] if result.size() > 0 else 1.0


func _press(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


# --- Registers --------------------------------------------------------------------------


func _check_registers(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var material := room.get("room_material") as ShaderMaterial
	scene.call("set_beat", 1, true)
	scene.call("observe", Vector3(3.2, 0.0, 2.0), Vector3(3.2, 0.0, 0.0))
	await _physics(2)
	scene.call("snap_registers")
	var calm_chill := float(material.get_shader_parameter("chill"))
	_expect(calm_chill < 0.15, "The wake beat, far from the lectern, is already chilled (%.2f)." % calm_chill)
	scene.call("set_beat", 2, true)
	scene.call("observe", Vector3(-4.0, 0.0, -1.5), Vector3(-4.7, 0.0, -2.55))
	await _physics(2)
	scene.call("snap_registers")
	await _frames(2)
	var chill := float(material.get_shader_parameter("chill"))
	_expect(chill > 0.6, "The lesson beat by the lectern does not chill the room (%.2f)." % chill)
	var shadow := room.get("b_shadow") as MeshInstance3D
	var shadow_amount := float((shadow.material_override as ShaderMaterial).get_shader_parameter("amount"))
	_expect(shadow_amount > 0.8, "The shadow on the front wall did not climb (%.2f)." % shadow_amount)
	var square := room.get("square_shadow") as MeshInstance3D
	var square_amount := float((square.material_override as ShaderMaterial).get_shader_parameter("amount"))
	_expect(square_amount > 0.5, "The set square's shadow did not cross the floor (%.2f)." % square_amount)
	var body := room.get("lectern_body") as Node3D
	_expect(body.scale.y > 1.15, "The lectern did not grow in the lesson beat (%.2f)." % body.scale.y)
	_expect(String(scene.call("current_zone")) == "lectern", "Standing by the lectern is not the lectern's zone.")
	scene.call("set_beat", 3, true)
	scene.call("observe", Vector3(3.2, 0.0, 2.0), Vector3(3.2, 0.0, 0.0))
	scene.call("snap_registers")
	await _frames(2)
	_expect(float(material.get_shader_parameter("chill")) < 0.15, "The room stays chilled after the lesson beat.")


# --- The door, and Q --------------------------------------------------------------------


func _check_door_and_q(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var visitor := scene.get_node("Visitor") as CharacterBody3D
	var q := scene.get_node("QPresence") as Node3D
	var space := visitor.get_world_3d().direct_space_state
	var door_z: float = _room_const("FRONT_DOOR_Z")
	scene.call("open_door", false)
	scene.call("snap_registers")
	await _physics(3)
	_expect(_sweep(space, Vector3(6.3, 0.0, door_z), Vector3(8.6, 0.0, door_z)) < 0.9, "The shut front door does not stop a body.")
	scene.call("open_door", true)
	await _wait(0.9)
	await _physics(3)
	_expect(_sweep(space, Vector3(6.3, 0.0, door_z), Vector3(8.6, 0.0, door_z)) > 0.99, "The open front door does not let a body through.")
	# Out into the corridor: Q comes to the doorway, on foot, and stays inside.
	q.call("set_place_instant", 0)
	q.set("distance_walked", 0.0)
	q.set("largest_step", 0.0)
	var q_start := q.global_position
	var started := Time.get_ticks_msec()
	scene.call("observe", Vector3(8.8, 0.0, -2.0), Vector3(8.8, 0.0, 2.0))
	await _physics(3)
	_expect(String(scene.call("current_zone")) == "corridor", "The corridor is not its own zone.")
	_expect_walked(q, q_start, started, "Q jumped when the protagonist went out.")
	var waited := 0.0
	while bool(q.call("is_walking")) and waited < 16.0:
		await _wait(0.5)
		waited += 0.5
	var limit: float = _script_const(q, "THRESHOLD_LIMIT_X")
	var room_max: Vector2 = _room_const("ROOM_MAX")
	_expect(int(q.get("place")) == 2, "Q did not come to the doorway (place %d)." % int(q.get("place")))
	_expect(q.global_position.x <= limit + 0.001 and q.global_position.x < room_max.x, "Q crossed the doorway (x %.2f)." % q.global_position.x)
	_expect(float(q.get("distance_walked")) > 8.0, "Q did not walk to the doorway (%.2f m)." % float(q.get("distance_walked")))
	_expect(float(q.get("largest_step")) < 0.1, "Q moved %.2f m in one frame: a jump, not a walk." % float(q.get("largest_step")))
	_expect(q.global_position.distance_to(visitor.global_position) > 2.0, "Q is following the protagonist into the corridor.")
	# The outside's interactions: the stairs down, and the neighbouring door.
	scene.call("observe", Vector3(8.0, 0.0, -4.85), Vector3(8.0, 0.0, -2.0))
	await _physics(2)
	_expect(StringName(scene.call("current_interaction")[0]) == &"stair_down", "The stair head is not an interaction.")
	# Back inside: Q sets off home, walking.
	scene.call("observe", Vector3(2.0, 0.0, 0.6), Vector3(0.0, 0.0, 0.6))
	await _physics(4)
	_expect(int(q.get("place")) == 0 and bool(q.call("is_walking")), "Q does not walk back when the protagonist comes in.")
	scene.call("open_door", false)


# --- The curtain and the fall -----------------------------------------------------------


func _check_curtain_and_fall(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	var visitor := scene.get_node("Visitor") as CharacterBody3D
	var paper := scene.get_node("PaperSwitch")
	var q := scene.get_node("QPresence") as Node3D
	scene.call("reset_experiment")
	scene.call("set_beat", 3, true)
	scene.call("observe", Vector3(-5.9, 0.0, 2.2), Vector3(-7.0, 0.0, 2.2))
	await _physics(3)
	_expect(String(scene.call("current_zone")) == "curtain", "Standing at the curtain is not the curtain's zone.")
	_expect(StringName(scene.call("current_interaction")[0]) == &"curtain", "The curtain is not an interaction here.")
	var q_before := q.global_position
	var curtain_started := Time.get_ticks_msec()
	scene.call("open_curtain", true)
	await _frames(3)
	_expect(bool(paper.call("is_on")), "Drawing the curtain did not put the picture on paper.")
	_expect(root.disable_3d, "On paper, the root viewport still renders 3D (the frame would be drawn twice).")
	var view := paper.call("get_view") as SubViewport
	_expect(view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "On paper, the SubViewport is not rendering.")
	_expect((paper.call("get_canvas") as CanvasLayer).visible, "On paper, the paper canvas is hidden.")
	var shot_camera := scene.get_node("ShotCamera") as Camera3D
	var paper_camera := paper.call("get_paper_camera") as Camera3D
	_expect(paper_camera.global_transform.is_equal_approx(shot_camera.global_transform), "The paper is not drawn from the fixed camera's view.")
	_expect(String(scene.call("current_shot")) == "curtain", "At the curtain, the shot is %s." % String(scene.call("current_shot")))
	var ring := room.get("ring_mark") as MeshInstance3D
	_expect(ring.visible, "The red ring was not drawn.")
	_expect(Vector2(ring.global_position.x - visitor.global_position.x, ring.global_position.z - visitor.global_position.z).length() < 0.05, "The red ring is not where the protagonist stands.")
	_expect_walked(q, q_before, curtain_started, "Q jumped to the window.")
	_expect(int(q.get("place")) == 1 and bool(q.call("is_walking")), "Q does not walk over to the window.")
	_expect(StringName(scene.call("current_interaction")[0]) == &"curtain", "The open curtain offers no way to lean out.")
	scene.call("_fall")
	await _wait(3.2)
	var landing: Vector3 = _room_const("LANDING")
	_expect(visitor.global_position.distance_to(landing) < 0.6, "The fall did not land in the yard (at %s)." % str(visitor.global_position))
	_expect(String(scene.call("current_zone")) == "yard", "The landing is not the yard's zone.")
	_expect(not bool(paper.call("is_on")) and not root.disable_3d, "The yard is still on paper.")
	_expect(int(scene.get("falls")) == 1, "The fall was not counted.")
	_expect(q.global_position.distance_to(landing) > 3.0, "Q is at the fall's landing.")
	_expect(bool(_room_script.call("is_inside_room", q.global_position)), "Q left the classroom with the fall.")
	_expect(not bool(scene.get("locked")), "The controls stayed locked after the landing.")
	var yard_door: Vector3 = _script_const(scene, "YARD_DOOR_FEET")
	scene.call("observe", yard_door, yard_door + Vector3(-2.0, 0.0, 0.0))
	await _physics(2)
	_expect(StringName(scene.call("current_interaction")[0]) == &"stair_up", "The yard has no way back up.")


# --- The bell ---------------------------------------------------------------------------


func _check_bell(scene: Node3D) -> void:
	var room := scene.get_node("Room") as Node3D
	scene.call("reset_experiment")
	scene.call("observe", Vector3(2.5, 0.0, 0.6), Vector3(0.0, 0.0, -3.0))
	scene.call("set_beat", 4, true)
	await _frames(3)
	var n := scene.call("n_actor") as Node3D
	_expect(n != null, "The bell did not bring N.")
	if n != null:
		var lectern := room.get("lectern") as Node3D
		var platform_height: float = _room_const("PLATFORM_HEIGHT")
		_expect(is_equal_approx(n.global_position.y, platform_height), "N is not on the platform.")
		_expect(n.global_position.distance_to(lectern.global_position) > 3.0, "N stands at B's lectern.")
	_expect(bool(scene.call("is_n_standing")), "N is not standing in front of the class.")
	_expect(float(scene.get("dull")) > 0.9, "The bell beat does not drain the colour.")
	var q := scene.get_node("QPresence") as Node3D
	_expect(int(q.get("place")) == 3, "Q does not go to his seat when the bell has gone.")


# --- Helpers ----------------------------------------------------------------------------


## Q may have walked since `since_msec` (a software rasteriser's frame can take 0.1 s or
## more), but no further than walking allows.
func _expect_walked(q: Node3D, from: Vector3, since_msec: int, message: String) -> void:
	var seconds := float(Time.get_ticks_msec() - since_msec) / 1000.0
	var speed: float = _script_const(q, "WALK_SPEED")
	var moved := q.global_position.distance_to(from)
	_expect(moved <= speed * seconds + 0.1, "%s (%.2f m in %.2f s)" % [message, moved, seconds])


func _room_const(constant: String) -> Variant:
	return _room_script.get_script_constant_map().get(constant)


func _script_const(node: Object, constant: String) -> Variant:
	var script := node.get_script() as Script
	return script.get_script_constant_map().get(constant) if script != null else null


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics(count: int) -> void:
	for _index in count:
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
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
