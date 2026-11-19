extends SceneTree
## Native touch equivalents through the real input pipeline, not a call to pressed.emit().
## Input generates its mouse emulation as on a phone. Test metadata stands in only for
## native display metrics, which are not available in this desktop/headless process.

const Harness := preload("res://tests/test_harness.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const SCREENS := [
	[Vector2i(1334, 750), Rect2(0, 0, 1334, 750), 2.0],
	[Vector2i(2400, 1080), Rect2(132, 0, 2244, 1008), 3.0],
	[Vector2i(2048, 1536), Rect2(0, 42, 2048, 1452), 2.0],
]

var _check := Harness.Checker.new()
var _settings: Node
var _main: Node
var _nav: PointerNavigator
var _ui: GameUI
var _pause: PauseMenu
var _player: PlayerController


func _initialize() -> void:
	Harness.arm_watchdog(self, 75.0, "mobile_controls_test.gd")
	call_deferred("_run")


func _run() -> void:
	if not _check.expect(MobileLayout.enabled, "Run with -- --mobile-preview"):
		Harness.finish(self, _check.failures, "")
		return
	# Base DisplayServer uses emulate_touch_from_mouse to report a touch surface. This
	# only enables its ScrollContainer's touch behavior; the test injects raw touches.
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	_settings = Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	_settings.call("reset_to_defaults")
	L10n.load_tables()
	await _title_and_settings()
	await _load_world()
	await _world_taps()
	await _pause_navigation()
	await _reading()
	_main.queue_free()
	await process_frame
	Harness.finish(self, _check.failures,
		"mobile safe controls at three aspect ratios, single-finger world taps, "
		+ "settings scroll, modal back/resume, dialogue reveal and choice paging")


func _set_screen(metrics: Array) -> void:
	var pixels: Rect2 = metrics[1]
	root.set_meta(MobileLayout.TEST_SAFE_AREA, pixels)
	root.set_meta(MobileLayout.TEST_DENSITY, metrics[2])
	root.min_size = Vector2i.ZERO
	root.size = metrics[0]
	var measured := root.get_final_transform() * MobileLayout.safe_rect(root)
	_check.expect(measured.position.distance_to(pixels.position) < 1.1
		and measured.end.distance_to(pixels.end) < 1.1, "Safe-area transform shifted the OS inset: %s" % measured)
	await process_frame
	await process_frame


func _title_and_settings() -> void:
	Harness.stage = "title and settings"
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	for metrics: Array in SCREENS:
		await _set_screen(metrics)
		_check.expect(not title.get_entry_ids().has(&"quit"), "Phone title exposes desktop Quit")
		for id: StringName in title.get_entry_ids():
			_check_target(title.get_entry(id), String(id))
	await _set_screen(SCREENS[1])
	await _tap_control(title.get_entry(&"settings"))
	var settings := title.get_settings_panel()
	if _check.expect(settings.is_open(), "Tap did not open Settings"):
		_check_target(settings.get_row_control(&"back"), "Settings Back")
		_check.expect(settings.get_row_control(&"fullscreen") == null, "Phone Settings exposes desktop fullscreen")
		var scroll := settings.get_scroll()
		var speed := settings.get_row_control(&"text_speed") as Button
		var text := speed.text
		var start := speed.get_global_rect().get_center()
		# Start over an actual control: a swipe may scroll, but may not select a row.
		var origin := scroll.scroll_vertical
		_check.expect(scroll.get_global_rect().has_point(start), "Settings swipe starts outside scroll clip")
		await _swipe(start, start - Vector2(0, 110))
		_check.expect(scroll.scroll_vertical > origin, "Swiping a settings row did not scroll: start=%s clip=%s position=%s->%s flags=%s touch=%s" % [
			start, scroll.get_global_rect(), origin, scroll.scroll_vertical, speed.mouse_filter, DisplayServer.is_touchscreen_available()])
		_check.expect(speed.text == text, "Scrolling Settings changed reading speed")
		await _tap_control(settings.get_row_control(&"back"))
		_check.expect(not settings.is_open(), "Settings Back did not close the modal")
	title.queue_free()
	await process_frame


func _load_world() -> void:
	Harness.stage = "load world"
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	var opening := _main.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(_main)
	opening.allow_player_control()
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_player = _main.get_node(^"Player") as PlayerController
	_nav = _player.get_node(^"PointerNavigator") as PointerNavigator
	_ui = _main.get_node(^"GameUI") as GameUI
	_ui.fade.set_clear() # The real wake clears the fade; this test starts after the beat.
	_pause = _main.get_node(^"PauseMenu") as PauseMenu
	await physics_frame
	await physics_frame


func _world_taps() -> void:
	Harness.stage = "world tap, swipe, second finger and cancel"
	var safe := MobileLayout.safe_rect(_ui.hud)
	var point := safe.get_center()
	var before := _nav.get_world_click_event_count()
	_touch(point, true)
	_check.expect(_nav.get_world_click_event_count() == before, "Touch-down walked the player")
	_touch(point, false)
	_check.expect(_nav.get_world_click_event_count() == before + 1, "A single tap did not pick exactly once")
	_check.expect(_settings.call("get_input_device") == &"touch", "Mouse emulation displaced touch prompts")
	_player.cancel_path()
	before = _nav.get_world_click_event_count()
	await _swipe(point, point + Vector2(100, 0))
	_touch(point, true)
	_touch(point + Vector2(25, 0), true, 1)
	_touch(point + Vector2(25, 0), false, 1)
	_touch(point, false)
	_touch(point, true)
	_touch(point, false, 0, true)
	_touch(point, true)
	_nav.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_touch(point, false)
	_touch(safe.position - Vector2(10, -80), true)
	_touch(safe.position - Vector2(10, -80), false)
	_check.expect(_nav.get_world_click_event_count() == before, "Drag, second finger, cancel or unsafe tap picked the world")


func _pause_navigation() -> void:
	Harness.stage = "pause, journal and Back"
	var touch_menu := _ui.get_node(^"TouchActions/Pause") as Button
	_check_target(touch_menu, "Touch Menu")
	var before := _nav.get_world_click_event_count()
	await _tap_control(touch_menu)
	if not _check.expect(_pause.is_open() and paused, "Touch Menu did not pause the scene tree"):
		return
	await _tap_control(_pause.get_entry(&"journal"))
	var journal := _pause.get_journal_panel()
	_check.expect(journal.is_open(), "A tap did not open the notebook")
	root.go_back_requested.emit()
	_check.expect(not journal.is_open() and _pause.is_open(), "Android Back closed more than the notebook")
	await _tap_control(_pause.get_entry(&"resume"))
	_check.expect(not _pause.is_open() and not paused, "Touch Resume left the tree paused")
	_check.expect(_nav.get_world_click_event_count() == before, "A modal tap leaked into the world")


func _reading() -> void:
	Harness.stage = "dialogue scrolling, continue, log and choices"
	var panel := _ui.dialogue_panel
	panel.set_reveal_speed(0.1)
	panel.show_line({"speaker_name": "Test", "text": "A readable line for checking touch. ".repeat(90)})
	_check.expect(await Harness.wait_until(func() -> bool: return not bool(panel.get("_layout_dirty")), 3.0),
		"Reading band did not settle")
	var continued := [0]
	panel.advance_requested.connect(func() -> void: continued[0] += 1)
	var footer := panel.find_child("TouchReading", true, false)
	var next_line := footer.get_node(^"Continue") as Button
	_check_target(next_line, "Dialogue Continue")
	var before := _nav.get_world_click_event_count()
	await _tap_control(next_line)
	_check.expect(not panel.is_revealing() and continued[0] == 0, "First Continue did not only finish the reveal")
	await _tap_control(next_line)
	_check.expect(continued[0] == 1, "One tap did not continue exactly once")
	var body := panel.get_node(^"Frame/Content/BodyLabel") as RichTextLabel
	var start := body.get_global_rect().get_center()
	var bar := body.get_v_scroll_bar()
	var origin := bar.value
	_touch(start, true)
	var capture := int(panel.get("_body_touch"))
	_drag(start, start - Vector2(0, 64))
	var changed := bar.value
	_touch(start - Vector2(0, 64), false)
	await process_frame
	_check.expect(bar.value > origin and continued[0] == 1,
		"Dragging long dialogue did not just scroll: active=%s finger=%s position=%s->%s->%s range=%s advance=%s" % [
			body.scroll_active, capture, origin, changed, bar.value, bar.max_value - bar.page, continued[0]])
	await _tap_control(footer.get_node(^"Log") as Button)
	_check.expect(_ui.backlog.is_open(), "Reading tray did not open Log")
	await _tap_control(_ui.backlog.find_child("TouchClose", true, false) as Button)
	_check.expect(not _ui.backlog.is_open(), "Touch Close did not close Log")
	await _option_page(panel, footer)
	_check.expect(_nav.get_world_click_event_count() == before, "Reading or choosing leaked into the world")
	panel.close()


func _option_page(panel: DialoguePanel, footer: Node) -> void:
	var choices: Array[Dictionary] = []
	for i in range(10):
		choices.append({"text": "Option %d" % (i + 1)})
	panel.set_choices(choices)
	var next_page := footer.get_node(^"Next") as Button
	var selected: Array[int] = []
	panel.choice_selected.connect(func(index: int) -> void: selected.append(index))
	if not _check.expect(await Harness.wait_until(func() -> bool: return not next_page.disabled, 3.0),
		"Overflowing choice list has no accessible next button"):
		return
	_check_target(next_page, "Next choice page")
	await _tap_control(next_page)
	if not _check.expect(await Harness.wait_until(func() -> bool: return panel.get_choice_window().x > 0, 3.0),
		"Tapping Next did not reveal the hidden choices"):
		return
	var expected := panel.get_choice_window().x
	var choice := panel.get_choice_buttons()[expected]
	_check_target(choice, "Paged choice")
	await _tap_control(choice)
	_check.expect(selected == [expected], "Choice was missed or selected more than once: %s" % [selected])


func _check_target(control: Control, label: String) -> void:
	if not _check.expect(control != null and control.is_visible_in_tree(), label + " is not visible"):
		return
	var transform := root.get_final_transform() * control.get_global_transform_with_canvas()
	var physical := transform * Rect2(Vector2.ZERO, control.size)
	var safe := MobileLayout.safe_pixels(root).grow(1.0)
	var side := MobileLayout.TARGET_POINTS * MobileLayout.density(root) - 1.0
	_check.expect(safe.encloses(physical), "%s outside %s: %s" % [label, safe, physical])
	_check.expect(physical.size.x >= side and physical.size.y >= side, "%s is too small: %s" % [label, physical.size])


func _tap_control(control: Control) -> void:
	if control == null:
		return
	var center := control.get_global_transform_with_canvas() * (control.size * 0.5)
	_touch(center, true)
	await process_frame
	_touch(center, false)
	await process_frame
	await process_frame


func _swipe(from: Vector2, to: Vector2) -> void:
	_touch(from, true)
	_drag(from, to)
	await process_frame
	_touch(to, false)
	await process_frame


func _drag(from: Vector2, to: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = root.get_final_transform() * to
	drag.relative = root.get_final_transform().basis_xform(to - from)
	drag.screen_relative = drag.relative
	_send(drag)


func _touch(point: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * point
	event.index = index
	event.pressed = down
	event.canceled = canceled
	_send(event)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
