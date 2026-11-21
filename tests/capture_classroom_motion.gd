extends SceneTree
## Live-window acceptance for the classroom. Review the movement under fixed lenses;
## use the real gameplay camera for the chair, bag and seated classmate input checks.

const Harness = preload("res://tests/test_harness.gd")
const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
const APPROACH := Vector3(-0.75, 0, 2.15)
# Start in the open left aisle, outside Q's desk and chair, not in the desktop seam.
const OTHER_AISLE := Vector3(-3.77, 0, 2.20)
const STUDENT_AISLE := Vector3(-1.6, 0, 0.33)
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
	if _check.expect(not _dialogue.is_busy() and _player.is_control_enabled(),
		"The classroom did not return control after the bag inspection."):
		if not MobileLayout.enabled:
			await _capture_dressing()
		await _capture_student()
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
	await _capture_chair_details()

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


func _capture_chair_details() -> void:
	# The actual wake chair, at its pushed stop: leave the desk and its bag in the
	# frame for scale. Review cameras only; the interaction camera is unchanged.
	var old_transform := _review.global_transform
	var old_fov := _review.fov
	var focus := _chair.to_global(Vector3(0, 0.42, 0.01))
	_review.fov = 43.0
	_review.global_position = _chair.to_global(Vector3(1.08, 1.02, 0.98))
	_review.look_at(focus)
	await _shot("15_student_chair_back")
	_review.global_position = _chair.to_global(Vector3(-1.12, 1.06, -0.68))
	_review.look_at(focus)
	await _shot("16_student_chair_front")
	_review.global_transform = old_transform
	_review.fov = old_fov


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


func _capture_dressing() -> void:
	# A fixed review lens shows the authored edge movement. The scenario does not
	# change the story's curtain state or take the transition out of this room.
	var paper := _room.get_node(^"TimetableSheet") as MeshInstance3D
	var clip := _room.get_node(^"TimetableClip") as Node3D
	await _place(Vector3(0.45, 0.0, 3.55), Vector3.BACK)
	_review.current = true
	_review.position = Vector3(1.3, 1.82, 3.65)
	_review.look_at(paper.global_position)
	_review.fov = 50.0
	var pin := paper.to_local(clip.global_position)
	var bottom := Vector3(0.0, paper.get_aabb().position.y, 0.0)
	if await _wait(func() -> bool: return absf(paper.rotation.x) < 0.0001, "the paper's rest"):
		var rest := paper.to_global(bottom)
		await _shot("09_timetable_still")
		# The draft follows the game clock. Let that clock advance without a full
		# software-rendered frame on every wait tick; neither pose is forced.
		var was_rendering := RenderingServer.render_loop_enabled
		RenderingServer.render_loop_enabled = false
		var draft := await _wait(func() -> bool: return paper.rotation_degrees.x > 3.2, "a draft at the timetable", 13.0)
		RenderingServer.render_loop_enabled = was_rendering
		if draft:
			var travel := rest.z - paper.to_global(bottom).z
			_check.expect(travel > 0.035 and travel < 0.055, "Timetable lift is not a bounded lift into the room.")
			_check.expect(paper.to_global(pin).distance_to(clip.global_position) < 0.001,
				"The timetable slipped out of its clip.")
			print("MOTION_PAPER bottom_lift=%.3f m" % travel)
			await _shot("10_timetable_draft")
			await _inspect_lifted_paper(paper, bottom)
		await _wait(func() -> bool: return absf(paper.rotation.x) < 0.0001, "the paper to rest again")

	var curtain := _room.get_node(^"Anomalies/BackCurtain") as WindowCurtain
	var panels := curtain.get_fabric_meshes()
	var left := panels[0].get_parent() as Node3D
	var right := panels[1].get_parent() as Node3D
	var rail_left := left.position
	var stop := _room.get_node(^"WallWest/ClosedCurtainStop") as CollisionShape3D
	if await _wait(func() -> bool: return absf(left.rotation_degrees.x) > 0.35, "a draft at the curtain", 13.0):
		_check.expect(not stop.disabled and is_zero_approx(curtain.get_open_amount())
			and is_equal_approx(left.rotation.x, right.rotation.x), "The closed curtain draft uncovered the seam.")
		var fabric := curtain.get_fabric_aabb()
		_check.expect(fabric.position.z <= 0.75 and fabric.end.z >= 3.65 and fabric.position.y < 0.12,
			"A moving curtain does not cover the cut from floor to rail.")
	_review.position = Vector3(-3.0, 1.66, 2.55)
	_review.look_at(Vector3(-6.55, 1.58, 2.2))
	_review.fov = 64.0
	await curtain.open()
	if await _wait(func() -> bool:
		return absf(left.rotation_degrees.x - right.rotation_degrees.x) > 0.24, "the hems to recoil after the pull"):
		_check.expect(curtain.is_open() and left.position.is_equal_approx(rail_left) and stop.disabled == false,
			"Visual recoil changed the gather, rail or room collision.")
		print("MOTION_CURTAIN gathered=%.3f hem_lag=%.2f deg" % [curtain.get_open_amount(),
			absf(left.rotation_degrees.x - right.rotation_degrees.x)])
		await _shot("11_curtain_recoil")
	if await _wait(func() -> bool:
		return is_equal_approx(left.rotation.x, right.rotation.x), "the hems to come to rest"):
		await _shot("12_curtain_settled")
	curtain.set_open_amount(0.0)
	_game_camera.current = true


func _inspect_lifted_paper(paper: MeshInstance3D, bottom: Vector3) -> void:
	var target := _room.find_interactable(&"timetable")
	var print_point := paper.to_global(bottom + Vector3(0, 0.06, -0.0106))
	var pixel := _review.unproject_position(print_point)
	if not _check.expect(target != null and _interaction.get_target_at_screen_position(pixel) == target,
		"The lifted edge of the timetable no longer picks its own sheet."):
		return
	_mouse_click(pixel, target)
	_check.expect(_dialogue.get_mode() == DialogueController.Mode.INSPECTION
		and StringName(_dialogue.get_current_line().get("inspection_id", &"")) == &"classroom_timetable_sheet",
		"The lifted timetable no longer opens its original inspection.")
	_continue_line()
	await _wait(func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		"control after reading the moving sheet")


func _capture_student() -> void:
	var student := _room.get_node(^"Actors/SeatedStudent") as CharacterVisualAnimation
	var talk := _room.find_interactable(&"student_talk")
	if not _check.expect(talk != null and student.is_bound(), "The seated visual or talk anchor is missing."):
		return
	if MobileLayout.enabled:
		root.get_node(^"Loc").set_locale("en")
	await _place(STUDENT_AISLE, Vector3.LEFT)
	var at := _player.global_position
	var rig := student.get_skeleton()
	var bones: Dictionary = student.get_bind_report()["resolved"]
	var head := rig.find_bone(String(bones["head"]))
	var rest := rig.get_bone_pose_rotation(head)
	var body := student.global_transform
	var played := student.get_animation_player()
	var game_rig := _player.camera_rig
	if not await _click_student(talk, rig, head, true):
		return
	_check.expect(_player.global_position.distance_to(at) > 0.7 and not _player.is_control_enabled(),
		"Student talk did not walk to A1 and hold control during the line.")
	_check.expect(student.is_seated() and student.is_talking() and not student.is_playing_action()
		and student.get_current_clip() == "sit_talk", "The visible student never entered seated speech.")
	var line := _dialogue.get_current_line()
	var expected := "I'm trying to get this line by heart." if MobileLayout.enabled else "我正背到这句。"
	_check.expect(String(line.get("text", "")).begins_with(expected), "The short answer is missing in the active language.")
	_ui.dialogue_panel.complete_reveal()
	if await _wait(func() -> bool:
		return played.current_animation == "char/sit_talk" and played.current_animation_position >= 0.46 \
			and game_rig.get_focus_weight() >= 0.9,
		"the reply gesture and its gameplay framing"):
		var turn := rad_to_deg(rest.angle_to(rig.get_bone_pose_rotation(head)))
		var panel := _ui.dialogue_panel
		var head_pixel := _game_camera.unproject_position(_student_head_at(rig, head))
		var player_pixel := _game_camera.unproject_position(_player.global_position + Vector3.UP * 1.6)
		var band := panel.get_global_rect()
		_check.expect(game_rig.get_focus_subject() == talk and root.get_visible_rect().has_point(head_pixel)
			and root.get_visible_rect().has_point(player_pixel) and not band.has_point(head_pixel),
			"The live dialogue lens hid a participant or put the student's head behind the reading band.")
		_check.expect(turn > 16.0 and student.global_transform.is_equal_approx(body),
			"The answer needs a visible head turn without traveling in the chair.")
		print("MOTION_STUDENT input=%s walk=%.2f m head_turn=%.1f deg" % [
			"touch" if MobileLayout.enabled else "mouse", _player.global_position.distance_to(at), turn])
		await _shot("13_student_answers")
		if not MobileLayout.enabled:
			# The same live reply from desk height, to see the elbow and hand clearance.
			_review.position = Vector3(-2.69, 1.49, -0.76)
			_review.look_at(Vector3(-4.8, 0.80, -0.42))
			_review.fov = 44.0
			_review.current = true
			await _shot("13b_student_at_desk")
			_game_camera.current = true
	if not await _choose_student(0, &"st_let_be"):
		return
	_check.expect(_student_node() == &"st_let_be" and not student.is_talking()
		and student.get_current_clip() == "sit_idle", "The narrator kept the student speaking.")
	_continue_line()
	if not await _wait(func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		"control after the short student reply"):
		return
	var state := root.get_node(^"GameState")
	_check.expect(not bool(state.get_flag(StoryFlags.STUDENT_TALKED, false)),
		"Leaving the student to recite completed the longer conversation's flag.")
	if not await _wait(func() -> bool: return is_zero_approx(game_rig.get_focus_weight()),
		"the dialogue framing to release"):
		return
	await _shot("14_student_recites_again")
	if not await _click_student(talk, rig, head, false):
		return
	if not await _choose_student(1, &"st_1"):
		return
	for id: StringName in [&"st_1", &"st_2", &"st_3", &"st_4", &"st_5"]:
		var speaking := id in [&"st_1", &"st_3", &"st_5"]
		_check.expect(_student_node() == id and student.is_talking() == speaking,
			"The original exchange or its speaker cue changed at '%s'." % id)
		_continue_line()
	_check.expect(_student_node() == &"st_ask", "The original student choices disappeared.")
	if not await _choose_student(0, &"st_moved"):
		return
	for id: StringName in [&"st_moved", &"st_m2", &"st_end"]:
		_check.expect(_student_node() == id, "The desk question did not reach '%s'." % id)
		_continue_line()
	await _wait(func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		"control after the longer exchange")
	_check.expect(bool(state.get_flag(StoryFlags.STUDENT_TALKED, false)) and not student.is_talking()
		and student.is_seated() and student.get_current_clip() == "sit_idle",
		"The longer exchange lost its completion flag or did not restore recitation.")


func _click_student(talk: Interactable, rig: Skeleton3D, head: int, walk_first: bool) -> bool:
	var pixel := _game_camera.unproject_position(_student_head_at(rig, head))
	var target := _interaction.get_target_at_screen_position(pixel, false)
	if not _check.expect(target == talk, "A1 head pixel %s selected '%s' instead of the student." % [
		pixel, String(target.interact_id) if target != null else "nothing"]):
		return false
	_check.expect(_interaction.is_in_reach(talk) != walk_first, "Student scene did not cover both approach and direct talk.")
	if MobileLayout.enabled:
		_tap(pixel, talk, walk_first)
	else:
		_mouse_click(pixel, talk, walk_first)
	if walk_first:
		_check.expect(_player.camera_rig.get_focus_subject() == null, "The student shot started before arrival.")
	return await _wait(func() -> bool:
		return _clicked == talk and _student_node() == &"st_reciting", "the clicked student to answer")


func _student_head_at(rig: Skeleton3D, head: int) -> Vector3:
	return rig.to_global(rig.get_bone_global_pose(head).origin) + Vector3(0.0, 0.10, 0.0)


func _student_node() -> StringName:
	return StringName(_dialogue.get_current_line().get("node_id", &""))


func _choose_student(index: int, next: StringName) -> bool:
	var panel := _ui.dialogue_panel
	panel.complete_reveal()
	if not await _wait(func() -> bool:
		var buttons := panel.get_choice_buttons()
		if index >= buttons.size() or bool(panel.get("_layout_dirty")):
			return false
		var choice := buttons[index]
		return choice.is_visible_in_tree() and not choice.disabled and choice.size.y >= 24.0 \
			and panel.get_global_rect().encloses(choice.get_global_rect()),
		"the student's choice button to be laid out"):
		return false
	# A user can only hit the new row once the deferred container layout is drawn.
	await RenderingServer.frame_post_draw
	var button := panel.get_choice_buttons()[index]
	var pixel := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var before := _pointer.get_world_click_event_count()
	if MobileLayout.enabled:
		_touch(pixel, true)
		await process_frame
		_touch(pixel, false)
	else:
		_mouse_buttons(pixel)
	var chosen := await Harness.wait_until(func() -> bool: return _student_node() == next, 9.0)
	_check.expect(_pointer.get_world_click_event_count() == before, "Choosing a reply clicked through into the room.")
	return _check.expect(chosen, "Choice %d at %s did not reach '%s' (at '%s')." % [index, pixel, next, _student_node()])


func _continue_line() -> void:
	_ui.dialogue_panel.complete_reveal()
	_dialogue.advance_presentation()


func _settled_at_seat() -> bool:
	return _player.is_seated() and not _sequence.is_beat_active()


func _seat_pixel() -> Vector2:
	var back := _chair.get_node(^"Back") as Node3D
	return _game_camera.unproject_position(back.global_position)


func _bag_pixel() -> Vector2:
	var shell := _room.get_node(^"Furniture/DeskB2/Schoolbag/Shell") as MeshInstance3D
	return _game_camera.unproject_position(shell.to_global(shell.get_aabb().get_center()))


func _mouse_click(pixel: Vector2, target: Interactable, walk_first: bool = false) -> void:
	_clicked = null
	var before := _pointer.get_world_click_event_count()
	_mouse_buttons(pixel)
	_check.expect(_pointer.get_world_click_event_count() == before + 1, "Mouse press did not reach world input exactly once.")
	_check.expect((_pointer.get_pending_target() if walk_first else _clicked) == target,
		"Mouse did not select %s from its visible pixel." % target.interact_id)


func _mouse_buttons(pixel: Vector2) -> void:
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = root.get_final_transform() * pixel
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		_send(click)


func _tap(pixel: Vector2, target: Interactable, walk_first: bool = false) -> void:
	_clicked = null
	var before := _pointer.get_world_click_event_count()
	_check.expect(MobileLayout.safe_rect(_ui.hud).has_point(pixel), "The target pixel is outside the touch safe area.")
	_touch(pixel, true)
	_check.expect(_pointer.get_world_click_event_count() == before, "Touch-down activated the prop.")
	_touch(pixel, false)
	_check.expect(_pointer.get_world_click_event_count() == before + 1, "A tap did not reach world input exactly once.")
	_check.expect((_pointer.get_pending_target() if walk_first else _clicked) == target,
		"Touch did not select %s from its visible pixel." % target.interact_id)


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


func _wait(predicate: Callable, what: String, timeout: float = 9.0) -> bool:
	return _check.expect(await Harness.wait_until(predicate, timeout), "Timed out waiting for %s." % what)


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
	Harness.finish(self, _check.failures,
		"live seat contacts, bag inspection, bounded prop motion (desktop) and both student reply paths (touch=%s)."
		% MobileLayout.enabled)
