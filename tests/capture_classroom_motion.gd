extends SceneTree
## Live-window acceptance for the classroom actions. Compare the fixed side view
## with the baseline and use the real gameplay camera for pointer/inspection checks.

const Harness = preload("res://tests/test_harness.gd")
const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
const APPROACH := Vector3(-0.75, 0, 2.15)
const OTHER_AISLE := Vector3(-2.43, 0, 2.83)
const CAMERA_AT := Vector3(0.65, 1.46, 2.48)
const LOOK_AT := Vector3(-1.53, 0.84, 1.95)

var _out := "build/classroom-motion"
var _check := Harness.Checker.new()
var _main: Node3D
var _player: PlayerController
var _sequence: OpeningSequence
var _interaction: InteractionController
var _dialogue: DialogueController
var _pointer: PointerNavigator
var _ui: GameUI
var _lid: Node3D
var _brace: Marker3D
var _room: LocationRoot
var _chair: PushableChair
var _seat: Interactable
var _bag: Interactable
var _game_camera: Camera3D
var _review: Camera3D
var _animator: CharacterVisualAnimation
var _rig: Skeleton3D
var _bones: Dictionary
var _clicked: Interactable


func _initialize() -> void:
	Harness.arm_watchdog(self, 130.0, "capture_classroom_motion.gd")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	if not _check.expect(DisplayServer.get_name() != "headless"
		and RenderingServer.get_current_rendering_method() == "gl_compatibility"
		and RenderingServer.get_current_rendering_driver_name() == "opengl3",
		"Classroom motion evidence requires a live Compatibility renderer."):
		_finish()
		return
	if not _check.expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out)) == OK,
		"Cannot create the evidence directory."):
		_finish()
		return
	print("MOTION_DISPLAY engine=%s display=%s renderer=%s adapter=%s" % [
		Engine.get_version_info().string, DisplayServer.get_name(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
	])
	if MobileLayout.enabled:
		Input.emulate_mouse_from_touch = true
		Input.emulate_touch_from_mouse = true
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := root.get_node_or_null("Loc")
	if loc != null:
		loc.set_locale("zh-CN")
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_main)
	_player = _sequence.get_player()
	_animator = _player.get_character_animator()
	_rig = _animator.get_skeleton()
	_bones = _animator.get_bind_report()["resolved"]
	_room = (_main.get_node(^"LocationHost") as LocationHost).get_current()
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_pointer.approach_activated.connect(func(target: Interactable) -> void: _clicked = target)
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_chair = _room.get_node(^"Furniture/DeskB2/Chair") as PushableChair
	_seat = _room.find_interactable(&"chair_sit")
	_bag = _room.find_interactable(&"schoolbag")
	_game_camera = (_main.get_node(^"CameraRig") as CameraRig).camera
	if not _check.expect(_seat != null and _bag != null, "The real chair or bag interaction is missing."):
		_finish()
		return
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_ui = _main.get_node(^"GameUI") as GameUI
	_lid = _room.get_node(^"Furniture/DeskB2/Schoolbag/Lid") as Node3D
	_brace = _room.get_node(^"Furniture/DeskB2/Schoolbag/MouthBrace") as Marker3D
	_ui.fade.set_clear()
	_player.settle_wake_seated_pose(0.0)
	_player.set_camera_roll(0.0)
	_sequence.allow_player_control()
	if not await _wait(func() -> bool: return _foot_on_floor("foot.L"), "wake foot to plant"):
		_finish()
		return

	if MobileLayout.enabled:
		await _run_touch()
	else:
		await _run_desktop()
	_finish()


func _run_desktop() -> void:
	_review = Camera3D.new()
	_main.add_child(_review)
	_review.position = CAMERA_AT
	_review.look_at(LOOK_AT)
	_review.fov = 53.0
	_review.current = true
	_check_seated("wake")
	await _shot("01_wake")

	# A real movement intent from the opening seat, not a direct pose call.
	Input.action_press(&"move_right")
	await _wait(_player.is_getting_up, "standing to begin")
	Input.action_release(&"move_right")
	if await _phase("classroom_rise", 0.42):
		var offset := _chair.to_local(_player.global_position)
		_check.expect(offset.z < -0.05 and offset.z > -0.58, "Chair and lift did not overlap in time.")
		_check.expect(not _seat.can_interact(), "A moving chair still offered a second activation.")
		_check_floor_and_grip("rise")
		await _shot("02_rising")
	await _wait(func() -> bool: return not _player.is_getting_up(), "stand-up to finish")
	await _wait(func() -> bool: return _chair_solid().collision_layer == PushableChair.SOLID_LAYER, "solid pushed stop")
	_check.expect(_player.global_position.distance_to(_chair.home_mark()) < 0.02, "Rising moved the capsule before input.")

	# Isolate the approach direction, not the seat pose. The rest of the action is
	# played by the same endpoint that clicks, taps and E use.
	await _place(APPROACH, Vector3.LEFT)
	_interaction.request_activation(_seat)
	if await _phase("classroom_sit", 0.52):
		_check.expect(not _player.is_seated(), "Sit-idle took over before the chair was home.")
		_check.expect(_chair_solid().collision_layer == 0, "Chair stayed solid during the pull.")
		_check_floor_and_grip("pull")
		await _shot("02b_lowering")
		await _pause_during_sit()
	await _wait(func() -> bool: return not _sequence.is_beat_active(), "sit request to finish")
	_check_seated("returned from right aisle")
	await _shot("03_returned_from_aisle")

	# Rise again via the actual staged stand, then enter from the other side with
	# the pointer. Both pick shapes should still follow their own visible meshes.
	_interaction.request_activation(_seat)
	await _wait(func() -> bool: return _chair.is_pushed_back() and not _sequence.is_beat_active(), "repeat stand")
	_game_camera.current = true
	await _place(OTHER_AISLE, Vector3.RIGHT)
	var seat_pixel := _seat_pixel()
	_check.expect(_interaction.get_target_at_screen_position(seat_pixel, false) == _seat,
		"The backrest pixel selected something other than the pushed chair.")
	_mouse_click(seat_pixel, _seat)
	_check.expect(not _player.is_seated(), "The click immediately posed the actor at the aisle.")
	await _wait(_settled_at_seat, "left-aisle mouse click to sit")
	_check_seated("mouse from left aisle")

	# From the seat a real click starts the search, including a stand. Both shapes
	# must pick their own object. The hover override only stabilizes the screenshot.
	var bag_pixel := _bag_pixel()
	_check.expect(_interaction.get_target_at_screen_position(_seat_pixel()) == _seat, "Seated chair pixel hit the bag or desk.")
	_check.expect(_interaction.get_target_at_screen_position(bag_pixel) == _bag, "Bag pixel hit another prop.")
	_interaction.set_mouse_override(bag_pixel)
	if await _wait(func() -> bool: return _interaction.get_current_target() == _bag, "bag hover"):
		await _shot("04_bag_target")
	_mouse_click(bag_pixel, _bag)
	_interaction.clear_mouse_override()
	if await _phase("schoolbag_search", 0.46):
		_check_search()
		await _shot("05a_search_game_camera")
		_review.position = Vector3(-0.60, 1.72, 2.55)
		_review.look_at(Vector3(-0.85, 0.85, 1.40))
		_review.fov = 53.0
		_review.current = true
		await _shot("05_rummaging")
	_game_camera.current = true
	await _finish_search()


func _run_touch() -> void:
	# Native touch path with mobile layout, in the X11 preview of the game.
	var seat_pixel := _seat_pixel()
	_check.expect(_interaction.get_target_at_screen_position(seat_pixel) == _seat, "Touch could not target the occupied chair.")
	_tap(seat_pixel, _seat)
	if not await _wait(func() -> bool: return _chair.is_pushed_back() and not _sequence.is_beat_active(), "stand on tap"):
		return
	await _place(APPROACH, Vector3.LEFT)
	seat_pixel = _seat_pixel()
	_check.expect(_interaction.get_target_at_screen_position(seat_pixel) == _seat, "Touch could not target the empty chair.")
	var events := _pointer.get_world_click_event_count()
	_touch(seat_pixel, true)
	_touch(seat_pixel, false, true)
	_check.expect(_pointer.get_world_click_event_count() == events and not _sequence.is_beat_active(),
		"A canceled chair tap started to walk or sit.")
	_tap(seat_pixel, _seat)
	_check.expect(not _player.is_seated(), "The tap posed the actor before walking to the seat.")
	if not await _wait(_settled_at_seat, "right-aisle touch to sit"):
		return
	_check_seated("touch from right aisle")
	await _shot("07_touch_returned")
	var bag_pixel := _bag_pixel()
	_check.expect(_interaction.get_target_at_screen_position(bag_pixel) == _bag, "Bag touch ray found the chair or desk instead.")
	_tap(bag_pixel, _bag)
	if await _phase("schoolbag_search", 0.46):
		_check_search()
		await _shot("08_touch_search")
	await _finish_search()


func _settled_at_seat() -> bool:
	return _player.is_seated() and not _sequence.is_beat_active()


func _seat_pixel() -> Vector2:
	var back := _chair.get_node(^"Back") as Node3D
	return _game_camera.unproject_position(back.global_position)


func _bag_pixel() -> Vector2:
	var shell := _room.get_node(^"Furniture/DeskB2/Schoolbag/Shell") as MeshInstance3D
	return _game_camera.unproject_position(shell.to_global(shell.get_aabb().get_center()))


func _mouse_click(pixel: Vector2, target: Interactable) -> void:
	_clicked = null
	var before := _pointer.get_world_click_event_count()
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = root.get_final_transform() * pixel
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		_send(click)
	_check.expect(_pointer.get_world_click_event_count() == before + 1, "Mouse press did not reach world input exactly once.")
	_check.expect(_clicked == target, "Mouse did not activate %s from its own visible pixel." % target.interact_id)


func _tap(pixel: Vector2, target: Interactable) -> void:
	_clicked = null
	var before := _pointer.get_world_click_event_count()
	_check.expect(MobileLayout.safe_rect(_ui.hud).has_point(pixel), "The target pixel is outside the touch safe area.")
	_touch(pixel, true)
	_check.expect(_pointer.get_world_click_event_count() == before, "Touch-down activated the prop.")
	_touch(pixel, false)
	_check.expect(_pointer.get_world_click_event_count() == before + 1, "A tap did not reach world input exactly once.")
	_check.expect(_clicked == target, "Touch did not activate %s from its own visible pixel." % target.interact_id)


func _touch(pixel: Vector2, down: bool, canceled: bool = false) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = root.get_final_transform() * pixel
	touch.index = 0
	touch.pressed = down
	touch.canceled = canceled
	_send(touch)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pause_during_sit() -> void:
	var menu := _main.get_node(^"PauseMenu") as PauseMenu
	var chair_at := _chair.global_position
	var phase := _animator.get_action_progress()
	menu.open()
	await create_timer(0.20, true, false, true).timeout
	_check.expect(paused and _sequence.is_beat_active() and _player.is_seat_transition_active()
		and _chair.global_position.is_equal_approx(chair_at) and is_equal_approx(phase, _animator.get_action_progress()),
		"Opening the real pause menu advanced part of the seat transfer.")
	menu.close()


func _check_floor_and_grip(label: String) -> void:
	var wrist := _joint("hand.L").distance_to(_chair.grip_point())
	_check.expect(wrist < 0.12, "%s: chair wrist missed its support by %.3f m." % [label, wrist])
	_check.expect(_foot_on_floor("foot.L") and _foot_on_floor("foot.R"), "%s: feet lost the floor during load bearing." % label)
	_check.expect(not _player.test_move(_player.global_transform.translated(Vector3.UP * 0.035),
		Vector3.ZERO, null, 0.001, true), "%s: the capsule intersects the desk during transfer." % label)
	print("MOTION_CONTACT %s wrist_gap=%.3f ankle_y=%.3f/%.3f" % [label, wrist, _joint("foot.L").y, _joint("foot.R").y])


func _check_search() -> void:
	var wrist := _joint("hand.R").distance_to(_brace.global_position)
	_check.expect(_lid.rotation_degrees.x < -70.0, "The rummage clip did not actually open the bag.")
	_check.expect(wrist < 0.12, "The bracing wrist missed the bag mouth by %.3f m." % wrist)
	_check.expect(_foot_on_floor("foot.L") and _foot_on_floor("foot.R"), "Searching the bag lost the floor.")
	_check.expect(not _dialogue.is_busy() and not _player.is_control_enabled() and not _has_missing_book(),
		"The original inspection or its effect started while the bag was still open.")
	print("MOTION_CONTACT bag wrist_gap=%.3f lid_deg=%.1f ankle_y=%.3f/%.3f" % [
		wrist, _lid.rotation_degrees.x, _joint("foot.L").y, _joint("foot.R").y,
	])


func _has_missing_book() -> bool:
	return bool(root.get_node(^"GameState").call("get_flag", StoryFlags.TEXTBOOK_MISSING, false))


func _finish_search() -> void:
	if not await _wait(func() -> bool: return _dialogue.get_mode() == DialogueController.Mode.INSPECTION,
		"original inspection to follow the rummage"):
		return
	_check.expect(StringName(_dialogue.get_current_line().get("inspection_id", "")) == &"classroom_schoolbag",
		"The stage opened a different inspection.")
	_check.expect(absf(_lid.rotation.x) < 0.001, "The bag was left open after searching it.")
	var entry := root.get_node(^"NarrativeState").call("get_entry", &"bag_missing_textbook") as NarrativeEntry
	_check.expect(_has_missing_book() and entry != null and entry.source == NarrativeEntry.Source.OBSERVED,
		"The inspection lost the missing-textbook flag or the journal observation.")
	_ui.dialogue_panel.complete_reveal()
	await _shot("06_inspection")
	_dialogue.advance_presentation()
	await _wait(func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(), "control after reading")


func _place(at: Vector3, toward: Vector3) -> void:
	_player.teleport(Transform3D(Basis.looking_at(toward, Vector3.UP), at))
	_player.face_toward(toward)
	await physics_frame
	await physics_frame


func _chair_solid() -> StaticBody3D:
	return _chair.get_node(^"Solid") as StaticBody3D


func _joint(key: String) -> Vector3:
	var index := _rig.find_bone(String(_bones.get(key, "")))
	return _rig.to_global(_rig.get_bone_global_pose(index).origin) if index >= 0 else Vector3.INF


func _foot_on_floor(key: String) -> bool:
	# The model's foot joint is 8.5 cm above the sole, in world units.
	return absf(_joint(key).y - _chair.home_mark().y - 0.085) < 0.028


func _check_seated(label: String) -> void:
	var body := _player.global_position
	var aim := _player.get_facing_direction()
	var offset := _chair.to_local(body)
	var cushion := _joint("thigh.L").y - _chair.seat_surface_height()
	_check.expect(_player.is_seated() and _animator.get_current_clip() == "sit_idle", "%s: no held seat pose." % label)
	_check.expect(body.distance_to(_chair.home_mark()) < 0.025, "%s: pelvis not over the chair mark." % label)
	_check.expect(aim.dot(-_chair.global_basis.z) > 0.995, "%s: wrong seated facing." % label)
	_check.expect(not _chair.is_pushed_back() and absf(offset.z - 0.07) < 0.025,
		"%s: the seat was not returned under the pelvis." % label)
	_check.expect(cushion > 0.034 and cushion < 0.094, "%s: thigh is floating above or inside the seat (%.3f m)." % [label, cushion])
	_check.expect(_foot_on_floor("foot.L") and _foot_on_floor("foot.R"), "%s: feet not on the floor." % label)
	print("MOTION_POSE %s body=%s facing=%s chair_offset=%s thigh_above_seat=%.3f ankle_y=%.3f/%.3f" % [
		label, body, aim, offset, cushion, _joint("foot.L").y, _joint("foot.R").y,
	])


func _phase(clip: String, phase: float) -> bool:
	return await _wait(func() -> bool:
		return _animator.get_current_clip() == clip and _animator.get_action_progress() >= phase,
		"%.2f of %s" % [phase, clip]
	)


func _wait(predicate: Callable, what: String) -> bool:
	return _check.expect(await Harness.wait_until(predicate, 9.0), "Timed out waiting for %s." % what)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not _check.expect(image != null and not image.is_empty() and image.get_width() >= 640,
		"No rendered pixels for %s." % file_name):
		return
	_check.expect(image.save_png(_out.path_join(file_name + ".png")) == OK, "Could not save %s." % file_name)
	# The original full-size frames are the evidence; small previews are relayed
	# for review when the artifact CDN isn't available to the coding sandbox.
	image.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	_check.expect(image.save_jpg(_out.path_join(file_name + ".jpg"), 0.46) == OK, "Could not save %s preview." % file_name)


func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await process_frame
	Harness.finish(self, _check.failures, "live seat contacts, approach, separate world input and the staged bag inspection (touch=%s)." % MobileLayout.enabled)
