extends SceneTree
## Issue #171: the biology teacher B is heard about from Q before anything presents her.
##
## B has no actor in this slice; what presents her is the imagined `expected_b` scene, in
## which she is the speaker. The owner saw it before Q's first conversation had told the
## player about the lesson. `BPresence` now keeps everything that presents B behind
## `q_first_talk_done`, and an actor of hers (should a room ever hold one) behind an explicit
## entrance as well. This test checks, on the real main scene:
##
## 1. **The real new-game order.** Wake, Q's approach and `q_wake` run as authored; the bag
##    is tried throughout. No line spoken by `b` and no `expected_b` may start before
##    `q_wake` has finished; `q_first_talk_done` is `false` from Q's first line until then.
## 2. **No Q talk, no B.** A searched bag without Q's finished conversation - the approach
##    could not run, or the run stopped mid-talk and was resumed - passes the scene over
##    (`expectation_skipped`) instead of playing it ahead of Q. An older save that only has
##    `met_q` (written at a checkpoint, so after the talk) keeps playing it, and is not
##    rewritten for it.
## 3. **Repeat talks.** A Q talk started by the player instead of the beat also counts; the
##    repeat reply changes nothing and presents no B.
## 4. **An actor of hers is scheduled, not automatic.** A classroom that holds a `b` actor
##    keeps it hidden and not processing on entry, after Q's talk too, until the explicit
##    trigger (`present_b()`), which is refused before the talk. After it she is shown; a
##    re-entered room shows the one B again, and a snapshot without her entrance hides her.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const NPC_ACTOR := "res://scenes/actors/npc/npc_actor.tscn"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
## The classroom with a B actor added, written by this test (never shipped).
const ROOM_WITH_B := "user://b_reveal_classroom_with_b.tscn"
const TIME_SCALE := 6.0
const OPENING_REAL_SECONDS := 150.0

var _failures: Array[String] = []
var _state: Node = null
var _narrative: Node = null
var _world: Node = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _host: LocationHost = null
var _started: Array[StringName] = []
var _finished: Array[StringName] = []
var _talk_done_at_first_line: Variant = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 330.0, "b_reveal_timing_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	await _check_real_opening_order()
	await _check_gate_snapshots()
	await _check_player_started_talk()
	await _check_actor_schedule()
	Engine.time_scale = 1.0
	await _release()
	Harness.clear_session_state(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOM_WITH_B))
	Harness.finish(
		self, _failures,
		"B is presented only after Q's first conversation has ended: the real opening plays "
		+ "q_wake before any line of B's, a missing or unfinished Q talk skips the imagined "
		+ "scene, older saves keep it, and a room's B stays hidden until her explicit entrance, "
		+ "across repeat talks, reloads and re-entering the room."
	)


# --- 1. The real opening ----------------------------------------------------


func _check_real_opening_order() -> void:
	Harness.stage = "the real new-game opening"
	await _boot(true, {})
	if _world == null:
		return
	Engine.time_scale = TIME_SCALE
	var bag := _host.get_current().find_interactable(&"schoolbag")
	_expect(bag != null, "The classroom has no schoolbag.")
	var until := Time.get_ticks_msec() + int(OPENING_REAL_SECONDS * 1000.0)
	var frame := 0
	while not _flag(StoryFlags.EXPECTATION_PLAYED) and not _flag(StoryFlags.EXPECTATION_SKIPPED):
		if Time.get_ticks_msec() > until:
			_expect(false, "The opening did not reach the expectation beat in time (started %s)."
				% str(_started))
			break
		frame += 1
		if not _finished.has(&"q_wake"):
			_expect(not _flag(StoryFlags.Q_FIRST_TALK_DONE),
				"q_first_talk_done was true before q_wake had finished.")
		# The player tries the bag all along: before Q, during Q, after Q.
		if bag != null and frame % 7 == 0 and not _dialogue.is_busy() \
				and not _flag(StoryFlags.TEXTBOOK_MISSING):
			_interaction.request_activation(bag)
		if _dialogue.is_busy():
			_advance()
		await process_frame
	Engine.time_scale = 1.0
	_expect(typeof(_talk_done_at_first_line) == TYPE_BOOL and not bool(_talk_done_at_first_line),
		"Q's first line did not record the talk as begun-but-unfinished (got %s)."
		% str(_talk_done_at_first_line))
	var q_at := _started.find(&"q_wake")
	var b_at := _started.find(&"expected_b")
	_expect(q_at >= 0, "Q's first conversation never played in the real opening.")
	_expect(b_at >= 0, "The imagined scene with B never played after Q's conversation and the bag.")
	_expect(q_at < 0 or b_at < 0 or q_at < b_at,
		"expected_b started before q_wake: %s." % str(_started))
	_expect(_flag(StoryFlags.Q_FIRST_TALK_DONE), "Q's finished conversation was not recorded.")
	_expect(not _flag(StoryFlags.B_ON_STAGE), "Something put B on stage during the opening.")
	await _release()


# --- 2. Snapshots: no talk, an unfinished talk, an older save ---------------


func _check_gate_snapshots() -> void:
	Harness.stage = "the expectation gate: Q never talked"
	await _boot(false, {StoryFlags.TEXTBOOK_MISSING: true})
	if _world != null:
		_expect(not _sequence.is_b_introduced(), "A run where Q never talked counts B as introduced.")
		await _sequence._beat_expectation()
		await _frames(2)
		_expect(not _started.has(&"expected_b"),
			"expected_b played although Q's first conversation never happened.")
		_expect(_flag(StoryFlags.EXPECTATION_SKIPPED),
			"The ungated expectation step was not closed as skipped.")
		await _release()

	Harness.stage = "the expectation gate: a resumed, unfinished Q talk"
	await _boot(false, {
		StoryFlags.MET_Q: true, StoryFlags.Q_FIRST_TALK_DONE: false,
		StoryFlags.TEXTBOOK_MISSING: true,
	})
	if _world != null:
		_expect(not _sequence.is_b_introduced(),
			"An unfinished Q talk was taken for a finished one after a reload.")
		_expect(_sequence.next_step() == &"expectation",
			"The unfinished-talk snapshot resumes at '%s'." % _sequence.next_step())
		await _sequence._beat_expectation()
		await _frames(2)
		_expect(not _started.has(&"expected_b"), "expected_b played after an unfinished Q talk.")
		_expect(_flag(StoryFlags.EXPECTATION_SKIPPED),
			"The expectation step stayed open after an unfinished Q talk.")
		await _release()

	Harness.stage = "the expectation gate: an older save"
	await _boot(false, {StoryFlags.MET_Q: true, StoryFlags.TEXTBOOK_MISSING: true})
	if _world != null:
		_expect(_sequence.is_b_introduced(),
			"An older save's met_q (always written after Q's talk) does not count as the talk.")
		_expect(not _state.has_flag(StoryFlags.Q_FIRST_TALK_DONE),
			"Reading an older save wrote a flag into it.")
		_expect(not _sequence.is_b_on_stage(), "Adopting an older save put B on stage.")
		await _release()


# --- 3. A talk the player starts --------------------------------------------


func _check_player_started_talk() -> void:
	Harness.stage = "a Q talk started by the player"
	await _boot(false, {})
	if _world == null:
		return
	_sequence.allow_player_control()
	var talk := _host.get_current().find_interactable(&"q_talk")
	_expect(talk != null, "The classroom has no q_talk anchor.")
	if talk == null:
		return
	_interaction.request_activation(talk)
	await _frames(2)
	_expect(_started.has(&"q_wake"), "Talking to Q first did not start Q's introduction.")
	await _finish_dialogue()
	_expect(_flag(StoryFlags.Q_FIRST_TALK_DONE),
		"A Q introduction the player started did not count as Q's first talk.")
	_started.clear()
	_interaction.request_activation(talk)
	await _frames(2)
	await _finish_dialogue()
	_expect(_started == [&"q_studying"], "The repeat talk with Q played %s." % str(_started))
	_expect(_flag(StoryFlags.Q_FIRST_TALK_DONE) and not _flag(StoryFlags.B_ON_STAGE),
		"A repeat talk changed B's reveal state.")
	await _release()


# --- 4. An actor of hers ----------------------------------------------------


func _check_actor_schedule() -> void:
	Harness.stage = "a room with a B actor"
	if not _write_room_with_b():
		return
	await _boot(false, {})
	if _world == null:
		return
	var spawn := _host.get_current_spawn()
	_expect(_enter_room_with_b(spawn), "The classroom with a B actor could not be entered.")
	var actor := _b_actor()
	_expect(actor != null, "The fixture room lost its B actor.")
	if actor == null:
		return
	_expect_hidden(actor, "on entering the room before Q has talked")
	var refused := _sequence.present_b(Vector3(1.8, 0.0, -3.0), Vector3(1.8, 0.0, 0.0))
	_expect(not refused and not _flag(StoryFlags.B_ON_STAGE),
		"present_b() let B in before Q's first conversation.")
	_expect_hidden(actor, "after a refused entrance")

	# Q's talk is over: B is now *known*, not *present*.
	_state.set_flag(StoryFlags.MET_Q, true)
	_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)
	await _frames(2)
	_expect_hidden(actor, "right after Q's first conversation")
	_expect(_enter_room_with_b(spawn), "Re-entering the room with a B actor failed.")
	actor = _b_actor()
	if actor != null:
		_expect_hidden(actor, "on re-entering after Q's talk, before her entrance")

	# The explicit trigger.
	_expect(_sequence.present_b(Vector3(1.8, 0.0, -3.0), Vector3(1.8, 0.0, 0.0)),
		"present_b() was refused after Q's first conversation.")
	await _frames(2)
	if actor != null:
		_expect(actor.visible and actor.is_visible_in_tree(),
			"B is not visible after her explicit entrance.")
		_expect(actor.process_mode != Node.PROCESS_MODE_DISABLED,
			"B is still disabled after her explicit entrance.")
		_expect(actor.global_position.distance_to(Vector3(1.8, 0.0, -3.0)) < 0.05,
			"present_b() did not place B where it was asked.")
	_expect(_sequence.present_b(Vector3(1.6, 0.0, -3.0)), "A second present_b() was refused.")
	_expect(_count_b_actors() == 1, "A second entrance made %d B actors." % _count_b_actors())

	# Reload-shaped changes: re-entering keeps her; a snapshot without her entrance does not.
	_expect(_enter_room_with_b(spawn), "Re-entering the room after B's entrance failed.")
	actor = _b_actor()
	_expect(actor != null and actor.visible and _count_b_actors() == 1,
		"Re-entering the room did not show exactly one B after her entrance.")
	_state.replace_snapshot({StoryFlags.MET_Q: true})
	await _frames(1)
	if actor != null:
		_expect(_sequence.is_b_introduced() and not _sequence.is_b_on_stage(),
			"An older snapshot without B's entrance reads as on stage.")
		_expect_hidden(actor, "after loading a snapshot without her entrance")
	_state.clear()
	await _frames(1)
	if actor != null:
		_expect_hidden(actor, "after a new game cleared the flags")
	await _release()


func _write_room_with_b() -> bool:
	var room := (load(CLASSROOM) as PackedScene).instantiate()
	var actors := room.get_node_or_null(^"Actors")
	var b := (load(NPC_ACTOR) as PackedScene).instantiate() as NpcActor
	if actors == null or b == null:
		_expect(false, "The B fixture could not be assembled.")
		room.free()
		return false
	b.name = "B"
	b.npc_id = &"b"
	b.debug_name = "B"
	b.position = Vector3(1.8, 0.0, -3.6)
	# Visible as authored: the schedule, not the scene, is what has to hide her.
	b.visible = true
	actors.add_child(b)
	b.owner = room
	var packed := PackedScene.new()
	var packed_ok := packed.pack(room) == OK
	room.free()
	if not packed_ok or ResourceSaver.save(packed, ROOM_WITH_B) != OK:
		_expect(false, "The B fixture room could not be written to %s." % ROOM_WITH_B)
		return false
	return true


func _enter_room_with_b(spawn: StringName) -> bool:
	return _host.load_location(ROOM_WITH_B, spawn, _player, &"classroom")


func _b_actor() -> NpcActor:
	var room := _host.get_current()
	return room.find_actor(&"b") if room != null else null


func _count_b_actors() -> int:
	var room := _host.get_current()
	var count := 0
	if room == null:
		return 0
	for node in room.find_children("*", "", true, false):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == &"b":
			count += 1
	return count


func _expect_hidden(actor: NpcActor, when: String) -> void:
	_expect(not actor.visible and not actor.is_visible_in_tree(), "B is visible %s." % when)
	_expect(actor.process_mode == Node.PROCESS_MODE_DISABLED, "B is processing %s." % when)


# --- Plumbing ---------------------------------------------------------------


func _boot(autostart: bool, flags: Dictionary) -> void:
	await _release()
	Harness.clear_session_state(self)
	for flag: StringName in flags:
		_state.set_flag(flag, flags[flag])
	_started.clear()
	_finished.clear()
	_talk_done_at_first_line = null
	_world = (load(MAIN) as PackedScene).instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = autostart
	_sequence.autosave_enabled = false
	root.add_child(_world)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_player = _world.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_host = _world.get_node(^"LocationHost") as LocationHost
	var voices := _world.get_node_or_null(^"InnerVoiceDirector")
	if voices != null:
		voices.set_process(false)
	_dialogue.conversation_started.connect(_on_started)
	_dialogue.conversation_finished.connect(func(id: StringName) -> void: _finished.append(id))
	_dialogue.line_presented.connect(_on_line)
	_state.story_flag_changed.connect(_on_flag)
	if not autostart:
		(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	await _frames(3)
	if _host.get_current() == null:
		_expect(false, "%s: main did not enter the classroom." % Harness.stage)
		await _release()


func _release() -> void:
	if _state != null and _state.story_flag_changed.is_connected(_on_flag):
		_state.story_flag_changed.disconnect(_on_flag)
	if is_instance_valid(_world):
		_world.queue_free()
		await _frames(3)
	_world = null
	_sequence = null


func _on_started(conversation_id: StringName) -> void:
	_started.append(conversation_id)
	if conversation_id == &"expected_b" and not _finished.has(&"q_wake") \
			and not _flag(StoryFlags.Q_FIRST_TALK_DONE):
		_expect(false, "%s: expected_b started before Q's first conversation ended."
			% Harness.stage)


func _on_line(line: Dictionary) -> void:
	if StringName(line.get("speaker_id", &"")) == &"b" and not _flag(StoryFlags.Q_FIRST_TALK_DONE):
		_expect(false, "%s: B spoke ('%s') before Q's first conversation ended."
			% [Harness.stage, String(line.get("node_id", ""))])


func _on_flag(flag: StringName, _previous: Variant, value: Variant) -> void:
	# BPresence is connected first (in the director's `_ready`), so by now it has answered.
	if flag == StoryFlags.MET_Q and bool(value) and _talk_done_at_first_line == null:
		_talk_done_at_first_line = _state.get_flag(StoryFlags.Q_FIRST_TALK_DONE, null)


func _advance() -> void:
	if _dialogue.has_pending_choices():
		_dialogue.select_choice(0)
	else:
		_dialogue.advance_presentation()


func _finish_dialogue() -> void:
	var until := Time.get_ticks_msec() + 30000
	while (_dialogue.is_busy() or _sequence.is_beat_active()) and Time.get_ticks_msec() < until:
		if _dialogue.is_busy():
			_advance()
		await process_frame
	_expect(not _dialogue.is_busy(), "%s: a conversation did not finish." % Harness.stage)


func _flag(flag: StringName) -> bool:
	return _state != null and bool(_state.get_flag(flag, false))


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
