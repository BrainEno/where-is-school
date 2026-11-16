extends SceneTree
## Auto, skip and the read log: what the player has read, and the two ways a conversation
## can move on without a key press for every line.
##
## A. `ReadLog` on its own: what counts as read (identity, language, edited text), options,
##    the file round trip, and every way the file can be wrong (not JSON, not ours, a newer
##    version, single bad entries), with the bytes kept and nothing written over a newer file.
## B. `DialoguePlayback` on its own, with a hand-driven clock: the auto pause and what holds
##    it (typing, options, backlog, a check), skip and each of its stops, tap against hold,
##    and auto coming back after skip.
## C. The settings: the two new choices are stored, read back, checked and reset; the two new
##    inputs are declared in `project.godot`, rebindable, and share no input with anything.
## D. The real game (`main.tscn`, the classroom's `n_class`): a first read marks every line;
##    a second read skips to the choice and stops there, with the option taken before marked;
##    a log that has read nothing stops skip at once and says why; auto passes lines by
##    itself, never picks an option, freezes while the backlog is open; a language switch
##    is not a new reading; R and the "Auto" word switch auto; and the settings screen's
##    "forget" row asks twice and then forgets.
## E. Sprint as a toggle, the other accessibility control in this change: stored, followed by
##    the player, a press switches the jog on and the next off, standing still or losing
##    control ends it, and "hold" still means hold.
##
## Nothing here touches the player's files: the read log lives in test-only paths and the
## settings file is backed up and restored.

const Harness = preload("res://tests/test_harness.gd")

const TIMEOUT_SECONDS := 260.0
const SETTINGS_PATH := "user://settings.cfg"
const LOG_DIR := "user://playback_test"
const MAX_STEPS := 80

var _failures: Array[String] = []
var _had_settings := false
var _settings_backup := PackedByteArray()
var _restored := false
var _settings = null
var _main: Node = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null
var _backlog: BacklogPanel = null
var _mode_events: Array = []


func _initialize() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "dialogue_playback_test.gd")
	call_deferred("_run")


func _finalize() -> void:
	_restore_settings()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_check_read_log_rules()
	_check_read_log_file()
	_check_read_log_damage()
	_check_auto_rules()
	_check_skip_rules()
	_check_skip_hold_and_resume()

	root.size = Vector2i(1600, 900)
	await _frames(3)
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		_finish_with(["State autoloads are unavailable."])
		return
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	_settings = Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	Harness.clear_session_state(self)
	if _settings == null:
		_finish_with(["The Settings autoload could not be created."])
		return
	_settings.call("reset_to_defaults")
	_check_settings_values()
	_check_settings_bindings()

	# The game's own read log, for everything below: a fresh file in the test directory.
	var shared := ReadLog.new(_log_path("game"))
	shared.load_file()
	ReadLog.use_shared(shared)
	if not await _load_main():
		_finish_with(_failures)
		return
	await _check_first_and_second_reading()
	await _check_skip_stops_at_unread()
	await _check_auto_in_game()
	await _check_inputs_and_mode_bar()
	await _check_settings_screen()
	await _check_sprint_toggle()
	_finish_with(_failures)


func _finish_with(failures: Array) -> void:
	ReadLog.use_shared(null)
	Engine.time_scale = 1.0
	_restore_settings()
	_remove_dir(LOG_DIR)
	Harness.finish(
		self, failures,
		"lines read and options taken are remembered by identity, language and text; the file "
		+ "survives damage and newer versions; auto waits a reading pause and never picks an "
		+ "option; skip passes read lines and stops at unread text, choices and the end; the "
		+ "settings, the inputs, the mode words and the forget row all work in the real game."
	)


# --- A. the read log --------------------------------------------------------------------


func _check_read_log_rules() -> void:
	var read_log := ReadLog.new(_log_path("rules"))
	var id := "conv:n_class/start"
	_expect(not read_log.is_read(id, "en", "Hello."), "A: an empty read_log already knew a line.")
	_expect(read_log.mark_read(id, "en", "Hello."), "A: marking a new line was not news.")
	_expect(read_log.is_read(id, "en", "Hello."), "A: a marked line is not read.")
	_expect(not read_log.mark_read(id, "en", "Hello."), "A: marking the same text twice was news.")
	_expect(read_log.is_read(id, "zh-CN", "Ni hao."),
		"A: a line read in English does not count when it is shown in Chinese.")
	_expect(not read_log.is_read(id, "en", "Hello, again."),
		"A: an edited line still counts as read in the language it was read in.")
	_expect(read_log.mark_read(id, "en", "Hello, again."), "A: the edited text was not news.")
	_expect(read_log.is_read(id, "en", "Hello, again.") and not read_log.is_read(id, "en", "Hello."),
		"A: after re-reading, the read_log remembers the old text instead of the new one.")
	_expect(read_log.mark_read(id, "zh-CN", "Ni hao."), "A: a second language was not news.")
	_expect(not read_log.is_read(id, "zh-CN", "Ni hao!"),
		"A: a change to the Chinese text did not make the line unread in Chinese.")
	_expect(read_log.line_count() == 1, "A: one line in two languages counted as %d lines." % read_log.line_count())

	for unknown: String in ["unidentified:abc", ""]:
		_expect(not read_log.mark_read(unknown, "en", "x"), "A: '%s' was remembered." % unknown)
		_expect(not read_log.is_read(unknown, "en", "x"), "A: '%s' counts as read." % unknown)
	_expect(not read_log.mark_read("conv:a/b", "", "x"), "A: a line with no language was remembered.")

	var choice := ReadLog.choice_identity(&"n_class", &"stay_or_go", &"stay")
	_expect(choice == "choice:n_class/stay_or_go/stay", "A: the option identity is %s." % choice)
	_expect(not read_log.has_chosen(choice), "A: an option was taken before anyone took it.")
	_expect(read_log.mark_chosen(choice), "A: taking an option was not news.")
	_expect(read_log.has_chosen(choice) and not read_log.mark_chosen(choice), "A: the option was not remembered once.")
	_expect(not read_log.mark_chosen(""), "A: an empty option id was remembered.")
	_expect(ReadLog.fingerprint("x").length() == ReadLog.FINGERPRINT_LENGTH,
		"A: the fingerprint is %d characters." % ReadLog.fingerprint("x").length())


func _check_read_log_file() -> void:
	var path := _log_path("file")
	var read_log := ReadLog.new(path)
	_expect(read_log.load_file() and read_log.problems.is_empty(), "A: a missing file is a problem: %s" % str(read_log.problems))
	_expect(read_log.flush().get("written", true) == false, "A: a clean read_log wrote a file.")
	_expect(not FileAccess.file_exists(path), "A: flushing a clean read_log created the file.")
	read_log.mark_read("conv:c/n1", "en", "One.")
	read_log.mark_read("inspection:desk/first", "zh-CN", "Zhuo.")
	read_log.mark_chosen("choice:c/n1/a")
	_expect(read_log.is_dirty(), "A: a changed read_log is not dirty.")
	var written := read_log.flush()
	_expect(bool(written.get("ok", false)), "A: the read_log was not written: %s" % str(written))
	_expect(not read_log.is_dirty(), "A: a written read_log is still dirty.")
	_expect(not FileAccess.file_exists("%s.tmp" % path), "A: the temporary file was left behind.")

	var again := ReadLog.new(path)
	_expect(again.load_file() and again.problems.is_empty(), "A: the written file did not load: %s" % str(again.problems))
	_expect(again.is_read("conv:c/n1", "en", "One."), "A: a line did not survive the file.")
	_expect(again.is_read("inspection:desk/first", "zh-CN", "Zhuo."), "A: an inspection did not survive the file.")
	_expect(again.has_chosen("choice:c/n1/a"), "A: an option did not survive the file.")
	_expect(not again.is_dirty(), "A: a freshly loaded read_log is dirty.")

	var forgotten := again.forget_all()
	_expect(bool(forgotten.get("ok", false)), "A: forgetting did not write: %s" % str(forgotten))
	var empty := ReadLog.new(path)
	empty.load_file()
	_expect(empty.line_count() == 0 and empty.choice_count() == 0,
		"A: after forgetting, the file still holds %d lines and %d options." % [empty.line_count(), empty.choice_count()])


func _check_read_log_damage() -> void:
	# Not JSON at all: started empty, bytes kept.
	var path := _log_path("broken")
	_write_text(path, "{ this is not json")
	var read_log := ReadLog.new(path)
	_expect(not read_log.load_file(), "A: a file that is not JSON loaded.")
	_expect(read_log.line_count() == 0 and not read_log.problems.is_empty(), "A: a broken file left lines or no problem.")
	var broken := path.get_basename() + ".broken.json"
	_expect(FileAccess.file_exists(broken) and FileAccess.get_file_as_string(broken) == "{ this is not json",
		"A: the unreadable bytes were not kept in %s." % broken)

	# Somebody else's JSON.
	path = _log_path("foreign")
	_write_text(path, JSON.stringify({"format": "other", "version": 1}))
	read_log = ReadLog.new(path)
	_expect(not read_log.load_file(), "A: a file with another format loaded.")
	_expect(FileAccess.file_exists(path.get_basename() + ".broken.json"), "A: the foreign file was not kept.")

	# No usable version.
	path = _log_path("noversion")
	_write_text(path, JSON.stringify({"format": ReadLog.FORMAT, "version": "one"}))
	_expect(not ReadLog.new(path).load_file(), "A: a file without a usable version loaded.")

	# Bad entries are dropped one by one; the good ones stay.
	path = _log_path("entries")
	var good := ReadLog.fingerprint("Fine.")
	_write_text(path, JSON.stringify({
		"format": ReadLog.FORMAT, "version": ReadLog.VERSION,
		"lines": {
			"conv:a/ok": {"en": good},
			"conv:a/short": {"en": "abc"},
			"conv:a/upper": {"en": good.to_upper() if good.to_upper() != good else "ZZZZZZZZZZZZZZZZ"},
			"unidentified:x": {"en": good},
			"conv:a/notdict": "nope",
		},
		"choices": ["choice:a/n/x", 7, "not-a-choice"],
	}))
	read_log = ReadLog.new(path)
	_expect(read_log.load_file(), "A: a file with some bad entries was refused as a whole.")
	_expect(read_log.line_count() == 1 and read_log.is_read("conv:a/ok", "en", "Fine."),
		"A: %d lines kept from one good and four bad entries." % read_log.line_count())
	_expect(read_log.choice_count() == 1 and read_log.has_chosen("choice:a/n/x"),
		"A: %d options kept from one good and two bad entries." % read_log.choice_count())
	_expect(read_log.problems.size() == 2, "A: bad entries reported as %s." % str(read_log.problems))

	# A newer version: read for what this one understands, never written over.
	path = _log_path("newer")
	var newer_text := JSON.stringify({
		"format": ReadLog.FORMAT, "version": ReadLog.VERSION + 1,
		"lines": {"conv:a/ok": {"en": good}}, "choices": [], "future": {"x": 1},
	})
	_write_text(path, newer_text)
	read_log = ReadLog.new(path)
	_expect(read_log.load_file(), "A: a newer file was refused.")
	_expect(read_log.is_read_only(), "A: a newer file is not read-only.")
	_expect(read_log.is_read("conv:a/ok", "en", "Fine."), "A: a newer file's lines were not read.")
	read_log.mark_read("conv:a/new", "en", "New.")
	var refused := read_log.flush()
	_expect(not bool(refused.get("ok", true)) and String(refused.get("error", "")) == "read_only",
		"A: writing over a newer file was not refused: %s" % str(refused))
	_expect(FileAccess.get_file_as_string(path) == newer_text, "A: the newer file was changed.")
	var cleared := read_log.forget_all()
	_expect(bool(cleared.get("ok", false)) and not read_log.is_read_only(),
		"A: forgetting, which the player asks for, did not replace the newer file: %s" % str(cleared))


# --- B. playback ------------------------------------------------------------------------


func _check_auto_rules() -> void:
	var playback := DialoguePlayback.new()
	var line := {"presenting": true}
	playback.begin_line("conv:a/1", 22, false, "en")
	_expect(playback.tick(30.0, line) == DialoguePlayback.NOTHING, "B: manual mode advanced by itself.")

	playback.set_auto(true)
	_expect(playback.is_auto(), "B: auto did not switch on.")
	var english := playback.auto_pause()
	_expect(is_equal_approx(english, DialoguePlayback.BASE_PAUSE + 1.0),
		"B: 22 English characters wait %.2f s." % english)
	playback.begin_line("conv:a/1", 22, false, "zh-CN")
	var chinese := playback.auto_pause()
	_expect(chinese > english, "B: 22 Chinese characters (%.2f s) do not wait longer than English (%.2f s)." % [chinese, english])
	playback.begin_line("conv:a/1", 1, false, "en")
	_expect(is_equal_approx(playback.auto_pause(), DialoguePlayback.MIN_PAUSE), "B: a one-letter line is not given the minimum.")
	playback.begin_line("conv:a/1", 100000, false, "en")
	_expect(is_equal_approx(playback.auto_pause(), DialoguePlayback.MAX_PAUSE), "B: a huge line is not capped.")
	_expect(is_equal_approx(playback.auto_pause(true), DialoguePlayback.MAX_PAUSE + DialoguePlayback.CHECK_PAUSE),
		"B: a check on screen does not add its pause.")
	playback.begin_line("conv:a/1", 60, false, "en")
	playback.set_auto_speed(&"slow")
	var slow := playback.auto_pause()
	playback.set_auto_speed(&"fast")
	var fast := playback.auto_pause()
	playback.set_auto_speed(&"bogus")
	_expect(playback.auto_speed == &"fast", "B: an unknown auto speed was accepted.")
	_expect(slow > fast, "B: slow (%.2f s) is not slower than fast (%.2f s)." % [slow, fast])
	playback.set_auto_speed(&"normal")

	playback.begin_line("conv:a/2", 22, false, "en")
	var pause := playback.auto_pause()
	_expect(playback.tick(pause * 2.0, {"presenting": true, "revealing": true}) == DialoguePlayback.NOTHING,
		"B: auto passed a line still typing.")
	_expect(playback.tick(pause - 0.1, line) == DialoguePlayback.NOTHING, "B: auto passed a line early.")
	var waited := playback.get_waited()
	_expect(playback.tick(30.0, {"presenting": true, "blocked": true}) == DialoguePlayback.NOTHING,
		"B: auto passed a line nobody could read.")
	_expect(is_equal_approx(playback.get_waited(), waited), "B: the clock ran while the player was away.")
	_expect(playback.tick(0.2, line) == DialoguePlayback.ADVANCE, "B: auto did not pass the line after its pause.")
	for _i in 5:
		_expect(playback.tick(60.0, {"presenting": true, "choices": true}) == DialoguePlayback.NOTHING,
			"B: auto acted on a choice.")
	_expect(playback.is_auto(), "B: a choice switched auto off.")
	_expect(playback.tick(1.0, {}) == DialoguePlayback.NOTHING and playback.is_auto(),
		"B: auto did not stay on between conversations.")
	playback.toggle_auto()
	_expect(not playback.is_auto(), "B: auto did not toggle off.")


func _check_skip_rules() -> void:
	var playback := DialoguePlayback.new()
	_mode_events.clear()
	playback.mode_changed.connect(_on_mode_changed)
	var line := {"presenting": true}

	playback.begin_line("conv:a/1", 10, true, "en")
	playback.press_skip()
	playback.release_skip()
	_expect(playback.is_skipping(), "B: a tap of skip did not leave skip on.")
	_expect(playback.tick(0.01, {"presenting": true, "revealing": true}) == DialoguePlayback.COMPLETE,
		"B: skip did not finish a read line that was typing.")
	_expect(playback.tick(DialoguePlayback.SKIP_STEP * 0.5, line) == DialoguePlayback.NOTHING,
		"B: skip passed a line before its step.")
	_expect(playback.tick(DialoguePlayback.SKIP_STEP, line) == DialoguePlayback.ADVANCE,
		"B: skip did not pass a read line.")

	playback.begin_line("conv:a/2", 10, false, "en")
	_expect(playback.tick(0.01, line) == DialoguePlayback.NOTHING, "B: skip passed an unread line.")
	_expect(not playback.is_skipping(), "B: skip did not stop at an unread line.")
	_expect(_last_reason() == DialoguePlayback.REASON_UNREAD, "B: skip stopped with reason %s." % _last_reason())

	playback.set_skip_scope(&"all")
	playback.press_skip()
	playback.release_skip()
	_expect(playback.tick(DialoguePlayback.SKIP_STEP, line) == DialoguePlayback.ADVANCE,
		"B: skip set to all text did not pass an unread line.")
	_expect(playback.tick(0.01, {"presenting": true, "choices": true}) == DialoguePlayback.NOTHING
		and not playback.is_skipping() and _last_reason() == DialoguePlayback.REASON_CHOICE,
		"B: skip did not stop at a choice (reason %s)." % _last_reason())
	playback.press_skip()
	playback.release_skip()
	playback.tick(0.01, {"presenting": false})
	_expect(not playback.is_skipping() and _last_reason() == DialoguePlayback.REASON_CLOSED,
		"B: skip did not stop when the conversation closed (reason %s)." % _last_reason())
	playback.set_skip_scope(&"bogus")
	_expect(playback.skip_scope == &"all", "B: an unknown skip scope was accepted.")


func _check_skip_hold_and_resume() -> void:
	var playback := DialoguePlayback.new()
	_mode_events.clear()
	playback.mode_changed.connect(_on_mode_changed)
	var line := {"presenting": true}
	playback.begin_line("conv:a/1", 10, true, "en")

	# A tap toggles; a second tap stops.
	playback.press_skip()
	playback.tick(DialoguePlayback.HOLD_SECONDS * 0.5, {"presenting": true, "blocked": true})
	playback.release_skip()
	_expect(playback.is_skipping(), "B: a short press did not leave skip on.")
	playback.press_skip()
	_expect(not playback.is_skipping() and _last_reason() == DialoguePlayback.REASON_TOGGLED,
		"B: a second tap did not stop skip.")

	# A hold is momentary.
	playback.press_skip()
	_expect(playback.is_holding_skip(), "B: a press is not tracked as a hold.")
	playback.tick(DialoguePlayback.HOLD_SECONDS + 0.1, {"presenting": true, "blocked": true})
	playback.release_skip()
	_expect(not playback.is_skipping() and _last_reason() == DialoguePlayback.REASON_RELEASED,
		"B: letting go of a held skip did not stop it (reason %s)." % _last_reason())

	# Auto comes back when skip ends; switching auto off while skipping cancels that.
	playback.set_auto(true)
	playback.press_skip()
	playback.release_skip()
	_expect(playback.is_skipping(), "B: skip did not take over from auto.")
	playback.begin_line("conv:a/2", 10, false, "en")
	playback.tick(0.01, line)
	_expect(playback.is_auto(), "B: auto did not come back after skip stopped at unread text.")
	playback.press_skip()
	playback.release_skip()
	playback.set_auto(false)
	playback.tick(0.01, line)
	_expect(playback.mode == DialoguePlayback.Mode.MANUAL,
		"B: auto came back after it was switched off during skip.")
	playback.set_auto(true)
	playback.stop()
	_expect(playback.mode == DialoguePlayback.Mode.MANUAL, "B: stop() left a mode on.")


func _on_mode_changed(mode: int, reason: StringName) -> void:
	_mode_events.append([mode, reason])


func _last_reason() -> StringName:
	return StringName() if _mode_events.is_empty() else StringName(_mode_events[-1][1])


# --- C. settings ------------------------------------------------------------------------


func _check_settings_values() -> void:
	_expect(_settings.call("get_auto_speed") == &"normal", "C: auto speed does not start at normal.")
	_expect(_settings.call("get_skip_scope") == &"read", "C: skip does not start at read text only.")
	var changed: Array = []
	var note := func(key: StringName) -> void: changed.append(key)
	_settings.connect("setting_changed", note)
	_settings.call("set_auto_speed", &"slow")
	_settings.call("set_skip_scope", &"all")
	_settings.call("set_auto_speed", &"warp")
	_settings.call("set_skip_scope", &"nothing")
	_settings.disconnect("setting_changed", note)
	_expect(str(changed) == str([&"auto_speed", &"skip_scope"]), "C: the changes announced %s." % str(changed))
	var file := ConfigFile.new()
	file.load(SETTINGS_PATH)
	_expect(file.get_value("text", "auto_speed", "") == "slow" and file.get_value("text", "skip_scope", "") == "all",
		"C: the choices were not stored in [text].")
	_settings.call("load_settings")
	_expect(_settings.call("get_auto_speed") == &"slow" and _settings.call("get_skip_scope") == &"all",
		"C: the stored choices did not load back.")
	file.set_value("text", "auto_speed", 3)
	file.set_value("text", "skip_scope", "everything")
	file.save(SETTINGS_PATH)
	_settings.call("load_settings")
	_expect(_settings.call("get_auto_speed") == &"normal" and _settings.call("get_skip_scope") == &"read",
		"C: bad stored values were not replaced by the defaults.")
	var problems: Array = _settings.call("get_load_problems")
	_expect(problems.size() >= 2, "C: bad stored values were not reported: %s" % str(problems))
	_settings.call("set_auto_speed", &"fast")
	_settings.call("reset_to_defaults")
	_expect(_settings.call("get_auto_speed") == &"normal", "C: reset did not restore auto speed.")


func _check_settings_bindings() -> void:
	var actions: Array = _settings.call("get_rebindable_actions")
	var expected := {
		&"dialogue_auto": ["key:%d" % KEY_R, "joy_axis:%d:+" % JOY_AXIS_RIGHT_X],
		&"dialogue_skip": ["key:%d" % KEY_F, "joy_axis:%d:+" % JOY_AXIS_TRIGGER_LEFT],
	}
	for action: StringName in expected:
		_expect(actions.has(action), "C: %s cannot be rebound." % action)
		_expect(L10n.has_key("settings.action.%s" % action), "C: %s has no name on the settings screen." % action)
		var have := PackedStringArray()
		for event: InputEvent in InputMap.action_get_events(action):
			have.append(String(_settings.call("encode_event", event)))
		_expect(Array(have) == expected[action], "C: %s is bound to %s." % [action, str(have)])
		for other: Variant in actions:
			if StringName(other) == action:
				continue
			for event: InputEvent in InputMap.action_get_events(StringName(other)):
				var code := String(_settings.call("encode_event", event))
				_expect(not have.has(code), "C: %s and %s both use %s." % [action, other, code])
	var result: Dictionary = _settings.call("rebind", &"dialogue_skip", _key_event(KEY_G))
	_expect(bool(result.get("ok", false)), "C: skip could not be moved to G: %s" % str(result))
	_settings.call("restore_default_bindings")
	_expect(InputMap.action_has_event(&"dialogue_skip", _key_event(KEY_F)), "C: restore did not bring F back to skip.")


# --- D. the real game -------------------------------------------------------------------


func _load_main() -> bool:
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return false
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _frames(3)
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	var ui := _main.get_node_or_null("GameUI")
	if ui != null:
		_panel = ui.get_node_or_null("DialoguePanel") as DialoguePanel
		_backlog = ui.get_node_or_null("BacklogPanel") as BacklogPanel
	if _dialogue == null or _panel == null or _backlog == null:
		_failures.append("main.tscn did not expose the dialogue controller, panel and backlog.")
		return false
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	if _dialogue.get_read_log() != ReadLog.shared():
		_failures.append("The dialogue controller does not use the shared read log.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	Engine.time_scale = 4.0
	await _frames(2)
	return true


func _check_first_and_second_reading() -> void:
	var read_log := _dialogue.get_read_log()
	Harness.clear_session_state(self)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("D: n_class could not be started.")
		return
	var read_flags: Array[bool] = []
	var steps := 0
	while _dialogue.is_busy() and not _dialogue.has_pending_choices() and steps < MAX_STEPS:
		read_flags.append(_dialogue.was_current_line_read())
		steps += 1
		_dialogue.advance_presentation()
		await _frames(2)
	if not _dialogue.has_pending_choices():
		_failures.append("D: the first reading never reached the choice.")
		await _close()
		return
	_expect(not read_flags.has(true), "D: a line counted as read on the very first reading: %s" % str(read_flags))
	var lines_read := read_log.line_count()
	_expect(lines_read >= read_flags.size(), "D: %d lines were shown but only %d remembered." % [read_flags.size(), lines_read])
	var first_choices := _panel.get_choice_buttons().size()
	for index in first_choices:
		_expect(not _panel.is_choice_marked_chosen(index), "D: option %d is marked before it was ever taken." % index)
	_dialogue.select_choice(0)
	await _frames(2)
	_expect(read_log.choice_count() == 1, "D: taking an option remembered %d options." % read_log.choice_count())
	await _close()
	_expect(not read_log.is_dirty(), "D: the read log was not written when the conversation closed.")
	_expect(FileAccess.file_exists(read_log.path), "D: the read log file was not written.")

	# Second reading: skip runs to the choice and stops there.
	Harness.clear_session_state(self)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("D: n_class could not be started a second time.")
		return
	await _frames(2)
	_expect(_dialogue.was_current_line_read(), "D: the first line is not read on the second reading.")
	_dialogue.request_skip()
	await _frames(1)
	_expect(_panel.get_playback_mode() == DialoguePlayback.Mode.SKIP, "D: the panel was not told skip is on.")
	_expect(_panel.get_hint_text() == L10n.t("ui.dialogue_skip_on", _mode_keys()),
		"D: while skipping the hint says '%s'." % _panel.get_hint_text())
	var reached := await _wait_until(func() -> bool: return _dialogue.has_pending_choices(), 20.0)
	_expect(reached, "D: skip did not reach the choice of a conversation read before.")
	await _frames(3)
	_expect(not _dialogue.get_playback().is_skipping(), "D: skip did not stop at the choice.")
	var buttons := _panel.get_choice_buttons()
	_expect(buttons.size() == first_choices, "D: the second reading offered %d options, the first %d." % [buttons.size(), first_choices])
	if buttons.size() >= 2:
		_expect(_panel.is_choice_marked_chosen(0), "D: the option taken before is not marked.")
		_expect(not _panel.is_choice_marked_chosen(1), "D: an option never taken is marked.")
		var seen_color := buttons[0].get_theme_color(&"font_color")
		var fresh_color := buttons[1].get_theme_color(&"font_color")
		_expect(seen_color != fresh_color, "D: the option taken before looks like the others.")
	await _close()


func _check_skip_stops_at_unread() -> void:
	var fresh := ReadLog.new(_log_path("fresh"))
	_dialogue.set_read_log(fresh)
	Harness.clear_session_state(self)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("D: n_class could not be started with a fresh read_log.")
		_dialogue.set_read_log(null)
		return
	await _frames(3)
	var line_before := String(_dialogue.get_current_line().get("text", ""))
	_dialogue.request_skip()
	await _frames(4)
	_expect(not _dialogue.get_playback().is_skipping(), "D: skip ran on with nothing read.")
	_expect(String(_dialogue.get_current_line().get("text", "")) == line_before, "D: skip passed an unread line.")
	_expect(_panel.get_playback_notice() == L10n.t("ui.dialogue_skip_stopped"),
		"D: the hint did not say why skip stopped ('%s')." % _panel.get_playback_notice())
	_expect(_panel.get_hint_text() == L10n.t("ui.dialogue_skip_stopped"), "D: the notice is not on the hint line.")

	# A language switch shows the line again; it is not a new reading.
	L10n.set_locale("zh-CN")
	_dialogue.apply_locale("zh-CN")
	await _frames(3)
	_expect(not _dialogue.was_current_line_read(), "D: switching language made the line count as read before.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	await _frames(2)
	await _close()
	_expect(fresh.line_count() >= 1, "D: the fresh read_log remembered nothing.")
	_dialogue.set_read_log(null)
	_expect(_dialogue.get_read_log() == ReadLog.shared(), "D: set_read_log(null) did not go back to the shared read_log.")


func _check_auto_in_game() -> void:
	Harness.clear_session_state(self)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("D: n_class could not be started for auto.")
		return
	await _frames(2)
	_dialogue.toggle_auto()
	await _frames(1)
	_expect(_dialogue.get_playback().is_auto(), "D: auto did not switch on.")
	_expect(_panel.get_hint_text() == L10n.t("ui.dialogue_auto_on", _mode_keys()),
		"D: with auto on the hint says '%s'." % _panel.get_hint_text())

	# The backlog freezes it.
	await _wait_until(func() -> bool: return not _panel.is_revealing(), 5.0)
	_backlog.open()
	await _frames(2)
	var frozen := String(_dialogue.get_current_line().get("text", ""))
	await _seconds(_dialogue.get_playback().auto_pause(true) / Engine.time_scale + 0.5)
	_expect(String(_dialogue.get_current_line().get("text", "")) == frozen, "D: auto passed a line behind the open backlog.")
	_backlog.close()
	await _frames(2)

	var first := _line_text()
	var line_moved := func() -> bool: return _line_text() != first or _dialogue.has_pending_choices()
	var moved := await _wait_until(line_moved, DialoguePlayback.MAX_PAUSE / Engine.time_scale + 3.0)
	_expect(moved, "D: auto did not pass a line by itself.")
	var reached := await _wait_until(func() -> bool: return _dialogue.has_pending_choices(), 60.0)
	_expect(reached, "D: auto did not carry the conversation to its choice.")
	if reached:
		var count := _panel.get_choice_buttons().size()
		await _seconds(DialoguePlayback.MAX_PAUSE / Engine.time_scale + 0.5)
		_expect(_dialogue.has_pending_choices() and _panel.get_choice_buttons().size() == count,
			"D: auto picked an option.")
		_expect(_dialogue.get_playback().is_auto(), "D: a choice switched auto off.")
	_dialogue.toggle_auto()
	await _close()


func _check_inputs_and_mode_bar() -> void:
	Harness.clear_session_state(self)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("D: n_class could not be started for the inputs.")
		return
	await _frames(3)
	await _press_key(KEY_R)
	_expect(_dialogue.get_playback().is_auto(), "D: R did not switch auto on.")
	await _press_key(KEY_R)
	_expect(not _dialogue.get_playback().is_auto(), "D: R did not switch auto off.")

	var bar := _panel.get_mode_bar()
	_expect(bar != null and bar.visible, "D: the Auto / Skip words are not shown at 1600x900.")
	if bar != null:
		var expected_auto := L10n.t("ui.dialogue_mode_auto_key", {"key": MenuStyle.key(_panel, &"dialogue_auto")})
		_expect(bar.get_auto_button().text == expected_auto,
			"D: the auto word reads '%s', not '%s'." % [bar.get_auto_button().text, expected_auto])
		var hint := _panel.get_node("Frame/Content/HintLabel") as Label
		var font := hint.get_theme_font(&"font")
		var hint_width := font.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			hint.get_theme_font_size(&"font_size")).x
		var text_start := hint.get_global_rect().end.x - hint_width
		_expect(bar.get_global_rect().end.x <= text_start, "D: the mode words run into the hint text.")
		bar.get_auto_button().pressed.emit()
		await _frames(1)
		_expect(_dialogue.get_playback().is_auto(), "D: the Auto word did not switch auto on.")
		_expect(bar.get_auto_button().get_theme_color(&"font_color") == DialogueModeBar.LIT,
			"D: the Auto word is not lit while auto is on.")
		bar.get_auto_button().pressed.emit()
		await _frames(1)
		_expect(not _dialogue.get_playback().is_auto(), "D: the Auto word did not switch auto off.")
	await _close()


func _check_settings_screen() -> void:
	var menu := _main.get_node_or_null("PauseMenu") as PauseMenu
	if menu == null:
		_failures.append("D: main.tscn has no pause menu.")
		return
	var panel := menu.get_settings_panel()
	panel.open()
	await _frames(3)
	for id: StringName in [&"auto_speed", &"skip_scope", &"clear_read_log"]:
		_expect(panel.get_row_control(id) != null, "D: the settings screen has no %s row." % id)
	panel.cycle(&"auto_speed", 1)
	await _frames(1)
	_expect(_settings.call("get_auto_speed") == &"fast", "D: cycling the auto row set %s." % _settings.call("get_auto_speed"))
	_expect(_dialogue.get_playback().auto_speed == &"fast", "D: the dialogue did not follow the auto speed setting.")
	panel.cycle(&"skip_scope", 1)
	await _frames(1)
	_expect(_dialogue.get_playback().skip_scope == &"all", "D: the dialogue did not follow the skip setting.")

	var read_log := ReadLog.shared()
	var count := read_log.line_count()
	var clear := panel.get_row_control(&"clear_read_log") as Button
	_expect(count > 0, "D: the shared read_log is empty before the forget row is tried.")
	_expect(clear.text == L10n.t("settings.clear_read_log", {"count": count}),
		"D: the forget row reads '%s'." % clear.text)
	panel.focus_row(&"clear_read_log")
	await _frames(1)
	clear.pressed.emit()
	await _frames(1)
	_expect(panel.is_clear_read_log_armed() and read_log.line_count() == count, "D: one press forgot, or did not ask.")
	_expect(panel.get_status_text() == L10n.t("settings.clear_read_log_ask"), "D: the first press did not ask.")
	_expect(clear.text == L10n.t("settings.clear_read_log_confirm"), "D: the row does not say to press again.")
	panel.focus_row(&"auto_speed")
	await _frames(1)
	_expect(not panel.is_clear_read_log_armed(), "D: leaving the row did not cancel the question.")
	clear.pressed.emit()
	clear.pressed.emit()
	await _frames(1)
	_expect(read_log.line_count() == 0 and read_log.choice_count() == 0, "D: two presses did not forget.")
	_expect(panel.get_status_text() == L10n.t("settings.read_log_cleared"), "D: forgetting did not say so.")
	_expect(clear.text == L10n.t("settings.clear_read_log", {"count": 0}), "D: the row does not show zero lines.")
	var on_disk := ReadLog.new(read_log.path)
	on_disk.load_file()
	_expect(on_disk.line_count() == 0, "D: the forgotten lines are still in the file.")
	clear.pressed.emit()
	await _frames(1)
	_expect(panel.get_status_text() == L10n.t("settings.read_log_empty") and not panel.is_clear_read_log_armed(),
		"D: pressing forget on an empty read_log asked anyway.")
	panel.close()
	await _frames(2)
	_settings.call("reset_to_defaults")


# --- E. sprint as a toggle --------------------------------------------------------------


func _check_sprint_toggle() -> void:
	var player := _main.get_node_or_null("Player") as PlayerController
	if player == null:
		_failures.append("E: main.tscn has no player.")
		return
	_expect(_settings.call("get_sprint_mode") == &"hold", "E: sprint does not start as hold.")
	_expect(player.sprint_mode == &"hold", "E: the player does not start with hold.")
	_settings.call("set_sprint_mode", &"toggle")
	_settings.call("set_sprint_mode", &"sideways")
	_expect(player.sprint_mode == &"toggle", "E: the player did not follow the setting (%s)." % player.sprint_mode)
	var file := ConfigFile.new()
	file.load(SETTINGS_PATH)
	_expect(file.get_value("controls", "sprint_mode", "") == "toggle", "E: sprint mode was not stored in [controls].")

	# The player's own physics frame also reads the input; it is paused so the latch is
	# driven only from here, with a clock this test controls.
	player.set_physics_process(false)
	player.set_control_enabled(true)
	var walk := player.move_speed
	var jog := player.jog_speed
	_expect(is_equal_approx(player.target_speed(), walk), "E: toggle mode jogs before any press.")
	await _tap_sprint(player, Vector2.ZERO)
	_expect(player.is_sprint_latched() and is_equal_approx(player.target_speed(), jog),
		"E: a press of sprint did not switch the jog on.")
	player.update_sprint_latch(Vector2(1.0, 0.0), 5.0)
	_expect(player.is_sprint_latched(), "E: the jog stopped while the player was moving.")
	player.update_sprint_latch(Vector2.ZERO, PlayerController.SPRINT_LATCH_IDLE_SECONDS * 0.5)
	_expect(player.is_sprint_latched(), "E: the jog stopped after a short pause.")
	player.update_sprint_latch(Vector2.ZERO, PlayerController.SPRINT_LATCH_IDLE_SECONDS)
	_expect(not player.is_sprint_latched(), "E: standing still did not end the jog.")

	# A press held over several frames is one press.
	Input.action_press(PlayerController.SPRINT_ACTION)
	player.update_sprint_latch(Vector2(1.0, 0.0), 0.0)
	for _i in 3:
		await process_frame
		player.update_sprint_latch(Vector2(1.0, 0.0), 0.0)
	_expect(player.is_sprint_latched(), "E: holding the press turned the jog off again.")
	Input.action_release(PlayerController.SPRINT_ACTION)
	await process_frame
	await _tap_sprint(player, Vector2(1.0, 0.0))
	_expect(not player.is_sprint_latched(), "E: a second press did not switch the jog off.")

	await _tap_sprint(player, Vector2(1.0, 0.0))
	_expect(player.is_sprint_latched(), "E: a third press did not switch the jog on.")
	player.set_control_enabled(false)
	player.update_sprint_latch(Vector2(1.0, 0.0), 0.0)
	_expect(not player.is_sprint_latched(), "E: losing control did not end the jog.")
	player.set_control_enabled(true)

	_settings.call("set_sprint_mode", &"hold")
	Input.action_press(PlayerController.SPRINT_ACTION)
	_expect(is_equal_approx(player.target_speed(), jog), "E: hold mode does not jog while sprint is down.")
	Input.action_release(PlayerController.SPRINT_ACTION)
	_expect(is_equal_approx(player.target_speed(), walk), "E: hold mode jogs after sprint is let go.")
	_settings.call("set_sprint_mode", &"toggle")
	_settings.call("reset_to_defaults")
	_expect(player.sprint_mode == &"hold", "E: reset did not bring the player back to hold.")
	player.set_physics_process(true)


## One press of sprint, seen by the latch in the frame it lands in (that is the frame
## `is_action_just_pressed` answers for), then let go.
func _tap_sprint(player: PlayerController, moving: Vector2) -> void:
	Input.action_press(PlayerController.SPRINT_ACTION)
	player.update_sprint_latch(moving, 0.0)
	Input.action_release(PlayerController.SPRINT_ACTION)
	await process_frame


# --- helpers ----------------------------------------------------------------------------


func _line_text() -> String:
	return String(_dialogue.get_current_line().get("text", ""))


func _mode_keys() -> Dictionary:
	return {
		"auto": MenuStyle.key(_panel, &"dialogue_auto"),
		"skip": MenuStyle.key(_panel, &"dialogue_skip"),
	}


func _close() -> void:
	_dialogue.get_playback().stop()
	var steps := 0
	while _dialogue.is_busy() and steps < MAX_STEPS:
		steps += 1
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(2)
	if _dialogue.is_busy():
		_failures.append("D: a conversation would not close.")
	_panel.close()
	await _frames(2)


func _wait_until(condition: Callable, real_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(real_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await process_frame
	return bool(condition.call())


func _seconds(real_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(real_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _press_key(code: Key) -> void:
	var press := _key_event(code)
	press.pressed = true
	root.push_input(press, true)
	await _frames(1)
	var release := _key_event(code)
	release.pressed = false
	root.push_input(release, true)
	await _frames(1)


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	return event


func _log_path(tag: String) -> String:
	return "%s/%s.json" % [LOG_DIR, tag]


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write the fixture %s." % path)
		return
	file.store_string(text)
	file.close()


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _restore_settings() -> void:
	if _restored:
		return
	_restored = true
	if _had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_settings_backup)
			file.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
