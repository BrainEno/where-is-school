extends SceneTree
## The classroom visual slice: the painted room is still the room it was.
##
## The art pass replaced the graybox classroom's look - painted walls and floor, a colour
## system of its own, restyled board, windows and teacher's desk - and none of that is
## allowed to cost the room anything a player relies on. The claims under test:
##
## 1. **Same room.** Floor, walls, door gap, desk grid, spawn points and every original
##    interactable are where they were, and `Sun` / `WorldEnvironment` still exist.
## 2. **No new solids.** The only collision bodies are the floor, the walls, the six
##    desk wrappers and the teacher's desk (plus whatever the interactables and actors
##    bring themselves). Decoration that collided would carve the baked navigation mesh
##    and block the interaction rays.
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
##    room, the board and the windows never stand between the camera and the player; the
##    furniture reads at a sensible size next to the characters.
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

const FLOOR_SIZE := Vector3(9.4, 0.2, 7.4)
const WALLS := {
	"WallNorth": Vector3(0.0, 1.6, -3.6),
	"WallWest": Vector3(-4.6, 1.6, 0.0),
	"WallEast": Vector3(4.6, 1.6, 0.0),
	"WallSouthLeft": Vector3(-1.0, 1.6, 3.6),
	"WallSouthRight": Vector3(4.2, 1.6, 3.6),
	"DoorLintel": Vector3(3.2, 2.65, 3.6),
}
const DESKS := {
	"DeskA1": Vector3(-2.5, 0.0, -1.5),
	"DeskA2": Vector3(0.0, 0.0, -1.5),
	"DeskA3": Vector3(2.5, 0.0, -1.5),
	"DeskB1": Vector3(-2.5, 0.0, 0.2),
	"DeskB2": Vector3(0.0, 0.0, 0.2),
	"DeskB3": Vector3(2.5, 0.0, 0.2),
}
const PROPS := {
	"Furniture/FrontDesk": Vector3(2.0, 0.0, -2.85),
	"Props/Blackboard": Vector3(0.2, 0.0, -3.45),
	"Props/SetSquare": Vector3(1.35, 0.81, -2.72),
	"Props/Schoolbag": Vector3(0.62, 0.0, 1.02),
	"Actors/Q": Vector3(-1.32, 0.0, 0.82),
	"SpawnPoints/PlayerStart": Vector3(0.0, 0.0, 0.85),
	"SpawnPoints/FromCorridor": Vector3(3.2, 0.0, 2.85),
}
const INTERACTABLES := {
	"blackboard": Vector3(0.2, 0.6, -3.0),
	"set_square": Vector3(1.35, 0.6, -2.5),
	"front_desk": Vector3(2.4, 0.5, -2.5),
	"window": Vector3(-3.9, 0.6, -0.2),
	"own_desk": Vector3(0.0, 0.4, 0.25),
	"schoolbag": Vector3(0.62, 0.2, 1.02),
	"timetable": Vector3(1.6, 0.6, 3.15),
	"q_talk": Vector3(-1.32, 0.8, 0.82),
	"classroom_door": Vector3(3.2, 0.6, 3.3),
}
const SOLIDS: Array[String] = [
	"Floor", "WallNorth", "WallWest", "WallEast", "WallSouthLeft", "WallSouthRight",
	"DoorLintel", "Furniture/DeskA1/Desk", "Furniture/DeskA2/Desk", "Furniture/DeskA3/Desk",
	"Furniture/DeskB1/Desk", "Furniture/DeskB2/Desk", "Furniture/DeskB3/Desk",
	"Furniture/FrontDesk/Body",
]
## Each wall's painted face and the material it has to carry.
const WALL_PAINT := {
	"WallNorth": "wall_north.tres",
	"WallWest": "wall_west.tres",
	"WallEast": "wall_east.tres",
	"WallSouthLeft": "wall_south_left.tres",
	"WallSouthRight": "wall_south_right.tres",
	"DoorLintel": "wall_south_lintel.tres",
}
## [focus material, backdrop material, why]. The focus has to separate from the backdrop
## by at least HIERARCHY_MIN in value or in colourfulness.
const HIERARCHY_PAIRS := [
	["board_face", "wall_north", "the board against the front wall"],
	["lacquer_oxblood", "wall_north", "the board frame and the teacher's desk front"],
	["canvas_mustard", "floor_paint", "the schoolbag on the floor"],
	["window_view_front", "wall_west", "the window against its wall"],
	["varnish_pale", "wood_honey", "the set square on the teacher's desk top"],
	["register_cover", "wood_honey", "the register on the teacher's desk top"],
	["lacquer_oxblood", "wall_south_left", "the door frame against the back wall"],
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
	"WindowGlow1", "WindowGlass1", "WindowFrameTop1", "WindowFrameBottom1",
	"WindowFrameLeft1", "WindowFrameRight1", "WindowMullion1", "ClockFace",
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
		"the painted classroom keeps its layout, colliders, interactables and navigation, "
		+ "draws only its own materials, and keeps the board and windows out of the "
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
		_failures.append("The classroom floor is no longer the 9.4 x 7.4 m room.")
	for wall_name: String in WALLS:
		_expect_at(wall_name, WALLS[wall_name])
	for desk_name: String in DESKS:
		_expect_at("Furniture/%s" % desk_name, DESKS[desk_name])
	for path: String in PROPS:
		_expect_at(path, PROPS[path])

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
	for pair: Array in [["WallNorth", "FrontWallDressing"], ["WallSouthLeft", "BackBoard"]]:
		var dressing := _room.get_node_or_null(NodePath("%s/%s" % [pair[0], pair[1]]))
		if dressing == null:
			_failures.append(
				"'%s' is not hung on '%s', so it would not fade with the wall." % [pair[1], pair[0]]
			)
	# The fader collects every GeometryInstance3D under a wall; make sure it will.
	var north := _room.get_node_or_null(^"WallNorth")
	if north != null:
		var geometry := north.find_children("*", "GeometryInstance3D", true, false)
		# Exactly shell + paint + clock face. The red pseudo-writing banner AND
		# its two pins are removed, not made transparent or hidden in the tree.
		if geometry.size() != 3:
			_failures.append("WallNorth has %d meshes, expected only shell, paint and clock dial." % geometry.size())
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
	var bag := _room.get_node_or_null(^"Props/Schoolbag")
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
		"nav polygons %d, worst desk reach %.2f m" % [navigation.get_polygon_count(), worst]
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
	var x := -4.25
	while x <= 4.25:
		var z := -3.25
		while z <= 3.25:
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
