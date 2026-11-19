extends SceneTree
## Start on the 02 biology landing, then use the real stairs, two doors each way,
## ordinary inspections, camera and a disk save made inside an optional room.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const OFFICE := &"staff_office"
const RESTROOM := &"restroom"
const ROTA := &"staff_office_rota"
const BASINS := &"restroom_basins"
const OBJECTIVE := "objective.schoolyard"
const ROTA_STANCE := Vector3(-2.19, 0, -0.14)
const BASINS_STANCE := Vector3(-2.12, 0, -0.98)

var _check := Harness.Checker.new()
var _state: Node
var _knowledge: Node
var _save: Node
var _loc: Node
var _original_locale: String
var _main: Node
var _host: LocationHost
var _sequence: OpeningSequence
var _player: PlayerController
var _interaction: InteractionController
var _pointer: PointerNavigator
var _dialogue: DialogueController
var _camera: Camera3D
var _journal: JournalCatalog


func _initialize() -> void:
	Harness.arm_watchdog(self, 210.0, "school_rooms_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	_state = autoloads["game_state"]
	_knowledge = autoloads["narrative_state"]
	_save = autoloads["save"]
	_loc = root.get_node(^"Loc")
	_original_locale = L10n.current
	_loc.set_locale("en")
	_journal = JournalCatalog.build(null, InspectionLibrary.load_all())
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, OBJECTIVE)
	_boot()
	if await _settled(&"classroom") and _check.expect(
		_host.load_location(CORRIDOR, &"FromClassroom", _player, &"corridor"), "Cannot start on 02."):
		_state.set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
		if await _visit_office():
			await _visit_restroom()
	_save.forget_all()
	_loc.set_locale(_original_locale)
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	await process_frame
	Harness.finish(self, _check.failures, "both hall branches walked and returned; six props read, real focus, observations and save/continue.")


func _boot() -> void:
	_main = (load(MAIN) as PackedScene).instantiate()
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(_main)
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_host = _main.get_node(^"LocationHost") as LocationHost
	_player = _main.get_node(^"Player") as PlayerController
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_interaction.mouse_targeting = false
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_camera = _player.camera_rig.camera
	_sequence.allow_player_control()


func _visit_office() -> bool:
	Harness.stage = "02 to 03 to the staff office"
	for point: Vector3 in [Vector3(0,0,-8.45), Vector3(-11.76,3.6,-8.45), Vector3(-12,3.6,-42.76)]:
		if not await _walk(point):
			return false
	var hall := _host.get_current()
	var door := hall.get_node(^"TeachingBlock/UpperFloor/OfficePortal/Door") as Node3D
	var hall_basis := door.global_basis
	var hall_scene := door.scene_file_path
	var hall_stance := hall.get_spawn(&"FromStaffOffice").global_position
	if not await _visit(&"to_staff_office", hall_stance, OFFICE, &"FromCorridor", true):
		return false
	_check_threshold(hall_scene, hall_basis)
	_check.expect(_state.get_flag(StoryFlags.OBJECTIVE_KEY) == OBJECTIVE, "The office changed the objective.")
	_check.expect(_host.get_current().find_children("*", "NpcActor", true, false).is_empty(), "The office introduced an actor.")
	Harness.stage = "office binder, trays and rail"
	if not await _inspect(ROTA, ROTA_STANCE, true, "first", "binder"):
		return false
	if not await _inspect(&"staff_office_trays", Vector3(2.08,0,-1.35), false, "first", "OUT"):
		return false
	if not await _inspect(&"staff_office_keys", Vector3(-3.04,0,-.25), false, "first", "four"):
		return false
	_check_note(&"saw_staff_office_rota", "place.staff_office")
	_check_note(&"saw_staff_office_keys", "place.staff_office")
	if not await _continue_inside(OFFICE):
		return false
	_loc.set_locale("zh-CN")
	var office := _host.get_current()
	_check.expect(_dialogue.get_interact_prompt(office.find_interactable(ROTA)) == "读桌上的值日表", "Chinese office prompt is missing.")
	if not await _inspect(ROTA, ROTA_STANCE, false, "repeat", "名字"):
		return false
	_loc.set_locale("en")
	if not await _visit(&"staff_office_to_corridor", office.get_spawn(&"FromCorridor").global_position,
		&"corridor", &"FromStaffOffice"):
		return false
	return _check.expect(_player.global_position.distance_to(hall_stance) < .14, "The office returns to the wrong landing.")


func _visit_restroom() -> void:
	Harness.stage = "03 down the rear stair to the 01 restroom"
	var stair := _host.get_current().get_node(^"TeachingBlock/RearStair")
	var points: Array[Vector3] = [Vector3(-12, 3.6, -42.76), Vector3(-12, 3.6, -3.12)]
	for name: String in ["UpLanding", "Junction", "DownLanding"]:
		points.append((stair.get_node(NodePath(name)) as Node3D).global_position)
	points.append(Vector3(-11.45, -3.4, 12.6))
	for point in points:
		if not await _walk(point):
			return
	var hall := _host.get_current()
	var door := hall.get_node(^"TeachingBlock/GroundFloor/RestroomPortal/Door") as Node3D
	var hall_basis := door.global_basis
	var hall_scene := door.scene_file_path
	var hall_stance := hall.get_spawn(&"FromRestroom").global_position
	if not await _visit(&"to_restroom", hall_stance, RESTROOM, &"FromCorridor"):
		return
	_check_threshold(hall_scene, hall_basis)
	_check.expect(_state.get_flag(StoryFlags.OBJECTIVE_KEY) == OBJECTIVE, "The restroom changed the objective.")
	_check.expect(_host.get_current().find_children("*", "NpcActor", true, false).is_empty(), "The restroom is not an unstaffed room.")
	Harness.stage = "restroom basins, cubicle and grate"
	if not await _inspect(BASINS, BASINS_STANCE, true, "first", "levers"):
		return
	if not await _inspect(&"restroom_latch", Vector3(2.18,0,.47), false, "first", "red"):
		return
	if not await _inspect(&"restroom_drain", Vector3(-.88,0,1.70), true, "first", "tile"):
		return
	_check_note(&"saw_restroom_drain", "place.restroom")
	if not await _continue_inside(RESTROOM):
		return
	_loc.set_locale("zh-CN")
	var room := _host.get_current()
	if not await _inspect(&"restroom_drain", Vector3(-.88, 0, 1.70), false, "repeat", "地漏边上"):
		return
	if await _visit(&"restroom_to_corridor", room.get_spawn(&"FromCorridor").global_position, &"corridor", &"FromRestroom", true):
		_check.expect(_player.global_position.distance_to(hall_stance) < .14, "The restroom returns to the wrong landing.")
		_check.expect(_knowledge.get_entries().size() == 3, "Unvisited or repeat props wrote extra notes.")


func _check_threshold(path: String, basis: Basis) -> void:
	var current := _host.get_current()
	var door := current.get_node(^"Door") as Node3D
	_check.expect(door.scene_file_path == path and door.global_basis.is_equal_approx(basis),
		"%s does not share the hall face of its own door." % current.location_id)
	var spawn := current.get_spawn(&"FromCorridor")
	_check.expect(door.to_local(spawn.global_position).z < -1.0
		and _player.get_facing_direction().dot(-door.global_basis.z) > .96,
		"%s does not arrive on the room face, facing inward." % current.location_id)
	var hit := KinematicCollision3D.new()
	_check.expect(_player.test_move(_player.global_transform, door.global_basis.z * 2.4, hit)
		and hit.get_collider() == door.get_node(^"Panel"), "The closed leaf did not stop the capsule.")


func _continue_inside(id: StringName) -> bool:
	Harness.stage = "save and continue in %s" % id
	_sequence.autosave_enabled = true
	var result := _sequence.autosave("school rooms test")
	if not _check.expect(result.get("ok", false), "Cannot save in %s." % id):
		return false
	var known: Dictionary = _knowledge.to_snapshot()
	var feet := _player.global_position
	_main.queue_free()
	await process_frame
	_state.clear()
	_knowledge.clear()
	_boot()
	if not await _settled(id):
		return false
	return _check.expect(_player.global_position.distance_to(feet) < .18 and _knowledge.to_snapshot() == known
		and _host.get_current_spawn() == &"FromCorridor" and _state.get_flag(StoryFlags.CURRENT_LOCATION) == id,
		"Continue lost the position, door spawn or observations for %s." % id)


func _check_note(id: StringName, place: String) -> void:
	var note := _knowledge.get_entry(id) as NarrativeEntry
	_check.expect(note != null and note.source == NarrativeEntry.Source.OBSERVED,
		"%s was not recorded as a direct observation." % id)
	_check.expect(_journal.place_key_for(id) == place, "The journal lists %s at the wrong place." % id)


func _settled(id: StringName) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		var current := _host.get_current()
		if current == null or current.location_id != id:
			return false
		var nav := current.get_node(^"Navigation") as LocationNavigation
		return nav.is_routable() and _player.is_on_floor() and _player.is_control_enabled(), 12.0),
		"The player never reached a usable floor in %s." % id)


func _walk(point: Vector3) -> bool:
	if not await _settled(_host.get_current().location_id):
		return false
	if _player.global_position.distance_to(point) < .18:
		return true
	if not _check.expect(_player.request_path_to(point), "No route from %s to %s." % [_player.global_position, point]):
		return false
	var arrived := await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.is_on_floor(), 27.0)
	print("school rooms: %s walked to %s" % [_host.get_current().location_id, _player.global_position])
	return _check.expect(arrived and _player.global_position.distance_to(point) < .62,
		"Stopped at %s instead of %s." % [_player.global_position, point])


func _use(id: StringName, stance: Vector3, mouse: bool) -> bool:
	if not await _walk(stance):
		return false
	var target := _host.get_current().find_interactable(id)
	if not _check.expect(target != null, "Missing %s." % id):
		return false
	_player.face_toward(target.global_position - _player.global_position)
	if mouse:
		_player.camera_rig.snap()
		var mesh := target.get_outline_meshes()[0] as MeshInstance3D
		var pixel := _camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_center())
		if not _check.expect(_camera.get_viewport().get_visible_rect().has_point(pixel)
			and await Harness.wait_until(func() -> bool:
				return _interaction.get_target_at_screen_position(pixel, false) == target, 2.5),
			"%s does not have a visible clickable face from %s (at %s)." % [id, _player.global_position, pixel]):
			return false
		_pointer.click_at_screen_position(pixel)
		return _check.expect(_pointer.was_last_click_accepted(), "%s pointer refused: %s" % [id, _pointer.get_last_rejection()])
	if not _check.expect(await Harness.wait_until(func() -> bool: return _interaction.get_current_target() == target, 3.0),
		"No E prompt for %s from %s." % [id, _player.global_position]):
		return false
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = &"interact"
	Input.parse_input_event(release)
	return true


func _visit(door: StringName, stance: Vector3, id: StringName, spawn: StringName, mouse: bool = false) -> bool:
	if not await _use(door, stance, mouse) or not await _settled(id):
		return false
	return _check.expect(_host.get_current_spawn() == spawn and _state.get_flag(StoryFlags.CURRENT_LOCATION) == id
		and not _dialogue.is_busy(), "The door led to a wrong spawn, flag or forced conversation.")


func _inspect(id: StringName, stance: Vector3, mouse: bool, variant: String, words: String) -> bool:
	if not await _use(id, stance, mouse):
		return false
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _dialogue.get_current_line().get("inspection_id", &"") == id, 5.0),
		"%s presented no inspection." % id):
		return false
	var line := _dialogue.get_current_line()
	_check.expect(line.get("variant") == variant and String(line.get("text")).contains(words)
		and line.get("source") == NarrativeEntry.Source.OBSERVED, "%s presented the wrong wording or kind." % id)
	var rig := _player.camera_rig
	var target := _host.get_current().find_interactable(id)
	if _check.expect(await Harness.wait_until(func() -> bool:
		return rig.get_focus_subject() == target and rig.get_focus_weight() > .97, 4.0),
		"The shot did not hold on %s." % id):
		var view := _camera.get_viewport().get_visible_rect().grow(-12.0)
		for mesh: GeometryInstance3D in target.get_outline_meshes():
			for corner in 8:
				var world := mesh.to_global(mesh.get_aabb().get_endpoint(corner))
				if not _check.expect(not _camera.is_position_behind(world) and view.has_point(_camera.unproject_position(world)),
					"%s shot cuts off %s." % [id, mesh.name]):
					break
	_dialogue.advance_presentation()
	return _check.expect(await Harness.wait_until(func() -> bool:
		return not _dialogue.is_busy() and _player.is_control_enabled() and rig.get_focus_weight() < .03, 5.0),
		"Dismissal of %s did not give movement and framing back." % id)
