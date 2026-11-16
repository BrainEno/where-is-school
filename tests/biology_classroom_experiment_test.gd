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
## 9. A performance sample, and a teardown that leaves the window rendering 3D even if the
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
}
const CAPTURE_SCRIPTS: Array[String] = ["res://tests/capture_biology_classroom.gd"]
const FORBIDDEN: Array[String] = [
	"res://scripts/actors/player/",
	"res://scripts/world/camera_rig.gd",
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
	_sweep_exclude.append((scene.get_node("Observer") as CollisionObject3D).get_rid())
	var q_body := scene.get_node_or_null("QPresence/Body") as CollisionObject3D
	if q_body != null:
		_sweep_exclude.append(q_body.get_rid())

	Harness.stage = "set"
	_check_set(scene)
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
	_expect(scene.get_node_or_null("Observer") is CharacterBody3D, "No visitor body.")
	_expect(scene.get_node_or_null("Observer/Visual/Character") != null, "The visitor is not the protagonist.")
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


# --- Playable ---------------------------------------------------------------------------


func _check_playable(scene: Node3D) -> void:
	var observer := scene.get_node("Observer") as CharacterBody3D
	scene.call("reset_experiment")
	await _physics(3)
	_expect(bool(scene.get("seated")), "The protagonist does not start seated at his desk.")
	var seat := observer.global_position
	_press(KEY_D, true)
	await _wait(2.2)
	_press(KEY_D, false)
	await _physics(3)
	_expect(not bool(scene.get("seated")), "A movement key did not stand the protagonist up.")
	var walked := Vector2(observer.global_position.x - seat.x, observer.global_position.z - seat.z).length()
	_expect(walked > 0.4, "Holding a movement key did not walk the protagonist (%.2f m)." % walked)
	# Bodies stop at desks and walls.
	var space := observer.get_world_3d().direct_space_state
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
	_expect(observer.global_position.z < -2.0 and observer.global_position.y > 0.1, "The protagonist cannot step up onto the platform (at %s)." % str(observer.global_position))


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
	var observer := scene.get_node("Observer") as CharacterBody3D
	var q := scene.get_node("QPresence") as Node3D
	var space := observer.get_world_3d().direct_space_state
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
	_expect(q.global_position.distance_to(observer.global_position) > 2.0, "Q is following the protagonist into the corridor.")
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
	var observer := scene.get_node("Observer") as CharacterBody3D
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
	var ring := room.get("ring_mark") as MeshInstance3D
	_expect(ring.visible, "The red ring was not drawn.")
	_expect(Vector2(ring.global_position.x - observer.global_position.x, ring.global_position.z - observer.global_position.z).length() < 0.05, "The red ring is not where the protagonist stands.")
	_expect_walked(q, q_before, curtain_started, "Q jumped to the window.")
	_expect(int(q.get("place")) == 1 and bool(q.call("is_walking")), "Q does not walk over to the window.")
	_expect(StringName(scene.call("current_interaction")[0]) == &"curtain", "The open curtain offers no way to lean out.")
	scene.call("_fall")
	await _wait(3.2)
	var landing: Vector3 = _room_const("LANDING")
	_expect(observer.global_position.distance_to(landing) < 0.6, "The fall did not land in the yard (at %s)." % str(observer.global_position))
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
