extends SceneTree
## The protagonist and Q animate in the shipping game: `main.tscn`, the real player, the real
## classroom, the real companion — not a model dropped into an empty test scene.
##
##   godot --headless --path . --script res://tests/runtime_character_animation_test.gd
##
## `character_animation_test.gd` proves the clip *table* binds to both rigs. This file proves
## what a player would see, and measures it off the skeletons rather than trusting a state
## name:
##
##   1. every animated character in the game is driven by the same `CharacterVisualAnimation`,
##      fed by the controller's own velocity (the player's body, the companion's body, or the
##      velocity an NPC's tween walk reports);
##   2. the clips only rotate skeleton bones — no transform track, so animation cannot move a
##      body or turn a character;
##   3. standing still is idle **with the arms hanging and the legs under the body**. The first
##      runtime wiring played clips whose keys replaced the rest pose, and both characters
##      stood with their arms straight up; a state-name check passed over it;
##   4. holding a movement key plays walk, the legs swing forward and back (along the
##      character's facing, not sideways), and releasing it returns to idle with the legs back
##      under the body, not frozen mid-stride;
##   5. a click on the floor, through `PointerNavigator`, walks with the same clip and stops
##      in idle; holding Shift with a movement key jogs, with the same limb checks as the walk;
##   6. the classroom Q's tween walk plays walk and returns to idle;
##   6b. the classroom N — the one model exported facing −Z — idles on the four loops its
##      author made, measured moving on the skeleton, and its tween walk passes the same
##      limb checks as the player's: legs along its facing, knees folding backwards;
##   7. Q following the player walks, faces the way it walks, and idles when it stops;
##   8. the facing the controllers decide is untouched by animation: the player's pivot is
##      at `atan2(facing)`, the model under it is never moved.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 2.0
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"

## A bone in idle stays this close to its rest rotation. The idle offsets are a few degrees;
## the broken wiring put limbs ~170° from rest.
const IDLE_REST_DEGREES := 20.0
## After walking stops and the cross-fade has finished, the legs are back under the body.
const SETTLED_REST_DEGREES := 8.0
## A walking thigh has to swing at least this much across a cycle.
const WALK_SWING_DEGREES := 12.0
## Foot travel along the facing axis during a walk, in metres of skeleton space.
const WALK_FOOT_TRAVEL := 0.12

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _companion: CompanionController = null
var _navigator: PointerNavigator = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "runtime_character_animation_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "boot"
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(2)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_companion = _main.get_node_or_null("Companion") as CompanionController
	var sequence := _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _player != null:
		_navigator = _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if _host == null or _player == null or _companion == null or sequence == null or _navigator == null:
		Harness.finish(self, ["main.tscn did not expose the host, player, companion, director and pointer."], "")
		return
	sequence.allow_player_control()
	# The passive inner voice can open a conversation at any time, which locks the player
	# mid-walk and turns every timing below into a race. It has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	Engine.time_scale = TIME_SCALE

	Harness.stage = "classroom"
	if not await _enter(CLASSROOM, &"PlayerStart"):
		Harness.finish(self, _failures, "")
		return
	var player_animator := _player.get_character_animator()
	if player_animator == null or not player_animator.is_bound():
		_failures.append("The player's protagonist model has no bound CharacterVisualAnimation.")
		Harness.finish(self, _failures, "")
		return
	if player_animator.get_locomotion_body() != _player:
		_failures.append("The protagonist's animator is not driven by the player's own body.")
	_check_tracks_are_bones_only("protagonist", player_animator)
	_notes.append("protagonist bind: %s" % CharacterAnimation.describe(player_animator.get_bind_report()))
	_check_walking_limbs_free("protagonist", player_animator)
	_check_in_game_look("protagonist", player_animator)

	Harness.stage = "wake"
	await _check_wake(player_animator)

	Harness.stage = "player idle"
	await _seconds(0.6)
	await _check_idle_pose("the player, standing at the start", player_animator, IDLE_REST_DEGREES)

	Harness.stage = "player keyboard"
	await _check_keyboard_walk(player_animator)

	Harness.stage = "player mouse"
	await _check_click_walk(player_animator)

	Harness.stage = "classroom Q"
	await _check_classroom_q()

	Harness.stage = "classroom N"
	await _check_classroom_n()

	Harness.stage = "player sprint"
	await _check_sprint_jog(player_animator)

	Harness.stage = "companion Q"
	await _check_companion()

	_report()
	Engine.time_scale = 1.0
	Harness.finish(
		self, _failures,
		"in main.tscn the player (keys and clicks), the classroom Q, the classroom N and the "
		+ "following Q idle and walk through one animator, with limbs measured where they belong "
		+ "and facing untouched."
	)


# --- the player -------------------------------------------------------------


## A new game opens asleep at the desk: the director's `set_wake_pose(1.0)` seats the
## model, and the settle back to 0 is the get-up. Measured, so a seated pose that folded the
## legs backwards (the wrong hip sign) fails here rather than in a screenshot.
func _check_wake(animator: CharacterVisualAnimation) -> void:
	await _frames(2)
	if not animator.is_seated() or animator.get_current_clip() != CharacterVisualAnimation.SEATED_CLIP:
		_failures.append(
			"A new game should open with the protagonist seated (wake pending), but the model is on '%s'."
			% animator.get_current_clip()
		)
	else:
		var hip := _bone(animator, "thigh.L")
		var knee := _bone(animator, "shin.L")
		var foot := _bone(animator, "foot.L")
		if hip >= 0 and knee >= 0 and foot >= 0:
			var thigh := _joint(animator, knee) - _joint(animator, hip)
			var shin := _joint(animator, foot) - _joint(animator, knee)
			_notes.append("seated: knee %+.2f m ahead of the hip, foot %.2f m below the knee" % [thigh.z, -shin.y])
			if thigh.z < 0.2:
				_failures.append(
					"Seated, the protagonist's knee is %+.2f m ahead of the hip: the thighs are not forward."
					% thigh.z
				)
			if -shin.y < 0.2:
				_failures.append("Seated, the protagonist's shin does not hang down (foot %.2f m below the knee)." % -shin.y)
	_player.set_wake_pose(0.0)
	_player.set_camera_roll(0.0)
	await _frames(1)
	if not animator.is_playing_action() or animator.get_current_clip() != "get_up":
		_failures.append("Settling the wake pose did not play the get-up (clip '%s')." % animator.get_current_clip())
	var waited := 0.0
	while animator.is_playing_action() and waited < 4.0:
		await _seconds(0.1)
		waited += 0.1
	if animator.is_playing_action():
		_failures.append("The get-up never finished.")
	elif animator.is_seated() or animator.get_current_clip() != String(CharacterVisualAnimation.STATE_IDLE):
		_failures.append("After the get-up the protagonist is on '%s', not idle." % animator.get_current_clip())


func _check_keyboard_walk(animator: CharacterVisualAnimation) -> void:
	var action := _clear_movement_action(2.0)
	if action.is_empty():
		_failures.append("No movement key has 2 m of clear floor in front of the player start; cannot test WASD.")
		return
	var model := _player_model()
	var model_transform := model.transform if model != null else Transform3D.IDENTITY
	var visual_rotation := _player.visual.rotation

	Input.action_press(action)
	# Half a second of game time at 3.6 m/s is ~1.8 m: inside the clear floor just measured,
	# so the walk is measured on open ground and not against a desk.
	var walked := await _sample_walk("the player (key '%s')" % action, animator, 0.5)
	Input.action_release(action)
	if not walked:
		return
	# The facing is the controller's: the pivot turned to the direction of travel by atan2,
	# and nothing under it was moved by the animation.
	var facing := _player.get_facing_direction()
	var expected_yaw := atan2(facing.x, facing.z)
	var pivot := _player.visual_pivot
	if absf(angle_difference(pivot.rotation.y, expected_yaw)) > deg_to_rad(6.0):
		_failures.append(
			"While walking, the player's pivot sits at %.1f° but the controller faces %.1f°."
			% [rad_to_deg(pivot.rotation.y), rad_to_deg(expected_yaw)]
		)
	if model != null and not model.transform.is_equal_approx(model_transform):
		_failures.append("Walking moved the protagonist model under the pivot: %s → %s." % [model_transform, model.transform])
	if not _player.visual.rotation.is_equal_approx(visual_rotation):
		_failures.append("Walking changed %Visual's rotation; only the wake beat writes it.")
	var model_forward := pivot.global_basis.z
	model_forward.y = 0.0
	if model_forward.normalized().dot(facing.normalized()) < 0.95:
		_failures.append("The protagonist walks one way and faces another (model +Z %s, facing %s)." % [model_forward, facing])

	await _check_returns_to_idle("the player after releasing the key", animator)


func _check_click_walk(animator: CharacterVisualAnimation) -> void:
	await _seconds(0.3)
	var screen: Variant = _walkable_screen_point(2.2, 6.0)
	if screen == null:
		_failures.append("No floor 2.2–6 m from the player is visible to the camera; cannot test click-to-move.")
		return
	_navigator.click_at_screen_position(screen)
	if not _navigator.was_last_click_accepted():
		_failures.append("A click on walkable floor was refused: %s" % _navigator.get_last_rejection())
		return
	if not _player.is_path_active():
		_failures.append("A click on the floor was accepted but started no walk.")
		return
	_notes.append("click walk to %s" % str(_player.get_path_target()))
	if not await _sample_walk("the player (click-to-move)", animator, 0.6):
		_player.cancel_path()
		return
	var waited := 0.0
	while _player.is_path_active() and waited < 8.0:
		await _seconds(0.1)
		waited += 0.1
	if _player.is_path_active():
		_failures.append("The click-to-move walk did not arrive within 8 s.")
		_player.cancel_path()
	await _check_returns_to_idle("the player after the click-to-move walk arrived", animator)


## Shift held with a movement key: the body aims for `jog_speed` (5.6 m/s), crosses the jog
## threshold (4.4) and the clip follows. Measured in the walkway, which has the room for it,
## with the same knee/elbow/hand/foot checks as the walk; releasing the keys returns to idle.
func _check_sprint_jog(animator: CharacterVisualAnimation) -> void:
	if not await _enter(CORRIDOR, &"FromClassroom"):
		return
	await _seconds(0.3)
	var action := _clear_movement_action(3.5)
	if action.is_empty():
		_failures.append("No movement key has 3.5 m of clear floor at the walkway spawn; cannot test Shift jog.")
		return
	Input.action_press(PlayerController.SPRINT_ACTION)
	Input.action_press(action)
	# Up to speed in ~0.3 s at 18 m/s², then ~0.35 s of jogging: about 2.6 m of the 3.5 m.
	var jogged := await _sample_walk(
		"the player (Shift + '%s')" % action, animator, 0.65, CharacterVisualAnimation.STATE_JOG
	)
	Input.action_release(action)
	Input.action_release(PlayerController.SPRINT_ACTION)
	if jogged:
		await _check_returns_to_idle("the player after the Shift jog", animator)


# --- Q ----------------------------------------------------------------------


func _check_classroom_q() -> void:
	var location := _host.get_current()
	var q: NpcActor = null
	if location != null:
		q = location.find_actor(&"q")
	if q == null:
		_failures.append("The classroom has no authored Q.")
		return
	var animator := q.get_character_animator()
	if animator == null or not animator.is_bound():
		_failures.append("The classroom Q's model has no bound CharacterVisualAnimation.")
		return
	_check_tracks_are_bones_only("classroom Q", animator)
	_notes.append("Q bind: %s" % CharacterAnimation.describe(animator.get_bind_report()))
	_check_walking_limbs_free("Q", animator)
	_check_in_game_look("Q", animator)
	_check_distinct_rhythm(_player.get_character_animator(), animator)
	if animator.get_locomotion_body() != null:
		_failures.append("The classroom Q is not under a body, but its animator found one: %s." % animator.get_locomotion_body())
	await _check_idle_pose("the classroom Q, standing", animator, IDLE_REST_DEGREES)

	var start := q.global_position
	var start_rotation := q.rotation.y
	# A short step sideways along the room and back: the tween walk does not collide, and the
	# test puts Q back where the scene put it.
	var target := start + Vector3(0.9, 0.0, 0.0)
	q.walk_along([target])
	await _frames(3)
	if animator.get_locomotion_state() != CharacterVisualAnimation.STATE_WALK:
		_failures.append("The classroom Q's walk_along() did not play walk (state %s)." % animator.get_locomotion_state())
	var model_forward := (q.global_basis * q.get_visual().transform.basis) * _model_forward(animator)
	model_forward.y = 0.0
	if model_forward.normalized().dot(Vector3.RIGHT) < 0.95:
		_failures.append("The classroom Q walks +X but its model faces %s." % model_forward.normalized())
	var waited := 0.0
	while q.global_position.distance_to(target) > 0.01 and waited < 4.0:
		await _seconds(0.1)
		waited += 0.1
	await _frames(2)
	if animator.get_locomotion_state() != CharacterVisualAnimation.STATE_IDLE:
		_failures.append("The classroom Q kept walking after walk_along() finished.")
	await _seconds(0.4)
	await _check_idle_pose("the classroom Q after its walk", animator, SETTLED_REST_DEGREES, true)
	q.global_position = start
	q.rotation.y = start_rotation


## N is hidden until the opening walks it in through the door, so this drives the same actor
## the opening drives, through the same `walk_along()`, while nobody can see it, and puts it
## back exactly as the scene placed it.
func _check_classroom_n() -> void:
	var location := _host.get_current()
	var n: NpcActor = null
	if location != null:
		n = location.find_actor(&"n")
	if n == null:
		_failures.append("The classroom has no N.")
		return
	var animator := n.get_character_animator()
	if animator == null or not animator.is_bound():
		_failures.append("The classroom N's model has no bound CharacterVisualAnimation.")
		return
	var report := animator.get_bind_report()
	_check_tracks_are_bones_only("classroom N", animator)
	_notes.append("N bind: %s" % CharacterAnimation.describe(report))
	_check_walking_limbs_free("N", animator)
	if not animator.faces_negative_z or String(report.get("faces", "")) != "-Z":
		_failures.append("N's model faces −Z, but its clips were bound for %s." % report.get("faces", "?"))
	if not (report.get("mirrored", []) as Array).is_empty():
		# Bound in N's own frame, `.L` is the limb on the character's −X side, which on a −Z
		# model is the one its author named `.R`, exactly as on a +Z model turned round.
		_notes.append("N mirrored pairs (expected for a −Z model): %s" % [report["mirrored"]])

	# Idle is the author's: four layers, every one found, every track a bone of N's skeleton.
	var authored: Dictionary = report.get("authored_idle", {})
	if not bool(authored.get("ok", false)):
		_failures.append("N's idle is not built from its own clips: %s" % authored.get("reason", "no report"))
	else:
		var layers: PackedStringArray = authored["layers"]
		if layers.size() != 4:
			_failures.append("N's idle combines %d of the model's clips, not its four loops." % layers.size())
		if int(authored["ignored_tracks"]) != 0:
			_failures.append("%d track(s) of N's own clips could not be applied." % int(authored["ignored_tracks"]))
		_notes.append(
			"N idle: %s, %d bone(s) moved, %d held, %.2fs"
			% [", ".join(layers), (authored["bones"] as Array).size(), int(authored["held"]), float(authored["length"])]
		)
	await _check_idle_pose("the classroom N, standing", animator, IDLE_REST_DEGREES)
	await _check_idle_moves(animator)

	var was_visible := n.visible
	var start := n.global_transform
	# Two metres along the front of the room and back: long enough for the walk to cover more
	# than a stride at N's 1.5 m/s, and the tween does not collide.
	var target := n.global_position + Vector3(-2.0, 0.0, 0.0)
	n.walk_along([target])
	await _frames(3)
	if animator.get_locomotion_state() != CharacterVisualAnimation.STATE_WALK:
		_failures.append("The classroom N's walk_along() did not play walk (state %s)." % animator.get_locomotion_state())
	var model_forward := (n.global_basis * n.get_visual().transform.basis) * _model_forward(animator)
	model_forward.y = 0.0
	if model_forward.normalized().dot(Vector3.LEFT) < 0.95:
		_failures.append("The classroom N walks −X but its model faces %s." % model_forward.normalized())
	await _sample_walk("the classroom N", animator, 0.9)
	var waited := 0.0
	while n.global_position.distance_to(target) > 0.01 and waited < 4.0:
		await _seconds(0.1)
		waited += 0.1
	await _check_returns_to_idle("the classroom N after its walk", animator)
	n.global_transform = start
	n.visible = was_visible


## The authored idle is played, not just bound: over one five-second cycle N's head and spine
## move by more than a held pose would, and less than anything but a small idle.
func _check_idle_moves(animator: CharacterVisualAnimation) -> void:
	var skeleton := animator.get_skeleton()
	var bones := {}
	for canonical in ["head", "spine"]:
		var index := _bone(animator, canonical)
		if index >= 0:
			bones[canonical] = [INF, -INF]
	var length := 5.0
	var authored: Dictionary = animator.get_bind_report().get("authored_idle", {})
	if bool(authored.get("ok", false)):
		length = float(authored["length"])
	var elapsed := 0.0
	while elapsed < length + 0.1:
		await process_frame
		elapsed += _frame_seconds()
		for canonical: String in bones:
			var angle := _angle_from_rest(skeleton, _bone(animator, canonical))
			var span: Array = bones[canonical]
			bones[canonical] = [minf(float(span[0]), angle), maxf(float(span[1]), angle)]
	for canonical: String in bones:
		var span: Array = bones[canonical]
		var moved := float(span[1]) - float(span[0])
		_notes.append("N idle %s moves %.2f° over a cycle" % [canonical, moved])
		if moved < 1.0:
			_failures.append("N's %s moves only %.2f° over an idle cycle: the authored idle is not playing." % [canonical, moved])
		if float(span[1]) > IDLE_REST_DEGREES:
			_failures.append("N's %s reaches %.1f° from rest while idle." % [canonical, float(span[1])])


func _check_companion() -> void:
	if not await _enter(CORRIDOR, &"FromClassroom"):
		return
	_companion.join()
	await _seconds(0.8)
	if not _companion.is_with_player():
		_failures.append("Q did not appear beside the player in the walkway after join().")
		return
	var animator := _companion.get_character_animator()
	if animator == null or not animator.is_bound():
		_failures.append("The companion Q has no bound CharacterVisualAnimation.")
		return
	if animator.get_locomotion_body() != _companion:
		_failures.append("The companion Q's animator is not driven by the companion's body.")
	if animator.get_script() != _player.get_character_animator().get_script():
		_failures.append("Q and the player are animated by different scripts; the rule is meant to be one.")
	await _check_idle_pose("Q standing beside the player", animator, IDLE_REST_DEGREES)

	# Walk the player away so Q has to follow on its own.
	var destination: Variant = _farthest_reachable(_player.global_position, 7.0)
	if destination == null or not _player.request_path_to(destination):
		_failures.append("Could not walk the player away from Q in the walkway.")
		return
	var walk_frames := 0
	var facing_checked := 0
	var facing_wrong := 0
	var mismatched := 0
	var thigh := _bone(animator, "thigh.L")
	var thigh_angles: Array[float] = []
	var elapsed := 0.0
	while elapsed < 6.0:
		await process_frame
		elapsed += _frame_seconds()
		var velocity := Vector3(_companion.velocity.x, 0.0, _companion.velocity.z)
		var state := animator.get_locomotion_state()
		# Q catches up at 4.4 m/s, the jog threshold: walking or jogging are both moving.
		var moving_clip := state == CharacterVisualAnimation.STATE_WALK or state == CharacterVisualAnimation.STATE_JOG
		if moving_clip:
			walk_frames += 1
			if thigh >= 0:
				thigh_angles.append(_angle_from_rest(animator.get_skeleton(), thigh))
		# The rule, checked against the body directly: clearly moving is walk, still is idle.
		if velocity.length() > animator.walk_enter_speed + 0.3 and not moving_clip:
			mismatched += 1
		if velocity.length() > 1.0:
			facing_checked += 1
			var actor := _companion.get_node(^"Actor") as NpcActor
			var forward := (actor.global_basis * actor.get_visual().transform.basis) * Vector3(0.0, 0.0, 1.0)
			forward.y = 0.0
			if forward.normalized().dot(velocity.normalized()) < 0.5:
				facing_wrong += 1
		if not _player.is_path_active() and velocity.length() < 0.02 and walk_frames > 0:
			break
	_notes.append(
		"companion: %d walk frame(s), facing checked on %d (%d wrong), %d mismatch(es), note '%s'"
		% [walk_frames, facing_checked, facing_wrong, mismatched, _companion.get_last_chase_note()]
	)
	if walk_frames == 0:
		_failures.append("Q never walked while following a player who walked %.1f m away." % 7.0)
		return
	# The animator decides in its own _process, which runs after this coroutine resumes on
	# `process_frame`: each start of a walk can be one frame behind the body. More than that
	# is the rule not being followed.
	if mismatched * 10 > walk_frames + 10:
		_failures.append("Q moved faster than %.2f m/s on %d frame(s) without walking." % [animator.walk_enter_speed + 0.3, mismatched])
	if facing_checked > 0 and facing_wrong * 4 > facing_checked:
		_failures.append("Q walked facing away from its direction of travel on %d of %d frames." % [facing_wrong, facing_checked])
	if not thigh_angles.is_empty():
		var swing: float = float(thigh_angles.max()) - float(thigh_angles.min())
		if swing < WALK_SWING_DEGREES * 0.5:
			_failures.append("Q's walk swung its thigh only %.1f°; the legs are not moving." % swing)
	await _check_returns_to_idle("Q after catching up", animator)


# --- shared measurements ----------------------------------------------------


## Plays out a stretch of walking (or, with `state` = jog, jogging) and measures it. Returns
## whether the character played that clip.
func _sample_walk(
	label: String, animator: CharacterVisualAnimation, duration: float,
	state: StringName = CharacterVisualAnimation.STATE_WALK
) -> bool:
	var skeleton := animator.get_skeleton()
	var thigh := _bone(animator, "thigh.L")
	var foot := _bone(animator, "foot.L")
	var walk_frames := 0
	var frames := 0
	var thigh_angles: Array[float] = []
	var foot_min := Vector3(INF, INF, INF)
	var foot_max := Vector3(-INF, -INF, -INF)
	var raised_hands := 0
	# Joint bends, as the sine of the angle with its sign about the character's side axis:
	# a knee only ever folds the shin back (positive), an elbow only ever folds the forearm
	# forward (negative). A clip whose X convention were the wrong way round would still
	# swing the feet forward and back, but with knees and elbows bending backwards.
	var limbs := _bending_limbs(animator)
	var bend_min := {}
	var bend_max := {}
	var elapsed := 0.0
	var max_scale := 0.0
	while elapsed < duration:
		await process_frame
		elapsed += _frame_seconds()
		frames += 1
		if animator.get_locomotion_state() != state:
			continue
		walk_frames += 1
		max_scale = maxf(max_scale, animator.get_animation_player().speed_scale)
		if thigh >= 0:
			thigh_angles.append(_angle_from_rest(skeleton, thigh))
		if foot >= 0:
			var at := _joint(animator, foot)
			foot_min = foot_min.min(at)
			foot_max = foot_max.max(at)
		for joint: String in limbs:
			var chain: Array = limbs[joint]
			var bend := _bend(animator, chain, false)
			bend_min[joint] = minf(float(bend_min.get(joint, INF)), bend)
			bend_max[joint] = maxf(float(bend_max.get(joint, -INF)), bend)
		# The arms swing, they never come up past the shoulder.
		for side in ["L", "R"]:
			var shoulder := _bone(animator, "upper_arm.%s" % side)
			var hand := _bone(animator, "hand.%s" % side)
			if shoulder >= 0 and hand >= 0 and _joint(animator, hand).y > _joint(animator, shoulder).y - 0.03:
				raised_hands += 1
	if walk_frames == 0:
		_failures.append(
			"%s moved (speed %.2f m/s) but never played %s in %d frame(s)."
			% [label, animator.get_planar_speed(), state, frames]
		)
		return false
	var player := animator.get_animation_player()
	if player.current_animation != "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), state] or not player.is_playing():
		_failures.append("%s reports %s but its AnimationPlayer is on '%s'." % [label, state, player.current_animation])
	var swing := 0.0
	if not thigh_angles.is_empty():
		swing = float(thigh_angles.max()) - float(thigh_angles.min())
	var travel := foot_max - foot_min
	_notes.append(
		"%s: %s on %d/%d frames, thigh swing %.1f°, foot travel z %.3f x %.3f m, playback ×%.2f"
		% [label, state, walk_frames, frames, swing, travel.z, travel.x, max_scale]
	)
	if swing < WALK_SWING_DEGREES:
		_failures.append("%s plays walk but its thigh swings only %.1f°." % [label, swing])
	for joint: String in bend_min:
		var rest_bend := _bend(animator, limbs[joint], true)
		var low := float(bend_min[joint]) - rest_bend
		var high := float(bend_max[joint]) - rest_bend
		_notes.append("%s %s bend vs rest %+.2f..%+.2f" % [label, joint, low, high])
		if joint.begins_with("knee"):
			if low < -0.1:
				_failures.append("%s's %s bends backwards while walking (%+.2f against rest)." % [label, joint, low])
			if high < 0.2:
				_failures.append("%s's %s barely bends while walking (at most %+.2f against rest)." % [label, joint, high])
		elif high > 0.1:
			_failures.append("%s's %s bends backwards while walking (%+.2f against rest)." % [label, joint, high])
	if raised_hands > 0:
		_failures.append("%s raised a hand to shoulder height on %d walking frame(s)." % [label, raised_hands])
	if foot >= 0 and walk_frames >= 6:
		# Measured in the character's space, whose +Z is the way it faces. A walk swings the
		# feet along it; a clip on the wrong axis would kick them out sideways.
		if travel.z < WALK_FOOT_TRAVEL:
			_failures.append("%s's foot travels only %.3f m forward and back while walking." % [label, travel.z])
		if travel.x > travel.z * 0.5:
			_failures.append(
				"%s's foot swings %.3f m sideways against %.3f m forward: the walk is on the wrong axis."
				% [label, travel.x, travel.z]
			)
	return true


## Waits for the character to stop and checks it is idle with the limbs back at rest.
func _check_returns_to_idle(label: String, animator: CharacterVisualAnimation) -> void:
	var waited := 0.0
	while animator.get_locomotion_state() != CharacterVisualAnimation.STATE_IDLE and waited < 4.0:
		await _seconds(0.05)
		waited += 0.05
	if animator.get_locomotion_state() != CharacterVisualAnimation.STATE_IDLE:
		_failures.append("%s never returned to idle (speed %.2f m/s)." % [label, animator.get_planar_speed()])
		return
	var player := animator.get_animation_player()
	if player.current_animation != "%s/idle" % String(CharacterAnimation.LIBRARY_NAME):
		_failures.append("%s is idle but its AnimationPlayer is on '%s'." % [label, player.current_animation])
	if not is_equal_approx(player.speed_scale, 1.0):
		_failures.append("%s idles at playback ×%.2f; the walk's speed leaked into idle." % [label, player.speed_scale])
	# Past the cross-fade, then the legs have to be under the body again.
	await _seconds(animator.blend_time + 0.3)
	await _check_idle_pose(label, animator, SETTLED_REST_DEGREES, true)


## In the running game, the character is the painted one with its own motion profile: the
## wrapper's profile was bound (and named nothing the rig cannot move), and its Look applier
## is on PAINTED with no surface left in the GLB's material.
func _check_in_game_look(label: String, animator: CharacterVisualAnimation) -> void:
	var report := animator.get_bind_report()
	if animator.motion_profile == null or String(report.get("profile", "")).is_empty():
		_failures.append("The in-game %s was bound without its motion profile." % label)
	elif not (report.get("profile_ignored", []) as Array).is_empty():
		_failures.append("The in-game %s's profile names bones it cannot move: %s" % [label, str(report["profile_ignored"])])
	var applier := animator.get_node_or_null(^"Look") as CharacterLookApplier
	if applier == null:
		_failures.append("The in-game %s has no Look applier." % label)
		return
	var look := applier.get_report()
	if String(look.get("treatment", "")) != "PAINTED" or not (look.get("kept", []) as Array).is_empty():
		_failures.append(
			"The in-game %s is drawn %s and kept %s; it should be painted throughout."
			% [label, String(look.get("treatment", "?")), str(look.get("kept", []))]
		)
	_notes.append(
		"%s look: %s, %d/%d surfaces painted, %d outlined, %d mesh(es) with rest coordinates"
		% [
			label, String(look.get("look", "")), int(look.get("replaced", 0)), int(look.get("surfaces", 0)),
			(look.get("outlined", []) as Array).size(), (look.get("rebuilt_meshes", []) as Array).size(),
		]
	)


## The protagonist and Q, as the game built them, do not share one body rhythm.
func _check_distinct_rhythm(protagonist: CharacterVisualAnimation, q: CharacterVisualAnimation) -> void:
	if protagonist == null or q == null:
		return
	var library := String(CharacterAnimation.LIBRARY_NAME)
	var parts: PackedStringArray = []
	var same: Array[String] = []
	for clip_name: String in ["idle", "walk", "talk", "wave"]:
		var mine := protagonist.get_animation_player().get_animation("%s/%s" % [library, clip_name])
		var theirs := q.get_animation_player().get_animation("%s/%s" % [library, clip_name])
		if mine == null or theirs == null:
			continue
		parts.append("%s %.2f/%.2f s" % [clip_name, mine.length, theirs.length])
		if is_equal_approx(mine.length, theirs.length):
			same.append(clip_name)
	_notes.append("clip lengths in game, protagonist / Q: %s" % ", ".join(parts))
	if same.size() > 1:
		_failures.append("The protagonist and Q play %s at the same tempo in game." % str(same))


## Idle means the character is standing the way it was modelled: limbs near rest, hands below
## the shoulders, feet below the hips.
func _check_idle_pose(
	label: String, animator: CharacterVisualAnimation, tolerance: float, legs_only: bool = false
) -> void:
	await _frames(2)
	if animator.get_locomotion_state() != CharacterVisualAnimation.STATE_IDLE:
		_failures.append("%s is not idle (state '%s')." % [label, animator.get_locomotion_state()])
		return
	var skeleton := animator.get_skeleton()
	if skeleton == null:
		_failures.append("%s has no skeleton to measure." % label)
		return
	var worst := 0.0
	var worst_bone := ""
	var bones := ["thigh.L", "thigh.R", "shin.L", "shin.R"]
	if not legs_only:
		bones.append_array(["upper_arm.L", "upper_arm.R", "fore_arm.L", "fore_arm.R", "spine", "head"])
	for canonical: String in bones:
		var index := _bone(animator, canonical)
		if index < 0:
			continue
		var angle := _angle_from_rest(skeleton, index)
		if angle > worst:
			worst = angle
			worst_bone = canonical
	if worst > tolerance:
		_failures.append(
			"%s stands with '%s' %.1f° away from its rest pose (allowed %.1f°): the idle pose is not the modelled one."
			% [label, worst_bone, worst, tolerance]
		)
	for side in ["L", "R"]:
		var shoulder := _bone(animator, "upper_arm.%s" % side)
		var hand := _bone(animator, "hand.%s" % side)
		if shoulder >= 0 and hand >= 0:
			# Against the rig's own modelled arm, not a fixed number: Q is modelled with the
			# right forearm held out in front, the protagonist with both arms hanging.
			var drop := _joint(animator, shoulder).y - _joint(animator, hand).y
			var rest_drop := _rest_joint(animator, shoulder).y - _rest_joint(animator, hand).y
			if drop < 0.03 or drop < rest_drop - 0.1:
				_failures.append(
					"%s's %s hand is %.2f m below the shoulder, modelled %.2f m: the arm is raised."
					% [label, side, drop, rest_drop]
				)
		var hip := _bone(animator, "thigh.%s" % side)
		var foot := _bone(animator, "foot.%s" % side)
		if hip >= 0 and foot >= 0:
			var leg := _joint(animator, hip).y - _joint(animator, foot).y
			if leg < 0.5:
				_failures.append("%s's %s foot is %.2f m below the hip: the leg is not under the body." % [label, side, leg])
	_notes.append("%s: idle, worst bone %s %.1f° from rest" % [label, worst_bone, worst])


## A limb the rig does not model hanging down is held at its modelled pose
## (`CharacterAnimation.posed_limbs`). That is right for Q's carried forearm, and would be a
## silent failure for the limbs a walk is made of: a re-import that changed their rest would
## freeze the legs or the arm swing without an error anywhere.
func _check_walking_limbs_free(label: String, animator: CharacterVisualAnimation) -> void:
	var posed: Array = animator.get_bind_report().get("posed", [])
	for canonical in ["thigh.L", "thigh.R", "shin.L", "shin.R", "upper_arm.L", "upper_arm.R"]:
		if posed.has(canonical):
			_failures.append(
				"%s's '%s' is held at its modelled pose, so it does not walk: its rest no longer hangs down."
				% [label, canonical]
			)


## The clips are allowed to touch bone rotations and nothing else.
func _check_tracks_are_bones_only(label: String, animator: CharacterVisualAnimation) -> void:
	var player := animator.get_animation_player()
	var skeleton := animator.get_skeleton()
	if player == null or skeleton == null:
		_failures.append("%s has no animation player or skeleton." % label)
		return
	var skeleton_path := String(animator.get_path_to(skeleton))
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for track in animation.get_track_count():
			var path := String(animation.track_get_path(track))
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or not path.begins_with(skeleton_path + ":"):
				_failures.append(
					"%s clip '%s' has a track that is not a bone rotation (%s); animation must not move or turn the character."
					% [label, clip, path]
				)
				return


# --- helpers ----------------------------------------------------------------


func _enter(scene: String, spawn: StringName) -> bool:
	if not _host.load_location(scene, spawn, _player):
		_failures.append("Could not load %s." % scene)
		return false
	await _frames(3)
	await _physics_frames(2)
	var location := _host.get_current()
	var nav: LocationNavigation = null
	if location != null:
		nav = location.get_node_or_null("Navigation") as LocationNavigation
	if nav != null and not await nav.wait_until_synchronized():
		_failures.append("%s's navigation never synchronized: %s" % [scene, nav.describe_sync()])
		return false
	await _frames(2)
	return true


func _player_model() -> Node3D:
	return _player.visual.get_node_or_null(^"Model") as Node3D if _player.visual != null else null


## The movement key whose camera-relative direction has `distance` of clear floor ahead.
func _clear_movement_action(distance: float) -> String:
	var rig := _player.camera_rig
	var forward := rig.planar_forward() if rig != null else Vector3.FORWARD
	var right := rig.planar_right() if rig != null else Vector3.RIGHT
	var candidates := {
		"move_forward": forward, "move_back": -forward, "move_right": right, "move_left": -right,
	}
	var lifted := _player.global_transform.translated(Vector3.UP * 0.05)
	for action: String in candidates:
		var direction: Vector3 = candidates[action]
		if not _player.test_move(lifted, direction.normalized() * distance):
			return action
	return ""


## A screen position the pointer would turn into a walk to floor `min_distance`–`max_distance`
## away, found the way a player finds one: by looking at the screen.
func _walkable_screen_point(min_distance: float, max_distance: float) -> Variant:
	var rect := _player.get_viewport().get_visible_rect().size
	var interaction := _player.get_node_or_null("InteractionController") as InteractionController
	for y_step in 10:
		for x_step in 10:
			var screen := Vector2(
				rect.x * (0.15 + 0.7 * float(x_step) / 9.0), rect.y * (0.3 + 0.55 * float(y_step) / 9.0)
			)
			var point: Variant = _navigator.get_ground_point_at(screen)
			if point == null:
				continue
			var distance := Vector2(point.x - _player.global_position.x, point.z - _player.global_position.z).length()
			if distance < min_distance or distance > max_distance:
				continue
			if interaction != null and interaction.get_target_at_screen_position(screen, false) != null:
				continue
			return screen
	return null


func _farthest_reachable(origin: Vector3, max_distance: float) -> Variant:
	var map := _player.navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_regions(map).is_empty():
		return null
	var floor_y := NavigationServer3D.map_get_closest_point(map, origin).y
	var best: Variant = null
	var best_length := 0.0
	for index in 24:
		var angle := TAU * float(index) / 24.0
		var candidate := origin + Vector3(cos(angle), 0.0, sin(angle)) * max_distance
		var on_mesh := NavigationServer3D.map_get_closest_point(map, candidate)
		if absf(on_mesh.y - floor_y) > 0.15:
			continue
		var path := NavigationServer3D.map_get_path(map, origin, on_mesh, true)
		if path.size() < 2 or path[path.size() - 1].distance_to(on_mesh) > 0.3:
			continue
		var length := Vector2(on_mesh.x - origin.x, on_mesh.z - origin.z).length()
		if length > best_length:
			best_length = length
			best = on_mesh
	return best


func _bone(animator: CharacterVisualAnimation, canonical: String) -> int:
	var resolved: Dictionary = animator.get_bind_report().get("resolved", {})
	if not resolved.has(canonical):
		return -1
	return animator.get_skeleton().find_bone(String(resolved[canonical]))


## A joint's position in the character's own space: +Y up, +Z the way the character faces,
## whatever transform the glTF armature node carries. For the +Z models that is the wrapper's
## space; a model that faces −Z (N) is measured half a turn round, so "forward" and "the side
## axis" mean the same thing on every character and the limb checks need no second version.
func _joint(animator: CharacterVisualAnimation, index: int) -> Vector3:
	var skeleton := animator.get_skeleton()
	return _to_character(animator) * skeleton.get_bone_global_pose(index).origin


## Skeleton space to the character's own space (see `_joint()`).
func _to_character(animator: CharacterVisualAnimation) -> Transform3D:
	var skeleton := animator.get_skeleton()
	var to_wrapper := animator.global_transform.affine_inverse() * skeleton.global_transform
	if animator.faces_negative_z:
		to_wrapper = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * to_wrapper
	return to_wrapper


## The way the model looks in its wrapper's space.
func _model_forward(animator: CharacterVisualAnimation) -> Vector3:
	return Vector3.FORWARD if animator.faces_negative_z else Vector3.BACK


## The knees and elbows a walk bends, as `name → [upper, joint, end]` bone indices. An elbow
## the rig holds at its modelled pose (see `CharacterAnimation.posed_limbs`) is left out.
func _bending_limbs(animator: CharacterVisualAnimation) -> Dictionary:
	var posed: Array = animator.get_bind_report().get("posed", [])
	var limbs := {}
	for side in ["L", "R"]:
		var knee := [_bone(animator, "thigh.%s" % side), _bone(animator, "shin.%s" % side), _bone(animator, "foot.%s" % side)]
		if not knee.has(-1):
			limbs["knee.%s" % side] = knee
		if posed.has("fore_arm.%s" % side) or posed.has("upper_arm.%s" % side):
			continue
		var elbow := [_bone(animator, "upper_arm.%s" % side), _bone(animator, "fore_arm.%s" % side), _bone(animator, "hand.%s" % side)]
		if not elbow.has(-1):
			limbs["elbow.%s" % side] = elbow
	return limbs


## How far the middle joint of a three-bone chain is folded, signed about the character's X
## (its side axis, see `_joint()`): the X of `upper × lower` on unit vectors.
func _bend(animator: CharacterVisualAnimation, chain: Array, rest: bool) -> float:
	var points: Array[Vector3] = []
	for index: int in chain:
		points.append(_rest_joint(animator, index) if rest else _joint(animator, index))
	var upper := (points[1] - points[0]).normalized()
	var lower := (points[2] - points[1]).normalized()
	return upper.cross(lower).x


## Where a joint sits in the modelled pose, in the same character space as `_joint()`.
func _rest_joint(animator: CharacterVisualAnimation, index: int) -> Vector3:
	var skeleton := animator.get_skeleton()
	return _to_character(animator) * skeleton.get_bone_global_rest(index).origin


func _angle_from_rest(skeleton: Skeleton3D, index: int) -> float:
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	return rad_to_deg(skeleton.get_bone_pose_rotation(index).angle_to(rest))


func _seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await process_frame
		elapsed += _frame_seconds()


## Seconds of game time the last frame advanced (time scale included).
func _frame_seconds() -> float:
	return maxf(root.get_process_delta_time(), 1.0 / 240.0)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	print("::notice title=runtime character animation::%s" % "|".join(_notes))
