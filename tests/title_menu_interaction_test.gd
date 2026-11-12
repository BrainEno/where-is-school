extends SceneTree
## End-to-end title input regression: synthetic pointer events hit the real Button rects.
const Harness = preload("res://tests/test_harness.gd")
const TITLE := "res://scenes/ui/title_screen.tscn"
const MAIN := "res://scenes/main/main.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "title_menu_interaction_test.gd")
	call_deferred("_run")

func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.ensure_autoload(self, "Session", "res://scripts/ui/game_session.gd")
	Harness.ensure_autoload(self, "Settings", "res://scripts/autoload/settings_manager.gd")
	var save := root.get_node(^"Save")
	save.forget_all()
	await _open_title()
	var title := current_scene as TitleScreen
	_check(title != null and title.get_entry_ids() == [&"new_game", &"settings", &"quit"], "No-save menu must show Start, Settings, Quit.")
	await _click(title.get_entry(&"new_game"))
	await _wait_for_scene(MAIN)
	_check(_opening_starts_at_wake(), "Mouse Start did not enter main.tscn at wake.")

	# Save a real running world, return to title, and exercise Cancel then Confirm by pointer.
	root.get_node(^"Session").call("go_to_title")
	await _wait_for_title()
	var written: Dictionary = save.write_payload({"flags": {}, "entries": [], "check_seed": 0})
	_check(bool(written.get("ok", false)), "Could not create the valid-save interaction fixture.")
	await _open_title()
	title = current_scene as TitleScreen
	_check(title.get_entry_ids() == [&"continue", &"new_game", &"settings", &"quit"], "Saved menu must show Continue and New Game.")
	await _click(title.get_entry(&"new_game"))
	_check(title.get_confirm().visible, "Mouse New Game did not open confirmation.")
	await _click(title.get_confirm().get_cancel_button())
	_check(save.has_save(), "Mouse Cancel deleted the valid save.")
	_check(not title.get_confirm().visible, "Mouse Cancel did not close confirmation.")
	await _click(title.get_entry(&"new_game"))
	await _click(title.get_confirm().get_confirm_button())
	await _wait_for_scene(MAIN)
	_check(_opening_starts_at_wake(), "Confirmed mouse New Game did not start at wake.")

	root.get_node(^"Session").call("go_to_title")
	await _wait_for_title()
	var file := FileAccess.open("user://save.json", FileAccess.WRITE)
	file.store_string("{ not valid save")
	file.close()
	await _open_title()
	title = current_scene as TitleScreen
	_check(title.get_save_state() == &"broken" and not title.get_notice_text().is_empty(), "Broken save warning is missing.")
	_check(FileAccess.file_exists("user://save.broken.json"), "Broken save was not quarantined.")
	await _click(title.get_entry(&"new_game"))
	_check(title.get_confirm().visible, "Broken-save New Game did not ask for confirmation.")
	await _click(title.get_confirm().get_confirm_button())
	await _wait_for_scene(MAIN)
	_check(FileAccess.file_exists("user://save.broken.json"), "Confirmed new game removed the quarantine copy.")
	_check(_opening_starts_at_wake(), "Broken-save recovery did not enter the opening at wake.")

	# Keyboard and gamepad activate the same actual focused Button path.
	root.get_node(^"Session").call("go_to_title")
	await _wait_for_title()
	title = current_scene as TitleScreen
	title.get_entry(&"new_game").grab_focus()
	await _push_key(KEY_ENTER)
	await _wait_for_scene(MAIN)
	_check(_opening_starts_at_wake(), "Keyboard accept did not enter the wake.")
	# Exercise gamepad accept at a title Button; use isolated title after returning.
	root.get_node(^"Session").call("go_to_title")
	await _wait_for_title()
	title = current_scene as TitleScreen
	title.get_entry(&"new_game").grab_focus()
	await _push_pad(JOY_BUTTON_A)
	for _i in 90:
		if title.get_confirm().visible or current_scene != title:
			break
		await process_frame
	_check(title.get_confirm().visible or current_scene != title, "Gamepad A did not activate the focused entry.")

	Harness.clear_session_state(self)
	if failures.is_empty():
		print("PASS: real synthetic mouse clicks hit title Buttons for Start, New Game, Cancel and Confirm; quarantine survives; keyboard/gamepad input reaches the same controls; main.tscn begins at wake.")
	else:
		for failure: String in failures:
			push_error("TEST FAILURE: " + failure)
		print("FAIL: %d title menu interaction assertion(s) failed." % failures.size())
	quit(0 if failures.is_empty() else 1)

func _click(button: Button) -> void:
	if button == null:
		_check(false, "A required Button was not present.")
		return
	await process_frame
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = 0
	root.push_input(motion, true)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = point
	down.global_position = point
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.button_mask = 0
	up.position = point
	up.global_position = point
	root.push_input(up, true)
	await process_frame

func _push_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event)
	await process_frame

func _push_pad(button: JoyButton) -> void:
	# A synthetic pad event belongs to the Input singleton, not a physical device.
	# Parse both halves through the same path so Xvfb does not receive a half-open pad.
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var release := event.duplicate() as InputEventJoypadButton
	release.device = 0
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _open_title() -> void:
	change_scene_to_file(TITLE)
	await _wait_for_title()

func _wait_for_title() -> void:
	for _i in 90:
		await process_frame
		if current_scene is TitleScreen:
			return
	_check(false, "Title scene did not load.")

func _wait_for_scene(path: String) -> void:
	for _i in 240:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			return
	_check(false, "Scene transition did not reach %s." % path)

func _opening_starts_at_wake() -> bool:
	if current_scene == null or current_scene.scene_file_path != MAIN:
		return false
	var director := current_scene.get_node_or_null("OpeningSequence")
	return director != null and director.call("next_step") == &"wake"

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
