extends SceneTree
## Optional rendered evidence follows the live camera and the same input path as a player.
## Run with XDG_DATA_HOME isolated: the harness clears its test save and settings.

const Harness = preload("res://tests/test_harness.gd")
const Rules = preload("res://scenes/locations/computer_room/terminal_games.gd")
const View = preload("res://scenes/locations/computer_room/terminal_session.gd")
const Desktop = preload("res://scenes/locations/computer_room/terminal_desktop.gd")
const Board = preload("res://scenes/locations/computer_room/terminal_board.gd")
const ROOM := "res://scenes/locations/computer_room/computer_room.tscn"
const WALK_UP := Vector3(3.49, 0, 0.48)

var _check := Harness.Checker.new()
var _main: Node
var _director: OpeningSequence
var _host: LocationHost
var _player: PlayerController
var _interaction: InteractionController
var _room: LocationRoot
var _state: Node
var _path := ""
var _frames := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 130.0, "computer_room_test.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("capture="):
			_path = arg.trim_prefix("capture=")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "minigame rules"
	_check_mines()
	_check_snake()
	root.size = Vector2i(1600, 900)
	if not _path.is_empty():
		DirAccess.make_dir_recursive_absolute(_path)
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	if await _enter():
		await _try_station()
	if not _path.is_empty():
		_check.expect(_frames == 6, "Expected six rendered steps; saved %s." % _frames)
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	if is_instance_valid(_main):
		_main.queue_free()
	await process_frame
	Harness.finish(self, _check.failures,
		"computer room: seated power gate, boot/input check, both games, input lock, restart and clean exit.")


func _check_mines() -> void:
	var mine := Rules.Minefield.new()
	var first := Vector2i(4, 4)
	mine.reset(25)
	mine.toggle_flag(first)
	mine.reveal(first)
	_check.expect(mine.mines.is_empty() and mine.at(first) == Rules.Minefield.FLAGGED and mine.flags == 1,
		"Opening a flagged square planted mines or opened it.")
	mine.toggle_flag(first)
	mine.reveal(first)
	_check.expect(not mine.lost and mine.opened > 1 and mine.nearby(first) == 0
		and mine.flags == 0 and mine.mines.size() == 10, "First click or flood opening is wrong.")
	var loss: Vector2i = mine.mines[0]
	mine.reveal(loss)
	_check.expect(mine.lost and not mine.won, "Hitting a mine did not end the board.")
	mine.reset(25)
	mine.reveal(first)
	for y in Rules.Minefield.SIDE:
		for x in Rules.Minefield.SIDE:
			var cell := Vector2i(x, y)
			if not mine.mines.has(cell):
				mine.reveal(cell)
	_check.expect(mine.won and not mine.lost and mine.opened == 71, "Clearing every safe cell did not win.")


func _check_snake() -> void:
	var snake := Rules.Snake.new()
	snake.reset(18)
	var head: Vector2i = snake.body[0]
	snake.food = head + Vector2i.RIGHT
	snake.turn(Vector2i.LEFT)
	snake.step()
	_check.expect(snake.body.size() == 4 and snake.score() == 1 and snake.body[0] == head + Vector2i.RIGHT
		and not snake.body.has(snake.food), "Reverse, growth, or food placement is wrong.")
	snake.turn(Vector2i.UP)
	snake.turn(Vector2i.LEFT)
	snake.step()
	_check.expect(snake.direction == Vector2i.UP and not snake.lost, "Turn buffer allowed a double turn.")
	for i in Rules.Snake.SIZE.y:
		snake.step()
	_check.expect(snake.lost, "Running into a wall did not end Snake.")
	snake.reset(19)
	snake.body.assign([Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 2)])
	snake.food = Vector2i(8, 5)
	snake.direction = Vector2i.UP
	snake.turn(Vector2i.RIGHT)
	snake.step()
	_check.expect(not snake.lost and snake.body[0] == Vector2i(3, 2), "Snake could not enter its vacated tail cell.")


func _enter() -> bool:
	Harness.stage = "walk from the corridor spawn"
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_director = _main.get_node(^"OpeningSequence") as OpeningSequence
	_director.autostart = false
	_director.autosave_enabled = false
	root.add_child(_main)
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	_host = _main.get_node(^"LocationHost") as LocationHost
	_player = _main.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_interaction.mouse_targeting = false
	(_main.get_node(^"GameUI") as GameUI).fade.set_clear()
	_director.allow_player_control()
	await process_frame
	if not _check.expect(_host.load_location(ROOM, &"FromCorridor", _player, &"computer_room"),
			"Could not enter the production computer room."):
		return false
	_room = _host.get_current()
	_state.set_flag(StoryFlags.CURRENT_LOCATION, &"computer_room")
	var nav := _room.get_node(^"Navigation") as LocationNavigation
	if not _check.expect(await Harness.wait_until(func() -> bool:
			return nav.is_routable() and _player.is_on_floor(), 8.0), "No walkable map in the lab."):
		return false
	return await _walk(WALK_UP)


func _try_station() -> void:
	Harness.stage = "chair and power gate"
	var seat := _room.find_interactable(&"terminal_seat")
	var power := _room.find_interactable(&"terminal_power")
	var glow := _room.get_node(^"Station1/Right/BootGlow") as OmniLight3D
	var flags: Dictionary = _state.get_snapshot()
	if not _check.expect(seat != null and power != null, "The lab is missing one of its two hotspots."):
		return
	_check.expect(_room.find_interactable(&"computer_room_detail") != null, "The separate CRT inspection was removed.")
	_interaction.request_activation(power)
	_check.expect(not _director.is_beat_active() and not power.can_interact() and not glow.visible,
		"The terminal booted without sitting.")
	if not await _sit(seat, power):
		return
	await _frame("01_seated_power_off")
	_press_action(&"interact")
	var panel := await _wait_panel()
	if panel == null:
		return
	var desktop := panel.desktop
	_check.expect(desktop.page == Desktop.Page.BOOT and glow.visible and _director.is_beat_active()
		and _player.is_seated() and not _player.is_control_enabled() and not _interaction.is_enabled(),
		"World and CRT did not share one held beat at boot.")
	var panel_pos := _player.global_position
	_press_action(&"journal")
	_check.expect(not (_main.get_node(^"PauseMenu") as PauseMenu).is_open(), "The journal opened behind the glass.")
	var logo := desktop.get_node(^"Startup/Logo") as Control
	var input_check := desktop.get_node(^"Startup/InputCheck") as Control
	_check.expect(await Harness.wait_until(func() -> bool: return logo.visible, 4.0), "Boot skipped the logo.")
	await _frame("02_boot_logo")
	_check.expect(await Harness.wait_until(func() -> bool: return input_check.visible, 4.0), "First boot skipped the key check.")
	var keys := desktop.get_node(^"Startup/InputCheck/Keys") as Label
	_check.expect(await Harness.wait_until(func() -> bool: return keys.text.ends_with("[ENT]"), 4.0),
		"The protagonist's input sequence did not complete.")
	await _frame("03_input_check")
	if not _check.expect(await Harness.wait_until(func() -> bool: return desktop.page == Desktop.Page.DESKTOP, 5.0),
			"Boot did not give way to the launcher."):
		return
	await _frame("04_desktop")
	await _play(panel)
	_check.expect(_player.global_position.distance_to(panel_pos) < .02 and not paused and _state.get_snapshot() == flags,
		"Playing moved the world, paused it, or wrote story progress.")
	_press_action(&"pause")
	if not await _restored(panel, glow):
		return
	Harness.stage = "reboot, cancel and depart"
	if not await _sit(seat, power):
		return
	_press_action(&"interact")
	if await _wait_panel() == null:
		return
	_check.expect(desktop.page == Desktop.Page.BOOT, "Reboot resumed an old game.")
	_press_action(&"pause")
	if await _restored(panel, glow) and await _walk(Vector3(3.45, 0, 2.33)):
		var exit := _room.find_interactable(&"computer_room_to_corridor")
		if _check.expect(exit != null and _interaction.is_in_reach(exit), "The corridor exit is no longer reachable."):
			var panel_id := panel.get_instance_id()
			_interaction.request_activation(exit)
			_check.expect(await Harness.wait_until(func() -> bool:
				return not is_instance_id_valid(panel_id) and not _director.is_beat_active() \
					and _host.get_current().location_id == &"corridor" and _host.get_current_spawn() == &"FromComputerRoom",
				12.0), "Leaving did not free the terminal and return to the same hallway threshold.")


func _play(panel: View) -> void:
	Harness.stage = "launch, interact, reset and leave both games"
	var desktop := panel.desktop
	var board := desktop.get_node(^"Game/Board") as Board
	_key(KEY_1)
	await process_frame
	if not _check.expect(desktop.page == Desktop.Page.MINES, "The Minesweeper shortcut did not launch it."):
		return
	if DisplayServer.get_name() == "headless":
		_key(KEY_SPACE)
	else:
		# Aim at the centre cell in the 640×480 desktop. Push events
		# in the fitted screen's actual coordinates, through SubViewportContainer.
		_click(panel, Vector2(188, 232), MOUSE_BUTTON_LEFT)
	_check.expect(await Harness.wait_until(func() -> bool: return board.minefield.opened > 1, 3.0),
		"The board did not accept a safe first reveal.")
	await _frame("05_minesweeper")
	_key(KEY_R)
	_key(KEY_F)
	await process_frame
	_check.expect(board.minefield.opened == 0 and board.minefield.flags == 1, "Restart or keyboard flag did not work.")
	if DisplayServer.get_name() != "headless":
		_click(panel, Vector2(64, 109), MOUSE_BUTTON_RIGHT)
		_check.expect(await Harness.wait_until(func() -> bool: return board.minefield.flags == 2, 3.0),
			"Right-click did not mark the top-left tile.")
	_press_action(&"pause")
	await process_frame
	_check.expect(desktop.page == Desktop.Page.DESKTOP and panel.is_open() and _director.is_beat_active(),
		"Cancel in a game escaped the whole staged beat.")
	_key(KEY_2)
	await process_frame
	if not _check.expect(desktop.page == Desktop.Page.SNAKE, "The Snake shortcut did not launch it."):
		return
	_key(KEY_UP)
	_key(KEY_SPACE)
	_check.expect(await Harness.wait_until(func() -> bool: return board.snake.body[0].y < 6, 3.0),
		"Snake did not move in response to a direction and start.")
	_key(KEY_SPACE)
	await process_frame
	await _frame("06_snake")
	var head: Vector2i = board.snake.body[0]
	await create_timer(0.32).timeout
	_check.expect(board.snake.body[0] == head, "Paused Snake still advanced.")
	_press_action(&"pause")
	await process_frame


func _sit(seat: Interactable, power: Interactable) -> bool:
	if not _check.expect(await Harness.wait_until(func() -> bool: return _interaction.get_current_target() == seat, 4.0),
			"The chair was not offered at %s (target: %s)." % [_player.global_position, _interaction.get_current_target()]):
		return false
	_press_action(&"interact")
	return _check.expect(await Harness.wait_until(func() -> bool:
		return _player.is_seated() and not _director.is_beat_active() and _interaction.get_current_target() == power,
		8.0), "Could not select power at %s: seated=%s enabled=%s beat=%s current=%s visible=%s line=%s." % [
			_player.global_position, _player.is_seated(), power.can_interact(), _director.is_beat_active(),
			_interaction.get_current_target(), _interaction.is_seen_by_camera(power), _interaction.has_line_of_sight(power)])


func _wait_panel() -> View:
	var control := _room.get_node(^"StationControl")
	var opened := await Harness.wait_until(func() -> bool:
		var view := control.get_node_or_null(^"TerminalSession") as View
		return view != null and view.is_open(), 6.0)
	return control.get_node(^"TerminalSession") as View if _check.expect(opened, "Power did not open the CRT.") else null


func _restored(panel: View, glow: OmniLight3D) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		return not panel.is_open() and not glow.visible and not _player.is_seated() and _player.is_control_enabled() \
			and not _director.is_beat_active() and _interaction.is_enabled(),
		5.0), "Closing did not stand the player up and restore world control.")


func _walk(point: Vector3) -> bool:
	return _check.expect(_player.request_path_to(point) and await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.global_position.distance_to(point) < .62, 12.0),
		"Could not walk to %s (at %s)." % [point, _player.global_position])


func _press_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _click(panel: View, pixel: Vector2, button: MouseButton) -> void:
	var display := panel.get_node(^"Shade/Display") as Control
	var pos := display.get_global_transform_with_canvas() * pixel
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.global_position = pos
		event.pressed = pressed
		event.button_index = button
		root.push_input(event, true)


func _frame(title: String) -> void:
	if _path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if _check.expect(image != null and not image.is_empty(), "No rendered image for %s." % title):
		if _check.expect(image.save_jpg(_path.path_join(title + ".jpg"), 0.87) == OK,
				"Could not save frame %s." % title):
			_frames += 1
			if title in ["04_desktop", "05_minesweeper"]:
				image.resize(400, roundi(image.get_height() * 400.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
				image.save_jpg(_path.path_join(title + "_preview.jpg"), 0.62)
