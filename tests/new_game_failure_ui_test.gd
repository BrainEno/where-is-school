extends SceneTree
## A new game that does not start, seen from the screen the player started it on (#146).
##
## `opening_resume_test.gd` proves the transaction in `game_session.gd`: a save that cannot
## be moved aside, an opening that cannot load and a staged save that cannot be removed all
## roll back, byte for byte. This check is the other half - what the player sees - and it
## only uses the controls a player uses: real key, gamepad and mouse events on the real
## buttons of the pause menu, the end card and the title screen. No `activate()`, no
## `pressed.emit()`, no direct call to `Session.start_new_game()`.
##
## For every entry point and every failure it asserts:
##
## - the reason is on screen, in the player's language (not the English log detail), on the
##   screen that survived - the pause menu or the end card when the world is still there,
##   the title screen when it is not - and it says the save is safe;
## - the focus is on the way to try again, and keyboard, mouse and gamepad still work: try
##   again, go back (Cancel, Resume, Esc), move to the other button;
## - the save and the quarantined copy of an unreadable save are the same bytes, and the
##   story flags and knowledge are the ones from before;
## - the failure is shown once: a title screen reached later does not show it again, a
##   language switch renders it again in the new language, the next attempt clears it, and
##   a new game that does start shows no old error;
## - a refusal because a new game is already starting (`busy`) says so;
## - at the largest text size, in English and in Chinese, the whole message is on screen.
##
## The `busy` refusal is produced by holding Session's `_starting` flag for the length of
## one press: two real transactions cannot be made to overlap on a chosen frame from input
## alone, and the concurrency itself is `opening_resume_test.gd`'s second-click check.

const Harness = preload("res://tests/test_harness.gd")

const MAIN_SCENE := "res://scenes/main/main.tscn"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const LOC_SCRIPT := "res://scripts/i18n/loc.gd"
const MISSING_SCENE := "res://scenes/ui/does_not_exist.tscn"
const SAVE_PATH := "user://save.json"
const BROKEN_PATH := "user://save.broken.json"
const USER_DIR := "user://"
const PROBE_ENTRY := &"new_game_failure_probe"
const KEY := "menu.new_game_failed."
const LARGEST_SCALE := 1.3


## The real file layer, with the calls a case names made to fail (as in
## `opening_resume_test.gd`). Everything else reaches the disk, so the bytes asserted on
## are real.
class FaultyIO:
	var fail_renames: Array = []
	var fail_removes: Array = []
	var renames := 0
	var removes := 0

	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> PackedByteArray:
		return FileAccess.get_file_as_bytes(path)

	func write_bytes(path: String, data: PackedByteArray) -> int:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(data)
		var error := file.get_error()
		file.close()
		return error

	func rename(from: String, to: String) -> int:
		var index := renames
		renames += 1
		if fail_renames.has(index):
			return ERR_FILE_CANT_WRITE
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.rename(from, to)

	func remove(path: String) -> int:
		var index := removes
		removes += 1
		if fail_removes.has(index):
			return ERR_FILE_CANT_WRITE
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.remove(path)

	func list() -> PackedStringArray:
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return PackedStringArray()
		return dir.get_files()


var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null
var _save: Node = null
var _session: Node = null
var _settings: Node = null
var _loc: Node = null
var _case := ""
## What was on disk and in memory before the press, for the "nothing changed" checks.
var _save_before := PackedByteArray()
var _quarantine_before := PackedByteArray()
var _flags_before: Dictionary = {}
var _entries_before := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "new_game_failure_ui_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_save = autoloads["save"]
	_loc = Harness.ensure_autoload(self, "Loc", LOC_SCRIPT)
	_session = Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	_settings = Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if _game_state == null or _narrative == null or _save == null or _session == null \
			or _settings == null or _loc == null:
		Harness.finish(self, ["The state, save, session, settings or locale autoloads are unavailable."], "")
		return
	var original_locale: String = _loc.call("get_locale")
	var original_size: StringName = _settings.call("get_text_size")
	_loc.call("set_locale", "en")
	_settings.call("set_text_size", &"standard")

	await _check_pause_menu_staging_failure()
	await _check_pause_menu_scene_failure()
	await _check_end_card_staging_failure()
	await _check_end_card_discard_failure()
	await _check_title_staging_failure()
	await _check_title_discard_failure()

	_save.set("io", null)
	_session.set("world_scene", MAIN_SCENE)
	_session.set("_starting", false)
	paused = false
	await _free_current_scene()
	if FileAccess.file_exists(BROKEN_PATH):
		DirAccess.remove_absolute(BROKEN_PATH)
	_loc.call("set_locale", original_locale)
	_settings.call("set_text_size", original_size)
	Harness.clear_session_state(self)
	Harness.finish(
		self, _failures,
		"A new game that fails from the pause menu, the end card or the title (save cannot "
		+ "move, opening cannot load, staged save cannot be removed) is reported once, in the "
		+ "player's language, on the screen that survived, with the focus on trying again; "
		+ "keyboard, mouse and gamepad still work, the save and the quarantined copy keep "
		+ "their bytes, a busy refusal is explained, and the message fits at the largest "
		+ "text size in English and Chinese."
	)


# --- Pause menu --------------------------------------------------------------------


## The save cannot be moved aside. The world is still there, so the pause menu comes back
## with the reason, paused, with New game focused. Keyboard throughout.
func _check_pause_menu_staging_failure() -> void:
	_case = "pause menu, save cannot move"
	Harness.stage = _case
	var world := await _make_saved_world()
	var menu: PauseMenu = world.get_node_or_null(^"PauseMenu") as PauseMenu if world != null else null
	if menu == null:
		_failures.append("%s: main.tscn has no pause menu." % _case)
		return
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(menu.is_open(), "%s: Esc did not open the pause menu." % _case)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_expect_focus(menu.get_entry(&"new_game"), "Down, Down did not reach New game")
	# Back first: Cancel keeps everything and returns the focus.
	await _key(KEY_ENTER)
	await _frames(2)
	_expect(menu.get_confirm().visible, "%s: Enter on New game did not ask first." % _case)
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(menu.is_open() and not menu.get_confirm().visible, "%s: Esc did not just cancel the question." % _case)
	_expect_focus(menu.get_entry(&"new_game"), "cancelling did not return the focus to New game")
	_snapshot()

	await _key(KEY_ENTER)
	await _frames(2)
	await _key(KEY_RIGHT)
	_expect_focus(menu.get_confirm().get_confirm_button(), "Right did not reach the confirm answer")
	var faults := FaultyIO.new()
	faults.fail_renames = [0, 1, 2, 3]
	_save.set("io", faults)
	await _key(KEY_ENTER)
	_save.set("io", null)
	await _frames(3)

	_expect(is_instance_valid(world) and current_scene == world, "%s: the world did not survive." % _case)
	if not is_instance_valid(menu):
		_failures.append("%s: the pause menu was freed." % _case)
		return
	_expect(menu.is_open(), "%s: the pause menu did not come back after the failure." % _case)
	_expect(paused, "%s: the world runs again behind the failed new game." % _case)
	_expect_failure_text(menu.get_notice_text(), "save_stage_failed", true)
	_expect_focus(menu.get_entry(&"new_game"), "the focus is not on New game after the failure")
	_expect_nothing_changed()

	# The language switch renders the same report again, in Chinese, and it fits.
	await _toggle_language()
	_expect(String(_loc.call("get_locale")) == "zh-CN", "%s: the language key did not switch to Chinese." % _case)
	_expect_failure_text(menu.get_notice_text(), "save_stage_failed", true)
	await _expect_readable_at_largest(_notice_label(menu, "Notice"), "pause menu notice")
	await _toggle_language()
	_expect_failure_text(menu.get_notice_text(), "save_stage_failed", true)

	# A press while a new game is already starting is refused, and the menu says why.
	await _key(KEY_ENTER)
	await _frames(2)
	await _key(KEY_RIGHT)
	_expect_focus(menu.get_confirm().get_confirm_button(), "Right did not reach the confirm answer (busy)")
	_session.set("_starting", true)
	await _key(KEY_ENTER)
	_session.set("_starting", false)
	await _frames(2)
	_expect(is_instance_valid(menu) and menu.is_open(), "%s: a busy refusal closed the pause menu." % _case)
	_expect(menu.get_notice_text() == L10n.t(KEY + "busy"), "%s: a busy refusal reads '%s'." % [
		_case, menu.get_notice_text()
	])
	_expect_focus(menu.get_entry(&"new_game"), "the focus is not on New game after a busy refusal")
	_expect_nothing_changed()

	# Back to the run: Esc resumes, and the next time the menu opens the error is gone.
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(not menu.is_open() and not paused, "%s: Esc did not resume after the failure." % _case)
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(menu.is_open(), "%s: Esc did not open the menu again." % _case)
	_expect(menu.get_notice_text().is_empty(), "%s: reopening the menu shows a stale error: '%s'." % [
		_case, menu.get_notice_text()
	])
	await _key(KEY_ESCAPE)
	await _frames(2)
	# And a title screen reached afterwards does not show it a second time.
	var title := await _leave_to_title()
	if title != null:
		_expect(title.get_notice_text().is_empty(), "%s: the title shows an error already shown: '%s'." % [
			_case, title.get_notice_text()
		])


## The opening cannot load: the world is already freed when it fails, so Session takes the
## player to the title, and the title shows what happened - once. Gamepad into the
## failure, then a mouse retry that works and leaves no old error.
func _check_pause_menu_scene_failure() -> void:
	_case = "pause menu, opening cannot load"
	Harness.stage = _case
	var world := await _make_saved_world()
	var menu: PauseMenu = world.get_node_or_null(^"PauseMenu") as PauseMenu if world != null else null
	if menu == null:
		_failures.append("%s: main.tscn has no pause menu." % _case)
		return
	_snapshot()
	var previous_id := _scene_id()
	await _pad(JOY_BUTTON_START)
	await _frames(2)
	_expect(menu.is_open(), "%s: Start did not open the pause menu." % _case)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_expect_focus(menu.get_entry(&"new_game"), "the D-pad did not reach New game")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_expect(menu.get_confirm().visible, "%s: A on New game did not ask first." % _case)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_expect_focus(menu.get_confirm().get_confirm_button(), "the D-pad did not reach the confirm answer")
	_session.set("world_scene", MISSING_SCENE)
	await _pad(JOY_BUTTON_A)
	var title := await _wait_for_title(previous_id)
	_session.set("world_scene", MAIN_SCENE)
	if title == null:
		return
	_expect(not is_instance_valid(world), "%s: the old world is still alive." % _case)
	_expect(not paused, "%s: the title opened paused." % _case)
	_expect(title.get_save_state() == &"valid", "%s: the title reads the save as '%s'." % [
		_case, title.get_save_state()
	])
	_expect_failure_text(title.get_notice_text(), "scene_change_failed", true)
	_expect_focus(title.get_entry(&"new_game"), "the title did not focus New game after the failure")
	_expect_nothing_changed()
	await _expect_readable_at_largest(_notice_label(title, "Notice"), "title notice (opening cannot load)")

	# A title reached again does not repeat it.
	title = await _leave_to_title()
	if title == null:
		return
	_expect(title.get_notice_text().is_empty(), "%s: a second title repeats the error: '%s'." % [
		_case, title.get_notice_text()
	])
	# Try again with the mouse: it works, and nothing of the failure follows the new run.
	await _start_from_title_by_mouse(title)


# --- End card ----------------------------------------------------------------------


## The save cannot be moved aside from the end of the slice: the card stays, says why, and
## Start again keeps the focus. Mouse into the failure, keyboard around it.
func _check_end_card_staging_failure() -> void:
	_case = "end card, save cannot move"
	Harness.stage = _case
	var world := await _make_saved_world()
	var card := await _present_end_card(world)
	if card == null:
		return
	await _click(card.get_restart_button())
	await _frames(2)
	_expect(card.get_confirm().visible, "%s: a click on Start again did not ask first." % _case)
	_snapshot()
	var faults := FaultyIO.new()
	faults.fail_renames = [0, 1, 2, 3]
	_save.set("io", faults)
	await _click(card.get_confirm().get_confirm_button())
	_save.set("io", null)
	await _frames(3)
	_expect(is_instance_valid(world) and current_scene == world, "%s: the world did not survive." % _case)
	if not is_instance_valid(card):
		_failures.append("%s: the end card was freed." % _case)
		return
	_expect(card.visible and card.has_actions(), "%s: the card lost its buttons." % _case)
	_expect_failure_text(_notice_text(card, "EndNotice"), "save_stage_failed", true)
	_expect_focus(card.get_restart_button(), "Start again did not keep the focus after the failure")
	_expect_nothing_changed()
	await _key(KEY_RIGHT)
	_expect_focus(card.get_title_button(), "Right did not reach Title after the failure")
	await _key(KEY_LEFT)
	_expect_focus(card.get_restart_button(), "Left did not come back to Start again")

	await _toggle_language()
	_expect_failure_text(_notice_text(card, "EndNotice"), "save_stage_failed", true)
	await _expect_readable_at_largest(_notice_label(card, "EndNotice"), "end card notice")
	await _toggle_language()

	# Busy: refused, explained, focus kept.
	await _click(card.get_restart_button())
	await _frames(2)
	_session.set("_starting", true)
	await _click(card.get_confirm().get_confirm_button())
	_session.set("_starting", false)
	await _frames(2)
	_expect(_notice_text(card, "EndNotice") == L10n.t(KEY + "busy"), "%s: a busy refusal reads '%s'." % [
		_case, _notice_text(card, "EndNotice")
	])
	_expect_focus(card.get_restart_button(), "Start again lost the focus after a busy refusal")
	_expect_nothing_changed()
	var title := await _leave_to_title()
	if title != null:
		_expect(title.get_notice_text().is_empty(), "%s: the title shows an error already shown: '%s'." % [
			_case, title.get_notice_text()
		])


## The opening was entered and only the staged copy could not be removed: everything is put
## back and the player lands on the title, which shows it. Gamepad throughout.
func _check_end_card_discard_failure() -> void:
	_case = "end card, staged save cannot be removed"
	Harness.stage = _case
	var world := await _make_saved_world()
	var card := await _present_end_card(world)
	if card == null:
		return
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_expect(card.get_confirm().visible, "%s: A on Start again did not ask first." % _case)
	# Back first: B cancels and Start again has the focus again.
	await _pad(JOY_BUTTON_B)
	await _frames(2)
	_expect(not card.get_confirm().visible, "%s: B did not cancel." % _case)
	_expect_focus(card.get_restart_button(), "B did not return the focus to Start again")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_expect_focus(card.get_confirm().get_confirm_button(), "the D-pad did not reach the confirm answer")
	var world_id := world.get_instance_id()
	# The world is not paused under the end card, so the moment before the press is the
	# "before": the transaction restores what it found when it started.
	_snapshot()
	var faults := FaultyIO.new()
	faults.fail_removes = [0]
	_save.set("io", faults)
	await _pad(JOY_BUTTON_A)
	var title := await _wait_for_title(world_id)
	_save.set("io", null)
	if title == null:
		return
	_expect_failure_text(title.get_notice_text(), "staged_discard_failed", true)
	_expect_focus(title.get_entry(&"new_game"), "the title did not focus New game after the failure")
	_expect_nothing_changed()
	_expect(_strays().is_empty(), "%s: the rollback left %s." % [_case, str(_strays())])
	await _toggle_language()
	_expect_failure_text(title.get_notice_text(), "staged_discard_failed", true)
	await _expect_readable_at_largest(_notice_label(title, "Notice"), "title notice (staged save)")
	await _toggle_language()
	title = await _leave_to_title()
	if title != null:
		_expect(title.get_notice_text().is_empty(), "%s: a second title repeats the error: '%s'." % [
			_case, title.get_notice_text()
		])


# --- Title screen ------------------------------------------------------------------


## From the title the save cannot be moved aside: the title stays, says why in the player's
## language, and New game tries again. Mouse, then a keyboard retry that works.
func _check_title_staging_failure() -> void:
	_case = "title, save cannot move"
	Harness.stage = _case
	var title := await _title_with_save()
	if title == null:
		return
	await _click(title.get_entry(&"new_game"))
	await _frames(2)
	_expect(title.get_confirm().visible, "%s: New game did not ask first." % _case)
	var faults := FaultyIO.new()
	faults.fail_renames = [0, 1, 2, 3]
	_save.set("io", faults)
	await _click(title.get_confirm().get_confirm_button())
	_save.set("io", null)
	await _frames(3)
	_expect(is_instance_valid(title) and current_scene == title, "%s: the title did not stay." % _case)
	if not is_instance_valid(title):
		return
	_expect_failure_text(title.get_notice_text(), "save_stage_failed", true)
	_expect_focus(title.get_entry(&"new_game"), "New game does not have the focus after the failure")
	_expect(not title.get_entry(&"new_game").disabled, "%s: New game stayed disabled." % _case)
	_expect_nothing_changed()
	await _toggle_language()
	_expect_failure_text(title.get_notice_text(), "save_stage_failed", true)
	await _toggle_language()

	# Back: Cancel keeps the screen as it is.
	await _click(title.get_entry(&"new_game"))
	await _frames(2)
	await _click(title.get_confirm().get_cancel_button())
	await _frames(2)
	_expect(not title.get_confirm().visible, "%s: Cancel did not close the question." % _case)
	_expect_focus(title.get_entry(&"new_game"), "Cancel did not return the focus to New game")
	_expect_nothing_changed()

	# Busy: refused and explained, and the entries stay usable.
	await _click(title.get_entry(&"new_game"))
	await _frames(2)
	_session.set("_starting", true)
	await _click(title.get_confirm().get_confirm_button())
	_session.set("_starting", false)
	await _frames(2)
	_expect(title.get_notice_text() == L10n.t(KEY + "busy"), "%s: a busy refusal reads '%s'." % [
		_case, title.get_notice_text()
	])
	_expect(not title.get_entry(&"new_game").disabled, "%s: a busy refusal left New game disabled." % _case)
	_expect_focus(title.get_entry(&"new_game"), "New game lost the focus after a busy refusal")
	_expect_nothing_changed()

	# Try again with the keyboard; it works.
	await _key(KEY_ENTER)
	await _frames(2)
	await _key(KEY_RIGHT)
	_expect_focus(title.get_confirm().get_confirm_button(), "Right did not reach the confirm answer")
	await _start_and_check_clean(title, func() -> void: await _key(KEY_ENTER))


## From the title the opening is entered (the title is freed) and then the staged save
## cannot be removed: Session rolls back to a new title, which must show it - once.
func _check_title_discard_failure() -> void:
	_case = "title, staged save cannot be removed"
	Harness.stage = _case
	var title := await _title_with_save()
	if title == null:
		return
	_expect_focus(title.get_entry(&"continue"), "Continue is not focused first")
	await _key(KEY_DOWN)
	_expect_focus(title.get_entry(&"new_game"), "Down did not reach New game")
	await _key(KEY_ENTER)
	await _frames(2)
	await _key(KEY_RIGHT)
	_expect_focus(title.get_confirm().get_confirm_button(), "Right did not reach the confirm answer")
	var title_id := title.get_instance_id()
	var faults := FaultyIO.new()
	faults.fail_removes = [0]
	_save.set("io", faults)
	await _key(KEY_ENTER)
	var next := await _wait_for_title(title_id)
	_save.set("io", null)
	if next == null:
		return
	_expect_failure_text(next.get_notice_text(), "staged_discard_failed", true)
	_expect_focus(next.get_entry(&"new_game"), "the new title did not focus New game")
	_expect_nothing_changed()
	var again := await _leave_to_title()
	if again != null:
		_expect(again.get_notice_text().is_empty(), "%s: a second title repeats the error: '%s'." % [
			_case, again.get_notice_text()
		])


# --- Shared steps ------------------------------------------------------------------


## A running world with a real autosave behind it, as the current scene.
func _make_saved_world() -> Node:
	paused = false
	await _free_current_scene()
	Harness.clear_session_state(self)
	for flag: StringName in [StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING]:
		_game_state.set_flag(flag, true)
	_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")
	_narrative.record(PROBE_ENTRY, NarrativeEntry.Source.OBSERVED, &"", "A probe the failure must keep.")
	var packed: PackedScene = load(MAIN_SCENE)
	var world := packed.instantiate()
	var director := world.get_node_or_null(^"OpeningSequence")
	if director != null:
		director.set("autostart", false)
	root.add_child(world)
	current_scene = world
	await _frames(3)
	var written: Dictionary = _save.save_game()
	_expect(bool(written.get("ok", false)), "%s: the probe save was not written: %s" % [_case, str(written)])
	_write_quarantine()
	return world


## A title screen with a readable save behind it (and a quarantined copy beside it).
func _title_with_save() -> TitleScreen:
	paused = false
	await _free_current_scene()
	Harness.clear_session_state(self)
	_game_state.set_flag(StoryFlags.MET_Q, true)
	var written: Dictionary = _save.write_payload({"flags": {}, "entries": [], "check_seed": 0})
	_expect(bool(written.get("ok", false)), "%s: the title fixture save was not written." % _case)
	_write_quarantine()
	_snapshot()
	var previous_id := _scene_id()
	change_scene_to_file(TITLE_SCENE)
	return await _wait_for_title(previous_id)


func _write_quarantine() -> void:
	var file := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("%s: the quarantine fixture could not be written." % _case)
		return
	file.store_string("{ quarantined probe for %s" % _case)
	file.close()


func _present_end_card(world: Node) -> EndCard:
	var card: EndCard = world.find_child("EndCard", true, false) as EndCard if world != null else null
	if card == null:
		_failures.append("%s: main.tscn has no end card." % _case)
		return null
	card.present("End of this build", "A probe for the failure check.", "")
	await _frames(4)
	_expect(card.has_actions(), "%s: the end card offers no Start again." % _case)
	_expect_focus(card.get_restart_button(), "Start again is not focused on the end card")
	return card


func _snapshot() -> void:
	_save_before = FileAccess.get_file_as_bytes(SAVE_PATH)
	_quarantine_before = FileAccess.get_file_as_bytes(BROKEN_PATH)
	_flags_before = _game_state.get_snapshot()
	_entries_before = _narrative.get_entries().size()


func _expect_nothing_changed() -> void:
	_expect(
		FileAccess.file_exists(SAVE_PATH) and FileAccess.get_file_as_bytes(SAVE_PATH) == _save_before,
		"%s: the save on disk is not the save from before." % _case
	)
	_expect(
		FileAccess.file_exists(BROKEN_PATH)
		and FileAccess.get_file_as_bytes(BROKEN_PATH) == _quarantine_before,
		"%s: the quarantined copy changed or disappeared." % _case
	)
	var flags_now: Dictionary = _game_state.get_snapshot()
	_expect(flags_now == _flags_before, "%s: the story flags changed: %s." % [
		_case, _flag_diff(_flags_before, flags_now)
	])
	_expect(_narrative.get_entries().size() == _entries_before, "%s: the knowledge log changed." % _case)
	_expect(not bool(_session.call("is_starting_new_game")), "%s: the session is still busy." % _case)


## The text a failure must show: the line for its reason, in the current language, and
## that the save is safe. Never the log's English detail.
func _expect_failure_text(text: String, reason: String, kept: bool) -> void:
	var headline := L10n.t(KEY + reason)
	_expect(
		text.contains(headline),
		"%s [%s]: the notice does not say why ('%s'); it reads '%s'." % [
			_case, L10n.current, headline, text
		]
	)
	if kept:
		_expect(
			text.contains(L10n.t(KEY + "kept")),
			"%s [%s]: the notice does not say the save is safe; it reads '%s'." % [_case, L10n.current, text]
		)
	_expect(
		not text.contains("(") and not text.contains("user://save.json."),
		"%s [%s]: the notice shows the log detail: '%s'." % [_case, L10n.current, text]
	)


## At the largest text size the whole message is on screen, nothing cut off - in the
## language that is current and in the other one.
func _expect_readable_at_largest(label: Label, what: String) -> void:
	if label == null:
		_failures.append("%s: there is no %s to measure." % [_case, what])
		return
	_settings.call("set_text_size", &"largest")
	for _pass in 2:
		await _frames(3)
		var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1.0)
		var rect := label.get_global_rect()
		var language := L10n.current
		_expect(label.is_visible_in_tree() and not label.text.is_empty(), "%s [%s]: the %s is not visible." % [
			_case, language, what
		])
		_expect(view.encloses(rect), "%s [%s]: the %s runs off the screen (%s in %s)." % [
			_case, language, what, str(rect), str(view)
		])
		_expect(
			label.get_visible_line_count() >= label.get_line_count(),
			"%s [%s]: the %s shows %d of %d lines." % [
				_case, language, what, label.get_visible_line_count(), label.get_line_count()
			]
		)
		var size := label.get_theme_font_size(&"font_size")
		_expect(
			size >= roundi(float(MenuStyle.BODY_SIZE) * LARGEST_SCALE) - 1,
			"%s [%s]: the %s is set at %d px at the largest text size." % [_case, language, what, size]
		)
		await _toggle_language()
	_settings.call("set_text_size", &"standard")
	await _frames(2)


## Start from a title by mouse, check that it is a clean start, and go back to the title.
func _start_from_title_by_mouse(title: TitleScreen) -> void:
	await _click(title.get_entry(&"new_game"))
	await _frames(2)
	_expect(title.get_confirm().visible, "%s: New game did not ask first (retry)." % _case)
	await _start_and_check_clean(title, func() -> void: await _click(title.get_confirm().get_confirm_button()))


## Presses confirm with `press`, expects the opening, and then a title with no old error.
func _start_and_check_clean(title: TitleScreen, press: Callable) -> void:
	var started: Array = []
	var failed: Array = []
	var on_started := func(report: Dictionary) -> void: started.append(report)
	var on_failed := func(report: Dictionary) -> void: failed.append(report)
	_session.connect("new_game_started", on_started)
	_session.connect("new_game_failed", on_failed)
	var title_id := title.get_instance_id()
	await press.call()
	var world := await _wait_for_world(title_id)
	_session.disconnect("new_game_started", on_started)
	_session.disconnect("new_game_failed", on_failed)
	_expect(started.size() == 1 and failed.is_empty(), "%s: the retry did not start one clean new game (%d started, %d failed)." % [
		_case, started.size(), failed.size()
	])
	if world == null:
		return
	var next := await _leave_to_title()
	if next != null:
		_expect(next.get_notice_text().is_empty(), "%s: after a new game that started, the title shows '%s'." % [
			_case, next.get_notice_text()
		])


func _leave_to_title() -> TitleScreen:
	paused = false
	var previous_id := _scene_id()
	if current_scene != null:
		var director := current_scene.get_node_or_null(^"OpeningSequence")
		if director != null:
			director.set("autosave_enabled", false)
	_session.call("go_to_title")
	return await _wait_for_title(previous_id)


func _scene_id() -> int:
	return current_scene.get_instance_id() if current_scene != null else 0


## A notice label found by name, so this check does not depend on an accessor the screen
## may not have.
func _notice_label(screen: Node, label_name: String) -> Label:
	return screen.find_child(label_name, true, false) as Label if screen != null else null


func _notice_text(screen: Node, label_name: String) -> String:
	var label := _notice_label(screen, label_name)
	return label.text if label != null and label.is_visible_in_tree() else ""


## `previous_id` is the instance id of the scene that was current before the press: it
## may be freed by now, and a freed node cannot be passed or compared safely.
func _wait_for_title(previous_id: int) -> TitleScreen:
	for _index in 300:
		await process_frame
		if current_scene is TitleScreen and current_scene.get_instance_id() != previous_id:
			await _frames(3)
			return current_scene as TitleScreen
	_failures.append("%s: no new title screen became the current scene (%s)." % [
		_case, current_scene.name if current_scene != null else "nothing"
	])
	return null


func _wait_for_world(previous_id: int) -> Node:
	for _index in 300:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != previous_id \
				and current_scene.scene_file_path == MAIN_SCENE:
			await _frames(3)
			return current_scene
	_failures.append("%s: the game never entered main.tscn." % _case)
	return null


func _free_current_scene() -> void:
	var scene := current_scene
	if scene != null:
		var director := scene.get_node_or_null(^"OpeningSequence")
		if director != null:
			director.set("autosave_enabled", false)
		scene.queue_free()
	await _frames(3)
	if _save != null:
		_save.unbind_world()


## "flag: before -> now" for every flag that differs.
func _flag_diff(before: Dictionary, now: Dictionary) -> String:
	var lines := PackedStringArray()
	var keys: Array = before.keys()
	for key: Variant in now.keys():
		if not keys.has(key):
			keys.append(key)
	for key: Variant in keys:
		var was: Variant = before.get(key, "<unset>")
		var is_now: Variant = now.get(key, "<unset>")
		if typeof(was) != typeof(is_now) or was != is_now:
			lines.append("%s: %s -> %s" % [str(key), str(was), str(is_now)])
	return ", ".join(lines)


func _strays() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return found
	for name: String in dir.get_files():
		if name.begins_with("save.json."):
			found.append(name)
	return found


# --- Input -------------------------------------------------------------------------


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)
		await process_frame


## Both halves through the Input singleton, as in `title_menu_interaction_test.gd`: under
## Xvfb a half-open synthetic pad would otherwise keep a button held.
func _pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


## A real pointer press and release on the middle of the button.
func _click(button: Button) -> void:
	if button == null or not button.is_visible_in_tree():
		_failures.append("%s: a button to click is missing or hidden." % _case)
		return
	await process_frame
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame


## The player's language key, from the input map rather than a hard-coded key.
func _toggle_language() -> void:
	for event: InputEvent in InputMap.action_get_events(&"toggle_language"):
		var key := event as InputEventKey
		if key == null:
			continue
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var before := L10n.current
		await _key(code)
		await _frames(2)
		_expect(L10n.current != before, "%s: the language key did not switch the language." % _case)
		return
	_failures.append("%s: toggle_language has no key." % _case)


func _expect_focus(control: Control, what: String) -> void:
	var focused := root.gui_get_focus_owner()
	if focused == control:
		return
	_failures.append("%s: %s (focus on %s)." % [
		_case, what, String(focused.name) if focused != null else "nothing"
	])
	# Put it where the case needs it, so one miss does not cascade into the next step.
	if control != null and control.is_visible_in_tree():
		control.grab_focus()


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
