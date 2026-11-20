extends SceneTree
## Walk to both service controls using the live map, then use E and a world click.
## Optionally capture start, movement and outcome from the same game camera:
##   godot --resolution 1600x900 --script res://tests/school_facilities_test.gd -- capture=/tmp/service-frames

const Harness = preload("res://tests/test_harness.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const HALL := "res://scenes/locations/corridor/corridor.tscn"
const SCREEN := &"corridor_stair_screen"
const BELL := &"corridor_bell_register"
const SCHOOL_SCREEN := ^"TeachingBlock/Stairs/ClosedSection/Screen"
const REGISTER := ^"TeachingBlock/GroundFloor/EndWall/BellRegister"
const SCREEN_FEET := Vector3(.13, 1.8, -36.06)
const BELL_FEET := Vector3(-25.55, -3.4, 8.04)
const BEND := Vector3(0, 0, -28.02)
const OBJECTIVE := "objective.schoolyard"

var _check := Harness.Checker.new()
var _state: Node
var _save: Node
var _knowledge: Node
var _world: Node
var _host: LocationHost
var _director: OpeningSequence
var _dialogue: DialogueController
var _player: PlayerController
var _ic: InteractionController
var _pointer: PointerNavigator
var _camera: Camera3D
var _capture_dir := ""
var _frames := 0
var _last_inspection: StringName


func _initialize() -> void:
	Harness.arm_watchdog(self, 146.0, "school_facilities_test.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("capture="):
			_capture_dir = arg.trim_prefix("capture=")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir + "/review")
	var nodes := Harness.ensure_state_autoloads(self)
	_state = nodes["game_state"]
	_save = nodes["save"]
	_knowledge = nodes["narrative_state"]
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, OBJECTIVE)
	_boot()
	# Let the starting classroom finish its deferred navigation and chair binding
	# before asking the host to remove it in this route fixture.
	await process_frame
	if await _load_hall(&"FromClassroom") and await _screen_control() \
			and await _load_hall(&"FromTeachingEntrance") and await _bell_control():
		await _continue_and_exit()
	if not _capture_dir.is_empty():
		_check.expect(_frames == 6, "Expected six staged game frames; got %d." % _frames)
	Harness.clear_session_state(self)
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	await process_frame
	Harness.finish(self, _check.failures,
		"both controls walked to and used; the wall and register animate, persist and leave a walkable way back.")


func _boot() -> void:
	_world = MAIN.instantiate()
	_director = _world.get_node(^"OpeningSequence") as OpeningSequence
	_director.autostart = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_ic = _player.get_node(^"InteractionController") as InteractionController
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_camera = _player.camera_rig.camera
	_ic.mouse_targeting = false
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _last_inspection = id)
	_director.allow_player_control()
	# Restore boot normally fades in; the test bypasses autostart and owns that step.
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()


func _load_hall(spawn: StringName) -> bool:
	if not _check.expect(_host.load_location(HALL, spawn, _player, &"corridor"), "Cannot enter the hall at %s." % spawn):
		return false
	_state.set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
	return await _ready_in(&"corridor")


func _ready_in(id: StringName) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		var room := _host.get_current()
		return room != null and room.location_id == id and _player.is_on_floor() \
			and _player.is_control_enabled() and (room.get_node(^"Navigation") as LocationNavigation).is_routable(), 8.0),
		"Could not use the live map in %s (%s)." % [id, Harness.stage])


func _walk(point: Vector3) -> bool:
	if not _check.expect(_player.request_path_to(point), "No path from %s to %s." % [_player.global_position, point]):
		return false
	var arrived := await Harness.wait_until(func() -> bool:
		return _player.is_on_floor() and not _player.is_path_active() and _player.velocity.length() < .06, 20.0)
	print("service test: walked to %s (target %s)" % [_player.global_position, point])
	return _check.expect(arrived and _player.global_position.distance_to(point) < .70,
		"Did not walk to %s; ended at %s." % [point, _player.global_position])


func _screen_control() -> bool:
	Harness.stage = "02 into the offset stair and back down again"
	if not await _walk(BEND) or not await _walk(SCREEN_FEET):
		return false
	var hall := _host.get_current()
	var wall := hall.get_node(SCHOOL_SCREEN) as Node3D
	var button := hall.find_interactable(SCREEN)
	var guard := hall.get_node(^"TeachingBlock/Stairs/LandingNorth/Guard") as CollisionShape3D
	var original_guard := guard.global_transform
	var flag := StoryFlags.CORRIDOR_SCREEN_RAISED
	if not _check.expect(wall.position.y == 0.0 and not _state.get_flag(flag, false), "The stair wall started raised."):
		return false
	if not await _begin(button, false, "screen"):
		return false
	var travelled := await Harness.wait_until(func() -> bool:
		return wall.position.y > 1.05 and wall.position.y < 2.45, 4.0)
	_check.expect(travelled and _director.is_beat_active() and not _state.get_flag(flag, false),
		"The wall skipped its movement, released the player early, or recorded a partial pose.")
	await _frame("screen_1_moving")
	if not await _result(&"corridor_screen_reveal", flag, "screen"):
		return false
	_check.expect(wall.position.y > 2.58 and guard.global_transform == original_guard and not guard.disabled,
		"The screen did not rise above head height, or the opening moved the actual guard.")
	return await _walk(BEND)


func _bell_control() -> bool:
	Harness.stage = "01 through the lab return to the bell register"
	var hall := _host.get_current()
	_check.expect((hall.get_node(SCHOOL_SCREEN) as Node3D).position.y > 2.58, "Re-entering the block lowered the raised wall.")
	var button := hall.find_interactable(BELL)
	_check.expect(_ic.get_current_target() != button, "The small control is advertised at the front door.")
	if not await _walk(Vector3(-25.29, -3.4, 12.63)) or not await _walk(BELL_FEET):
		return false
	var register := hall.get_node(REGISTER)
	var first := register.get_node(^"Plate0") as Node3D
	var last := register.get_node(^"Plate2") as Node3D
	var bell := register.get_node(^"Bell") as AudioStreamPlayer3D
	var flag := StoryFlags.CORRIDOR_BELL_TESTED
	if not _check.expect(is_zero_approx(first.rotation.y) and is_zero_approx(last.rotation.y) \
			and not _state.get_flag(flag, false) and not bell.playing, "The bell did not start quiet with its plates face up."):
		return false
	if not await _begin(button, true, "bell"):
		return false
	var staggered := await Harness.wait_until(func() -> bool:
		return first.rotation.y > 3.04 and is_zero_approx(last.rotation.y), 4.0)
	_check.expect(staggered and bell.playing and not _state.get_flag(flag, false) and _director.is_beat_active(),
		"The first plate did not turn during the ring with the last plate still waiting.")
	await _frame("bell_1_moving")
	_check.expect(await Harness.wait_until(func() -> bool: return not bell.playing, 2.0)
		and is_zero_approx(last.rotation.y), "The last plate moved before the test ring stopped.")
	if not await _result(&"corridor_bell_reveal", flag, "bell"):
		return false
	_check.expect(last.rotation.y > 3.13 and not bell.playing, "The test did not end on a silent blank.")
	return true


func _begin(button: Interactable, mouse: bool, label: String) -> bool:
	if not _check.expect(button is StagedInteractable and button.camera_shot != null, "No staged %s control." % label):
		return false
	if not await _use(button, mouse):
		return false
	if not _check.expect(await Harness.wait_until(_director.is_beat_active, 2.8) and not _player.is_control_enabled(),
		"%s never took a staging beat." % label):
		return false
	if not _capture_dir.is_empty():
		# Both movement tracks start after the button press; use the actual focused shot.
		await Harness.wait_until(func() -> bool: return _player.camera_rig.get_focus_weight() > .83, 1.0)
		await _frame(label + "_0_start")
	return _check.expect(_player.camera_rig.get_focus_subject() == button, "The %s shot did not focus its control." % label)


func _result(id: StringName, flag: StringName, label: String) -> bool:
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _dialogue.get_runtime().get_active_conversation_id() == id and _dialogue.is_busy(), 5.0),
		"The %s outcome did not play its observation." % label):
		return false
	await _frame(label + "_2_result")
	var locale := L10n.current
	var text := String(_dialogue.get_current_line().get("text", ""))
	var other := "zh-CN" if locale == "en" else "en"
	_check.expect(_dialogue.apply_locale(other) and _dialogue.get_runtime().get_active_conversation_id() == id
		and String(_dialogue.get_current_line().get("text", "")) != text, "%s does not have a localized outcome." % label)
	_dialogue.apply_locale(locale)
	if not await _close():
		return false
	var read := _save.read_save() as Dictionary
	var payload: Dictionary = read.get("payload", {})
	var decoded := SaveCodec.decode_flags(payload.get("flags", {}))
	var entry: NarrativeEntry = _knowledge.get_entry(StringName("corridor_" + label + "_revealed"))
	return _check.expect(decoded.get("flags", {}).get(flag, false) and entry != null
		and entry.source == NarrativeEntry.Source.OBSERVED and _state.get_flag(StoryFlags.OBJECTIVE_KEY) == OBJECTIVE,
		"The %s completion, observation or unchanged objective is missing after the beat." % label)


func _continue_and_exit() -> void:
	Harness.stage = "Continue: both completed poses, no replay, and leave via the lab door"
	_world.queue_free()
	await process_frame
	_state.clear()
	_knowledge.clear()
	_boot()
	if not await _ready_in(&"corridor"):
		return
	var hall := _host.get_current()
	var last := hall.get_node(NodePath(String(REGISTER) + "/Plate2")) as Node3D
	_check.expect((hall.get_node(SCHOOL_SCREEN) as Node3D).position.y > 2.58 and last.rotation.y > 3.13
		and _knowledge.get_entry(&"corridor_screen_revealed") != null and _knowledge.get_entry(&"corridor_bell_revealed") != null,
		"Continue lost a completed pose or its journal entry.")
	var bell := hall.find_interactable(BELL)
	_last_inspection = &""
	if not _check.expect(bell.get_prompt_override() == "prompt.service_result", "A restored control still prompts to press."):
		return
	if not await _use(bell, false):
		return
	_check.expect(await Harness.wait_until(func() -> bool: return _last_inspection == BELL, 2.0),
		"The second use did not inspect the stationary result.")
	_check.expect(last.rotation.y > 3.13, "A revisit started the bell animation again.")
	if await _close() and await _walk(Vector3(-24.94, -3.4, 7.07)):
		if await _use(hall.find_interactable(&"to_laboratory"), false):
			await _ready_in(&"laboratory")


func _use(button: Interactable, mouse: bool) -> bool:
	if not _check.expect(button != null, "Missing interactable (%s)." % Harness.stage):
		return false
	_player.face_toward(button.global_position - _player.global_position)
	if mouse:
		var cap := button.get_node(^"Plunger") as MeshInstance3D
		var pixel := _camera.unproject_position(cap.global_position)
		if not _check.expect(_camera.get_viewport().get_visible_rect().has_point(pixel)
			and await Harness.wait_until(func() -> bool: return _ic.get_target_at_screen_position(pixel, false) == button, 2.6),
			"No visible button pick at %s from %s." % [pixel, _player.global_position]):
			return false
		var clicks := _pointer.get_world_click_event_count()
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = pixel
			event.global_position = pixel
			event.pressed = down
			Input.parse_input_event(event)
		return _check.expect(await Harness.wait_until(func() -> bool:
			return _pointer.get_world_click_event_count() == clicks + 1, 1.5) and _pointer.was_last_click_accepted(),
			"The world click was not accepted: %s." % _pointer.get_last_rejection())
	if not _check.expect(await Harness.wait_until(func() -> bool: return _ic.get_current_target() == button, 2.6),
		"No E prompt for %s at %s (actual target %s)." % [_describe(button), _player.global_position, _describe(_ic.get_current_target())]):
		return false
	for down in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = down
		Input.parse_input_event(event)
	return true


func _describe(target: Interactable) -> String:
	return String(target.interact_id) if target != null else "none"


func _close() -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy() and not _director.is_beat_active() and _player.is_control_enabled(), 3.0),
		"A service beat left the controls locked.")


func _frame(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not _check.expect(image != null and not image.is_empty(), "No real renderer image for %s." % name):
		return
	var filename := "service_%s.jpg" % name
	var full := image.save_jpg(_capture_dir.path_join(filename), .86)
	image.resize(432, 243, Image.INTERPOLATE_LANCZOS)
	var review := image.save_jpg(_capture_dir.path_join("review").path_join(filename), .69)
	if _check.expect(full == OK and review == OK, "Could not write %s." % filename):
		_frames += 1
