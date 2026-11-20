extends SceneTree
## Every newly fitted end room and both optional studies on each floor. Starts
## from the real director and controller: no injected unlock or second dice roll.
## --room-tour separately exercises the developer scene, including save isolation.

const Harness = preload("res://tests/test_harness.gd")
const TOUR := "res://scenes/dev/school_room_tour.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const STUDIES := {
	&"archive": [&"FromArchive", -3.4, true, Vector3(1.04, 0, -0.39)],
	&"plan_room": [&"FromPlanRoom", -3.4, false, Vector3(0.42, 0, 0.13)],
	&"projection_room": [&"FromProjectionRoom", -3.4, true, Vector3(0.84, 0, 1.48)],
	&"computer_room": [&"FromComputerRoom", 0.0, false, Vector3(1.58, 0, -0.87)],
	&"vacant_office": [&"FromVacantOffice", 0.0, true, Vector3(1.09, 0, -0.34)],
	&"principal_office": [&"FromPrincipalOffice", 3.6, false, Vector3(1.47, 0, -0.34)],
}
const WC := {&"restroom": &"FromRestroom", &"restroom_02": &"FromRestroom02", &"restroom_03": &"FromRestroom03"}
const OBJECTIVE := "objective.schoolyard"

var _check := Harness.Checker.new()
var _main: Node
var _state: Node
var _save: Node
var _knowledge: Node
var _journal: JournalCatalog
var _sequence: OpeningSequence
var _host: LocationHost
var _player: PlayerController
var _ic: InteractionController
var _pointer: PointerNavigator
var _dialogue: DialogueController
var _rolls: Array[Dictionary] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 345.0, "school_expansion_test.gd")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	if "--room-tour" in OS.get_cmdline_user_args():
		await _run_tour()
		return
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_save = autoloads["save"]
	_knowledge = autoloads["narrative_state"]
	_journal = JournalCatalog.build(null, InspectionLibrary.load_all())
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, OBJECTIVE)
	_boot()
	if await _settled(&"classroom") and _check.expect(
		_host.load_location(CORRIDOR, &"FromClassroom", _player, &"corridor"), "Could not start from 02."):
		_state.set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
		if await _settled(&"corridor"):
			_check_connected_landings()
			await _visit_all()
	_save.forget_all()
	await _finish("three end restrooms, six room-specific trials of Orientation, unlock discipline, same-door returns and continue.")


func _run_tour() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_save = autoloads["save"]
	Harness.clear_session_state(self)
	var sentinel := &"tour_fixture_live_save"
	_state.set_flag(sentinel, true)
	var saved: Dictionary = _save.save_game()
	_check.expect(saved.get("ok", false), "Could not write a pre-existing live save for the tour fixture.")
	var before := FileAccess.get_file_as_bytes(SaveFileStore.SAVE_PATH)
	_state.clear()
	var tour := (load(TOUR) as PackedScene).instantiate()
	root.add_child(tour)
	Harness.stage = "tour from the real 01 entrance"
	if _check.expect(await Harness.wait_until(func() -> bool: return tour.has_node(^"Main"), 8.0),
		"The dev entrance could not start."):
		_main = tour.get_node(^"Main")
		_bind_world()
		if await _settled(&"corridor"):
			_check.expect(_host.get_current_spawn() == &"FromTeachingEntrance",
				"The tour did not start at the real entrance.")
			_check.expect(not _state.get_flag(sentinel, false) and not _save.has_save() and _save.writes_suspended(),
				"The tour exposed or restored the pre-existing story save.")
			await _check_tour_pause()
			_check_connected_landings()
			await _visit_tour()
	_check.expect(not before.is_empty() and before == FileAccess.get_file_as_bytes(SaveFileStore.SAVE_PATH),
		"The tour changed the pre-existing save bytes.")
	_save.io = null
	_save.suspend_writes(false)
	_save.forget_all()
	await _finish("dev entrance, physical route into the recess, six open studies, public office/WC, isolated pause and saves.")


func _check_tour_pause() -> void:
	var pause := _main.get_node(^"PauseMenu") as PauseMenu
	_tap_action(&"pause")
	if _check.expect(await Harness.wait_until(pause.is_open, 2.0), "The tour could not open its pause menu."):
		_check.expect(pause.get_entry(&"resume").is_visible_in_tree()
			and not pause.get_entry(&"new_game").is_visible_in_tree()
			and not pause.get_entry(&"save_quit").is_visible_in_tree()
			and pause.get_status_text() == L10n.t("menu.no_save_yet"),
			"Pausing exposed the live save or a story session command.")
		_tap_action(&"pause")
		_check.expect(await Harness.wait_until(func() -> bool: return not pause.is_open() and not paused, 2.0),
			"Could not resume the tour after pausing.")
		# Keep cleanup and the other tour assertions useful even if the key did not close it.
		pause.close()


func _tap_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _visit_tour() -> void:
	var destinations := {&"projection_room": &"FromProjectionRoom", &"archive": &"FromArchive",
		&"plan_room": &"FromPlanRoom", &"vacant_office": &"FromVacantOffice", &"computer_room": &"FromComputerRoom",
		&"principal_office": &"FromPrincipalOffice", &"staff_office": &"FromStaffOffice", &"restroom_03": &"FromRestroom03"}
	for id: StringName in destinations:
		Harness.stage = "tour to %s and back" % id
		var hall := _host.get_current()
		var marker: StringName = destinations[id]
		var door := hall.find_interactable(StringName("to_" + String(id))) as LocationExit
		var landing := hall.get_spawn(marker)
		if not _check.expect(door != null and door.is_open() and landing != null, "Tour door unavailable: %s." % id):
			return
		var feet := landing.global_position
		if id == &"projection_room":
			# Do not warp past the return: make the real controller negotiate the
			# glass opening, forecourt corner and short lab corridor before clicking.
			if not _check.expect(_player.request_path_to(feet) and await Harness.wait_until(func() -> bool:
				return not _player.is_path_active() and _player.global_position.distance_to(feet) < .69, 24.0),
				"No live route from the glass forecourt to the projection recess."):
				return
		if id in STUDIES:
			var slide := hall.find_interactable(StringName("align_" + String(id)))
			_check.expect(slide != null and not slide.can_interact(), "The tour still offers a calibration for %s." % id)
		if not await _use(door, feet, id in [&"projection_room", &"vacant_office", &"computer_room"]) or not await _settled(id):
			return
		if not await _return_to_same_threshold(id, marker, feet):
			return
		if id in STUDIES:
			_check.expect(not _state.get_flag(StringName("annex.%s.aligned" % id), false)
				and not _state.get_flag(StoryFlags.inspection_seen_flag(StringName("%s_threshold" % id)), false),
				"Tour access recorded a clue or alignment for %s." % id)
	_check.expect(_rolls.is_empty(), "Tour access rolled an Orientation check.")


func _finish(message: String) -> void:
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	await process_frame
	Harness.finish(self, _check.failures, message)


func _boot() -> void:
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(_main)
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_bind_world()
	_sequence.allow_player_control()


func _bind_world() -> void:
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_host = _main.get_node(^"LocationHost") as LocationHost
	_player = _main.get_node(^"Player") as PlayerController
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_dialogue.get_runtime().check_resolved.connect(_on_roll)
	_ic = _player.get_node(^"InteractionController") as InteractionController
	_ic.mouse_targeting = false
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator


func _on_roll(result: Dictionary) -> void:
	_rolls.append(result.duplicate(true))


func _check_connected_landings() -> void:
	var hall := _host.get_current()
	var nav := hall.get_node(^"Navigation") as LocationNavigation
	var map := nav.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(map, _player.global_position)
	var markers: Array = WC.values()
	for id: StringName in STUDIES:
		markers.append(STUDIES[id][0])
		var marker := hall.get_spawn(STUDIES[id][0])
		if marker != null:
			_check.expect(is_equal_approx(marker.global_position.y, float(STUDIES[id][1])), "%s is on the wrong storey." % id)
	for key: StringName in markers:
		var stance := hall.get_spawn(key)
		if not _check.expect(stance != null, "Missing landing %s." % key):
			continue
		var projected := nav.project_point(stance.global_position)
		if not _check.expect(projected["ok"], "Could not project %s onto the hall: %s" % [key, projected["reason"]]):
			continue
		var goal: Vector3 = projected["point"]
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		# The baked polygon is on a voxel plane above the physics floor. Keep
		# the landing close in XZ and reject a projection onto another storey.
		var voxel_lift := 2.0 * NavigationServer3D.map_get_cell_height(map) + .01
		_check.expect(float(projected["offset"]) < .31 and absf(goal.y - stance.global_position.y) <= voxel_lift
			and path.size() >= 2 and path[-1].distance_to(goal) < .25,
			"%s is not connected to the hall start (projected to %s from %s)." % [key, goal, stance.global_position])


func _visit_all() -> void:
	for id: StringName in WC:
		Harness.stage = "direct washroom door %s" % id
		if not await _visit_wc(id, WC[id]):
			return
	for id: StringName in STUDIES:
		Harness.stage = "local marks, roll and reveal for %s" % id
		if not await _study(id, STUDIES[id][0], STUDIES[id][2], STUDIES[id][3]):
			return
	_check.expect(_rolls.size() == STUDIES.size(), "One roll per study, even across manual recovery and Continue.")
	_check.expect(_state.get_flag(StoryFlags.OBJECTIVE_KEY) == OBJECTIVE, "An optional room changed the main objective.")


func _visit_wc(id: StringName, marker: StringName) -> bool:
	var hall := _host.get_current()
	var feet := hall.get_spawn(marker).global_position
	var exit := hall.find_interactable(StringName("to_"+id)) as LocationExit
	if not _check.expect(exit != null and exit.required_flag.is_empty(), "A public washroom has a gate."):
		return false
	if not await _use(exit, feet, id == &"restroom_02") or not await _settled(id):
		return false
	var wash := _host.get_current()
	var body := wash.get_node_or_null(^"Fittings/Cubicles/SquatPan/Recess") as MeshInstance3D
	_check.expect(body != null and body.get_aabb().size.y > .16 and body.get_aabb().size.z > .82,
		"%s has no recessed squat pan." % id)
	for i in 2:
		var pocket := wash.get_node_or_null("Fittings/Urinals/Urinal%d/Pocket" % i) as MeshInstance3D
		_check.expect(pocket != null and pocket.get_aabb().size.z > .35, "%s has no hollow urinal %d." % [id, i])
	var fly_count := 0
	for cloud in wash.get_node(^"FlyClouds").get_children():
		var batch := cloud as MultiMeshInstance3D
		fly_count += batch.multimesh.instance_count if batch != null and batch.multimesh != null else 0
	_check.expect(fly_count >= 50, "%s lost its batched fly clusters." % id)
	return await _return_to_same_threshold(id, marker, feet)


func _study(id: StringName, marker: StringName, success: bool, observation_stance: Vector3) -> bool:
	var hall := _host.get_current()
	var feet := hall.get_spawn(marker).global_position
	var route := StringName("align_"+id)
	var door_id := StringName("to_"+id)
	var clue := StringName(String(id)+"_threshold")
	var door := hall.find_interactable(door_id) as LocationExit
	var slide := hall.find_interactable(route)
	if not _check.expect(door != null and slide != null and not door.is_open(), "Fresh %s was open or incomplete." % id):
		return false
	# The return marker faces out of the portal. The lever anchor is offset
	# along the leaf, so the vector from it would skew the stance sideways.
	var toward_hall := -hall.get_spawn(marker).global_basis.z
	var slide_stance := Vector3(slide.global_position.x, feet.y, slide.global_position.z) + toward_hall * 1.05
	var record_key := StoryFlags.check_record_flag(route, &"bearing")
	if not await _show_choices(slide, slide_stance, route, id == &"archive"):
		return false
	_check.expect(_choices() == [&"leave"], "%s can roll without a clue: %s." % [id, _choices()])
	if not _choose(&"leave") or not await _close():
		return false
	if not await _use(door, feet, id == &"archive"):
		return false
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _dialogue.get_current_line().get("inspection_id") == clue, 5.0), "%s refused without its clue." % id):
		return false
	if not await _close():
		return false
	_check.expect(_host.get_current() == hall and not door.is_open()
		and _state.get_flag(StoryFlags.inspection_seen_flag(clue), false), "Trying %s skipped the gate or lost the clue." % id)
	var roll_count := _rolls.size()
	# Pick sums strictly either side of 10/11 for the shipped +3 voice. This
	# seeds the single real resolver; it does not inject the outcome flag.
	if not _set_die(String(route)+"/bearing", 11 if success else 4):
		return false
	if not await _show_choices(slide, slide_stance, route, id in [&"projection_room", &"vacant_office"]) \
		or not _choose(&"check") or not await _close():
		return false
	if not _check.expect(_rolls.size() == roll_count+1, "No unique roll for %s." % id):
		return false
	var rolled: Dictionary = _rolls.back()
	var record: Dictionary = _state.get_flag(record_key, {}).duplicate(true)
	_check.expect(not record.is_empty() and door.is_open() == success and rolled.get("success") == success
		and rolled.get("kind") == "visible" and rolled.get("ability") == &"orientation", "%s rolled or unlocked wrongly: %s" % [id, rolled])
	if not success:
		if not await _manual(slide, slide_stance, route, &"wrong"):
			return false
		_check.expect(not door.is_open(), "The wrong alignment opened %s." % id)
		if not await _manual(slide, slide_stance, route, &"correct"):
			return false
		_check.expect(door.is_open() and _state.get_flag(record_key,{}) == record
			and _rolls.size() == roll_count+1, "Manual recovery rerolled or failed to open %s." % id)
	if not await _use(door, feet, false) or not await _settled(id):
		return false
	var room := _host.get_current()
	var observed := StringName(String(id)+"_detail")
	var subject := room.find_interactable(observed)
	if not _check.expect(subject != null and subject.camera_shot != null and room.has_node(^"PaperAssembly")
		and room.has_node(^"FloorComposition"), "%s is not furnished with readable local media." % id):
		return false
	_check.expect(room.find_children("*", "SubViewport", true, false).is_empty(), "%s leaked a global experiment into play." % id)
	if not await _use(subject, observation_stance, id == &"computer_room"):
		return false
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _dialogue.get_current_line().get("inspection_id") == observed, 5.0), "No inspection for %s." % id):
		return false
	var log_id := StringName("saw_"+id+"_register")
	var note := _knowledge.get_entry(log_id) as NarrativeEntry
	_check.expect(note != null and note.source == NarrativeEntry.Source.OBSERVED
		and _journal.place_key_for(log_id) == "place."+id, "%s lost its local observation in the journal." % id)
	if not await _close():
		return false
	if id == &"computer_room" or id == &"archive":
		if not await _continue_in_room(id, record_key, record):
			return false
	if not await _return_to_same_threshold(id, marker, feet):
		return false
	var open_door := _host.get_current().find_interactable(door_id) as LocationExit
	if not _check.expect(open_door != null and open_door.is_open(), "Revisit locked %s again." % id):
		return false
	if id == &"archive":
		if not await _use(open_door, feet, true) or not await _settled(id):
			return false
		return await _return_to_same_threshold(id, marker, feet)
	return true


func _set_die(key: String, sum_to_get: int) -> bool:
	var resolver := CheckResolver.new()
	for seed in 256:
		resolver.set_session_seed(seed)
		if resolver.dice_total_for(key) == sum_to_get:
			_dialogue.set_session_seed(seed)
			return true
	return _check.expect(false, "Could not realize die sum %d for %s." % [sum_to_get,key])


func _manual(slide: Interactable, feet: Vector3, route: StringName, answer: StringName) -> bool:
	if not await _show_choices(slide, feet, route) or not _check.expect(
		_choices().has(&"manual") and not _choices().has(&"check"), "Manual recovery duplicated the roll.") or not _choose(&"manual"):
		return false
	return await _wait_choices(route) and _choose(answer) and await _close()


func _continue_in_room(id: StringName, key: StringName, record: Dictionary) -> bool:
	_sequence.autosave_enabled = true
	if not _check.expect(_sequence.autosave("school expansion fixture").get("ok", false), "Failed to save inside %s." % id):
		return false
	var origin := _player.global_position
	var journal: Dictionary = _knowledge.to_snapshot()
	_main.queue_free()
	await process_frame
	_state.clear()
	_knowledge.clear()
	_boot()
	if not await _settled(id):
		return false
	return _check.expect(_player.global_position.distance_to(origin) < .18 and _state.get_flag(key,{}) == record
		and _knowledge.to_snapshot() == journal and _state.get_flag(StringName("annex."+id+".aligned"), false), "%s lost the alignment or roll on Continue." % id)


func _return_to_same_threshold(id: StringName, marker: StringName, feet: Vector3) -> bool:
	var interior := _host.get_current()
	var back := interior.find_interactable(StringName(String(id)+"_to_corridor")) as LocationExit
	if not _check.expect(back != null and back.is_open() and back.destination_spawn == marker,
		"%s has no unconditional return to %s." % [id, marker]):
		return false
	var landing := interior.get_spawn(&"FromCorridor").global_position
	if not await _use(back, landing, id == &"restroom_03") or not await _settled(&"corridor"):
		return false
	return _check.expect(_player.global_position.distance_to(feet) < .16 and _host.get_current_spawn() == marker
		and _state.get_flag(StoryFlags.CURRENT_LOCATION) == &"corridor", "%s returned to another door." % id)


func _use(target: Interactable, stance: Vector3, via_mouse: bool) -> bool:
	# Each stance is a checked arrival position with a real nav route. Teleport
	# to it for the many dialogue branches instead of repeating the whole stair test.
	_player.teleport(Transform3D(Basis.IDENTITY, stance + Vector3.UP*.05))
	_player.face_toward(target.global_position - stance)
	_player.camera_rig.snap()
	if via_mouse:
		var id := target.interact_id
		var camera := _player.camera_rig.camera
		var mesh := target.get_outline_meshes()[0] as MeshInstance3D
		var screen := camera.unproject_position(mesh.to_global(mesh.get_aabb().get_center()))
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return _ic.get_target_at_screen_position(screen, false) == target, 3.0),
			"No pointer target %s from %s." % [target.interact_id, stance]):
			return false
		var clicks := _pointer.get_world_click_event_count()
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = screen
			event.global_position = screen
			event.pressed = pressed
			Input.parse_input_event(event)
		return _check.expect(await Harness.wait_until(func() -> bool:
			return _pointer.get_world_click_event_count() == clicks + 1, 1.5) and _pointer.was_last_click_accepted(),
			"World click for %s was not accepted: %s" % [id, _pointer.get_last_rejection()])
	if not _check.expect(await Harness.wait_until(func() -> bool: return _ic.get_current_target() == target, 3.0),
		"No E target %s from %s; got %s." % [target.interact_id, stance, _ic.get_current_target()]):
		return false
	_tap_action(&"interact")
	return true


func _settled(id: StringName) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		var current := _host.get_current()
		return current != null and current.location_id == id and _player.is_on_floor() \
			and _player.is_control_enabled() and (current.get_node(^"Navigation") as LocationNavigation).is_routable(), 12.0),
		"Not ready in %s (%s)." % [id, Harness.stage])


func _choices() -> Array[StringName]:
	return _dialogue.get_runtime().get_available_choice_ids()


func _choose(id: StringName) -> bool:
	var index := _choices().find(id)
	if not _check.expect(index >= 0, "Option %s absent from %s." % [id, _choices()]):
		return false
	_dialogue.select_choice(index)
	return true


func _show_choices(slide: Interactable, feet: Vector3, route: StringName, via_mouse: bool = false) -> bool:
	return await _use(slide, feet, via_mouse) and await _wait_choices(route)


func _wait_choices(route: StringName) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.has_pending_choices():
			return _dialogue.get_runtime().get_active_conversation_id() == route
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		return false, 5.0),
		"No choices from %s." % route)


func _close() -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy() and _player.is_control_enabled() and _player.camera_rig.get_focus_weight() < .03, 8.0), "Presentation did not return control.")
