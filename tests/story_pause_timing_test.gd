extends SceneTree
## The prologue's clock stops while the game is paused.
##
## The pause menu pauses the tree. Every authored wait in the prologue used
## `SceneTree.create_timer(seconds)`, whose `process_always` argument defaults to
## **true**: the timer keeps counting through a pause. The fades never noticed (they are
## node tweens, which stop with the tree), but the beats did. A player who sat in the
## pause menu or the settings during the bag step came back to a step that had timed out
## behind the menu; the expectation beat needs the bag to have been searched, so it was
## skipped for the rest of the run. A beat whose lead-in ran out under the menu took the
## player lock and opened its conversation while the menu was still up.
##
## What this checks, in the real `main.tscn` with the real director and dialogue:
## 1. `OpeningSequence.wait_seconds()` - the one story-time wait - does not finish while
##    the tree is paused, and does finish once it is not.
## 2. `_wait_for_flag()`, the bag step's fallback clock, does not run out under a pause.
## 3. The expectation beat, started and then paused through its lead-in, neither takes
##    the beat lock nor opens its conversation until the pause ends - and then it does.
## 4. No story script - `res://scripts/world/`, and the room scripts under
##    `res://scenes/locations/` that stage moments of their own - creates a timer that
##    keeps counting through a pause, so the next wait cannot quietly bring the bug back.
##
## Before the fix, checks 2 and 3 fail (the fallback returns and the beat starts while
## paused) and check 1 reports the missing helper.

const Harness = preload("res://tests/test_harness.gd")

## Never written by content or by this test, so a wait on it can only end by timing out.
const FLAG_NOBODY_SETS := &"fixture_story_pause_flag_nobody_sets"
## Long enough that a timer counting through the pause would certainly have fired.
const PAUSE_SECONDS := 1.6
## Short story-time waits, comfortably inside `PAUSE_SECONDS`.
const SHORT_WAIT := 0.4
## The expectation beat's lead-in (0.8 s) plus the gap before its conversation (0.7 s).
const EXPECTATION_PAUSE_SECONDS := 2.4
## How long, after unpausing, a wait is allowed to take to finish.
const RESUME_LIMIT_SECONDS := 4.0
## Where story time is kept. `scenes/locations/` is searched recursively: a room's own
## script stages beats too, and its waits are as visible to a paused player as the
## director's.
const STORY_SCRIPT_DIRS: Array[String] = ["res://scripts/world/", "res://scenes/locations/"]

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _game_state: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "story_pause_timing_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	if _game_state == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	Harness.stage = "the story scripts' timers"
	_check_story_timers()

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(3)

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = sequence_node as OpeningSequence
	if _dialogue == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	# The passive inner voice can open a conversation of its own at any moment, which
	# would make the "nothing started under the pause" assertions a race.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	_sequence.allow_player_control()
	await _frames(2)

	Harness.stage = "the story-time wait under a pause"
	await _check_wait_helper()
	Harness.stage = "the bag step's fallback clock under a pause"
	await _check_flag_wait()
	Harness.stage = "the expectation beat paused through its lead-in"
	await _check_expectation_beat()

	paused = false
	_main.queue_free()
	await _frames(2)
	Harness.clear_session_state(self)
	Harness.stage = ""
	Harness.finish(
		self, _failures,
		"the prologue's waits stop while the game is paused and resume when it is not."
	)


# --- 1. The helper ---------------------------------------------------------------


func _check_wait_helper() -> void:
	# Untyped on purpose: before the fix the method does not exist, and a typed call
	# would stop this whole script from compiling instead of reporting that.
	var director: Variant = _sequence
	if not _sequence.has_method("wait_seconds"):
		_failures.append("OpeningSequence has no story-time wait (wait_seconds).")
		return
	var done := [false]
	var waiter := func() -> void:
		await director.wait_seconds(SHORT_WAIT)
		done[0] = true
	paused = true
	waiter.call()
	await _real_seconds(PAUSE_SECONDS)
	_expect(
		not bool(done[0]),
		"wait_seconds(%.1f) finished during a %.1f s pause." % [SHORT_WAIT, PAUSE_SECONDS]
	)
	paused = false
	_expect(
		await _until(func() -> bool: return bool(done[0]), RESUME_LIMIT_SECONDS),
		"wait_seconds(%.1f) did not finish within %.1f s of the pause ending."
		% [SHORT_WAIT, RESUME_LIMIT_SECONDS]
	)


# --- 2. The bag step's fallback -------------------------------------------------


func _check_flag_wait() -> void:
	var director: Variant = _sequence
	var done := [false]
	var waiter := func() -> void:
		await director._wait_for_flag(FLAG_NOBODY_SETS, SHORT_WAIT)
		done[0] = true
	paused = true
	waiter.call()
	await _real_seconds(PAUSE_SECONDS)
	_expect(
		not bool(done[0]),
		"The bag step's %.1f s fallback ran out during a %.1f s pause: a player in the "
		% [SHORT_WAIT, PAUSE_SECONDS]
		+ "pause menu loses the bag step and the expectation beat with it."
	)
	paused = false
	_expect(
		await _until(func() -> bool: return bool(done[0]), RESUME_LIMIT_SECONDS),
		"The bag step's fallback did not run out after the pause ended."
	)


# --- 3. A real beat --------------------------------------------------------------


func _check_expectation_beat() -> void:
	_game_state.set_flag(StoryFlags.TEXTBOOK_MISSING, true)
	_game_state.set_flag(StoryFlags.EXPECTATION_PLAYED, false)
	_expect(not _sequence.is_beat_active(), "A beat was already active before the check.")
	_expect(not _dialogue.is_busy(), "A conversation was already open before the check.")

	var director: Variant = _sequence
	paused = true
	# Fire and forget, the way `_run_opening()` would be left running behind the menu.
	director._beat_expectation()
	await _real_seconds(EXPECTATION_PAUSE_SECONDS)
	_expect(
		not _sequence.is_beat_active(),
		"The expectation beat took the lock while the game was paused."
	)
	_expect(
		not _dialogue.is_busy(),
		"The expectation conversation opened while the game was paused."
	)

	paused = false
	_expect(
		await _until(
			func() -> bool: return _sequence.is_beat_active() or _dialogue.is_busy(),
			RESUME_LIMIT_SECONDS
		),
		"The expectation beat never started after the pause ended."
	)


# --- 4. The source rule ----------------------------------------------------------


## A timer in a story script is story time. One created with the default
## `process_always = true` counts through the pause menu, which is the bug above.
func _check_story_timers() -> void:
	var single_argument := RegEx.create_from_string("create_timer\\(([^,()]*)\\)")
	var always := RegEx.create_from_string("create_timer\\([^,()]*,\\s*true")
	var scripts: Array[String] = []
	for dir_path in STORY_SCRIPT_DIRS:
		_collect_scripts(dir_path, dir_path != STORY_SCRIPT_DIRS[0], scripts)
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			var line := lines[index]
			if line.strip_edges().begins_with("#"):
				continue
			if single_argument.search(line) != null or always.search(line) != null:
				_failures.append(
					"%s:%d creates a timer that keeps counting while the game is paused: %s"
					% [path, index + 1, line.strip_edges()]
				)
	_expect(
		scripts.has("res://scripts/world/opening_sequence.gd"),
		"The scan did not reach opening_sequence.gd; it would pass without looking."
	)


func _collect_scripts(dir_path: String, recursive: bool, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_failures.append("Could not open %s." % dir_path)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			into.append(dir_path.path_join(file_name))
	if recursive:
		for sub in dir.get_directories():
			_collect_scripts(dir_path.path_join(sub), true, into)


# --- Helpers ---------------------------------------------------------------------


## Waits real time. `process_frame` is emitted while the tree is paused, so this keeps
## going under a pause - which is the point: it measures how long the pause lasted.
func _real_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## Polls `condition` every frame for up to `seconds` of real time.
func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await process_frame
	return bool(condition.call())


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
