extends SceneTree
## The school block is a playable loop, not scenery past a locked end. Run on the
## shipped main scene: the production capsule, input, pointer, camera and transitions.
## CI entry: corridor_art. The separate location_art suite checks the exterior art.

const Harness = preload("res://tests/test_harness.gd")
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const SCHOOL := ^"TeachingBlock"
const BIOLOGY_BAY := ^"TeachingBlock/LowerFloor/LowerWest1"
const UPPER := ^"TeachingBlock/UpperFloor"
const LANDING := Vector3(2.2, 1.8, -35.75)
const FIRST_BEND := Vector3(0, 0, -27.75)
const SECOND_BEND := Vector3(-12, 3.6, -42.75)
const UPPER_EAST := Vector3(11.2, 3.6, -42.75)
const HALL_BY_WEST_STAIR := Vector3(0, 0, -8.45)
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


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "corridor_art_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
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
		var next := Vector3(-11.2, 3.6, -14.4)
		# A ground click must not stop at the nearer transparent pane, and it must
		# choose the upper floor the player pointed at, not look through it to the yard.
		_player.camera_rig.snap()
		var screen := _camera.unproject_position(next)
		var view_ray := PhysicsRayQueryParameters3D.create(_camera.project_ray_origin(screen), next, PLAYER_GLASS_LAYER)
		var barrier := _player.get_world_3d().direct_space_state.intersect_ray(view_ray)
		_check.expect(not barrier.is_empty() and (barrier["collider"] as Node).name == &"GlassSafety",
			"The 02 floor click didn't actually aim through the safety glass.")
		var hit: Variant = _pointer.get_ground_point_at(screen)
		var nav_point := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), next)
		if _check.expect(hit is Vector3 and (hit as Vector3).distance_to(nav_point) < 0.12,
			"A floor click on 02 was lost behind glazing (hit %s, wanted %s)." % [hit, nav_point]):
			_pointer.click_at_screen_position(screen)
			await _arrive(next, "02 clicked floor")
		var upper_peek := corridor.find_interactable(&"high_window_upperwest1")
		if await _walk(Vector3(-13.25, 3.6, -12.2), "02 high window"):
			await _check_peek(upper_peek, true)
		await _walk(SECOND_BEND, "upper bend")
		await _walk(UPPER_EAST, "upper east wing")
		await _walk(LANDING, "dogleg half landing")
		await _walk(FIRST_BEND, "ground floor via far stair")

	Harness.stage = "yard fire stair and two-way exit"
	var approach := corridor.get_spawn(&"FromSchoolyard")
	if await _walk(approach.global_position, "fire stair bottom"):
		if await _use_exit(&"to_schoolyard", &"playground", &"FromCorridor"):
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
		if _host.get_current().location_id == &"corridor" and await _walk(Vector3(0, 0, 5.4), "school gate"):
			if await _use_exit(&"school_gate", &"street", &"FromCorridor"):
				# The street spawn is across the pavement, not in reach of the gate.
				if await _walk(Vector3(-8.15, 0, 15.2), "street side of the gate"):
					await _use_exit(&"street_back_to_school", &"corridor", &"FromStreet")
	_finish()


func _finish() -> void:
	Harness.finish(self, _check.failures,
		"the biology doors match on both sides and only the front door routes; "
		+ "the ten bays, glazed galleries, stairs, two-way exits and both peek inputs still work.")


func _check_structure(corridor: LocationRoot, nav: LocationNavigation) -> void:
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
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i-1].distance_to(path[i])
	print("corridor art: gate to fire door %.1f m on the baked map" % length)
	_check.expect(not path.is_empty() and path[-1].distance_to(end) < 0.5 and length > 42.0,
		"The gate to fire door no longer follows a long connected route (%.1f m)." % length)


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
	_check.expect(not (locked is LocationExit or locked is StagedInteractable) and locked.inspection_id == &"classroom_rear_door",
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
	var glass := corridor.get_node(^"TeachingBlock/LowerFloor/EastGlazing/Bay0_3/GlassSafety") as StaticBody3D
	var from := _player.global_transform
	# Sweep the actual player capsule above the opaque rail, where only glass can stop it.
	from.origin = glass.to_global(Vector3(-0.5, 1.05, 1.0))
	var hit := KinematicCollision3D.new()
	var blocked := _player.test_move(from, -glass.global_basis.z * 2.0, hit)
	_check.expect(blocked and hit.get_collider() == glass,
		"The player capsule can pass through a glazed bay above the rail.")


func _walk(destination: Vector3, label: String) -> bool:
	if not _check.expect(_player.request_path_to(destination), "%s: path request refused from %s." % [label, _player.global_position]):
		return false
	return await _arrive(destination, label)


func _arrive(destination: Vector3, label: String) -> bool:
	var arrived := await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.is_on_floor(), 28.0)
	_player.cancel_path()
	print("corridor art: %s -> %s" % [label, _player.global_position])
	return _check.expect(arrived and _player.global_position.distance_to(destination) < 0.8,
		"%s: stayed at %s instead of walking to %s." % [label, _player.global_position, destination])


func _climb_with_keys() -> bool:
	# In the default 45-degree framing, these two inputs add up to due west.
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	var reached := await Harness.wait_until(func() -> bool: return _player.global_position.x < -10.8, 7.0)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	return _check.expect(reached and absf(_player.global_position.y - 3.6) < 0.15,
		"W+A did not take the player onto 02: %s" % _player.global_position)


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
