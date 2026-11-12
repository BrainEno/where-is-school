extends SceneTree
## Regression guard for the player settings (#105) and the input rebinding (#106).
##
## `opening_resume_test.gd` already proves the happy path once: one set of preferences
## survives a restart, `[display] locale` survives a write, one conflict is refused and a
## damaged binding falls back. `hud_layout_test.gd` measures every label of the settings
## screen at the largest text size. This file covers what neither of them does:
##
## A. **Persistence and the language key.** Every preference (text size and speed, UI
##    scale, the three volumes, a rebinding) is read back by a re-instantiated node and by
##    `load_settings()`; `Loc` and `Settings` writing the same file in either order lose
##    nothing of each other's; sections and keys this node does not own survive; damaged
##    values, an unreadable file and bindings that break the rules (Esc taken off the
##    menus, Esc given to an action, two actions on one input, a device left without a
##    binding) fall back to the defaults and are named by `get_load_problems()`.
## B. **Serialisation and the rebinding rules.** Keys, pad buttons and both directions of
##    every stick axis survive encode -> decode; everything else is refused; Esc never
##    becomes an ordinary binding and the Esc actions keep it; a conflict changes nothing;
##    the two shared pairs still share; "Restore defaults" is exactly `project.godot`.
## C. **The capture flow on the real settings screen, inside the real pause menu.** A key,
##    a pad button and a stick direction are captured from the focused cell; Esc and the
##    six-second timeout end a capture without a change; the focus stays on the row; a
##    press from the other device, a click and closing the menu leave no capture behind
##    and leak nothing to the game; afterwards the pause menu and the game get input.
##    The events are synthetic (`Viewport.push_input`): this is not a hardware test.
## D. **The volume dials.** Master 0 mutes only Master, Music 0 only Music, SFX 0 the SFX
##    bus and the interaction cues' own gain; each dial lands on the authored trim plus its
##    own level and never moves another; a restart restores the same dB; the cues stay on
##    Master, the music on Music, room tones are moved to SFX and nothing else is.
## E. **Accessibility of the settings screen.** 3 text sizes x 4 text speeds, at 1280x720
##    and 1600x900, in English and Chinese: the panel fits, the rows show the setting, the
##    reveal speed matches, every row can be scrolled into view, and walking the screen
##    with only the keyboard (arrows, Tab, Shift+Tab) or only the pad (D-pad) reaches every
##    row without the focus ever landing on the pause menu behind it.
##
## The real `user://settings.cfg` is copied at start and written back on every exit path
## (the normal one and `_finalize()`, which also runs after the watchdog quits).

const Harness = preload("res://tests/test_harness.gd")
const SettingsScript := preload("res://scripts/autoload/settings_manager.gd")

const TIMEOUT_SECONDS := 300.0
const SETTINGS_PATH := "user://settings.cfg"
const CAPTURE_SIZE := Vector2i(1600, 900)
const LAYOUT_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900)]
const LOCALES: Array[String] = ["en", "zh-CN"]
## The levels `default_bus_layout.tres` gives each bus: 100 % on a dial means this.
const BUS_TRIM_DB: Dictionary = {&"master": 0.0, &"music": -6.0, &"sfx": 0.0}
const DB_TOLERANCE := 0.05


## Records what reaches `_unhandled_input`: anything here got past the settings screen.
class InputProbe:
	extends Node

	var events: Array[InputEvent] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion or not event.is_pressed() or event.is_echo():
			return
		events.append(event)

	func count(action: StringName) -> int:
		var total := 0
		for event: InputEvent in events:
			if event.is_action_pressed(action):
				total += 1
		return total

	func describe() -> String:
		var names: Array[String] = []
		for event: InputEvent in events:
			names.append(event.as_text())
		return ", ".join(names)


var _failures: Array[String] = []
var _had_file := false
var _backup := PackedByteArray()
var _restored := false
# Untyped on purpose: the autoload scripts are looked up at run time and every member
# is called dynamically.
var _settings = null
var _loc = null
var _cues = null
var _music = null
var _menu: PauseMenu = null
## Runs while the tree is paused: sees anything that leaks past an open menu.
var _menu_probe: InputProbe = null
## Pausable, like the game: sees input only once the menus are gone.
var _game_probe: InputProbe = null


func _initialize() -> void:
	_backup_settings()
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "settings_regression_test.gd")
	call_deferred("_run")


func _finalize() -> void:
	_restore_settings()


func _run() -> void:
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	_cues = Harness.ensure_autoload(self, "CueAudio", "res://scripts/audio/cue_audio.gd")
	_music = Harness.ensure_autoload(self, "Music", "res://scripts/autoload/music_player.gd")
	_settings = Harness.ensure_autoload(
		self, "Settings", "res://scripts/autoload/settings_manager.gd"
	)
	if _settings == null or _loc == null or _cues == null or _music == null:
		_restore_settings()
		Harness.finish(self, ["The Settings, Loc, CueAudio or Music node is missing."], "")
		return
	_cues.call("set_silent", true)
	await _frames(2)

	await _check_persistence()
	await _check_damaged_file()
	await _check_loaded_bindings()
	_check_serialisation()
	_check_rebind_rules()
	_check_restore_defaults()
	await _check_audio()
	await _make_menu()
	await _check_capture()
	await _check_layout()

	_start_clean()
	_menu.queue_free()
	await _frames(2)
	_restore_settings()
	_expect(_file_matches_backup(), "The real settings.cfg was not restored byte for byte.")
	Harness.finish(
		self,
		_ordered_failures(),
		"settings persist without touching the language, bindings serialise and refuse "
		+ "what they must, capture never traps or leaks input, the volume dials are "
		+ "independent, and the settings screen is reachable by keyboard and pad alone."
	)


## The CI annotation keeps only the first twenty failure lines, so a section with many
## failures must not hide another's: the first three of every section come first.
func _ordered_failures() -> Array[String]:
	var first: Array[String] = []
	var rest: Array[String] = []
	var per_section: Dictionary = {}
	for failure: String in _failures:
		var section := failure.substr(0, 2)
		var seen := int(per_section.get(section, 0))
		per_section[section] = seen + 1
		if seen < 3:
			first.append(failure)
		else:
			rest.append(failure)
	first.append_array(rest)
	return first


# --- A. persistence and the language key -------------------------------------------


func _check_persistence() -> void:
	Harness.stage = "A. persistence and the language key"
	_start_clean()
	_loc.call("set_locale", "zh-CN")
	var config := _read_file()
	_expect(
		String(config.get_value("display", "locale", "")) == "zh-CN",
		"A: Loc did not write [display] locale."
	)
	config.set_value("mods", "palette", "warm")
	config.set_value("display", "window_hint", 3)
	config.set_value("text", "future_option", "kept")
	config.save(SETTINGS_PATH)

	_settings.call("set_text_size", &"large")
	_settings.call("set_text_speed", &"fast")
	_settings.call("set_ui_scale", &"125")
	_settings.call("set_volume", &"master", 40)
	_settings.call("set_volume", &"music", 70)
	_settings.call("set_volume", &"sfx", 20)
	var rebound: Dictionary = _settings.call("rebind", &"sprint", _key(KEY_K))
	_expect(bool(rebound.get("ok", false)), "A: rebinding sprint to K was refused: %s" % rebound)
	_expect_foreign_keys("A: after every Settings write", "zh-CN")
	config = _read_file()
	_expect(
		String(config.get_value("text", "future_option", "")) == "kept",
		"A: a key Settings does not know in its own [text] section was dropped."
	)

	# Loc writing after Settings keeps everything Settings wrote.
	_loc.call("set_locale", "en")
	config = _read_file()
	_expect(String(config.get_value("text", "size", "")) == "large", "A: Loc dropped [text] size.")
	_expect(int(config.get_value("audio", "sfx", -1)) == 20, "A: Loc dropped [audio] sfx.")
	var stored: Variant = config.get_value("input", "sprint", null)
	_expect(
		stored is PackedStringArray and (stored as PackedStringArray).has("key:%d" % KEY_K),
		"A: [input] sprint is stored as %s, not a list of encoded inputs." % str(stored)
	)
	_expect(
		int(config.get_value("settings", "version", 0)) == SettingsScript.FORMAT_VERSION,
		"A: [settings] version is not %d." % SettingsScript.FORMAT_VERSION
	)

	var next_run: Node = await _new_settings_node("SettingsNextRun")
	_expect_values(next_run, "A: a re-instantiated Settings node", [&"large", &"fast", &"125"],
		[40, 70, 20])
	_expect(
		String(next_run.call("binding_label", &"sprint", &"keyboard")) == "K",
		"A: the re-instantiated node lost sprint = K."
	)
	var problems: Array = next_run.call("get_load_problems")
	_expect(problems.is_empty(), "A: a file Settings wrote itself reports %s." % str(problems))
	next_run.queue_free()
	await _frames(1)

	_settings.call("load_settings")
	_expect_values(_settings, "A: load_settings() on the same node", [&"large", &"fast", &"125"],
		[40, 70, 20])

	_settings.call("reset_to_defaults")
	_expect_foreign_keys("A: after reset_to_defaults()", "en")
	_expect_values(_settings, "A: after reset_to_defaults()", [&"standard", &"normal", &"auto"],
		[100, 100, 100])
	config = _read_file()
	_expect(
		not config.has_section("input") and not config.has_section_key("display", "ui_scale"),
		"A: reset_to_defaults() left [input] or [display] ui_scale behind."
	)


func _check_damaged_file() -> void:
	Harness.stage = "A. damaged values"
	_start_clean()
	var config := ConfigFile.new()
	config.set_value("display", "locale", "zh-CN")
	config.set_value("text", "size", 3)
	config.set_value("text", "speed", "warp")
	config.set_value("display", "ui_scale", "300")
	config.set_value("audio", "master", -5)
	config.set_value("audio", "music", "loud")
	config.set_value("audio", "sfx", 100.5)
	config.save(SETTINGS_PATH)
	_settings.call("load_settings")
	var problems: Array = _settings.call("get_load_problems")
	for key: String in ["size", "speed", "ui_scale", "master", "music", "sfx"]:
		_expect(_mentions(problems, key), "A: a damaged '%s' was not reported (%s)." % [
			key, str(problems)
		])
	_expect_values(_settings, "A: damaged values", [&"standard", &"normal", &"auto"],
		[100, 100, 100])
	_expect(
		String(_read_file().get_value("display", "locale", "")) == "zh-CN",
		"A: reading a damaged file rewrote the language."
	)

	# A file that is not a config file at all.
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("[text\nsize = \"largest\n[audio]]\nmaster = ((\n")
	file.close()
	var probe := ConfigFile.new()
	if probe.load(SETTINGS_PATH) == OK:
		_failures.append("A: the unreadable fixture parsed; the check below proves nothing.")
	_settings.call("load_settings")
	problems = _settings.call("get_load_problems")
	_expect(not problems.is_empty(), "A: an unreadable settings.cfg was not reported.")
	_expect_values(_settings, "A: unreadable file", [&"standard", &"normal", &"auto"],
		[100, 100, 100])
	_settings.call("set_text_size", &"largest")
	_expect(
		String(_read_file().get_value("text", "size", "")) == "largest",
		"A: the first write after an unreadable file did not leave a readable one."
	)

	_remove_file()
	_settings.call("load_settings")
	problems = _settings.call("get_load_problems")
	_expect(problems.is_empty(), "A: a missing file (a first run) reports %s." % str(problems))


## Bindings written by hand or by an older build. Each case is loaded on its own; the
## rejected actions must come back exactly at their defaults, the others as written.
func _check_loaded_bindings() -> void:
	Harness.stage = "A. loaded bindings"
	var esc := "key:%d" % KEY_ESCAPE
	var cases: Array[Dictionary] = [
		{"name": "Esc taken off cancel", "input": {&"cancel": ["key:%d" % KEY_K, "joy_button:1"]},
			"rejected": [&"cancel"]},
		{"name": "Esc taken off pause", "input": {&"pause": ["key:%d" % KEY_P, "joy_button:6"]},
			"rejected": [&"pause"]},
		{"name": "Esc given to interact", "input": {&"interact": [esc, "joy_button:0"]},
			"rejected": [&"interact"]},
		{"name": "the log on interact's key", "input": {&"backlog": ["key:69", "joy_button:3"]},
			"rejected": [&"backlog"]},
		{"name": "sprint on the pause button",
			"input": {&"sprint": ["key:%d" % KEY_SHIFT, "joy_button:6"]}, "rejected": [&"sprint"]},
		{"name": "sprint with no key", "input": {&"sprint": ["joy_button:10"]},
			"rejected": [&"sprint"]},
		{"name": "interact and the log swapped",
			"input": {&"backlog": ["key:69", "joy_button:3"],
				&"interact": ["key:%d" % KEY_TAB, "joy_button:0"]}, "rejected": []},
		{"name": "interact on Space (shared with dialogue)",
			"input": {&"interact": ["key:32", "joy_button:0"]}, "rejected": []},
		{"name": "pause on X, Esc kept", "input": {&"pause": [esc, "joy_button:2"]},
			"rejected": []},
	]
	for case: Dictionary in cases:
		var tag := "A: loading '%s'" % String(case["name"])
		_remove_file()
		var config := ConfigFile.new()
		var written: Dictionary = case["input"]
		for action: StringName in written.keys():
			config.set_value("input", String(action), PackedStringArray(written[action]))
		config.save(SETTINGS_PATH)
		_settings.call("load_settings")
		var problems: Array = _settings.call("get_load_problems")
		var rejected: Array = case["rejected"]
		for action: StringName in written.keys():
			if rejected.has(action):
				_expect(_encoded(action) == _declared_encoded(action),
					"%s: %s is %s, not its default." % [tag, action, _encoded(action)])
				_expect(_mentions(problems, String(action)),
					"%s: %s was not reported (%s)." % [tag, action, str(problems)])
			else:
				_expect(_encoded(action) == PackedStringArray(written[action]),
					"%s: %s is %s, not what was written." % [tag, action, _encoded(action)])
		if rejected.is_empty():
			_expect(problems.is_empty(), "%s: a valid file reports %s." % [tag, str(problems)])
		_expect_no_conflicts(tag)
		_expect(_keyboard_keeps_esc(), "%s: Esc no longer reaches cancel and pause." % tag)

	# Two written actions on one key: whichever is kept, the map ends without a clash.
	_remove_file()
	var clash := ConfigFile.new()
	clash.set_value("input", "sprint", PackedStringArray(["key:%d" % KEY_K, "joy_button:10"]))
	clash.set_value("input", "backlog", PackedStringArray(["key:%d" % KEY_K, "joy_button:3"]))
	clash.save(SETTINGS_PATH)
	_settings.call("load_settings")
	var owners := 0
	for action: StringName in [&"sprint", &"backlog"]:
		if _encoded(action).has("key:%d" % KEY_K):
			owners += 1
	_expect(owners == 1, "A: two written actions on K left %d of them on it." % owners)
	_expect(not (_settings.call("get_load_problems") as Array).is_empty(),
		"A: two written actions on one key were not reported.")
	_expect_no_conflicts("A: two written actions on one key")
	_start_clean()


# --- B. serialisation and the rebinding rules ----------------------------------------


func _check_serialisation() -> void:
	Harness.stage = "B. serialisation"
	var samples: Array[InputEvent] = [
		_key(KEY_K), _key(KEY_F5), _key(KEY_KP_7), _key(KEY_SEMICOLON),
		_joy(JOY_BUTTON_X), _joy(JOY_BUTTON_DPAD_LEFT), _joy(JOY_BUTTON_LEFT_SHOULDER),
		_joy(JOY_BUTTON_MISC1),
	]
	for axis: JoyAxis in [
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y,
		JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT,
	]:
		samples.append(_motion(axis, -1.0))
		samples.append(_motion(axis, 1.0))
	samples.append(_motion(JOY_AXIS_LEFT_Y, 0.7))
	for event: InputEvent in samples:
		var text := SettingsScript.encode_event(event)
		var back := SettingsScript.decode_event(text)
		var tag := "B: %s (%s)" % [event.as_text(), text]
		if text.is_empty() or back == null:
			_failures.append("%s did not survive encode -> decode." % tag)
			continue
		_expect(back.get_class() == event.get_class(), "%s came back as %s." % [
			tag, back.get_class()
		])
		_expect(SettingsScript.encode_event(back) == text, "%s re-encoded differently." % tag)
		_expect(back.device == -1, "%s came back bound to device %d only." % [tag, back.device])
		_expect(
			SettingsScript.event_label(back) == SettingsScript.event_label(event),
			"%s is labelled differently after the round trip." % tag
		)
		if event is InputEventJoypadMotion:
			var sign_in := signf((event as InputEventJoypadMotion).axis_value)
			var sign_out := signf((back as InputEventJoypadMotion).axis_value)
			_expect(sign_in == sign_out, "%s lost its direction." % tag)

	var keycode_only := InputEventKey.new()
	keycode_only.keycode = KEY_K
	for event: InputEvent in [InputEventMouseMotion.new(), keycode_only, InputEventAction.new()]:
		_expect(SettingsScript.encode_event(event).is_empty(),
			"B: %s encoded to something." % event.get_class())
	for text: String in [
		"", "key", "key:", "key:0", "key:-4", "key:abc", "key:69:1", "joy_button:-1",
		"joy_button:999", "joy_button:1.5", "joy_axis:1", "joy_axis:1:x", "joy_axis:99:+",
		"joy_axis:-1:-", "mouse:0", "mouse:99", "pad:1", "touch:1", ":69",
	]:
		_expect(SettingsScript.decode_event(text) == null, "B: '%s' decoded to an input." % text)


func _check_rebind_rules() -> void:
	Harness.stage = "B. rebinding rules"
	_start_clean()
	var actions: Array = _settings.call("get_rebindable_actions")
	var locked: Array[StringName] = [&"cancel", &"pause"]

	# Unsupported inputs and unknown actions.
	var keycode_only := InputEventKey.new()
	keycode_only.keycode = KEY_K
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	for event: InputEvent in [InputEventMouseMotion.new(), mouse, keycode_only]:
		_expect_refused(&"sprint", event, "unsupported", "B: %s on sprint" % event.get_class())
	_expect_refused(&"jump", _key(KEY_K), "unknown_action", "B: an unknown action")
	_expect_refused(&"ui_accept", _key(KEY_K), "unknown_action", "B: a built-in UI action")

	# Esc is never an ordinary binding; the Esc actions keep it.
	for action: Variant in actions:
		if locked.has(StringName(action)):
			continue
		_expect_refused(StringName(action), _key(KEY_ESCAPE), "reserved",
			"B: Esc on %s" % action)
	for action: StringName in locked:
		_expect_refused(action, _key(KEY_K), "reserved", "B: K on %s's keyboard side" % action)
		_expect(not bool(_settings.call("can_rebind", action, &"keyboard")),
			"B: %s's keyboard side is offered for rebinding." % action)
		_expect(bool(_settings.call("can_rebind", action, &"gamepad")),
			"B: %s's controller side is not offered for rebinding." % action)
	_expect_rebound(&"cancel", _joy(JOY_BUTTON_X), "B: cancel on X")
	_expect(_keyboard_keeps_esc(), "B: rebinding cancel's button took Esc away.")
	_settings.call("restore_default_bindings")

	# Conflicts change nothing anywhere.
	var conflicts: Array[Array] = [
		[&"sprint", _key(KEY_E), &"interact"],
		[&"backlog", _key(KEY_W), &"move_forward"],
		[&"toggle_language", _key(KEY_F11), &"toggle_fullscreen"],
		[&"move_left", _motion(JOY_AXIS_LEFT_Y, -1.0), &"move_forward"],
		[&"move_forward", _motion(JOY_AXIS_LEFT_Y, 1.0), &"move_back"],
		[&"sprint", _joy(JOY_BUTTON_START), &"pause"],
		[&"interact", _joy(JOY_BUTTON_B), &"cancel"],
		[&"backlog", _joy(JOY_BUTTON_A), &"interact"],
	]
	for item: Array in conflicts:
		var action: StringName = item[0]
		var event: InputEvent = item[1]
		var tag := "B: %s on %s" % [event.as_text(), action]
		var before := _snapshot()
		var result: Dictionary = _settings.call("rebind", action, event)
		_expect(String(result.get("reason", "")) == "conflict",
			"%s was not refused as a conflict: %s" % [tag, str(result)])
		_expect(StringName(result.get("conflict", &"")) == item[2],
			"%s named %s as the conflict, not %s." % [tag, result.get("conflict"), item[2]])
		_expect(_snapshot() == before, "%s changed the input map although it was refused." % tag)
	_expect(not _read_file().has_section("input"), "B: refused rebindings were saved.")

	# The two shared pairs still share.
	_expect_rebound(&"interact", _key(KEY_SPACE), "B: interact on Space (dialogue's key)")
	_expect(_encoded(&"dialogue_advance").has("key:%d" % KEY_SPACE),
		"B: sharing Space took it away from dialogue_advance.")
	_expect_rebound(&"dialogue_advance", _joy(JOY_BUTTON_X), "B: dialogue_advance on X")
	_expect_rebound(&"interact", _joy(JOY_BUTTON_X), "B: interact on X too")
	_expect_rebound(&"pause", _joy(JOY_BUTTON_B), "B: pause on B (cancel's button)")
	_expect(_encoded(&"cancel").has("joy_button:%d" % JOY_BUTTON_B),
		"B: sharing B took it away from cancel.")
	_expect_refused(&"sprint", _key(KEY_SPACE), "conflict",
		"B: a third action on a shared key")
	_expect_no_conflicts("B: after the shared rebindings")
	_settings.call("restore_default_bindings")


func _check_restore_defaults() -> void:
	Harness.stage = "B. restore defaults"
	_start_clean()
	_expect_rebound(&"sprint", _key(KEY_K), "B: sprint on K")
	_expect_rebound(&"move_forward", _motion(JOY_AXIS_RIGHT_Y, -1.0), "B: forward on RS up")
	_expect_rebound(&"backlog", _joy(JOY_BUTTON_X), "B: the log on X")
	_expect_rebound(&"pause", _joy(JOY_BUTTON_LEFT_SHOULDER), "B: pause on LB")
	_expect(_read_file().has_section("input"), "B: the rebindings were not saved.")
	_settings.call("restore_default_bindings")
	var actions: Array = _settings.call("get_rebindable_actions")
	for action_name: Variant in actions:
		var action := StringName(action_name)
		var declared := _declared(action)
		var live := InputMap.action_get_events(action)
		var tag := "B: after Restore defaults, %s" % action
		if declared.size() != live.size():
			_failures.append("%s has %d inputs, project.godot declares %d." % [
				tag, live.size(), declared.size()
			])
			continue
		for index in declared.size():
			var want := declared[index] as InputEvent
			var have := live[index]
			var same := want.get_class() == have.get_class() \
				and SettingsScript.encode_event(want) == SettingsScript.encode_event(have) \
				and want.device == have.device
			if want is InputEventKey and have is InputEventKey:
				same = same and (want as InputEventKey).keycode == (have as InputEventKey).keycode
			if want is InputEventJoypadMotion and have is InputEventJoypadMotion:
				same = same and is_equal_approx(
					(want as InputEventJoypadMotion).axis_value,
					(have as InputEventJoypadMotion).axis_value
				)
			_expect(same, "%s input %d is %s, project.godot declares %s." % [
				tag, index, have.as_text(), want.as_text()
			])
		_expect(bool(_settings.call("is_default_binding", action)),
			"%s does not report itself as the default." % tag)
	_expect(not _read_file().has_section("input"), "B: Restore defaults left [input] behind.")
	_expect_no_conflicts("B: the shipped defaults")


# --- D. the volume dials ---------------------------------------------------------------


func _check_audio() -> void:
	Harness.stage = "D. volume dials"
	_start_clean()
	for key: StringName in SettingsScript.VOLUME_KEYS:
		if AudioServer.get_bus_index(SettingsScript.VOLUME_BUS[key]) == -1:
			_failures.append("D: there is no %s bus." % SettingsScript.VOLUME_BUS[key])
			return
	_expect_buses("D: every dial at 100", 100, 100, 100)
	var voices_at_full := _voice_levels()
	_expect(not voices_at_full.is_empty(), "D: CueAudio has no voices to measure.")
	var music_dial: float = _music.call("get_volume_db")

	_settings.call("set_volume", &"master", 0)
	_expect_buses("D: Master at 0", 0, 100, 100)
	_expect(is_equal_approx(float(_cues.call("get_gain_db")), 0.0),
		"D: Master at 0 moved the cues' own gain.")
	_settings.call("set_volume", &"master", 80)
	_expect_buses("D: Master back to 80", 80, 100, 100)

	_settings.call("set_volume", &"music", 0)
	_expect_buses("D: Music at 0", 80, 0, 100)
	_expect(is_equal_approx(float(_music.call("get_volume_db")), music_dial),
		"D: the Music dial moved the music player's own level.")
	_settings.call("set_volume", &"music", 55)
	_expect_buses("D: Music back to 55", 80, 55, 100)

	_settings.call("set_volume", &"sfx", 0)
	_expect_buses("D: SFX at 0", 80, 55, 0)
	_expect(float(_cues.call("get_gain_db")) <= -79.9, "D: SFX at 0 left the cues audible.")
	_expect_voices("D: SFX at 0", voices_at_full, -80.0)
	_settings.call("set_volume", &"sfx", 30)
	_expect_buses("D: SFX back to 30", 80, 55, 30)
	_expect(absf(float(_cues.call("get_gain_db")) - linear_to_db(0.3)) < DB_TOLERANCE,
		"D: SFX at 30 put the cues at %.2f dB." % float(_cues.call("get_gain_db")))
	_expect_voices("D: SFX at 30", voices_at_full, linear_to_db(0.3))

	# The next run restores the same levels, from the authored trim, not the live bus.
	var next_run: Node = await _new_settings_node("SettingsAudioRun")
	for pair: Array in [[&"master", 80], [&"music", 55], [&"sfx", 30]]:
		_expect(int(next_run.call("get_volume", pair[0])) == int(pair[1]),
			"D: the next run read %s as %d." % [pair[0], int(next_run.call("get_volume", pair[0]))])
	_expect_buses("D: after a restart", 80, 55, 30)
	next_run.queue_free()
	await _frames(1)

	for key: StringName in SettingsScript.VOLUME_KEYS:
		_settings.call("set_volume", key, 100)
	_expect_buses("D: every dial back at 100", 100, 100, 100)
	_expect_voices("D: SFX back at 100", voices_at_full, 0.0)

	# Routing: cues on Master, music on Music, room tones moved to SFX and only those.
	for child: Node in _cues.get_children():
		if child is AudioStreamPlayer:
			_expect((child as AudioStreamPlayer).bus == &"Master",
				"D: a cue voice is on %s, not Master." % (child as AudioStreamPlayer).bus)
	var music_player: AudioStreamPlayer = _music.call("get_player")
	_expect(music_player != null and music_player.bus == &"Music",
		"D: the music player is not on the Music bus.")
	var room := AmbiencePlayer.new()
	room.name = "RoomToneProbe"
	room.stream = _silent_wav()
	room.bus = &"Master"
	root.add_child(room)
	var plain := AudioStreamPlayer.new()
	plain.name = "PlainPlayerProbe"
	plain.bus = &"Master"
	root.add_child(plain)
	await _frames(1)
	_expect(room.bus == &"SFX", "D: a room tone stayed on %s instead of SFX." % room.bus)
	_expect(plain.bus == &"Master", "D: an ordinary player was moved to %s." % plain.bus)
	room.queue_free()
	plain.queue_free()
	await _frames(1)


# --- C. capturing on the real screen -----------------------------------------------------


func _make_menu() -> void:
	_menu_probe = InputProbe.new()
	_menu_probe.name = "MenuInputProbe"
	_menu_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_menu_probe)
	_game_probe = InputProbe.new()
	_game_probe.name = "GameInputProbe"
	root.add_child(_game_probe)
	# After the probes: input reaches the menu first, as it would in the game.
	_menu = PauseMenu.new()
	root.add_child(_menu)
	await _frames(2)


func _check_capture() -> void:
	Harness.stage = "C. capture"
	_start_clean()
	_settings.call("set_input_device", &"keyboard")
	root.min_size = Vector2i.ZERO
	root.size = CAPTURE_SIZE
	await _frames(3)
	var panel := await _open_settings()
	if panel == null or not panel.is_open():
		_failures.append("C: the settings screen did not open from the pause menu.")
		return
	_clear_probes()

	# A key, from the focused cell.
	await _start_capture_on(panel, &"bind_sprint_keyboard", false)
	_expect(panel.is_capturing(), "C: Enter on sprint's key cell did not start a capture.")
	_expect(panel.get_status_text() == L10n.t("settings.capture_key", {
		"action": L10n.t("settings.action.sprint")
	}), "C: the capture did not say what it is waiting for.")
	await _tap_key(KEY_K)
	await _frames(2)
	_expect(not panel.is_capturing(), "C: the capture kept waiting after K.")
	_expect(_label(&"sprint", &"keyboard") == "K", "C: K did not become sprint's key.")
	_expect_focus(panel, &"bind_sprint_keyboard", "C: after capturing K")
	_expect_no_leak("C: capturing K")

	# Esc cancels, by physical key and by key code alone, and changes nothing.
	for physical: bool in [true, false]:
		var tag := "C: Esc (%s)" % ("physical key" if physical else "key code only")
		await _start_capture_on(panel, &"bind_sprint_keyboard", false)
		if physical:
			await _tap_key(KEY_ESCAPE)
		else:
			var down := InputEventKey.new()
			down.keycode = KEY_ESCAPE
			down.pressed = true
			var up := down.duplicate() as InputEventKey
			up.pressed = false
			await _tap(down, up)
		await _frames(2)
		_expect(not panel.is_capturing(), "%s did not cancel the capture." % tag)
		_expect(panel.is_open() and _menu.is_open(), "%s closed a menu while cancelling." % tag)
		_expect(_label(&"sprint", &"keyboard") == "K", "%s changed the binding." % tag)
		_expect(panel.get_status_text() != L10n.t("settings.refused"),
			"%s was treated as a refused binding, not a cancel." % tag)
		_expect_focus(panel, &"bind_sprint_keyboard", tag)
		_expect_no_leak(tag)

	# The timeout ends a capture by itself.
	await _start_capture_on(panel, &"bind_sprint_keyboard", false)
	await create_timer(SettingsPanel.CAPTURE_SECONDS + 0.5, true, false, true).timeout
	await _frames(1)
	_expect(not panel.is_capturing(), "C: the capture did not time out.")
	_expect(panel.get_status_text() == L10n.t("settings.capture_timeout"),
		"C: the timeout did not say so.")
	_expect(_label(&"sprint", &"keyboard") == "K", "C: the timeout changed the binding.")
	_expect_focus(panel, &"bind_sprint_keyboard", "C: after the timeout")

	# A pad button and both directions of a stick, from the focused cells.
	_settings.call("set_input_device", &"gamepad")
	await _start_capture_on(panel, &"bind_backlog_gamepad", true)
	_expect(panel.is_capturing(), "C: A on the log's button cell did not start a capture.")
	await _tap_pad(JOY_BUTTON_X)
	await _frames(2)
	_expect(_label(&"backlog", &"gamepad") == "X", "C: X did not become the log's button.")
	_expect_focus(panel, &"bind_backlog_gamepad", "C: after capturing X")
	await _start_capture_on(panel, &"bind_sprint_gamepad", true)
	await _tap(_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0), _motion(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	await _frames(2)
	_expect(_encoded(&"sprint").has("joy_axis:%d:+" % JOY_AXIS_TRIGGER_RIGHT),
		"C: RT did not become sprint's input (%s)." % _encoded(&"sprint"))
	await _start_capture_on(panel, &"bind_move_left_gamepad", true)
	await _tap(_motion(JOY_AXIS_RIGHT_X, -0.9), _motion(JOY_AXIS_RIGHT_X, 0.0))
	await _frames(2)
	_expect(_label(&"move_left", &"gamepad") == "RS ←",
		"C: RS left did not become move_left's input (%s)." % _label(&"move_left", &"gamepad"))
	_expect_focus(panel, &"bind_move_left_gamepad", "C: after capturing a stick")
	_expect_no_leak("C: capturing on the pad")

	# The other device during a keyboard capture: nothing stays waiting, nothing leaks.
	_settings.call("set_input_device", &"keyboard")
	var interact_before := _encoded(&"interact")
	var locale_before := L10n.current
	for button: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_BACK, JOY_BUTTON_START]:
		var tag := "C: pad %s during a keyboard capture" % SettingsScript.JOY_BUTTON_NAMES[button]
		await _reset_capture(panel)
		await _start_capture_on(panel, &"bind_interact_keyboard", false)
		await _tap_pad(button)
		await _frames(2)
		_expect(not panel.is_capturing(), "%s left the capture waiting." % tag)
		_expect_focus(panel, &"bind_interact_keyboard", tag)
		_expect(_encoded(&"interact") == interact_before, "%s changed interact." % tag)
		_expect(L10n.current == locale_before, "%s switched the language." % tag)
		_expect(panel.is_open() and _menu.is_open(), "%s closed a menu." % tag)
		_expect_no_leak(tag)

	# A click during a controller capture is not a binding and not a new capture.
	await _reset_capture(panel)
	await _start_capture_on(panel, &"bind_backlog_gamepad", true)
	await _click(panel.get_row_control(&"bind_backlog_keyboard"))
	await _frames(2)
	_expect(panel.is_capturing(), "C: a click ended the controller capture.")
	_expect(panel.get_status_text() == L10n.t("settings.capture_pad", {
		"action": L10n.t("settings.action.backlog")
	}), "C: a click replaced the controller capture with another one.")
	_expect_focus(panel, &"bind_backlog_gamepad", "C: a click during a controller capture")
	await _tap_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not panel.is_capturing(), "C: Esc did not cancel the controller capture.")
	_expect_no_leak("C: a click during a controller capture")

	# Choices and dials by pad and by keyboard alone.
	panel.focus_row(&"text_speed")
	await _frames(1)
	await _tap_pad(JOY_BUTTON_DPAD_RIGHT)
	_expect(_settings.call("get_text_speed") == &"fast", "C: D-pad right did not change speed.")
	await _tap_key(KEY_LEFT)
	_expect(_settings.call("get_text_speed") == &"normal", "C: Left did not change speed back.")
	panel.focus_row(&"volume_music")
	await _frames(1)
	# A slider also asks the `Input` singleton whether a pad direction was just pressed (it
	# repeats while held), and `push_input` does not touch that state; a real press does.
	Input.action_press(&"ui_left")
	await _tap_pad(JOY_BUTTON_DPAD_LEFT)
	Input.action_release(&"ui_left")
	_expect(int(_settings.call("get_volume", &"music")) == 95, "C: D-pad left did not lower music.")
	await _tap_key(KEY_RIGHT)
	_expect(int(_settings.call("get_volume", &"music")) == 100, "C: Right did not raise music.")

	# Closing the menu in the middle of a capture traps nothing.
	await _start_capture_on(panel, &"bind_sprint_keyboard", false)
	_menu.close()
	await _frames(2)
	_expect(not panel.is_open() and not panel.is_capturing(),
		"C: closing the pause menu left the settings screen capturing.")
	_expect(not paused, "C: closing the pause menu left the game paused.")
	_clear_probes()
	await _tap_key(KEY_E)
	await _tap_pad(JOY_BUTTON_A)
	_expect(_game_probe.count(&"interact") == 2,
		"C: after the menus closed the game saw %s." % _game_probe.describe())

	# The menus answer the keyboard alone and the pad alone afterwards.
	await _tap_key(KEY_ESCAPE)
	_expect(_menu.is_open(), "C: Esc did not open the pause menu after a capture.")
	await _tap_key(KEY_DOWN)
	await _tap_key(KEY_ENTER)
	await _frames(2)
	_expect(panel.is_open(), "C: Down, Enter did not open the settings screen.")
	_expect(not panel.is_capturing(), "C: the settings screen reopened capturing.")
	await _tap_key(KEY_ESCAPE)
	await _frames(2)
	_expect(not panel.is_open() and _menu.is_open(), "C: Esc did not close only the settings.")
	_expect(_focused() == _menu.get_entry(&"settings"), "C: closing settings lost the focus.")
	await _tap_key(KEY_ESCAPE)
	_expect(not _menu.is_open(), "C: Esc did not close the pause menu.")
	await _tap_pad(JOY_BUTTON_START)
	_expect(_menu.is_open(), "C: Start did not open the pause menu.")
	await _tap_pad(JOY_BUTTON_DPAD_DOWN)
	await _tap_pad(JOY_BUTTON_A)
	await _frames(2)
	_expect(panel.is_open(), "C: D-pad down, A did not open the settings screen.")
	await _tap_pad(JOY_BUTTON_B)
	await _frames(2)
	_expect(not panel.is_open() and _menu.is_open(), "C: B did not close only the settings.")
	await _tap_pad(JOY_BUTTON_B)
	_expect(not _menu.is_open() and not paused, "C: B did not close the pause menu.")
	_settings.call("restore_default_bindings")


# --- E. accessibility of the screen ----------------------------------------------------


func _check_layout() -> void:
	_start_clean()
	for size: Vector2i in LAYOUT_SIZES:
		root.min_size = Vector2i.ZERO
		root.size = size
		await _frames(3)
		var viewport := root.get_visible_rect().size
		_expect(Vector2i(viewport) == size, "E: the viewport is %s, not %s." % [viewport, size])
		for locale: String in LOCALES:
			_loc.call("set_locale", locale)
			for text_size: StringName in SettingsScript.TEXT_SIZES:
				_settings.call("set_text_size", text_size)
				for speed: StringName in SettingsScript.TEXT_SPEEDS:
					_settings.call("set_text_speed", speed)
					var tag := "E: %dx%d, %s, %s text, %s speed" % [
						size.x, size.y, locale, text_size, speed
					]
					Harness.stage = tag
					var panel := await _open_settings()
					if panel == null or not panel.is_open():
						_failures.append("%s: the settings screen did not open." % tag)
						continue
					_check_panel_state(panel, tag, text_size, speed, viewport)
					if speed == &"normal":
						await _check_reachable(panel, tag)
					if speed == &"normal" and text_size == &"largest":
						await _check_focus_walk(panel, tag, false)
						await _check_focus_walk(panel, tag, true)
					panel.close()
					_menu.close()
					await _frames(1)
	_loc.call("set_locale", "en")


func _check_panel_state(
	panel: SettingsPanel, tag: String, text_size: StringName, speed: StringName, viewport: Vector2
) -> void:
	var box := panel.get_panel().get_global_rect()
	_expect(
		box.position.x >= -0.5 and box.position.y >= -0.5
		and box.end.x <= viewport.x + 0.5 and box.end.y <= viewport.y + 0.5,
		"%s: the panel %s is not inside the viewport." % [tag, box]
	)
	_expect(_choice_value(panel, &"text_size") == String(text_size),
		"%s: the text size row shows %s." % [tag, _choice_value(panel, &"text_size")])
	_expect(_choice_value(panel, &"text_speed") == String(speed),
		"%s: the text speed row shows %s." % [tag, _choice_value(panel, &"text_speed")])
	_expect(_choice_value(panel, &"language") == L10n.current,
		"%s: the language row shows %s." % [tag, _choice_value(panel, &"language")])
	var cps := float(_settings.call("reveal_characters_per_second"))
	_expect(is_equal_approx(cps, float(SettingsScript.TEXT_SPEED_CPS[speed])),
		"%s: the reveal runs at %.0f characters per second." % [tag, cps])
	var factor := float(SettingsScript.TEXT_SIZE_SCALE[text_size])
	var cell := panel.get_row_control(&"bind_interact_keyboard") as Button
	_expect(cell != null and cell.get_theme_font_size(&"font_size")
		== UiTextScale.scaled(MenuStyle.BODY_SIZE, factor),
		"%s: the binding cells are not drawn at the chosen size." % tag)
	_expect_focus(panel, &"text_size", "%s, on opening" % tag)


## Every row the focus can stop on is scrolled fully into view when it gets the focus.
func _check_reachable(panel: SettingsPanel, tag: String) -> void:
	var area := panel.get_scroll().get_global_rect()
	for id: StringName in _focusable_ids(panel):
		panel.focus_row(id)
		await _frames(3)
		var control := panel.get_row_control(id)
		var box := control.get_global_rect()
		_expect(_focused() == control, "%s: %s does not take the focus." % [tag, id])
		if not panel.get_scroll().is_ancestor_of(control):
			continue
		_expect(
			box.position.y >= area.position.y - 1.0 and box.end.y <= area.end.y + 1.0,
			"%s: %s %s is not scrolled into the list %s." % [tag, id, box, area]
		)


## Breadth-first over what the arrows (and Tab) or the D-pad actually do from every row:
## every row is reached and the focus never lands behind the modal.
func _check_focus_walk(panel: SettingsPanel, tag: String, pad: bool) -> void:
	var how := "the D-pad" if pad else "the keyboard"
	var wanted := _focusable_ids(panel)
	var visited: Dictionary = {&"text_size": true}
	var queue: Array[StringName] = [&"text_size"]
	var escapes: Array[String] = []
	while not queue.is_empty():
		var id: StringName = queue.pop_front()
		for move: String in _moves(id, pad):
			panel.focus_row(id)
			await process_frame
			await _move(move, pad)
			var owner_control := _focused()
			if owner_control == null or not panel.is_ancestor_of(owner_control):
				escapes.append("%s from %s -> %s" % [
					move, id, owner_control.name if owner_control != null else "nothing"
				])
				continue
			var reached := _row_id(panel, owner_control)
			if not String(reached).is_empty() and not visited.has(reached):
				visited[reached] = true
				queue.append(reached)
	_expect(escapes.is_empty(), "%s: with %s the focus left the settings screen: %s" % [
		tag, how, "; ".join(escapes)
	])
	var missed: Array[String] = []
	for id: StringName in wanted:
		if not visited.has(id):
			missed.append(String(id))
	_expect(missed.is_empty(), "%s: %s never reaches %s." % [tag, how, ", ".join(missed)])


func _moves(id: StringName, pad: bool) -> Array[String]:
	var out: Array[String] = ["up", "down"]
	# ←/→ change a choice or a dial; on the other rows they move between cells.
	if String(id).begins_with("bind_") or id == &"restore_bindings" or id == &"back":
		out.append_array(["left", "right"])
	if not pad:
		out.append_array(["next", "previous"])
	return out


func _move(move: String, pad: bool) -> void:
	if pad:
		var buttons := {
			"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
			"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
		}
		await _tap_pad(buttons[move])
		return
	var keys := {
		"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"next": KEY_TAB, "previous": KEY_TAB,
	}
	await _tap_key(keys[move], move == "previous")


# --- helpers ----------------------------------------------------------------------------


func _open_settings() -> SettingsPanel:
	if not _menu.is_open():
		_menu.open()
		await _frames(2)
	_menu.activate(&"settings")
	await _frames(3)
	return _menu.get_settings_panel()


func _start_capture_on(panel: SettingsPanel, id: StringName, pad: bool) -> void:
	panel.focus_row(id)
	await _frames(1)
	if pad:
		await _tap_pad(JOY_BUTTON_A)
	else:
		await _tap_key(KEY_ENTER)
	await _frames(1)


## Ends whatever a failed step left waiting, so one failure does not cascade.
func _reset_capture(panel: SettingsPanel) -> void:
	if panel.is_capturing():
		panel.close()
		await _frames(1)
		await _open_settings()
	_clear_probes()


func _expect_focus(panel: SettingsPanel, id: StringName, tag: String) -> void:
	var owner_control := _focused()
	_expect(owner_control == panel.get_row_control(id), "%s: the focus is on %s, not %s." % [
		tag, owner_control.name if owner_control != null else "nothing", id
	])


func _expect_no_leak(tag: String) -> void:
	_expect(_menu_probe.events.is_empty(), "%s: input leaked past the settings screen: %s" % [
		tag, _menu_probe.describe()
	])
	_clear_probes()


func _clear_probes() -> void:
	_menu_probe.events.clear()
	_game_probe.events.clear()


func _focusable_ids(panel: SettingsPanel) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in panel.get_row_ids():
		var control := panel.get_row_control(id)
		if control != null and control.focus_mode != Control.FOCUS_NONE \
				and control.is_visible_in_tree():
			out.append(id)
	return out


func _row_id(panel: SettingsPanel, control: Control) -> StringName:
	for id: StringName in panel.get_row_ids():
		if panel.get_row_control(id) == control:
			return id
	return StringName()


func _choice_value(panel: SettingsPanel, id: StringName) -> String:
	var button := panel.get_row_control(id) as Button
	if button == null:
		return ""
	var options: Array = button.get_meta(&"options", [])
	var index := int(button.get_meta(&"index", -1))
	if index < 0 or index >= options.size():
		return ""
	return String((options[index] as Dictionary).get("value", ""))


func _expect_values(node: Node, tag: String, choices: Array, volumes: Array) -> void:
	var have := [node.call("get_text_size"), node.call("get_text_speed"), node.call("get_ui_scale")]
	for index in choices.size():
		_expect(StringName(have[index]) == StringName(choices[index]),
			"%s: %s, expected %s." % [tag, have, choices])
	for index in SettingsScript.VOLUME_KEYS.size():
		var key: StringName = SettingsScript.VOLUME_KEYS[index]
		_expect(int(node.call("get_volume", key)) == int(volumes[index]),
			"%s: %s volume is %d, expected %d." % [
				tag, key, int(node.call("get_volume", key)), int(volumes[index])
			])


func _expect_foreign_keys(tag: String, locale: String) -> void:
	var config := _read_file()
	_expect(String(config.get_value("display", "locale", "")) == locale,
		"%s: [display] locale is '%s', not '%s'." % [
			tag, config.get_value("display", "locale", ""), locale
		])
	_expect(String(config.get_value("mods", "palette", "")) == "warm",
		"%s: a section Settings does not own was dropped." % tag)
	_expect(int(config.get_value("display", "window_hint", 0)) == 3,
		"%s: an unknown key in [display] was dropped." % tag)


func _expect_buses(tag: String, master: int, music: int, sfx: int) -> void:
	var levels := {&"master": master, &"music": music, &"sfx": sfx}
	for key: StringName in SettingsScript.VOLUME_KEYS:
		var index := AudioServer.get_bus_index(SettingsScript.VOLUME_BUS[key])
		var percent := int(levels[key])
		var want := -80.0 if percent <= 0 else float(BUS_TRIM_DB[key]) + linear_to_db(percent / 100.0)
		var have := AudioServer.get_bus_volume_db(index)
		_expect(absf(have - want) < DB_TOLERANCE, "%s: the %s bus is at %.2f dB, not %.2f." % [
			tag, key, have, want
		])
		_expect(AudioServer.is_bus_mute(index) == (percent <= 0), "%s: the %s bus is %s." % [
			tag, key, "muted" if AudioServer.is_bus_mute(index) else "not muted"
		])
		_expect(int(_settings.call("get_volume", key)) == percent,
			"%s: Settings reports %s at %d." % [tag, key, int(_settings.call("get_volume", key))])


func _voice_levels() -> Array[float]:
	var out: Array[float] = []
	for child: Node in _cues.get_children():
		if child is AudioStreamPlayer:
			out.append((child as AudioStreamPlayer).volume_db)
	return out


func _expect_voices(tag: String, at_full: Array[float], gain: float) -> void:
	var now := _voice_levels()
	_expect(now.size() == at_full.size(), "%s: the cue voices changed in number." % tag)
	for index in mini(now.size(), at_full.size()):
		_expect(absf(now[index] - (at_full[index] + gain)) < DB_TOLERANCE,
			"%s: cue voice %d is at %.2f dB, not %.2f." % [
				tag, index, now[index], at_full[index] + gain
			])


func _silent_wav() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	return wav


func _expect_refused(action: StringName, event: InputEvent, reason: String, tag: String) -> void:
	var before := _snapshot()
	var result: Dictionary = _settings.call("rebind", action, event)
	_expect(not bool(result.get("ok", true)) and String(result.get("reason", "")) == reason,
		"%s was not refused as '%s': %s" % [tag, reason, str(result)])
	_expect(_snapshot() == before, "%s changed the input map although it was refused." % tag)


func _expect_rebound(action: StringName, event: InputEvent, tag: String) -> void:
	var result: Dictionary = _settings.call("rebind", action, event)
	_expect(bool(result.get("ok", false)), "%s was refused: %s" % [tag, str(result)])
	_expect(_encoded(action).has(SettingsScript.encode_event(event)),
		"%s did not reach the input map (%s)." % [tag, _encoded(action)])


## No two rebindable actions share an input, apart from the two pairs that may.
func _expect_no_conflicts(tag: String) -> void:
	var actions: Array = _settings.call("get_rebindable_actions")
	for first_index in actions.size():
		for second_index in range(first_index + 1, actions.size()):
			var first := StringName(actions[first_index])
			var second := StringName(actions[second_index])
			if _shared(first, second):
				continue
			for code: String in _encoded(first):
				_expect(not _encoded(second).has(code), "%s: %s and %s both use %s." % [
					tag, first, second, code
				])


func _shared(first: StringName, second: StringName) -> bool:
	for pair: Array in SettingsScript.SHARED_PAIRS:
		if pair.has(first) and pair.has(second):
			return true
	return false


func _keyboard_keeps_esc() -> bool:
	var esc := "key:%d" % KEY_ESCAPE
	return _encoded(&"cancel").has(esc) and _encoded(&"pause").has(esc)


func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for action: Variant in (_settings.call("get_rebindable_actions") as Array):
		out[action] = _encoded(StringName(action))
	return out


func _encoded(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for event: InputEvent in InputMap.action_get_events(action):
		out.append(SettingsScript.encode_event(event))
	return out


func _declared(action: StringName) -> Array:
	var declared: Variant = ProjectSettings.get_setting("input/%s" % action, null)
	if declared is Dictionary:
		return ((declared as Dictionary).get("events", []) as Array)
	return []


func _declared_encoded(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for event: Variant in _declared(action):
		out.append(SettingsScript.encode_event(event as InputEvent))
	return out


func _label(action: StringName, device: StringName) -> String:
	return String(_settings.call("binding_label", action, device))


func _mentions(problems: Array, word: String) -> bool:
	for problem: Variant in problems:
		if String(problem).contains(word):
			return true
	return false


func _new_settings_node(node_name: String) -> Node:
	var node: Node = SettingsScript.new()
	node.name = node_name
	root.add_child(node)
	await _frames(1)
	return node


## Defaults everywhere, no file, English: every check starts from a first run.
func _start_clean() -> void:
	L10n.set_locale("en")
	_remove_file()
	_settings.call("load_settings")


func _read_file() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return config


func _remove_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _backup_settings() -> void:
	_had_file = FileAccess.file_exists(SETTINGS_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings() -> void:
	if _restored:
		return
	_restored = true
	if _had_file:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_backup)
			file.close()
	else:
		_remove_file()


func _file_matches_backup() -> bool:
	if not _had_file:
		return not FileAccess.file_exists(SETTINGS_PATH)
	return FileAccess.get_file_as_bytes(SETTINGS_PATH) == _backup


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


func _joy(button: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	return event


func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _tap(down: InputEvent, up: InputEvent) -> void:
	root.push_input(down)
	await process_frame
	root.push_input(up)
	await process_frame


func _tap_key(code: Key, shift: bool = false) -> void:
	var down := _key(code)
	var up := _key(code, false)
	down.shift_pressed = shift
	up.shift_pressed = shift
	await _tap(down, up)


func _tap_pad(button: JoyButton) -> void:
	await _tap(_joy(button), _joy(button, false))


func _click(control: Control) -> void:
	if control == null:
		_failures.append("C: nothing to click.")
		return
	var at := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event)
		await process_frame


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
