extends SceneTree
## The exam-dream dressing (docs/EXAM_DREAM_ART.md) stays dressing.
##
##   godot --headless --path . --script res://tests/dream_annex_test.gd
##
## `tools/build_dream_annex.py` writes `scenes/locations/corridor/dream_annex.tscn` (the
## corridor instances it beside the teaching block) and the waiting room inside the staff
## office. Its moving people, horses, hens, belts and smells are shader motion only. This
## checks what would break play if that stopped being true:
##
## 1. Every piece draws: a material on each mesh, and a shader behind each ShaderMaterial.
## 2. Nothing in it acts: no script, actor, sound or interactable under the annex.
## 3. The stable yard is a place: the lane and yard bake into the corridor's navigation,
##    reachable from the glass entrance, as far as the strip by the corner doorway.
## 4. Nothing moved: the stair under the escalator still climbs 02 -> 03, the 01 gallery
##    and every spawn marker stay clear of the annex's colliders.

const Harness = preload("res://tests/test_harness.gd")
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const OFFICE := "res://scenes/locations/staff_office/staff_office.tscn"
const REQUIRED: Array[NodePath] = [
	^"DreamAnnex/Escalator/Tilt/Belt",
	^"DreamAnnex/Totem",
	^"DreamAnnex/TicketCounter/Booth/Clerk0",
	^"DreamAnnex/ExamFloor/SeatingGrid",
	^"DreamAnnex/ExamFloor/Troublemaker/Ranter",
	^"DreamAnnex/ExamFloor/TurnedChair0",
	^"DreamAnnex/StableYard/Lane",
	^"DreamAnnex/StableYard/DreamHouse/CornerDoorway",
	^"DreamAnnex/StableYard/DreamHouse/SkyEscalator/Rider0",
	^"DreamAnnex/StableYard/Flies0",
	^"DreamAnnex/StableYard/Smell0",
]
const YARD_POINTS := {
	"the yard": Vector3(-31.0, -3.4, 13.4),
	"the strip by the corner doorway": Vector3(-38.6, -3.4, 11.15),
	"the lane": Vector3(-24.0, -3.4, 17.4),
}
const KEPT_POINTS := {
	"the 01 gallery": Vector3(-11.4, -3.4, 12.6),
	"the restroom door": Vector3(-25.0, -3.4, 12.6),
	"the foot of the escalator": Vector3(0.0, 0.0, -8.45),
	"the 03 lane": Vector3(-13.2, 3.6, -7.8),
}

var _check := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "dream_annex_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	var corridor := (load(CORRIDOR) as PackedScene).instantiate() as Node3D
	root.add_child(corridor)
	await process_frame
	for path in REQUIRED:
		_check.expect(corridor.get_node_or_null(path) != null, "The corridor has no %s." % path)
	var annex := corridor.get_node_or_null(^"DreamAnnex")
	if _check.expect(annex != null, "The corridor does not instance dream_annex.tscn."):
		_check_pieces(annex, "corridor")
		_check_spawns(corridor, annex)
	var nav := corridor.get_node_or_null(^"Navigation") as LocationNavigation
	if _check.expect(nav != null, "The corridor lost its navigation.") and _check.expect(
		await _wait_for_bake(nav), "The corridor's navigation never baked."):
		_check_routes(corridor as LocationRoot, nav)
	root.remove_child(corridor)
	corridor.free()

	var office := (load(OFFICE) as PackedScene).instantiate() as Node3D
	root.add_child(office)
	await process_frame
	var waiting := office.get_node_or_null(^"WaitingRoom")
	if _check.expect(waiting != null, "The staff office has no WaitingRoom."):
		_check_pieces(waiting, "staff office")
		_check.expect(waiting.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"The waiting room added a collider to the office's inspection routes.")
	root.remove_child(office)
	office.free()
	for _frame in 4:
		await physics_frame
	Harness.finish(self, _check.failures, "the exam dream draws, never acts, opens the stable yard and moves nothing.")


func _check_pieces(holder: Node, where: String) -> void:
	var meshes := 0
	var moving := 0
	for node in holder.find_children("*", "", true, false):
		_check.expect(node.get_script() == null, "%s: '%s' carries a script." % [where, holder.get_path_to(node)])
		_check.expect(not (node is NpcActor or node is Interactable or node is AudioStreamPlayer3D),
			"%s: '%s' is more than dressing." % [where, holder.get_path_to(node)])
		var mesh := node as GeometryInstance3D
		if mesh == null or node is Label3D:
			continue
		meshes += 1
		var material := mesh.material_override
		if not _check.expect(material != null, "%s: '%s' draws without a material." % [where, holder.get_path_to(node)]):
			continue
		var shaded := material as ShaderMaterial
		if shaded != null:
			moving += 1
			_check.expect(shaded.shader != null and not shaded.shader.code.is_empty(),
				"%s: '%s' has an empty shader." % [where, holder.get_path_to(node)])
	_check.expect(meshes > 60 and moving > 20, "%s: only %d pieces, %d moving." % [where, meshes, moving])


func _check_spawns(corridor: Node3D, annex: Node) -> void:
	var spawns := corridor.get_node(^"SpawnPoints").get_children()
	for body in annex.find_children("*", "CollisionShape3D", true, false):
		var shape := body as CollisionShape3D
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var bounds := shape.global_transform * AABB(-box.size * 0.5, box.size)
		bounds = bounds.grow(0.5)
		for spawn in spawns:
			var spot := (spawn as Node3D).global_position + Vector3.UP * 0.9
			_check.expect(not bounds.has_point(spot), "'%s' crowds the spawn %s." % [annex.get_path_to(shape), spawn.name])


func _check_routes(corridor: LocationRoot, nav: LocationNavigation) -> void:
	var map := nav.get_navigation_map()
	var entrance := NavigationServer3D.map_get_closest_point(map, corridor.get_spawn(&"FromTeachingEntrance").global_position)
	for label: String in YARD_POINTS:
		var wanted: Vector3 = YARD_POINTS[label]
		var spot := NavigationServer3D.map_get_closest_point(map, wanted)
		if not _check.expect(_on_mesh(spot, wanted), "%s is not walkable (nearest %s)." % [label, spot]):
			continue
		var path := NavigationServer3D.map_get_path(map, entrance, spot, true)
		_check.expect(path.size() >= 2 and path[path.size() - 1].distance_to(spot) < 0.3,
			"%s cannot be reached from the glass entrance." % label)
	for label: String in KEPT_POINTS:
		var wanted: Vector3 = KEPT_POINTS[label]
		var spot := NavigationServer3D.map_get_closest_point(map, wanted)
		_check.expect(_on_mesh(spot, wanted), "%s is no longer walkable (nearest %s)." % [label, spot])
	var foot := NavigationServer3D.map_get_closest_point(map, KEPT_POINTS["the foot of the escalator"])
	var top := NavigationServer3D.map_get_closest_point(map, KEPT_POINTS["the 03 lane"])
	var climb := NavigationServer3D.map_get_path(map, foot, top, true)
	var length := 0.0
	for i in range(1, climb.size()):
		length += climb[i - 1].distance_to(climb[i])
	_check.expect(climb.size() >= 2 and climb[climb.size() - 1].distance_to(top) < 0.3 and length < 18.0,
		"The stair under the escalator no longer climbs 02 -> 03 directly (%.1f m)." % length)


## The baked surface floats a cell or two above the collider, so only the plan
## position has to match; the height only has to be the same floor.
func _on_mesh(spot: Vector3, wanted: Vector3) -> bool:
	return Vector2(spot.x - wanted.x, spot.z - wanted.z).length() < 0.35 and absf(spot.y - wanted.y) < 0.75


func _wait_for_bake(nav: LocationNavigation) -> bool:
	var budget := 0
	while budget < 240:
		var alone := NavigationServer3D.map_get_regions(nav.get_navigation_map()).size() == 1
		if nav.is_baked() and alone and nav.is_synchronized() and nav.is_routable():
			return true
		await physics_frame
		budget += 1
	return false
