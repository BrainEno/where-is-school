extends SceneTree
## The school block is a playable loop, not scenery past a locked end. Run on the
## shipped main scene: the production capsule, input, pointer, camera and transitions.
## CI entry: corridor_art. The separate location_art suite checks the exterior art.

const Harness = preload("res://tests/test_harness.gd")
const DirectoryCase = preload("res://tests/corridor_directory_support.gd")
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const FRONT_YARD := "res://scenes/locations/front_yard/front_yard.tscn"
const PLAYGROUND := "res://scenes/locations/playground/playground.tscn"
const SCHOOL := ^"TeachingBlock"
const ENTRANCE := ^"TeachingBlock/GroundFloor/GlassEntrance"
const DIRECTORY := &"corridor_folded_directory"
const BIOLOGY_BAY := ^"TeachingBlock/LowerFloor/LowerWest1"
const UPPER := ^"TeachingBlock/UpperFloor"
const LANDING := Vector3(2.2, 1.8, -35.75)
const FIRST_BEND := Vector3(0, 0, -27.75)
const SECOND_BEND := Vector3(-12, 3.6, -42.75)
const UPPER_EAST := Vector3(11.2, 3.6, -42.75)
const HALL_BY_WEST_STAIR := Vector3(0, 0, -8.45)
const FORECOURT_GATE := Vector3(-17.65, -3.64, 21.3)
const ROOM_WINDOW_Y := 2.15
const FLOOR_RISE := 3.6
const PLAYER_GLASS_LAYER := 4

var _check := Harness.Checker.new()
var _host: LocationHost
var _player: PlayerController
var _camera: Camera3D
var _interaction: InteractionController
var _pointer: PointerNavigator
var _dialogue: DialogueController
var _last_inspection: StringName = &""
var _directory_checkpoints: Dictionary = {}


func _initialize() -> void:
	Harness.arm_watchdog(self, 170.0, "corridor_art_test.gd")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	var director := main.get_node(^"OpeningSequence") as OpeningSequence
	director.autostart = false
	root.add_child(main)
	main.get_node(^"InnerVoiceDirector").set_process(false)
	_host = main.get_node(^"LocationHost") as LocationHost
	_player = main.get_node(^"Player") as PlayerController
	_camera = main.get_node(^"CameraRig/Camera3D") as Camera3D
	_dialogue = main.get_node(^"DialogueController") as DialogueController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_interaction.mouse_targeting = false # E uses facing; the pointer case uses the actual click path below.
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _last_inspection = id)
	var flags := root.get_node(^"GameState")
	for flag in [StoryFlags.PLAYGROUND_ARRIVED, StoryFlags.STREET_ARRIVED]:
		flags.set_flag(flag, true) # Arrival dialogue and Q are covered by companion_route.

	var classroom := _host.get_current()
	var inner_wall := classroom.get_node(^"WallEast") as Node3D
	var classroom_doors := _measure_biology_doors(classroom, inner_wall, true)
	_check_biology_thresholds(classroom, inner_wall, true)
	var initial_nav := classroom.get_node(^"Navigation") as LocationNavigation
	if not await Harness.wait_until(initial_nav.is_routable, 5.0):
		_check.fail("Initial classroom did not finish entering the navigation map.")
		_finish()
		return

	if not _check.expect(_host.load_location(CORRIDOR, &"FromClassroom", _player, &"corridor"), "Corridor failed to load."):
		_finish()
		return
	director.allow_player_control()
	var corridor := _host.get_current()
	var outer_wall := corridor.get_node(BIOLOGY_BAY) as StaticBody3D
	_check_door_alignment(classroom_doors, _measure_biology_doors(corridor, outer_wall, false))
	_check_biology_thresholds(corridor, outer_wall, false)
	var nav := corridor.get_node(^"Navigation") as LocationNavigation
	if not await Harness.wait_until(func() -> bool: return nav.is_routable() and _player.is_on_floor(), 5.0):
		_check.fail("The new building never became routable: %s" % nav.get_bake_error())
		_finish()
		return

	Harness.stage = "structure, glass and paths"
	_check_structure(corridor, nav)
	_check_yard_view(corridor)
	await physics_frame
	_check_glass_collision(corridor)

	Harness.stage = "rear door on the corridor side"
	flags.set_flag(StoryFlags.CLASS_DISMISSED, true)
	await _check_rear_door(corridor, outer_wall)
	# Leave the rest of the structural walk solo until the real classroom exit joins Q.
	flags.set_flag(StoryFlags.CLASS_DISMISSED, false)
	if _host.get_current().location_id != &"corridor":
		_finish()
		return

	Harness.stage = "front-room jump with the existing interact input"
	var peek := corridor.find_interactable(&"classroom_glass")
	if await _walk(Vector3(-1.27, 0, -3.35), "biology high window"):
		await _check_peek(peek, false)

	Harness.stage = "walking the whole building"
	if await _walk(HALL_BY_WEST_STAIR, "west stair foot") and await _climb_with_keys():
		await _click_through_upper_window(corridor, nav)
		var upper_peek := corridor.find_interactable(&"high_window_upperwest1")
		if await _walk(Vector3(-13.25, 3.6, -12.2), "03 high window"):
			await _check_peek(upper_peek, true)
		await _walk(SECOND_BEND, "upper bend")
		await _walk(UPPER_EAST, "upper east wing")
		await _walk(LANDING, "dogleg half landing")
		await _walk(FIRST_BEND, "02 via far stair")

	Harness.stage = "yard fire stair and two-way exit"
	var approach := corridor.get_spawn(&"FromSchoolyard")
	if await _walk(approach.global_position, "fire stair bottom"):
		if await _use_exit(&"to_schoolyard", &"playground", &"FromCorridor"):
			# Round 24: arriving, the player walks out from under the fire door and off its
			# step, so the way back in is not under the cursor at their feet.
			var yard_spawn := _host.get_current().get_spawn(&"FromCorridor").global_position
			_check.expect(_player.global_position.distance_to(yard_spawn) > 1.2,
				"Arriving in the yard did not walk the player off the fire step (%s)." % _player.global_position)
			var yard_nav := _host.get_current().get_node(^"Navigation") as LocationNavigation
			await Harness.wait_until(func() -> bool: return yard_nav.is_routable(), 7.0)
			if await _walk(yard_spawn, "back under the fire door"):
				await _use_exit(&"pg_to_corridor", &"corridor", &"FromSchoolyard")
	if _host.get_current().location_id == &"corridor":
		await _walk(FIRST_BEND, "climb back from the yard")
		Harness.stage = "classroom and street returns"
		var front_step := _host.get_current().get_spawn(&"FromClassroom").global_position
		if await _walk(front_step, "return to biology front door"):
			if await _use_exit(&"back_to_classroom", &"classroom", &"FromCorridor"):
				flags.set_flag(StoryFlags.CLASS_DISMISSED, true)
				if await _use_exit(&"classroom_door", &"corridor", &"FromClassroom"):
					_check.expect(_player.global_position.distance_to(front_step) < 0.12,
						"Leaving the classroom did not land on the hall side of the front door.")
		if _host.get_current().location_id == &"corridor" and await _walk(Vector3(0, 0, 5.4), "old 02 school gate"):
			if await _use_exit(&"school_gate", &"front_yard", &"FromCorridor"):
				# Round 24: down the gate steps the arrival walks on toward the gate (`entry_walk`).
				var yard_arrival := _host.get_current().get_spawn(&"FromCorridor").global_position
				_check.expect(_player.global_position.x - yard_arrival.x > 1.8,
					"The front yard arrival did not walk on from %s (at %s)." % [yard_arrival, _player.global_position])
				await _check_glass_entrance()
	if _host.get_current().location_id == &"corridor":
		await _check_rear_stair_and_laboratory(_host.get_current())
	if _check.expect(not _directory_checkpoints.is_empty(), "The directory never reached its save cases."):
		if _check.expect(await DirectoryCase.close_world(main), "Could not close the walking world's scene."):
			await DirectoryCase.check_resume(self, main_scene, _directory_checkpoints, _check)
	_finish()


func _finish() -> void:
	Harness.finish(self, _check.failures,
		"the biology doors match on both sides and only the front door routes; "
		+ "the ten bays, masonry and divided windows, older exits and both peek inputs still work; "
		+ "the 01 glass entrance is passable and connected to the front yard, and the yard's side door to the street; the rear stair and hidden laboratory still work; "
		+ "directory poses and the wall's shortened revisit survive resuming a checkpoint.")


func _check_structure(corridor: LocationRoot, nav: LocationNavigation) -> void:
	_check_entry_headings()
	_check.expect(corridor.get_node_or_null(^"StageArt/Beyond") == null, "The old inaccessible extension was left in.")
	var env := (corridor.get_node(^"WorldEnvironment") as WorldEnvironment).environment
	_check.expect(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH, "The hall lost its depth haze.")
	_check.expect(env.fog_light_color.is_equal_approx(env.background_color), "Distance haze no longer meets the background colour.")
	_check.expect(env.fog_depth_begin > _player.camera_rig.offset.length() and env.fog_depth_end < _camera.far * 0.5,
		"Fog is in front of the player or too close to the far plane.")
	_check.expect(env.tonemap_exposure < 0.68 and env.fog_height < -3.4,
		"The hall is not darker than #243, or the height haze has risen above the lowest landing.")
	var map := nav.get_navigation_map()
	for floor in [corridor.get_node(SCHOOL).get_node(^"LowerFloor"), corridor.get_node(UPPER)]:
		var count := 0
		for bay in floor.get_children():
			if not bay.is_in_group(&"teaching_bay"):
				continue
			count += 1
			_check_bay(bay as StaticBody3D, map)
		_check.expect(count >= 5, "%s has only %d classroom bays." % [floor.name, count])
	# Measure the long route from the fixed street-side entrance. The biology arrival
	# moved one door-spacing north; it is not the datum for the length of this gallery.
	var start := corridor.get_spawn(&"FromStreet").global_position
	var end := corridor.get_spawn(&"FromSchoolyard").global_position
	var path := NavigationServer3D.map_get_path(map, start, end, true)
	var length := _route_length(path)
	print("corridor art: gate to fire door %.1f m on the baked map" % length)
	_check.expect(not path.is_empty() and path[-1].distance_to(end) < 0.5 and length > 42.0,
		"The gate to fire door no longer follows a long connected route (%.1f m)." % length)
	var school := corridor.get_node(SCHOOL) as Node3D
	_check_separate_box_faces(school, ^"YardPortal/YardDoorStep", ^"YardPortal/YardDoorLeaf")
	_check_separate_box_faces(school, ^"YardPortal/CeilingReturn", ^"Stairs/YardLandingSide0/Plaster")
	_check_separate_box_faces(school, ^"UpperFloor/SouthGlazing/Bay0_0/SillWall", ^"UpperFloor/EastGlazing/Bay0_0/SillWall")


## The formerly identical faces were visible from the follow camera. The
## neighbouring boxes can meet or have a rebate, but cannot draw the same face.
## The four doorway arrivals that carry an explicit heading (entry_facing). Each must face
## the way the doorway needs: into the block when entering, away from the door when leaving.
func _check_entry_headings() -> void:
	var cases := [
		[CORRIDOR, &"FromTeachingEntrance", Vector3.FORWARD],
		[CORRIDOR, &"FromSchoolyard", Vector3.FORWARD],
		[FRONT_YARD, &"FromCorridor", Vector3.RIGHT],
		[PLAYGROUND, &"FromCorridor", Vector3.BACK],
	]
	for case in cases:
		var scene := (load(case[0]) as PackedScene).instantiate() as Node3D
		var spawn := scene.get_node_or_null(NodePath("SpawnPoints/%s" % case[1])) as Node3D
		_check.expect(spawn != null and bool(spawn.get_meta(&"entry_facing", false))
			and (-spawn.basis.z).dot(case[2]) > 0.99,
			"%s %s does not declare its doorway heading." % [case[0].get_file(), case[1]])
		scene.free()


func _check_separate_box_faces(bay: Node3D, first: NodePath, second: NodePath) -> void:
	var a := bay.get_node_or_null(first) as MeshInstance3D
	var b := bay.get_node_or_null(second) as MeshInstance3D
	if not _check.expect(a != null and b != null, "%s is missing a wall or ceiling piece." % bay.name):
		return
	var to_bay := bay.global_transform.affine_inverse()
	var ax := (to_bay * a.global_transform) * a.get_aabb()
	var bx := (to_bay * b.global_transform) * b.get_aabb()
	var coverage := ax.end.min(bx.end) - ax.position.max(bx.position)
	for axis in 3:
		var same_face := absf(ax.position[axis] - bx.position[axis]) < 0.001 or absf(ax.end[axis] - bx.end[axis]) < 0.001
		if same_face and coverage[(axis + 1) % 3] > 0.002 and coverage[(axis + 2) % 3] > 0.002:
			_check.fail("%s: %s and %s draw overlapping faces." % [bay.name, first, second])


func _route_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i-1].distance_to(path[i])
	return length


func _check_bay(bay: StaticBody3D, map: RID) -> void:
	var front := bay.get_node_or_null(^"FrontDoor") as Node3D
	var rear := bay.get_node_or_null(^"RearDoor") as Node3D
	var slit := bay.get_node_or_null(^"HighGlass") as MeshInstance3D
	if not _check.expect(front != null and rear != null and slit != null, "%s lost a door or high window." % bay.name):
		return
	for door in [front, rear]:
		var glass := bay.get_node_or_null(NodePath(String(door.name) + "Transom")) as MeshInstance3D
		_check.expect(glass != null and is_equal_approx(glass.position.x, door.position.x) and glass.position.y > 2.4,
			"%s/%s has no small glass above the door." % [bay.name, door.name])
	_check_separate_box_faces(bay, ^"Wall6_0", ^"CeilingReturn")
	_check_separate_box_faces(bay, ^"Return0", ^"RoomRoof")
	_check_separate_box_faces(bay, ^"Return1", ^"RoomBack")
	# Repeated classroom pieces used to have exact matches on the end or foot of
	# the bay, most visible in motion when the camera cut away the stairs or piers.
	for pair: Array in [[^"Pier0", ^"Wall0_0"], [^"Pier1", ^"Wall0_2"],
			[^"Skirt1", ^"Wall0_1"], [^"Return0", ^"RoomFloor"], [^"Return1", ^"RoomFloor"]]:
		_check_separate_box_faces(bay, pair[0], pair[1])
	var quad := slit.mesh as QuadMesh
	_check.expect(quad != null and quad.size.x > quad.size.y * 5.0 and is_equal_approx(slit.position.y, ROOM_WINDOW_Y),
		"%s's high window is not a narrow slit above standing eye height." % bay.name)
	_check.expect(minf(front.position.x, rear.position.x) < slit.position.x
		and slit.position.x < maxf(front.position.x, rear.position.x),
		"%s's high window is not between the two doors." % bay.name)
	var spot := bay.to_global(Vector3(slit.position.x, 0, 1.18))
	var closest := NavigationServer3D.map_get_closest_point(map, spot)
	var path := NavigationServer3D.map_get_path(map, _player.global_position, spot, true)
	_check.expect(closest.distance_to(spot) < 0.55 and not path.is_empty() and path[-1].distance_to(spot) < 0.55,
		"%s has no connected floor in front of its window." % bay.name)


## Snapshot the materials before the camera's wall fade can replace them with alpha copies.
## Use the wall's foot as the origin but the location's axes (the bay has its own yaw).
func _measure_biology_doors(location: LocationRoot, wall: Node3D, inside: bool) -> Dictionary:
	var foot := wall.global_position
	foot.y = location.global_position.y
	var to_wall := Transform3D(location.global_basis, foot).affine_inverse()
	var face := "Model" if inside else "Reverse"
	var walk_side := Vector3.LEFT if inside else Vector3.RIGHT
	var measured := {}
	for door_name in ["FrontDoor", "RearDoor"]:
		var door := wall.get_node_or_null(NodePath(door_name)) as ClassroomDoorDressing
		if not _check.expect(door != null, "%s is missing %s." % [location.name, door_name]):
			continue
		var parts := {}
		var paths := ["Model/Door_leaf", "Model/Door_frame_head"]
		for part in ["Door_panel_inset", "Door_vision_glass", "Door_handle_rosette", "Door_kick_plate"]:
			paths.append("%s/%s" % [face, part])
		for path in paths:
			var mesh := door.get_node_or_null(NodePath(path)) as MeshInstance3D
			if not _check.expect(mesh != null and mesh.material_override != null,
				"%s/%s is missing its dressed %s." % [location.name, door_name, path]):
				continue
			parts[mesh.name] = mesh.material_override
			if mesh.name == &"Door_handle_rosette":
				var latch := door.to_local(mesh.global_position)
				_check.expect(latch.x > 0.3 and (mesh.global_position - door.global_position).dot(walk_side) > 0.03,
					"%s/%s has the handle on the wrong edge or face." % [location.name, door_name])
		measured[door_name] = {"pose": to_wall * door.global_transform,
			"prefab": door.scene_file_path, "parts": parts}
	return measured


func _check_door_alignment(inside: Dictionary, outside: Dictionary) -> void:
	for door_name in ["FrontDoor", "RearDoor"]:
		if not inside.has(door_name) or not outside.has(door_name):
			continue # Reported by the measurement above.
		var room_pose: Transform3D = inside[door_name]["pose"]
		var hall_pose: Transform3D = outside[door_name]["pose"]
		_check.expect(room_pose.is_equal_approx(hall_pose),
			"%s does not line up across the wall: inside %s, outside %s." % [door_name, room_pose, hall_pose])
		_check.expect(inside[door_name]["prefab"] == outside[door_name]["prefab"]
			and inside[door_name]["parts"] == outside[door_name]["parts"],
			"%s does not use the same prefab and painted fittings on both sides." % door_name)


func _check_biology_thresholds(location: LocationRoot, wall: Node3D, inside: bool) -> void:
	var through := location.find_interactable(&"classroom_door" if inside else &"back_to_classroom") as LocationExit
	var locked := location.find_interactable(&"rear_door" if inside else &"corridor_rear_door")
	var front := wall.get_node_or_null(^"FrontDoor") as Node3D
	var rear := wall.get_node_or_null(^"RearDoor") as Node3D
	var spawn := location.get_spawn(&"FromCorridor" if inside else &"FromClassroom")
	if not _check.expect(through != null and locked != null and front != null and rear != null and spawn != null,
		"%s has no matching front threshold and rear-door inspection." % location.name):
		return
	# Inside, the door is staged for its one borrow attempt (ClassroomAnomalies) and
	# otherwise reads the same locked line; it is never an exit.
	_check.expect(not locked is LocationExit and (inside or not locked is StagedInteractable)
		and locked.inspection_id == &"classroom_rear_door",
		"The rear door is not an inspection-only target in %s." % location.name)
	if inside:
		var exits := location.get_interactables().filter(func(target: Interactable) -> bool: return target is LocationExit)
		_check.expect(exits.size() == 1 and exits[0] == through
			and through.required_flag == StoryFlags.CLASS_DISMISSED and not through.is_open(),
			"Only the front door may lead out, and only after the lesson.")
	var walk_side := Vector3.LEFT if inside else Vector3.RIGHT
	for pair in [[through, front], [locked, rear]]:
		var target := pair[0] as Interactable
		var door := pair[1] as Node3D
		var offset := target.global_position - door.global_position
		var outline := target.get_outline_meshes()
		_check.expect(absf(offset.z) < 0.02 and offset.dot(walk_side) > 0.0
			and not outline.is_empty() and outline.all(func(mesh: GeometryInstance3D) -> bool: return door.is_ancestor_of(mesh)),
			"%s points at the wrong door in %s." % [target.interact_id, location.name])
	var arrival := spawn.global_position - front.global_position
	_check.expect(absf(arrival.z) < 0.02 and absf(arrival.y) < 0.02 and arrival.dot(walk_side) > 0.0
		and (-spawn.global_basis.z).dot(walk_side) > 0.99,
		"%s does not land at the front door facing away from it." % spawn.name)


func _check_rear_door(corridor: LocationRoot, bay: StaticBody3D) -> void:
	var leaf := bay.get_node_or_null(^"RearDoor/Model/Door_leaf") as MeshInstance3D
	var locked := corridor.find_interactable(&"corridor_rear_door")
	if leaf == null or locked == null:
		return # The doorway contract already reports this.
	var centre := leaf.to_global(leaf.get_aabb().get_center())
	if not await _walk(Vector3(-1.2, 0, centre.z), "white rear door"):
		return
	_player.camera_rig.snap()
	var screen := _camera.unproject_position(centre)
	if not _check.expect(_interaction.get_target_at_screen_position(screen) == locked,
		"The white door does not point to its locked inspection from the corridor."):
		return
	_last_inspection = &""
	_pointer.click_at_screen_position(screen)
	var inspected := await Harness.wait_until(func() -> bool: return _last_inspection != &"", 3.0)
	_check.expect(inspected and _last_inspection == &"classroom_rear_door" and _host.get_current() == corridor,
		"Clicking the white rear door should inspect it and never change location.")
	await _dismiss_inspection()


func _check_glass_entrance() -> void:
	Harness.stage = "01 glass entrance from the front yard"
	var yard := _host.get_current()
	var yard_facade := yard.get_node_or_null(^"SchoolGlassEntrance") as Node3D
	if not _check.expect(yard_facade != null, "The front yard has no glass school entrance."):
		return
	var entrance_scene := yard_facade.scene_file_path
	if not await _walk(Vector3(-8.4, 0, 15.8), "front yard side of the glass entrance"):
		return
	if not await _use_exit(&"front_yard_back_inside", &"corridor", &"FromTeachingEntrance"):
		return
	var inside := _host.get_current()
	var doorway := inside.get_node_or_null(ENTRANCE) as Node3D
	var arrival := inside.get_spawn(&"FromTeachingEntrance")
	if not _check.expect(doorway != null and arrival != null and doorway.scene_file_path == entrance_scene,
		"The exterior and interior must share the same glass assembly."):
		return
	_check.expect(_player.get_facing_direction().dot(-arrival.global_basis.z) > 0.99,
		"Arrival from the front yard must face into the block, not keep the old heading.")
	var exterior := doorway.to_local(_player.global_position)
	_check.expect(exterior.z > 1.0 and absf(exterior.x) < 0.08 and absf(exterior.y) < 0.09,
		"Street arrival must put the player's feet outside, level with the door: %s." % exterior)
	var ground := doorway.get_parent()
	_check.expect(ground.find_children("BlindBay*", "Node3D", false, false).is_empty(),
		"A blind arch section survived on 01.")
	var directory_wall := ground.get_node_or_null(^"DirectoryWall") as Node3D
	_check.expect(directory_wall != null and doorway.global_position.z - directory_wall.global_position.z > 3.9,
		"The new door is not across the hall from the former arch wall.")
	var half_panel := doorway.get_node(^"Right/Pane") as MeshInstance3D
	var glass := half_panel.material_override as BaseMaterial3D
	_check.expect(glass != null and glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		and glass.albedo_color.a < 0.5, "The entrance sidelights are opaque.")
	var pose := _player.global_transform
	pose.origin = doorway.to_global(Vector3(2.18, 0.53, 1.35))
	var contact := KinematicCollision3D.new()
	_check.expect(_player.test_move(pose, Vector3.FORWARD * 2.7, contact)
		and contact.get_collider() == doorway.get_node(^"Right/GlassSafety"),
		"The side glazing was left open to the capsule.")
	pose.origin = doorway.to_global(Vector3(0, 0.045, 1.35))
	_check.expect(not _player.test_move(pose, Vector3.FORWARD * 2.7),
		"An invisible barrier crosses the centre of the glass entrance.")
	var nav := inside.get_node(^"Navigation") as LocationNavigation
	if _check.expect(await Harness.wait_until(nav.is_synchronized, 5.0), "01 never finished its navigation bake."):
		_check_entrance_route(nav.get_navigation_map(), doorway, arrival.global_position)

	# In the default camera basis W+D steps north. This crosses the portal with
	# actual continuous movement: no reload, no activation and no teleport.
	var cap := doorway.get_node(^"Header/EnamelCap") as MeshInstance3D
	var fade: Array[float] = [0.0]
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	var crossed := await Harness.wait_until(func() -> bool:
		fade[0] = maxf(fade[0], cap.transparency)
		return doorway.to_local(_player.global_position).z < -2.42, 6.0)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	_check.expect(fade[0] > 0.45, "The camera never clears the door cap while walking into 01.")
	if not _check.expect(crossed and _host.get_current() == inside and _player.is_on_floor(),
		"Keyboard movement did not carry the player through the glass doorway: %s." % _player.global_position):
		return
	await _check_directory(inside)
	# On the reversal Q is behind us. Line up on the other side of the opening,
	# then click the apron itself (not the street plaque's pick box beyond it).
	var companion := _host.get_parent().get_node(^"Companion") as CompanionController
	var lane := -0.84 if doorway.to_local(companion.global_position).x > 0.0 else 0.84
	if not await _walk(doorway.to_global(Vector3(lane * 1.3, 0, -2.42)), "01 passing lane"):
		return
	if await _click_floor(doorway.to_global(Vector3(lane, 0, 2.08)), "mouse through the open glass entrance"):
		if not _check.expect(doorway.to_local(_player.global_position).z > 1.0,
			"The click accepted the hall side instead of crossing to the apron."):
			return
		# Round 23: the apron walks out. Down its two steps onto the forecourt's soil, to
		# the gateposts; the exit stands between them, not on a railing at the apron's edge.
		if not await _walk(FORECOURT_GATE, "down the walk-out to the gateposts"):
			return
		if await _use_exit(&"teaching_entrance_to_street", &"front_yard", &"FromCorridor"):
			# Across the front yard and out of the side door: the school wall is the street's.
			if await _walk(Vector3(13.3, 0, 15.8), "front yard to the side door"):
				if await _use_exit(&"front_yard_to_street", &"street", &"FromCorridor"):
					_directory_checkpoints["wall"] = DirectoryCase.check_street_echo(_host.get_parent(), _check)
					if await _walk(Vector3(-9.5, 0, 15.8), "back to the side door"):
						if await _use_exit(&"street_back_to_school", &"front_yard", &"FromStreet"):
							if await _walk(Vector3(-8.4, 0, 15.8), "back across the front yard"):
								if await _use_exit(&"front_yard_back_inside", &"corridor", &"FromTeachingEntrance"):
									DirectoryCase.check_return(_host.get_current(), _check)


## A long click from outside should turn through the opening, not across a sill.
func _check_entrance_route(map: RID, doorway: Node3D, from: Vector3) -> void:
	var hall := doorway.to_global(Vector3(6.3, 0, -2.0))
	var route := NavigationServer3D.map_get_path(map, from, hall, true)
	if not _check.expect(not route.is_empty() and route[-1].distance_to(hall) < 0.6,
		"The apron route to the hall is partial: %s." % str(route)):
		return
	for i in range(1, route.size()):
		var a := doorway.to_local(route[i - 1])
		var b := doorway.to_local(route[i])
		if a.z > 0.0 and b.z <= 0.0:
			var threshold := a.lerp(b, a.z / (a.z - b.z))
			_check.expect(absf(threshold.x) < 1.14,
				"The baked route sent the player through a side pane: %s." % threshold)
			return
	_check.fail("The baked route never crossed the 01 threshold.")


func _check_directory(corridor: LocationRoot) -> void:
	Harness.stage = "optional bilingual directory"
	var directory := corridor.find_interactable(DIRECTORY)
	if not _check.expect(directory != null and directory.inspection_id == DIRECTORY,
		"The information panel is not inspectable."):
		return
	var library := InspectionLibrary.load_all()
	for locale: String in L10n.LOCALES:
		library.set_locale(locale)
		var record := library.get_inspection(DIRECTORY)
		_check.expect(record != null and not record.prompt.is_empty() and not record.text.is_empty(),
			"The directory's reading is absent in %s." % locale)
	_player.face_toward(directory.global_position - _player.global_position)
	if not await Harness.wait_until(func() -> bool: return _interaction.get_current_target() == directory, 3.0):
		_check.fail("No prompt at the directory's own wall.")
		return
	_last_inspection = &""
	_press_interact()
	var opened := await Harness.wait_until(func() -> bool: return _last_inspection == DIRECTORY, 5.0)
	if not _check.expect(opened, "The directory did not open through the normal inspection channel."):
		return
	await _dismiss_inspection()
	_directory_checkpoints = await DirectoryCase.use_tab(corridor, directory, _dialogue, _check, _press_interact)


## Take the new branches from the same landing without placing or reloading the player.
## The half landings put a real turn between each pair of flights, not another exit.
func _check_rear_stair_and_laboratory(corridor: LocationRoot) -> void:
	Harness.stage = "02 rear hub to 03 and back"
	var hub := corridor.get_node_or_null(^"TeachingBlock/RearStair/Junction") as Node3D
	var up := corridor.get_node_or_null(^"TeachingBlock/RearStair/UpLanding") as Node3D
	var down := corridor.get_node_or_null(^"TeachingBlock/RearStair/DownLanding") as Node3D
	var lab := corridor.get_node_or_null(^"TeachingBlock/GroundFloor/LaboratoryPortal/Door") as Node3D
	var screen_wall := corridor.get_node_or_null(^"TeachingBlock/GroundFloor/RecessScreen") as StaticBody3D
	var hall_spawn := corridor.get_spawn(&"FromLaboratory")
	if not _check.expect(hub != null and up != null and down != null and lab != null
		and screen_wall != null and hall_spawn != null, "The teaching block lost its new walk or threshold."):
		return
	var rear := corridor.find_interactable(&"corridor_rear_door")
	var rear_dz := hub.global_position.z - rear.global_position.z
	_check.expect(rear_dz > 1.0 and rear_dz < 4.5 and is_zero_approx(hub.global_position.y),
		"The new stair is not just beyond the biology rear door on 02.")
	var junction := hub.global_position
	var lower_landing := down.global_position
	if not await _walk(junction, "rear-door junction") or not await _walk(up.global_position, "03 half landing"):
		return
	var top := Vector3(-12, 3.6, -7.8)
	var school_nav := corridor.get_node(^"Navigation") as LocationNavigation
	var up_path := NavigationServer3D.map_get_path(school_nav.get_navigation_map(), _player.global_position, top, true)
	_check.expect(not up_path.is_empty() and up_path[-1].distance_to(top) < 0.5 and _route_length(up_path) < 18.0,
		"The upper flight detours through the old stair instead of meeting 03.")
	if not await _walk(top, "03 from the new stair"):
		return
	# Q has a solid capsule and stops behind us. On a reversal, use the side of
	# the 4.5 m gallery to pass, rather than clicking straight through another actor.
	var companion := _host.get_parent().get_node_or_null(^"Companion") as CompanionController
	if not _check.expect(companion != null and companion.is_with_player()
		and (companion.collision_layer & _player.collision_mask) != 0,
		"The new route must still work with the solid companion following the player."):
		return
	var passing_lane_x := -13.2
	if not await _walk(Vector3(passing_lane_x, top.y, top.z), "03 into the passing lane"):
		return
	if not await _click_floor(Vector3(passing_lane_x, top.y, -3.15), "03 floor click past Q"):
		return
	_check.expect(_player.global_position.z > companion.global_position.z and companion.is_with_player(),
		"The player and Q did not pass one another on the 03 gallery.")
	if not await _walk(up.global_position, "03 turn on the way back") or not await _walk(junction, "02 from 03"):
		return

	Harness.stage = "02 down to 01 and the hidden recess"
	if not await _walk(lower_landing, "01 half landing"):
		return
	var near_end := Vector3(-11.4, -3.4, 12.6)
	if not await _walk(near_end, "01 directory gallery from 02"):
		return
	_check.expect(_host.get_current() == corridor, "Walking between floors loaded a different location.")
	var leaf := lab.get_node(^"LeafLeft") as MeshInstance3D
	var sight := PhysicsRayQueryParameters3D.create(near_end + Vector3.UP * 1.43, leaf.global_position, 1)
	var blocked := _player.get_world_3d().direct_space_state.intersect_ray(sight)
	var blocker := blocked.get("collider") as StaticBody3D
	_check.expect(blocker != null and blocker != lab.get_parent() and screen_wall.get_parent().is_ancestor_of(blocker),
		"The laboratory door is in the direct sight line down 01, not behind the return.")
	var hall_step := hall_spawn.global_position
	var door_scene := lab.scene_file_path
	var door_basis := lab.global_basis
	if not await _walk(Vector3(-25, -3.4, 12.6), "end of the 01 gallery") or not await _walk(hall_step, "laboratory recess"):
		return

	Harness.stage = "laboratory mouse entry and return"
	_player.camera_rig.snap()
	var door_click := _camera.unproject_position(leaf.to_global(Vector3(0, 0, 0.145)))
	var enter := corridor.find_interactable(&"to_laboratory") as LocationExit
	if not _check.expect(enter != null and enter.destination_spawn == &"FromCorridor"
		and _interaction.get_target_at_screen_position(door_click) == enter,
		"The hidden door cannot be clicked from its own landing."):
		return
	_pointer.click_at_screen_position(door_click)
	var entered := await Harness.wait_until(func() -> bool:
		return (_host.get_current().location_id == &"laboratory" and _player.is_control_enabled()
			and _player.is_on_floor()), 10.0)
	if not _check.expect(entered and _host.get_current_spawn() == &"FromCorridor",
		"Clicking the hidden door did not enter the laboratory at its door."):
		return
	var room := _host.get_current()
	var inside := room.get_node_or_null(^"WallSouth/EntranceFrame") as Node3D
	var inside_step := room.get_spawn(&"FromCorridor").global_position
	_check.expect(inside != null and inside.scene_file_path == door_scene and inside.global_basis.is_equal_approx(door_basis)
		and absf(inside_step.x - inside.global_position.x) < 0.02 and inside_step.z < inside.global_position.z
		and _player.global_position.distance_to(inside_step) < 0.15,
		"The laboratory does not show the reverse of the same doorway at the arrival.")
	var nav := room.get_node(^"Navigation") as LocationNavigation
	if not await Harness.wait_until(nav.is_routable, 5.0):
		_check.fail("The laboratory entrance never became routable.")
		return
	if not await _walk(room.get_spawn(&"Entry").global_position, "into the working laboratory"):
		return
	# Return along the open south aisle, rather than retracing the approach through Q.
	if not await _walk(inside_step + Vector3.RIGHT * 2.25, "laboratory return aisle"):
		return
	if not await _walk(inside_step, "laboratory south door"):
		return
	if await _use_exit(&"laboratory_to_corridor", &"corridor", &"FromLaboratory"):
		_check.expect(_player.global_position.distance_to(hall_step) < 0.15,
			"The laboratory return did not land outside the same door on 01.")
		var returned_nav := _host.get_current().get_node(^"Navigation") as LocationNavigation
		if await Harness.wait_until(returned_nav.is_routable, 5.0):
			await _walk(lower_landing, "back up the lower flight after returning")
			await _walk(junction, "02 after visiting the laboratory")
		else:
			_check.fail("The returned 01 floor never became routable.")


func _check_yard_view(corridor: LocationRoot) -> void:
	var bay := corridor.get_node(^"TeachingBlock/LowerFloor/EastGlazing/Bay0_5")
	var pane := bay.get_node(^"ClearGlass") as MeshInstance3D
	var mat := pane.material_override as BaseMaterial3D
	_check.expect(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.25,
		"The gallery no longer uses see-through glass.")
	_check.expect(bay.is_in_group(&"camera_occluder") and bay.get_node_or_null(^"GlassSafety/Pane") is CollisionShape3D,
		"Glazing lost its safety collision or its cutaway fade.")
	var view := corridor.get_node(^"StageArt/Yard")
	var yard := (load("res://scenes/locations/playground/playground.tscn") as PackedScene).instantiate()
	for path in [^"CourtSurface", ^"HoopNearBoard", ^"ShedRoof", ^"PlaygroundArt/Court/LineCentre", ^"PlaygroundArt/Equipment/HoopFarRing"]:
		var outside := yard.get_node(path) as MeshInstance3D
		var inside_path := NodePath(String(path).trim_prefix("PlaygroundArt/"))
		var seen := view.get_node_or_null(inside_path) as MeshInstance3D
		_check.expect(seen != null and seen.position.is_equal_approx(outside.position)
			and seen.get_aabb().is_equal_approx(outside.get_aabb()) and seen.material_override == outside.material_override,
			"%s from the hall does not match the real yard." % path)
	var fire_door := yard.get_node(^"FireDoor") as MeshInstance3D
	var portal := corridor.get_node(^"TeachingBlock/YardPortal") as Node3D
	_check.expect((view as Node3D).to_global(fire_door.position).distance_to(portal.global_position + Vector3.UP * 1.3) < 0.02,
		"The fire stairs are not aligned with the fire door from the yard.")
	yard.free()
	_check.expect(corridor.get_node(^"StageArt").find_children("*", "CollisionObject3D", true, false).is_empty(),
		"The yard view contains live yard physics or hotspots.")


func _check_glass_collision(corridor: LocationRoot) -> void:
	for path: NodePath in [^"TeachingBlock/LowerFloor/EastGlazing/Bay0_3", ^"TeachingBlock/UpperFloor/EastGlazing/Bay0_6"]:
		var bay := corridor.get_node(path) as StaticBody3D
		var glass := bay.get_node(^"GlassSafety") as StaticBody3D
		var opening := (glass.get_node(^"Pane") as CollisionShape3D).shape as BoxShape3D
		var sill := (bay.get_node(^"SillWallSolid") as CollisionShape3D).shape as BoxShape3D
		var aperture := opening.size.x * opening.size.y
		_check.expect(opening.size.x >= 1.55 and opening.size.x <= 1.84
			and is_equal_approx(opening.size.y, 1.29) and is_equal_approx(sill.size.y, 1.06)
			and aperture < sill.size.x * 3.15 * .25, "%s is a slit or a window wall, not a regular window in masonry." % path)
		var space := _player.get_world_3d().direct_space_state
		# The aperture transmits a camera/ground ray, not the capsule. The same
		# horizontal ray at the sill, over the lintel, or in the pier meets masonry.
		for ray: Vector3 in [Vector3(0,.55,0), Vector3(0,2.70,0), Vector3(opening.size.x/2+.21,1.70,0), Vector3(.36,1.70,0)]:
			var into := PhysicsRayQueryParameters3D.create(bay.to_global(ray + Vector3.BACK), bay.to_global(ray + Vector3.FORWARD), 1)
			var view := space.intersect_ray(into)
			if is_equal_approx(ray.x,.36):
				_check.expect(view.is_empty(), "The aperture does not pass the ground ray in %s." % path)
				into.collision_mask = PLAYER_GLASS_LAYER
				_check.expect(space.intersect_ray(into).get("collider") == glass, "The aperture has no player barrier in %s." % path)
			else:
				_check.expect(view.get("collider") == bay, "Masonry fails to block the ray at %s in %s." % [ray,path])
		var from := _player.global_transform
		from.origin = glass.to_global(Vector3(-.5, 1.09, 1.0))
		var hit := KinematicCollision3D.new()
		# The 1.80 m capsule is taller than the window; hitting the lintel instead
		# of the pane also stops a jump. Neither shape alone substitutes for the other.
		var blocked := _player.test_move(from, -glass.global_basis.z * 2.0, hit)
		_check.expect(blocked and (hit.get_collider() == glass or hit.get_collider() == bay),
			"The player capsule can jump through %s." % path)


func _click_through_upper_window(corridor: LocationRoot, nav: LocationNavigation) -> void:
	# Aim through a specific sash of the new smaller opening, then continue
	# the actual screen ray to the floor. A fixed point on the old floor-to-
	# ceiling glass would now hit the lower wall instead of probing the pane.
	_player.camera_rig.snap()
	var pane := corridor.get_node(^"TeachingBlock/UpperFloor/EastGlazing/Bay0_6/GlassSafety") as StaticBody3D
	var from := _camera.global_position
	var pass_at := pane.to_global(Vector3(.39,1.90,0))
	var next := from.lerp(pass_at, (3.6-from.y)/(pass_at.y-from.y))
	var screen := _camera.unproject_position(next)
	var ray := PhysicsRayQueryParameters3D.create(_camera.project_ray_origin(screen), next, PLAYER_GLASS_LAYER)
	_check.expect(_player.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == pane,
		"The 03 floor click did not aim through the chosen sash.")
	var hit: Variant = _pointer.get_ground_point_at(screen)
	var on_floor := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), next)
	if _check.expect(hit is Vector3 and (hit as Vector3).distance_to(on_floor) < .12,
		"The 03 floor point is lost through the window (hit %s, wanted %s)." % [hit, on_floor]):
		_pointer.click_at_screen_position(screen)
		await _arrive(next, "03 clicked floor")


func _click_floor(destination: Vector3, label: String) -> bool:
	_player.camera_rig.snap()
	_pointer.click_at_screen_position(_camera.unproject_position(destination))
	if not _check.expect(_pointer.was_last_click_accepted(), "%s: %s" % [label, _pointer.get_last_rejection()]):
		return false
	return await _arrive(destination, label)


func _walk(destination: Vector3, label: String) -> bool:
	if not _check.expect(_player.request_path_to(destination), "%s: path request refused from %s." % [label, _player.global_position]):
		return false
	return await _arrive(destination, label)


func _arrive(destination: Vector3, label: String) -> bool:
	var route := _player.get_path_legs()
	var arrived := await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.is_on_floor(), 28.0)
	_player.cancel_path()
	print("corridor art: %s -> %s" % [label, _player.global_position])
	return _check.expect(arrived and _player.global_position.distance_to(destination) < 0.8,
		"%s: stopped at %s instead of walking to %s via %s." % [label, _player.global_position, destination, str(route)])


func _climb_with_keys() -> bool:
	# In the default 45-degree framing, these two inputs add up to due west.
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	var reached := await Harness.wait_until(func() -> bool: return _player.global_position.x < -10.8, 7.0)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	return _check.expect(reached and absf(_player.global_position.y - 3.6) < 0.15,
		"W+A did not take the player onto 03: %s" % _player.global_position)


func _check_peek(peek: Interactable, by_mouse: bool) -> void:
	if not _check.expect(peek is StagedInteractable and peek.has_method(&"can_peek_at"), "A high window is not staged."):
		return
	var feet := _player.global_position
	_check.expect(not peek.call(&"can_peek_at", feet), "%s can be read standing on the hall floor." % peek.interact_id)
	for other_floor in [-FLOOR_RISE, FLOOR_RISE]:
		_check.expect(not peek.call(&"can_peek_at", feet + Vector3.UP * (other_floor + 0.55)),
			"%s admits an eye at hop height on the wrong storey." % peek.interact_id)
	_last_inspection = &""
	_player.face_toward(peek.global_position - feet)
	if by_mouse:
		var pane := peek.get_outline_meshes()[0]
		_pointer.click_at_screen_position(_camera.unproject_position(pane.global_position))
		_check.expect(_pointer.was_last_click_accepted(), "Clicking the high glass was refused: %s" % _pointer.get_last_rejection())
	else:
		if not await Harness.wait_until(func() -> bool: return _interaction.get_current_target() == peek, 3.0):
			_check.fail("Facing the high window gave no prompt (got %s)." % _interaction.get_current_target())
			return
		_press_interact()
	var apex := feet.y
	var eyes_at_slit := false
	var deadline := Time.get_ticks_msec() + 2800
	while _last_inspection == &"" and Time.get_ticks_msec() < deadline:
		await physics_frame
		apex = maxf(apex, _player.global_position.y)
		eyes_at_slit = eyes_at_slit or bool(peek.call(&"can_peek_at", _player.global_position))
	_check.expect(apex > feet.y + 0.40 and eyes_at_slit and _player.is_on_floor()
		and _last_inspection == peek.inspection_id, "%s did not hop and present the inspection on landing (rise %.2f, inspection %s)." %
		[peek.interact_id, apex - feet.y, _last_inspection])
	await _dismiss_inspection()


func _dismiss_inspection() -> void:
	var dismissed := await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy(), 3.0)
	_check.expect(dismissed, "The inspection held the player after dismissal.")


func _use_exit(id: StringName, destination: StringName, spawn: StringName) -> bool:
	var exit := _host.get_current().find_interactable(id) as LocationExit
	if not _check.expect(exit != null and exit.destination_id == destination and exit.destination_spawn == spawn,
		"%s no longer leads to %s/%s." % [id, destination, spawn]):
		return false
	_player.face_toward(exit.global_position - _player.global_position)
	if not await Harness.wait_until(func() -> bool: return _interaction.get_current_target() == exit, 3.0):
		_check.fail("No %s prompt from %s (target %s)." % [id, _player.global_position, _interaction.get_current_target()])
		return false
	_press_interact()
	var arrived := await Harness.wait_until(func() -> bool:
		return _host.get_current().location_id == destination and _player.is_control_enabled() and _player.is_on_floor(), 10.0)
	return _check.expect(arrived and _host.get_current_spawn() == spawn, "%s did not complete the transition." % id)


func _press_interact() -> void:
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"interact"
	Input.parse_input_event(release)
