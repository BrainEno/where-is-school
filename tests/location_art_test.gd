extends SceneTree
## The stage pass over the walkway, street, courtyard and alley (and the yard's additions)
## is visual-only, and stays out of the player's way.
##
##   godot --headless --path . --script res://tests/location_art_test.gd
##
## `scenes/environment/props/stage_art/source/build_stage_art.py` repoints materials,
## retunes the light and adds mesh-only nodes to four scenes; the yard's builder adds a
## few more pieces to its painted distance. This test loads the real scenes and checks
## what a player would notice if the pass had got it wrong:
##
## 1. **Nothing to walk into.** No node of the pass (`StageArt/**`, `Stage*`) is or
##    holds a collider; each scene keeps exactly the colliders it had before the pass.
## 2. **The map is unchanged.** Every location keeps its spawn markers, its number of
##    interactables, and its exits with the same destination and spawn; every outline
##    path of every interactable still resolves.
## 3. **Still walkable.** The navigation bakes, and every spawn reaches every exit.
## 4. **Own materials, small textures.** Every mesh of the pass draws with a material
##    from `stage_art/materials/`; every texture lives under `stage_art/textures/` or the
##    yard's `playground_art/textures/`, at most 512 KiB and 2048 px.
## 5. **The distance stays distant.** `StageArt/Distance` casts no shadow, and its sky
##    floor lies at least a metre under the lowest walkable floor.
## 6. **Never in the way of the camera.** From every standing spot (a 1 m grid over the
##    navigation mesh) and at every interactable, no piece of the pass crosses the sight
##    line from the follow camera to the player (at 0.9 m and 1.5 m) or to the thing.
##    Pieces under 0.5 m across are only reported. A piece parented under a
##    `camera_occluder` body is not counted when the same sight line also meets that
##    body's collider: the occluder fader (`scripts/world/camera_occluder_fader.gd`) then
##    fades the body together with everything under it.
## 7. **Not murk.** A filmic tone map, a flat ambient colour bright enough to read the
##    shaded ground, and a clear colour that is not near-black.
##
## Not yet registered in `.github/workflows/godot-ci.yml` (that file is being changed by
## another open pull request); see docs/MAP_PLAN.md, "Tests".

const Harness = preload("res://tests/test_harness.gd")

const STAGE_MATERIALS := "res://scenes/environment/props/stage_art/materials/"
const TEXTURE_ROOTS: Array[String] = [
	"res://scenes/environment/props/stage_art/textures/",
	"res://scenes/environment/props/playground_art/textures/",
]
const MAX_TEXTURE_BYTES := 512 * 1024
const MAX_TEXTURE_PX := 2048
## The follow camera (`scripts/world/camera_rig.gd`): the rig sits on the player.
const CAMERA_OFFSET := Vector3(3.4, 6.4, 3.4)
const BODY_HEIGHTS: Array[float] = [0.9, 1.5]
const STAND_GRID_STEP := 1.0
const SMALL_PIECE := 0.5
const MIN_AMBIENT := 0.45

## Per location: scene, whether the stage pass dresses it, colliders, interactables,
## spawn markers, and exits as interact_id -> "destination_id/destination_spawn".
## Collision shapes are counted at runtime, so the instanced prop wrappers and the
## interactables' areas are included. The pass does not touch either, and the scene files
## hold the same CollisionShape3D nodes as on main at 6cdf037, so these are main's numbers.
const LOCATIONS := {
	"corridor": {
		"scene": "res://scenes/locations/corridor/corridor.tscn",
		"stage": true,
		"shapes": 87,
		"interactables": 9,
		"spawns": ["FromClassroom", "FromStreet", "FromSchoolyard"],
		"exits": {
			"back_to_classroom": "classroom/FromCorridor",
			"school_gate": "street/FromCorridor",
			"to_schoolyard": "playground/FromCorridor",
		},
	},
	"street": {
		"scene": "res://scenes/locations/street/street.tscn",
		"stage": true,
		"shapes": 80,
		"interactables": 8,
		"spawns": ["FromCorridor", "FromResidential"],
		"exits": {
			"street_back_to_school": "corridor/FromStreet",
			"street_to_residential": "residential/FromStreet",
		},
	},
	"residential": {
		"scene": "res://scenes/locations/residential/residential.tscn",
		"stage": true,
		"shapes": 131,
		"interactables": 9,
		"spawns": ["FromStreet", "FromStair", "FromAlley"],
		"exits": {
			"res_back_to_street": "street/FromResidential",
			"res_alley_end": "alley/FromCourtyard",
		},
	},
	"alley": {
		"scene": "res://scenes/locations/alley/alley.tscn",
		"stage": true,
		"shapes": 17,
		"interactables": 5,
		"spawns": ["FromCourtyard", "FromPlayground"],
		"exits": {
			"alley_back_to_courtyard": "residential/FromAlley",
			"alley_to_playground": "playground/FromAlley",
		},
	},
	"playground": {
		"scene": "res://scenes/locations/playground/playground.tscn",
		"stage": false,
		"shapes": 79,
		"interactables": 12,
		"spawns": ["FromAlley", "FromCorridor", "FromSchool"],
		"exits": {
			"pg_back_to_alley": "alley/FromPlayground",
			"pg_to_corridor": "corridor/FromSchoolyard",
		},
	},
}

## Spawns that are not meant to reach every exit (see docs/MAP_PLAN.md: FromStair stands
## on a look-only landing, FromSchool is not used by any exit).
const ROUTE_EXEMPT: Array[String] = ["residential/FromStair", "playground/FromSchool"]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 600.0, "location_art_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	for id: String in LOCATIONS:
		await _check_location(id, LOCATIONS[id])
	for note in _notes:
		print("  ", note)
	print("location art: %d checks" % _checks)
	Harness.finish(
		self,
		_failures,
		"the stage pass adds no collider, keeps every exit, spawn and route, draws with its own small textures and never blocks the follow camera.",
	)


func _check_location(id: String, spec: Dictionary) -> void:
	var packed := load(String(spec["scene"])) as PackedScene
	if packed == null:
		_failures.append("%s: the scene could not be loaded." % id)
		return
	var location := packed.instantiate() as Node3D
	root.add_child(location)
	await process_frame
	await process_frame

	_check_map(id, spec, location)
	var pieces: Array[MeshInstance3D] = []
	if bool(spec["stage"]):
		pieces = _stage_pieces(id, location)
		_check_pieces(id, pieces)
		_check_distance(id, location)
		_check_light(id, location)

	var nav := location.get_node_or_null(^"Navigation") as LocationNavigation
	if nav == null:
		_failures.append("%s has no navigation region." % id)
	elif not await _wait_for_bake(nav):
		_failures.append("%s: the navigation never baked (%s)." % [id, nav.get_bake_error()])
	else:
		_check_routes(id, location, nav)
		if bool(spec["stage"]):
			_check_camera(id, location, nav, pieces)

	root.remove_child(location)
	location.free()
	await process_frame


# --- 1 and 2. colliders, spawns, interactables, exits ---------------------------------


func _check_map(id: String, spec: Dictionary, location: Node) -> void:
	var shapes := 0
	for node in _descendants(location):
		if node is CollisionShape3D:
			shapes += 1
	_checks += 1
	if shapes != int(spec["shapes"]):
		_failures.append("%s has %d collision shapes; it had %d." % [id, shapes, int(spec["shapes"])])

	var spawns: Array[String] = []
	var spawn_root := location.get_node_or_null(^"SpawnPoints")
	if spawn_root != null:
		for child in spawn_root.get_children():
			spawns.append(String(child.name))
	for wanted: String in spec["spawns"]:
		_checks += 1
		if not spawns.has(wanted):
			_failures.append("%s lost its spawn marker %s." % [id, wanted])

	var interactables := location.get_node_or_null(^"Interactables")
	if interactables == null:
		_failures.append("%s has no Interactables." % id)
		return
	_checks += 1
	if interactables.get_child_count() != int(spec["interactables"]):
		_failures.append(
			"%s has %d interactables; it had %d." % [id, interactables.get_child_count(), int(spec["interactables"])]
		)
	var exits: Dictionary = spec["exits"]
	var seen := {}
	for child in interactables.get_children():
		_check_outlines(id, child)
		var exit := child as LocationExit
		if exit == null or exit.destination_id == &"":
			continue
		var key := String(exit.interact_id)
		seen[key] = true
		var got := "%s/%s" % [exit.destination_id, exit.destination_spawn]
		_checks += 1
		if not exits.has(key):
			_failures.append("%s has a new exit '%s' -> %s." % [id, key, got])
		elif got != String(exits[key]):
			_failures.append("%s: exit '%s' now leads to %s, not %s." % [id, key, got, exits[key]])
	for key: String in exits:
		_checks += 1
		if not seen.has(key):
			_failures.append("%s lost its exit '%s'." % [id, key])


func _check_outlines(id: String, interactable: Node) -> void:
	var paths: Variant = interactable.get("outline_paths")
	if not paths is PackedStringArray:
		return
	for path: String in paths:
		_checks += 1
		if interactable.get_node_or_null(NodePath(path)) == null:
			_failures.append("%s: '%s' outlines %s, which is gone." % [id, interactable.name, path])


# --- 4 and 5. the pass's own nodes ---------------------------------------------------


func _stage_pieces(id: String, location: Node) -> Array[MeshInstance3D]:
	var pieces: Array[MeshInstance3D] = []
	var art := location.get_node_or_null(^"StageArt")
	_checks += 1
	if art == null:
		_failures.append("%s has no StageArt subtree; run build_stage_art.py." % id)
		return pieces
	var nodes: Array[Node] = [art]
	nodes.append_array(_descendants(art))
	for node in _descendants(location):
		if String(node.name).begins_with("Stage") and not art.is_ancestor_of(node) and node != art:
			nodes.append(node)
			nodes.append_array(_descendants(node))
	for node in nodes:
		_checks += 1
		if node is CollisionObject3D or node is CollisionShape3D:
			_failures.append("%s: '%s' of the stage pass can be collided with." % [id, location.get_path_to(node)])
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null and not pieces.has(mesh):
			pieces.append(mesh)
	return pieces


func _check_pieces(id: String, pieces: Array[MeshInstance3D]) -> void:
	var textures := {}
	for mesh in pieces:
		_checks += 1
		var material := mesh.material_override as BaseMaterial3D
		if material == null or not material.resource_path.begins_with(STAGE_MATERIALS):
			_failures.append("%s: '%s' does not draw with a stage material." % [id, mesh.name])
			continue
		if material.albedo_texture != null:
			textures[material.albedo_texture.resource_path] = true
	for path: String in textures:
		_check_texture(id, path)


func _check_texture(id: String, path: String) -> void:
	_checks += 1
	var inside := false
	for prefix in TEXTURE_ROOTS:
		inside = inside or path.begins_with(prefix)
	if not inside:
		_failures.append("%s: texture %s lives outside the art folders." % [id, path])
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_TEXTURE_BYTES:
		_failures.append("%s: %s is %d KiB." % [id, path, bytes.size() / 1024])
	var texture := load(path) as Texture2D
	if texture != null and maxi(texture.get_width(), texture.get_height()) > MAX_TEXTURE_PX:
		_failures.append("%s: %s is %d px across." % [id, path, maxi(texture.get_width(), texture.get_height())])


func _check_distance(id: String, location: Node3D) -> void:
	var distance := location.get_node_or_null(^"StageArt/Distance")
	_checks += 1
	if distance == null:
		_failures.append("%s: the painted distance is missing." % id)
		return
	var lowest := INF
	for node in _descendants(location):
		var body := node as StaticBody3D
		if body != null:
			for shape_node in body.get_children():
				var shape := shape_node as CollisionShape3D
				if shape != null and shape.shape is BoxShape3D:
					var size := (shape.shape as BoxShape3D).size
					lowest = minf(lowest, (shape.global_transform * AABB(-size * 0.5, size)).end.y)
	for node in _descendants(distance):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		_checks += 1
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_failures.append("%s: '%s' casts shadows." % [id, mesh.name])
		if String(mesh.name) == "SkyFloor":
			var top := (mesh.global_transform * mesh.get_aabb()).end.y
			if top > lowest - 1.0:
				_failures.append("%s: the sky floor (%.2f m) is within a metre of a floor top." % [id, top])


func _check_light(id: String, location: Node) -> void:
	var holder := location.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_checks += 1
	if holder == null or holder.environment == null:
		_failures.append("%s has no environment." % id)
		return
	var env := holder.environment
	if env.tonemap_mode != Environment.TONE_MAPPER_FILMIC or env.ambient_light_source != 2:
		_failures.append("%s: expected Filmic and a flat ambient colour." % id)
	var ambient := _luminance(env.ambient_light_color) * env.ambient_light_energy
	if ambient < MIN_AMBIENT:
		_failures.append("%s: ambient %.2f is murk; the shaded ground will not read." % [id, ambient])
	if _luminance(env.background_color) < 0.15:
		_failures.append("%s: the clear colour is near-black." % id)


# --- 3. routes --------------------------------------------------------------------


func _check_routes(id: String, location: Node, nav: LocationNavigation) -> void:
	var map := nav.get_navigation_map()
	var spawn_root := location.get_node_or_null(^"SpawnPoints")
	var interactables := location.get_node_or_null(^"Interactables")
	if spawn_root == null or interactables == null:
		return
	for spawn in spawn_root.get_children():
		if ROUTE_EXEMPT.has("%s/%s" % [id, spawn.name]):
			continue
		for child in interactables.get_children():
			var exit := child as LocationExit
			if exit == null:
				continue
			_checks += 1
			var start := NavigationServer3D.map_get_closest_point(map, (spawn as Node3D).global_position)
			var goal := NavigationServer3D.map_get_closest_point(map, exit.global_position)
			var path := NavigationServer3D.map_get_path(map, start, goal, true)
			if path.size() < 2 and start.distance_to(goal) > 0.3:
				_failures.append("%s: %s no longer reaches '%s'." % [id, spawn.name, exit.interact_id])
			elif path.size() >= 2 and path[path.size() - 1].distance_to(goal) > 0.3:
				_failures.append("%s: %s no longer reaches '%s'." % [id, spawn.name, exit.interact_id])


# --- 6. the follow camera -------------------------------------------------------------


func _check_camera(id: String, location: Node, nav: LocationNavigation, pieces: Array[MeshInstance3D]) -> void:
	var boxes := []
	for mesh in pieces:
		if mesh.is_visible_in_tree():
			var path := String(location.get_path_to(mesh))
			boxes.append([path, mesh.get_aabb(), mesh.global_transform.affine_inverse(), _fading_shapes(mesh)])
	var map := nav.get_navigation_map()
	var spots := _standing_spots(nav, map)
	_checks += 1
	if spots.size() < 20:
		_failures.append("%s: only %d standing spots were found." % [id, spots.size()])
	var blocked: Array[String] = []
	var grazed := {}
	for spot in spots:
		for height in BODY_HEIGHTS:
			var target := spot + Vector3(0.0, height, 0.0)
			_test_segment(boxes, spot + CAMERA_OFFSET, target, "the player at %s" % str(spot), blocked, grazed)
	var interactables := location.get_node_or_null(^"Interactables")
	for child in interactables.get_children():
		var node := child as Node3D
		var stand := NavigationServer3D.map_get_closest_point(map, node.global_position)
		_test_segment(boxes, stand + CAMERA_OFFSET, node.global_position, "'%s'" % node.name, blocked, grazed)
	for line in blocked.slice(0, 6):
		_failures.append("%s: %s" % [id, line])
	if blocked.size() > 6:
		_failures.append("%s: ... and %d more blocked views." % [id, blocked.size() - 6])
	var names: Array[String] = []
	for key: String in grazed:
		names.append("%s x%d" % [key, grazed[key]])
	_notes.append("%s: %d spots, %d pieces; small pieces on a sight line: %s" % [
		id, spots.size(), boxes.size(), ", ".join(names) if not names.is_empty() else "none"
	])


func _standing_spots(nav: LocationNavigation, map: RID) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var mesh := nav.navigation_mesh
	if mesh == null or mesh.get_vertices().is_empty():
		return spots
	var low := Vector3.INF
	var high := -Vector3.INF
	for vertex in mesh.get_vertices():
		var world := nav.global_transform * vertex
		low = low.min(world)
		high = high.max(world)
	var x := low.x
	while x <= high.x:
		var z := low.z
		while z <= high.z:
			var probe := Vector3(x, (low.y + high.y) * 0.5, z)
			var on_mesh := NavigationServer3D.map_get_closest_point(map, probe)
			if Vector2(on_mesh.x - x, on_mesh.z - z).length() < 0.05:
				spots.append(on_mesh)
			z += STAND_GRID_STEP
		x += STAND_GRID_STEP
	return spots


func _test_segment(
	boxes: Array, eye: Vector3, target: Vector3, what: String, blocked: Array[String], grazed: Dictionary
) -> void:
	for entry: Array in boxes:
		var box: AABB = entry[1]
		var to_local: Transform3D = entry[2]
		if not box.intersects_segment(to_local * eye, to_local * target):
			continue
		var fades := false
		for shape: Array in entry[3]:
			var shape_box: AABB = shape[0]
			var shape_local: Transform3D = shape[1]
			fades = fades or shape_box.intersects_segment(shape_local * eye, shape_local * target)
		if fades:
			continue
		if maxf(box.size.x, box.size.z) < SMALL_PIECE:
			grazed[entry[0]] = int(grazed.get(entry[0], 0)) + 1
		else:
			blocked.append("%s hides %s" % [entry[0], what])


## The box colliders of the `camera_occluder` body a piece hangs under, as
## [local box, world-to-local transform]; empty when it hangs under none.
func _fading_shapes(mesh: Node) -> Array:
	var shapes := []
	var body := mesh.get_parent()
	while body != null and not (body is CollisionObject3D and body.is_in_group(&"camera_occluder")):
		body = body.get_parent()
	if body == null:
		return shapes
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var size := (shape.shape as BoxShape3D).size
			shapes.append([AABB(-size * 0.5, size), shape.global_transform.affine_inverse()])
	return shapes


# --- helpers ------------------------------------------------------------------------


func _wait_for_bake(nav: LocationNavigation) -> bool:
	var budget := 0
	while budget < 240:
		if nav.is_baked() and nav.get_map_region_count() > 0 and nav.is_routable():
			return true
		await physics_frame
		budget += 1
	return false


func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


func _descendants(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root_node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
