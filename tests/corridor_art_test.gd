extends SceneTree
## The walkway that does not end (docs/CORRIDOR_ART.md), checked on the real corridor
## scene. `location_art_test.gd` already holds every location to the stage rules (no
## colliders in stage art, materials under `stage_art/materials/`, the camera's sight lines,
## counts, exits and routes); this test holds the corridor to its own idea:
##
## 1. **The haze.** Depth fog whose colour is the clear colour, so nothing has an edge
##    where it gives out; clear around the player (begins past the camera's own distance
##    from the player), and gone to haze well inside the camera's far plane. Height fog
##    lies below the walkway, never on it.
## 2. **The walkway goes on.** `StageArt/Beyond` carries the floor, the wall, the
##    parapet and the upper storey on past the yard door, lying wholly north of the end
##    railing (no standing spot or sight line reaches it), at least 60 m of it, and the
##    continuation's wall tile repeats a whole number of times along it.
## 3. **The door is the only way on.** The end wall's picture is gone but its collider
##    stays, full height; the railing either side leaves the yard door's opening clear;
##    the door leaf is still there to be seen; the far block that closed the view across
##    the yard is hidden.
##
## Godot CI runs it headless (`corridor_art`).

const Harness = preload("res://tests/test_harness.gd")

const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
## The end railing's line (WallEndNorth at z -9.1, 0.2 m thick): the continuation starts here.
const BEYOND_START_Z := -9.2
const MIN_BEYOND := 60.0
## The camera rig's offset (scripts/world/camera_rig.gd): its length is how far the camera
## stands from the player, inside which the fog must not begin.
const CAMERA_OFFSET := Vector3(3.4, 6.4, 3.4)
## main.tscn's Camera3D.far.
const CAMERA_FAR := 120.0
## The yard door's opening, between its frame posts.
const DOOR_HALF_WIDTH := 0.65
const WALL_FAR_TILE := 8.0
const EPS := 0.02

var _check := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "corridor_art_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	L10n.load_tables()
	var packed := load(CORRIDOR) as PackedScene
	if packed == null:
		Harness.finish(self, ["corridor.tscn could not be loaded."], "")
		return
	var location := packed.instantiate() as Node3D
	root.add_child(location)
	await process_frame

	Harness.stage = "haze"
	_check_haze(location)
	Harness.stage = "beyond"
	_check_beyond(location)
	Harness.stage = "end"
	_check_end(location)

	Harness.finish(self, _check.failures, "the corridor goes on into the haze, and the yard door is the only way on.")


func _check_haze(location: Node) -> void:
	var world := location.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if not _check.expect(world != null and world.environment != null, "The corridor has no WorldEnvironment."):
		return
	var env := world.environment
	_check.expect(env.fog_enabled, "The corridor's fog is off.")
	_check.expect(env.fog_mode == Environment.FOG_MODE_DEPTH, "The corridor's fog is not depth fog.")
	_check.expect(
		_close(env.fog_light_color, env.background_color),
		"The fog colour %s is not the clear colour %s: the haze would have an edge." % [env.fog_light_color, env.background_color]
	)
	_check.expect(
		env.fog_depth_begin > CAMERA_OFFSET.length(),
		"The fog begins at %.1f m, inside the camera's %.1f m from the player." % [env.fog_depth_begin, CAMERA_OFFSET.length()]
	)
	_check.expect(
		env.fog_depth_end > env.fog_depth_begin and env.fog_depth_end < CAMERA_FAR * 0.5,
		"The fog ends at %.1f m: it has to end past its begin and well inside the far plane." % env.fog_depth_end
	)
	_check.expect(env.fog_density >= 0.99, "The depth fog does not reach full haze (density %.2f)." % env.fog_density)
	_check.expect(
		env.fog_height_density > 0.0 and env.fog_height < 0.0,
		"The height fog has to lie below the walkway (height %.2f, density %.2f)." % [env.fog_height, env.fog_height_density]
	)


func _check_beyond(location: Node) -> void:
	var beyond := location.get_node_or_null("StageArt/Beyond") as Node3D
	if not _check.expect(beyond != null, "The corridor has no StageArt/Beyond: the walkway stops at the yard door."):
		return
	for piece: String in ["Floor", "Wall", "WallPaint", "Parapet", "Rail", "Upper", "Upper/Windows"]:
		_check.expect(beyond.get_node_or_null(piece) is MeshInstance3D, "StageArt/Beyond has no %s." % piece)
	var reach := 0.0
	for mesh: MeshInstance3D in _meshes(beyond):
		var box := mesh.global_transform * mesh.get_aabb()
		_check.expect(
			box.end.z <= BEYOND_START_Z + EPS,
			"Beyond/%s reaches z %.2f, south of the end railing (%.1f)." % [beyond.get_path_to(mesh), box.end.z, BEYOND_START_Z]
		)
		reach = maxf(reach, BEYOND_START_Z - box.position.z)
	_check.expect(reach >= MIN_BEYOND, "The walkway goes on only %.1f m past the yard door." % reach)
	var paint := beyond.get_node_or_null("WallPaint") as MeshInstance3D
	if paint != null and paint.material_override is BaseMaterial3D and paint.mesh is QuadMesh:
		var length: float = (paint.mesh as QuadMesh).size.x
		var tiles: float = (paint.material_override as BaseMaterial3D).uv1_scale.x
		_check.expect(
			is_equal_approx(tiles * WALL_FAR_TILE, length) and is_equal_approx(tiles, roundf(tiles)),
			"The continuation's wall repeats %.2f times along %.1f m: it should be whole %.0f m tiles." % [tiles, length, WALL_FAR_TILE]
		)


func _check_end(location: Node) -> void:
	var end_mesh := location.get_node_or_null("WallEndNorth/MeshInstance3D") as MeshInstance3D
	_check.expect(end_mesh != null and not end_mesh.visible, "The end wall is still drawn across the walkway.")
	var shape := location.get_node_or_null("WallEndNorth/CollisionShape3D") as CollisionShape3D
	_check.expect(
		shape != null and shape.shape is BoxShape3D and (shape.shape as BoxShape3D).size.y >= 3.0,
		"The end wall's collider is gone or no longer full height."
	)
	var leaf := location.get_node_or_null("YardDoorLeaf") as MeshInstance3D
	_check.expect(leaf != null and leaf.visible, "The yard door's leaf is gone.")
	var far := location.get_node_or_null("FarBuilding") as MeshInstance3D
	_check.expect(far == null or not far.visible, "The far block still closes the view across the yard.")
	var railing := 0
	for child: Node in location.get_node("WallEndNorth").get_children():
		if not (child is MeshInstance3D) or not String(child.name).begins_with("StageEnd"):
			continue
		railing += 1
		var box := (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
		_check.expect(
			box.end.x <= -DOOR_HALF_WIDTH + EPS or box.position.x >= DOOR_HALF_WIDTH - EPS,
			"WallEndNorth/%s (x %.2f..%.2f) blocks the yard door's opening." % [child.name, box.position.x, box.end.x]
		)
	_check.expect(railing >= 2, "The yard door stands in no railing (%d pieces)." % railing)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		out.append(child as MeshInstance3D)
	return out


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
