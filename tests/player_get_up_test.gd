extends Node
## #170 regression checks, called by the registered runtime_character_animation test.
## Real player, skeleton, PointerNavigator and dialogue locks; no controller mocks.
## The clear-aisle fixture isolates locomotion from the classroom author's chair layout.

var failures: Array[String] = []
var _player: PlayerController
var _navigator: PointerNavigator
var _dialogue: DialogueController
var _animator: CharacterVisualAnimation
var _screen_point: Callable
var _clear_action: Callable
var _action: String
var _screen: Vector2
var _origin: Vector3
var _starts := 0
var _finish_tilt := 0.0
var _finish_height := 0.0
var _finish_hip := 0.0
var _latest_target := Vector3.ZERO


func run(player: PlayerController, navigator: PointerNavigator, dialogue: DialogueController,
		screen_point: Callable, clear_action: Callable) -> void:
	_player = player
	_navigator = navigator
	_dialogue = dialogue
	_animator = player.get_character_animator()
	_screen_point = screen_point
	_clear_action = clear_action
	var saved_position := player.global_position
	var saved_facing := player.get_facing_direction()
	_animator.get_animation_player().animation_started.connect(_on_clip_started)
	_animator.get_animation_player().animation_finished.connect(_on_clip_finished)
	for mode: String in ["click", "keyboard", "cancel", "override", "dialogue", "pause"]:
		if not await _seat_in_clear_aisle():
			break
		if mode == "keyboard":
			Input.action_press(_action)
		else:
			_navigator.click_at_screen_position(_screen)
			_expect(_navigator.was_last_click_accepted() and _player.is_path_active(),
				"%s: the real floor click did not start a path." % mode)
			_latest_target = _player.get_path_target()
		await _watch_get_up(mode)
		if mode in ["click", "keyboard", "override", "pause"]:
			var waited := 0.0
			while _flat_gap(_player.global_position) < 0.12 and waited < 1.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
			_expect(_flat_gap(_player.global_position) >= 0.12,
				"%s: movement did not resume after standing." % mode)
			if mode in ["click", "pause"]:
				_expect(_player.get_path_target().distance_to(_latest_target) < 0.01,
					"%s: standing lost or replaced the requested destination." % mode)
		else:
			await _seconds(0.15)
			_expect(not _player.is_path_active() and _flat_gap(_player.global_position) < 0.02,
				"%s: a cancelled/locked path resumed after standing." % mode)
		Input.action_release(_action)
		_navigator.cancel()
		while _dialogue.is_busy():
			_dialogue.advance_presentation()
			await get_tree().process_frame
		await _seconds(0.2)
		_expect(_player.is_control_enabled(), "%s: control did not return after unlock." % mode)
		_expect(_starts == 1, "%s: repeated input restarted get_up %d times." % [mode, _starts])
		_expect(absf(_finish_tilt) < 0.001 and absf(_finish_height - 0.9) < 0.001,
			"%s: the pivot was not upright when the skeleton finished (%.3f / %.3f)."
			% [mode, _finish_tilt, _finish_height])
		_expect(_finish_hip < 12.0, "%s: get_up did not finish on standing legs (%.1f degrees)." % [mode, _finish_hip])
	await _locked_seat()
	_player.teleport(Transform3D(Basis.looking_at(saved_facing, Vector3.UP), saved_position))
	print("::notice title=player get-up regression::click, keys, repeat/replace, cancel, keyboard override, "
		+ "dialogue lock and pause; %d problem(s)." % failures.size())


func _seat_in_clear_aisle() -> bool:
	if not _action.is_empty():
		Input.action_release(_action)
	_navigator.cancel()
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(5.7, 0.0, -2.0)))
	await _seconds(0.3)
	_player.settle_wake_seated_pose(0.0)
	await _seconds(0.1)
	var point: Variant = _screen_point.call(2.2, 6.0)
	_action = String(_clear_action.call(2.0))
	if point == null or _action.is_empty():
		_expect(false, "The get-up fixture has no visible floor click or clear movement key.")
		return false
	_screen = point
	_origin = _player.global_position
	_starts = 0
	_finish_tilt = INF
	_finish_height = INF
	_finish_hip = INF
	_expect(_animator.is_seated(), "Preparing a seat did not hold sit_idle.")
	return true


func _watch_get_up(mode: String) -> void:
	var elapsed := 0.0
	var seen := false
	var changed := false
	var drift := 0.0
	var speed := 0.0
	var phase_error := 0.0
	var advanced := false
	var tilt := _player.visual.rotation.x
	var ap := _animator.get_animation_player()
	while elapsed < 4.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not _animator.is_playing_action():
			if seen:
				break
			continue
		seen = true
		_expect(_animator.get_current_clip() == "get_up", "%s: a different action replaced get_up." % mode)
		drift = maxf(drift, _flat_gap(_player.global_position))
		speed = maxf(speed, Vector2(_player.velocity.x, _player.velocity.z).length())
		var fraction := ap.current_animation_position / maxf(ap.current_animation_length, 0.001)
		var weight := 0.5 - cos(PI * fraction) * 0.5
		phase_error = maxf(phase_error, absf(_player.visual.rotation.x - lerpf(tilt, 0.0, weight)))
		if _player.is_path_active():
			advanced = advanced or _player.get_path_index() != 1 \
				or float(_player.get("_path_progress_elapsed")) > 0.001
		if not changed and fraction > 0.2:
			changed = true
			match mode:
				"click":
					_navigator.click_at_screen_position(_screen)
					# Replace the destination without restarting the action; the same
					# clear direction used for the keyboard fixture is reachable ground.
					var keys := {"move_left": Vector2.LEFT, "move_right": Vector2.RIGHT,
						"move_forward": Vector2.UP, "move_back": Vector2.DOWN}
					var direction: Vector3 = _player._camera_relative(keys[_action])
					_expect(_player.request_path_to(_origin + direction * 1.6), "Replacing the held path was refused.")
					_latest_target = _player.get_path_target()
				"keyboard":
					Input.action_press(_action)
				"cancel":
					_navigator.cancel()
				"override":
					Input.action_press(_action)
				"dialogue":
					_expect(_dialogue.play_conversation(&"q_studying"), "The dialogue-lock fixture did not open.")
					_expect(not _player.is_control_enabled(), "Dialogue did not lock the player during get_up.")
				"pause":
					var at := ap.current_animation_position
					get_tree().paused = true
					await get_tree().create_timer(0.1, true, false, true).timeout
					_expect(is_equal_approx(at, ap.current_animation_position), "Pausing advanced the get_up clip.")
					get_tree().paused = false
	_expect(seen and not _animator.is_playing_action(), "%s: get_up never started or finished." % mode)
	_expect(elapsed >= 0.6 and elapsed <= 1.05,
		"%s: get_up took %.3f story seconds, expected a brisk synchronized transition." % [mode, elapsed])
	_expect(drift < 0.02 and speed < 0.001,
		"%s: moving before standing (%.3f m drift, %.3f m/s)." % [mode, drift, speed])
	_expect(not advanced, "%s: the path index/watchdog advanced during get_up." % mode)
	_expect(phase_error < 0.045, "%s: pivot and bone clocks diverged (%.3f radians)." % [mode, phase_error])
	print("note: get_up %s: %.3f s, %.4f m drift, %.4f m/s, phase error %.4f rad" % [mode, elapsed, drift, speed, phase_error])


func _locked_seat() -> void:
	if not await _seat_in_clear_aisle():
		return
	_player.set_control_enabled(false)
	Input.action_press(_action)
	_expect(not _player.request_path_to(_origin + Vector3.FORWARD * 2.0), "A locked seated player accepted a path.")
	await _seconds(0.15)
	_expect(_animator.is_seated() and _starts == 0 and _flat_gap(_player.global_position) < 0.02,
		"A locked movement intention made the seated player get up.")
	Input.action_release(_action)
	_player.set_control_enabled(true)
	await _seconds(0.1)
	_expect(_animator.is_seated() and _starts == 0, "Unlocking replayed a stale movement intention.")
	# Restore this runtime fixture for the pre-existing standing/walking checks.
	_player.set_wake_pose(0.0)
	await _seconds(2.5)


func _on_clip_started(clip: StringName) -> void:
	if String(clip) == "char/get_up":
		_starts += 1


func _on_clip_finished(clip: StringName) -> void:
	if String(clip) != "char/get_up":
		return
	_finish_tilt = _player.visual.rotation.x
	_finish_height = _player.visual.position.y
	var resolved: Dictionary = _animator.get_bind_report().get("resolved", {})
	var skeleton := _animator.get_skeleton()
	var index := skeleton.find_bone(String(resolved.get("thigh.L", "")))
	if index >= 0:
		_finish_hip = rad_to_deg(skeleton.get_bone_pose_rotation(index).angle_to(
			skeleton.get_bone_rest(index).basis.get_rotation_quaternion()))


func _flat_gap(point: Vector3) -> float:
	return Vector2(point.x - _origin.x, point.z - _origin.z).length()


func _seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
