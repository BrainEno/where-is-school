extends SceneTree
## Live-window acceptance for the classroom actions. Compare the fixed side view
## with the baseline and use the real gameplay camera for pointer/inspection checks.

const Harness = preload("res://tests/test_harness.gd")
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
var _room: LocationRoot
var _chair: PushableChair
var _seat: Interactable
var _bag: Interactable
var _game_camera: Camera3D
var _review: Camera3D
var _animator: CharacterVisualAnimation
var _rig: Skeleton3D
var _bones: Dictionary


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
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_chair = _room.get_node(^"Furniture/DeskB2/Chair") as PushableChair
	_seat = _room.find_interactable(&"chair_sit")
	_bag = _room.find_interactable(&"schoolbag")
	_game_camera = (_main.get_node(^"CameraRig") as CameraRig).camera
	if not _check.expect(_seat != null and _bag != null, "The real chair or bag interaction is missing."):
		_finish()
		return
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	(_main.get_node(^"GameUI") as GameUI).fade.set_clear()
	_player.settle_wake_seated_pose(0.0)
	_player.set_camera_roll(0.0)
	_sequence.allow_player_control()
	if not await _wait(func() -> bool: return _foot_on_floor("foot.L"), "wake foot to plant"):
		_finish()
		return

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
		_check.expect(_foot_on_floor("foot.L"), "The near foot lost floor contact on the lift.")
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
		await _shot("02b_lowering")
	await _wait(func() -> bool: return not _sequence.is_beat_active(), "sit request to finish")
	_check_seated("returned from right aisle")
	await _shot("03_returned_from_aisle")

	# Rise again via the actual staged stand, then enter from the other side with
	# the pointer. Both pick shapes should still follow their own visible meshes.
	_interaction.request_activation(_seat)
	await _wait(func() -> bool: return _chair.is_pushed_back() and not _sequence.is_beat_active(), "repeat stand")
	_game_camera.current = true
	await _place(OTHER_AISLE, Vector3.RIGHT)
	var back := _chair.get_node(^"Back") as Node3D
	var seat_pixel := _game_camera.unproject_position(back.global_position)
	_check.expect(_interaction.get_target_at_screen_position(seat_pixel, false) == _seat,
		"The backrest pixel selected something other than the pushed chair.")
	var pointer := _player.get_node(^"PointerNavigator") as PointerNavigator
	pointer.click_at_screen_position(seat_pixel)
	await _wait(func() -> bool: return _player.is_seated() and not _sequence.is_beat_active(), "left-aisle click to sit")
	_check_seated("returned from left aisle")

	# From the seat a real pointer click can start the search; it includes a stand.
	# Capture the two separate live prompts, then the wrist/lid and original text.
	var shell := _room.get_node(^"Furniture/DeskB2/Schoolbag/Shell") as MeshInstance3D
	var bag_pixel := _game_camera.unproject_position(shell.to_global(shell.get_aabb().get_center()))
	seat_pixel = _game_camera.unproject_position(back.global_position)
	_check.expect(_interaction.get_target_at_screen_position(seat_pixel) == _seat, "Seated chair pixel hit the bag.")
	_check.expect(_interaction.get_target_at_screen_position(bag_pixel) == _bag, "Bag pixel hit another prop.")
	_interaction.set_mouse_override(bag_pixel)
	if await _wait(func() -> bool: return _interaction.get_current_target() == _bag, "bag hover"):
		await _shot("04_bag_target")
	pointer.click_at_screen_position(bag_pixel)
	_interaction.clear_mouse_override()
	if await _phase("schoolbag_search", 0.46):
		var lid := _room.get_node(^"Furniture/DeskB2/Schoolbag/Lid") as Node3D
		_check.expect(lid.rotation_degrees.x < -70.0, "The rummage clip did not actually open the bag.")
		_check.expect(not _dialogue.is_busy() and not _player.is_control_enabled(),
			"The hands did not own the beat until the inspection.")
		_review.position = Vector3(-0.60, 1.72, 2.55)
		_review.look_at(Vector3(-0.85, 0.85, 1.40))
		_review.fov = 53.0
		_review.current = true
		await _shot("05_rummaging")
	_game_camera.current = true
	if await _wait(func() -> bool:
		return _dialogue.get_mode() == DialogueController.Mode.INSPECTION,
		"original inspection to follow the rummage"
	):
		_check.expect(StringName(_dialogue.get_current_line().get("inspection_id", "")) == &"classroom_schoolbag",
			"The stage opened a different inspection.")
		var lid := _room.get_node(^"Furniture/DeskB2/Schoolbag/Lid") as Node3D
		_check.expect(absf(lid.rotation.x) < 0.001, "The bag was left open after searching it.")
		_dialogue.advance_presentation() # reveal the current line without waiting for the typewriter
		await _shot("06_inspection")
	_finish()


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
	image.resize(520, 293, Image.INTERPOLATE_LANCZOS)
	_check.expect(image.save_jpg(_out.path_join(file_name + ".jpg"), 0.62) == OK, "Could not save %s preview." % file_name)


func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await process_frame
	Harness.finish(self, _check.failures, "live seat contacts, two approaches, pointer separation and the staged bag inspection.")
