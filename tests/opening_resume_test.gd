extends SceneTree
## The prologue can be resumed from a flag snapshot, not just replayed from the top.
##
## `OpeningSequence` used to keep its position in a coroutine's call stack: a linear
## `_run_opening()` that always started with the wake and always walked every beat.
## That is why the audit filed saving and the director as one problem (#59) — a save
## would have had nothing to restore but flags, and the flags could not tell the
## director where it was.
##
## Now each step names the flag that proves it is done, so "start" and "resume" are
## the same call. This test feeds the director four snapshots and asserts three
## things about each:
##
## 1. **The step it picks** (`next_step()`) is the one the flags say.
## 2. **What it replays.** A resumed game must not play the lines whose beats are
##    already behind it — the specific failure mode of a director that only knows how
##    to start.
## 3. **What it looks like.** A fresh game is asleep: black screen, slumped body,
##    rolled camera, no control. A resumed game is standing up, in control, with the
##    saved objective on screen and nothing left to play.
##
## Time is scaled up so the authored pacing does not dominate CI.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 6.0
const OVERALL_TIMEOUT_SECONDS := 200.0
const CASE_TIMEOUT_SECONDS := 90.0

var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null
var _main: Node = null
var _dialogue: DialogueController = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null
## Every conversation the director started during the current case.
var _played: Array[StringName] = []
var _case_label := ""


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "opening_resume_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Engine.time_scale = TIME_SCALE

	for scenario: Dictionary in _scenarios():
		await _run_scenario(scenario)

	Engine.time_scale = 1.0
	Harness.finish(
		self, _failures,
		"every flag snapshot resumes at the right beat without replaying the ones behind it."
	)


## The snapshots. `run` is false for the fresh game: its steps take the full authored
## pacing and `opening_flow_test` already walks them end to end.
func _scenarios() -> Array:
	return [
		{
			"label": "a game that has not started",
			"flags": [],
			"expect_next": &"wake",
			"run": false,
			"expect_played": [],
			"expect_not_played": [],
		},
		{
			"label": "Q has spoken and the bag has been searched",
			"flags": [StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING],
			"expect_next": &"expectation",
			"run": true,
			"expect_played": [&"expected_b"],
			"expect_not_played": [&"q_wake", &"q_bag_reminder"],
		},
		{
			"label": "the bell has rung",
			"flags": [
				StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING,
				StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG,
			],
			"expect_next": &"substitute",
			"run": true,
			"expect_played": [&"n_class"],
			"expect_not_played": [&"q_wake", &"expected_b", &"bell_moment"],
		},
		{
			"label": "the class has been dismissed",
			"flags": [
				StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING,
				StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG,
				StoryFlags.N_ARRIVED, StoryFlags.CLASS_DISMISSED,
				StoryFlags.LEFT_CLASSROOM,
			],
			"expect_next": &"",
			"run": true,
			"expect_played": [],
			"expect_not_played": [&"q_wake", &"expected_b", &"bell_moment", &"n_class"],
		},
	]


func _run_scenario(scenario: Dictionary) -> void:
	_case_label = String(scenario["label"])
	Harness.stage = "scenario: %s" % _case_label
	_played.clear()
	Harness.clear_session_state(self)

	# The flags go in before the scene exists, because the director reads them in
	# `_ready()` to decide what it is looking at.
	for flag: StringName in scenario["flags"]:
		_game_state.set_flag(flag, true)
	if not (scenario["flags"] as Array).is_empty():
		_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(3)

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_player = _main.get_node_or_null("Player") as PlayerController
	_sequence = sequence_node as OpeningSequence
	if _dialogue == null or _player == null or _sequence == null:
		_failures.append("%s: main did not expose its nodes." % _case_label)
		return
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	_dialogue.conversation_started.connect(_on_conversation_started)

	_expect(
		_sequence.next_step() == scenario["expect_next"],
		"%s: next step is '%s', expected '%s'." % [
			_case_label, _sequence.next_step(), scenario["expect_next"],
		]
	)

	if not bool(scenario["run"]):
		# A game that has not started is asleep: no control, body slumped, camera
		# rolled, screen black.
		_expect(
			not _player.is_control_enabled(),
			"%s: the player has control before the wake happened." % _case_label
		)
		await _free_scene()
		return

	# Everything the wake leaves behind is derived, not remembered.
	_expect(
		_player.is_control_enabled() or _sequence.is_beat_active(),
		"%s: a resumed game is frozen; the wake was skipped and control was not granted."
		% _case_label
	)
	_expect(
		is_zero_approx(_player.visual.rotation_degrees.x),
		"%s: the body is still slumped (%.1f degrees) in a resumed game."
		% [_case_label, _player.visual.rotation_degrees.x]
	)
	_expect(
		_player.camera_rig == null or is_zero_approx(_player.camera_rig.get_roll()),
		"%s: the camera is still rolled in a resumed game." % _case_label
	)

	_sequence.start()
	if not await _run_until_idle(CASE_TIMEOUT_SECONDS):
		await _free_scene()
		return

	_expect(
		String(_sequence.next_step()).is_empty(),
		"%s: the prologue did not finish; '%s' is still pending." % [
			_case_label, _sequence.next_step(),
		]
	)
	_expect(
		_player.is_control_enabled(),
		"%s: control was not returned when the prologue finished." % _case_label
	)
	for conversation: StringName in scenario["expect_played"]:
		_expect(
			_played.has(conversation),
			"%s: '%s' was never played, but the flags say it should happen next."
			% [_case_label, conversation]
		)
	for conversation: StringName in scenario["expect_not_played"]:
		_expect(
			not _played.has(conversation),
			"%s: '%s' was replayed even though its beat is behind this snapshot."
			% [_case_label, conversation]
		)

	# The world has to agree with the flags too: a dismissed class means an open door.
	if _has_flag(StoryFlags.CLASS_DISMISSED):
		var host := _main.get_node_or_null("LocationHost") as LocationHost
		var classroom: LocationRoot = host.get_current() if host != null else null
		var door: Interactable = null
		if classroom != null:
			door = classroom.find_interactable(&"classroom_door")
		_expect(door != null, "%s: the classroom has no door." % _case_label)
		var exit := door as LocationExit
		if exit != null:
			_expect(
				exit.is_open(),
				"%s: the door is still locked although the class was dismissed." % _case_label
			)

	await _free_scene()


## Advances whatever is on screen until the prologue is over and nobody is talking.
func _run_until_idle(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		elif String(_sequence.next_step()).is_empty() and _player.is_control_enabled():
			await _frames(2)
			return true
		await process_frame
	_failures.append("%s: timed out waiting for the prologue to finish." % _case_label)
	return false


func _free_scene() -> void:
	if _dialogue != null and _dialogue.conversation_started.is_connected(_on_conversation_started):
		_dialogue.conversation_started.disconnect(_on_conversation_started)
	if _main != null:
		_main.queue_free()
		_main = null
	await _frames(3)


func _on_conversation_started(conversation_id: StringName) -> void:
	_played.append(conversation_id)


func _has_flag(flag: StringName) -> bool:
	return bool(_game_state.get_flag(flag, false))


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
