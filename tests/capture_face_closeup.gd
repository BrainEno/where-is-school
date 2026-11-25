extends SceneTree
## Records #387's close-up evidence: a real `q_wake` conversation on the game's own
## cameras - the wide talk shot, then Q's face insert (`q_face.tres`, following his
## live `Head` bone) - showing a directed face state entering and settling, the
## close-up gaze engaging on the insert, one staged attention shift and its return,
## the authored grin playing through untouched, and everything released back to the
## gameplay framing when the conversation ends.
##
## This is a *recording*, not a screenshot run: it is meant to be executed with Godot's
## movie maker, which renders at a fixed step and writes every frame, so the result is
## reproducible frame for frame:
##
##   xvfb-run -a godot --path . --resolution 1280x720 --rendering-driver opengl3 \
##     --audio-driver Dummy --write-movie build/face_closeup/frame.png \
##     --fixed-fps 24 --script res://tests/capture_face_closeup.gd
##
## Everything is driven through the game's own APIs (activation, advances, choices) at
## a frame pace the fixed step makes deterministic. The one staged beat - Q's gaze
## leaving the camera for a mark beside it and coming back - is placed by this script
## the way the laboratory walkthrough places the player: the mechanism is the game's,
## the mark is the evidence's, and the mark's position is printed with the run.
##
## The script asserts as it records (states, gaze, camera, length) and finishes with
## PASS/FAIL; the workflow refuses to upload anything a failed run produced.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"

const FPS := 24.0
## Frame holds. The whole recording lands near 27 s at 24 fps - inside the issue's
## 15-30 s window, which the end-of-run assertion enforces.
const BOOT_HOLD := 24
const WIDE_HOLD := 32
const KEY_HOLD := 24
const LINE_HOLD := 16
const INSERT_HOLD := 192
## Frames into the insert hold: the gaze leaves the lens for the mark, then returns.
const RETARGET_OUT := 84
const RETARGET_BACK := 156
const GRIN_HOLD := 36
const END_HOLD := 48
## The mark sits about 24 degrees left of the lens, three metres out: a head turn the
## close-up can show without ever leaving the frame.
const MARK_OFFSET := Vector3(-1.15, 0.05, -2.6)

var _checks := Harness.Checker.new()
var _recorded := 0
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _rig: CameraRig = null
var _focus: CameraFocusDirector = null
var _room: LocationRoot = null
var _q_actor: NpcActor = null
var _q_look: CharacterLookApplier = null
var _player: PlayerController = null
var _player_look: CharacterLookApplier = null
var _talk: Interactable = null
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 900.0, "capture_face_closeup.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	L10n.set_locale("zh-CN")
	ProjectSettings.set_setting(CharacterNameplate.SETTING, true)

	var packed := load(MAIN) as PackedScene
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	var world := packed.instantiate()
	_sequence = world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(world)
	await _frames(BOOT_HOLD)

	_dialogue = world.get_node(^"DialogueController") as DialogueController
	_rig = world.get_node(^"CameraRig") as CameraRig
	_focus = _sequence.get_camera_focus()
	_room = (world.get_node(^"LocationHost") as LocationHost).get_current()
	_player = world.get_node(^"Player") as PlayerController
	if _dialogue == null or _focus == null or _room == null \
			or _room.location_id != &"classroom":
		Harness.finish(self, ["The production classroom did not boot."], "")
		return
	_q_actor = _room.find_actor(&"q")
	_talk = _room.find_interactable(&"q_talk")
	if _q_actor == null or _talk == null:
		Harness.finish(self, ["Q or the QTalk interactable is missing."], "")
		return
	_q_look = _q_actor.get_character_animator().get_node(^"Look") as CharacterLookApplier
	_player_look = _player.get_character_animator().get_node(^"Look") as CharacterLookApplier

	# --- the wide hold: gameplay framing, Q idle at his desk --------------------
	await _frames(WIDE_HOLD)
	_face_note("wide")

	# --- activation: the wide talk shot, Q's own first line --------------------
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	interaction.request_activation(_talk)
	if not await _arrive(&"q_1", &"", 90):
		Harness.finish(self, ["q_wake did not start at q_1."], "")
		return
	await _frames(KEY_HOLD)
	_face_note("q_1")
	_checks.expect(_q_look.get_face_state() == &"friendly"
			and _q_look.get_face_state_weight() >= 0.9,
		"Q did not hold the friendly state on his own line.")
	_checks.expect(_player_look.get_face_state() == &"listening",
		"The protagonist did not hold the listening state on Q's line.")

	# --- the trunk to the insert choice, one hold per line ---------------------
	for step: Array in [[&"p_who", &""], [&"q_3", &""], [&"q_who_1", &"who"],
			[&"q_who_2", &""], [&"q_who_look", &""]]:
		if not await _arrive(step[0], step[1], 90):
			Harness.finish(self, ["The conversation did not reach %s." % String(step[0])], "")
			return
		await _frames(LINE_HOLD)
	_face_note("q_who_look")

	# --- the insert: Q's face fills the frame ----------------------------------
	if not await _arrive(&"p_why", &"watch_q", 120):
		Harness.finish(self, ["watch_q did not start the face insert on p_why."], "")
		return
	await _frames(20) # let the insert glide settle before the mark is placed
	if not _checks.expect(_focus.get_glance() == _talk, "The insert glance is not held on QTalk."):
		Harness.finish(self, _checks.failures, "")
		return
	var gaze := _q_actor.get_gaze()
	var camera := _rig.camera
	var mark := Marker3D.new()
	mark.name = "StagedAttentionMark"
	mark.position = camera.global_transform * MARK_OFFSET
	root.add_child(mark)
	_notes.append("mark at %s (lens at %s)" % [str(mark.position), str(camera.global_position)])

	var max_attention := 0.0
	var max_eye := 0.0
	var max_head := 0.0
	var yaw_at_lens := 0.0
	var yaw_at_mark := 0.0
	var engaged := false
	for step in INSERT_HOLD:
		if _q_look.get_face_state() == &"attention":
			max_attention = maxf(max_attention, _q_look.get_face_state_weight())
		if gaze != null:
			max_eye = maxf(max_eye, absf(gaze.get_applied_eye_degrees()))
			max_head = maxf(max_head, absf(gaze.get_measured_head_turn_degrees()))
			if gaze.is_looking() and gaze.get_weight() > 0.5:
				engaged = true
		if step == RETARGET_OUT:
			yaw_at_lens = gaze.get_desired_yaw_degrees() if gaze != null else 0.0
			_q_actor.watch(mark, 0.0)
			_face_note("retarget-out")
		if step == RETARGET_BACK:
			yaw_at_mark = gaze.get_desired_yaw_degrees() if gaze != null else 0.0
			camera = _rig.camera
			_q_actor.watch(camera, 0.0)
			_face_note("retarget-back")
		await _frames(1)
	_checks.expect(max_attention >= 0.9,
		"Q never held the attention state inside his insert (%.2f)." % max_attention)
	_checks.expect(engaged, "The close-up gaze never engaged on the insert.")
	_checks.expect(max_eye > 0.5 and max_eye <= 14.5,
		"The eye lead is missing or out of clamp (%.2f deg)." % max_eye)
	_checks.expect(max_head > 1.0, "Q's head never turned during the insert.")
	_checks.expect(absf(yaw_at_mark - yaw_at_lens) > 5.0,
		"The staged retarget did not move the gaze target (%.1f -> %.1f deg)."
			% [yaw_at_lens, yaw_at_mark])
	_face_note("insert-end")
	# The mark stays alive until the scene tears down: freeing it early would drop
	# the gaze target and start the release a beat before the insert ends.

	# --- out of the insert: talk shot again, Q back on his line ----------------
	if not await _arrive(&"q_zero", &"", 90):
		Harness.finish(self, ["The insert line did not advance to q_zero."], "")
		return
	await _frames(KEY_HOLD)
	_face_note("q_zero")
	_checks.expect(_focus.get_glance() == null, "The glance outlived its line.")
	_checks.expect(_q_look.get_face_state() == &"friendly"
			and _q_look.get_face_state_weight() >= 0.9,
		"Q did not return to his line state after the insert.")

	# --- the rest of the conversation to its natural end -----------------------
	for step: Array in [[&"p_zero", &""], [&"p_none", &"none"], [&"q_none_1", &""],
			[&"q_exam_end", &""], [&"p_topic_what", &""], [&"q_topic_ask", &""],
			[&"p_topic_silent", &"silent"], [&"q_topic_silent", &""], [&"q_end_2", &""],
			[&"q_end_grin", &""]]:
		if not await _arrive(step[0], step[1], 90):
			Harness.finish(self, ["The conversation did not reach %s." % String(step[0])], "")
			return
		await _frames(LINE_HOLD if step[0] != &"q_end_grin" else GRIN_HOLD)
	_face_note("grin")
	_checks.expect(await _wait_frames(36, _grin_visible),
		"The authored grin did not play on q_end_grin.")

	# --- end: everything released, camera home, faces at rest ------------------
	if not await _arrive_end(120):
		Harness.finish(self, ["The conversation did not end."], "")
		return
	await _frames(END_HOLD)
	_face_note("settled")
	_checks.expect(_q_look.get_face_state_weight() == 0.0
			and _player_look.get_face_state_weight() == 0.0,
		"A face state survived the end of the conversation.")
	_checks.expect(_rig.get_focus_weight() == 0.0 and _rig.get_focus_subject() == null,
		"The camera did not return to its gameplay framing.")
	if gaze != null:
		_checks.expect(gaze.get_weight() <= 0.01 and not _q_actor.is_watching(),
			"Q's gaze survived the end of the conversation.")
	for shape in _q_look.look.expression:
		if _q_look.look.blink_shapes.has(shape):
			continue
		_checks.expect(is_equal_approx(float(_q_look.get_composed_face().get(shape, -1.0)),
				float(_q_look.look.expression[shape])),
			"Q's %s did not settle to rest." % shape)

	# Movie Maker mixes on rendered frames, not on the audio thread: stop the room
	# and autoload players, then let the mix run before tearing the tree down.
	var players: Array[Node] = []
	for type: String in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		players.append_array(root.find_children("*", type, true, false))
	if AudioRelease.stop_all(players) > 0:
		await _frames(2)

	var seconds := float(_recorded) / FPS
	_checks.expect(_recorded >= 15.0 * FPS and _recorded <= 30.0 * FPS,
		"The recording is %.1f s of frames, outside the 15-30 s window." % seconds)
	print("FACE_CLOSEUP: %d frames at %.0f fps (%.1f s)" % [_recorded, FPS, seconds])
	for note in _notes:
		print("FACE_CLOSEUP: %s" % note)
	Harness.finish(self, _checks.failures,
		"the close-up recording: insert, states, gaze, retarget, grin and settle.")


## Advances the presentation (picking `choice` when asked) until the runtime sits on
## `node_id`, pacing by rendered frames so the movie is deterministic.
func _arrive(node_id: StringName, choice: StringName, budget: int) -> bool:
	var frames := 0
	while frames < budget:
		if _dialogue.get_runtime().get_current_node_id() == node_id and _dialogue.is_busy():
			return true
		if _dialogue.has_pending_choices():
			if choice.is_empty():
				return false
			var index := _dialogue.get_runtime().get_available_choice_ids().find(choice)
			if index < 0:
				return false
			_dialogue.select_choice(index)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		await _frames(1)
		frames += 1
	return _dialogue.get_runtime().get_current_node_id() == node_id and _dialogue.is_busy()


## The last line read out: advance until nothing is busy and the focus has let go.
func _arrive_end(budget: int) -> bool:
	var frames := 0
	while frames < budget:
		if not _dialogue.is_busy() and _rig.get_focus_weight() == 0.0:
			return true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await _frames(1)
		frames += 1
	return not _dialogue.is_busy()


func _grin_visible() -> bool:
	var head := _q_actor.get_character_animator().get_node("Model") \
		.find_child("Q_Head", true, false) as MeshInstance3D
	if head == null:
		return false
	var smile := head.find_blend_shape_by_name(&"Smile")
	return smile >= 0 and head.get_blend_shape_value(smile) > 0.2


func _face_note(label: String) -> void:
	var gaze := _q_actor.get_gaze()
	_notes.append("%s: q=%s/%.2f protagonist=%s/%.2f glance=%s gaze=%s"
		% [label, String(_q_look.get_face_state()), _q_look.get_face_state_weight(),
			String(_player_look.get_face_state()), _player_look.get_face_state_weight(),
			"yes" if _focus.get_glance() != null else "no",
			"on" if gaze != null and gaze.get_weight() > 0.5 else "off"])


## Up to `count` more rendered frames, stopping early once `condition` holds.
func _wait_frames(count: int, condition: Callable) -> bool:
	for _index in count:
		if bool(condition.call()):
			return true
		await _frames(1)
	return bool(condition.call())


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
		_recorded += 1
