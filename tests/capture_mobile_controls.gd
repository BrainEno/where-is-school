extends SceneTree
## A rendered game, not a mock-up: enter a seeded classroom checkpoint via the real
## title, steer the player and touch the two real Return buttons. Uses desktop preview
## metrics and raw screen events, not iOS hardware. Run in an isolated user profile.

const Harness := preload("res://tests/test_harness.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const OUT := "res://build/mobile-controls/frames"
const SCREEN := Vector2i(2532, 1170)
const SAFE := Rect2(141, 0, 2250, 1107)

var _checks := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "capture_mobile_controls.gd")
	call_deferred("_run")


func _run() -> void:
	await _capture()
	Harness.finish(self, _checks.failures, "Three gameplay/confirmation/title PNGs rendered from the same mobile-preview run")


func _capture() -> void:
	if not _checks.expect(MobileLayout.preview and DisplayServer.get_name() != "headless",
			"Use a real window and -- --mobile-preview"):
		return
	root.set_meta(MobileLayout.TEST_SAFE_AREA, SAFE)
	root.set_meta(MobileLayout.TEST_DENSITY, 3.0)
	root.size = SCREEN
	Input.emulate_mouse_from_touch = true
	var states := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	loc.set_locale("zh-CN")
	var save: Node = states["save"]
	var flags := {
		StoryFlags.MET_Q: true, StoryFlags.TEXTBOOK_MISSING: true, StoryFlags.EXPECTATION_PLAYED: true,
		StoryFlags.BELL_RUNG: true, StoryFlags.CLASS_DISMISSED: true,
		StoryFlags.OBJECTIVE_KEY: "objective.leave_classroom",
	}
	var written: Dictionary = save.write_payload({"flags": SaveCodec.encode_flags(flags), "entries": [],
		"check_seed": 7, "world": {"location_id": "classroom", "spawn": "PlayerStart"}})
	if not _checks.expect(written.get("ok", false), "The classroom checkpoint could not be written"):
		return
	if not _checks.expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK, "Could not create the evidence directory"):
		return
	print("MOBILE_CAPTURE engine=%s renderer=%s adapter=%s window=%s safe=%s density=3 (desktop simulation)"
		% [Engine.get_version_info()["string"], RenderingServer.get_current_rendering_method(),
			RenderingServer.get_video_adapter_name(), root.size, SAFE])

	Harness.stage = "capture: title Continue and world"
	var session := Harness.ensure_autoload(self, "Session", "res://scripts/ui/game_session.gd")
	change_scene_to_file(TITLE_SCENE)
	if not _checks.expect(await Harness.wait_until(func() -> bool: return current_scene is TitleScreen, 12.0),
			"Could not enter the title"):
		return
	await process_frame
	var title := current_scene as TitleScreen
	await _tap(title.get_entry(&"continue"))
	if not _checks.expect(await Harness.wait_until(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_SCENE, 12.0),
		"Continue did not load a world"):
		return
	var world := current_scene
	var pause := world.get_node(^"PauseMenu") as PauseMenu
	var ui := world.get_node(^"GameUI") as GameUI
	var stick := ui.get_node(^"TouchActions/Joystick") as Control
	var shortcut := ui.get_node(^"TouchActions/ReturnToTitle") as Button
	if not _checks.expect(await Harness.wait_until(func() -> bool:
		return stick.is_visible_in_tree() and shortcut.is_visible_in_tree() and session.is_at_rest(world), 15.0),
		"Classroom never became playable with the touch HUD"):
		return
	var point := stick.get_global_rect().get_center() + Vector2.UP * stick.size.x * 0.24
	_touch(point, true)
	await _shot("01_gameplay_joystick_and_return")
	_touch(point, false)
	Harness.stage = "capture: return confirmation and title"
	await _tap(shortcut)
	var prompt := pause.get_confirm()
	if not _checks.expect(paused and prompt.visible and prompt.get_message() == L10n.t("menu.confirm_return_save"),
			"Opening the shortcut did not show the save-and-return question"):
		return
	await _shot("02_return_confirmation")
	var old: WeakRef = weakref(world)
	await _tap(prompt.get_confirm_button())
	if not _checks.expect(await Harness.wait_until(func() -> bool:
		return current_scene is TitleScreen and old.get_ref() == null, 12.0), "Return did not enter the real title and free the old world"):
		return
	title = current_scene as TitleScreen
	if _checks.expect(not paused and title.get_entry_ids().has(&"continue"), "The returned title cannot continue the save"):
		await _shot("03_main_menu_after_return")


func _shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	if not _checks.expect(image != null and not image.is_empty() and image.get_size() == SCREEN,
			"No full-size rendered pixels for %s" % label):
		return
	var colors := {}
	for y in range(20, image.get_height(), 73):
		for x in range(20, image.get_width(), 71):
			colors[image.get_pixel(x, y)] = true
	if _checks.expect(colors.size() >= 12 and image.save_png(OUT.path_join(label + ".png")) == OK,
			"A blank or unsavable frame: %s" % label):
		print("MOBILE_FRAME %s.png %dx%d" % [label, image.get_width(), image.get_height()])


func _tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	_touch(point, true)
	await process_frame
	_touch(point, false)
	await process_frame
	await process_frame


func _touch(point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * point
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
