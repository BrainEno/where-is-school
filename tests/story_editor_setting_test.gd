extends SceneTree
## The story editor switch, on the real pause menu and the real classroom (#338 follow-up).
##
## Settings → 「剧情编辑」 is the only way a player's copy reaches the editor: off (the
## default) means no `StoryEditor` autoload, no 「剧情编辑」 button in the world and no draft
## read; on installs both, and the pause menu gains a sixth entry that opens the drawer over
## the running world. Drafts and the bridge exchange live in `user://story_editor/`, apart
## from `user://save.json`, and the switch survives a restart without touching any other
## preference.
##
## F9 moves the same switch from anywhere in the run, which is what makes a preferences file
## this machine refuses unable to lock the author out of their own tool (#396). This file is the
## switch, the entry and the key; the editor's own behaviour (edit, insert, trial walk, export) is
## `tests/authoring_classroom_test.gd`.

const Harness := preload("res://tests/test_harness.gd")
const MainScene := preload("res://scenes/main/main.tscn")
const SettingsScript := preload("res://scripts/autoload/settings_manager.gd")
const StoryEditorEntry := preload("res://scripts/ui/story_editor_entry.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")

const TIMEOUT_SECONDS := 150.0
const DRAFT_DIR := "user://story_editor"
const SETTINGS_PATH := SettingsStore.PATH
const SAVE_PATH := "user://save.json"


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "story_editor_setting_test.gd")
	call_deferred("_run")


func _run() -> void:
	var check := Harness.Checker.new()
	if not check.expect(not FileAccess.file_exists(SETTINGS_PATH) and not FileAccess.file_exists(SAVE_PATH)
			and not DirAccess.dir_exists_absolute(DRAFT_DIR), "Use a fresh, isolated user directory"):
		Harness.finish(self, check.failures, "")
		return
	Harness.ensure_state_autoloads(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	loc.set_locale("en")
	loc.set_locale("zh-CN")
	var settings := Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	check.expect(not settings.is_story_editor_enabled(), "A fresh settings file must start with the story editor off")
	settings.set_volume(&"music", 37)
	_check_interrupted_swap(check, settings, loc)
	await _check_dev_override(check, settings)
	var world := await _boot_world(check)
	await _check_off_by_default(check, world)
	await _check_entry_follows_switch(check, world, settings)
	await _check_restart_and_disable(check, world, settings)
	check.expect(not FileAccess.file_exists(SAVE_PATH), "The editor preference or drawer created a gameplay save")
	paused = false
	world.queue_free()
	await process_frame
	Harness.finish(self, check.failures,
		"story editor opt-in: save refusal, on/off, fresh settings load, pause handoff, and save isolation")


func _boot_world(check: Harness.Checker) -> Node:
	Harness.stage = "the real classroom with the switch off"
	var world := MainScene.instantiate()
	var opening := world.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(world)
	current_scene = world
	opening.allow_player_control()
	world.get_node(^"InnerVoiceDirector").set_process(false)
	var ui := world.get_node(^"GameUI") as GameUI
	ui.fade.set_clear()
	# The opening director would queue its own beats over the menu; this check is about the
	# pause menu and the editor install, not the prologue.
	opening.set_process(false)
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1600, 900)
	await process_frame
	check.expect(world.get_node_or_null(^"PauseMenu") != null, "The classroom has no pause menu")
	return world


func _check_off_by_default(check: Harness.Checker, world: Node) -> void:
	Harness.stage = "off: no editor installed, no launcher, no draft read"
	check.expect(root.get_node_or_null(^"StoryEditor") == null,
		"The editor autoload exists before the switch is on")
	check.expect(world.get_node_or_null(^"AuthorOverlay/EditStory") == null,
		"The world offers a story editor launcher while the switch is off")
	var menu := world.get_node(^"PauseMenu") as PauseMenu
	menu.open()
	await process_frame
	check.expect(menu.get_entry(&"story_editor") == null, "The pause menu shows the editor entry while off")
	check.expect(menu.get_story_editor() == null and not menu.open_story_editor(),
		"The pause menu opens an editor that was never installed")
	menu.close()
	await process_frame
	check.expect(not DirAccess.dir_exists_absolute(DRAFT_DIR + "/share"),
		"Turning nothing on created the bridge exchange folder")


func _check_entry_follows_switch(check: Harness.Checker, world: Node, settings: Node) -> void:
	Harness.stage = "on: the settings row installs the editor and the pause entry"
	var menu := world.get_node(^"PauseMenu") as PauseMenu
	menu.open()
	await process_frame
	var panel := menu.get_settings_panel()
	menu.activate(&"settings")
	await process_frame
	var row := panel.get_row_control(&"story_editor") as Button
	if not check.expect(row != null and row.is_visible_in_tree(), "Settings has no Story editor row"):
		menu.close()
		return
	check.expect(row.text.contains(L10n.t("settings.off")), "The row does not show the switch off")
	# Geometry is a touch rule: on desktop the row simply has to be reachable in the list.
	panel.focus_row(&"story_editor")
	await process_frame
	if MobileLayout.enabled:
		check.expect(MobileLayout.safe_rect(row).encloses(row.get_global_rect()) \
				and row.size.y >= MobileLayout.hit_size(row),
			"The Story editor row is outside the safe area or smaller than a finger")
	_check_wedged_backup(check, panel, settings)
	# A legacy fixed stage must never block an update or be overwritten by it.
	var legacy_stage := SETTINGS_PATH + ".tmp"
	check.expect(DirAccess.make_dir_absolute(legacy_stage) == OK, "Could not arrange the legacy stage fixture")
	panel.cycle(&"story_editor", 1)
	check.expect(DirAccess.dir_exists_absolute(legacy_stage), "Saving removed the unrelated legacy stage directory")
	DirAccess.remove_absolute(legacy_stage)
	await process_frame
	check.expect(panel.get_status_text() == L10n.t("settings.done_note"), "A stored switch gave no saved feedback")
	check.expect(bool(settings.call("is_story_editor_enabled")), "The row did not turn the switch on")
	row = panel.get_row_control(&"story_editor") as Button
	check.expect(row != null and row.text.contains(L10n.t("settings.on")), "The row does not show the switch on")
	panel.close()
	await process_frame
	var entry := menu.get_story_entry()
	if not check.expect(entry != null and entry.is_visible_in_tree(), "The pause menu has no entry after switching on"):
		menu.close()
		return
	check.expect(entry.pressed.get_connections().size() == 1, "Repeated sync connected the entry more than once")
	if not check.expect(await Harness.wait_until(func() -> bool:
		return world.has_node(^"AuthorOverlay") and root.has_node(^"StoryEditor")
	, 5.0), "The editor overlay did not attach to the classroom"):
		menu.close()
		return
	# Press the real connected entry while the world is paused.
	entry.pressed.emit()
	await process_frame
	var overlay := world.get_node(^"AuthorOverlay")
	check.expect(overlay.is_editing() and paused and not menu.is_open(), "The menu did not hand its pause to the editor")
	overlay.close_editor()
	check.expect(not overlay.is_editing() and not paused, "Closing the editor did not resume the world")


## A leftover nobody can remove must not be able to wedge the preferences file. The name
## `settings.cfg.bak` is where the swap would put the previous file, and a directory of that
## name - or a read-only copy an outside tool holds - used to refuse every later settings
## change, which is how an author ends up unable to turn the editor on at all (#394). The
## swap now takes another name, publishes, and leaves what it does not own alone.
func _check_wedged_backup(check: Harness.Checker, panel: SettingsPanel, settings: Node) -> void:
	Harness.stage = "a backup name somebody else occupies"
	var backup := SettingsStore.BACKUP_PATH
	var made_dir := false
	if not DirAccess.dir_exists_absolute(backup):
		if FileAccess.file_exists(backup):
			# A copy an earlier run left without confirming its publish - ours by name, and
			# removable, which is not the case this check is about.
			DirAccess.remove_absolute(backup)
		made_dir = DirAccess.make_dir_absolute(backup) == OK
		if not check.expect(made_dir, "Could not create the wedged-backup fixture"):
			return
	# Non-empty, the way a person's own folder beside the file would be: a remove of an empty
	# directory succeeds, and then this fixture would say nothing about what we do not own.
	var held := backup.path_join("keep.txt")
	var holding := FileAccess.open(held, FileAccess.WRITE)
	if not check.expect(holding != null, "Could not fill the wedged-backup fixture"):
		DirAccess.remove_absolute(backup)
		return
	holding.store_string("left here by whoever made this folder\n")
	holding.close()
	panel.cycle(&"story_editor", 1)
	check.expect(bool(settings.call("is_story_editor_enabled")),
		"A settings change was refused because the usual backup name was occupied")
	check.expect(panel.get_status_text() == L10n.t("settings.done_note"), "A published switch gave no saved feedback")
	var written := ConfigFile.new()
	check.expect(written.load(SETTINGS_PATH) == OK and bool(written.get_value("authoring", "story_editor", false)) \
			and int(written.get_value("audio", "music", -1)) == 37,
		"The published file lost the switch or the volume it did not own")
	check.expect(DirAccess.dir_exists_absolute(backup), "The swap removed a directory it does not own")
	var staying: Array[String] = []
	for path: String in SettingsStore.leftovers():
		if FileAccess.file_exists(path):
			staying.append(path)
	check.expect(staying.is_empty(),
		"A copy this swap made stayed after a verified publish: %s" % str(staying))
	panel.cycle(&"story_editor", 1)
	check.expect(not settings.is_story_editor_enabled(), "The switch could not be turned off again")
	DirAccess.remove_absolute(held)
	if made_dir:
		check.expect(DirAccess.remove_absolute(backup) == OK, "Could not clean up the wedged-backup fixture")


func _check_interrupted_swap(check: Harness.Checker, settings: Node, loc: Node) -> void:
	Harness.stage = "settings survive a refused publication and interrupted rollback"
	var prior := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	var candidate := SettingsStore.open()
	candidate.set_value("authoring", "story_editor", true)
	var stage := SETTINGS_PATH + ".test-stage"
	if not check.expect(not prior.is_empty() and candidate.save(stage) == OK, "Could not stage fixture preferences"):
		return
	var refuse_stage := func(from: String, to: String) -> Error:
		return ERR_FILE_CANT_WRITE if from == stage else DirAccess.rename_absolute(from, to)
	check.expect(SettingsStore._publish(stage, refuse_stage) == ERR_FILE_CANT_WRITE,
		"A failed publication reported success")
	check.expect(FileAccess.get_file_as_bytes(SETTINGS_PATH) == prior,
		"Failure did not restore the previous settings byte for byte")
	# The second refusal stops the publication *and* the rollback, so the preferences live only
	# in the copy the swap made. Which name that copy has depends on what was already beside the
	# file - that is the point of #394 - so everything below follows the bytes, not a path.
	var refuse_primary := func(from: String, to: String) -> Error:
		return ERR_FILE_CANT_WRITE if to == SETTINGS_PATH else DirAccess.rename_absolute(from, to)
	var report := {}
	check.expect(SettingsStore._publish(stage, refuse_primary, report) == ERR_FILE_CANT_WRITE,
		"An interrupted swap reported success")
	var resting := _resting_copy(prior)
	check.expect(not resting.is_empty()
			and String(report.get("step", "")).contains(resting)
			and int(report.get("error", OK)) == ERR_FILE_CANT_WRITE,
		"A swap that could not publish or roll back did not say where the previous file waits: %s"
			% str(report))
	check.expect(not FileAccess.file_exists(SETTINGS_PATH) and not resting.is_empty(),
		"An interrupted swap lost the previous settings")
	settings.load_settings()
	check.expect(settings.get_volume(&"music") == 37 and not settings.is_story_editor_enabled()
			and loc._load_saved_locale() == "zh-CN", "Settings and Loc did not both read the recovered copy")
	check.expect(SettingsStore.write(SettingsStore.open()) == OK and FileAccess.file_exists(SETTINGS_PATH)
			and not FileAccess.file_exists(resting), "Next write did not recover from an interrupted swap")
	DirAccess.remove_absolute(stage)


## The newest leftover that holds exactly `bytes`, or "" when none does. This is what `read()`
## has to find after a half-finished swap, and what a verified publish has to clear away.
static func _resting_copy(bytes: PackedByteArray) -> String:
	for path: String in SettingsStore.leftovers():
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
			return path
	return ""


## The two ways a development run keeps the editor reachable: the launch override, which needs
## no file at all, and a switch the machine refused to store - which is refused on a player's copy
## and installed for the session on an author's run (#394, #395).
func _check_dev_override(check: Harness.Checker, settings: Node) -> void:
	Harness.stage = "the development override and the session-only switch"
	if not StoryEditorEntry.scripts_present():
		print("NOTE: this build has no editor scripts, so the override has nothing to install")
		return
	var asked := PackedStringArray(["--story-editor"])
	check.expect(StoryEditorEntry.development_requested(asked, ""),
		"--story-editor did not ask for the editor")
	check.expect(StoryEditorEntry.development_requested(PackedStringArray(), "1"),
		"The development environment variable did not ask for the editor")
	check.expect(not StoryEditorEntry.development_requested(PackedStringArray(["--editor"]), "0"),
		"An unrelated argument or value turned the editor on")
	check.expect(StoryEditorEntry.development_override()
			== StoryEditorEntry.development_requested(
				OS.get_cmdline_user_args(), OS.get_environment(StoryEditorEntry.DEVELOPMENT_ENVIRONMENT)),
		"The override the settings load honours is not the rule it states")
	# The boot default of #395 must not reach in here: this harness is a `--script` launch,
	# which is precisely the run `development_default()` excludes so a test can still speak
	# as a player's copy - so `Settings` reading a fresh file below really does start off.
	check.expect(not StoryEditorEntry.development_default(),
		"A scripted harness run must not boot with the story editor forced on")
	# The live line editor follows the same window as the boot default: this harness is a
	# `--script` run, so a development project under the test still gets the drawer only.
	# The staged authoring app reaches live through `isolated_author()`, not this gate.
	check.expect(not StoryEditorEntry.live_editing_allowed(),
		"A scripted harness run may attach the live line editor")
	# Assert contexts this scripted harness cannot itself inhabit, including the allowed desktop window.
	var rows := [
		[false, false, false, false, false, true], [false, false, false, false, false, true],
		[true, false, false, false, false, false], [false, true, false, false, false, false],
		[false, false, true, false, false, false], [false, false, false, true, false, false],
		[false, false, false, false, true, false],
	]
	for row: Array in rows:
		check.expect(StoryEditorEntry.development_window_allows(row[0], row[1], row[2], row[3], row[4]) == row[5],
			"The live editing gate misclassified a launch context")
	# What each outcome reads as on the row, and the step inside it: `saved` is the file, `moved`
	# is the switch, and the two come apart in a development run - which is why one sentence cannot
	# serve both. The tables have to carry the placeholder, or the sentence arrives with "{step}"
	# in it on one language.
	check.expect(SettingsPanel._story_feedback_key(true, true, "") == "settings.done_note",
		"A stored switch did not read as saved")
	check.expect(SettingsPanel._story_feedback_key(false, false, "publish staged preferences")
			== "settings.save_failed_step", "A refused switch did not name the step it refused")
	check.expect(SettingsPanel._story_feedback_key(false, true, "publish staged preferences")
			== "settings.session_only_note", "A session-only install claimed the switch was unchanged")
	for locale: String in ["zh-CN", "en"]:
		var only := L10n.t_for("settings.session_only_note", locale)
		check.expect(only.contains("{step}"),
			"The %s table has no {step} for the session-only note" % locale)
		# One sentence serves both directions of a session-only change, so it cannot repeat the
		# refusal's claim that the switch did not move: F9 moves it without the file.
		var unchanged := "开关未更改" if locale == "zh-CN" else "has not changed"
		check.expect(not only.contains(unchanged),
			"The %s session-only note says the switch did not move, which is what the key just did"
			% locale)
	var refused := RefusedStore.new()
	check.expect(SettingsPanel._store_failure_step(refused) == "publish staged preferences",
		"The settings row did not read the step a refused write reported")
	check.expect(SettingsPanel._store_failure_step(null) == ""
			and SettingsPanel._store_failure_step(Node.new()) == "",
		"A settings node with no report made the row claim a cause it does not have")
	refused.free()
	_check_hotkey_presses(check)
	_check_packaging_keeps_the_authoring_out(check)
	await _hold_preferences_hostage(check, settings)


## The file is moved aside whole and put back, so a refused write here cannot cost the run a
## preference it already had; the directory in its place is the case a rename cannot step over.
func _hold_preferences_hostage(check: Harness.Checker, settings: Node) -> void:
	Harness.stage = "a preferences write the machine refuses, as a player and as an author"
	var hold := SETTINGS_PATH + ".author-hold"
	if not check.expect(DirAccess.rename_absolute(SETTINGS_PATH, hold) == OK
			and DirAccess.make_dir_absolute(SETTINGS_PATH) == OK,
			"Could not block the preferences file for the session-only check"):
		return
	StoryEditorEntry.debug_run = false
	check.expect(not bool(settings.call("set_story_editor_enabled", true))
			and not bool(settings.call("is_story_editor_enabled")),
		"A player's copy turned the editor on over a preferences write it could not make")
	StoryEditorEntry.debug_run = true
	check.expect(not bool(settings.call("set_story_editor_enabled", true))
			and bool(settings.call("is_story_editor_enabled")),
		"An author's run was locked out of the tool by a file it could not write, or the switch "
		+ "said the refused write had saved it")
	var failure: Variant = settings.call("get_last_store_failure")
	check.expect(failure is Dictionary and not String((failure as Dictionary).get("step", "")).is_empty(),
		"The session-only install did not report which step the write failed at")
	await _check_hotkey_over_a_refused_write(check, settings)
	DirAccess.remove_absolute(SETTINGS_PATH)
	if not check.expect(DirAccess.rename_absolute(hold, SETTINGS_PATH) == OK,
			"Could not put the blocked preferences file back"):
		return
	StoryEditorEntry.debug_run = OS.is_debug_build()
	check.expect(bool(settings.call("set_story_editor_enabled", false))
			and not bool(settings.call("is_story_editor_enabled")),
		"Once the file was writable again the session-only switch could not be turned off")


## What one key is allowed to mean. The key decides nothing on its own - who may use it is the
## entry's rule - so this is about what counts as asking, and about a run that must not answer.
func _check_hotkey_presses(check: Harness.Checker) -> void:
	Harness.stage = "what counts as the story-editor key"
	check.expect(StoryEditorEntry.HOTKEY == KEY_F9,
		"The story-editor key is not the F9 the settings row promises")
	var release := _story_key(StoryEditorEntry.HOTKEY, false)
	var repeated := _story_key(StoryEditorEntry.HOTKEY)
	repeated.echo = true
	var chord := _story_key(StoryEditorEntry.HOTKEY)
	chord.ctrl_pressed = true
	check.expect(StoryEditorEntry.hotkey_pressed(_story_key(StoryEditorEntry.HOTKEY))
			and not StoryEditorEntry.hotkey_pressed(release)
			and not StoryEditorEntry.hotkey_pressed(repeated)
			and not StoryEditorEntry.hotkey_pressed(chord)
			and not StoryEditorEntry.hotkey_pressed(_story_key(KEY_F8))
			and not StoryEditorEntry.hotkey_pressed(InputEventMouseButton.new())
			and not StoryEditorEntry.hotkey_pressed(null),
		"The story-editor key did not answer to exactly one fresh, unmodified press")
	# A key is an author's tool, not a player's shortcut. In a run that is not a development run -
	# every release export, and the iOS package that does carry the runtime - the press is not this
	# code's to take, and the report says nothing rather than refusing something never offered.
	var settings := root.get_node(^"Settings") as Node
	var was_on := bool(settings.call("is_story_editor_enabled"))
	StoryEditorEntry.debug_run = false
	var silent: Dictionary = StoryEditorEntry.toggle(root)
	check.expect(String(silent["step"]).is_empty() and not bool(silent["changed"])
			and not bool(silent["saved"]) and not bool(silent["enabled"]),
		"A run that is not an author's run answered the story-editor key")
	check.expect(bool(settings.call("is_story_editor_enabled")) == was_on,
		"A key nobody was allowed to press still moved the switch")
	StoryEditorEntry.debug_run = OS.is_debug_build()


## The key pushed through the real input path while the preferences file is held hostage, which is
## the one run where it has to prove something. The hook's place is the engine's own order
## (`Viewport::push_input`, 4.7.2-stable): `_input` first, so a rebinding capture in the settings
## screen keeps the key it asked for; the GUI next; then `_shortcut_input`, which is this, before
## the pause menu and the open editor each take every key in `_unhandled_input`.
func _check_hotkey_over_a_refused_write(check: Harness.Checker, settings: Node) -> void:
	Harness.stage = "the story-editor key over a refused write"
	var session := Harness.ensure_autoload(
		self, "Session", "res://scripts/ui/game_session.gd")
	if not check.expect(session != null,
			"The node that owns the key could not be created, so the push below proves nothing"):
		return
	check.expect(bool(session.call("is_processing_shortcut_input")),
		"The owner of the key is not receiving shortcut input, so the engine would never hand it F9")
	if not check.expect(await Harness.wait_until(
			func() -> bool: return root.has_node(^"StoryEditor"), 5.0),
			"The session-only install never put the editor on the tree"):
		return
	root.push_input(_story_key(StoryEditorEntry.HOTKEY), true)
	check.expect(root.is_input_handled(),
		"The story-editor key was left to the game in an author's run")
	check.expect(await Harness.wait_until(func() -> bool:
		return not bool(settings.call("is_story_editor_enabled")) and not root.has_node(^"StoryEditor")
	, 5.0), "The key could not put the editor away without a writable preferences file")
	root.push_input(_story_key(StoryEditorEntry.HOTKEY), true)
	if check.expect(await Harness.wait_until(func() -> bool:
		return bool(settings.call("is_story_editor_enabled")) and root.has_node(^"StoryEditor")
	, 5.0), "The key could not open the editor again without a writable preferences file"):
		root.push_input(_story_key(KEY_F8), true)
		check.expect(not root.is_input_handled(),
			"An unrelated key was eaten by the story-editor hook")
	# Off for the checks that follow, which expect a run with no editor on the tree. The file is
	# still hostage here, so this is the session-only direction, not a stored one.
	settings.call("set_story_editor_enabled", false)
	check.expect(await Harness.wait_until(
			func() -> bool: return not root.has_node(^"StoryEditor"), 5.0),
		"Leaving this fixture put the editor on the tree for the checks that follow")


## The separation the author has to be able to count on: the tool lives in one folder, the export
## presets switch it off, and the code that stays in a player's package answers only while that
## folder is really in it. This reads the file the exporter reads, so a preset added later without
## the filter fails here rather than shipping a menu nobody meant to publish. The one preset that
## exists to carry the tool - the Windows developer build of #395 - is asserted the other way
## round: if it ever stops including `scripts/story_editor/*`, the double-click run loses the
## editor this issue is about, and this check says so before the export does.
func _check_packaging_keeps_the_authoring_out(check: Harness.Checker) -> void:
	Harness.stage = "what a player's export leaves out, and what the developer build carries"
	var config := ConfigFile.new()
	if not check.expect(config.load("res://export_presets.cfg") == OK,
			"export_presets.cfg could not be read to check what ships out"):
		return
	var dropped: Array[String] = ["scripts/story_editor/*", "scripts/dev/*", "tests/*", "tools/*", "addons/*"]
	var kept_out: Array[String] = ["scripts/dev/*", "tests/*", "tools/*", "addons/*"]
	var index := 0
	var presets := 0
	var developer := false
	while config.has_section("preset.%d" % index):
		var section := "preset.%d" % index
		var preset := String(config.get_value(section, "name", ""))
		var excludes := String(config.get_value(section, "exclude_filter", ""))
		if preset == "iOS":
			# The one package that carries the runtime, because the device app has the opt-in row;
			# `_check_hotkey_presses` is the evidence that a released run of it answers nothing.
			check.expect(excludes.contains("addons/*") and excludes.contains("tests/*"),
				"The iOS export ships the editor-only addon or the test scripts")
		elif preset == "Windows Dev":
			# The developer build is the exception that proves the rule above: it carries the
			# editor on purpose (and `development_default()` turns it on at boot), while still
			# leaving the harness and the authoring sources themselves out of the pack.
			developer = true
			check.expect(not excludes.contains("scripts/story_editor/*"),
				"The Windows Dev export leaves the story editor out of the pack it exists to carry")
			for filter: String in kept_out:
				check.expect(excludes.contains(filter),
					"The Windows Dev export ships %s, which is not part of the game it previews"
					% filter)
		else:
			for filter: String in dropped:
				check.expect(excludes.contains(filter),
					"The %s export ships %s, which the author's tool needs to run" % [preset, filter])
		presets += 1
		index += 1
	check.expect(presets >= 3,
		"Fewer than the three player-facing export presets were readable")
	check.expect(developer,
		"The Windows Dev preset is gone, so there is no packaged development run left (#395)")


## A `Settings` stand-in that only reports a refused write, so the settings row's message can
## be checked apart from a disk the machine will not let go of (#394).
class RefusedStore:
	extends Node

	func get_last_store_failure() -> Dictionary:
		return {"step": "publish staged preferences", "error": ERR_FILE_CANT_WRITE}


## A keyboard event for the two checks above: a raw press of `code`, with the flags left default
## unless the test asks for one.
static func _story_key(code: Key, pressed: bool = true) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	return key


## The switch as the next process sees it, and the two ways back off.
func _check_restart_and_disable(check: Harness.Checker, world: Node, settings: Node) -> void:
	Harness.stage = "fresh settings instance, toggle off, then toggle on again"
	var config := ConfigFile.new()
	check.expect(config.load(SETTINGS_PATH) == OK, "The settings file could not be read back")
	check.expect(config.get_value("authoring", "story_editor", false) == true,
		"The switch was not written to [authoring] story_editor")
	check.expect(config.get_value("display", "locale", "") == "zh-CN", "Saving the switch dropped the language")
	check.expect(config.get_value("audio", "music", -1) == 37, "Saving the switch dropped the volume")
	var restarted := SettingsScript.new()
	root.add_child(restarted)
	check.expect(restarted.is_story_editor_enabled(), "A fresh Settings instance lost the stored switch")
	restarted.queue_free()
	await process_frame

	var menu := world.get_node(^"PauseMenu") as PauseMenu
	menu.open()
	menu.activate(&"settings")
	var panel := menu.get_settings_panel()
	panel.cycle(&"story_editor", 1)
	panel.close()
	await _expect_removed(check, world, "Turning off")
	check.expect(not settings.is_story_editor_enabled() and not SettingsStore.open().get_value("authoring", "story_editor", true),
		"The switch off did not persist")
	check.expect(menu.get_story_entry() == null and not menu.open_story_editor() and menu.is_open() and paused,
		"Disabling the editor broke the pause page or left its entry active")
	menu.close()
	check.expect(not paused, "The player could not resume after turning the editor off")

	check.expect(settings.set_story_editor_enabled(true), "Could not re-enable the editor")
	if check.expect(await Harness.wait_until(func() -> bool: return world.has_node(^"AuthorOverlay"), 5.0),
			"Re-enabling did not attach the editor"):
		await _check_removal_with_blocked_draft(check, world, settings)


func _check_removal_with_blocked_draft(check: Harness.Checker, world: Node, settings: Node) -> void:
	Harness.stage = "uninstalling the editor hands back the world even after a refused journal write"
	var directory := DRAFT_DIR.path_join("removal-test")
	for slot in ["draft-0.json", "draft-1.json"]:
		check.expect(DirAccess.make_dir_recursive_absolute(directory.path_join(slot)) == OK, "Could not block the journal")
	var workspace := Store.new(directory)
	workspace.load_workspace()
	var overlay := world.get_node(^"AuthorOverlay")
	var live_panel := (world.get_node(^"GameUI") as GameUI).dialogue_panel
	var tint := live_panel.modulate
	overlay.store = workspace
	overlay.open_editor()
	var drawer := overlay.get_node(^"AuthorDrawer")
	drawer.body.text = "Temporary text that cannot be saved."
	drawer.button("apply_text").pressed.emit()
	check.expect(paused and workspace.has_save_error(), "The removal fixture did not block writes")
	settings.reset_to_defaults()
	check.expect(not settings.is_story_editor_enabled(), "Restore defaults left the story editor on")
	await _expect_removed(check, world, "Resetting to defaults")
	check.expect(not paused and live_panel.modulate == tint, "Uninstalling the overlay left the world frozen or dialogue hidden")


func _expect_removed(check: Harness.Checker, world: Node, label: String) -> void:
	check.expect(await Harness.wait_until(func() -> bool:
		return not root.has_node(^"StoryEditor") and not world.has_node(^"AuthorOverlay")
	, 5.0), label + " left the editor or the world's overlay installed")
