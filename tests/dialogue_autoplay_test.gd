extends SceneTree
## Auto-advance, "skip read text", the read log and the reading progress.
##
##     godot --headless --path . --script res://tests/dialogue_autoplay_test.gd
##
## A. **The read log on its own** (`ReadLog`, a scratch path). It round-trips; it never
##    marks an identity that is not stable; a clean log does not write; a damaged file is
##    moved aside to `.broken` (not deleted) and the game carries on empty; a write that
##    stopped after the temporary file was written is finished on the next load; a wrong
##    version and a list with a bad entry are reported, not crashed on.
## B. **How long auto waits.** Longer text waits longer, a CJK character longer than a
##    Latin letter, slow > normal > fast, markup is not read, and a visible check adds time.
## C. **Reading progress.** Counted from the shipped content (cross-checked here by reading
##    the JSON directly), repeat reads left out, rounded down, and worded in both languages.
##    The "unread text left in" line names only areas the player has started.
## D. **Settings.** The auto speed, skip scope and skip key mode default, persist, refuse
##    nonsense and announce a change; the two new actions are rebindable on both devices and
##    their defaults clash with nothing.
## E. **The real conversation.** In `main.tscn`, with a fresh read log: holding skip on
##    unread text does nothing and says why; auto reads `n_class` up to its choice and waits
##    there; the second time through, skip runs to the choice on its own and stops there;
##    the log pauses auto; the auto key toggles it; the HUD says what is going on; the
##    notebook's progress line moves; and the log is written to its own file, not the save.
##    In "toggle" mode one press of the skip key runs to the choice and ends there. The
##    settings screen's "clear reading history" takes two presses and empties the live log.

const Harness = preload("res://tests/test_harness.gd")
const SettingsScript = preload("res://scripts/autoload/settings_manager.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const LOC_SCRIPT := "res://scripts/i18n/loc.gd"
const SCRATCH := "user://read_lines_test.json"
const LIVE_LOG := "user://read_lines_e2e_test.json"
const MAX_STEPS := 80
const CONVERSATION := &"n_class"

var _failures: Array[String] = []
var _settings: Node = null
var _main: Node = null
var _dialogue: DialogueController = null
var _autoplay: DialogueAutoplay = null
var _panel: DialoguePanel = null
var _backlog: BacklogPanel = null
var _hud: GameHud = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "dialogue_autoplay_test.gd")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	await _frames(2)
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	Harness.ensure_autoload(self, "Loc", LOC_SCRIPT)
	_settings = Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if _settings == null:
		Harness.finish(self, ["The Settings autoload is unavailable."], "")
		return
	_settings.call("reset_to_defaults")
	L10n.load_tables()
	L10n.set_locale("en")

	_check_read_log()
	_check_hold_seconds()
	_check_reading_progress()
	_check_settings()
	await _check_real_conversation()

	if _main != null:
		_main.queue_free()
		# The autoplay writes its log on leaving the tree; let it, then clean up.
		await _frames(3)
	for path: String in [SCRATCH, LIVE_LOG]:
		ReadLog.new(path).forget()
		_remove("%s.broken" % path)
	_settings.call("reset_to_defaults")
	Engine.time_scale = 1.0
	await _frames(2)
	Harness.finish(
		self, _failures,
		"the read log survives damage, auto waits for the text and stops at choices, skip passes "
		+ "only read text and says why it stops, and progress counts the shipped lines."
	)


# --- A. The read log ----------------------------------------------------------------


func _check_read_log() -> void:
	Harness.stage = "A. read log"
	_clean(SCRATCH)
	var fresh := ReadLog.open(SCRATCH)
	_expect(fresh.size() == 0 and fresh.get_problems().is_empty(),
		"A: a log with no file is not empty and clean: %s" % str(fresh.get_problems()))
	_expect(fresh.flush() and fresh.writes == 0, "A: a clean log wrote a file.")
	_expect(not FileAccess.file_exists(SCRATCH), "A: a clean log created its file.")

	_expect(fresh.mark("conv:n_class/start"), "A: a conversation line was not marked.")
	_expect(fresh.mark("inspection:desk/first"), "A: an inspection line was not marked.")
	_expect(not fresh.mark("conv:n_class/start"), "A: a line was marked read twice.")
	for unstable: String in ["unidentified:protagonist", "", "conv:", "inspection:", "free text"]:
		_expect(not fresh.mark(unstable), "A: '%s' was marked although it is not stable." % unstable)
	_expect(fresh.size() == 2, "A: the log holds %d lines, not 2." % fresh.size())
	_expect(fresh.flush() and fresh.writes == 1, "A: the first flush did not write once.")
	_expect(fresh.flush() and fresh.writes == 1, "A: a second flush with nothing new wrote again.")
	_expect(not FileAccess.file_exists("%s.tmp" % SCRATCH), "A: a flush left its .tmp behind.")

	var again := ReadLog.open(SCRATCH)
	_expect(again.has_read("conv:n_class/start") and again.has_read("inspection:desk/first"),
		"A: the log did not round-trip: %s" % str(again.get_identities()))
	_expect(not again.has_read("conv:n_class/other"), "A: an unread line came back read.")
	_expect(again.count_read(["conv:n_class/start", "conv:x/y", &"inspection:desk/first"]) == 2,
		"A: count_read did not count the two read lines.")

	# Damage: moved aside, never deleted, reported, and the game carries on empty.
	_write(SCRATCH, "{\"version\": 1, \"lines\": [")
	var damaged := ReadLog.open(SCRATCH)
	_expect(damaged.size() == 0, "A: a damaged log still claimed %d lines." % damaged.size())
	_expect(not damaged.get_problems().is_empty(), "A: a damaged log was not reported.")
	_expect(FileAccess.file_exists("%s.broken" % SCRATCH), "A: the damaged bytes were not kept.")
	_expect(not FileAccess.file_exists(SCRATCH), "A: the damaged file is still in the way.")
	damaged.mark("conv:a/b")
	_expect(damaged.flush() and ReadLog.open(SCRATCH).has_read("conv:a/b"),
		"A: a log that started from damage could not be written again.")

	# Wrong version, wrong shape and a bad entry.
	_write(SCRATCH, JSON.stringify({"version": 9, "lines": ["conv:a/b"]}))
	var future := ReadLog.open(SCRATCH)
	_expect(future.size() == 0 and not future.get_problems().is_empty(),
		"A: a log from another format version was accepted.")
	_write(SCRATCH, JSON.stringify(["conv:a/b"]))
	_expect(ReadLog.open(SCRATCH).size() == 0, "A: a JSON list was read as a log.")
	_write(SCRATCH, JSON.stringify({"version": 1, "lines": ["conv:a/b", 7, "unidentified:x"]}))
	var partial := ReadLog.open(SCRATCH)
	_expect(partial.has_read("conv:a/b") and partial.size() == 1,
		"A: one bad entry threw away the good one, or was kept: %s" % str(partial.get_identities()))
	_expect(partial.get_problems().size() == 1 and FileAccess.file_exists(SCRATCH),
		"A: bad entries were not reported once, or the file was set aside for them.")

	# A write interrupted after the temporary file was complete and the old one removed.
	_clean(SCRATCH)
	_write("%s.tmp" % SCRATCH, JSON.stringify({"version": 1, "lines": ["conv:c/d"]}))
	var recovered := ReadLog.open(SCRATCH)
	_expect(recovered.has_read("conv:c/d"), "A: the finished temporary file was not recovered.")
	_expect(FileAccess.file_exists(SCRATCH) and not FileAccess.file_exists("%s.tmp" % SCRATCH),
		"A: recovering did not finish the interrupted swap.")

	recovered.forget()
	_expect(not FileAccess.file_exists(SCRATCH) and recovered.size() == 0,
		"A: forget left the file or the lines behind.")
	_clean(SCRATCH)


# --- B. How long auto waits ---------------------------------------------------------


func _check_hold_seconds() -> void:
	Harness.stage = "B. hold time"
	var short := DialogueAutoplay.hold_seconds("Okay.")
	var long := DialogueAutoplay.hold_seconds(
		"The corridor is longer than it was this morning, and the light at the end of it "
		+ "has not moved at all."
	)
	_expect(long > short + 2.0, "B: a long line waits %.2f s, a short one %.2f s." % [long, short])
	var latin := DialogueAutoplay.hold_seconds("abcdefghij")
	var cjk := DialogueAutoplay.hold_seconds("走廊比早上长了很多啊")
	_expect(cjk > latin, "B: ten CJK characters (%.2f s) do not wait longer than ten letters (%.2f s)."
		% [cjk, latin])
	var text := "她把书包挂在椅背上，没有回头。"
	var slow := DialogueAutoplay.hold_seconds(text, &"slow")
	var normal := DialogueAutoplay.hold_seconds(text, &"normal")
	var fast := DialogueAutoplay.hold_seconds(text, &"fast")
	_expect(slow > normal and normal > fast,
		"B: slow/normal/fast wait %.2f/%.2f/%.2f s." % [slow, normal, fast])
	_expect(is_equal_approx(DialogueAutoplay.hold_seconds(text, &"nonsense"), normal),
		"B: an unknown speed is not read as normal.")
	_expect(is_equal_approx(DialogueAutoplay.hold_seconds("[b]Okay.[/b]"), short),
		"B: markup was counted as text to read.")
	_expect(fast > 0.5, "B: even fast auto does not leave a moment on an empty line.")
	_expect(DialogueAutoplay.is_cjk("字".unicode_at(0)) and DialogueAutoplay.is_cjk("。".unicode_at(0))
		and not DialogueAutoplay.is_cjk("a".unicode_at(0)), "B: is_cjk is wrong.")


# --- C. Reading progress ------------------------------------------------------------


func _check_reading_progress() -> void:
	Harness.stage = "C. progress"
	var abilities := InnerAbilities.load_all()
	var dialogue := DialogueLibrary.load_all(abilities)
	var inspections := InspectionLibrary.load_all()
	var identities := ReadingProgress.identities(dialogue, inspections)
	var unique: Dictionary = {}
	for identity: String in identities:
		unique[identity] = true
	_expect(unique.size() == identities.size(), "C: the content counts a line twice.")
	for identity: String in identities:
		if not ReadLog.is_stable(identity) or identity.ends_with("/repeat"):
			_failures.append("C: '%s' is counted as a line." % identity)
			break
	var expected := _content_identities()
	var missing: Array[String] = []
	for identity: String in expected:
		if not unique.has(identity):
			missing.append(identity)
	_expect(missing.is_empty(), "C: shipped lines are not counted: %s" % ", ".join(missing.slice(0, 5)))
	_expect(identities.size() == expected.size(),
		"C: %d lines counted, the content has %d." % [identities.size(), expected.size()])

	var read_log := ReadLog.new(SCRATCH)
	_expect(ReadingProgress.measure(read_log, identities)["percent"] == 0, "C: nothing read is not 0%.")
	_expect(ReadingProgress.measure(null, identities)["read"] == 0, "C: no log is not nothing read.")
	if identities.size() >= 3:
		read_log.mark(identities[0])
		read_log.mark("inspection:never_shipped/first")
		var progress := ReadingProgress.measure(read_log, identities)
		_expect(int(progress["read"]) == 1, "C: a line the content does not have was counted.")
		var all_but_one := ReadLog.new(SCRATCH)
		for index in identities.size() - 1:
			all_but_one.mark(identities[index])
		_expect(ReadingProgress.measure(all_but_one, identities)["percent"] < 100,
			"C: all but one line rounds up to 100%.")
		for identity: String in identities:
			all_but_one.mark(identity)
		_expect(ReadingProgress.measure(all_but_one, identities)["percent"] == 100,
			"C: every line read is not 100%.")
	_check_areas(dialogue, inspections, identities)
	var sample := {"read": 3, "total": 12, "percent": 25}
	for locale: String in ["en", "zh-CN"]:
		L10n.set_locale(locale)
		var words := ReadingProgress.describe(sample)
		_expect(words.contains("25") and words.contains("12") and not words.contains("{"),
			"C: the %s progress line reads '%s'." % [locale, words])
	L10n.set_locale("en")
	_expect(ReadingProgress.describe({}).is_empty(), "C: no content still printed a progress line.")


func _check_areas(
	dialogue: DialogueLibrary, inspections: InspectionLibrary, identities: Array[String]
) -> void:
	var by_area := ReadingProgress.identities_by_area(dialogue, inspections)
	var filed := 0
	for area: String in by_area.keys():
		filed += (by_area[area] as Array).size()
		_expect(area.is_empty() or ReadingProgress.AREAS.has(area), "C: unknown area '%s'." % area)
	_expect(filed == identities.size(), "C: %d lines filed by area, %d counted." % [
		filed, identities.size()
	])
	_expect(ReadingProgress.area_of_chapter("prologue") == "classroom"
		and ReadingProgress.area_of_chapter("inner_voice") == "inner_voice"
		and ReadingProgress.area_of_chapter("laboratory").is_empty(),
		"C: chapters are not filed under the right areas.")
	var classroom: Array = by_area.get("classroom", [])
	var corridor: Array = by_area.get("corridor", [])
	if classroom.size() < 2 or corridor.is_empty():
		_failures.append("C: the classroom or corridor has no lines to count.")
		return
	var read_log := ReadLog.new(SCRATCH)
	_expect(ReadingProgress.unfinished_areas(read_log, by_area).is_empty(),
		"C: with nothing read, an area was named (a spoiler).")
	read_log.mark(String(classroom[0]))
	var rows := ReadingProgress.unfinished_areas(read_log, by_area)
	_expect(rows.size() == 1 and rows[0]["area"] == "classroom"
		and int(rows[0]["total"]) - int(rows[0]["read"]) == classroom.size() - 1,
		"C: one classroom line read gave %s." % str(rows))
	for identity: Variant in classroom:
		read_log.mark(String(identity))
	_expect(ReadingProgress.unfinished_areas(read_log, by_area).is_empty(),
		"C: a finished area is still listed as unfinished.")
	read_log.mark(String(corridor[0]))
	var progress := ReadingProgress.measure(read_log, identities, by_area)
	L10n.set_locale("en")
	var words := ReadingProgress.describe(progress)
	_expect(words.contains("\n") and words.contains(L10n.t("place.corridor"))
		and not words.contains(L10n.t("place.classroom")) and not words.contains("{"),
		"C: the progress lines read '%s'." % words)
	var many: Array[Dictionary] = []
	for area: String in ReadingProgress.AREAS:
		many.append({"area": area, "read": 1, "total": 3})
	var listed := ReadingProgress.describe_areas(many)
	_expect(listed.contains(str(many.size() - ReadingProgress.AREAS_LISTED)),
		"C: more areas than fit are not summarised: '%s'." % listed)
	_expect(ReadingProgress.describe_areas([{"area": "", "read": 1, "total": 2}]).is_empty(),
		"C: content without an area was named.")


## Every line the shipped content can show, read from the JSON directly.
func _content_identities() -> Array[String]:
	var out: Array[String] = []
	for chapter: String in DialogueLibrary.CHAPTERS:
		var data: Variant = _json("res://data/dialogue/en/%s.json" % chapter)
		if not data is Dictionary:
			continue
		var conversations: Variant = (data as Dictionary).get("conversations", {})
		if not conversations is Dictionary:
			continue
		for conversation_id: Variant in (conversations as Dictionary).keys():
			var conversation: Variant = (conversations as Dictionary)[conversation_id]
			if not conversation is Dictionary:
				continue
			for node: Variant in (conversation as Dictionary).get("nodes", []):
				if node is Dictionary and not String((node as Dictionary).get("text", "")) \
						.strip_edges().is_empty():
					out.append("conv:%s/%s" % [conversation_id, (node as Dictionary).get("id", "")])
	var inspections := InspectionLibrary.load_all()
	for inspection_id: StringName in inspections.get_ids("en"):
		var inspection := inspections.get_inspection_in("en", inspection_id)
		if not inspection.text.strip_edges().is_empty():
			out.append("inspection:%s/first" % inspection_id)
		if not inspection.recall_text.strip_edges().is_empty():
			out.append("inspection:%s/recall" % inspection_id)
	return out


# --- D. Settings --------------------------------------------------------------------


func _check_settings() -> void:
	Harness.stage = "D. settings"
	_settings.call("reset_to_defaults")
	_expect(_settings.call("get_auto_speed") == &"normal", "D: auto speed does not default to normal.")
	_expect(_settings.call("get_skip_scope") == &"read", "D: skip does not default to read text.")
	_expect(_settings.call("get_skip_mode") == &"hold", "D: the skip key does not default to hold.")
	_settings.call("set_skip_mode", &"toggle")
	_settings.call("set_skip_mode", &"sometimes")
	_settings.call("load_settings")
	_expect(_settings.call("get_skip_mode") == &"toggle", "D: the skip key mode did not persist.")
	_settings.call("reset_to_defaults")
	var heard: Array[StringName] = []
	var listener := func(key: StringName) -> void: heard.append(key)
	_settings.connect("setting_changed", listener)
	_settings.call("set_auto_speed", &"fast")
	_settings.call("set_skip_scope", &"all")
	_settings.call("set_auto_speed", &"warp")
	_settings.call("set_skip_scope", &"everything")
	_settings.call("set_auto_speed", &"fast")
	_settings.disconnect("setting_changed", listener)
	_expect(heard == [&"auto_speed", &"skip_scope"],
		"D: the changes announced %s, not one auto_speed and one skip_scope." % str(heard))
	_settings.call("load_settings")
	_expect(_settings.call("get_auto_speed") == &"fast" and _settings.call("get_skip_scope") == &"all",
		"D: the auto speed or skip scope did not persist.")
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("text", "auto_speed", "ludicrous")
	config.set_value("text", "skip", 3)
	config.save("user://settings.cfg")
	_settings.call("load_settings")
	_expect(_settings.call("get_auto_speed") == &"normal" and _settings.call("get_skip_scope") == &"read",
		"D: a damaged auto speed or skip scope was not reset to its default.")
	_settings.call("reset_to_defaults")

	var actions: Array = _settings.call("get_rebindable_actions")
	for action: StringName in [&"dialogue_auto", &"dialogue_skip"]:
		_expect(actions.has(action), "D: %s is not rebindable." % action)
		_expect(InputMap.has_action(action), "D: %s is not in the input map." % action)
		_expect(L10n.has_key("settings.action.%s" % action), "D: %s has no name." % action)
		var key := _settings.call("primary_event", action, &"keyboard") as InputEvent
		_expect(key != null, "D: %s has no default key." % action)
	_expect(_settings.call("binding_label", &"dialogue_auto", &"keyboard") == "V",
		"D: auto's default key is not V.")
	_expect(_settings.call("binding_label", &"dialogue_auto", &"gamepad") == "LT",
		"D: auto's default controller input is not LT.")
	_expect(_settings.call("binding_label", &"dialogue_skip", &"gamepad") == "RT",
		"D: skip's default controller input is not RT.")
	var seen: Dictionary = {}
	for action: Variant in actions:
		for event: InputEvent in InputMap.action_get_events(StringName(action)):
			var code := SettingsScript.encode_event(event)
			if seen.has(code) and not _shared(StringName(seen[code]), StringName(action)):
				_failures.append("D: %s and %s share %s by default." % [seen[code], action, code])
			seen[code] = action


func _shared(first: StringName, second: StringName) -> bool:
	for pair: Array in SettingsScript.SHARED_PAIRS:
		if pair.has(first) and pair.has(second):
			return true
	return false


# --- E. The real conversation -------------------------------------------------------


func _check_real_conversation() -> void:
	Harness.stage = "E. main scene"
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("E: main.tscn could not be loaded.")
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _frames(3)
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	var game_ui := _main.get_node_or_null("GameUI")
	if _dialogue == null or game_ui == null:
		_failures.append("E: main.tscn has no dialogue controller or GameUI.")
		return
	_panel = game_ui.get_node_or_null("DialoguePanel") as DialoguePanel
	_backlog = game_ui.get_node_or_null("BacklogPanel") as BacklogPanel
	_hud = game_ui.get_node_or_null("HUD") as GameHud
	_autoplay = _dialogue.get_autoplay()
	if _autoplay == null or _panel == null or _hud == null:
		_failures.append("E: the controller has no autoplay, or the UI no panel or HUD.")
		return
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	# The scene may restore the language a previous run left; the HUD wording checked
	# below is the English one.
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	_hud.refresh_language_text()
	_hud.refresh_reading_text()
	# A fresh log at a scratch path: the player's own log is not this test's to touch.
	_clean(LIVE_LOG)
	var overlay := game_ui.get_node_or_null("CheckOverlay") as CheckOverlay
	_autoplay.bind(_dialogue, _panel, _backlog, overlay, ReadLog.open(LIVE_LOG))
	_settings.call("set_auto_speed", &"fast")
	Engine.time_scale = 8.0
	var before_progress := _dialogue.get_reading_progress()
	_expect(int(before_progress.get("total", 0)) > 0 and int(before_progress.get("read", -1)) == 0,
		"E: a fresh log does not start at 0 of the shipped lines: %s" % str(before_progress))

	# 1. Holding skip on text nobody has read: nothing moves, and the HUD says why.
	if not _dialogue.play_conversation(CONVERSATION):
		_failures.append("E: %s could not be started." % CONVERSATION)
		return
	await _frames(3)
	_expect(_hud.get_reading_text().contains("V"),
		"E: during a conversation the HUD does not name the auto key: '%s'." % _hud.get_reading_text())
	var first_identity := _autoplay.get_current_identity()
	_expect(first_identity.begins_with("conv:%s/" % CONVERSATION),
		"E: the first line's identity is '%s'." % first_identity)
	_autoplay.set_skip_forced(true)
	await _seconds(0.4)
	_expect(_autoplay.get_advance_count() == 0 and _autoplay.get_current_identity() == first_identity,
		"E: skip moved past a line nobody had read.")
	_expect(_autoplay.get_stop_reason() == DialogueAutoplay.STOP_UNREAD,
		"E: skip on unread text gave the reason '%s'." % _autoplay.get_stop_reason())
	_expect(_hud.get_reading_text() == L10n.t("hud.reading_stopped.unread"),
		"E: the HUD does not say skip stopped for new text: '%s'." % _hud.get_reading_text())
	_autoplay.set_skip_forced(false)

	# 2. Auto: reads up to the choice and waits there.
	_autoplay.set_auto(true)
	await _frames(2)
	_expect(_autoplay.get_mode() == DialogueAutoplay.MODE_AUTO, "E: auto did not switch on.")
	_expect(_hud.get_reading_text().begins_with("AUTO"),
		"E: the HUD does not say auto is on: '%s'." % _hud.get_reading_text())
	var reached := await _wait_for(func() -> bool: return _dialogue.has_pending_choices(), 30.0)
	_expect(reached, "E: auto never reached %s's choice (%d advances)."
		% [CONVERSATION, _autoplay.get_advance_count()])
	var auto_advances := _autoplay.get_advance_count()
	_expect(auto_advances >= 1, "E: auto did not advance a single line.")
	if reached:
		await _seconds(0.6)
		_expect(_dialogue.has_pending_choices() and _autoplay.get_advance_count() == auto_advances,
			"E: auto went past (or made) a choice.")

	# The log pauses auto.
	if reached and _backlog != null:
		_dialogue.select_choice(0)
		await _frames(2)
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_backlog.open()
			var paused_at := _autoplay.get_advance_count()
			# Longer than auto would hold this line (fast: under 3 s for a short line).
			_expect(_autoplay.current_hold_seconds() < 5.0,
				"E: the line under the log holds %.1f s; the wait below proves nothing."
				% _autoplay.current_hold_seconds())
			await _seconds(5.0)
			_expect(_autoplay.get_advance_count() == paused_at, "E: auto advanced under the open log.")
			_backlog.close()
	_autoplay.set_auto(false)
	await _close_conversation()
	_expect(_autoplay.get_read_log().size() >= auto_advances,
		"E: %d lines were read but %d marked." % [auto_advances, _autoplay.get_read_log().size()])
	_expect(FileAccess.file_exists(LIVE_LOG), "E: the read log was not written when the talk ended.")
	_expect(not FileAccess.file_exists("user://save.json")
		or not FileAccess.get_file_as_string("user://save.json").contains(first_identity),
		"E: a read mark ended up in the save.")
	var after_progress := _dialogue.get_reading_progress()
	_expect(int(after_progress.get("read", 0)) >= auto_advances,
		"E: the progress did not count what was read: %s" % str(after_progress))
	await _check_journal_line(after_progress)

	# 3. The second time through: skip runs over what was read and stops at the choice.
	if not _dialogue.play_conversation(CONVERSATION):
		_failures.append("E: %s could not be started a second time." % CONVERSATION)
		return
	await _frames(3)
	_expect(_autoplay.current_line_was_read(), "E: the first line was not remembered as read.")
	var skip_from := _autoplay.get_advance_count()
	_autoplay.set_skip_forced(true)
	var skipped := await _wait_for(func() -> bool: return _dialogue.has_pending_choices(), 10.0)
	_expect(skipped, "E: skip did not reach the choice over read lines.")
	await _frames(4)
	_expect(_autoplay.get_stop_reason() == DialogueAutoplay.STOP_CHOICE,
		"E: skip at a choice gave the reason '%s'." % _autoplay.get_stop_reason())
	_expect(_autoplay.get_advance_count() - skip_from >= 1, "E: skip did not advance.")
	_expect(_dialogue.has_pending_choices(), "E: skip made a choice.")
	_autoplay.set_skip_forced(false)
	await _close_conversation()

	# 4. "toggle": one press of the skip key runs to the choice and ends there.
	_settings.call("set_skip_mode", &"toggle")
	if _dialogue.play_conversation(CONVERSATION):
		await _frames(3)
		var expected_hint := L10n.t("hud.reading_hint_toggle", {
			"auto": InputHint.action_key(_hud, &"dialogue_auto"),
			"skip": InputHint.action_key(_hud, &"dialogue_skip"),
		})
		_expect(_hud.get_reading_text() == expected_hint,
			"E: the toggle hint reads '%s', not '%s'." % [_hud.get_reading_text(), expected_hint])
		_key(KEY_CTRL)
		await _frames(2)
		_expect(_autoplay.is_skip_toggled(), "E: in toggle mode Ctrl did not start skipping.")
		var toggled := await _wait_for(func() -> bool: return _dialogue.has_pending_choices(), 10.0)
		await _frames(4)
		_expect(toggled and not _autoplay.is_skip_toggled(),
			"E: a toggled skip did not reach the choice and end there.")
		_expect(_hud.get_reading_text() == L10n.t("hud.reading_stopped.choice"),
			"E: after a toggled skip the HUD reads '%s'." % _hud.get_reading_text())
		await _close_conversation()
	else:
		_failures.append("E: %s could not be started a third time." % CONVERSATION)
	_settings.call("set_skip_mode", &"hold")
	await _check_forget_read()

	# 5. The auto key toggles, and is the auto key only.
	_key(KEY_V)
	await _frames(2)
	_expect(_autoplay.is_auto(), "E: V did not turn auto on.")
	_expect(_hud.get_reading_text().begins_with("AUTO"),
		"E: with auto on outside a conversation the HUD says nothing.")
	_key(KEY_V)
	await _frames(2)
	_expect(not _autoplay.is_auto(), "E: V did not turn auto off again.")
	_expect(_hud.get_reading_text().is_empty(), "E: the HUD still shows a reading mode.")
	_settings.call("reset_to_defaults")


func _check_forget_read() -> void:
	var menu := _main.get_node_or_null("PauseMenu")
	if menu == null or not menu.has_method("get_settings_panel"):
		_failures.append("E: main.tscn has no pause menu with a settings screen.")
		return
	var read_before := _autoplay.get_read_log().size()
	menu.call("open")
	var panel := menu.call("get_settings_panel") as SettingsPanel
	panel.open()
	await _frames(2)
	var button := panel.get_row_control(&"forget_read") as Button
	if button == null:
		_failures.append("E: the settings screen has no 'clear reading history' row.")
	else:
		_expect(button.text.contains(str(read_before)),
			"E: the clear button does not say how much is read: '%s'." % button.text)
		button.pressed.emit()
		await _frames(1)
		_expect(panel.get_forget_read_state() == SettingsPanel.FORGET_ARMED
			and _autoplay.get_read_log().size() == read_before,
			"E: one press of 'clear reading history' already cleared it.")
		button.pressed.emit()
		await _frames(1)
		_expect(panel.get_forget_read_state() == SettingsPanel.FORGET_DONE
			and _autoplay.get_read_log().size() == 0 and not FileAccess.file_exists(LIVE_LOG),
			"E: two presses did not clear the live log and its file.")
		_expect(int(_dialogue.get_reading_progress().get("read", -1)) == 0,
			"E: the progress still counts lines after the history was cleared.")
	panel.close()
	menu.call("close")
	await _frames(2)


func _check_journal_line(progress: Dictionary) -> void:
	var words := ReadingProgress.describe(progress)
	_expect(words.contains(str(int(progress.get("total", 0)))),
		"E: the notebook's progress line '%s' does not give the total." % words)
	var menu := _main.get_node_or_null("PauseMenu")
	if menu == null or not menu.has_method("get_journal_panel"):
		_failures.append("E: main.tscn has no pause menu with a notebook.")
		return
	menu.call("open_journal")
	await _frames(2)
	var journal := menu.call("get_journal_panel") as JournalPanel
	var shown := journal.get_progress_text() if journal != null else ""
	_expect(shown == words, "E: the notebook shows '%s', not '%s'." % [shown, words])
	menu.call("close")
	await _frames(2)
	_expect(not paused, "E: closing the notebook left the game paused.")


# --- Helpers ------------------------------------------------------------------------


func _close_conversation() -> void:
	var steps := 0
	while _dialogue.is_busy() and steps < MAX_STEPS:
		steps += 1
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(2)
	_expect(not _dialogue.is_busy(), "E: the conversation would not close.")
	_panel.close()
	await _frames(2)


func _wait_for(condition: Callable, game_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(1000.0 * game_seconds / Engine.time_scale) + 2000
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await process_frame
	return bool(condition.call())


## Game seconds, under the test's time scale.
func _seconds(game_seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(1000.0 * game_seconds / Engine.time_scale)
	while Time.get_ticks_msec() < until:
		await process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)


func _json(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _clean(path: String) -> void:
	for item: String in [path, "%s.tmp" % path, "%s.broken" % path]:
		_remove(item)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
