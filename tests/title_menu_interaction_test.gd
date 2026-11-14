extends SceneTree
## The title menu, driven only the way a player drives it (#121).
##
## Every press here is an `InputEvent` handed to `Input.parse_input_event()` - the door the
## operating system's own events come through - in **window** coordinates. The engine then
## does the rest exactly as for a real mouse, key or pad: the window maps the point into the
## viewport (through the UI scale when there is one), the GUI finds the Control under it,
## the Button's own press/release logic decides whether it was clicked, and the focused
## Button answers `ui_accept`. There is no `activate()`, no `pressed.emit()`, no direct call
## to `Session.start_new_game()`.
##
## It runs under Xvfb with the OpenGL renderer: a real window, a real viewport image.
##
## The run is split in parts so each stays well inside its CI budget (`-- --part=<name>`):
##
## - `mouse`  (1600x900, English): no save -> Start; a valid save -> New game -> Cancel keeps
##   the save byte for byte -> New game -> Confirm; an unreadable save -> the reason and the
##   quarantined copy on screen -> New game -> Confirm keeps the copy byte for byte. Start
##   and Confirm are each clicked twice in quick succession and must start one game.
## - `keys`   (1600x900, English): Enter and Space on Start, and the pad's A on New game,
##   D-pad to Confirm, A again - the same entry, the same one start.
## - `matrix` (1280x720 and 1920x1080, Chinese, largest text): the same clicks still land on
##   the entry under the pointer, Cancel still keeps the save, Start still starts.
##
## Every part also checks what the player sees on the real viewport image: one entry marked
## at a time (the pointer moves the mark; it does not add a second one), the mark really
## drawn, and the page on the project ink rather than the viewport's clear colour.
##
## Every start must end on `main.tscn` with the opening's next step `wake`, and exactly one
## `Session.new_game_started` per player decision. A start that fails is the other half of
## #121's point 5; `tests/new_game_failure_ui_test.gd` drives it with the same real inputs
## (the title stays, the reason is shown, New game is enabled and focused, and a retry by
## mouse starts the game).

const Harness = preload("res://tests/test_harness.gd")
const TITLE := "res://scenes/ui/title_screen.tscn"
const MAIN := "res://scenes/main/main.tscn"
const SAVE_PATH := "user://save.json"
const BROKEN_PATH := "user://save.broken.json"
## The ink every menu page is set on (MenuStyle.INK, 0.043/0.051/0.051), darkened at the
## edges by the vignette. The viewport's clear colour (0.106/0.118/0.118) is far above this.
const INK_CEILING := 0.08

var _failures: Array[String] = []
var _part := "mouse"
var _session: Node = null
var _save: Node = null
var _settings: Node = null
var _loc: Node = null
var _starts := 0
var _activations: Array[StringName] = []
var _locale_before := ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--part="):
			_part = arg.trim_prefix("--part=")
	Harness.arm_watchdog(self, 180.0, "title_menu_interaction_test.gd (%s)" % _part)
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	_save = root.get_node(^"Save")
	_settings = Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	_session = Harness.ensure_autoload(self, "Session", "res://scripts/ui/game_session.gd")
	_session.connect("new_game_started", func(_report: Dictionary) -> void: _starts += 1)
	_locale_before = L10n.current
	await process_frame
	var window := Vector2i(root.size)
	print("title menu interaction: part %s, window %s, UI scale %.2f" % [
		_part, str(window), _ui_scale()
	])
	if root.get_texture() == null or root.get_texture().get_image() == null:
		_fail("the viewport has no image: this is not a real window (run it under Xvfb)")
	else:
		match _part:
			"mouse":
				await _part_mouse()
			"keys":
				await _part_keys()
			"matrix":
				await _part_matrix()
			_:
				_fail("unknown part '%s'" % _part)
	# Leave the shared user:// as it was found: no save, default text size, same language.
	if _settings != null:
		_settings.call("reset_to_defaults")
	_set_locale(_locale_before)
	Harness.clear_session_state(self)
	Harness.finish(self, _failures, _summary())


func _summary() -> String:
	match _part:
		"keys":
			return "Enter, Space and the pad's A reach the focused title entry and the new-game question through the real input path; each decision starts one game at the opening's wake."
		"matrix":
			return "at %s in Chinese at the largest text size, pointer clicks land on the title entry under them, Cancel keeps the save byte for byte, and Start starts one game at the opening's wake." % str(Vector2i(root.size))
	return "real pointer clicks in window coordinates start the game from Start, ask before New game, keep the save on Cancel and the quarantined copy on Confirm, start one game per double click, and end on main.tscn at the opening's wake; one entry is marked at a time on the project ink."


# --- Parts ----------------------------------------------------------------------------


func _part_mouse() -> void:
	# 1. No save: Start. Clicked twice in quick succession - one game.
	Harness.stage = "mouse: no save"
	var title := await _fresh_title()
	if title == null:
		return
	_expect(title.get_entry_ids() == [&"new_game", &"settings", &"quit"],
		"no save: the list is %s, not Start, Settings, Quit" % str(title.get_entry_ids()))
	await _check_page(title, "no save")
	await _double_click_and_start(title.get_entry(&"new_game"), title, "Start")

	# 2. A valid save: New game asks; Cancel keeps the save; Confirm (twice) starts one game.
	Harness.stage = "mouse: valid save"
	title = await _title_with_valid_save()
	if title == null:
		return
	await _cancel_keeps_save(title, "valid save")
	await _click(title.get_entry(&"new_game"))
	_expect(title.get_confirm().visible, "valid save: New game did not ask again after Cancel")
	await _double_click_and_start(title.get_confirm().get_confirm_button(), title, "Confirm")

	# 3. An unreadable save: the reason and the copy, and Confirm keeps the copy.
	Harness.stage = "mouse: unreadable save"
	await _leave_to_title()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ not valid save")
	file.close()
	title = await _open_title()
	if title == null:
		return
	_expect(title.get_save_state() == &"broken", "unreadable save: the title reads it as '%s'" % title.get_save_state())
	_expect(not title.get_entry_ids().has(&"continue"), "unreadable save: Continue is offered")
	var notice := title.get_notice_text()
	_expect(notice.contains(L10n.t("menu.save_unreadable")), "unreadable save: the notice does not say so: '%s'" % notice)
	_expect(notice.contains(BROKEN_PATH.get_file()), "unreadable save: the notice does not say where the copy is: '%s'" % notice)
	_expect(FileAccess.file_exists(BROKEN_PATH), "unreadable save: no quarantined copy was kept")
	var copy := FileAccess.get_file_as_bytes(BROKEN_PATH)
	await _check_page(title, "unreadable save")
	await _click(title.get_entry(&"new_game"))
	_expect(title.get_confirm().visible, "unreadable save: New game did not ask first")
	_expect(_focus_owner() == title.get_confirm().get_cancel_button(), "unreadable save: the question did not open on Cancel")
	_expect(FileAccess.get_file_as_bytes(BROKEN_PATH) == copy, "unreadable save: asking changed the quarantined copy")
	await _click_and_start(title.get_confirm().get_confirm_button(), title, "Confirm (unreadable save)")
	_expect(FileAccess.file_exists(BROKEN_PATH) and FileAccess.get_file_as_bytes(BROKEN_PATH) == copy,
		"unreadable save: the new game removed or changed the quarantined copy")


func _part_keys() -> void:
	for key: Key in [KEY_ENTER, KEY_SPACE]:
		var name := OS.get_keycode_string(key)
		Harness.stage = "keys: %s on Start" % name
		var title := await _fresh_title()
		if title == null:
			return
		_expect(_focus_owner() == title.get_entry(&"new_game"), "%s: Start does not have the focus on a fresh title" % name)
		await _check_page(title, name)
		var before := _starts
		await _key(key)
		_expect(_activations == [&"new_game"], "%s: the entries activated were %s, not [new_game]" % [name, str(_activations)])
		await _wait_for_start(before, "%s on Start" % name)

	Harness.stage = "pad: A on New game, D-pad, A on Confirm"
	var title := await _title_with_valid_save()
	if title == null:
		return
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_expect(_focus_owner() == title.get_entry(&"new_game"), "pad: D-pad down did not move from Continue to New game")
	await _pad(JOY_BUTTON_A)
	_expect(_activations == [&"new_game"], "pad: the entries activated were %s, not [new_game]" % str(_activations))
	_expect(title.get_confirm().visible, "pad: A on New game did not ask first")
	_expect(_focus_owner() == title.get_confirm().get_cancel_button(), "pad: the question did not open on Cancel")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_expect(_focus_owner() == title.get_confirm().get_confirm_button(), "pad: D-pad right did not reach Confirm")
	var before := _starts
	await _pad(JOY_BUTTON_A)
	await _wait_for_start(before, "pad A on Confirm")


func _part_matrix() -> void:
	_set_locale("zh-CN")
	if _settings != null:
		_settings.call("set_text_size", &"largest")
	await process_frame
	var factor := UiTextScale.current(root)
	_expect(factor >= 1.25, "matrix: the largest text size scales by only %.2f" % factor)

	Harness.stage = "matrix: valid save, Chinese, largest text"
	var title := await _title_with_valid_save()
	if title == null:
		return
	_expect(title.get_entry(&"new_game").text == L10n.t("menu.new_game"), "matrix: New game is not in Chinese: '%s'" % title.get_entry(&"new_game").text)
	_expect(title.get_entry(&"new_game").get_theme_font_size(&"font_size") == UiTextScale.scaled(MenuStyle.ENTRY_SIZE, factor),
		"matrix: the entries are not at the largest text size")
	await _check_page(title, "matrix, valid save")
	await _cancel_keeps_save(title, "matrix")

	Harness.stage = "matrix: no save, Chinese, largest text"
	title = await _fresh_title()
	if title == null:
		return
	_expect(title.get_entry(&"new_game").text == L10n.t("menu.start"), "matrix: Start is not in Chinese: '%s'" % title.get_entry(&"new_game").text)
	await _check_page(title, "matrix, no save")
	await _click_and_start(title.get_entry(&"new_game"), title, "Start (matrix)")


# --- Shared checks --------------------------------------------------------------------


## New game on a valid save asks first, on Cancel; a click on Cancel closes the question,
## puts the focus back on New game and leaves the save exactly as it was.
func _cancel_keeps_save(title: TitleScreen, tag: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	_expect(not bytes.is_empty(), "%s: the save fixture is empty" % tag)
	var starts_before := _starts
	await _click(title.get_entry(&"new_game"))
	_expect(_activations == [&"new_game"], "%s: the click activated %s, not [new_game]" % [tag, str(_activations)])
	_expect(title.get_confirm().visible, "%s: New game on a save did not ask first" % tag)
	_expect(_focus_owner() == title.get_confirm().get_cancel_button(), "%s: the question did not open on Cancel" % tag)
	await _click(title.get_confirm().get_cancel_button())
	_expect(not title.get_confirm().visible, "%s: Cancel did not close the question" % tag)
	_expect(_focus_owner() == title.get_entry(&"new_game"), "%s: Cancel did not return the focus to New game" % tag)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == bytes, "%s: Cancel changed or removed the save" % tag)
	_expect(_starts == starts_before and current_scene == title, "%s: Cancel started a new game" % tag)


## What the player sees, read off the real viewport image: the page on the project ink;
## the pointer over an entry moves the one mark there (focus follows it) instead of
## lighting a second entry; and the mark is really drawn under the entry text.
func _check_page(title: TitleScreen, tag: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var column := _window_rect(title.get_column())
	var corner := image.get_pixel(clampi(int(column.position.x * 0.5), 0, image.get_width() - 1), 4)
	_expect(maxf(corner.r, maxf(corner.g, corner.b)) <= INK_CEILING,
		"%s: the page behind the column is %s, not the project ink (the clear colour shows through)" % [tag, str(corner)])

	var settings := title.get_entry(&"settings")
	var quit := title.get_entry(&"quit")
	var plain := _mean_warmth(image, _window_rect(settings))
	await _hover(settings)
	_expect(root.gui_get_hovered_control() == settings, "%s: the pointer over Settings hovers %s" % [tag, str(root.gui_get_hovered_control())])
	_expect(_focus_owner() == settings, "%s: the pointer over Settings left the mark on %s" % [tag, str(_focus_owner())])
	await _frames(1)
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	var marked := _mean_warmth(image, _window_rect(settings))
	_expect(marked > plain + 0.01, "%s: the mark is not drawn under Settings (warmth %.3f, unmarked %.3f)" % [tag, marked, plain])
	for id: StringName in title.get_entry_ids():
		if id == &"settings":
			continue
		var other := _mean_warmth(image, _window_rect(title.get_entry(id)))
		_expect(other < marked - 0.01, "%s: '%s' still looks marked while the pointer is on Settings (%.3f vs %.3f)" % [tag, id, other, marked])
	await _hover(quit)
	_expect(_focus_owner() == quit, "%s: the mark did not follow the pointer to Quit" % tag)
	# Back to where a player would start: the first entry, and the pointer off the list.
	await _move_pointer(Vector2(root.size) * Vector2(0.97, 0.97))
	title.focus_entry(title.get_entry_ids()[0])
	await _frames(1)
	_activations.clear()


## Two full clicks a player makes in a hurry, the second as a double click on the same
## spot. The first starts the game and disables the list; the second finds nothing to
## press. One activation, one start, and the opening at wake.
func _double_click_and_start(button: Button, title: TitleScreen, tag: String) -> void:
	if button == null:
		_fail("%s: the button is missing" % tag)
		return
	await _frames(1)
	var point := _window_point(button)
	var before := _starts
	var before_activations := _activations.size()
	await _move_pointer(point)
	await _press_release(point, false)
	if is_instance_valid(title) and current_scene == title:
		var entry := title.get_entry(&"new_game")
		_expect(entry != null and entry.disabled, "%s: the list is still enabled while the game starts" % tag)
	await _press_release(point, true)
	await _wait_for_start(before, tag)
	var new_game_activations := _activations.slice(before_activations).count(&"new_game")
	_expect(new_game_activations <= 1, "%s: the double click activated New game %d times" % [tag, new_game_activations])


func _click_and_start(button: Button, title: TitleScreen, tag: String) -> void:
	var before := _starts
	await _click(button)
	if is_instance_valid(title) and current_scene == title:
		var entry := title.get_entry(&"new_game")
		_expect(entry != null and entry.disabled, "%s: the list is still enabled while the game starts" % tag)
	await _wait_for_start(before, tag)


## The decision must end on main.tscn, at the opening's first step, with exactly one start
## and no second one arriving a little later.
func _wait_for_start(before: int, tag: String) -> void:
	for _i in 300:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MAIN:
			break
	if current_scene == null or current_scene.scene_file_path != MAIN:
		_fail("%s: the game did not reach %s (current %s)" % [
			tag, MAIN, current_scene.scene_file_path if current_scene != null else "none"
		])
		return
	await _frames(20)
	_expect(_starts - before == 1, "%s: Session started %d new games, not 1" % [tag, _starts - before])
	var director := current_scene.get_node_or_null(^"OpeningSequence")
	_expect(director != null and director.call("next_step") == &"wake",
		"%s: the opening does not begin at wake (next step %s)" % [
			tag, str(director.call("next_step")) if director != null else "none"
		])


# --- Titles ---------------------------------------------------------------------------


## A title with no save on disk.
func _fresh_title() -> TitleScreen:
	await _leave_to_title()
	Harness.clear_session_state(self)
	return await _open_title()


## A title over a real save: the one the running game writes, so Continue has a room and a
## time under it. Falls back to a written payload if the world wrote none.
func _title_with_valid_save() -> TitleScreen:
	await _leave_to_title()
	var report: Dictionary = _session.call("inspect_save")
	if StringName(report.get("state", &"none")) != &"valid":
		var written: Dictionary = _save.call("write_payload", {"flags": {}, "entries": [], "check_seed": 0})
		_expect(bool(written.get("ok", false)), "could not write the valid-save fixture")
	var title := await _open_title()
	if title != null:
		_expect(title.get_save_state() == &"valid", "valid save: the title reads it as '%s'" % title.get_save_state())
		_expect(title.get_entry_ids() == [&"continue", &"new_game", &"settings", &"quit"],
			"valid save: the list is %s, not Continue, New game, Settings, Quit" % str(title.get_entry_ids()))
		_expect(_focus_owner() == title.get_entry(&"continue"), "valid save: Continue does not have the focus")
	return title


## Leaves a running game through Session, the way the pause menu does.
func _leave_to_title() -> void:
	if current_scene != null and current_scene.scene_file_path == MAIN:
		_session.call("go_to_title")
		for _i in 120:
			await process_frame
			if current_scene is TitleScreen:
				break


func _open_title() -> TitleScreen:
	change_scene_to_file(TITLE)
	for _i in 120:
		await process_frame
		if current_scene is TitleScreen and current_scene.is_node_ready():
			break
	var title := current_scene as TitleScreen
	if title == null:
		_fail("the title scene did not load")
		return null
	title.entry_activated.connect(func(id: StringName) -> void: _activations.append(id))
	_activations.clear()
	# The column is fitted again after the first layout pass.
	await _frames(3)
	return title


# --- Input, the player's way ----------------------------------------------------------


## Where a Control's centre is in the window: the viewport point mapped through the
## window's final transform (the UI scale, when there is one).
func _window_point(control: Control) -> Vector2:
	var local := control.get_global_transform_with_canvas() * (control.size * 0.5)
	return root.get_final_transform() * local


func _window_rect(control: Control) -> Rect2:
	var final := root.get_final_transform() * control.get_global_transform_with_canvas()
	return Rect2(final * Vector2.ZERO, final.basis_xform(control.size)).abs()


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_send(motion)
	await _frames(1)


func _hover(control: Control) -> void:
	await _move_pointer(_window_point(control))


func _press_release(point: Vector2, as_double: bool) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.double_click = as_double
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = point
	down.global_position = point
	_send(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.button_mask = 0
	up.position = point
	up.global_position = point
	_send(up)
	await _frames(1)


## A full click: the pointer arrives, the GUI sees it over the button, press, release.
func _click(button: Button) -> void:
	if button == null:
		_fail("a button the click needs is missing")
		return
	await _frames(1)
	var point := _window_point(button)
	await _move_pointer(point)
	_expect(root.gui_get_hovered_control() == button, "the pointer at %s hovers %s, not '%s'" % [
		str(point), str(root.gui_get_hovered_control()), button.name
	])
	await _press_release(point, false)


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	_send(down)
	await _frames(1)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	_send(up)
	await _frames(1)


func _pad(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.device = 0
	down.button_index = button
	down.pressed = true
	_send(down)
	await _frames(1)
	var up := down.duplicate() as InputEventJoypadButton
	up.pressed = false
	_send(up)
	await _frames(1)


# --- Small helpers --------------------------------------------------------------------


func _focus_owner() -> Control:
	return root.gui_get_focus_owner()


func _ui_scale() -> float:
	if _settings != null and _settings.has_method("get_applied_ui_scale"):
		return float(_settings.call("get_applied_ui_scale"))
	return 1.0


func _set_locale(locale: String) -> void:
	if _loc != null and _loc.has_method("set_locale"):
		_loc.call("set_locale", locale)
	else:
		L10n.set_locale(locale)


## How much warmer than neutral a strip of the entry is: the ember mark (and its lit text)
## raise red over blue. The strip is the left part of the entry, where the mark's border
## and wash sit, sampled every other pixel.
func _mean_warmth(image: Image, rect: Rect2) -> float:
	var area := Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if area.size.x <= 0 or area.size.y <= 0:
		return 0.0
	var total := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			var pixel := image.get_pixel(x, y)
			total += pixel.r - pixel.b
			count += 1
	return total / float(maxi(count, 1))


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("[%s] %s" % [_part, message])


func _fail(message: String) -> void:
	_failures.append("[%s] %s" % [_part, message])
