extends SceneTree
## The exam-dream dressing (docs/EXAM_DREAM_ART.md) stays dressing.
##
##   godot --headless --path . --script res://tests/dream_annex_test.gd
##
## `tools/build_dream_annex.py` writes `scenes/locations/corridor/dream_annex.tscn` (the
## corridor instances it beside the teaching block) and the waiting room inside the staff
## office. The 03 crowd uses native pose loops; the rest of the dream uses shader motion.
##
## 1. Every piece draws: a material on each mesh, and a shader behind each ShaderMaterial.
## 2. Nothing in it acts: no script, actor, sound or interactable under the annex.
## 3. The stable yard is walkable; the stair still climbs 02 -> 03 and spawns stay clear.
## 4. The 03 figures have real tinted silhouettes, planted feet and readable posing beats.
## 5. The stink stable's smell filter (`StenchHaze`, in the corridor beside the annex) is a
##    world filter under the outline, off until the protagonist nears the stalls, and gone
##    again on the far side of the yard and on the other floors.

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
# Pose sample, driven joint and (where present) the prop carried by that figure.
const EXAM_CROWD := {
	^"Clique0/Person0": [&"Listen", 2.72, ^"Body/Head", ^""],
	^"Clique0/Person1": [&"Converse", 2.1, ^"Body/ForearmR", ^""],
	^"Clique0/Person2": [&"CheckSlip", 4.5, ^"Body/Head", ^"Body/ForearmR/AdmissionSlip"],
	^"Clique1/Person0": [&"Revise", 2.78, ^"Body/ForearmR", ^"Body/ForearmL/Notes"],
	^"Clique1/Person1": [&"CheckSlip", 4.5, ^"Body/Head", ^"Body/ForearmR/AdmissionSlip"],
	^"Troublemaker/Ranter": [&"RapOnPlaster", 1.54, ^"Body/ForearmR", ^""],
	^"Troublemaker/Accomplice": [&"Steady", 3.45, ^"Body/Head", ^""],
}
const WAITING_CROWD := {
	^"Clique0/Person0": [&"OfferSnacks", 2.2, ^"Body/ForearmR", ^"Body/ForearmR/SnackPouch"],
	^"Clique0/Person1": [&"Converse", 2.1, ^"Body/ForearmR", ^""],
	^"Clique0/Person2": [&"Listen", 2.72, ^"Body/Head", ^""],
	^"Clique1/Person0": [&"Revise", 2.78, ^"Body/ForearmR", ^"Body/ForearmL/Notes"],
	^"Clique1/Person1": [&"CheckSlip", 4.5, ^"Body/Head", ^"Body/ForearmR/AdmissionSlip"],
}
const STENCH_SHADER := "res://assets/shaders/school/stench_haze.gdshader"
const STENCH_POINTS := {
	"the muck heap": [Vector3(-31.6, -3.4, 5.6), 0.99, 1.01],
	"the yard": [Vector3(-31.0, -3.4, 13.4), 0.5, 0.95],
	"the glass entrance": [Vector3(-20.0, -3.4, 18.2), -0.01, 0.01],
	"the 01 gallery": [Vector3(-11.4, -3.4, 12.6), -0.01, 0.01],
	"02 above the stalls": [Vector3(-31.6, 0.0, 5.6), -0.01, 0.01],
}
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
		var exam := annex.get_node_or_null(^"ExamFloor")
		if _check.expect(exam != null, "The annex has no ExamFloor."):
			_check_candidates(exam, EXAM_CROWD, true)
			_check.expect(exam.find_children("*", "CollisionObject3D", true, false).is_empty(),
				"An exam vignette adds a collider to the 03 lane.")
	await _check_stench(corridor)
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
		_check_candidates(waiting, WAITING_CROWD)
		var seat := waiting.get_node_or_null(^"Clique1/StudyStool") as MeshInstance3D
		var sitter := waiting.get_node_or_null(^"Clique1/Person0/Body") as Node3D
		if _check.expect(seat != null and sitter != null, "The waiting room lost its seated reader."):
			var seat_top := seat.global_position.y + seat.get_aabb().end.y
			_check.expect(sitter.global_position.y - seat_top > 0.03 and sitter.global_position.y - seat_top < 0.09,
				"The reader's hips no longer rest just above the stool.")
		_check.expect(waiting.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"The waiting room added a collider to the office's inspection routes.")
	root.remove_child(office)
	office.free()
	for _frame in 4:
		await physics_frame
	Harness.finish(self, _check.failures, "the exam dream draws, never acts, opens the stable yard and moves nothing.")


func _check_stench(corridor: Node) -> void:
	var haze := corridor.get_node_or_null(^"StenchHaze") as CanvasLayer
	if not _check.expect(haze != null, "The corridor lost the stink stable's StenchHaze filter."):
		return
	_check.expect(haze.is_in_group(&"world_filter") and haze.layer < 0,
		"StenchHaze is not a world filter under the outline overlay.")
	var sheet := haze.get_node_or_null(^"Sheet") as ColorRect
	var material: ShaderMaterial = null
	if sheet != null:
		material = sheet.material as ShaderMaterial
	if not _check.expect(material != null and material.shader != null and material.shader.resource_path == STENCH_SHADER,
			"StenchHaze lost its sheet or its shader."):
		return
	_check.expect(sheet.mouse_filter == Control.MOUSE_FILTER_IGNORE, "StenchHaze takes the mouse.")
	_check.expect(not haze.visible, "StenchHaze draws with nobody near the stable.")
	for label: String in STENCH_POINTS:
		var spec: Array = STENCH_POINTS[label]
		var strength: float = haze.call(&"stench_at", spec[0])
		_check.expect(strength >= spec[1] and strength <= spec[2],
			"The stench at %s is %.2f, outside %.2f..%.2f." % [label, strength, spec[1], spec[2]])
	var walker := Node3D.new()
	walker.add_to_group(&"protagonist")
	corridor.add_child(walker)
	walker.global_position = (STENCH_POINTS["the muck heap"] as Array)[0]
	for _frame in 30:
		await process_frame
	var near: float = haze.call(&"get_strength")
	var drawn: Variant = material.get_shader_parameter(&"stench")
	_check.expect(haze.visible and near > 0.0 and drawn is float and is_equal_approx(drawn as float, near),
		"Standing at the muck heap does not bring the stench filter up.")
	corridor.remove_child(walker)
	walker.free()


func _check_pieces(holder: Node, where: String) -> void:
	var meshes := 0
	var moving := 0
	var checked_shaders: Dictionary = {}
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
			if not _check.expect(shaded.shader != null and not shaded.shader.code.is_empty(),
					"%s: '%s' has an empty shader." % [where, holder.get_path_to(node)]):
				continue
			if not checked_shaders.has(shaded.shader):
				checked_shaders[shaded.shader] = true
				# Preflighting another corridor can hold two copies at once. Their motion
				# must not take slots from Compatibility's shared instance buffer.
				_check.expect(not shaded.shader.code.contains("instance uniform "),
					"%s: %s uses the instance shader buffer." % [where, shaded.shader.resource_path])
	_check.expect(meshes > 60 and moving > 20, "%s: only %d pieces, %d moving." % [where, meshes, moving])


func _check_candidates(floor: Node, specs: Dictionary, sculpted := false) -> void:
	var heights: Array[float] = []
	var tailoring: Dictionary = {}
	var proportions: Dictionary = {}
	for path: NodePath in specs:
		var spec: Array = specs[path]
		var person := floor.get_node_or_null(path) as Node3D
		if not _check.expect(person != null, "Missing exam candidate %s." % path):
			continue
		var feet := person.get_node_or_null(^"PlantedFeet") as MeshInstance3D
		var face := person.get_node_or_null(^"Body/Head/FaceAndHair") as MeshInstance3D
		var coat := person.get_node_or_null(^"Body/Tailoring") as MeshInstance3D
		if not _check.expect(feet != null and face != null and coat != null, "%s lost its main volumes." % path):
			continue
		heights.append((face.global_transform * face.get_aabb()).end.y - person.global_position.y)
		tailoring[coat.mesh] = true
		if sculpted:
			var size := face.get_aabb().size
			if _check.expect(size.y > 0.2 and size.x > 0.16 and size.z > 0.16,
					"%s has no full-sized, three-dimensional head sculpt." % path):
				# Compare proportions, so tint and uniform rescaling cannot make clones pass.
				var shape := Vector2(size.x, size.z) / size.y
				proportions[shape.snapped(Vector2(0.01, 0.01))] = true
		_check.expect(absf((feet.global_transform * feet.get_aabb()).position.y - person.global_position.y) < 0.005,
			"The soles of %s no longer meet the floor." % path)
		var pieces := person.find_children("*", "MeshInstance3D", true, false)
		_check.expect(pieces.size() <= 7, "%s has more than one draw per moving form/prop." % path)
		var indices := 0
		for piece: MeshInstance3D in pieces:
			var mesh := piece.mesh as ArrayMesh
			var paint := piece.material_override as StandardMaterial3D
			if _check.expect(mesh != null and mesh.get_surface_count() == 1
					and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0
					and paint != null and paint.vertex_color_use_as_albedo,
					"%s has lost a tinted, non-box silhouette: %s." % [path, piece.name]):
				indices += mesh.surface_get_array_index_len(0)
		_check.expect(indices > 0 and indices <= 6300, "%s exceeds the 2100-triangle dressing budget." % path)
		_check_beat(person, feet, spec)
	_check.expect(tailoring.size() == specs.size(), "%s reused a costume mesh across candidates." % floor.name)
	if sculpted:
		_check.expect(proportions.size() == specs.size(), "The seven hall head silhouettes must be distinct.")
	_check.expect(not heights.is_empty() and heights.max() - heights.min() > 0.22,
		"%s lost its range of heights." % floor.name)


func _check_beat(person: Node3D, feet: MeshInstance3D, spec: Array) -> void:
	var motion := person.get_node_or_null(^"Motion") as AnimationPlayer
	var joint := person.get_node_or_null(spec[2]) as Node3D
	var beat: StringName = spec[0]
	if not _check.expect(joint != null and motion != null and motion.is_playing() and motion.current_animation == beat,
			"%s does not autoplay %s." % [person.get_path(), beat]):
		return
	var clip := motion.get_animation(beat)
	_check.expect(clip.loop_mode == Animation.LOOP_LINEAR, "%s no longer loops." % beat)
	for i in clip.get_track_count():
		var path := clip.track_get_path(i)
		_check.expect(String(path).begins_with("Body") and path.get_concatenated_subnames() == &"rotation_degrees",
			"%s animates something other than a visual pivot: %s." % [beat, path])
	var prop: MeshInstance3D
	var grip_to_prop := Transform3D.IDENTITY
	if not (spec[3] as NodePath).is_empty():
		prop = person.get_node_or_null(spec[3]) as MeshInstance3D
		if _check.expect(prop != null and String(prop.get_parent().name).begins_with("Forearm"),
				"%s lost its handheld prop or detached it from the grip." % beat):
			grip_to_prop = (prop.get_parent() as Node3D).global_transform.affine_inverse() * prop.global_transform
	if beat == &"Revise":
		_check.expect(person.has_node(^"Body/ForearmR/Pencil"), "Revision lost its pencil.")
	var planted := feet.global_transform
	motion.seek(0.0, true)
	var rest := joint.rotation_degrees
	motion.seek(spec[1], true)
	_check.expect(rest.distance_to(joint.rotation_degrees) > 7.0, "%s has no readable gesture." % beat)
	_check.expect(feet.global_transform.is_equal_approx(planted), "%s moves its planted shoes." % beat)
	if prop != null:
		var moved := (prop.get_parent() as Node3D).global_transform.affine_inverse() * prop.global_transform
		_check.expect(moved.is_equal_approx(grip_to_prop), "%s slides the prop out of its grip." % beat)


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
