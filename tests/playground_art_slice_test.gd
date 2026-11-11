extends SceneTree
## The schoolyard art slice: the painted yard is still the yard it was.
##
## Issue #82 repainted the graybox schoolyard (painted pours and seam, a hand-painted court,
## a local colour system, a flat painted distance, ring tyres, hoop rings, the far net). None
## of it may cost the yard anything a player relies on. The claims under test:
##
## 1. **Same yard.** Every collision body, interactable, exit and spawn keeps its place, shape,
##    id and destination from the base commit; Sun, WorldEnvironment and Navigation exist.
## 2. **No new solids.** Only the graybox's 33 bodies collide outside Interactables/:
##    colliding decoration would carve the navigation mesh and block interaction rays.
## 3. **Its own colour system.** Every drawn surface (the imported bench and bag aside) uses a
##    material from `playground_art/`; nothing reaches into `assets/materials/` or the Shader
##    Agent's painterly folders.
## 4. **Dressing fades with its wall.** Decals on the school wall and the container are
##    children of those occluders, so the camera fades them together.
## 5. **Textures within budget**, all from the slice's own texture folder.
## 6. **Hierarchy.** Broad planes stay quiet; what the player looks for stands out.
## 7. **The texts are true.** The green shed door with hasp and padlock, the newer concrete
##    round the near hoop and its missing net, the far hoop's net, the seam, the darker far
##    court half, the pale strip under the hedge, the duty sheet in the shed window: drawn.
## 8. **The real camera.** From the game's camera rig, nothing the slice added stands between
##    the camera and the player anywhere on the walkable yard, or between the camera and an
##    interactable the player walks up to; the painted distance stays out and casts no shadow.
## 9. **Navigation.** The baked mesh keeps the base polygon count and reaches every
##    interactable and exit from the gate.
## 10. **The HUD stays readable.** From every standing spot, rays through the pale HUD text
##    find what lies behind it; its estimated luminance gives the prompt a WCAG contrast of
##    4.5 and the top-left sentence 3.5 wherever that is the yard floor or the sky.

const Harness = preload("res://tests/test_harness.gd")

const PLAYGROUND := "res://scenes/locations/playground/playground.tscn"
const ART := "res://scenes/environment/props/playground_art/"
const ART_MATERIALS := "res://scenes/environment/props/playground_art/materials/"
const ART_TEXTURES := "res://scenes/environment/props/playground_art/textures/"
const FOREIGN_PREFIXES: Array[String] = [
	"res://assets/materials/", "res://assets/shaders/", "res://scenes/dev/painterly_lab/",
]
## Imported models keep their own materials; the art pass frames them from the ground.
const OWN_MATERIAL_PREFIXES: Array[String] = ["YardBench/", "YardBag/"]
const TEXTURE_WARN_BYTES := 512 * 1024
const TEXTURE_MAX_SIDE := 2048

## Every collision body at base commit 359ed4a: [position, collision box size].
const SOLIDS := {
	"YardGround": [Vector3(0, -0.1, 0), Vector3(46, 0.2, 40)],
	"SchoolBackWall": [Vector3(0, 6.0, -21), Vector3(46, 12, 2.0)],
	"SchoolPlinth": [Vector3(0, 0.6, -19.9), Vector3(46, 1.2, 0.4)],
	"FencePostGapWest": [Vector3(-8.4, 1.1, -18.6), Vector3(0.16, 2.2, 0.2)],
	"FencePostGapEast": [Vector3(-19.4, 1.1, -18.6), Vector3(0.16, 2.2, 0.2)],
	"SouthFenceWest": [Vector3(-12.5, 1.1, 19.6), Vector3(21, 2.2, 0.16)],
	"SouthFenceEast": [Vector3(12.5, 1.1, 19.6), Vector3(21, 2.2, 0.16)],
	"EstateBlockSouth": [Vector3(0, 5.0, 26), Vector3(46, 10, 8)],
	"EstateBlockEast": [Vector3(24, 6.0, -2), Vector3(8, 12, 40)],
	"HoopNearPole": [Vector3(-8.0, 1.6, 7.5), Vector3(0.18, 3.2, 0.18)],
	"HoopNearRim": [Vector3(-8.0, 2.6, 7.2), Vector3(0.05, 0.05, 0.45)],
	"HoopNearFooting": [Vector3(-8.0, 0.1, 7.5), Vector3(1.2, 0.2, 1.2)],
	"HoopFarPole": [Vector3(8.0, 1.6, -11.5), Vector3(0.18, 3.2, 0.18)],
	"HoopFarRim": [Vector3(8.0, 2.6, -11.8), Vector3(0.05, 0.05, 0.45)],
	"HoopFarFooting": [Vector3(8.0, 0.1, -11.5), Vector3(1.2, 0.2, 1.2)],
	"ShedBody": [Vector3(-17.0, 1.5, -4.0), Vector3(6.0, 3.0, 8.0)],
	"ShedFootingWest": [Vector3(-15.6, 0.2, -0.1), Vector3(1.4, 0.4, 1.4)],
	"ShedFootingEast": [Vector3(-13.2, 0.3, -0.1), Vector3(1.4, 0.6, 1.4)],
	"BoardPostA": [Vector3(14.0, 1.3, 2.0), Vector3(0.12, 2.6, 0.12)],
	"BoardPostB": [Vector3(14.0, 1.3, 4.4), Vector3(0.12, 2.6, 0.12)],
	"FramePost_0": [Vector3(18.0, 1.4, 7.0), Vector3(0.14, 2.8, 0.14)],
	"FramePost_1": [Vector3(18.0, 1.4, 9.0), Vector3(0.14, 2.8, 0.14)],
	"FramePost_2": [Vector3(18.0, 1.4, 11.0), Vector3(0.14, 2.8, 0.14)],
	"ContainerBody": [Vector3(12.0, 1.3, -15.5), Vector3(6.0, 2.6, 2.4)],
	"ContainerFootingA": [Vector3(9.4, 0.1, -15.5), Vector3(0.8, 0.2, 2.6)],
	"ContainerFootingB": [Vector3(14.6, 0.1, -15.5), Vector3(0.8, 0.2, 2.6)],
	"FitnessPost_0": [Vector3(-20.6, 1.0, 4.8), Vector3(0.14, 2.0, 0.14)],
	"FitnessPost_1": [Vector3(-20.6, 1.0, 7.2), Vector3(0.14, 2.0, 0.14)],
	"SitupFrame": [Vector3(-20.4, 0.42, 9.4), Vector3(0.9, 0.1, 1.6)],
	"TapPost": [Vector3(-6.0, 0.9, 14.0), Vector3(0.16, 1.8, 0.16)],
	"TreeTrunk": [Vector3(20.0, 2.0, 15.0), Vector3(0.5, 4.0, 0.5)],
	"YardBench": [Vector3(11.0, 0.0, 3.2), Vector3(2.043, 1.04, 0.527)],
	"YardBag": [Vector3(11.03, 0.52, 3.75), Vector3(0.528, 0.498, 0.386)],
}
## The bodies the camera fades; the slice must leave their group membership alone.
const OCCLUDERS: Array[String] = [
	"SchoolBackWall", "SouthFenceWest", "SouthFenceEast", "EstateBlockSouth",
	"EstateBlockEast", "ShedBody", "ContainerBody",
]
const INTERACTABLES := {
	"pg_hoop_near": Vector3(-8.0, 1.4, 8.8), "pg_court_middle": Vector3(0.0, 0.9, 2.0),
	"pg_bench_look": Vector3(10.2, 1.0, 3.2), "pg_frame_look": Vector3(17.0, 1.4, 9.0),
	"pg_shed_door": Vector3(-13.2, 1.1, -4.0), "pg_ball_look": Vector3(-14.2, 0.8, 0.6),
	"pg_board_look": Vector3(13.2, 1.7, 3.2), "pg_container_look": Vector3(12.0, 1.4, -13.9),
	"pg_tyre_look": Vector3(-14.6, 0.7, 2.9),
}
## [position, destination scene, destination spawn, milestone end].
const EXITS := {
	"pg_back_to_alley": [
		Vector3(0.0, 0.9, 18.2), "res://scenes/locations/alley/alley.tscn", &"FromPlayground", false,
	],
	"pg_to_corridor": [
		Vector3(-3.0, 0.9, -19.2), "res://scenes/locations/corridor/corridor.tscn",
		&"FromSchoolyard", false,
	],
	"pg_gap_in_fence": [Vector3(-14.0, 0.9, -18.2), "", &"default", true],
}
const SPAWNS := {
	"FromAlley": Vector3(0.0, 0.0, 16.0), "FromCorridor": Vector3(-3.0, 0.0, -17.6),
	"FromSchool": Vector3(-3.0, 0.0, -17.4),
}
## The baked navigation at base commit 359ed4a (Godot CI run 43014461771).
const NAV_POLYGONS := 143

## [focus material, backdrop material, why]; separation in value or colourfulness.
const HIERARCHY_PAIRS := [
	["door_green", "shed_wall", "the green shed door in the shed wall"],
	["fire_door", "school_wall", "the fire door (the way back in) in the school wall"],
	["frame_yellow", "ground", "the climbing frame against the yard"],
	["bench_patch", "ground", "the colour block under the bench and bag"],
	["court", "ground", "the court against the yard"],
	["hoop_rim", "court", "the hoop rings over the court"],
	["court_key", "court", "the keys inside the court"],
]
const HIERARCHY_MIN := 0.15
const QUIET_PLANES: Array[String] = ["ground", "pour_b", "school_wall", "estate"]
const QUIET_CHROMA_MAX := 0.2

## Body points sampled from the camera: waist and eye line. (A low tyre may cover shins;
## that is a thing standing in front of the legs, not a hidden player.)
const BODY_HEIGHTS: Array[float] = [0.9, 1.5]
const STAND_GRID_STEP := 1.0
## Thin equipment narrower than this (a hoop ring, the net, a padlock) cannot hide a
## person; it is reported, not failed.
const SMALL_PIECE := 0.5
const SCREEN_HEIGHT := 900.0
const SCREEN_WIDTH := 1600.0

## Where the text sits at 1600 x 900 (game_ui.tscn offsets; the project's base viewport).
const HUD_SAMPLES := {"PromptLabel": [Vector2(640, 842), Vector2(800, 842), Vector2(960, 842)],
	"ObjectiveLabel": [Vector2(70, 57), Vector2(240, 57), Vector2(410, 57)]}
const HUD_MIN_CONTRAST := {"PromptLabel": 4.5, "ObjectiveLabel": 3.5}
## The surfaces the yard floor is made of. Court lines and the seam are left out: they are
## narrower than a letter. Lit walls and props are reported, not failed (see the README).
const FLOOR_MATERIALS: Array[String] = ["ground", "pour_b", "hoop_patch", "bench_patch",
	"court", "court_far", "court_key", "concrete", "concrete_patch"]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _yard: Node3D = null
var _albedo_cache := {}


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "playground_art_slice_test.gd")
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
	if not host.load_location(PLAYGROUND, &"FromAlley", _player):
		Harness.finish(self, ["The schoolyard could not be entered."], "")
		return
	await _physics_frames(3)
	_yard = host.get_current()
	if _yard == null:
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
	_check_dressing()
	Harness.stage = "textures"
	_check_textures()
	Harness.stage = "hierarchy"
	_check_hierarchy()
	Harness.stage = "story agreement"
	_check_story_agreement()
	Harness.stage = "navigation"
	var navigation := await _check_navigation()
	Harness.stage = "game camera"
	await _check_game_camera(navigation)

	print("::notice title=playground art slice::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		"the painted schoolyard keeps its colliders, interactables, exits, spawns and "
		+ "navigation, draws only its own materials, and keeps its new pieces out of the "
		+ "camera's way.",
	)


# --- 1. layout ----------------------------------------------------------------------


func _check_layout() -> void:
	for required: String in ["Sun", "WorldEnvironment", "Navigation", "YardGround", "PlaygroundArt"]:
		if _yard.get_node_or_null(required) == null:
			_failures.append("The schoolyard lost its '%s' node." % required)
	for path: String in SPAWNS:
		_expect_at("SpawnPoints/%s" % path, SPAWNS[path])
	var location := _yard as LocationRoot
	if location != null:
		for spawn_name: String in SPAWNS:
			if location.get_spawn(StringName(spawn_name)) == null:
				_failures.append("The schoolyard no longer resolves spawn '%s'." % spawn_name)

	var found := {}
	var interactables := _yard.get_node_or_null(^"Interactables")
	if interactables == null:
		_failures.append("The schoolyard lost its Interactables node.")
		return
	for child in interactables.get_children():
		var id := String(child.get("interact_id"))
		var node := child as Node3D
		if INTERACTABLES.has(id):
			found[id] = true
			_expect_position("Interactable '%s'" % id, node, INTERACTABLES[id])
		elif EXITS.has(id):
			found[id] = true
			var spec: Array = EXITS[id]
			_expect_position("Exit '%s'" % id, node, spec[0])
			var exit := child as LocationExit
			if exit == null:
				_failures.append("'%s' is no longer a LocationExit." % id)
				continue
			if exit.destination_scene != spec[1] or exit.destination_spawn != spec[2]:
				_failures.append(
					"Exit '%s' now leads to %s @ %s; it led to %s @ %s."
					% [id, exit.destination_scene, exit.destination_spawn, spec[1], spec[2]]
				)
			if exit.is_milestone_end != spec[3]:
				_failures.append("Exit '%s' changed its milestone-end flag." % id)
		else:
			_failures.append("'%s' is an interactable the graybox did not have." % id)
	for id: String in INTERACTABLES:
		if not found.has(id):
			_failures.append("The schoolyard lost the '%s' interactable." % id)
	for id: String in EXITS:
		if not found.has(id):
			_failures.append("The schoolyard lost the '%s' exit." % id)
	_notes.append(
		"%d interactables, %d exits, %d spawns" % [INTERACTABLES.size(), EXITS.size(), SPAWNS.size()]
	)


func _expect_at(path: String, expected: Vector3) -> void:
	var node := _yard.get_node_or_null(NodePath(path)) as Node3D
	if node == null:
		_failures.append("The schoolyard lost '%s'." % path)
		return
	_expect_position("'%s'" % path, node, expected)


func _expect_position(label: String, node: Node3D, expected: Vector3) -> void:
	if not node.position.is_equal_approx(expected):
		_failures.append(
			"%s stands at %s; the yard has it at %s." % [label, str(node.position), str(expected)]
		)


# --- 2. collision -------------------------------------------------------------------


func _check_collision() -> void:
	var found := {}
	for node in _descendants(_yard):
		if not node is CollisionObject3D:
			continue
		var path := _relative(node)
		if path.begins_with("Interactables/"):
			continue
		if not SOLIDS.has(path):
			_failures.append(
				"'%s' collides. The art pass carries no collision: it would carve the " % path
				+ "navigation mesh and block interaction rays."
			)
			continue
		found[path] = true
		var spec: Array = SOLIDS[path]
		var body := node as Node3D
		if not body.position.is_equal_approx(spec[0]):
			_failures.append(
				"Body '%s' moved to %s; it stood at %s." % [path, str(body.position), str(spec[0])]
			)
		var shape_node := body.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		var box: BoxShape3D = shape_node.shape as BoxShape3D if shape_node != null else null
		if box == null or not box.size.is_equal_approx(spec[1]):
			_failures.append("Body '%s' changed its collision box (was %s)." % [path, str(spec[1])])
		elif not shape_node.transform.origin.is_equal_approx(_shape_origin(path)):
			_failures.append("Body '%s' moved its collision shape inside the body." % path)
		var collision := node as CollisionObject3D
		if collision.collision_layer & 1 == 0:
			_failures.append("Body '%s' left collision layer 1, which navigation bakes from." % path)
	for path: String in SOLIDS:
		if not found.has(path):
			_failures.append("'%s' no longer collides; the yard's solids changed." % path)
	for path: String in OCCLUDERS:
		var body := _yard.get_node_or_null(NodePath(path))
		if body != null and not body.is_in_group("camera_occluder"):
			_failures.append("'%s' left the camera_occluder group; it would never fade." % path)
	var art := _yard.get_node_or_null(^"PlaygroundArt")
	if art != null:
		for node in _descendants(art):
			if node is CollisionObject3D or node is CollisionShape3D:
				_failures.append("The art node '%s' brings collision." % _relative(node))
	_notes.append("solids %d" % found.size())


## The two imported props carry their shape half their height up; the graybox boxes are
## centred on their body.
func _shape_origin(path: String) -> Vector3:
	if path == "YardBench":
		return Vector3(0.0, 0.52, 0.0)
	if path == "YardBag":
		return Vector3(0.0, 0.249, 0.0)
	return Vector3.ZERO


# --- 3. colour system ---------------------------------------------------------------


func _check_colour_system() -> void:
	var used := {}
	var surfaces := 0
	for node in _descendants(_yard):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var path := _relative(node)
		if path.begins_with("Interactables/") or _has_own_materials(path):
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			surfaces += 1
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				_failures.append("'%s' surface %d draws with no material." % [path, surface])
				continue
			var resource_path := material.resource_path
			if not resource_path.begins_with(ART_MATERIALS):
				_failures.append(
					"'%s' draws '%s', which is not part of the schoolyard's colour system."
					% [path, resource_path if not resource_path.is_empty() else "<embedded>"]
				)
			used[resource_path] = true
	for resource_path: String in used:
		var material := load(resource_path) as Material
		while material != null:
			for prefix: String in FOREIGN_PREFIXES:
				if material.resource_path.begins_with(prefix):
					_failures.append("The schoolyard depends on '%s'." % material.resource_path)
			var standard := material as BaseMaterial3D
			if standard != null and standard.albedo_texture != null:
				if not standard.albedo_texture.resource_path.begins_with(ART_TEXTURES):
					_failures.append("'%s' samples '%s'." % [resource_path, standard.albedo_texture.resource_path])
			material = material.next_pass
	_notes.append("%d surfaces, %d materials" % [surfaces, used.size()])


func _has_own_materials(path: String) -> bool:
	for prefix: String in OWN_MATERIAL_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false


# --- 4. dressing on the occluders ---------------------------------------------------


func _check_dressing() -> void:
	for pair: Array in [["SchoolBackWall", "WallPatches"], ["ContainerBody", "Gesture"]]:
		var decal := _yard.get_node_or_null(NodePath("%s/%s" % [pair[0], pair[1]])) as MeshInstance3D
		if decal == null:
			_failures.append("'%s' is not hung on '%s', so it would not fade with it." % [pair[1], pair[0]])
			continue
		if decal.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_failures.append("The decal '%s/%s' casts a shadow." % pair)
	# The ruled graybox court and box tyres are hidden, and their painted replacements
	# are there.
	for path: String in [
		"CourtLineSouth", "CourtLineNorth", "CourtLineWest", "CourtLineEast", "CourtCentre",
		"KeyNear", "KeyFar", "TyreStack_0", "TyreStack_1", "TyreStack_2", "TyreLoose",
	]:
		var node := _yard.get_node_or_null(NodePath(path)) as Node3D
		if node == null:
			_failures.append("The graybox node '%s' is gone; it should only be hidden." % path)
		elif node.visible:
			_failures.append("The graybox node '%s' is still drawn under its painted copy." % path)
	for path: String in [
		"PlaygroundArt/Court/LineSouth", "PlaygroundArt/Court/LineNorth",
		"PlaygroundArt/Court/LineWest", "PlaygroundArt/Court/LineEast",
		"PlaygroundArt/Court/LineCentre", "PlaygroundArt/Court/KeyNear",
		"PlaygroundArt/Court/KeyFar", "PlaygroundArt/Equipment/Tyre_0",
		"PlaygroundArt/Equipment/Tyre_1", "PlaygroundArt/Equipment/Tyre_2",
		"PlaygroundArt/Equipment/TyreLoose",
	]:
		if _yard.get_node_or_null(NodePath(path)) == null:
			_failures.append("The painted replacement '%s' is missing." % path)


# --- 5. textures --------------------------------------------------------------------


func _check_textures() -> void:
	var textures := {}
	var dir := DirAccess.open(ART_MATERIALS)
	if dir == null:
		_failures.append("The schoolyard's material folder is missing.")
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var material := load(ART_MATERIALS + file_name) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			textures[material.albedo_texture.resource_path] = material.albedo_texture
	var total := 0
	for texture_path: String in textures:
		var texture: Texture2D = textures[texture_path]
		if not texture_path.begins_with(ART_TEXTURES):
			_failures.append("A schoolyard material samples '%s' from outside its folder." % texture_path)
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
		else:
			total += size
		if texture.get_width() > TEXTURE_MAX_SIDE or texture.get_height() > TEXTURE_MAX_SIDE:
			_failures.append("'%s' is larger than %d px." % [texture_path, TEXTURE_MAX_SIDE])
	if textures.size() < 20:
		_failures.append("Only %d painted textures are in use; the slice paints 25." % textures.size())
	_notes.append("%d textures, %d KiB" % [textures.size(), total / 1024])


# --- 6. hierarchy -------------------------------------------------------------------


func _check_hierarchy() -> void:
	var cache := {}
	var lines: Array[String] = []
	for pair: Array in HIERARCHY_PAIRS:
		var focus := _material_colour(pair[0], cache)
		var backdrop := _material_colour(pair[1], cache)
		var value_gap := absf(_luminance(focus) - _luminance(backdrop))
		var colour_gap := absf(_chroma(focus) - _chroma(backdrop))
		var hue_gap := _hue_distance(focus, backdrop) * minf(_chroma(focus), _chroma(backdrop)) * 2.0
		var separation := maxf(value_gap, maxf(colour_gap, hue_gap))
		lines.append("%s/%s %.2f" % [pair[0], pair[1], separation])
		if separation < HIERARCHY_MIN:
			_failures.append(
				"%s does not stand out: value gap %.2f, colour gap %.2f, hue gap %.2f (need %.2f)."
				% [pair[2], value_gap, colour_gap, hue_gap, HIERARCHY_MIN]
			)
	for plane: String in QUIET_PLANES:
		var chroma := _chroma(_material_colour(plane, cache))
		if chroma > QUIET_CHROMA_MAX:
			_failures.append("The broad plane '%s' is too loud (colourfulness %.2f)." % [plane, chroma])
	_notes.append("hierarchy " + ", ".join(lines))


func _material_colour(material_name: String, cache: Dictionary) -> Color:
	if cache.has(material_name):
		return cache[material_name]
	var path := ART_MATERIALS + material_name + ".tres"
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


## Hue distance on the colour wheel, 0 (same hue) .. 1 (opposite).
func _hue_distance(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d) * 2.0


# --- 7. the texts -------------------------------------------------------------------


func _check_story_agreement() -> void:
	var expectations := {
		"PlaygroundArt/Equipment/ShedHasp": "the hasp on the shed door",
		"PlaygroundArt/Equipment/ShedPadlock": "the padlock on the shed door",
		"PlaygroundArt/Equipment/HoopFarNet": "the net on the far hoop",
		"PlaygroundArt/Ground/HoopNearPatch": "the newer concrete the near hoop stands in",
		"PlaygroundArt/Ground/Seam": "the seam running past the middle of the yard",
		"PlaygroundArt/Ground/PourB": "the second pour of concrete",
		"PaleUnderHedge": "the pale strip under the hedge",
		"ShedSheet": "the duty sheet in the shed window",
		"PingPongBall": "the ball under the shed footing",
	}
	for path: String in expectations:
		var node := _yard.get_node_or_null(NodePath(path)) as Node3D
		if node == null or not node.is_visible_in_tree():
			_failures.append("The text describes %s, and '%s' is not drawn." % [expectations[path], path])
	_expect_material("ShedDoor", "door_green.tres", "the shed door is green")
	_expect_material("ShedSheet", "rota.tres", "the duty sheet is drawn as a sheet")
	_expect_material(
		"HoopNearFooting/MeshInstance3D", "concrete_patch.tres", "the near hoop stands in newer concrete"
	)
	_expect_material(
		"HoopFarFooting/MeshInstance3D", "concrete.tres", "the far hoop stands in the old concrete"
	)
	var cache := {}
	var patch := _material_colour("concrete_patch", cache)
	var old := _material_colour("concrete", cache)
	if absf(_luminance(patch) - _luminance(old)) < 0.03 and _hue_distance(patch, old) < 0.05:
		_failures.append("The near hoop's newer concrete reads the same as the old.")
	# No net on the near hoop: nothing named like a net within a metre of its ring.
	var near_ring := Vector3(-8.0, 2.6, 7.0)
	for node in _descendants(_yard):
		if String(node.name).contains("Net") and node is Node3D:
			if (node as Node3D).global_position.distance_to(_yard.to_global(near_ring)) < 1.0:
				_failures.append("The near hoop has a net ('%s'); the text says it has none." % _relative(node))
	# The far half of the court is darker, and drawn above the court surface, not under it.
	var far_paint := _luminance(_material_colour("court_far", cache))
	if far_paint >= _luminance(_material_colour("court", cache)) - 0.02:
		_failures.append("The far half of the court is not darker than the near half.")
	var far := _yard.get_node_or_null(^"CourtFarHalf") as MeshInstance3D
	var surface := _yard.get_node_or_null(^"CourtSurface") as MeshInstance3D
	if far != null and surface != null:
		var far_top := (far.global_transform * far.get_aabb()).end.y
		var surface_top := (surface.global_transform * surface.get_aabb()).end.y
		if far_top <= surface_top:
			_failures.append(
				"CourtFarHalf (top %.3f) is buried under CourtSurface (top %.3f)." % [far_top, surface_top]
			)
	# The yard is longer than it is wide, with the gate at the short end.
	var ground := _yard.get_node_or_null(^"YardGround/CollisionShape3D") as CollisionShape3D
	if ground != null:
		var size := (ground.shape as BoxShape3D).size
		if size.z < size.x * 0.8:
			_failures.append("The yard reads wider than long.")


func _expect_material(path: String, file_name: String, why: String) -> void:
	var mesh := _yard.get_node_or_null(NodePath(path)) as MeshInstance3D
	var worn := ""
	if mesh != null and mesh.material_override != null:
		worn = mesh.material_override.resource_path
	if worn != ART_MATERIALS + file_name:
		_failures.append("'%s' does not wear %s: %s." % [path, file_name, why])


# --- 9. navigation ------------------------------------------------------------------


func _check_navigation() -> LocationNavigation:
	var navigation := _yard.get_node_or_null(^"Navigation") as LocationNavigation
	if navigation == null:
		_failures.append("The schoolyard has no Navigation region.")
		return null
	var synchronized: bool = await navigation.wait_until_synchronized()
	if not synchronized:
		_failures.append("The schoolyard navigation never synchronized: %s" % navigation.describe_sync())
		return null
	var polygons := navigation.get_polygon_count()
	if polygons != NAV_POLYGONS:
		_failures.append(
			"The baked navigation has %d polygons; it had %d at the base commit, " % [polygons, NAV_POLYGONS]
			+ "so the walkable shape changed."
		)
	var map := navigation.get_navigation_map()
	var gate := _yard.get_node_or_null(^"SpawnPoints/FromAlley") as Node3D
	var start := NavigationServer3D.map_get_closest_point(map, gate.global_position)
	var worst := 0.0
	var interactables := _yard.get_node_or_null(^"Interactables")
	for child in interactables.get_children():
		var node := child as Node3D
		var radius := float(child.get("radius"))
		var gap := _route_gap(map, start, node.global_position)
		worst = maxf(worst, gap - radius)
		if gap > radius + 0.25:
			_failures.append(
				("'%s' cannot be reached from the gate: the nearest routed ground is %.2f m away, "
				+ "its radius %.2f.")
				% [String(child.get("interact_id")), gap, radius]
			)
	for spawn_name: String in SPAWNS:
		var marker := _yard.get_node_or_null(NodePath("SpawnPoints/%s" % spawn_name)) as Node3D
		if marker != null and _route_gap(map, start, marker.global_position) > 0.5:
			_failures.append("Spawn '%s' is cut off from the gate." % spawn_name)
	_notes.append(
		"nav polygons %d (base %d), worst reach margin %.2f m" % [polygons, NAV_POLYGONS, worst]
	)
	return navigation


func _route_gap(map: RID, start: Vector3, target: Vector3) -> float:
	var goal := NavigationServer3D.map_get_closest_point(map, target)
	var route := NavigationServer3D.map_get_path(map, start, goal, true)
	if route.is_empty():
		return INF
	var end := route[route.size() - 1]
	return Vector2(end.x - target.x, end.z - target.z).length()


# --- 8. the game camera -------------------------------------------------------------


func _check_game_camera(navigation: LocationNavigation) -> void:
	var rig := _main.get_node_or_null(^"CameraRig") as CameraRig
	if rig == null or rig.camera == null:
		_failures.append("Main has no CameraRig to look through.")
		return
	var camera := rig.camera
	var boxes := _art_boxes()

	# The painted distance stays off the walkable yard and out of the light.
	var distance := _yard.get_node_or_null(^"PlaygroundArt/Distance")
	if distance == null:
		_failures.append("The painted distance is missing.")
	else:
		for node in _descendants(distance):
			var mesh := node as MeshInstance3D
			if mesh == null:
				continue
			if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_failures.append("'%s' casts shadows onto the yard." % _relative(mesh))
			var box := mesh.global_transform * mesh.get_aabb()
			if String(mesh.name) == "SkyFloor":
				if box.end.y > _yard.to_global(Vector3(0.0, -0.5, 0.0)).y:
					_failures.append("The sky floor rises to %.2f m; it must stay under the yard." % box.end.y)
			elif box.end.x > _yard.to_global(Vector3(-25.0, 0.0, 0.0)).x:
				_failures.append(
					"'%s' stands inside x > -25 m, too close to the walkable yard." % _relative(mesh)
				)

	var spots: Array[Vector3] = []
	var map := navigation.get_navigation_map() if navigation != null else RID()
	var x := -22.5
	while x <= 22.5:
		var z := -19.5
		while z <= 19.5:
			var point := _yard.to_global(Vector3(x, 0.0, z))
			if map.is_valid():
				var on_mesh := NavigationServer3D.map_get_closest_point(map, point)
				if Vector2(on_mesh.x - point.x, on_mesh.z - point.z).length() < 0.05:
					spots.append(on_mesh)
			else:
				spots.append(point)
			z += STAND_GRID_STEP
		x += STAND_GRID_STEP
	if spots.size() < 600:
		_failures.append("Only %d standing spots were found in the yard." % spots.size())

	var blocked: Array[String] = []
	var grazed := {}
	var hud := _hud_context()
	for spot in spots:
		_player.teleport(Transform3D(Basis(), spot))
		rig.snap()
		var eye := camera.global_position
		_sample_hud(camera, spot, hud)
		for height in BODY_HEIGHTS:
			var what := "the player at %s (h %.1f)" % [str(spot), height]
			_test_segment(boxes, eye, spot + Vector3(0.0, height, 0.0), what, blocked, grazed)

	# Walk up to each interactable and look at it.
	var interactables := _yard.get_node_or_null(^"Interactables")
	for child in interactables.get_children():
		var node := child as Node3D
		var stand := node.global_position
		if map.is_valid():
			stand = NavigationServer3D.map_get_closest_point(map, node.global_position)
		_player.teleport(Transform3D(Basis(), stand))
		rig.snap()
		var label := "'%s'" % String(child.get("interact_id"))
		_test_segment(boxes, camera.global_position, node.global_position, label, blocked, grazed)

	_report_hud(hud)
	for line in blocked.slice(0, 8):
		_failures.append(line)
	if blocked.size() > 8:
		_failures.append("... and %d more blocked views." % (blocked.size() - 8))
	var grazed_names: Array[String] = []
	for key: String in grazed:
		grazed_names.append("%s x%d" % [key, grazed[key]])

	# The player, at the gate, at a 1600 x 900 window: how big the person and the yard read.
	var gate := _yard.get_node_or_null(^"SpawnPoints/FromAlley") as Node3D
	_player.teleport(Transform3D(Basis(), gate.global_position))
	rig.snap()
	var player_pixels := _screen_height(camera, gate.global_position, 1.6)
	if player_pixels < 60.0:
		_failures.append("At the gate the player is %.0f px tall on a 900-line screen." % player_pixels)
	_notes.append(
		"%d standing spots, %d art pieces checked; small pieces crossing a sight line: %s; "
		% [spots.size(), boxes.size(), ", ".join(grazed_names) if not grazed_names.is_empty() else "none"]
		+ "player %.0f px at %dx%d" % [player_pixels, int(SCREEN_WIDTH), int(SCREEN_HEIGHT)]
	)


# --- 10. the HUD over the yard. Calibrated on the CI frames of rounds 2-4 (exposure 1.0 /
# 0.62, Sun 0.85 / 0.32): it matched the measured ground, lit and shaded, within 4 sRGB levels.


func _hud_context() -> Dictionary:
	var env := (_yard.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	var sun := _yard.get_node(^"Sun") as DirectionalLight3D
	if env.tonemap_mode != Environment.TONE_MAPPER_FILMIC or env.ambient_light_source != 2:
		_failures.append("The HUD contrast estimate assumes Filmic and a flat ambient colour.")
	var text := {}
	for label_name: String in HUD_SAMPLES:
		var label := _main.find_child(label_name, true, false) as Label
		if label == null:
			_failures.append("The HUD has no %s to check." % label_name)
		else:
			text[label_name] = _luminance(label.get_theme_color(&"font_color").srgb_to_linear())
	var exclude: Array[RID] = []
	for body in _main.find_children("*", "CharacterBody3D", true, false):
		exclude.append((body as CharacterBody3D).get_rid())
	var paints := []  # [floor box, material, brightness], for the decals lying on the yard
	for node in _descendants(_yard):
		var mesh := node as MeshInstance3D
		var material := (mesh.material_override if mesh != null else null) as BaseMaterial3D
		if material == null or not mesh.is_visible_in_tree() or not FLOOR_MATERIALS.has(_name(material)):
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		if box.end.y < 0.1 and box.position.y > -0.1:
			paints.append([box, material, _luminance(_bright_albedo(material))])
	return {
		"ambient": env.ambient_light_color.srgb_to_linear() * env.ambient_light_energy,
		"sun": sun.light_color.srgb_to_linear() * sun.light_energy * PI,
		"to_sun": sun.global_basis.z.normalized(), "paints": paints,
		"exposure": env.tonemap_exposure, "white": env.tonemap_white, "text": text,
		"space": _yard.get_world_3d().direct_space_state, "exclude": exclude,
		"worst": {}, "loose": {}, "samples": 0, "low_loose": 0,
	}


func _sample_hud(camera: Camera3D, spot: Vector3, hud: Dictionary) -> void:
	var scale := (SCREEN_HEIGHT * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
	for label_name: String in hud.text:
		for pixel: Vector2 in HUD_SAMPLES[label_name]:
			var local := Vector3(pixel.x - SCREEN_WIDTH * 0.5, SCREEN_HEIGHT * 0.5 - pixel.y, -scale)
			var hit := _hud_hit(hud, camera.global_position, camera.global_basis * local.normalized())
			var contrast: float = (hud.text[label_name] + 0.05) / (hit[1] + 0.05)
			var key := "%s over %s" % [label_name, hit[0]]
			hud.samples += 1
			if hit[0] == "sky" or FLOOR_MATERIALS.has(hit[0]):
				if contrast < float(hud.worst.get(label_name, [99.0])[0]):
					hud.worst[label_name] = [contrast, key, spot]
				continue
			if contrast < 3.0:  # lit walls and props: reported, not failed
				hud.loose[key] = minf(contrast, float(hud.loose.get(key, 99.0)))
				hud.low_loose += 1


## [material name or "sky", estimated luminance] of what the ray first shows.
func _hud_hit(hud: Dictionary, origin: Vector3, direction: Vector3) -> Array:
	var exclude: Array[RID] = Array(hud.exclude, TYPE_RID, &"", null)
	for _attempt in 6:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 400.0)
		query.exclude = exclude
		var result: Dictionary = hud.space.intersect_ray(query)
		if result.is_empty():
			var sky := load(ART_MATERIALS + "sky_floor.tres") as BaseMaterial3D
			return ["sky", _shade(hud, sky, Vector3.UP, false)]
		var body := result.collider as CollisionObject3D
		var material: BaseMaterial3D = null
		for child in body.get_children():
			var mesh := child as MeshInstance3D
			if material == null and mesh != null and mesh.visible and mesh.mesh != null:
				var own: Material = mesh.material_override
				material = (own if own != null else mesh.mesh.surface_get_material(0)) as BaseMaterial3D
		if material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			exclude.append(body.get_rid())  # an invisible blocker or a see-through fence
			continue
		var point: Vector3 = result.position
		if body.name == &"YardGround":  # the brightest paint whose box covers the point
			var best := _luminance(_bright_albedo(material))
			for paint: Array in hud.paints:
				var box: AABB = paint[0]
				var inside := point.x >= box.position.x and point.x <= box.end.x
				if inside and point.z >= box.position.z and point.z <= box.end.z and paint[2] > best:
					material = paint[1]
					best = paint[2]
		var shadow := PhysicsRayQueryParameters3D.create(
			point + result.normal * 0.05, point + hud.to_sun * 120.0
		)
		shadow.exclude = hud.exclude
		var lit: bool = hud.space.intersect_ray(shadow).is_empty()
		return [_name(material), _shade(hud, material, result.normal, lit)]
	return ["sky", 0.0]


func _name(material: Resource) -> String:
	return material.resource_path.get_file().get_basename()


## Relative luminance on screen: albedo x (ambient + toon-lit Sun) x exposure, Filmic.
func _shade(hud: Dictionary, material: BaseMaterial3D, normal: Vector3, lit: bool) -> float:
	var light := Color.WHITE
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		light = hud.ambient
		if lit:
			var rough := maxf(material.roughness, 0.01)
			light += hud.sun * smoothstep(-rough, rough, normal.dot(hud.to_sun))
	var c := _bright_albedo(material) * light * float(hud.exposure)
	var w: float = hud.white
	return _luminance(Color(_filmic(c.r, w), _filmic(c.g, w), _filmic(c.b, w)))


func _filmic(x: float, white: float) -> float:
	var curve := func(v: float) -> float:
		return (v * (0.88 * v + 0.06) + 0.002) / (v * (0.88 * v + 0.6) + 0.06) - 0.01 / 0.3
	return clampf(curve.call(x) / curve.call(white), 0.0, 1.0)


## Linear albedo of the material's brightest tenth, in patches about a letter high
## (1/16 of the texture), so thin painted lines do not count as a light area.
func _bright_albedo(material: BaseMaterial3D) -> Color:
	if _albedo_cache.has(material.resource_path):
		return _albedo_cache[material.resource_path]
	var colour := material.albedo_color.srgb_to_linear()
	var image := Image.new()
	var texture := material.albedo_texture
	if texture != null and image.load(ProjectSettings.globalize_path(texture.resource_path)) == OK:
		image.convert(Image.FORMAT_RGBA8)
		var block := maxi(1, image.get_width() / 16)
		var patches: Array[Color] = []
		for by in range(0, image.get_height() - block + 1, block):
			for bx in range(0, image.get_width() - block + 1, block):
				var sum := Color(0, 0, 0, 0)
				var total := 0
				for y in range(by, by + block, 2):
					for x in range(bx, bx + block, 2):
						total += 1
						var pixel := image.get_pixel(x, y)
						if pixel.a > 0.5:
							sum += Color(pixel.srgb_to_linear(), 1.0)
				if sum.a * 2.0 >= total:
					patches.append(Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a))
		patches.sort_custom(func(a: Color, b: Color) -> bool: return _luminance(a) < _luminance(b))
		if not patches.is_empty():
			var bright := patches[int(0.9 * (patches.size() - 1))]
			colour = Color(colour.r * bright.r, colour.g * bright.g, colour.b * bright.b)
	_albedo_cache[material.resource_path] = colour
	return colour


func _report_hud(hud: Dictionary) -> void:
	var parts: Array[String] = []
	for label_name: String in HUD_MIN_CONTRAST:
		var worst: Array = hud.worst.get(label_name, [0.0, label_name + " over nothing", Vector3.ZERO])
		parts.append("%s %.2f" % [worst[1], worst[0]])
		if worst[0] < HUD_MIN_CONTRAST[label_name]:
			_failures.append(
				"%s: contrast %.2f at %s (need %.1f)."
				% [worst[1], worst[0], str(worst[2]), HUD_MIN_CONTRAST[label_name]]
			)
	var loose: Array[String] = []
	for key: String in hud.loose:
		loose.append("%s %.2f" % [key, hud.loose[key]])
	_notes.append(
		"HUD contrast estimate, worst over floor/sky: %s; lit walls/props under 3.0: %s (%d of %d)"
		% [", ".join(parts), ", ".join(loose) if not loose.is_empty() else "none",
			hud.low_loose, hud.samples]
	)


func _test_segment(
	boxes: Array,
	eye: Vector3,
	target: Vector3,
	what: String,
	blocked: Array[String],
	grazed: Dictionary,
) -> void:
	for entry: Array in boxes:
		# Tested in the mesh's own space: a rotated ring's world-space box is up to 40 %
		# wider than the ring, and would "hide" the very thing it stands next to.
		var box: AABB = entry[1]
		var to_local: Transform3D = entry[2]
		if not box.intersects_segment(to_local * eye, to_local * target):
			continue
		if maxf(box.size.x, box.size.z) < SMALL_PIECE:
			grazed[entry[0]] = int(grazed.get(entry[0], 0)) + 1
		else:
			blocked.append("%s hides %s" % [entry[0], what])


## Every drawn mesh the art pass added, as [path, local box, world-to-local transform]
## (the occluder decals fade with their wall and are left out).
func _art_boxes() -> Array:
	var boxes := []
	var art := _yard.get_node_or_null(^"PlaygroundArt")
	if art == null:
		return boxes
	for node in _descendants(art):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		boxes.append([_relative(mesh), mesh.get_aabb(), mesh.global_transform.affine_inverse()])
	return boxes


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
	return String(_yard.get_path_to(node))


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
