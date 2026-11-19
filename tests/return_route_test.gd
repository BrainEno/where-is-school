extends SceneTree
## End-to-end on the shipped locations. Use the real capsule, lookup, pointer,
## E input and exits; only the initial spawn and the two deterministic dice cases
## are fixtures. Neither inspection nor outcome flags are handed to the player.

const Harness = preload("res://tests/test_harness.gd")
const STREET := "res://scenes/locations/street/street.tscn"
const SHED := &"pg_shed"
const COMPARE := &"compare_return"
const ROLL_NODE := &"ps_return_check"
const SHED_STANCE := Vector3(-12.12, 0, -4.0)
const BOARD_STANCE := Vector3(12.45, 0, 3.2)
const GUIDE_STANCE := Vector3(-11.48, 0, -9.6)

var _check := Harness.Checker.new()
var _state: Node
var _notes: Node
var _loc: Node
var _host: LocationHost
var _player: PlayerController
var _dialogue: DialogueController
var _interaction: InteractionController
var _camera: Camera3D
var _last_line: Dictionary = {}
var _rolls: Array[Dictionary] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 200.0, "return_route_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	_state = autoloads["game_state"]
	_notes = autoloads["narrative_state"]
	_loc = root.get_node(^"Loc")
	_loc.set_locale("en")
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	var sequence := main.get_node(^"OpeningSequence") as OpeningSequence
	sequence.autostart = false
	root.add_child(main)
	main.get_node(^"InnerVoiceDirector").set_process(false)
	_host = main.get_node(^"LocationHost") as LocationHost
	_player = main.get_node(^"Player") as PlayerController
	_dialogue = main.get_node(^"DialogueController") as DialogueController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_camera = main.get_node(^"CameraRig/Camera3D") as Camera3D
	_interaction.mouse_targeting = false
	_dialogue.line_presented.connect(func(line: Dictionary) -> void: _last_line = line)
	_dialogue.check_resolved.connect(func(result: Dictionary) -> void: _rolls.append(result.duplicate(true)))
	# Arrival lines are covered by opening_flow. This case concentrates on optional content.
	for flag in [StoryFlags.STREET_ARRIVED, StoryFlags.RESIDENTIAL_ARRIVED,
			StoryFlags.ALLEY_ARRIVED, StoryFlags.PLAYGROUND_ARRIVED]:
		_state.set_flag(flag, true)
	if _check.expect(_host.load_location(STREET, &"FromCorridor", _player, &"street"), "Street did not load."):
		sequence.allow_player_control()
		await _walk_return_route()
		if _host.get_current().location_id == &"playground":
			await _check_choices_and_notes()
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	await process_frame # Release stopped playbacks on the main thread before exit.
	Harness.finish(self, _check.failures,
		"four locations walked, seven props read, two locales, both seeded comparisons, and exits on either result.")


func _walk_return_route() -> void:
	Harness.stage = "street props and estate stair"
	if await _inspect(&"street_return_plate", &"street_return_plate", Vector3(-9.27, 0, -10.8), true):
		_expect_note(&"saw_street_return_plate")
		await _dismiss()
	if await _inspect(&"street_receipt_slot", &"street_receipt_slot", Vector3(-9.22, 0, -24.7)):
		await _dismiss()
	# Cross the road to the foot of the stairs before climbing, rather than
	# asking the capsule to mount the side of the existing ramp diagonally.
	if not await _walk(Vector3(10.5, 0.15, -29.8)):
		return
	if not await _exit(&"street_to_residential", Vector3(10.49, 1.6, -35.7), &"residential", &"FromStreet"):
		return

	Harness.stage = "courtyard and alley mouth"
	if not await _exit(&"res_alley_end", Vector3(6.0, 0, -33.75), &"alley", &"FromCourtyard"):
		return
	Harness.stage = "trolley guide, reversed plate and yard gate"
	if await _inspect(&"alley_trolley_guide", &"alley_trolley_guide", Vector3(-2.10, 0, 5.6)):
		await _dismiss()
	if await _inspect(&"alley_return_plate", &"alley_return_plate", Vector3(-2.10, 0, -18.55), true):
		_expect_note(&"saw_alley_return_plate")
		await _dismiss()
	await _exit(&"alley_to_playground", Vector3(0.24, 0, -20.63), &"playground", &"FromAlley")


func _check_choices_and_notes() -> void:
	Harness.stage = "tap and shed before reading the board"
	if await _inspect(&"pg_tap", &"pg_tap", Vector3(-4.67, 0, 14.42)):
		await _dismiss()
	if not await _open_shed(false):
		return
	if not await _select_and_close(&"leave"):
		return

	Harness.stage = "independent bilingual board inspection and repeat"
	if not await _inspect(&"pg_board_look", &"pg_return_board", BOARD_STANCE, true):
		return
	var board := _host.get_current().find_interactable(&"pg_board_look")
	_check.expect(await Harness.wait_until(func() -> bool:
		return _player.camera_rig.get_focus_subject() == board and _player.camera_rig.get_focus_weight() > 0.85, 4.0),
		"Reading the board did not engage its dedicated shot.")
	_check.expect(String(_last_line.get("text", "")).contains("fire door"), "The board did not give a way back to school.")
	_expect_note(&"saw_pg_return_board")
	await _dismiss()
	var note_count: int = _notes.get_entries().size()
	_loc.set_locale("zh-CN")
	_check.expect(_dialogue.get_interact_prompt(board) == "读操场交还板", "The board's Chinese prompt was lost.")
	if not await _inspect(&"pg_board_look", &"pg_return_board", BOARD_STANCE):
		return
	_check.expect(_last_line.get("variant") == "repeat" and String(_last_line.get("text", "")).contains("防火门"),
		"The second read did not show the Chinese repeat line.")
	_check.expect(_notes.get_entries().size() == note_count, "A repeat read duplicated the board's note.")
	await _dismiss()
	_check.expect(await Harness.wait_until(func() -> bool:
		return _player.camera_rig.get_focus_weight() < 0.01, 4.0), "The return-board shot held the camera after dismissal.")
	_loc.set_locale("en")

	var before_flags: Dictionary = _state.get_snapshot()
	var before_notes: Dictionary = _notes.to_snapshot()
	var resolver := CheckResolver.new()
	# One fixed sum is deliberately marginal: 6 + 3 < 10, but the guide supplies +1.
	# Search seeds, not playthroughs, so no randomness enters the test verdict.
	var seed_found := false
	for candidate in 128:
		resolver.set_session_seed(candidate)
		if resolver.dice_total_for("pg_shed/ps_return_check") == 6:
			seed_found = true
			break
	if not _check.expect(seed_found, "No deterministic marginal dice fixture."):
		return
	_dialogue.set_check_resolver(resolver)

	Harness.stage = "failed comparison does not lock the estate gate"
	if not await _compare(false, 0, &"pg_return_unclear"):
		return
	var key := StoryFlags.check_record_flag(SHED, ROLL_NODE)
	var failure_record: Dictionary = _state.get_flag(key, {}).duplicate(true)
	if not await _exit(&"pg_back_to_alley", Vector3(0.12, 0, 17.12), &"alley", &"FromPlayground"):
		return
	if not await _exit(&"alley_to_playground", Vector3(0.24, 0, -20.63), &"playground", &"FromAlley"):
		return
	if not await _inspect(&"pg_chalk_guide", &"pg_chalk_guide", GUIDE_STANCE):
		return
	_expect_note(&"saw_pg_chalk_guide")
	await _dismiss()
	if not await _open_shed(false):
		return
	_check.expect(_rolls.size() == 1 and _state.get_flag(key, {}) == failure_record,
		"Returning to the yard or finding the guide changed the recorded failure.")
	if not await _select_and_close(&"leave"):
		return

	# An independent pass starting before the attempt, for the other outcome.
	_state.replace_snapshot(before_flags)
	_notes.restore_snapshot(before_notes)
	Harness.stage = "guide bonus and school return on success"
	if not await _inspect(&"pg_chalk_guide", &"pg_chalk_guide", GUIDE_STANCE):
		return
	await _dismiss()
	if await _compare(true, 1, &"pg_return_match"):
		await _exit(&"pg_to_corridor", Vector3(-3.0, 0, -18.07), &"corridor", &"FromSchoolyard")


func _walk(destination: Vector3) -> bool:
	var nav := _host.get_current().get_node(^"Navigation") as LocationNavigation
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return nav.is_routable() and _player.is_control_enabled() and _player.is_on_floor(), 7.0),
		"No usable floor in %s: %s." % [_host.get_current().location_id, nav.get_bake_error()]):
		return false
	if _player.global_position.distance_to(destination) < 0.43:
		return true
	if not _check.expect(_player.request_path_to(destination), "No route to %s from %s." % [destination, _player.global_position]):
		return false
	var settled := await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.is_on_floor(), 24.0)
	return _check.expect(settled and _player.global_position.distance_to(destination) < 0.78,
		"Stopped at %s, not %s." % [_player.global_position, destination])


func _use(id: StringName, stance: Vector3, via_pointer: bool = false) -> bool:
	if not await _walk(stance):
		return false
	var target := _host.get_current().find_interactable(id)
	if not _check.expect(target != null, "Missing %s." % id):
		return false
	_player.camera_rig.snap()
	_player.face_toward(target.global_position - _player.global_position)
	if via_pointer:
		var mesh := target.get_outline_meshes()[0] as MeshInstance3D
		var pointer := _player.get_node(^"PointerNavigator") as PointerNavigator
		var pixel := _camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_center())
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return _interaction.get_target_at_screen_position(pixel, false) == target, 2.0),
			"%s has no clickable drawn face from %s (pixel %s)." % [id, _player.global_position, pixel]):
			return false
		pointer.click_at_screen_position(pixel)
		return true
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _interaction.get_current_target() == target, 3.0),
		"No E prompt for %s from %s; current target is %s." % [id, _player.global_position, _interaction.get_current_target()]):
		return false
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"interact"
	Input.parse_input_event(release)
	return true


func _inspect(id: StringName, inspection: StringName, stance: Vector3, via_pointer: bool = false) -> bool:
	_last_line = {}
	if not await _use(id, stance, via_pointer):
		return false
	return _check.expect(await Harness.wait_until(func() -> bool:
		return _last_line.get("inspection_id", &"") == inspection, 5.0),
		"%s did not present inspection %s (got %s)." % [id, inspection, _last_line.get("inspection_id")])


func _exit(id: StringName, stance: Vector3, location: StringName, spawn: StringName) -> bool:
	if not await _use(id, stance):
		return false
	return _check.expect(await Harness.wait_until(func() -> bool:
		return (_host.get_current().location_id == location and _host.get_current_spawn() == spawn
			and _player.is_control_enabled() and _player.is_on_floor()), 12.0),
		"%s did not let the player through to %s/%s." % [id, location, spawn])


func _open_shed(offer_comparison: bool) -> bool:
	if not await _use(&"pg_shed_door", SHED_STANCE):
		return false
	var runtime := _dialogue.get_runtime()
	if not _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.has_pending_choices():
			return true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		return false, 5.0), "The shed never offered choices."):
		return false
	var offered := runtime.get_available_choice_ids()
	return _check.expect(runtime.get_active_conversation_id() == SHED and offered.has(&"leave")
		and offered.has(&"frame") and offered.has(&"count") and offered.has(COMPARE) == offer_comparison,
		"Wrong shed choices (comparison expected: %s): %s." % [offer_comparison, offered])


func _compare(success: bool, modifier: int, note: StringName) -> bool:
	if not await _open_shed(true):
		return false
	var roll_count := _rolls.size()
	if not await _select_and_close(COMPARE):
		return false
	if not _check.expect(_rolls.size() == roll_count + 1, "Comparison did not resolve exactly once."):
		return false
	var result: Dictionary = _rolls.back()
	_check.expect(result.get("ability") == &"orientation" and result.get("die") == 6
		and result.get("kind") == "visible" and result.get("modifier") == modifier and result.get("success") == success,
		"Unexpected comparison result: %s." % result)
	_expect_note(note)
	_check.expect(not _state.get_flag(StoryFlags.PLAYGROUND_CHECKED, false),
		"Comparing the strip incorrectly completed the existing shed/ball beat.")
	print("return route: die=%s modifier=%s success=%s note=%s" % [result.get("die"), modifier, success, note])
	return true


func _select_and_close(choice: StringName) -> bool:
	var index := _dialogue.get_runtime().get_available_choice_ids().find(choice)
	if not _check.expect(index >= 0, "Could not select %s." % choice):
		return false
	_dialogue.select_choice(index)
	return await _dismiss()


func _dismiss() -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy() and _player.is_control_enabled(), 6.0),
		"Presentation did not return control at %s." % Harness.stage)


func _expect_note(id: StringName) -> void:
	var entry := _notes.get_entry(id) as NarrativeEntry
	_check.expect(entry != null and entry.source == NarrativeEntry.Source.OBSERVED,
		"The journal did not record %s as an observation." % id)
