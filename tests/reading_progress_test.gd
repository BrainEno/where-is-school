extends SceneTree
## Reading progress across runs, and when a line becomes "read".
##
## A. `ReadingProgress` against the game's real content and a real `ReadLog` in a test path:
##    the total is every presentable line once (checked against a count taken straight from
##    the JSON files), the same in both languages; a line counts only with the text it has now
##    in the language on screen; reading in two languages counts once; a repeat look counts
##    nothing; only started and unfinished areas are named; all of it reads 100%, all but one
##    does not; no content means no line; forgetting goes back to 0.
## B. The real game (`main.tscn`): a line goes into the read log only once it has been on
##    screen whole - not while it types, not when a language switch re-renders it half-typed,
##    not when the world is torn down under it - and the inspection identities the controller
##    shows are the ones counted (first and recall count, a repeat does not).
## C. A new game (`Session.start_new_game`) and a deleted save keep the read log; the next
##    run's skip passes the line read whole and stops at the one that was cut off; auto waits
##    for the text before it counts or passes anything.
## D. The notebook: the progress line comes from the controller through the pause menu, is
##    re-measured on every opening, follows the language with the same numbers, says 0% and
##    100% plainly, names no area at 100%, is absent without content, wraps inside the sheet
##    and leaves the entries their room.
##
## The player's files are not touched: the read log lives in a test directory and the
## settings file is backed up and restored.

const Harness = preload("res://tests/test_harness.gd")

const TIMEOUT_SECONDS := 300.0
const SETTINGS_PATH := "user://settings.cfg"
const LOG_DIR := "user://reading_progress_test"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const INSPECTION := &"classroom_set_square"
const MAX_STEPS := 80
## Slow enough that a line is still typing several frames after it appears.
const SLOW_CPS := 3.0

var _failures: Array[String] = []
var _had_settings := false
var _settings_backup := PackedByteArray()
var _restored := false
var _settings: Node = null
var _main: Node = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null
var _menu: PauseMenu = null
var _log: ReadLog = null
## Lines of n_class as the first run left them: [identity, text] of the line read whole, and
## of the line that was still typing when the world went.
var _read_whole: Array = []
var _cut_off: Array = []


func _initialize() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "reading_progress_test.gd")
	call_deferred("_run")


func _finalize() -> void:
	_restore_settings()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	root.size = Vector2i(1600, 900)
	await _frames(3)
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		_finish_with(["State autoloads are unavailable."])
		return
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	_settings = Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	var session := Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	Harness.clear_session_state(self)
	if _settings == null or session == null:
		_finish_with(["The Settings / Session autoloads could not be created."])
		return
	_settings.call("reset_to_defaults")

	_log = ReadLog.new(_log_path("game"))
	_log.load_file()
	ReadLog.use_shared(_log)
	if not await _load_main():
		_finish_with(_failures)
		return
	_check_progress_rules()
	_check_empty_content()
	await _check_line_is_read_when_shown()
	await _check_new_game_keeps_the_log(session)
	await _check_next_run_skip_and_auto()
	await _check_journal()
	_finish_with(_failures)


func _finish_with(failures: Array) -> void:
	ReadLog.use_shared(null)
	Engine.time_scale = 1.0
	paused = false
	_restore_settings()
	_remove_dir(LOG_DIR)
	Harness.finish(
		self, failures,
		"reading progress counts every presentable line once, in any language, against the text "
		+ "on screen now; repeats and unvisited areas add nothing; a line is read once shown "
		+ "whole; a new game and a deleted save keep the log; the notebook shows it fresh."
	)


# --- A. the progress, against the real content ------------------------------------------


func _check_progress_rules() -> void:
	var progress := ReadingProgress.build(_dialogue.get_dialogue_library(), _dialogue.get_inspection_library())
	var expected := _count_presentable_lines("en")
	_expect(expected > 0, "A: the content files hold no line at all.")
	_expect(_count_presentable_lines("zh-CN") == expected,
		"A: the two languages' files hold %d and %d lines." % [expected, _count_presentable_lines("zh-CN")])
	_expect(progress.total() == expected,
		"A: %d lines counted, the files hold %d presentable ones." % [progress.total(), expected])
	var ids := progress.get_identities()
	var unique := {}
	for identity in ids:
		unique[identity] = true
		_expect(not identity.ends_with("/repeat"), "A: a repeat look is counted (%s)." % identity)
		_expect(identity.begins_with("conv:") or identity.begins_with("inspection:"),
			"A: '%s' is not an identity the backlog gives." % identity)
	_expect(unique.size() == ids.size(), "A: %d identities, %d of them distinct." % [ids.size(), unique.size()])

	var log := ReadLog.new(_log_path("rules"))
	var empty_en := progress.measure(log, "en")
	var empty_zh := progress.measure(log, "zh-CN")
	_expect(int(empty_en["read"]) == 0 and int(empty_en["percent"]) == 0 and (empty_en["areas"] as Array).is_empty(),
		"A: an empty log measures %s." % str(empty_en))
	_expect(int(empty_en["total"]) == int(empty_zh["total"]) and int(empty_en["total"]) == expected,
		"A: the total is %d in English and %d in Chinese." % [int(empty_en["total"]), int(empty_zh["total"])])

	# A line from the classroom (the prologue's n_class).
	var line := _first_identity_with_prefix(ids, "conv:n_class/")
	var en_text := progress.text_of(line, "en")
	var zh_text := progress.text_of(line, "zh-CN")
	_expect(not en_text.is_empty() and not zh_text.is_empty() and en_text != zh_text,
		"A: '%s' has no text in one of the languages." % line)
	_expect(progress.area_of(line) == "place.classroom", "A: the prologue is filed under '%s'." % progress.area_of(line))

	# An edited line is unread: the log knows the identity, with other words.
	log.mark_read(line, "en", "%s (as it read before the rewrite)" % en_text)
	_expect(int(progress.measure(log, "en")["read"]) == 0, "A: a line read with older words counts as read.")
	# The current text, in the language on screen.
	log.mark_read(line, "en", en_text)
	var after_en := progress.measure(log, "en")
	_expect(int(after_en["read"]) == 1, "A: the line read with its current words counts %d." % int(after_en["read"]))
	# Read in English, it counts in Chinese too (the skip rule), and once.
	_expect(int(progress.measure(log, "zh-CN")["read"]) == 1, "A: a line read in English is unread in Chinese.")
	log.mark_read(line, "zh-CN", zh_text)
	_expect(int(progress.measure(log, "en")["read"]) == 1 and int(progress.measure(log, "zh-CN")["read"]) == 1,
		"A: one line read in two languages counts twice.")
	# Edited in Chinese only: unread in Chinese, still read in English.
	log.mark_read(line, "zh-CN", "%s。" % zh_text)
	_expect(int(progress.measure(log, "zh-CN")["read"]) == 0, "A: a Chinese rewrite still counts as read in Chinese.")
	_expect(int(progress.measure(log, "en")["read"]) == 1, "A: a Chinese rewrite made the English line unread.")
	log.mark_read(line, "zh-CN", zh_text)

	# Areas: only the classroom has been started.
	var areas: Array = progress.measure(log, "en")["areas"]
	_expect(areas.size() == 1 and String((areas[0] as Dictionary)["place_key"]) == "place.classroom",
		"A: the started areas are %s." % str(areas))
	if areas.size() == 1:
		var classroom: Dictionary = areas[0]
		_expect(int(classroom["read"]) == 1 and int(classroom["left"]) == int(classroom["total"]) - 1,
			"A: the classroom reads %s." % str(classroom))
	L10n.set_locale("en")
	var described := ReadingProgress.describe(progress.measure(log, "en"))
	_expect(described.contains(L10n.t("place.classroom")), "A: the description does not name the classroom: '%s'." % described)
	for place in ["corridor", "street", "residential", "alley", "playground"]:
		_expect(not described.contains(L10n.t("place.%s" % place)),
			"A: the description names %s, where nothing was read: '%s'." % [place, described])

	# A repeat look adds nothing.
	var before := int(progress.measure(log, "en")["read"])
	log.mark_read("inspection:%s/repeat" % INSPECTION, "en", "anything")
	_expect(int(progress.measure(log, "en")["read"]) == before, "A: a repeat look raised the count.")

	# Everything but one: not 100%. Everything: 100%, no area left.
	for identity in ids:
		log.mark_read(identity, "en", progress.text_of(identity, "en"))
	var full := progress.measure(log, "en")
	_expect(int(full["read"]) == expected and int(full["percent"]) == 100 and (full["areas"] as Array).is_empty(),
		"A: everything read measures %s." % str(full))
	_expect(not ReadingProgress.describe(full).contains("\n"), "A: at 100%% an area is still named.")
	log.mark_read(line, "en", "%s (rewritten)" % en_text)
	var almost := progress.measure(log, "en")
	_expect(int(almost["read"]) == expected - 1 and int(almost["percent"]) < 100,
		"A: all but one line measures %s (rounded up to 100?)." % str(almost))

	# Forgetting goes back to nothing.
	log.forget_all()
	var cleared := progress.measure(log, "en")
	_expect(int(cleared["read"]) == 0 and int(cleared["percent"]) == 0 and int(cleared["total"]) == expected,
		"A: after forgetting the log measures %s." % str(cleared))


func _check_empty_content() -> void:
	var nothing := ReadingProgress.build(null, null)
	var measured := nothing.measure(_log, "en")
	_expect(nothing.total() == 0 and int(measured["total"]) == 0 and int(measured["percent"]) == 0,
		"A: no content measures %s." % str(measured))
	_expect(ReadingProgress.describe(measured).is_empty(), "A: no content still describes a progress.")
	_expect(ReadingProgress.describe({}).is_empty(), "A: an empty dictionary describes a progress.")


# --- B. when a line is read, in the real game -------------------------------------------


func _check_line_is_read_when_shown() -> void:
	_log.forget_all()
	Harness.clear_session_state(self)
	_panel.set_reveal_speed(SLOW_CPS)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("B: n_class could not be started.")
		return
	await _frames(3)
	var first := _current()
	_expect(_panel.is_revealing(), "B: the first line is not typing at %.0f characters a second." % SLOW_CPS)
	_expect(not _known(first[0]), "B: the log knows '%s' before it was shown whole." % first[0])
	_expect(int(_dialogue.get_reading_progress()["read"]) == 0, "B: progress counted a line still typing.")

	# A language switch half way re-renders it; neither text was read whole.
	L10n.set_locale("zh-CN")
	_dialogue.apply_locale("zh-CN")
	await _frames(3)
	_expect(not _known(first[0]), "B: a language switch during typing put the line in the log.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	await _frames(3)
	_expect(_panel.is_revealing() and not _known(first[0]), "B: switching back put the half-typed line in the log.")

	_panel.complete_reveal()
	await _frames(2)
	_expect(_log.is_read(first[0], "en", first[1]), "B: the line shown whole is not read.")
	_expect(int(_dialogue.get_reading_progress()["read"]) == 1,
		"B: one line shown whole counts %d." % int(_dialogue.get_reading_progress()["read"]))
	# Shown whole, a switch now is a reading in that language too (and no second line).
	L10n.set_locale("zh-CN")
	_dialogue.apply_locale("zh-CN")
	await _frames(2)
	var zh_line := _current()
	_expect(_log.is_read(first[0], "zh-CN", zh_line[1]), "B: the whole line re-rendered in Chinese is not read in Chinese.")
	_expect(int(_dialogue.get_reading_progress()["read"]) == 1, "B: a language switch counted the line twice.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	await _frames(2)

	_dialogue.advance_presentation()
	await _frames(3)
	var second := _current()
	_expect(second[0] != first[0], "B: advancing did not show the next line.")
	_expect(_panel.is_revealing() and not _known(second[0]), "B: the next line was read before it was shown whole.")
	_read_whole = first
	_cut_off = second


# --- C. a new game, a deleted save, and the next run ------------------------------------


func _check_new_game_keeps_the_log(session: Node) -> void:
	var before := _log.line_count()
	_expect(before == 1, "C: before the new game the log holds %d lines, not 1." % before)
	_expect(bool(_log.flush().get("ok", false)), "C: the log could not be written before the new game.")
	# The run ends with the second line still typing: the world goes from under it.
	var report: Dictionary = await session.call("start_new_game", _main, false)
	_expect(bool(report.get("ok", false)), "C: the new game failed: %s." % str(report))
	_main = null
	await _frames(2)
	_expect(ReadLog.shared() == _log, "C: the new game replaced the shared read log.")
	_expect(_log.line_count() == before, "C: the new game left %d lines of %d." % [_log.line_count(), before])
	_expect(not _known(_cut_off[0]), "C: the line cut off by the new game went into the log.")
	var on_disk := ReadLog.new(_log.path)
	on_disk.load_file()
	_expect(on_disk.is_read(_read_whole[0], "en", _read_whole[1]), "C: the line read whole is not in the file after the new game.")
	_expect(not on_disk.is_read(_cut_off[0], "en", _cut_off[1]), "C: the line cut off is in the file after the new game.")

	var save := root.get_node_or_null(^"Save")
	if save != null:
		save.call("delete_save", {"broken": true})
	_expect(FileAccess.file_exists(_log.path), "C: deleting the save removed the read log file.")

	if not await _load_main():
		return
	_expect(int(_dialogue.get_reading_progress()["read"]) == 1,
		"C: the next run counts %d lines read, not 1." % int(_dialogue.get_reading_progress()["read"]))


func _check_next_run_skip_and_auto() -> void:
	if _dialogue == null:
		return
	Harness.clear_session_state(self)
	_panel.set_reveal_speed(SLOW_CPS)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("C: n_class could not be started in the next run.")
		return
	await _frames(2)
	_expect(_current()[0] == _read_whole[0], "C: the next run did not start where the first did.")
	_expect(_dialogue.was_current_line_read(), "C: the line read whole in the first run is not read in the next.")
	_dialogue.request_skip()
	var stopped := await _wait_until(func() -> bool: return not _dialogue.get_playback().is_skipping(), 10.0)
	_expect(stopped, "C: skip did not stop.")
	await _frames(2)
	_expect(_current()[0] == _cut_off[0], "C: skip stopped at '%s', not at the line cut off ('%s')." % [_current()[0], _cut_off[0]])
	_expect(not _dialogue.was_current_line_read(), "C: the line cut off counts as read in the next run.")

	# Auto on an unread, slowly typing line: nothing is counted or passed until it is whole.
	_dialogue.toggle_auto()
	await _seconds(0.6)
	_expect(_current()[0] == _cut_off[0], "C: auto passed a line that was still typing.")
	_expect(_panel.is_revealing() and not _known(_cut_off[0]), "C: auto counted a line that was still typing.")
	_panel.set_reveal_speed(400.0)
	var whole := await _wait_until(func() -> bool: return _known(_cut_off[0]), 5.0)
	_expect(whole, "C: the line was not read once auto let it finish typing.")
	var moved := await _wait_until(func() -> bool: return _current()[0] != _cut_off[0] or _dialogue.has_pending_choices(),
		DialoguePlayback.MAX_PAUSE / Engine.time_scale + 3.0)
	_expect(moved, "C: auto did not pass the line once it was whole.")
	_dialogue.toggle_auto()
	await _close()


# --- D. the notebook --------------------------------------------------------------------


func _check_journal() -> void:
	if _menu == null:
		return
	var journal := _menu.get_journal_panel()
	var total := int(_dialogue.get_reading_progress()["total"])

	# Nothing read: 0%.
	_log.forget_all()
	_menu.open_journal(true)
	await _frames(3)
	_expect(journal.has_progress_source(), "D: the pause menu did not give the notebook a progress source.")
	var zero := journal.get_progress_text()
	_expect(zero == L10n.t("journal.read_progress", {"percent": 0, "read": 0, "total": total}),
		"D: with nothing read the notebook says '%s'." % zero)
	_menu.close()
	await _frames(2)

	# An inspection: its first reading and its recollection count; a repeat does not.
	Harness.clear_session_state(self)
	var shown := await _read_inspection()
	_expect(shown.size() >= 2 and shown[0] == "inspection:%s/first" % INSPECTION
		and shown[1] == "inspection:%s/recall" % INSPECTION,
		"B: the set square showed %s." % str(shown))
	var progress := ReadingProgress.build(_dialogue.get_dialogue_library(), _dialogue.get_inspection_library())
	for identity: String in shown:
		_expect(not progress.area_of(identity).is_empty(), "B: '%s' was shown but is not counted." % identity)
	var after_first := int(_dialogue.get_reading_progress()["read"])
	_expect(after_first == 2, "B: the first look at the set square counted %d lines, not 2." % after_first)
	var repeat := await _read_inspection()
	_expect(repeat == PackedStringArray(["inspection:%s/repeat" % INSPECTION]), "B: the second look showed %s." % str(repeat))
	_expect(int(_dialogue.get_reading_progress()["read"]) == after_first, "B: a repeat look raised the progress.")

	# Reopened: the new numbers, the area started, the entry it recorded still in view.
	_menu.open_journal(true)
	await _frames(3)
	var text := journal.get_progress_text()
	_expect(text.begins_with(L10n.t("journal.read_progress", {"percent": 0, "read": 2, "total": total})),
		"D: after two lines the notebook says '%s'." % text)
	_expect(text.contains(L10n.t("place.classroom")), "D: the started classroom is not named: '%s'." % text)
	_expect(not text.contains(L10n.t("place.street")), "D: the notebook names the street: '%s'." % text)
	var label := journal.find_child("ReadingProgress", true, false) as Label
	_expect(label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF, "D: the progress line does not wrap.")
	if label != null:
		var sheet := journal.get_panel().get_global_rect()
		_expect(sheet.encloses(label.get_global_rect()), "D: the progress line runs outside the sheet.")
	_expect(journal.get_row_ids().size() > 0 and journal.get_scroll().visible and journal.get_scroll().size.y > 40.0,
		"D: the entries lost their room (%d rows, scroll %.0f px high)." % [journal.get_row_ids().size(), journal.get_scroll().size.y])

	# The other language, switched the way the game does it: its words, the same numbers.
	var loc := root.get_node_or_null(^"Loc")
	loc.call("set_locale", "zh-CN")
	await _frames(3)
	var zh_text := journal.get_progress_text()
	_expect(zh_text.begins_with(L10n.t("journal.read_progress", {"percent": 0, "read": 2, "total": total})),
		"D: in Chinese the notebook says '%s'." % zh_text)
	_expect(zh_text.contains(L10n.t("place.classroom")), "D: the Chinese line does not name the classroom: '%s'." % zh_text)
	loc.call("set_locale", "en")
	await _frames(2)
	_menu.close()
	await _frames(2)

	# Everything read: 100%, nothing left to name.
	for identity in progress.get_identities():
		_log.mark_read(identity, "en", progress.text_of(identity, "en"))
	_menu.open_journal(true)
	await _frames(3)
	var full := journal.get_progress_text()
	_expect(full == L10n.t("journal.read_progress", {"percent": 100, "read": total, "total": total}),
		"D: with everything read the notebook says '%s'." % full)
	_menu.close()
	await _frames(2)

	# No content: no line at all.
	journal.set_progress_source(func() -> Dictionary: return ReadingProgress.build(null, null).measure(_log, "en"))
	_menu.open_journal(true)
	await _frames(3)
	_expect(journal.get_progress_text().is_empty(), "D: with no content the notebook says '%s'." % journal.get_progress_text())
	_menu.close()
	await _frames(2)


# --- helpers ----------------------------------------------------------------------------


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
	_menu = _main.get_node_or_null("PauseMenu") as PauseMenu
	var ui := _main.get_node_or_null("GameUI")
	_panel = ui.get_node_or_null("DialoguePanel") as DialoguePanel if ui != null else null
	if _dialogue == null or _panel == null or _menu == null:
		_failures.append("main.tscn did not expose the dialogue controller, panel and pause menu.")
		return false
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	if _dialogue.get_read_log() != _log:
		_failures.append("The dialogue controller does not use the shared read log.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	Engine.time_scale = 4.0
	await _frames(2)
	return true


## Looks at the set square and reads every line it shows, whole. Returns the identities shown.
func _read_inspection() -> PackedStringArray:
	var shown := PackedStringArray()
	_panel.set_reveal_speed(0.0)
	if not _dialogue.present_inspection(INSPECTION):
		_failures.append("B: the set square could not be looked at.")
		return shown
	var steps := 0
	while _dialogue.is_busy() and steps < MAX_STEPS:
		steps += 1
		await _frames(2)
		shown.append(_current()[0])
		_dialogue.advance_presentation()
	await _frames(2)
	return shown


## [identity, text] of the line on screen.
func _current() -> Array:
	var line := _dialogue.get_current_line()
	return [DialogueHistory.identify(line), String(line.get("text", ""))]


## Whether the log holds `identity` in any language, whatever the text.
func _known(identity: String) -> bool:
	return _log.is_read(identity, "xx-unused", "")


func _first_identity_with_prefix(ids: PackedStringArray, prefix: String) -> String:
	for identity in ids:
		if identity.begins_with(prefix):
			return identity
	_failures.append("A: no counted identity starts with '%s'." % prefix)
	return ""


## Every line the content can show in `locale`, counted from the files themselves: each
## conversation node with text, each inspection's first text and its recollection.
func _count_presentable_lines(locale: String) -> int:
	var count := 0
	for chapter: String in DialogueLibrary.CHAPTERS:
		var data: Variant = _read_json("res://data/dialogue/%s/%s.json" % [locale, chapter])
		if not data is Dictionary:
			continue
		var conversations: Dictionary = (data as Dictionary).get("conversations", {})
		for conversation: Variant in conversations.values():
			for node: Variant in (conversation as Dictionary).get("nodes", []):
				if not String((node as Dictionary).get("text", "")).is_empty():
					count += 1
	for chapter: String in InspectionLibrary.CHAPTERS:
		var data: Variant = _read_json(InspectionLibrary.chapter_path(locale, chapter))
		if not data is Dictionary:
			continue
		for value: Variant in (data as Dictionary).values():
			if not value is Dictionary:
				continue
			if not String((value as Dictionary).get("text", "")).is_empty():
				count += 1
			var recall: Variant = (value as Dictionary).get("recall", null)
			if recall is Dictionary and not String((recall as Dictionary).get("text", "")).is_empty():
				count += 1
	return count


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


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
		_failures.append("A conversation would not close.")
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


func _log_path(tag: String) -> String:
	return "%s/%s.json" % [LOG_DIR, tag]


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
