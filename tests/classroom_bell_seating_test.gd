extends SceneTree
## Exercise the real bell and substitute beats in the real classroom. Optional frames
## (-- capture=/path) come from the gameplay camera, not a separate pose preview.

const Harness = preload("res://tests/test_harness.gd")
const Limb = preload("res://scripts/actors/character_limb_contact.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const RIGHT_AISLE := Vector3(-0.74, 0, 2.83)
const FRONT_AISLE := Vector3(3.22, 0, -1.65)
const WAIT := 40.0

var _check := Harness.Checker.new()
var _state: Node
var _world: Node
var _sequence: OpeningSequence
var _dialogue: DialogueController
var _host: LocationHost
var _player: PlayerController
var _q: NpcActor
var _n: NpcActor
var _chair: PushableChair
var _q_chair: PushableChair
var _output := ""
var _saved_frames := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 160.0, "classroom_bell_seating_test.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("capture="):
			_output = arg.trim_prefix("capture=")
	call_deferred("_run")


func _run() -> void:
	_state = Harness.ensure_state_autoloads(self)["game_state"]
	var capture := not _output.is_empty()
	if capture:
		DirAccess.make_dir_recursive_absolute(_output)
		_check.expect(DisplayServer.get_name() != "headless", "Capture needs a rendered window.")
		print("::notice title=Bell seating renderer::%s, %s" % [
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	Engine.time_scale = 2.0 if capture else 3.0
	await _through_bell(false)
	await _free_world()
	if not capture:
		# These two cases run in full headless CI. Only the moving pair needs
		# real pixels; avoid three complete software-rendered lessons.
		await _through_bell(true)
		await _free_world()
		await _after_bell()
		await _free_world()
	Engine.time_scale = 1.0
	Harness.clear_session_state(self)
	if capture:
		_check.expect(_saved_frames == 3, "Expected all three live frames; saved %d." % _saved_frames)
	Harness.finish(self, _check.failures, "bell seating: two real chair transfers and lesson handoff."
		if capture else "bell seating: moving pair, already-seated player, lesson handoff and post-bell restore.")


func _boot(after_bell: bool) -> bool:
	Harness.clear_session_state(self)
	for flag: StringName in [StoryFlags.MET_Q, StoryFlags.Q_FIRST_TALK_DONE,
			StoryFlags.BAG_WAIT_EXPIRED, StoryFlags.EXPECTATION_SKIPPED]:
		_state.set_flag(flag, true)
	if after_bell:
		_state.set_flag(StoryFlags.BELL_RUNG, true)
	_world = MAIN.instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	var room := _host.get_current()
	_q = room.find_actor(&"q")
	_n = room.find_actor(&"n")
	_chair = room.get_node(^"Furniture/DeskB2/Chair") as PushableChair
	_q_chair = room.get_node(^"Furniture/DeskB1/Chair") as PushableChair
	if not after_bell:
		_player.set_wake_pose(1.0)
		_player.settle_wake_seated_pose(0.0)
	var navigation := room.get_node(^"Navigation") as LocationNavigation
	return _check.expect(await Harness.wait_until(navigation.is_synchronized, 8.0),
		"Classroom navigation did not synchronize.")


func _through_bell(already_seated: bool) -> void:
	Harness.stage = "already seated" if already_seated else "both students standing"
	if not await _boot(false):
		return
	var q_start := _q.global_position
	var q_chair_home := _q_chair.global_position
	var player_chair_home := _chair.global_position
	if not already_seated:
		_player.stand_up()
		if not _check.expect(await Harness.wait_until(func() -> bool: return not _player.is_seat_transition_active(), 5.0),
				"The existing rise never finished."):
			return
		var pushed := _chair.global_position.distance_to(player_chair_home)
		var gap := _chair.mesh_bounds().position.z - _chair.home_mark().z - _player.navigation_agent.radius
		_check.expect(_chair.is_pushed_back() and is_equal_approx(pushed, 0.64) and gap >= 0.009,
			"The shortened stand stopped at %.3f m with only %.3f m of mesh clearance." % [pushed, gap])
		_check.expect(not _player.test_move(_player.global_transform.translated(Vector3.UP * 0.035),
			Vector3.ZERO, null, _player.safe_margin, true), "The pushed chair or desk overlaps the standing body.")
		_player.teleport(Transform3D(Basis.IDENTITY, RIGHT_AISLE))

	var player_start := _player.global_position
	_sequence.start()
	var q_pulling := false
	var q_sitting := false
	var player_sitting := false
	var player_moved := false
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000.0)
	while not _n.visible and Time.get_ticks_msec() < deadline:
		var q_slide := _q_chair.global_position.distance_to(q_chair_home)
		var q_arrived := _q.global_position.distance_to(_q_chair.home_mark()) < 0.03
		var player_animation := _player.get_character_animator()
		var player_clip := player_animation.get_current_clip()
		if q_slide > 0.15 and q_slide < 0.47 and not q_arrived and not q_pulling:
			q_pulling = true
			_check.expect(_sequence.is_beat_active() and not _player.is_control_enabled()
				and _q.get_character_animator().is_playing_action(), "Q slid the chair without a locked performance.")
			_expect_support(_q.get_character_animator(), _q_chair, true, "Q pulls B1")
			if not already_seated:
				await _shot("01_q_pulls_chair")
		if q_slide > 0.15 and q_slide < 0.47 and q_arrived and not q_sitting:
			q_sitting = true
			_expect_support(_q.get_character_animator(), _q_chair, false, "Q sits")
		if player_clip == "classroom_sit" and player_animation.get_action_progress() >= 0.53 and not player_sitting:
			player_sitting = true
			_expect_support(player_animation, _chair, false, "Player sits")
			if not already_seated:
				await _shot("02_player_sits")
		player_moved = player_moved or _player.global_position.distance_to(player_start) > 0.03
		_pump_text()
		# Contact and chair progress are sampled in physics, not at the runner's
		# render rate. A slow software frame must not skip over the loaded pose.
		await physics_frame
	if not _check.expect(_n.visible, "N never reached the entrance after the bell."):
		return
	_check.expect(_q.global_position.distance_to(q_start) > 0.8 and q_pulling and q_sitting,
		"Q did not walk back, draw the chair out and slide it under himself to sit.")
	_check.expect(player_sitting != already_seated and player_moved != already_seated,
		"The player did not return with the sit clip, or re-animated the already settled seat.")
	_expect_both_seated()
	if not already_seated:
		await _shot("03_seated_before_lesson")
	# Do not remove the short free window during N's walk. If the player deliberately
	# stands there, the lesson still begins at the seats rather than in mid-rise.
	if already_seated:
		_check.expect(_player.is_control_enabled(), "N's walk took away the existing escape window.")
		_player.stand_up()
	await _expect_lesson()


func _after_bell() -> void:
	Harness.stage = "continue between bell and class"
	if not await _boot(true):
		return
	_check.expect(_q.get_character_animator().is_seated() and not _q_chair.is_pushed_back(),
		"A rebuilt Q did not start seated without replaying the bell.")
	_player.teleport(Transform3D(Basis.IDENTITY, FRONT_AISLE))
	# A standing save elsewhere in the room has a tucked chair. Exercise that
	# pull too, not just the chair left out by a prior get-up.
	_chair.snap_home()
	var tucked := _chair.global_position
	_sequence.start()
	if _check.expect(await _drive_until(func() -> bool:
			var offset := _chair.global_position.distance_to(tucked)
			return offset > 0.15 and offset < 0.47 and not _chair.is_pushed_back()),
			"Continue did not pull out the protagonist's tucked chair."):
		_expect_support(_player.get_character_animator(), _chair, true, "Player pulls B2")
	if not await _expect_lesson():
		return
	# No post-lesson move or actor state is serialized. A fresh instance derives Q's
	# place from the bell and leaves the player's saved/arrival pose alone.
	if not _check.expect(bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false)), "The lesson did not dismiss normally."):
		return
	var previous := _q.get_instance_id()
	if _check.expect(_host.load_location(CLASSROOM, &"FromCorridor", _player, &"classroom"),
			"Could not re-enter the real classroom."):
		_q = _host.get_current().find_actor(&"q")
		_q_chair = _host.get_current().get_node(^"Furniture/DeskB1/Chair") as PushableChair
		_check.expect(_q.get_instance_id() != previous and not _player.is_seated(),
			"Re-entry reused old nodes or forced the player into a seat after dismissal.")
		_expect_seated(_q, _q.get_character_animator(), _q_chair)
		_expect_q_talk()


func _expect_lesson() -> bool:
	if not _check.expect(await _drive_until(func() -> bool:
			return _dialogue.get_runtime().get_active_conversation_id() == &"n_class"),
			"The original class dialogue never started."):
		return false
	_expect_both_seated()
	_check.expect(not _player.is_control_enabled(), "Lesson released the player before the seating handoff.")
	return _check.expect(await _drive_until(func() -> bool:
		return not _dialogue.is_busy() and not _sequence.is_beat_active()), "The lesson left a beat locked.")


func _expect_both_seated() -> void:
	_expect_seated(_player, _player.get_character_animator(), _chair)
	_expect_seated(_q, _q.get_character_animator(), _q_chair)
	_check.expect(_player.is_seated() and not _player.is_seat_transition_active(), "Player pose did not commit.")
	_expect_q_talk()


func _expect_seated(body: Node3D, animator: CharacterVisualAnimation, chair: PushableChair) -> void:
	_check.expect(animator.is_seated() and not animator.is_playing_action() and not chair.is_pushed_back()
		and body.global_position.distance_to(chair.home_mark()) < 0.03,
		"%s was not settled at the correct chair." % body.name)
	var contacts := Limb.bind(animator)
	var leg: Limb = contacts.get("foot.L")
	if _check.expect(leg != null, "%s has no calibrated leg rig." % body.name):
		var hip := leg.skeleton.to_global(leg.skeleton.get_bone_global_pose(leg.joints.x).origin)
		var height := hip.y - chair.seat_surface_height()
		_check.expect(height > 0.033 and height < 0.095,
			"%s is floating above or inside the seat (hip relative to wood: %.3f m)." % [body.name, height])
		print("BELL_SEAT %s thigh_gap=%.3f" % [body.name, height])


func _expect_support(animator: CharacterVisualAnimation, chair: PushableChair, flank: bool, label: String) -> void:
	var contacts := Limb.bind(animator)
	var hand: Limb = contacts.get("hand.R" if flank else "hand.L")
	if not _check.expect(hand != null, "%s could not bind the gripping arm." % label):
		return
	var grip := chair.backrest_grip_point() if flank else chair.grip_point()
	var wrist := hand.skeleton.to_global(hand.skeleton.get_bone_global_pose(hand.joints.z).origin)
	var hand_gap := wrist.distance_to(grip)
	_check.expect(hand_gap < 0.12, "%s: wrist was %.3f m from the moving chair." % [label, hand_gap])
	var boot_gap := 0.0
	for side: String in ["foot.L", "foot.R"]:
		var leg: Limb = contacts.get(side)
		if not _check.expect(leg != null, "%s has no %s contact." % [label, side]):
			continue
		var ankle := leg.skeleton.to_global(leg.skeleton.get_bone_global_pose(leg.joints.z).origin)
		var expected := chair.home_mark().y + leg.rest_end.origin.y * leg.skeleton.global_basis.y.length()
		boot_gap = maxf(boot_gap, absf(ankle.y - expected))
	_check.expect(boot_gap < 0.03, "%s: an ankle was %.3f m off its planted height." % [label, boot_gap])
	print("::notice title=Bell seating contact::%s | wrist %.3f m | boot height error %.3f m" % [label, hand_gap, boot_gap])


func _expect_q_talk() -> void:
	var talk := _host.get_current().find_interactable(&"q_talk")
	var gap := (talk.global_position - _q.global_position).slide(Vector3.UP).length()
	_check.expect(gap < 0.06, "Q left the original interaction target behind by %.3f m." % gap)


func _drive_until(condition: Callable) -> bool:
	return await Harness.wait_until(func() -> bool:
		if bool(condition.call()):
			return true
		_pump_text()
		return false
	, WAIT)


func _pump_text() -> void:
	if _dialogue.has_pending_choices():
		_dialogue.select_choice(0)
	elif _dialogue.is_busy():
		_dialogue.advance_presentation()


func _shot(stem: String) -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		return
	paused = true
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	paused = false
	if _check.expect(image != null and image.save_jpg(_output.path_join(stem + ".jpg"), 0.9) == OK,
			"Could not save %s." % stem):
		_saved_frames += 1
		image.resize(400, roundi(image.get_height() * 400.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
		image.save_jpg(_output.path_join(stem + "_preview.jpg"), 0.62)


func _free_world() -> void:
	if not is_instance_valid(_world):
		return
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	var world_id := _world.get_instance_id()
	_world.queue_free()
	await Harness.wait_until(func() -> bool: return not is_instance_id_valid(world_id), 2.0)
