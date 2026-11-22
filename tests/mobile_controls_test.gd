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
	[Vector2i(2400, 1080), Rect2(24, 0, 2244, 1008), 3.0], # same phone, opposite grip
]

const PORTRAIT := [Vector2i(1170, 2532), Rect2(0, 141, 1170, 2289), 3.0]
const MAIN_SCENE := "res://scenes/main/main.tscn"
const SAVE_PATH := "user://save.json"

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
	await _hud_available_with_pointer()
	await _world_taps()
	await _joystick_motion()
	await _joystick_cancellation()
	await _menu_geometry()
	await _pause_navigation()
	await _reading()
	await _large_reading()
	await _compare_touch()
	await _return_during_dialogue()
	Harness.finish(self, _check.failures,
		"touch movement, eight directions and analog drag, release/cancel and hybrid input; "
		+ "persistent controls, compact menus on phone and tablet, independent taps and modal scrolling; "
		+ "dialogue cancellation, checkpoint return, Continue in another location and a clean new game")


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
		# A phone has no hint line naming the confirm input, so the screen itself must offer a
	# visible way out of a row it has already changed. "完成" is that key: it is a real
	# finger target, it says the change is stored, and it closes.
		var done := settings.get_row_control(&"done") as Button
		if _check.expect(done != null and done.is_visible_in_tree(), "Phone Settings has no Done key"):
			_check_target(done, "Settings Done")
			await _tap_control(done)
			_check.expect(not settings.is_open(), "Settings Done did not close the modal")
		await _tap_control(title.get_entry(&"settings"))
		var reopened := title.get_settings_panel()
		if _check.expect(reopened.is_open(), "Settings did not reopen after Done"):
			var speed_row := reopened.get_row_control(&"text_speed") as Button
			var before := speed_row.text
			_check.expect(reopened.get_scroll().get_global_rect().has_point(speed_row.get_global_rect().get_center()),
				"Reopening Settings kept the previous scroll position over the first rows")
			await _tap_control(speed_row)
			_check.expect(speed_row.text != before, "Tapping a choice row on a phone changed nothing")
			await _tap_control(reopened.get_row_control(&"back"))
			_check.expect(not reopened.is_open(), "Settings Back did not close the modal")
	title.queue_free()
	await process_frame


func _load_world() -> void:
	Harness.stage = "load world"
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var opening := _main.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(_main)
	current_scene = _main
	opening.allow_player_control()
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_player = _main.get_node(^"Player") as PlayerController
	_nav = _player.get_node(^"PointerNavigator") as PointerNavigator
	_ui = _main.get_node(^"GameUI") as GameUI
	_ui.fade.set_clear() # The real wake clears the fade; this test starts after the beat.
	_pause = _main.get_node(^"PauseMenu") as PauseMenu
	await physics_frame
	await physics_frame


func _hud_available_with_pointer() -> void:
	Harness.stage = "handheld HUD does not depend on the latest input device"
	var menu := _ui.get_node(^"TouchActions/Pause") as Button
	var use := _ui.get_node(^"TouchActions/Use") as Button
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	interaction.set_enabled(false)
	var pointer := InputEventMouseMotion.new()
	pointer.position = root.get_final_transform() * MobileLayout.safe_rect(_ui.hud).get_center()
	pointer.relative = Vector2.RIGHT * 4.0
	_send(pointer)
	await process_frame
	_check.expect(_settings.call("get_input_device") == &"mouse", "Fixture did not switch to pointer hints")
	_check_target(_stick(), "Joystick with pointer hints")
	_check_target(menu, "Menu with pointer hints")
	_check_target(_return_button(), "Return with pointer hints")
	_check_target(use, "Inactive Use with no target")
	_check.expect(use.disabled, "Use looks actionable with no target")
	var before := _nav.get_world_click_event_count()
	await _tap_control(use)
	_check.expect(_nav.get_world_click_event_count() == before, "Inactive Use let a tap through to the floor")
	interaction.set_enabled(true)


func _world_taps() -> void:
	Harness.stage = "world tap, swipe, second finger and cancel"
	var safe := MobileLayout.safe_rect(_ui.hud)
	# Use real floor, not the center pixel: an authored hotspot there can begin an
	# inspection and replace the independent long-line fixture later in this test.
	var candidates: Array[Vector2] = [Vector2.INF]
	if not _check.expect(await Harness.wait_until(func() -> bool:
		candidates[0] = _route_screen_point(safe)
		return candidates[0] != Vector2.INF, 4.0), "No visible, reachable, unoccupied floor for the touch path"):
		return
	var point := candidates[0]
	_player.set_wake_pose(1.0)
	var before := _nav.get_world_click_event_count()
	_touch(point, true)
	_check.expect(_nav.get_world_click_event_count() == before, "Touch-down walked the player")
	_touch(point, false)
	_check.expect(_nav.get_world_click_event_count() == before + 1, "A single tap did not pick exactly once")
	_check.expect(_settings.call("get_input_device") == &"touch", "Mouse emulation displaced touch prompts")
	_check.expect(_player.is_path_active(), "The accepted tap did not start a real navigation path")
	_check.expect(await Harness.wait_until(_player.is_getting_up, 3.0), "The first deliberate touch move did not start getting up")
	_player.cancel_path()
	_check.expect(await Harness.wait_until(func() -> bool: return not _player.is_getting_up(), 3.0),
		"Get-up did not finish after the touch move")
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


func _route_screen_point(safe: Rect2) -> Vector2:
	var map := _player.navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector2.INF
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	for y in range(14):
		for x in range(18):
			var screen := safe.position + safe.size * Vector2(0.13 + 0.74 * float(x) / 17.0,
				0.25 + 0.63 * float(y) / 13.0)
			var ground: Variant = _nav.get_ground_point_at(screen)
			if ground == null or _player.global_position.distance_to(ground) < 1.1:
				continue
			if interaction.get_target_at_screen_position(screen, false) != null:
				continue
			if NavigationServer3D.map_get_path(map, _player.global_position, ground, true).size() >= 2:
				return screen
	return Vector2.INF


func _joystick_motion() -> void:
	Harness.stage = "joystick directions, long hold and an independent world tap"
	var stick := _stick()
	if not _check.expect(stick != null and stick.is_visible_in_tree(), "Touch joystick is missing"):
		return
	var center := stick.get_global_rect().get_center()
	var before := _nav.get_world_click_event_count()
	_touch(center, true)
	var last := center
	for sector in range(8):
		var dir := Vector2.from_angle(float(sector) * TAU / 8.0)
		var next := center + dir * stick.size.x
		_drag(last, next)
		await _check_facing(dir, "sector %d" % sector)
		last = next
	var diagonal := Vector2(0.34, -0.94).normalized()
	var next := center + diagonal * stick.size.x * 0.18
	_drag(last, next)
	await _check_facing(diagonal, "non-octant and partially tilted")
	_touch(next, false)
	_check.expect(_horizontal_speed() < 0.001, "Release outside the base left movement")
	_check.expect(_nav.get_world_click_event_count() == before, "Joystick contact leaked a world click")

	# Simultaneous contacts are not a two-finger world gesture. The floor tap is still
	# picked once, but cannot queue automatic motion behind a steering thumb.
	var point := _route_screen_point(MobileLayout.safe_rect(_ui.hud))
	if _check.expect(point != Vector2.INF, "No reachable target for the second finger"):
		_touch(point, true, 5)
		_touch(center + Vector2.RIGHT * stick.size.x * 0.3, true)
		_touch(point, false, 5)
		_check.expect(_nav.get_world_click_event_count() == before + 1 and not _player.is_path_active(),
			"The second finger lost its tap or queued movement behind the joystick")
		_touch(center - Vector2.RIGHT * stick.size.x * 0.3, true, 7)
		_drag(center, center - Vector2.RIGHT * stick.size.x, 7)
		_touch(center, false, 7)
		await _check_facing(Vector2.RIGHT, "second finger did not steal the stick")
		_touch(center, false)



func _joystick_cancellation() -> void:
	Harness.stage = "joystick cancellation, focus loss and physical inputs"
	var stick := _stick()
	if stick == null:
		return
	var center := stick.get_global_rect().get_center()
	var edge := center + Vector2.LEFT * stick.size.x * 0.3
	_touch(edge, true)
	await _check_facing(Vector2.LEFT, "before OS cancellation")
	_touch(edge, false, 0, true)
	_check.expect(_horizontal_speed() < 0.001, "Canceled touch kept steering")
	for notice: int in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		_touch(edge, true)
		await _check_facing(Vector2.LEFT, "before focus/background loss")
		stick.get_parent().notification(notice)
		_drag(edge, center + Vector2.UP * stick.size.x)
		await physics_frame
		await physics_frame
		_check.expect(_horizontal_speed() < 0.001, "A stale drag resumed after losing focus")
		_touch(edge, false)
	# A held thumb must cancel even when the last hint already belonged to this keyboard.
	_settings.set_input_device(InputHint.DEVICE_KEYBOARD)
	_touch(edge, true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	_send(key)
	await _check_facing(Vector2.UP, "keyboard took over on a mobile surface")
	_check.expect(stick.is_visible_in_tree() and Input.is_action_pressed(&"move_forward"),
		"Keyboard should take over movement, not remove the touch HUD")
	key = key.duplicate() as InputEventKey
	key.pressed = false
	_send(key)
	_drag(edge, center + Vector2.UP * stick.size.x)
	_check.expect(await Harness.wait_until(func() -> bool: return _horizontal_speed() < 0.001, 3.0),
		"A held thumb took over again after the keyboard stopped")
	_touch(edge, false)
	key = key.duplicate() as InputEventKey
	key.pressed = true
	_send(key)
	_touch(edge, true)
	_touch(edge, false)
	_check.expect(Input.is_action_pressed(&"move_forward"), "Touch release cleared a real key")
	key = key.duplicate() as InputEventKey
	key.pressed = false
	_send(key)
	_touch(edge, true)
	await _check_facing(Vector2.LEFT, "before gamepad handoff")
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.8
	_send(axis)
	await _check_facing(Vector2.RIGHT, "gamepad axis in the same player controller")
	_check.expect(stick.is_visible_in_tree(), "Gamepad input removed the handheld joystick")
	axis = axis.duplicate() as InputEventJoypadMotion
	axis.axis_value = 0.0
	_send(axis)
	_drag(edge, center + Vector2.UP * stick.size.x)
	_check.expect(await Harness.wait_until(func() -> bool: return _horizontal_speed() < 0.001, 3.0),
		"A stick gesture canceled by gamepad input moved again after the axis was released")
	_touch(center, false)
	var fresh := center + Vector2.DOWN * stick.size.x * 0.32
	_touch(fresh, true)
	await _check_facing(Vector2.DOWN, "a fresh touch after gamepad handoff")
	_touch(fresh, false)


func _menu_geometry() -> void:
	Harness.stage = "rotation while steering, then touch header and confirmation bounds"
	var original_center := _stick().get_global_rect().get_center()
	var original_edge := original_center + Vector2.RIGHT * _stick().size.x * 0.3
	_touch(original_edge, true)
	await _check_facing(Vector2.RIGHT, "before rotation")
	await _set_screen(PORTRAIT)
	_drag(original_edge, original_center)
	_check.expect(_horizontal_speed() < 0.001, "Rotation kept an old steering gesture alive")
	_touch(original_center, false)
	var loc := root.get_node(^"Loc")
	_settings.call("set_text_size", &"largest")
	_ui.hud.set_objective("objective.leave_classroom")
	for metrics: Array in SCREENS + [PORTRAIT]:
		await _set_screen(metrics)
		for locale: String in L10n.LOCALES:
			loc.call("set_locale", locale)
			await process_frame
			var stick := _stick()
			var shortcut := _return_button()
			_check_target(stick, "Joystick")
			_check_target(shortcut, "Return shortcut")
			if stick == null or shortcut == null:
				return
			var physical := root.get_final_transform() * stick.get_global_rect()
			_check.expect(physical.size.x >= MobileLayout.density(root) * 85.0,
				"Joystick is too small for a thumb: %s" % physical)
			var objective := _ui.hud.get_node(^"ObjectiveLabel") as Control
			var pause_button := _ui.get_node(^"TouchActions/Pause") as Button
			_check.expect(not objective.get_global_rect().intersects(shortcut.get_global_rect())
				and not objective.get_global_rect().intersects(pause_button.get_global_rect()),
				"Touch header covered the objective")
			await _tap_control(shortcut)
			var prompt := _pause.get_confirm()
			_check_target(prompt.get_cancel_button(), "Keep playing")
			_check_target(prompt.get_confirm_button(), "Return to main menu")
			_check.expect(MobileLayout.safe_rect(prompt).encloses(prompt.get_panel().get_global_rect()),
				"Confirmation panel escaped the safe area at %s (%s)" % [metrics[0], locale])
			await _tap_control(prompt.get_cancel_button())
			_check.expect(not paused and not _pause.is_open(), "Keep playing did not resume directly")
	await _set_screen(SCREENS[1])
	loc.call("set_locale", "en")
	_settings.call("set_text_size", &"standard")


func _stick() -> Control:
	return _ui.get_node_or_null(^"TouchActions/Joystick") as Control


func _return_button() -> Button:
	return _ui.get_node_or_null(^"TouchActions/ReturnToTitle") as Button


func _world_direction(input: Vector2) -> Vector3:
	var rig := _main.get_node(^"CameraRig") as CameraRig
	return (rig.planar_right() * input.x - rig.planar_forward() * input.y).normalized()


func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _check_facing(dir: Vector2, label: String) -> void:
	_check.expect(await Harness.wait_until(func() -> bool:
		return _player.get_facing_direction().dot(_world_direction(dir)) > 0.995, 2.0),
		"Wrong camera-relative direction: %s (got %s)" % [label, _player.get_facing_direction()])


func _pause_navigation() -> void:
	Harness.stage = "pause, journal and Back"
	var touch_menu := _ui.get_node(^"TouchActions/Pause") as Button
	_check_target(touch_menu, "Touch Menu")
	var use := _ui.get_node(^"TouchActions/Use") as Button
	_check.expect(touch_menu.icon != null and _return_button().icon != null and use.icon != null,
		"The HUD buttons lost their phone glyphs")
	var before := _nav.get_world_click_event_count()
	await _tap_control(touch_menu)
	if not _check.expect(_pause.is_open() and paused, "Touch Menu did not pause the scene tree"):
		return
	var resume := _pause.get_entry(&"resume")
	var scroll := resume.get_parent().get_parent() as ScrollContainer
	var safe := MobileLayout.safe_rect(resume)
	_check.expect(safe.encloses(scroll.get_global_rect()) and scroll.size.x <= safe.size.x * 0.60
		and scroll.size.y <= safe.size.y * 0.70, "Pause column took up too much of the phone: %s" % scroll.size)
	for id: StringName in PauseMenu.ENTRIES:
		var entry := _pause.get_entry(id)
		_check_target(entry, "Pause " + String(id))
		_check.expect(scroll.get_global_rect().grow(1.0).encloses(entry.get_global_rect()),
			"A standard phone pause entry needs scrolling: " + String(id))
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
	var controller := _main.get_node(^"DialogueController") as DialogueController
	if not _check.expect(not controller.is_busy(), "A real presentation got into the dialogue layout fixture"):
		return
	var panel := _ui.dialogue_panel
	panel.set_reveal_speed(0.1)
	var line := "A readable line for checking touch. ".repeat(90)
	panel.show_line({"speaker_name": "Test", "text": line})
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
	_check.expect(panel.get_body_text() == line, "Continue replaced the fixture before it could be scrolled")
	var body := panel.get_body_label()
	var content_height := body.get_content_height()
	_check.expect(body.scroll_active and float(content_height) > body.size.y,
		"Long paragraph was not given a scrollable body: text=%s height=%s size=%s band=%s" % [
			body.text.length(), content_height, body.size, panel.size])
	var start := body.get_global_rect().get_center()
	var bar := body.get_v_scroll_bar()
	var origin := bar.value
	_touch(start, true)
	var capture := int(panel.get("_body_touch"))
	_drag(start, start - Vector2(0, 64))
	var changed := bar.value
	_touch(start - Vector2(0, 64), false)
	await process_frame
	_check.expect(bar.value > origin and continued[0] == 0,
		"Dragging long dialogue did not just scroll: active=%s finger=%s position=%s->%s->%s range=%s advance=%s" % [
			body.scroll_active, capture, origin, changed, bar.value, bar.max_value - bar.page, continued[0]])
	await _tap_control(next_line)
	_check.expect(continued[0] == 1, "One tap did not continue exactly once")
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


func _large_reading() -> void:
	Harness.stage = "largest text on compact phone and tablet"
	_settings.call("set_text_size", &"largest")
	var loc := root.get_node(^"Loc")
	var panel := _ui.dialogue_panel
	for sample: Array in [[SCREENS[0], "en", "A short layout sample."], [SCREENS[2], "zh-CN", "这段文字用于检查横屏阅读。"]]:
		await _set_screen(sample[0])
		loc.call("set_locale", sample[1])
		panel.show_line({"speaker_name": "Test", "text": sample[2]})
		_check.expect(await Harness.wait_until(func() -> bool: return not bool(panel.get("_layout_dirty")), 3.0),
			"Large reading layout did not settle")
		var button := panel.find_child("TouchReading", true, false).get_node(^"Continue") as Button
		_check_target(button, "Largest %s Continue" % sample[1])
		var body := panel.get_body_label()
		_check.expect(body.get_content_height() <= body.size.y + 1.0 or body.scroll_active,
			"Large %s reading body clipped without scroll" % sample[1])
		panel.close()


func _compare_touch() -> void:
	Harness.stage = "largest bilingual notebook on mobile"
	var loc := root.get_node(^"Loc")
	var narrative := root.get_node(^"NarrativeState")
	_settings.call("set_text_size", &"largest")
	_pause.open_journal()
	var journal := _pause.get_journal_panel()
	var catalog := journal.get_catalog()
	if not _check.expect(catalog != null, "Notebook has no catalog"):
		return
	var pairs := catalog.get_comparisons()
	if not _check.expect(pairs.size() >= 2, "Notebook has fewer than two authored pairs"):
		return
	for pair: Dictionary in pairs:
		for id: StringName in [pair["left"], pair["right"]]:
			var note := catalog.lookup(id, "en")
			narrative.record(id, int(note["source"]), StringName(note["speaker_id"]), String(note["text"]))
	for metrics: Array in SCREENS:
		await _set_screen(metrics)
		for locale: String in L10n.LOCALES:
			await _swipe_comparison(journal, pairs, loc, locale, "%s %s" % [metrics[0], locale])
	await _tap_control(journal.get_back_button())
	_check.expect(not journal.is_open(), "Mobile Back did not close the notebook after scrolling")


func _swipe_comparison(journal: JournalPanel, pairs: Array[Dictionary], loc: Node, locale: String, tag: String) -> void:
	# Start on a new page: a fit/rotation must not be needed after tapping a tab.
	loc.call("set_locale", locale)
	await process_frame
	await _tap_control(journal.get_filter_button(JournalPage.ALL))
	var compare := journal.get_filter_button(JournalPage.COMPARE)
	_check_target(compare, tag + " Compare")
	_check_target(journal.get_back_button(), tag + " Back")
	await _tap_control(compare)
	if not _check.expect(journal.get_filter() == JournalPage.COMPARE and journal.get_row_ids().size() == pairs.size() * 2,
			tag + ": tapping Compare did not show both sides of each pair"):
		return
	var scroll := journal.get_scroll()
	if not _check.expect(scroll.size.y >= 2.0 * MobileLayout.hit_size(scroll),
			"%s: header and tabs leave only %.0f px for reading" % [tag, scroll.size.y]):
		return
	var first := journal.find_child("Comparison_%s" % pairs[0]["id"], true, false) as Control
	var topic := first.find_child("Topic", true, false) as Control if first != null else null
	if not _check.expect(topic != null, tag + ": the first card's title is missing"):
		return
	# The route and reading progress share the scroll. Bring the first topic into view
	# before swiping on the card itself, not in the gutter or on the scrollbar.
	scroll.ensure_control_visible(topic)
	await process_frame
	var clip := scroll.get_global_rect().intersection(first.get_global_rect())
	if not _check.expect(clip.has_area(), tag + ": no part of the first card can be reached"):
		return
	var origin := scroll.scroll_vertical
	await _swipe(clip.get_center(), clip.get_center() - Vector2(0, 100))
	_check.expect(scroll.scroll_vertical > origin, tag + ": swiping a comparison card did not scroll")


func _return_during_dialogue() -> void:
	Harness.stage = "touch Use with a held stick; return without interrupting a dialogue"
	await _tap_control(_pause.get_entry(&"resume"))
	var save := root.get_node(^"Save")
	var state := root.get_node(^"GameState")
	var narrative := root.get_node(^"NarrativeState")
	var flags := {
		StoryFlags.MET_Q: true, StoryFlags.TEXTBOOK_MISSING: true, StoryFlags.EXPECTATION_PLAYED: true,
		StoryFlags.BELL_RUNG: true, StoryFlags.CLASS_DISMISSED: true,
		StoryFlags.OBJECTIVE_KEY: "objective.leave_classroom",
	}
	var written: Dictionary = save.write_payload({"flags": SaveCodec.encode_flags(flags),
		"entries": [], "check_seed": 7, "world": {"location_id": "corridor", "spawn": "FromClassroom"}})
	_check.expect(written.get("ok", false), "Could not seed the corridor checkpoint")
	var checkpoint := FileAccess.get_file_as_bytes(SAVE_PATH)
	state.set_flag(&"mobile_live_probe", true)
	state.set_flag(StoryFlags.MET_Q, true)
	_check.expect(await _offer_schoolbag(), "No reachable schoolbag prompt for the second finger")
	var use := _ui.get_node(^"TouchActions/Use") as Button
	_check.expect(use.is_visible_in_tree() and not use.disabled, "Use did not activate near the schoolbag")
	var center := _stick().get_global_rect().get_center()
	var controller := _main.get_node(^"DialogueController") as DialogueController
	var activations: Array[StringName] = []
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	interaction.activation_requested.connect(func(target: Interactable) -> void: activations.append(target.interact_id))
	_touch(center, true)
	await _tap_control(use, 3)
	_touch(center, false)
	var presented := await Harness.wait_until(func() -> bool:
		return controller.is_busy() and _ui.dialogue_panel.visible and _return_button().is_visible_in_tree(), 8.0)
	if not _check.expect(activations == [&"schoolbag"] and presented,
			"The second finger did not use the schoolbag exactly once: %s" % [activations]):
		return
	var panel := _ui.dialogue_panel
	var line := panel.get_body_text()
	_check.expect(not _stick().is_visible_in_tree() and _return_button().is_visible_in_tree(),
		"The dialogue obscured Return or left the joystick over the text")
	await _tap_control(_return_button())
	var prompt := _pause.get_confirm()
	_check.expect(paused and prompt.visible and root.gui_get_focus_owner() == prompt.get_cancel_button(),
		"Return did not pause on the safe answer")
	_check.expect(prompt.get_message().contains(L10n.t("place.corridor")), "Return did not name the prior checkpoint")
	await _tap_control(prompt.get_cancel_button())
	_check.expect(not paused and controller.is_busy() and panel.get_body_text() == line,
		"Keep playing interrupted or advanced the live conversation")
	_check.expect(FileAccess.get_file_as_bytes(SAVE_PATH) == checkpoint, "Opening/canceling Return wrote a save")
	var advance := panel.find_child("TouchReading", true, false).get_node(^"Continue") as Button
	if panel.is_revealing():
		await _tap_control(advance)
		_check.expect(not panel.is_revealing() and controller.is_busy(), "The resumed line could not finish revealing")
	# Leave this presentation before advancing; it is deliberately absent from the save.
	var old_world: WeakRef = weakref(_main)
	var old_dialogue: WeakRef = weakref(controller)
	await _tap_control(_return_button())
	await _confirm_twice(prompt.get_confirm_button())
	var title := await _wait_title()
	if title == null:
		return
	_check.expect(old_world.get_ref() == null and old_dialogue.get_ref() == null and not paused,
		"Return left an old world/dialogue alive or the title paused")
	_check.expect(state.get_snapshot().is_empty() and narrative.get_entries().is_empty(),
		"Return leaked transient flags or knowledge to the title")
	_check.expect(FileAccess.get_file_as_bytes(SAVE_PATH) == checkpoint, "Returning during dialogue changed the checkpoint")
	_check.expect(root.gui_get_focus_owner() == title.get_entry(&"continue"), "Return did not give the new title focus")
	await _return_from_corridor(title)


func _return_from_corridor(title: TitleScreen) -> void:
	Harness.stage = "title Continue, return from corridor and start a fresh game"
	await _tap_control(title.get_entry(&"continue"))
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_SCENE, 8.0),
		"Title Continue did not enter the game"):
		return
	_main = current_scene
	_ui = _main.get_node(^"GameUI") as GameUI
	_player = _main.get_node(^"Player") as PlayerController
	_pause = _main.get_node(^"PauseMenu") as PauseMenu
	var host := _main.get_node(^"LocationHost") as LocationHost
	if not _check.expect(host.get_current().location_id == &"corridor" and not _ui.dialogue_panel.visible,
			"Continue did not restore the corridor checkpoint cleanly"):
		return
	if not _check.expect(await Harness.wait_until(_return_button().is_visible_in_tree, 5.0),
			"The corridor did not show the touch controls"):
		return
	var stick := _stick()
	var center := stick.get_global_rect().get_center()
	# FromClassroom faces the corridor's open width. Test sustained displacement here,
	# not wedged against a desk after the classroom's eight-direction sweep.
	await _hold_and_release_in_corridor(stick, center)
	var down := center + Vector2.LEFT * stick.size.x * 0.3
	_touch(down, true)
	await _check_facing(Vector2.LEFT, "corridor")
	await _tap_control(_return_button(), 2)
	var prompt := _pause.get_confirm()
	_check.expect(prompt.visible and paused and _horizontal_speed() < 0.001,
		"The other thumb could not pause and reset the stick")
	var answer := prompt.get_confirm_button().get_global_rect().get_center()
	_drag(down, answer)
	_touch(answer, false)
	_check.expect(prompt.visible, "The original joystick release activated the modal")
	_check.expect(prompt.get_message() == L10n.t("menu.confirm_return_save"), "Stable corridor did not offer to save")
	var save := root.get_node(^"Save")
	var writes := int(save.saves_written)
	var world: WeakRef = weakref(_main)
	await _confirm_twice(prompt.get_confirm_button())
	var title_again := await _wait_title()
	if title_again == null:
		return
	_check.expect(world.get_ref() == null and int(save.saves_written) == writes + 1,
		"Repeated confirm issued multiple saves or did not free the corridor")
	await _tap_control(title_again.get_entry(&"new_game"))
	_check.expect(title_again.get_confirm().visible, "Title New game no longer confirms")
	await _tap_control(title_again.get_confirm().get_confirm_button())
	var session := root.get_node(^"Session")
	if _check.expect(await Harness.wait_until(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_SCENE \
			and not session.is_starting_new_game(), 8.0), "Title New game did not finish its transaction"):
		var host_again := current_scene.get_node(^"LocationHost") as LocationHost
		var state := root.get_node(^"GameState")
		_check.expect(host_again.get_current().location_id == &"classroom" and not save.has_save() \
			and not state.get_flag(StoryFlags.CLASS_DISMISSED, false) and not paused,
			"New game carried the old location or checkpoint into its opening")


func _hold_and_release_in_corridor(stick: Control, center: Vector2) -> void:
	var rig := _main.get_node(^"CameraRig") as CameraRig
	var across := Vector2(rig.planar_right().x, -rig.planar_forward().x).normalized()
	var start_x := _player.global_position.x
	_touch(center + across * stick.size.x * 0.3, true)
	_check.expect(await Harness.wait_until(func() -> bool:
		return _player.global_position.x > start_x + 0.18, 3.0),
		"The player did not keep walking without new drag events")
	var stopped := _player.global_position
	_touch(center + across * stick.size.x, false)
	await physics_frame
	await physics_frame
	var displacement := _player.global_position - stopped
	_check.expect(_horizontal_speed() < 0.001 and Vector2(displacement.x, displacement.z).length() < 0.02,
		"Thumb up did not stop displacement on the next physics frame")


func _offer_schoolbag() -> bool:
	# A real prop, in sight and within reach; use the authored navigation mesh to avoid
	# pinning a position to a chair that may move in a future art pass.
	var host := _main.get_node(^"LocationHost") as LocationHost
	var target := host.get_current().find_interactable(&"schoolbag")
	if target == null:
		return false
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	var map := _player.navigation_agent.get_navigation_map()
	var use := _ui.get_node(^"TouchActions/Use") as Button
	for i in range(16):
		var angle := float(i) * TAU / 16.0
		var point := target.global_position + Vector3(cos(angle), 0, sin(angle)) * 1.4
		var floor_point := NavigationServer3D.map_get_closest_point(map, point)
		if not interaction.is_in_reach_at(floor_point, target):
			continue
		_player.teleport(Transform3D(Basis.IDENTITY, floor_point + Vector3.UP * 0.05))
		_player.face_toward(target.global_position - floor_point)
		if await Harness.wait_until(func() -> bool:
			return interaction.get_current_target() == target and use.is_visible_in_tree(), 0.35):
			return true
	return false


func _confirm_twice(button: Button) -> void:
	var p := button.get_global_rect().get_center()
	_touch(p, true)
	_touch(p, true, 8)
	_touch(p, false)
	_touch(p, false, 8)
	await process_frame


func _wait_title() -> TitleScreen:
	if _check.expect(await Harness.wait_until(func() -> bool:
		return current_scene is TitleScreen, 8.0), "The title never became the current scene"):
		await process_frame
		return current_scene as TitleScreen
	return null


func _check_target(control: Control, label: String) -> void:
	if not _check.expect(control != null and control.is_visible_in_tree(), label + " is not visible"):
		return
	var transform := root.get_final_transform() * control.get_global_transform_with_canvas()
	var physical := transform * Rect2(Vector2.ZERO, control.size)
	var safe := MobileLayout.safe_pixels(root).grow(1.0)
	var side := MobileLayout.TARGET_POINTS * MobileLayout.density(root) - 1.0
	_check.expect(safe.encloses(physical), "%s outside %s: %s" % [label, safe, physical])
	_check.expect(physical.size.x >= side and physical.size.y >= side, "%s is too small: %s" % [label, physical.size])


func _tap_control(control: Control, index: int = 0) -> void:
	if control == null:
		return
	var center := control.get_global_transform_with_canvas() * (control.size * 0.5)
	_touch(center, true, index)
	await process_frame
	_touch(center, false, index)
	await process_frame
	await process_frame


func _swipe(from: Vector2, to: Vector2) -> void:
	_touch(from, true)
	_drag(from, to)
	await process_frame
	_touch(to, false)
	await process_frame


func _drag(from: Vector2, to: Vector2, index: int = 0) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
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
