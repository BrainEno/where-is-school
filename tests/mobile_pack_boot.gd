extends SceneTree
## Start a fresh run through the title, let the authored opening play, then operate the
## real touch HUD. Also runs against the exported iOS PCK with --main-pack, before that
## same pack is placed in an IPA. Neither invocation runs on device hardware.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const MAIN := "res://scenes/main/main.tscn"
const TITLE := "res://scenes/ui/title_screen.tscn"
const SAVE := "user://save.json"
const SCREEN := Vector2i(2400, 1080)


func _initialize() -> void:
	create_timer(65.0, true, false, true).timeout.connect(_fail.bind("mobile opening smoke timed out"))
	call_deferred("_run")


func _run() -> void:
	if not MobileLayout.enabled or not (MobileLayout.preview or OS.has_feature("wis_handheld")):
		_fail("the exported pack did not enable the handheld layout itself")
		return
	# Headless DisplayServer has no real window size and ignores --resolution.
	# Size the SceneTree viewport in both runs; only the editor-preview run
	# overrides OS metrics. The real pack must still enable the layout itself.
	root.min_size = Vector2i.ZERO
	root.size = SCREEN
	if MobileLayout.preview:
		root.set_meta(MobileLayout.TEST_SAFE_AREA, Rect2(132, 0, 2244, 1008))
		root.set_meta(MobileLayout.TEST_DENSITY, 3.0)
	# Refuse to overwrite a player's existing save when run outside of CI.
	if FileAccess.file_exists(SAVE):
		_fail("the mobile opening smoke requires an isolated, empty user directory")
		return
	# A --script launch can omit the project's ordinary autoloads. Use the authentic
	# runtime scripts, in order, if the engine has not already installed them.
	var autoloads := {
		"GameState": "res://scripts/autoload/game_state.gd",
		"NarrativeState": "res://scripts/autoload/narrative_state.gd",
		"Save": "res://scripts/autoload/save_manager.gd",
		"Loc": "res://scripts/i18n/loc.gd",
		"Settings": "res://scripts/autoload/settings_manager.gd",
		"Session": "res://scripts/ui/game_session.gd",
	}
	for node_name: String in autoloads:
		if root.has_node(NodePath(node_name)):
			continue
		var script := load(autoloads[node_name]) as Script
		var singleton: Node = script.new()
		singleton.name = node_name
		root.add_child(singleton)
	Input.emulate_mouse_from_touch = true
	if change_scene_to_file(TITLE) != OK:
		_fail("could not boot the title")
		return
	await scene_changed
	await process_frame
	var title := current_scene as TitleScreen
	if title == null or title.get_entry_ids().has(&"quit") or title.get_entry_ids().has(&"continue"):
		_fail("did not boot the fresh mobile title")
		return
	await _tap(title.get_entry(&"new_game"))
	if not await _wait_until(func() -> bool: return current_scene != null and current_scene.scene_file_path == MAIN, 10.0):
		_fail("tapping Start did not load the world")
		return
	var world := current_scene
	var ui := world.get_node(^"GameUI") as GameUI
	var player := world.get_node(^"Player") as PlayerController
	var dialogue := world.get_node(^"DialogueController") as DialogueController
	var touch_menu := ui.get_node_or_null(^"TouchActions/Pause") as Button
	var use := ui.get_node_or_null(^"TouchActions/Use") as Button
	var stick := ui.get_node_or_null(^"TouchActions/Joystick") as Control
	var back := ui.get_node_or_null(^"TouchActions/ReturnToTitle") as Button
	if touch_menu == null or use == null or stick == null or back == null:
		_fail("the world did not construct its gameplay controls")
		return
	if not await _wait_until(func() -> bool: return ui.dialogue_panel.visible, 22.0):
		_fail("the real wake and Q approach did not reach the opening dialogue")
		return
	if stick.is_visible_in_tree() or use.is_visible_in_tree():
		_fail("exploration controls covered the opening dialogue")
		return
	if not await _finish_opening(dialogue, player):
		_fail("the authored opening did not hand back control")
		return
	var settings := root.get_node(^"Settings")
	settings.set_input_device(InputHint.DEVICE_MOUSE)
	await process_frame
	var safe := MobileLayout.safe_rect(stick)
	for control: Control in [touch_menu, use, stick, back]:
		if not control.is_visible_in_tree() or not safe.encloses(control.get_global_rect()):
			_fail("%s did not fit the HUD after the opening: window=%s, bounds=%s, safe=%s" % [
				control.name, root.size, control.get_global_rect(), safe])
			return
	var thumb := stick.get_global_rect().get_center() + Vector2.RIGHT * stick.size.x * 0.32
	if not player.is_seated():
		_fail("the opening did not leave the protagonist seated before the first gesture")
		return
	_touch(thumb, true)
	var stood := await _wait_until(func() -> bool: return not player.is_seated(), 3.0)
	_touch(thumb, false)
	if not stood:
		_fail("the seated player did not respond to the joystick at %s (window=%s, stick=%s)" % [
			thumb, root.size, stick.get_global_rect()])
		return
	if not await _wait_until(func() -> bool: return not player.is_getting_up(), 4.0):
		_fail("the touch-initiated get-up never finished")
		return
	var pause_menu := world.get_node(^"PauseMenu") as PauseMenu
	await _tap(touch_menu)
	if not pause_menu.is_open() or not paused:
		_fail("the menu button did not pause gameplay")
		return
	if not await _check_editor_in_pack(pause_menu, world, settings):
		return
	await _tap(pause_menu.get_entry(&"resume"))
	if pause_menu.is_open() or paused:
		_fail("the pause menu did not return to gameplay")
		return

	# Between opening beats we can move, but only the last checkpoint is safe to keep.
	var checkpoint := FileAccess.get_file_as_bytes(SAVE)
	await _tap(back)
	var prompt := pause_menu.get_confirm()
	if not prompt.visible or not paused or prompt.get_message() == L10n.t("menu.confirm_return_save"):
		_fail("Return did not ask to keep the last checkpoint during the prologue")
		return
	await _tap(prompt.get_cancel_button())
	if paused or current_scene != world or checkpoint.is_empty() \
			or FileAccess.get_file_as_bytes(SAVE) != checkpoint:
		_fail("cancelling Return did not preserve the same world and checkpoint")
		return
	await _tap(back)
	if not prompt.visible:
		_fail("Return did not offer the checkpoint again")
		return
	await _tap(prompt.get_confirm_button())
	if not await _wait_until(func() -> bool: return current_scene is TitleScreen, 10.0):
		_fail("confirming Return did not boot the title")
		return
	if paused or not (current_scene as TitleScreen).get_entry_ids().has(&"continue") \
			or FileAccess.get_file_as_bytes(SAVE) != checkpoint:
		_fail("Return did not leave the opening checkpoint intact")
		return
	print("PASS: MOBILE_OPENING_TOUCH_OK os=%s engine=%s handheld=%s preview=%s" % [
		OS.get_name(), Engine.get_version_info()["string"], OS.has_feature("wis_handheld"), MobileLayout.preview])
	quit()


## A source tree can load files an export accidentally excluded. Exercise the same touch
## path against the retail device pack, all the way to the editor's actual drawer.
func _check_editor_in_pack(menu: PauseMenu, world: Node, settings: Node) -> bool:
	if settings.is_story_editor_enabled() or menu.get_story_editor() != null:
		_fail("a fresh run enabled the story editor automatically")
		return false
	await _tap(menu.get_entry(&"settings"))
	var panel := menu.get_settings_panel()
	var toggle := panel.get_row_control(&"story_editor") as Button
	if not panel.is_open() or toggle == null:
		_fail("the retail pack did not expose the story editor opt-in in Settings")
		return false
	panel.get_scroll().ensure_control_visible(toggle)
	await process_frame
	var legacy_stage := SettingsStore.PATH + ".tmp"
	if DirAccess.make_dir_absolute(legacy_stage) != OK:
		_fail("could not arrange the legacy settings staging obstruction")
		return false
	await _tap(toggle)
	DirAccess.remove_absolute(legacy_stage)
	var persisted := ConfigFile.new()
	if not settings.is_story_editor_enabled() or persisted.load(SettingsStore.PATH) != OK \
			or persisted.get_value("authoring", "story_editor", false) != true:
		_fail("the mobile settings tap did not save the editor switch")
		return false
	await _tap(panel.get_row_control(&"done"))
	var entry := menu.get_story_entry()
	if panel.is_open() or entry == null or not await _wait_until(func() -> bool:
		return world.has_node(^"AuthorOverlay"), 5.0):
		_fail("the pack did not attach the editor and expose its pause entry")
		return false
	var scroll := entry.get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(entry)
	await process_frame
	await _tap(entry)
	var overlay := world.get_node(^"AuthorOverlay")
	if menu.is_open() or not paused or not bool(overlay.call("is_editing")):
		_fail("a touch on the pause entry did not open the editor")
		return false
	overlay.call("close_editor")
	if paused or bool(overlay.call("is_editing")):
		_fail("closing the editor did not resume gameplay")
		return false
	menu.open()
	return true


func _finish_opening(dialogue: DialogueController, player: PlayerController) -> bool:
	var state := root.get_node(^"GameState")
	var deadline := Time.get_ticks_msec() + 16000
	while Time.get_ticks_msec() < deadline:
		if state.get_flag(StoryFlags.Q_FIRST_TALK_DONE, false) and player.is_control_enabled():
			return true
		if dialogue.is_busy():
			# The adjacent mobile suite tests the raw touches on lines and choices.
			# Here the presentation APIs only read through the authored conversation;
			# they do not change flags, remove the fade, or unlock the player.
			if not dialogue.has_pending_choices():
				dialogue.advance_presentation()
			else:
				var index := 0
				for choice: Dictionary in dialogue.get_runtime().get_current_choices():
					if choice.get("choice_id") == &"ignore_b":
						index = int(choice["index"])
				dialogue.select_choice(index)
		await process_frame
	return false


func _wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func _tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	_touch(point, true)
	await process_frame
	_touch(point, false)
	await process_frame
	await process_frame


func _touch(point: Vector2, down: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = root.get_final_transform() * point
	touch.pressed = down
	Input.parse_input_event(touch)
	Input.flush_buffered_events()


func _fail(reason: String) -> void:
	print("FAIL: mobile opening touch: " + reason)
	quit(1)
