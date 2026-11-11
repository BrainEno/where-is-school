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
##
## The second half covers the way into and out of a run (issues #95 and #62):
##
## 4. **The title screen** offers Continue / New game / Settings / Quit with a readable
##    save, Start / Settings / Quit without one, and names an unreadable save instead of
##    offering to continue it.
## 5. **Cancelling a new game keeps everything**: the file, the flags, the knowledge.
## 6. **Confirming one clears everything** - from the title, from the pause menu - in the
##    order `game_session.gd` documents, and the next boot proves it: no old flag, no old
##    knowledge entry, no old room, no old dice seed, and the prologue starts at the wake.
##    An unreadable save's quarantined copy survives; the old world cannot write it back.
## 7. **Settings survive a restart** without touching `[display] locale`, and a damaged
##    controls section falls back to the defaults instead of leaving actions unbound.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 6.0
const OVERALL_TIMEOUT_SECONDS := 200.0
const CASE_TIMEOUT_SECONDS := 90.0
const MAIN_SCENE := "res://scenes/main/main.tscn"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const SETTINGS_PATH := "user://settings.cfg"
const OLD_SEED := 424242
const OLD_ENTRY := &"new_game_probe_entry"

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
	var session := Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if session == null or settings == null:
		_failures.append("The Session / Settings autoloads could not be created.")
	else:
		await _check_title_menu()
		await _check_cancel_keeps_save()
		await _check_new_game_from_title()
		await _check_new_game_from_pause()
		await _check_broken_save_new_game()
		await _check_settings_persist(settings)
	Harness.clear_session_state(self)
	Harness.finish(
		self, _failures,
		"every flag snapshot resumes at the right beat without replaying the ones behind it; "
		+ "the title offers Continue / New game / Settings by save state, a cancelled new game "
		+ "keeps the save, a confirmed one leaves no flag, entry, room or seed for the next "
		+ "boot, and settings survive a restart."
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


# --- The way in and out of a run -------------------------------------------------


## A world with a real autosave behind it: flags, a knowledge entry, a fixed dice seed,
## written through the same `Save.save_game()` the director uses. Returns the world,
## still running and bound to the save, or null.
func _make_saved_world() -> Node:
	Harness.clear_session_state(self)
	for flag: StringName in [StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING]:
		_game_state.set_flag(flag, true)
	_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")
	_narrative.record(OLD_ENTRY, NarrativeEntry.Source.OBSERVED, &"", "A probe the new game must forget.")
	var packed: PackedScene = load(MAIN_SCENE)
	var world := packed.instantiate()
	var sequence_node := world.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(world)
	await _frames(3)
	var dialogue := world.get_node_or_null("DialogueController") as DialogueController
	if dialogue != null:
		dialogue.set_session_seed(OLD_SEED)
	var save := root.get_node_or_null(^"Save")
	var result: Dictionary = save.save_game() if save != null else {}
	_expect(result.get("ok", false) == true, "%s: the probe save was not written: %s" % [
		_case_label, str(result)
	])
	return world


## Goes to the title screen the way the game does, as the current scene.
func _open_title() -> TitleScreen:
	change_scene_to_file(TITLE_SCENE)
	for _index in 30:
		await process_frame
		if current_scene is TitleScreen:
			break
	await _frames(2)
	var title := current_scene as TitleScreen
	_expect(title != null, "%s: the title screen did not become the current scene." % _case_label)
	return title


func _entry_list(title: TitleScreen) -> String:
	var names := PackedStringArray()
	for id: StringName in title.get_entry_ids():
		names.append(String(id))
	return ",".join(names)


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _press_pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _check_title_menu() -> void:
	_case_label = "title menu"
	Harness.stage = _case_label
	Harness.clear_session_state(self)
	var title := await _open_title()
	if title == null:
		return
	_expect(title.get_save_state() == &"none", "%s: no save reads as '%s'." % [
		_case_label, title.get_save_state()
	])
	_expect(_entry_list(title) == "new_game,settings,quit", "%s: without a save the list is %s." % [
		_case_label, _entry_list(title)
	])
	var start := title.get_entry(&"new_game")
	_expect(
		start != null and start.text == L10n.t("menu.start"),
		"%s: the first entry without a save is not 'Start'." % _case_label
	)
	_expect(_focused() == start, "%s: the first entry does not have the focus." % _case_label)
	# Keyboard and controller move through the same list.
	await _press_key(KEY_DOWN)
	_expect(_focused() == title.get_entry(&"settings"), "%s: Down did not reach Settings." % _case_label)
	await _press_pad(JOY_BUTTON_DPAD_DOWN)
	_expect(_focused() == title.get_entry(&"quit"), "%s: D-pad down did not reach Quit." % _case_label)
	await _press_pad(JOY_BUTTON_DPAD_UP)
	# Settings opens from the title, takes the focus, and B closes it again.
	await _press_pad(JOY_BUTTON_A)
	await _frames(2)
	var panel := title.get_settings_panel()
	_expect(panel.is_open(), "%s: A on Settings did not open the settings screen." % _case_label)
	var focused := _focused()
	_expect(
		focused != null and panel.is_ancestor_of(focused),
		"%s: the settings screen opened without a focused row." % _case_label
	)
	await _press_pad(JOY_BUTTON_B)
	await _frames(2)
	_expect(not panel.is_open(), "%s: B did not close the settings screen." % _case_label)
	_expect(_focused() == title.get_entry(&"settings"), "%s: closing settings lost the focus." % _case_label)

	# A readable save: Continue comes first.
	var world := await _make_saved_world()
	if world != null:
		world.queue_free()
		await _frames(3)
	title.refresh_save_state()
	await _frames(1)
	_expect(title.get_save_state() == &"valid", "%s: a written save reads as '%s'." % [
		_case_label, title.get_save_state()
	])
	_expect(
		_entry_list(title) == "continue,new_game,settings,quit",
		"%s: with a save the list is %s." % [_case_label, _entry_list(title)]
	)
	_expect(_focused() == title.get_entry(&"continue"), "%s: Continue is not focused first." % _case_label)
	_expect(title.get_notice_text().is_empty(), "%s: a readable save shows a warning." % _case_label)


## Cancel, by key and by button, at the title: nothing is deleted.
func _check_cancel_keeps_save() -> void:
	_case_label = "cancel keeps the save"
	Harness.stage = _case_label
	var title := current_scene as TitleScreen
	var save := root.get_node_or_null(^"Save")
	if title == null or save == null:
		_failures.append("%s: no title screen to test on." % _case_label)
		return
	var flags_before: Dictionary = _game_state.get_snapshot().duplicate(true)
	for how: String in ["Esc", "B", "Cancel button"]:
		title.activate(&"new_game")
		await _frames(2)
		var confirm := title.get_confirm()
		_expect(confirm.visible, "%s (%s): New game did not ask first." % [_case_label, how])
		_expect(
			_focused() == confirm.get_cancel_button(),
			"%s (%s): the question opened on the destructive answer." % [_case_label, how]
		)
		match how:
			"Esc":
				await _press_key(KEY_ESCAPE)
			"B":
				await _press_pad(JOY_BUTTON_B)
			_:
				await _press_pad(JOY_BUTTON_A)
		await _frames(2)
		_expect(not confirm.visible, "%s (%s): the question did not close." % [_case_label, how])
		_expect(save.has_save(), "%s (%s): cancelling deleted the save." % [_case_label, how])
		_expect(
			bool((save.read_save() as Dictionary).get("ok", false)),
			"%s (%s): cancelling damaged the save." % [_case_label, how]
		)
		_expect(
			_game_state.get_snapshot() == flags_before,
			"%s (%s): cancelling changed the story flags." % [_case_label, how]
		)
		_expect(_narrative.has_entry(OLD_ENTRY), "%s (%s): cancelling lost knowledge." % [_case_label, how])
		_expect(
			current_scene == title and not title.is_queued_for_deletion(),
			"%s (%s): cancelling left the title screen." % [_case_label, how]
		)


## Confirm at the title, with the controller: the next boot is a new game.
func _check_new_game_from_title() -> void:
	_case_label = "new game from the title"
	Harness.stage = _case_label
	var title := current_scene as TitleScreen
	var session := root.get_node_or_null(^"Session")
	if title == null or session == null:
		_failures.append("%s: no title screen to test on." % _case_label)
		return
	var reports: Array = []
	var on_started := func(report: Dictionary) -> void: reports.append(report)
	session.connect("new_game_started", on_started)
	title.activate(&"new_game")
	await _frames(2)
	await _press_pad(JOY_BUTTON_DPAD_RIGHT)
	_expect(
		_focused() == title.get_confirm().get_confirm_button(),
		"%s: D-pad right did not reach the confirm answer." % _case_label
	)
	await _press_pad(JOY_BUTTON_A)
	var world := await _wait_for_world(reports)
	session.disconnect("new_game_started", on_started)
	await _expect_fresh_boot(world, reports)
	await _free_current_scene()


func _check_new_game_from_pause() -> void:
	_case_label = "new game from the pause menu"
	Harness.stage = _case_label
	var world := await _make_saved_world()
	var session := root.get_node_or_null(^"Session")
	if world == null or session == null:
		return
	var menu := world.get_node_or_null("PauseMenu") as PauseMenu
	_expect(menu != null, "%s: main.tscn has no pause menu." % _case_label)
	if menu == null:
		world.queue_free()
		return
	await _press_pad(JOY_BUTTON_START)
	await _frames(2)
	_expect(menu.is_open(), "%s: Start did not open the pause menu." % _case_label)
	_expect(paused, "%s: the world kept running under the pause menu." % _case_label)
	_expect(_focused() == menu.get_entry(&"resume"), "%s: Resume is not focused first." % _case_label)
	# Esc closes it again, and play resumes.
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not menu.is_open() and not paused, "%s: Esc did not resume." % _case_label)
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_expect(menu.is_open(), "%s: Esc did not open the pause menu." % _case_label)
	menu.focus_entry(&"new_game")
	await _press_key(KEY_ENTER)
	await _frames(2)
	_expect(menu.get_confirm().visible, "%s: New game did not ask first." % _case_label)
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	var save := root.get_node_or_null(^"Save")
	_expect(save.has_save(), "%s: cancelling in the pause menu deleted the save." % _case_label)
	_expect(menu.is_open(), "%s: cancelling closed the whole menu." % _case_label)

	var reports: Array = []
	var on_started := func(report: Dictionary) -> void: reports.append(report)
	session.connect("new_game_started", on_started)
	menu.activate(&"new_game")
	await _frames(2)
	menu.get_confirm().get_confirm_button().pressed.emit()
	var fresh := await _wait_for_world(reports)
	session.disconnect("new_game_started", on_started)
	_expect(not is_instance_valid(world), "%s: the old world was not freed." % _case_label)
	_expect(not paused, "%s: the new game started paused." % _case_label)
	await _expect_fresh_boot(fresh, reports)
	await _free_current_scene()


## An unreadable save: the title says so, offers no Continue, and a confirmed new game
## removes the file but keeps the quarantined copy.
func _check_broken_save_new_game() -> void:
	_case_label = "new game over an unreadable save"
	Harness.stage = _case_label
	Harness.clear_session_state(self)
	var file := FileAccess.open("user://save.json", FileAccess.WRITE)
	file.store_string("{ this is not a save")
	file.close()
	var title := await _open_title()
	if title == null:
		return
	_expect(title.get_save_state() == &"broken", "%s: it reads as '%s'." % [
		_case_label, title.get_save_state()
	])
	_expect(not title.get_entry_ids().has(&"continue"), "%s: Continue is offered." % _case_label)
	_expect(not title.get_notice_text().is_empty(), "%s: the problem is not shown." % _case_label)
	_expect(
		FileAccess.file_exists("user://save.broken.json"),
		"%s: reading it did not set a copy aside." % _case_label
	)
	var session := root.get_node_or_null(^"Session")
	var reports: Array = []
	var on_started := func(report: Dictionary) -> void: reports.append(report)
	session.connect("new_game_started", on_started)
	title.activate(&"new_game")
	await _frames(2)
	_expect(
		title.get_confirm().visible,
		"%s: a new game over an unreadable save did not ask first." % _case_label
	)
	title.get_confirm().get_confirm_button().pressed.emit()
	var world := await _wait_for_world(reports)
	session.disconnect("new_game_started", on_started)
	if not reports.is_empty():
		var report: Dictionary = reports[0]
		_expect(bool(report.get("kept_quarantine", false)), "%s: the copy was not kept." % _case_label)
	_expect(
		FileAccess.file_exists("user://save.broken.json"),
		"%s: the quarantined copy was deleted." % _case_label
	)
	_expect(not FileAccess.file_exists("user://save.json"), "%s: the bad save is still the save." % _case_label)
	await _free_current_scene()
	DirAccess.remove_absolute("user://save.broken.json")


## Waits for the session's report and for the fresh world to become the current scene.
func _wait_for_world(reports: Array) -> Node:
	for _index in 240:
		await process_frame
		if not reports.is_empty() and current_scene != null \
				and current_scene.get_node_or_null("OpeningSequence") != null:
			break
	await _frames(3)
	_expect(not reports.is_empty(), "%s: the session never reported a new game." % _case_label)
	var world := current_scene
	_expect(
		world != null and world.get_node_or_null("OpeningSequence") != null,
		"%s: the game did not enter the opening after the new game." % _case_label
	)
	return world


## The proof that nothing came back: the report, the file, and the booted world.
func _expect_fresh_boot(world: Node, reports: Array) -> void:
	if not reports.is_empty():
		var report: Dictionary = reports[0]
		_expect(bool(report.get("ok", false)), "%s: the report is not ok: %s" % [_case_label, str(report)])
		var steps := ",".join(report.get("steps", PackedStringArray()))
		_expect(
			steps == "autosave_off,world_freed,save_deleted,state_cleared,verified",
			"%s: the steps ran as %s." % [_case_label, steps]
		)
	if world == null:
		return
	var sequence := world.get_node_or_null("OpeningSequence") as OpeningSequence
	var dialogue := world.get_node_or_null("DialogueController") as DialogueController
	_expect(
		not _has_flag(StoryFlags.MET_Q) and not _has_flag(StoryFlags.TEXTBOOK_MISSING),
		"%s: old story flags came back on the next boot." % _case_label
	)
	_expect(
		String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.check_bag",
		"%s: the old objective came back on the next boot." % _case_label
	)
	_expect(not _narrative.has_entry(OLD_ENTRY), "%s: old knowledge came back." % _case_label)
	_expect(
		dialogue == null or dialogue.get_session_seed() != OLD_SEED,
		"%s: the old dice seed came back." % _case_label
	)
	_expect(
		sequence != null and sequence.next_step() == &"wake",
		"%s: the next boot did not start at the wake (next step '%s')." % [
			_case_label, sequence.next_step() if sequence != null else &"?"
		]
	)
	var location := String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "classroom"))
	_expect(location == "classroom", "%s: the next boot is in '%s'." % [_case_label, location])


func _free_current_scene() -> void:
	var scene := current_scene
	if scene != null:
		var sequence := scene.get_node_or_null("OpeningSequence")
		if sequence != null:
			sequence.set("autosave_enabled", false)
		scene.queue_free()
	await _frames(3)
	var save := root.get_node_or_null(^"Save")
	if save != null:
		save.unbind_world()
	Harness.clear_session_state(self)


## Preferences written by one Settings node are read back by the next one, the
## language key `Loc` owns survives every write, and damaged controls fall back.
func _check_settings_persist(settings: Node) -> void:
	_case_label = "settings persistence"
	Harness.stage = _case_label
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var original_locale: Variant = config.get_value("display", "locale", null)
	config.set_value("display", "locale", "zh-CN")
	config.save(SETTINGS_PATH)

	settings.call("set_text_size", &"largest")
	settings.call("set_text_speed", &"instant")
	settings.call("set_volume", &"music", 35)
	settings.call("set_volume", &"sfx", 0)
	settings.call("set_ui_scale", &"150")
	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_J
	var rebound: Dictionary = settings.call("rebind", &"interact", jump)
	_expect(bool(rebound.get("ok", false)), "%s: rebinding interact to J was refused." % _case_label)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	settings.call("rebind", &"interact", pad)
	var clash := InputEventKey.new()
	clash.physical_keycode = KEY_TAB
	var refused: Dictionary = settings.call("rebind", &"interact", clash)
	_expect(
		String(refused.get("reason", "")) == "conflict",
		"%s: binding interact to the log's key was not refused as a conflict." % _case_label
	)

	# Volumes have a real effect on the buses.
	var music_bus := AudioServer.get_bus_index(&"Music")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_expect(sfx_bus != -1, "%s: there is no SFX bus." % _case_label)
	if music_bus != -1:
		_expect(
			AudioServer.get_bus_volume_db(music_bus) < -6.0 - 8.0,
			"%s: the music dial at 35%% left the bus at %.1f dB." % [
				_case_label, AudioServer.get_bus_volume_db(music_bus)
			]
		)
	if sfx_bus != -1:
		_expect(AudioServer.is_bus_mute(sfx_bus), "%s: the SFX dial at 0 did not mute." % _case_label)

	# A second node is the next run.
	var script: Script = load(SETTINGS_SCRIPT)
	var next_run: Node = script.new()
	next_run.name = "SettingsNextRun"
	root.add_child(next_run)
	await _frames(1)
	_expect(next_run.call("get_text_size") == &"largest", "%s: text size was not kept." % _case_label)
	_expect(next_run.call("get_text_speed") == &"instant", "%s: text speed was not kept." % _case_label)
	_expect(int(next_run.call("get_volume", &"music")) == 35, "%s: music volume was not kept." % _case_label)
	_expect(next_run.call("get_ui_scale") == &"150", "%s: interface scale was not kept." % _case_label)
	var key_label := String(next_run.call("binding_label", &"interact", &"keyboard"))
	_expect(key_label == "J", "%s: the interact key came back as '%s'." % [_case_label, key_label])
	var pad_label := String(next_run.call("binding_label", &"interact", &"gamepad"))
	_expect(pad_label == "X", "%s: the interact button came back as '%s'." % [_case_label, pad_label])
	config = ConfigFile.new()
	config.load(SETTINGS_PATH)
	_expect(
		String(config.get_value("display", "locale", "")) == "zh-CN",
		"%s: saving settings dropped the language Loc stored." % _case_label
	)

	# Restore defaults puts E and A back.
	next_run.call("restore_default_bindings")
	_expect(
		String(next_run.call("binding_label", &"interact", &"keyboard")) == "E",
		"%s: restoring defaults did not bring E back." % _case_label
	)
	_expect(
		String(next_run.call("binding_label", &"interact", &"gamepad")) == "A",
		"%s: restoring defaults did not bring A back." % _case_label
	)

	# A damaged file: bad values fall back, bad bindings keep the defaults.
	config = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("text", "size", "enormous")
	config.set_value("audio", "master", 400)
	config.set_value("input", "interact", PackedStringArray(["key:notanumber"]))
	config.set_value("input", "no_such_action", PackedStringArray(["key:69"]))
	config.save(SETTINGS_PATH)
	next_run.call("load_settings")
	var problems: Array = next_run.call("get_load_problems")
	_expect(problems.size() >= 4, "%s: only %d problem(s) reported." % [_case_label, problems.size()])
	_expect(next_run.call("get_text_size") == &"standard", "%s: a bad size was used." % _case_label)
	_expect(int(next_run.call("get_volume", &"master")) == 100, "%s: a bad volume was used." % _case_label)
	_expect(
		InputMap.action_get_events(&"interact").size() > 0
		and String(next_run.call("binding_label", &"interact", &"keyboard")) == "E",
		"%s: a damaged binding left interact without its default." % _case_label
	)

	# Leave nothing behind for the next check in the job.
	next_run.call("reset_to_defaults")
	next_run.queue_free()
	settings.call("load_settings")
	config = ConfigFile.new()
	config.load(SETTINGS_PATH)
	_expect(
		String(config.get_value("display", "locale", "")) == "zh-CN",
		"%s: restoring defaults dropped the language." % _case_label
	)
	# The language as it was before this check, or no key at all.
	if original_locale == null:
		config.erase_section_key("display", "locale")
	else:
		config.set_value("display", "locale", original_locale)
	config.save(SETTINGS_PATH)
	await _frames(2)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
