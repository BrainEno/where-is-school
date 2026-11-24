extends SceneTree
## The exam-dream dressing (docs/EXAM_DREAM_ART.md) stays dressing.
##
##   godot --headless --path . --script res://tests/dream_annex_test.gd
##
## `tools/build_dream_annex.py` writes `scenes/locations/corridor/dream_annex.tscn` (the
## corridor instances it beside the teaching block) and the waiting room inside the staff
## office. The 03 crowd and the 01 stamp loop use native animation; scenery still uses shader motion.
##
## 1. Every piece draws: a material on each mesh, and a shader behind each ShaderMaterial.
## 2. Nothing in it acts: no script, actor, sound or interactable under the annex.
## 3. The stable yard is walkable; the stair still climbs 02 -> 03 and spawns stay clear.
## 4. The 03 figures have real tinted silhouettes, planted feet and readable posing beats.
## 5. The stink stable's smell filter (`StenchHaze`, in the corridor beside the annex) is a
##    world filter under the outline, off until the protagonist nears the stalls, and gone
##    again on the far side of the yard and on the other floors.
## 6. The stable animals are sculpted (round 18): each horse and hen is one dense painted
##    surface on `stable_coat.gdshader`, not boxes or cut paper, and the yard stays sparse.

const Harness = preload("res://tests/test_harness.gd")
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const OFFICE := "res://scenes/locations/staff_office/staff_office.tscn"
const COAT_SHADER := "res://assets/shaders/school/stable_coat.gdshader"
const FRONT_YARD_DIRT := "res://scenes/environment/props/stage_art/materials/yard_dirt.tres"
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
	"the muck heap": [Vector3(-41.9, -3.4, 13.45), 0.99, 1.01],
	"the yard": [Vector3(-35.0, -3.4, 13.4), 0.5, 0.95],
	"the glass entrance": [Vector3(-20.0, -3.4, 18.2), -0.01, 0.01],
	"the 01 gallery": [Vector3(-11.4, -3.4, 12.6), -0.01, 0.01],
	"02 above the stalls": [Vector3(-35.6, 0.0, 5.6), -0.01, 0.01],
}
const ENTRANCE_ROUTES := {
	"the yard": Vector3(-35.0, -3.4, 13.4),
	"the strip by the corner doorway": Vector3(-42.6, -3.4, 11.15),
	"the lane": Vector3(-24.0, -3.4, 17.4),
	"the lane in front of the booth": Vector3(-13.62, -3.4, 12.25),
	"the archive door landing": Vector3(-14.48, -3.4, 12.0),
	"the plan room door landing": Vector3(-6.45, -3.4, 8.0),
	"the foot of the blue stair": Vector3(-9.94, -3.4, 12.54),
	# Round 25: the forecourt is gone; the lane is reached through the gallery's side door.
	"the lane door": Vector3(-21.8, -3.4, 14.6),
}
## Round 23: the board across the lane's mouth (build_dream_annex.lane_barrier), world x and
## the z where it starts. Routes into the stable yard squeeze past its north end.
const BARRIER_X := -24.95
const BARRIER_NORTH_Z := 16.35
const KEPT_POINTS := {
	"the 01 gallery": Vector3(-11.4, -3.4, 12.6),
	"the restroom door": Vector3(-25.0, -3.4, 12.6),
	"the foot of the escalator": Vector3(0.0, 0.0, -8.45),
	"where the old 02 booth stood": Vector3(1.38, 0.0, -8.45),
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
		_check_ticket_counter(corridor)
		_check_stable_art(annex)
		_check_stable_surfaces(annex)
		var stable := annex.get_node_or_null(^"StableYard") as Node3D
		_check.expect(stable != null and is_equal_approx(stable.position.x, -4.0)
			and annex.has_node(^"StableLaneConnector"), "Stable must be separated from the restroom with a connected lane.")
		_check.expect(corridor.has_node(^"TeachingBlock/GroundFloor/GlassEntrance")
			and corridor.has_node(^"TeachingBlock/GroundFloor/LockedServiceGate/Lock"),
			"The glass entrance or closed service gate is missing.")
		_check_restroom_shell(corridor)
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


func _check_stable_art(annex: Node) -> void:
	# Round 19: two sculpted women at work, each with her tool and one looping native clip.
	var workers: Dictionary = {"OldWoman0": [&"Sift", ^"Body/Sieve"], "OldWoman1": [&"Rake", ^"Rake"]}
	for name: String in workers:
		var spec: Array = workers[name]
		var person := annex.get_node_or_null(NodePath("StableYard/" + name)) as Node3D
		if not _check.expect(person != null, "The stable lost " + name):
			continue
		var indices := 0
		for part: NodePath in [^"Feet", ^"Body/Coat", ^"Body/Head", ^"Body/ArmL", ^"Body/ArmR"]:
			var piece := person.get_node_or_null(part) as MeshInstance3D
			if not _check.expect(piece != null, name + " lost " + str(part)):
				continue
			var mesh := piece.mesh as ArrayMesh
			var paint := piece.material_override as ShaderMaterial
			if _check.expect(mesh != null and mesh.get_surface_count() == 1
				and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0
				and paint != null and paint.shader != null and paint.shader.resource_path == COAT_SHADER,
				name + " lost its sculpted, painted " + str(part)):
				indices += mesh.surface_get_array_index_len(0)
		_check.expect(indices > 30000, name + " is a coarse stand-in again, not a sculpted figure")
		var tool := person.get_node_or_null(spec[1]) as MeshInstance3D
		_check.expect(tool != null and tool.mesh != null, name + " lost the tool that says what she is doing")
		var motion := person.get_node_or_null(^"Motion") as AnimationPlayer
		var arm := person.get_node_or_null(^"Body/ArmR") as Node3D
		if not _check.expect(motion != null and motion.is_playing() and motion.current_animation == spec[0]
				and arm != null and tool != null, name + " no longer works on a loop"):
			continue
		var clip := motion.get_animation(spec[0])
		_check.expect(clip.loop_mode == Animation.LOOP_LINEAR, name + "'s work no longer loops")
		motion.seek(0.0, true)
		var rest_arm := arm.rotation_degrees
		var rest_tool := tool.global_position
		motion.seek(clip.length * 0.25, true)
		_check.expect(rest_arm.distance_to(arm.rotation_degrees) > 3.0
			and rest_tool.distance_to(tool.global_position) > 0.025,
			name + "'s arms and tool do not move together through the work")
		motion.play()
	_check.expect(annex.get_node_or_null(^"StableYard/Stool") == null, "The box stool is back")
	_check_stable_animals(annex)
	var wisp := annex.get_node_or_null(^"StableYard/Stink0") as MultiMeshInstance3D
	if _check.expect(wisp != null and wisp.multimesh != null, "The stable lost its wisps"):
		var bounds := wisp.multimesh.mesh.get_aabb()
		_check.expect(bounds.size.z > 0.15 and wisp.multimesh.instance_count <= 3,
			"The smell must be sparse and three-dimensional")


func _check_stable_surfaces(annex: Node) -> void:
	# The connector and the relief use one soil shader in the same yard-local coordinates.
	var earth := annex.get_node_or_null(^"StableYard/YardEarth") as MeshInstance3D
	var connector := annex.get_node_or_null(^"StableLaneConnectorEarth") as MeshInstance3D
	if _check.expect(earth != null and connector != null and connector.mesh != null,
			"Stable soil or its connector is missing"):
		var yard_mat := earth.material_override as ShaderMaterial
		var lane_mat := connector.material_override as ShaderMaterial
		if _check.expect(yard_mat != null and lane_mat != null and yard_mat.shader != null
				and yard_mat.shader == lane_mat.shader, "The connector no longer shares the yard soil shader"):
			# Round 22: both are painted with the front yard's packed dirt, laid in world space.
			var front := load(FRONT_YARD_DIRT) as StandardMaterial3D
			var yard_dirt: Texture2D = yard_mat.get_shader_parameter(&"dirt")
			var lane_dirt: Texture2D = lane_mat.get_shader_parameter(&"dirt")
			_check.expect(front != null and yard_dirt != null and yard_dirt == front.albedo_texture
				and lane_dirt == yard_dirt and front.uv1_world_triplanar,
				"The stable soil is no longer the front yard's dirt")
		var bounds := connector.mesh.get_aabb()
		_check.expect(is_equal_approx(connector.position.x + bounds.position.x, -24.75),
			"The connector overlaps or leaves a gap at the yard soil edge")
	# Round 22: the corner posts stand proud of the stall front and end walls, not flush with
	# them; bottoms on the floor and tops under the upper floor are buried, so only x and z.
	var house := annex.get_node_or_null(^"StableYard/DreamHouse")
	if _check.expect(house != null, "The stable house is missing"):
		var house_parts := ["NorthWall", "SouthWall", "StallBack", "Partition0", "Partition1", "Partition2"]
		house_parts.append_array(["Post0", "Post1", "Post2", "Post3"])
		_check_no_shared_faces(house, house_parts, [0, 2])
	# On each low wall, the lime is proud of the mud; caps stop at the ends.
	for wall: String in ["WallSouth", "WallWest", "WallNorth", "WallNorthEast"]:
		var base := "StableYard/" + wall + "/"
		var mud := annex.get_node_or_null(NodePath(base + "Mud")) as MeshInstance3D
		var lime := annex.get_node_or_null(NodePath(base + "Lime")) as MeshInstance3D
		var cap := annex.get_node_or_null(NodePath(base + "Cap")) as MeshInstance3D
		if not _check.expect(mud != null and lime != null and cap != null, wall + " lost a surface"):
			continue
		var ms := mud.mesh.get_aabb().size
		var ls := lime.mesh.get_aabb().size
		var cs := cap.mesh.get_aabb().size
		var along_x := ms.x > ms.z
		_check.expect((ls.z > ms.z and ls.x < ms.x) if along_x else (ls.x > ms.x and ls.z < ms.z),
			wall + " has coplanar mud and lime faces")
		_check.expect(is_equal_approx(cs.x, ms.x) and is_equal_approx(cs.z, ms.z),
			wall + " cap extends into its neighbour")
	var north := annex.get_node_or_null(^"StableYard/WallNorth/Cap") as MeshInstance3D
	var east := annex.get_node_or_null(^"StableYard/WallNorthEast/Cap") as MeshInstance3D
	if north != null and east != null:
		var north_end := north.global_position.x + north.mesh.get_aabb().end.x
		var east_start := east.global_position.x + east.mesh.get_aabb().position.x
		_check.expect(north_end <= east_start + 0.00001, "North caps overlap at the corner")


func _check_stable_animals(annex: Node) -> void:
	var animals: Dictionary = {
		"DreamHouse/BayHorse": 15000, "DreamHouse/BayHorse/Limbs": 15000,
		"DreamHouse/GreyHorse": 15000, "DreamHouse/GreyHorse/Limbs": 15000,
		"Coop/CoopHen0": 9000, "Coop/CoopHen1": 9000,
		"YardHen0": 9000, "YardHen1": 9000, "YardHen2": 9000,
	}
	for path: String in animals:
		var animal := annex.get_node_or_null(NodePath("StableYard/" + path)) as MeshInstance3D
		if not _check.expect(animal != null, "The stable lost " + path):
			continue
		var mesh := animal.mesh as ArrayMesh
		var coat := animal.material_override as ShaderMaterial
		_check.expect(mesh != null and mesh.get_surface_count() == 1
			and mesh.surface_get_array_index_len(0) > int(animals[path])
			and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0,
			path + " is not one dense, painted, sculpted surface")
		_check.expect(coat != null and coat.shader != null and coat.shader.resource_path == COAT_SHADER
			and animal.material_overlay == null, path + " is not lit by the coat shader alone")
	# Round 19: a few flies over the heap and some of the droppings, never a cloud.
	var fly_count := 0
	for swarm in annex.find_children("Flies*", "MultiMeshInstance3D", true, false):
		fly_count += (swarm as MultiMeshInstance3D).multimesh.instance_count
	_check.expect(fly_count >= 20 and fly_count <= 40, "%d flies: the yard wants a few, not a swarm" % fly_count)
	for index in 6:
		_check.expect(annex.get_node_or_null(NodePath("StableYard/Dung%d" % index)) != null,
			"The yard lost dropping %d" % index)
	var earth := annex.get_node_or_null(^"StableYard/YardEarth") as MeshInstance3D
	if _check.expect(earth != null and earth.mesh != null, "The stable yard lost its earth"):
		var relief := earth.mesh.get_aabb()
		_check.expect(relief.size.y > 0.04 and relief.size.y < 0.12 and relief.size.x > 19.0,
			"The yard's earth is flat again, or heaves out of the walking slab")
		_check.expect(earth.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"The yard's relief added a collider")
	var straw := annex.get_node_or_null(^"StableYard/LooseStraw") as MeshInstance3D
	_check.expect(straw != null and straw.mesh != null and straw.mesh.get_aabb().size.x > 12.0,
		"The yard lost its scattered straw")
	for name: String in ["GiantFly", "DazeHalo0", "Dung6", "WallStain0", "Smell1"]:
		_check.expect(annex.find_child(name, true, false) == null, "The yard is cluttered again: " + name)


func _check_restroom_shell(corridor: Node) -> void:
	# Round 19: the restroom behind the gallery's end wall has an outside, seen from the yard.
	var shell := corridor.get_node_or_null(^"TeachingBlock/GroundFloor/RestroomExterior") as StaticBody3D
	if not _check.expect(shell != null and shell.is_in_group(&"camera_occluder"),
			"The restroom has no camera-fading outer shell beside the stable yard."):
		return
	var solid := shell.get_node(^"Solid") as CollisionShape3D
	var half := (solid.shape as BoxShape3D).size * .5
	var bounds := solid.global_transform * AABB(-half, half * 2.0)
	var door := corridor.get_node_or_null(^"Interactables/RestroomDoor") as Node3D
	_check.expect(bounds.position.x > -31.0 and bounds.end.x < -26.8 and bounds.position.z < 6.0
		and bounds.end.z < 14.68 and bounds.size.y > 3.0,
		"The restroom shell must fill the gap between the yard and the end wall, clear of the lane.")
	if door != null:
		_check.expect(door.global_position.x > bounds.end.x + .4, "The restroom shell covers its own door.")
	for part: String in ["Plaster", "Light0/Frost", "Downpipe"]:
		_check.expect(shell.get_node_or_null(NodePath(part)) is MeshInstance3D, "The restroom shell lost its " + part)
	# Round 22: the roof membrane and the cornice shared their top face and flickered.
	_check_no_shared_faces(
		shell, ["Plinth", "Plaster", "Cornice", "Roof", "Coping0", "Coping1", "Coping2", "Coping3"], [0, 1, 2]
	)


## Fails where two box meshes with different materials have a face in the same plane, facing
## the same way and overlapping by more than a sliver: those faces z-fight as the camera moves.
## `axes` lists the axes to compare (0 = x, 1 = y, 2 = z), so faces known to be buried can be skipped.
func _check_no_shared_faces(owner: Node, parts: Array, axes: Array) -> void:
	var boxes: Array[AABB] = []
	var materials: Array[Material] = []
	var names: Array[String] = []
	for part: String in parts:
		var piece := owner.get_node_or_null(NodePath(part)) as MeshInstance3D
		if not _check.expect(piece != null and piece.mesh is BoxMesh, "%s lost its %s" % [owner.name, part]):
			continue
		boxes.append(piece.global_transform * piece.mesh.get_aabb())
		materials.append(piece.material_override)
		names.append(part)
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if materials[i] == materials[j]:
				continue
			for axis: int in axes:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var a: AABB = boxes[i]
				var b: AABB = boxes[j]
				var span_u := minf(a.end[u], b.end[u]) - maxf(a.position[u], b.position[u])
				var span_v := minf(a.end[v], b.end[v]) - maxf(a.position[v], b.position[v])
				if span_u < .005 or span_v < .005:
					continue
				var shared := absf(a.position[axis] - b.position[axis]) < .002 or absf(a.end[axis] - b.end[axis]) < .002
				_check.expect(not shared, "%s: %s and %s share a face; it flickers" % [owner.name, names[i], names[j]])


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


func _check_ticket_counter(corridor: Node3D) -> void:
	var booth := corridor.get_node_or_null(^"DreamAnnex/TicketCounter/Booth") as StaticBody3D
	var door := corridor.get_node_or_null(^"TeachingBlock/GroundFloor/GlassEntrance") as Node3D
	if not _check.expect(booth != null and door != null, "The clerk booth or the 01 glass entrance is missing."):
		return
	var solid := booth.get_node(^"Solid") as CollisionShape3D
	var half := (solid.shape as BoxShape3D).size * .5
	var bounds := solid.global_transform * AABB(-half, half * 2.0)
	var threshold := door.global_position
	_check.expect(absf(bounds.position.y - threshold.y) < .01 and bounds.position.x > threshold.x + 1.33
		and bounds.end.z < threshold.z and threshold.z - bounds.end.z < .65,
		"The booth isn't beside the right glazing, entirely inside 01 and clear of the door opening.")
	var motion := booth.get_node_or_null(^"Motion") as AnimationPlayer
	if not _check.expect(motion != null and motion.is_playing() and motion.current_animation == &"Stamp",
			"The booth lost its single autoplay stamp clock."):
		return
	var clip := motion.get_animation(&"Stamp")
	_check.expect(clip.loop_mode == Animation.LOOP_LINEAR and clip.get_track_count() == 3,
		"All three clerks must share one looping stamp clip.")
	motion.pause()
	for index in 3:
		var clerk := booth.get_node_or_null(NodePath("Clerk%d" % index)) as Node3D
		if not _check.expect(clerk != null, "Clerk %d missing at the new location." % index):
			continue
		var face := clerk.get_node(^"Head/FaceAndHair") as MeshInstance3D
		var shoes := clerk.get_node(^"PlantedFeet") as MeshInstance3D
		var stamp := clerk.get_node(^"StampArm/StampFoot") as MeshInstance3D
		var ticket := booth.get_node(NodePath("Ticket%d" % index)) as MeshInstance3D
		var skin := face.mesh as ArrayMesh
		_check.expect(skin != null and skin.surface_get_array_index_len(0) > 2100,
			"Clerk %d has no shaped face for the close-up." % index)
		_check.expect(absf((shoes.global_transform * shoes.get_aabb()).position.y - threshold.y) < .004,
			"Clerk %d's shoes don't rest on 01." % index)
		var paper_top := (ticket.global_transform * ticket.get_aabb()).end.y
		for beat: float in [0.0, .96, 1.65]:
			motion.seek(beat, true)
			var clearance := (stamp.global_transform * stamp.get_aabb()).position.y - paper_top
			var matches := clearance > .06 if beat == 0.0 else absf(clearance) < .003
			_check.expect(matches, "Clerk %d stamp misses the shared raised/contact pose at %.2fs." % [index, beat])
	motion.play()


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
	for label: String in ENTRANCE_ROUTES:
		var wanted: Vector3 = ENTRANCE_ROUTES[label]
		var spot := NavigationServer3D.map_get_closest_point(map, wanted)
		if not _check.expect(_on_mesh(spot, wanted), "%s is not walkable (nearest %s)." % [label, spot]):
			continue
		var path := NavigationServer3D.map_get_path(map, entrance, spot, true)
		_check.expect(path.size() >= 2 and path[path.size() - 1].distance_to(spot) < 0.3,
			"%s cannot be reached from the glass entrance." % label)
	_check_barrier(map, entrance)
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


## The lane barrier must turn the yard route through the gap by the wall, not let it pass
## straight through the board.
func _check_barrier(map: RID, entrance: Vector3) -> void:
	var yard := NavigationServer3D.map_get_closest_point(map, ENTRANCE_ROUTES["the yard"])
	var path := NavigationServer3D.map_get_path(map, entrance, yard, true)
	var crossed := false
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if (a.x - BARRIER_X) * (b.x - BARRIER_X) > 0.0 or is_equal_approx(a.x, b.x):
			continue
		var z := lerpf(a.z, b.z, (BARRIER_X - a.x) / (b.x - a.x))
		crossed = true
		_check.expect(z < BARRIER_NORTH_Z, "The yard route passes through the lane barrier at z %.2f." % z)
	_check.expect(crossed, "The yard route never crosses the lane barrier's line: %s." % str(path))


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
