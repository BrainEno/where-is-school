extends SceneTree
## The classroom visual slice: the painted room is still the room it was.
##
## The art pass replaced the graybox classroom's look - painted walls and floor, a colour
## system of its own, restyled board, windows and teacher's desk - and none of that is
## allowed to cost the room anything a player relies on. The claims under test:
##
## 1. **A larger room.** A 14 x 10 m shell contains twelve desks, two doors on the east
##    wall (issue #159), a roll-down screen over the board, a ceiling projector, a
##    step-up concrete platform, a curved lectern, the original story props and exits.
##    The blackboard wall is one unbroken wall; the schoolbag hangs on your chair.
## 2. **Only purposeful solids.** The floor, the five walls (each one whole collision box,
##    door openings and the back window included), platform/step, twelve desk wrappers
##    and teacher desk are the only scene-owned collision bodies.
## 3. **Its own colour system.** Every surface of the room draws a material from
##    `assets/materials/classroom/` (the shared ceiling-light material is the one
##    exception), nothing reaches into another agent's shader folder, and the imported
##    desk model replaces photographic PBR with an opaque classroom pigment surface.
## 4. **Wall decoration fades with the wall.** Each wall's painted face and the dressing
##    hung on it are children of the wall body, so the camera occluder fades them with it.
## 5. **Textures within budget.** Every painted texture is the project's own, lives with
##    the classroom materials, and stays under the per-file warning budget.
## 6. **Hierarchy.** The background planes are quiet, and each object the player is meant
##    to look at separates from what stands behind it in value or in colour.
## 7. **The inspection texts are true.** What the texts describe - the broken chalk and
##    the clip, the cracked pane, the teacher's chair, the marks on your desk, the taped
##    set square, the one strap - is in the scene.
## 8. **The real camera.** From the game's own camera rig, at every standing spot in the
##    room, the board and the windows never stand between the camera and the player, and
##    the ceiling projector thins out wherever it would; the furniture reads at a sensible
##    size next to the characters.
## 9. **Navigation.** The baked mesh reaches every desk and every interactable from the
##    spawn.

const Harness = preload("res://tests/test_harness.gd")
const WallContract = preload("res://tests/classroom_wall_contract.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CLASSROOM_MATERIALS := "res://assets/materials/classroom/"
const CLASSROOM_TEXTURES := "res://assets/materials/classroom/textures/"
## Shared materials the room may still use, each for a reason: the ceiling fittings are
## the same light panels the corridor hangs, and they are not part of the colour system.
const SHARED_MATERIALS: Array[String] = ["res://assets/materials/light_panel.tres"]
## No material presets are borrowed from another scene. The classroom student-wood
## material may reference the existing environment shader read-only (owner task direction).
const FOREIGN_PREFIXES: Array[String] = ["res://assets/shaders/"]
const DESK_SURFACE := "res://assets/materials/classroom/student_wood.tres"
## tools/verify_build.py: the texture warning budget, per file.
const TEXTURE_WARN_BYTES := 512 * 1024
const TEXTURE_MAX_SIDE := 2048

const FLOOR_SIZE := Vector3(14.0, 0.2, 10.0)
const WALLS := {
	"WallNorth": Vector3(0.0, 1.6, -4.9),
	"WallWest": Vector3(-6.9, 1.6, 0.0),
	"WallEast": Vector3(6.9, 1.6, 0.0),
	"WallSouthLeft": Vector3(-3.5, 1.6, 4.9),
	"WallSouthRight": Vector3(3.5, 1.6, 4.9),
}
const DESKS := {
	"DeskA1": Vector3(-4.8, 0.0, -0.8),
	"DeskA2": Vector3(-1.6, 0.0, -0.8),
	"DeskA3": Vector3(1.6, 0.0, -0.8),
	"DeskA4": Vector3(4.8, 0.0, -0.8),
	"DeskB1": Vector3(-4.8, 0.0, 1.3),
	"DeskB2": Vector3(-1.6, 0.0, 1.3),
	"DeskB3": Vector3(1.6, 0.0, 1.3),
	"DeskB4": Vector3(4.8, 0.0, 1.3),
	"DeskC1": Vector3(-4.8, 0.0, 3.4),
	"DeskC2": Vector3(-1.6, 0.0, 3.4),
	"DeskC3": Vector3(1.6, 0.0, 3.4),
	"DeskC4": Vector3(4.8, 0.0, 3.4),
}
const PROPS := {
	"Furniture/FrontDesk": Vector3(-4.65, 0.0, -2.2),
	"Props/Blackboard": Vector3(-1.6, 0.0, -4.75),
	"Props/SetSquare": Vector3(-4.25, 0.81, -2.1),
	"Furniture/DeskB2/Chair/Schoolbag": Vector3(0.0, 0.5, 0.34),
	"Actors/Q": Vector3(-3.3, 0.0, 3.1),
	# Where Q walks to before the first line (OpeningSequence, #160): the aisle at your left.
	"QOpeningTalk": Vector3(-2.75, 0.0, 1.95),
	"Actors/N": Vector3(3.2, 0.0, 4.2),
	"SpawnPoints/PlayerStart": Vector3(-1.6, 0.0, 1.95),
	"SpawnPoints/FromCorridor": Vector3(6.25, 0.0, -3.55),
	"WallEast/FrontDoor": Vector3(-0.04, -1.6, -3.55),
	"WallEast/RearDoor": Vector3(-0.04, -1.6, 3.55),
	"WallNorth/ProjectorScreen": Vector3(-2.9, 1.02, 0.35),
	"CeilingProjector": Vector3(-2.9, 3.2, -0.9),
	"Anomalies/BackCurtain": Vector3(-6.62, 3.14, 2.2),
}
const INTERACTABLES := {
	"blackboard": Vector3(-1.6, 0.6, -4.25),
	"set_square": Vector3(-4.0, 0.6, -1.45),
	"front_desk": Vector3(-4.4, 0.5, -1.7),
	"window": Vector3(-6.0, 0.6, 0.0),
	"own_desk": Vector3(-1.6, 0.4, 1.3),
	"schoolbag": Vector3(-1.6, 0.55, 2.3),
	"timetable": Vector3(0.0, 0.6, 4.3),
	"q_talk": Vector3(-3.3, 0.8, 3.1),
	"classroom_door": Vector3(6.35, 0.6, -3.55),
	"rear_door": Vector3(6.35, 0.6, 3.55),
	"curtain": Vector3(-5.95, 0.6, 2.2),
	"projector_screen": Vector3(-2.9, 0.7, -4.15),
}
const SOLIDS: Array[String] = [
	"Floor", "WallNorth", "WallWest", "WallEast", "WallSouthLeft", "WallSouthRight",
	"Stage",
	"Furniture/DeskA1/Desk", "Furniture/DeskA2/Desk", "Furniture/DeskA3/Desk", "Furniture/DeskA4/Desk",
	"Furniture/DeskB1/Desk", "Furniture/DeskB2/Desk", "Furniture/DeskB3/Desk", "Furniture/DeskB4/Desk",
	"Furniture/DeskC1/Desk", "Furniture/DeskC2/Desk", "Furniture/DeskC3/Desk", "Furniture/DeskC4/Desk",
	"Furniture/FrontDesk/Body",
]
## Each wall's painted face and the material it has to carry.
const WALL_PAINT := {
	"WallNorth": "wall_north.tres",
	"WallWest": "wall_west.tres",
	"WallEast": "wall_east.tres",
	"WallSouthLeft": "wall_south_left.tres",
	"WallSouthRight": "wall_south_right.tres",
}
## The east and west walls' extra painted pieces around their openings: each samples its
## own slice of the wall's painted texture (art/classroom/paint_classroom_textures.py).
const WALL_PAINT_SEGMENTS := {
	"WallEast/PaintFront": "wall_east_front.tres",
	"WallEast/PaintBack": "wall_east_back.tres",
	"WallEast/PaintLintelFront": "wall_east_lintel_front.tres",
	"WallEast/PaintLintelBack": "wall_east_lintel_back.tres",
	"WallWest/PaintSouth": "wall_west_south.tres",
	"WallWest/PaintSill": "wall_west_sill.tres",
	"WallWest/PaintHeader": "wall_west_header.tres",
}
## Each wall's one collision box: the openings are visual only.
const WALL_COLLISION := {
	"WallNorth": Vector3(14.0, 3.2, 0.2),
	"WallWest": Vector3(0.2, 3.2, 10.0),
	"WallEast": Vector3(0.2, 3.2, 10.0),
}

const HIERARCHY_PAIRS := [
	["board_face", "wall_north", "the board against the front wall"],
	["lacquer_oxblood", "wall_north", "the board frame and the teacher's desk front"],
	["canvas_mustard", "wood_worn", "the schoolbag on the chair back"],
	["window_view_front", "wall_west", "the window against its wall"],
	["varnish_pale", "wood_honey", "the set square on the teacher's desk top"],
	["register_cover", "wood_honey", "the register on the teacher's desk top"],
	["trim_teal", "wall_east", "the door frames against the east wall"],
	["door_white", "wall_east", "the white rear door against the east wall"],
	["curtain_blackout", "wall_west", "the blackout curtain against the west wall"],
	["screen_matte", "board_face", "the rolled-down screen over the board"],
]
const HIERARCHY_MIN := 0.15
## Broad planes stay quiet: walls and floor below this colourfulness (max - min, sRGB).
const BACKGROUND_PLANES: Array[String] = [
	"wall_north", "wall_west", "wall_east", "wall_south_left", "floor_paint",
]
const BACKGROUND_CHROMA_MAX := 0.2
## Twelve chairs must not be louder than the one schoolbag.
const CHAIR_MATERIAL := "wood_worn"
const FOCUS_OVER_CHAIRS := "canvas_mustard"

## Meshes that hang on a wall without being parented to it; the camera never fades
## them, so they must never be between the camera and the player.
const NEVER_FADED: Array[String] = [
	"Props/Blackboard", "WindowGlow0", "WindowGlass0", "WindowFrameTop0",
	"WindowFrameBottom0", "WindowFrameLeft0", "WindowFrameRight0", "WindowMullion0",
	"ClockFace",
	"ClockHandHour", "ClockHandMinute", "Fitting0", "Fitting1",
]
## Body points sampled from the camera: shins, waist, eye line.
const BODY_HEIGHTS: Array[float] = [0.3, 0.9, 1.5]
const STAND_GRID_STEP := 0.5
const SCREEN_HEIGHT := 900.0
## A person stands roughly twice as tall as a school desk; outside this band one of the
## two is at the wrong scale.
const PERSON_TO_DESK_MIN := 1.55
const PERSON_TO_DESK_MAX := 2.4
## At the game camera's distance, a desk smaller than this on a 900-line screen stops
## reading as furniture.
const DESK_MIN_PIXELS := 45.0
## A desk counts as reachable when the walkable floor comes this close to its chair.
const DESK_REACH := 1.0

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _room: Node3D = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "classroom_visual_slice_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _physics_frames(3)

	var host := _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	if host == null or _player == null:
		Harness.finish(self, ["Main did not expose the location host or the player."], "")
		return
	if host.get_current_path() != CLASSROOM or host.get_current() == null:
		if not host.load_location(CLASSROOM, &"PlayerStart", _player):
			Harness.finish(self, ["The classroom could not be entered."], "")
			return
		await _physics_frames(3)
	_room = host.get_current()
	if _room == null:
		Harness.finish(self, ["The host reports no current location."], "")
		return
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	await _physics_frames(2)

	Harness.stage = "layout"
	_check_layout()
	Harness.stage = "collision"
	_check_collision()
	Harness.stage = "colour system"
	_check_colour_system()
	Harness.stage = "wall dressing"
	_check_wall_dressing()
	Harness.stage = "textures"
	_check_textures()
	Harness.stage = "cool concrete floor"
	_check_floor_art()
	Harness.stage = "hierarchy"
	_check_hierarchy()
	Harness.stage = "inspection agreement"
	_check_inspection_agreement()
	Harness.stage = "navigation"
	var navigation := await _check_navigation()
	Harness.stage = "live wall rendering contract"
	await WallContract.verify(self, _main, _room, _failures)
	Harness.stage = "game camera"
	await _check_game_camera(navigation)

	print("::notice title=classroom visual slice::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		"the expanded classroom layout, colliders, interactables and navigation satisfy the slice, "
		+ "draws only its own materials and keeps the board and windows out of the "
		+ "camera's way.",
	)


# --- 1. layout ----------------------------------------------------------------------


func _check_layout() -> void:
	for required: String in ["Sun", "WorldEnvironment", "Navigation", "Floor"]:
		if _room.get_node_or_null(required) == null:
			_failures.append("The classroom lost its '%s' node." % required)
	var floor_shape := _room.get_node_or_null(^"Floor/CollisionShape3D") as CollisionShape3D
	var floor_box: BoxShape3D = null
	if floor_shape != null:
		floor_box = floor_shape.shape as BoxShape3D
	if floor_box == null or not floor_box.size.is_equal_approx(FLOOR_SIZE):
		_failures.append("The classroom floor is no longer the 14 x 10 m room.")
	for wall_name: String in WALLS:
		_expect_at(wall_name, WALLS[wall_name])
	for desk_name: String in DESKS:
		_expect_at("Furniture/%s" % desk_name, DESKS[desk_name])
	for path: String in PROPS:
		_expect_at(path, PROPS[path])
	for wall_name: String in WALL_COLLISION:
		var shapes := _room.get_node(NodePath(wall_name)).find_children(
			"*", "CollisionShape3D", true, false
		)
		var box := (shapes[0] as CollisionShape3D).shape as BoxShape3D if shapes.size() == 1 else null
		if box == null or not box.size.is_equal_approx(WALL_COLLISION[wall_name]):
			_failures.append("'%s' is no longer one whole collision box." % wall_name)
	for removed: String in [
		"DoorLintel", "AnomalyDoorLintel", "DoorFrameHead", "AnomalyDoorFrameHead", "Threshold",
		"WallNorth/RearDoorAnomalyMount", "WallNorth/PaintCenter", "WallNorth/PaintRight",
		"WindowGlass1", "Anomalies/Staircase",
	]:
		if _room.get_node_or_null(NodePath(removed)) != null:
			_failures.append("'%s' is still in the room; issue #159 took it out." % removed)
	var glass0 := _room.get_node_or_null(^"WindowGlass0") as MeshInstance3D
	if glass0 == null or not is_equal_approx(glass0.position.x, -6.74):
		_failures.append("The front west-wall window must remain in the room shell.")
	if DESKS.size() < 12:
		_failures.append("The layout has only %d authored student desks; twelve are required." % DESKS.size())
	var normal_door := _room.get_node_or_null(^"Interactables/ClassroomDoor") as LocationExit
	if normal_door == null or normal_door.interact_id != &"classroom_door":
		_failures.append("The normal exit lost its classroom_door ID.")
	elif normal_door.destination_id != &"corridor" or normal_door.destination_scene != "res://scenes/locations/corridor/corridor.tscn":
		_failures.append("classroom_door no longer routes to the corridor.")
	var front_door := _room.get_node_or_null(^"WallEast/FrontDoor") as ClassroomDoorDressing
	var rear_door := _room.get_node_or_null(^"WallEast/RearDoor") as ClassroomDoorDressing
	if front_door == null or rear_door == null:
		_failures.append("The east wall lost one of its two dressed doors.")
	elif front_door.global_position.z >= rear_door.global_position.z:
		_failures.append("The grey door is not the front (blackboard-end) door.")
	var bag := _room.get_node_or_null(^"Furniture/DeskB2/Chair/Schoolbag") as Node3D
	if bag != null:
		var bag_box := _subtree_aabb(bag)
		if bag_box.position.y < 0.3:
			_failures.append("The schoolbag %s is on the floor, not on the chair back." % str(bag_box))
	if _room.get_node_or_null(^"Props/Schoolbag") != null:
		_failures.append("A schoolbag is still on the floor.")
	for mount: Array in [
		["WindowCurtainMount0", Vector3(-6.55, 2.5, -2.4)],
		["WindowCurtainMount1", Vector3(-6.62, 3.14, 2.2)],
	]:
		var marker := _room.get_node_or_null(NodePath(mount[0])) as Marker3D
		if marker == null or not marker.position.is_equal_approx(mount[1]):
			_failures.append("The west-window curtain mount '%s' is missing or misplaced." % mount[0])
	var stage_shape := _room.get_node_or_null(^"Stage/CollisionShape3D") as CollisionShape3D
	var stage_box := stage_shape.shape as BoxShape3D if stage_shape != null else null
	var step_shape := _room.get_node_or_null(^"Stage/StepCollision") as CollisionShape3D
	var step_box := step_shape.shape as BoxShape3D if step_shape != null else null
	if stage_box == null or not stage_box.size.is_equal_approx(Vector3(6.8, 0.12, 2.5)):
		_failures.append("The raised concrete platform is missing its real 0.12 m collision surface.")
	if step_box == null or step_box.size.y > _player.max_step_height:
		_failures.append("The platform's physical front step is taller than the player's step-up limit.")
	var lectern := _room.get_node_or_null(^"Stage/Lectern") as Node3D
	var lectern_top := lectern.get_node_or_null(^"CurvedTop") as MeshInstance3D if lectern != null else null
	if lectern_top == null or not lectern_top.mesh is CylinderMesh:
		_failures.append("The raised platform lacks a distinctly curved high teacher's lectern.")
	else:
		var lectern_bounds := _subtree_aabb(lectern)
		var desk_node := _room.get_node(^"Furniture/DeskB2") as Node3D
		var desk_bounds := _subtree_aabb(desk_node.get_node(^"Desk"))
		if lectern_bounds.end.y < desk_bounds.end.y + 0.15:
			_failures.append("The curved lectern is not meaningfully taller than a student desk.")

	var found := {}
	var interactables := _room.get_node_or_null(^"Interactables")
	if interactables == null:
		_failures.append("The classroom lost its Interactables node.")
		return
	for child in interactables.get_children():
		var id := String(child.get("interact_id"))
		if INTERACTABLES.has(id):
			found[id] = true
			var node := child as Node3D
			if not node.global_position.is_equal_approx(_room.to_global(INTERACTABLES[id])):
				_failures.append(
					"Interactable '%s' moved to %s; it was authored at %s."
					% [id, str(node.position), str(INTERACTABLES[id])]
				)
	for id: String in INTERACTABLES:
		if not found.has(id):
			_failures.append("The classroom lost the '%s' interactable." % id)


func _expect_at(path: String, expected: Vector3) -> void:
	var node := _room.get_node_or_null(NodePath(path)) as Node3D
	if node == null:
		_failures.append("The classroom lost '%s'." % path)
		return
	if not node.position.is_equal_approx(expected):
		_failures.append(
			"'%s' stands at %s; the room has it at %s." % [path, str(node.position), str(expected)]
		)


# --- 2. collision -------------------------------------------------------------------


func _check_collision() -> void:
	var found := {}
	for node in _descendants(_room):
		if not node is CollisionObject3D:
			continue
		var path := _relative(node)
		if path.begins_with("Interactables/") or path.begins_with("Actors/"):
			continue
		if not SOLIDS.has(path):
			_failures.append(
				"'%s' collides. Classroom decoration carries no collision: it would carve the "
				% path
				+ "navigation mesh and block interaction rays."
			)
			continue
		found[path] = true
	for path: String in SOLIDS:
		if not found.has(path):
			_failures.append("'%s' no longer collides; the room's solids changed." % path)
	_notes.append("solids %d" % found.size())


# --- 3. colour system ---------------------------------------------------------------


func _check_colour_system() -> void:
	var used := {}
	var surfaces := 0
	for node in _descendants(_room):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var path := _relative(node)
		if path.begins_with("Actors/") or path.begins_with("Interactables/"):
			continue
		if path.contains("/Stationery"):
			continue
		var desk_model := _is_desk_model(path)
		if desk_model:
			var replacement := mesh_instance.material_override as ShaderMaterial
			if replacement == null or replacement.resource_path != DESK_SURFACE:
				_failures.append("The imported desk mesh '%s' kept its photographic PBR surface." % path)
			elif replacement.shader.resource_path != "res://assets/shaders/painterly/environment_surface.gdshader":
				_failures.append("The desk '%s' does not reuse the reviewed environment shader." % path)
			elif bool(replacement.get_shader_parameter("use_base_texture")):
				_failures.append("The desk '%s' still samples the photographic albedo." % path)
			if mesh_instance.material_overlay != null:
				_failures.append("The imported desk mesh '%s' still has a redundant alpha wash." % path)
		for surface in mesh_instance.mesh.get_surface_count():
			surfaces += 1
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				_failures.append("'%s' surface %d draws with no material." % [path, surface])
				continue
			var resource_path := material.resource_path
			if not resource_path.begins_with(CLASSROOM_MATERIALS) and not SHARED_MATERIALS.has(resource_path):
				_failures.append(
					"'%s' draws '%s', which is not part of the classroom's colour system."
					% [path, resource_path if not resource_path.is_empty() else "<embedded>"]
				)
			used[resource_path] = true
	for resource_path: String in used:
		var material := load(resource_path) as Material
		while material != null:
			for prefix: String in FOREIGN_PREFIXES:
				if material.resource_path.begins_with(prefix):
					_failures.append("The classroom depends on '%s'." % material.resource_path)
			var standard := material as BaseMaterial3D
			if standard != null and standard.albedo_texture != null:
				for prefix: String in FOREIGN_PREFIXES:
					if standard.albedo_texture.resource_path.begins_with(prefix):
						_failures.append(
							"'%s' samples '%s'." % [resource_path, standard.albedo_texture.resource_path]
						)
			material = material.next_pass
	_notes.append("%d surfaces, %d materials" % [surfaces, used.size()])


func _is_desk_model(path: String) -> bool:
	for desk_name: String in DESKS:
		if path.begins_with("Furniture/%s/Desk/" % desk_name):
			return true
	return false


# --- 4. wall dressing ---------------------------------------------------------------


func _check_wall_dressing() -> void:
	for wall_name: String in WALL_PAINT:
		var wall := _room.get_node_or_null(NodePath(wall_name)) as CollisionObject3D
		if wall == null:
			continue
		if not wall.is_in_group("camera_occluder"):
			_failures.append("'%s' left the camera_occluder group; it would never fade." % wall_name)
		var paint := wall.get_node_or_null(^"Paint") as MeshInstance3D
		if paint == null:
			_failures.append("'%s' has no painted face." % wall_name)
			continue
		var material := paint.get_active_material(0)
		var expected: String = CLASSROOM_MATERIALS + WALL_PAINT[wall_name]
		if material == null or material.resource_path != expected:
			_failures.append("'%s/Paint' does not carry %s." % [wall_name, expected])
	for path: String in WALL_PAINT_SEGMENTS:
		var segment := _room.get_node_or_null(NodePath(path)) as MeshInstance3D
		if segment == null or segment.material_override == null or not segment.material_override.resource_path.ends_with(WALL_PAINT_SEGMENTS[path]):
			_failures.append("The wall piece '%s' does not keep its metric UV slice." % path)
	for pair: Array in [
		["WallNorth", "FrontWallDressing"], ["WallSouthLeft", "BackBoard"],
		["WallNorth", "ProjectorScreen"], ["WallEast", "FrontDoor"], ["WallEast", "RearDoor"],
	]:
		var dressing := _room.get_node_or_null(NodePath("%s/%s" % [pair[0], pair[1]]))
		if dressing == null:
			_failures.append(
				"'%s' is not hung on '%s', so it would not fade with the wall." % [pair[1], pair[0]]
			)
	# The fader collects every GeometryInstance3D under a wall; make sure it will.
	var north := _room.get_node_or_null(^"WallNorth")
	if north != null:
		var geometry := north.find_children("*", "GeometryInstance3D", true, false)
		# The shell, its painted face, one clock dial and the screen's pieces.
		# The red pseudo-writing banner AND pins stay absent, not hidden in the tree.
		if geometry.size() < 6:
			_failures.append("WallNorth has only %d meshes; its face or the screen is missing." % geometry.size())
		var dressing := north.get_node("FrontWallDressing")
		if dressing.get_child_count() != 1 or not dressing.has_node("ClockDial"):
			_failures.append("FrontWallDressing must retain only the meaningful clock dial.")
	for removed: String in ["banner.tres", "textures/banner.png", "textures/banner.png.import"]:
		if FileAccess.file_exists(CLASSROOM_MATERIALS + removed):
			_failures.append("Removed decoration resource still exists: %s" % removed)


# --- 5. textures --------------------------------------------------------------------


func _check_textures() -> void:
	var textures := {}
	for path in _classroom_material_paths():
		var material := load(path) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			textures[material.albedo_texture.resource_path] = material.albedo_texture
	var total := 0
	for texture_path: String in textures:
		var texture: Texture2D = textures[texture_path]
		if not texture_path.begins_with(CLASSROOM_TEXTURES):
			_failures.append("A classroom material samples '%s' from outside its folder." % texture_path)
		var file := FileAccess.open(texture_path, FileAccess.READ)
		var size := -1
		if file != null:
			size = file.get_length()
			file.close()
		if size < 0:
			_failures.append("'%s' has no source file." % texture_path)
		elif size > TEXTURE_WARN_BYTES:
			_failures.append(
				"'%s' is %d KiB, over the %d KiB texture budget."
				% [texture_path, size / 1024, TEXTURE_WARN_BYTES / 1024]
			)
		total += maxi(size, 0)
		if texture.get_width() > TEXTURE_MAX_SIDE or texture.get_height() > TEXTURE_MAX_SIDE:
			_failures.append(
				"'%s' is %dx%d; no side may exceed %d."
				% [texture_path, texture.get_width(), texture.get_height(), TEXTURE_MAX_SIDE]
			)
	if textures.is_empty():
		_failures.append("No classroom material samples a painted texture.")
	_notes.append("%d textures, %d KiB source" % [textures.size(), total / 1024])


func _check_floor_art() -> void:
	var material := load(CLASSROOM_MATERIALS + "floor_paint.tres") as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		_failures.append("The expanded room has no generated floor paint texture.")
		return
	var texture := material.albedo_texture
	if texture.resource_path != CLASSROOM_TEXTURES + "floor.png":
		_failures.append("The floor stopped sampling its classroom-owned generated paint source.")
	if not is_equal_approx(float(texture.get_width()) / float(texture.get_height()), 1.4):
		_failures.append("The floor paint source no longer matches the 14 x 10 m room aspect.")
	var mean := _texture_mean(texture.resource_path)
	if mean.b <= mean.r or mean.r > 0.58 or _chroma(mean) > 0.14:
		_failures.append(
			"The floor source is not low-saturation cool concrete (mean RGB %.2f, %.2f, %.2f)."
			% [mean.r, mean.g, mean.b]
		)
	else:
		_notes.append("cool concrete floor %.2f/%.2f/%.2f" % [mean.r, mean.g, mean.b])


func _classroom_material_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(CLASSROOM_MATERIALS)
	if dir == null:
		_failures.append("%s cannot be listed." % CLASSROOM_MATERIALS)
		return paths
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			paths.append(CLASSROOM_MATERIALS + clean)
	return paths


# --- 6. hierarchy -------------------------------------------------------------------


func _check_hierarchy() -> void:
	var cache := {}
	for plane: String in BACKGROUND_PLANES:
		var colour := _material_colour(plane, cache)
		if _chroma(colour) > BACKGROUND_CHROMA_MAX:
			_failures.append(
				"The background plane '%s' is too loud (colourfulness %.2f > %.2f)."
				% [plane, _chroma(colour), BACKGROUND_CHROMA_MAX]
			)
	var lines: Array[String] = []
	for pair: Array in HIERARCHY_PAIRS:
		var focus := _material_colour(pair[0], cache)
		var backdrop := _material_colour(pair[1], cache)
		var value_gap := absf(_luminance(focus) - _luminance(backdrop))
		var colour_gap := _chroma(focus) - _chroma(backdrop)
		var separation := maxf(value_gap, colour_gap)
		lines.append("%s/%s %.2f" % [pair[0], pair[1], separation])
		if separation < HIERARCHY_MIN:
			_failures.append(
				"%s does not stand out: value gap %.2f, colour gap %.2f (need %.2f)."
				% [pair[2], value_gap, colour_gap, HIERARCHY_MIN]
			)
	var chairs := _chroma(_material_colour(CHAIR_MATERIAL, cache))
	var bag := _chroma(_material_colour(FOCUS_OVER_CHAIRS, cache))
	if bag - chairs < HIERARCHY_MIN:
		_failures.append(
			"The student chairs (colourfulness %.2f) compete with the schoolbag (%.2f)."
			% [chairs, bag]
		)
	_notes.append("hierarchy " + ", ".join(lines))


## The colour a material reads as from a distance: its albedo, times the average of its
## painted texture when it has one (read from the source image the texture was imported
## from, which is what the eye averages).
func _material_colour(material_name: String, cache: Dictionary) -> Color:
	if cache.has(material_name):
		return cache[material_name]
	var path := CLASSROOM_MATERIALS + material_name + ".tres"
	var material := load(path) as BaseMaterial3D
	if material == null:
		_failures.append("The colour system names '%s', which does not load." % path)
		cache[material_name] = Color.BLACK
		return Color.BLACK
	var colour := material.albedo_color
	if material.albedo_texture != null:
		var mean := _texture_mean(material.albedo_texture.resource_path)
		colour = Color(colour.r * mean.r, colour.g * mean.g, colour.b * mean.b, 1.0)
	cache[material_name] = colour
	return colour


func _texture_mean(texture_path: String) -> Color:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(texture_path))
	if error != OK or image.is_empty():
		_failures.append("The painted texture '%s' could not be read." % texture_path)
		return Color.WHITE
	image.convert(Image.FORMAT_RGBA8)
	image.resize(64, 32, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	var weight := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			sum += Vector3(pixel.r, pixel.g, pixel.b) * pixel.a
			weight += pixel.a
	if weight <= 0.0:
		return Color.WHITE
	sum /= weight
	return Color(sum.x, sum.y, sum.z, 1.0)


func _luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


func _chroma(colour: Color) -> float:
	return maxf(colour.r, maxf(colour.g, colour.b)) - minf(colour.r, minf(colour.g, colour.b))


# --- 7. inspection agreement --------------------------------------------------------


func _check_inspection_agreement() -> void:
	var expectations := {
		"Props/Blackboard/ChalkBrokenEnd": "the broken stick of chalk on the tray",
		"Props/Blackboard/Clip": "the clip that has lost its board",
		"Props/Blackboard/Board/Face": "the wiped-not-quite board face",
		"Furniture/FrontDesk/Chair": "the teacher's chair, pushed in at an angle",
		"Furniture/FrontDesk/Body/Register": "the register in its plastic cover",
		"Furniture/FrontDesk/Body/Stapler": "the stapler",
		"Furniture/FrontDesk/Body/Mug": "the mug of chalk",
		"Furniture/DeskB2/DeskMarks": "the cut-in name, the sticker and the groove",
		"Props/SetSquare/TapeRepair": "the browned tape on the split corner",
		"TimetableSheet/Face": "the timetable's printed face",
	}
	for path: String in expectations:
		if _room.get_node_or_null(NodePath(path)) == null:
			_failures.append(
				"The inspection text describes %s, and '%s' is missing." % [expectations[path], path]
			)
	var glass := _room.get_node_or_null(^"WindowGlass0") as MeshInstance3D
	if glass == null or glass.material_override == null or not glass.material_override.resource_path.ends_with("glass_cracked.tres"):
		_failures.append("The window's cracked, taped pane is not drawn.")
	var bag := _room.get_node_or_null(^"Furniture/DeskB2/Chair/Schoolbag")
	var q_talk := _room.get_node_or_null(^"Interactables/QTalk")
	if q_talk == null or StringName(q_talk.get("conversation_route")) != &"q":
		_failures.append("The original Q conversation interaction no longer routes to Q.")
	var q_actor := _room.get_node_or_null(^"Actors/Q") as Node3D
	var n_actor := _room.get_node_or_null(^"Actors/N") as Node3D
	if q_actor == null or not q_actor.visible or n_actor == null or n_actor.visible:
		_failures.append("The initial Q/N classroom story states have changed.")
	var normal_exit := _room.get_node_or_null(^"Interactables/ClassroomDoor") as LocationExit
	if normal_exit == null or normal_exit.blocked_inspection_id != &"classroom_door_blocked":
		_failures.append("The normal door lost its existing blocked-exit inspection.")
	if bag != null:
		var straps := 0
		for child in bag.get_children():
			if String(child.name).begins_with("Strap"):
				straps += 1
		if straps != 1:
			_failures.append("The schoolbag has %d straps; the text says one." % straps)
	# The set square lies flat: forearm-long, a few centimetres thick.
	var square := _room.get_node_or_null(^"Props/SetSquare") as Node3D
	if square != null:
		var box := _subtree_aabb(square)
		if box.size.y > 0.08 or maxf(box.size.x, box.size.z) < 0.4:
			_failures.append(
				"The set square is %.2f x %.2f x %.2f m; it should lie flat on the desk corner."
				% [box.size.x, box.size.y, box.size.z]
			)


# --- 9. navigation ------------------------------------------------------------------


func _check_navigation() -> LocationNavigation:
	var navigation := _room.get_node_or_null(^"Navigation") as LocationNavigation
	if navigation == null:
		_failures.append("The classroom has no Navigation region.")
		return null
	var synchronized: bool = await navigation.wait_until_synchronized()
	if not synchronized:
		_failures.append("The classroom navigation never synchronized: %s" % navigation.describe_sync())
		return null
	var map := navigation.get_navigation_map()
	var start_marker := _room.get_node_or_null(^"SpawnPoints/PlayerStart") as Node3D
	var start := NavigationServer3D.map_get_closest_point(map, start_marker.global_position)
	var stage_top := _room.to_global(Vector3(0.0, 0.12, -3.65))
	var stage_gap := _route_gap(map, start, stage_top)
	if stage_gap > 0.25:
		_failures.append("The navigation mesh does not join the floor to the raised platform step (%.2f m)." % stage_gap)
	var worst := 0.0
	for desk_name: String in DESKS:
		var desk := _room.get_node_or_null(NodePath("Furniture/%s" % desk_name)) as Node3D
		if desk == null:
			continue
		var chair := desk.to_global(Vector3(0.0, 0.0, 0.58))
		var reach := _route_gap(map, start, chair)
		worst = maxf(worst, reach)
		if reach > DESK_REACH:
			_failures.append(
				"%s cannot be reached: the nearest routed floor is %.2f m from its chair."
				% [desk_name, reach]
			)
	var interactables := _room.get_node_or_null(^"Interactables")
	for child in interactables.get_children():
		var node := child as Node3D
		var radius := float(child.get("radius"))
		var gap := _route_gap(map, start, node.global_position)
		if gap > radius + 0.25:
			_failures.append(
				"'%s' cannot be reached: the nearest routed floor is %.2f m away, its radius %.2f."
				% [String(child.get("interact_id")), gap, radius]
			)
	_notes.append(
		"nav polygons %d, twelve desks, step %.2f m, worst desk reach %.2f m" % [navigation.get_polygon_count(), stage_gap, worst]
	)
	return navigation


## How far from `target` a route that starts at `start` can end (horizontal metres). A
## route that cannot be built at all counts as infinitely far.
func _route_gap(map: RID, start: Vector3, target: Vector3) -> float:
	var goal := NavigationServer3D.map_get_closest_point(map, target)
	var route := NavigationServer3D.map_get_path(map, start, goal, true)
	if route.is_empty():
		return INF
	var end := route[route.size() - 1]
	return Vector2(end.x - target.x, end.z - target.z).length()


# --- 8. the game camera ----------------------------------------------------------------


func _check_game_camera(navigation: LocationNavigation) -> void:
	var rig := _main.get_node_or_null(^"CameraRig") as CameraRig
	if rig == null or rig.camera == null:
		_failures.append("Main has no CameraRig to look through.")
		return
	var camera := rig.camera
	var boxes := _never_faded_boxes()
	var start_position := _player.global_position
	var start_yaw := _player.global_rotation.y

	# Every standing spot on the walkable floor, on a half-metre grid.
	var spots: Array[Vector3] = []
	var map := navigation.get_navigation_map() if navigation != null else RID()
	var x := -6.25
	while x <= 6.25:
		var z := -4.25
		while z <= 4.25:
			var point := _room.to_global(Vector3(x, 0.0, z))
			if map.is_valid():
				var on_mesh := NavigationServer3D.map_get_closest_point(map, point)
				if Vector2(on_mesh.x - point.x, on_mesh.z - point.z).length() < 0.05:
					spots.append(on_mesh)
			else:
				spots.append(point)
			z += STAND_GRID_STEP
		x += STAND_GRID_STEP
	if spots.size() < 20:
		_failures.append("Only %d standing spots were found in the classroom." % spots.size())

	var blocked: Array[String] = []
	for spot in spots:
		_player.teleport(Transform3D(Basis(), spot))
		rig.snap()
		var eye := camera.global_position
		for height in BODY_HEIGHTS:
			var target := spot + Vector3(0.0, height, 0.0)
			for entry: Array in boxes:
				var box: AABB = entry[1]
				if box.intersects_segment(eye, target):
					blocked.append("%s hides the player at %s (h %.1f)" % [entry[0], str(spot), height])
	await _check_projector_thins(spots)
	for line in blocked.slice(0, 6):
		_failures.append(line)
	if blocked.size() > 6:
		_failures.append("... and %d more blocked views." % (blocked.size() - 6))

	# Scale: the desks and the characters through the same lens.
	var start_marker := _room.get_node_or_null(^"SpawnPoints/PlayerStart") as Node3D
	_player.teleport(Transform3D(Basis(), start_marker.global_position))
	rig.snap()
	var desk := _room.get_node_or_null(^"Furniture/DeskB2") as Node3D
	var desk_box := _subtree_aabb(desk.get_node(^"Desk"))
	var q := _room.get_node_or_null(^"Actors/Q") as Node3D
	var q_box := _subtree_aabb(q) if q != null else AABB()
	var player_visual := _player.get_node_or_null(^"VisualPivot/Visual")
	var player_box := _subtree_aabb(player_visual if player_visual != null else _player)
	var desk_pixels := _screen_height(camera, desk.global_position, desk_box.size.y)
	var q_pixels := _screen_height(camera, desk.global_position, q_box.size.y)
	if desk_pixels < DESK_MIN_PIXELS:
		_failures.append(
			"From the game camera a desk is %.0f px tall on a 900-line screen; it no longer "
			% desk_pixels
			+ "reads as furniture."
		)
	for entry: Array in [["Q", q_box.size.y], ["the player", player_box.size.y]]:
		var ratio: float = entry[1] / maxf(desk_box.size.y, 0.01)
		if ratio < PERSON_TO_DESK_MIN or ratio > PERSON_TO_DESK_MAX:
			_failures.append(
				"%s is %.2f m tall next to a %.2f m desk (ratio %.2f, expected %.2f-%.2f)."
				% [entry[0], entry[1], desk_box.size.y, ratio, PERSON_TO_DESK_MIN, PERSON_TO_DESK_MAX]
			)
	_notes.append(
		"%d standing spots checked; desk %.0f px, Q %.0f px; Q %.2f m, player %.2f m, desk %.2f m"
		% [spots.size(), desk_pixels, q_pixels, q_box.size.y, player_box.size.y, desk_box.size.y]
	)

	_player.teleport(Transform3D(Basis(Vector3.UP, start_yaw), start_position))
	rig.snap()
	await _physics_frames(1)


## The ceiling projector hangs where the camera looks down past it; wherever it would
## hide the player it has to thin out, and come back exactly as authored afterwards.
func _check_projector_thins(spots: Array[Vector3]) -> void:
	var projector := _room.get_node_or_null(^"CeilingProjector") as SeeThroughProp
	if projector == null:
		_failures.append("The ceiling projector is missing or does not thin out.")
		return
	var authored: Dictionary = {}
	for piece in projector.get_pieces():
		authored[piece] = piece.material_override
	var hiding := Vector3.INF
	for spot in spots:
		_player.teleport(Transform3D(Basis(), spot))
		var rig := _main.get_node(^"CameraRig") as CameraRig
		rig.snap()
		if projector.is_hiding(_player):
			hiding = spot
			break
	if hiding == Vector3.INF:
		_notes.append("the projector hides no standing spot")
		return
	await _physics_frames(30)
	if projector.get_opacity() > projector.see_through_alpha + 0.05:
		_failures.append(
			"Behind the projector at %s it stayed at %.2f opacity." % [str(hiding), projector.get_opacity()]
		)
	_notes.append("behind the projector at %s: opacity %.2f" % [str(hiding), projector.get_opacity()])
	var start := _room.get_node(^"SpawnPoints/PlayerStart") as Node3D
	_player.teleport(Transform3D(Basis(), start.global_position))
	(_main.get_node(^"CameraRig") as CameraRig).snap()
	await _physics_frames(40)
	if projector.get_opacity() < 0.999:
		_failures.append("The projector stayed thinned (%.2f) after the player left." % projector.get_opacity())
	for piece: MeshInstance3D in authored:
		if piece.material_override != authored[piece]:
			_failures.append("Projector piece '%s' did not get its material back." % piece.name)
			break


func _never_faded_boxes() -> Array:
	var boxes := []
	for path: String in NEVER_FADED:
		var node := _room.get_node_or_null(NodePath(path))
		if node == null:
			_failures.append("'%s' is gone; the camera check expected it." % path)
			continue
		var box := _subtree_aabb(node)
		if box.size == Vector3.ZERO:
			continue
		boxes.append([path, box])
	return boxes


## How tall something `height` metres high, standing at `base`, is on a 900-line screen
## through `camera`. Computed from the projection directly so it does not depend on the
## headless viewport's size.
func _screen_height(camera: Camera3D, base: Vector3, height: float) -> float:
	var view := camera.global_transform.affine_inverse()
	var bottom := view * base
	var top := view * (base + Vector3(0.0, height, 0.0))
	if bottom.z >= 0.0 or top.z >= 0.0:
		return 0.0
	var scale := (SCREEN_HEIGHT * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
	return absf(top.y / -top.z - bottom.y / -bottom.z) * scale


# --- helpers ------------------------------------------------------------------------


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			result.append(child)
			pending.append(child)
	return result


func _relative(node: Node) -> String:
	return String(_room.get_path_to(node))


func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
		# Meshes only, and only the ones drawn: a nameplate is a Label3D floating over the
		# head, and an actor's graybox body is hidden once its authored model is loaded.
		var mesh_instance := current as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.is_visible_in_tree():
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
