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
## The editor's own behaviour (edit, insert, trial walk, export) is
## `tests/authoring_classroom_test.gd`; this file is the switch and the entry.

const Harness := preload("res://tests/test_harness.gd")
const MainScene := preload("res://scenes/main/main.tscn")
const SettingsScript := preload("res://scripts/autoload/settings_manager.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

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
	_check_blocked_write(check, panel, settings)
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


func _check_blocked_write(check: Harness.Checker, panel: SettingsPanel, settings: Node) -> void:
	var prior := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	var backup := SettingsStore.BACKUP_PATH
	if not check.expect(DirAccess.make_dir_absolute(backup) == OK, "Could not create the blocked-write fixture"):
		return
	panel.cycle(&"story_editor", 1)
	var row := panel.get_row_control(&"story_editor") as Button
	check.expect(not settings.is_story_editor_enabled() and row.text.contains(L10n.t("settings.off")),
		"An unsaved switch was applied")
	check.expect(panel.get_status_text() == L10n.t("settings.save_failed"), "Write failure was not shown in Settings")
	check.expect(FileAccess.get_file_as_bytes(SETTINGS_PATH) == prior, "A refused swap changed the previous preferences")
	DirAccess.remove_absolute(backup)


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
	check.expect(FileAccess.get_file_as_bytes(SETTINGS_PATH) == prior and not FileAccess.file_exists(SettingsStore.BACKUP_PATH),
		"Failure did not restore the previous settings byte for byte")
	var refuse_primary := func(from: String, to: String) -> Error:
		return ERR_FILE_CANT_WRITE if to == SETTINGS_PATH else DirAccess.rename_absolute(from, to)
	check.expect(SettingsStore._publish(stage, refuse_primary) == ERR_FILE_CANT_WRITE,
		"An interrupted swap reported success")
	check.expect(not FileAccess.file_exists(SETTINGS_PATH) and FileAccess.get_file_as_bytes(SettingsStore.BACKUP_PATH) == prior,
		"An interrupted swap lost the previous settings")
	settings.load_settings()
	check.expect(settings.get_volume(&"music") == 37 and not settings.is_story_editor_enabled()
			and loc._load_saved_locale() == "zh-CN", "Settings and Loc did not both read the backup")
	check.expect(SettingsStore.write(SettingsStore.open()) == OK and FileAccess.file_exists(SETTINGS_PATH)
			and not FileAccess.file_exists(SettingsStore.BACKUP_PATH), "Next write did not recover from an interrupted swap")
	DirAccess.remove_absolute(stage)


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
	check.expect(await Harness.wait_until(func() -> bool: return world.has_node(^"AuthorOverlay"), 5.0),
		"Re-enabling did not attach the editor")
	settings.reset_to_defaults()
	check.expect(not settings.is_story_editor_enabled(), "Restore defaults left the story editor on")
	await _expect_removed(check, world, "Resetting to defaults")


func _expect_removed(check: Harness.Checker, world: Node, label: String) -> void:
	check.expect(await Harness.wait_until(func() -> bool:
		return not root.has_node(^"StoryEditor") and not world.has_node(^"AuthorOverlay")
	, 5.0), label + " left the editor or the world's overlay installed")
