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
const SETTINGS_PATH := "user://settings.cfg"


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "story_editor_setting_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	loc.set_locale("zh-CN")
	# Never inherit a stored switch (or a draft) from an earlier run of this machine.
	var backup := _take_backup()
	var settings := Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	var check := Harness.Checker.new()
	settings.reset_to_defaults()
	_remove_drafts()
	check.expect(not bool(settings.call("is_story_editor_enabled")),
		"A fresh settings file must start with the story editor off")
	var world := await _boot_world(check)
	if world != null:
		await _check_off_by_default(check, world, settings)
		await _check_entry_follows_switch(check, world, settings)
		await _check_restart(check, settings)
		await _check_draft_folder(check)
	paused = false
	if world != null and is_instance_valid(world):
		world.queue_free()
		await process_frame
	settings.reset_to_defaults()
	_restore_backup(backup)
	Harness.finish(self, check.failures,
		"story editor switch: off by default, entry and autoload follow it, drafts stay out of the save")


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


func _check_off_by_default(check: Harness.Checker, world: Node, settings: Node) -> void:
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
	panel.cycle(&"story_editor", 1)
	# A setting change rebuilds the list, so the button from before the press is gone.
	await process_frame
	await process_frame
	check.expect(bool(settings.call("is_story_editor_enabled")), "The row did not turn the switch on")
	row = panel.get_row_control(&"story_editor") as Button
	check.expect(row != null and row.text.contains(L10n.t("settings.on")), "The row does not show the switch on")
	panel.close()
	await process_frame
	# The settings screen closing is what installs it; the menu itself stays open.
	check.expect(root.get_node_or_null(^"StoryEditor") != null,
		"Closing Settings after switching on did not install the editor")
	var entry := menu.get_entry(&"story_editor")
	check.expect(entry != null and entry.is_visible_in_tree(), "The pause menu has no editor entry after switching on")
	menu.close()
	await process_frame
	if not check.expect(await Harness.wait_until(func() -> bool:
		return world.get_node_or_null(^"AuthorOverlay/EditStory") != null
	, 5), "The editor overlay did not attach to the classroom"):
		return
	var launcher := world.get_node(^"AuthorOverlay/EditStory") as Button
	check.expect(launcher.is_visible_in_tree(), "The editor launcher is hidden inside a running world")
	menu.open()
	await process_frame
	# The click runs the entry, which opens the drawer and then closes the menu under it.
	menu.activate(&"story_editor")
	await process_frame
	var overlay_now := world.get_node_or_null(^"AuthorOverlay")
	check.expect(overlay_now != null and bool(overlay_now.call("is_editing")),
		"The pause entry did not open the editor over the paused world")
	check.expect(paused, "Opening the editor from the pause menu left the world running")
	check.expect(not menu.is_open(), "The pause menu stayed over the opened editor")
	await process_frame
	if paused:
		var overlay := world.get_node_or_null(^"AuthorOverlay")
		if overlay != null and overlay.has_method("is_editing") and bool(overlay.call("is_editing")):
			overlay.call("close_editor")
		await process_frame


func _check_restart(check: Harness.Checker, settings: Node) -> void:
	Harness.stage = "the switch survives a restart without touching other preferences"
	check.expect(settings.call("is_story_editor_enabled"), "The switch was not on before the reload")
	var config := ConfigFile.new()
	check.expect(config.load(SETTINGS_PATH) == OK, "The settings file could not be read back")
	check.expect(config.get_value("authoring", "story_editor", false) == true,
		"The switch was not written to [authoring] story_editor")
	settings.call("load_settings")
	check.expect(settings.call("is_story_editor_enabled"), "A reload lost the switch")
	settings.call("reset_to_defaults")
	check.expect(not settings.call("is_story_editor_enabled"),
		"Restore defaults left the story editor on")
	# No world is left here, so the installed node is checked by `_check_entry_follows_switch`'s
	# signal path: the setting emits and the pause menu removes what it installed.


func _check_draft_folder(check: Harness.Checker) -> void:
	Harness.stage = "drafts and the bridge exchange are apart from the save"
	var inbox := "user://story_editor/share/request.json"
	check.expect(inbox.begins_with(DRAFT_DIR), "The bridge inbox is outside the draft folder")
	check.expect(not inbox.begins_with("user://save"), "The bridge inbox sits next to the save file")


## Runs from the player's settings: this test restores it whatever happens.
func _take_backup() -> Dictionary:
	var files: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		files[SETTINGS_PATH] = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	return files


func _restore_backup(files: Dictionary) -> void:
	if files.has(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(files[SETTINGS_PATH])
			file.close()
	else:
		DirAccess.remove_absolute(SETTINGS_PATH)


func _remove_drafts() -> void:
	if DirAccess.dir_exists_absolute(DRAFT_DIR):
		for name: String in DirAccess.get_files_at(DRAFT_DIR):
			DirAccess.remove_absolute(DRAFT_DIR.path_join(name))
