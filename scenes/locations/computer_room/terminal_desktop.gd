extends Control
## An original school desktop. Boot/POST/input rehearsal only play while powered;
## game state and the first-boot performance do not enter the narrative save.

const Rules = preload("res://scenes/locations/computer_room/terminal_games.gd")
const Board = preload("res://scenes/locations/computer_room/terminal_board.gd")
const SNAKE_TICK := 0.16
const BOOT_SECONDS := 2.15
const CHECK_SECONDS := 4.45
const CHECK_KEYS := ["[   ]    [   ]    [   ]", "[ → ]    [   ]    [   ]", "[ → ]    [ ↓ ]    [   ]", "[ → ]    [ ↓ ]    [ ↵ ]"]
const ARROWS := [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]
const MOVE_ACTIONS := [&"move_forward", &"move_left", &"move_back", &"move_right"]

enum Page { OFF, BOOT, DESKTOP, MINES, SNAKE }
var page := Page.OFF

signal shutdown_requested
signal boot_finished

@onready var _startup: Control = $Startup
@onready var _beam: ColorRect = $Startup/Beam
@onready var _post: Label = $Startup/Post
@onready var _logo: Control = $Startup/Logo
@onready var _check: Panel = $Startup/InputCheck
@onready var _check_keys: Label = $Startup/InputCheck/Keys
@onready var _progress: ProgressBar = $Startup/Progress
@onready var _desktop: Control = $DesktopLauncher
@onready var _game: Control = $Game
@onready var _board: Board = $Game/Board
@onready var _status: Label = $Game/Status
@onready var _mode: Button = $Game/Mode
@onready var _snake_controls: Control = $Game/Pad
@onready var _hint: Label = $Game/Hint
@onready var _launch: Array[Button] = [$DesktopLauncher/Mines, $DesktopLauncher/Snake]

var _time := 0.0
var _first := false
var _launch_index := 0
var _snake_running := false
var _ticks := 0.0


func _ready() -> void:
	_launch[0].pressed.connect(_start_mines)
	_launch[1].pressed.connect(_start_snake)
	$BottomBar/Power.pressed.connect(func() -> void: shutdown_requested.emit())
	$Game/Close.pressed.connect(back)
	$Game/Restart.pressed.connect(_restart)
	_mode.pressed.connect(_mode_pressed)
	for i in ARROWS.size():
		var button := _snake_controls.get_child(i) as Button
		button.pressed.connect(_move.bind(ARROWS[i]))
	_board.action_taken.connect(_refresh_status)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.locale_changed.connect(_localize)
	stop()
	_localize("")


func boot(first: bool) -> void:
	_first = first
	_time = 0.0
	$Wallpaper.show()
	_startup.show()
	$BottomBar.show()
	_desktop.hide()
	_game.hide()
	page = Page.BOOT
	_render_boot()
	set_process(true)


func stop() -> void:
	page = Page.OFF
	set_process(false)
	$Wallpaper.hide()
	_startup.hide()
	$BottomBar.hide()
	_desktop.hide()
	_game.hide()


func _process(delta: float) -> void:
	if page == Page.BOOT:
		_time += delta
		if _time >= (CHECK_SECONDS if _first else BOOT_SECONDS):
			_show_desktop()
			boot_finished.emit()
		else:
			_render_boot()
	elif page == Page.SNAKE and _snake_running:
		_ticks += delta
		if _ticks >= SNAKE_TICK:
			_ticks = fmod(_ticks, SNAKE_TICK)
			_board.snake.step()
			if _board.snake.won or _board.snake.lost:
				_snake_running = false
			_board.redraw()
			_refresh_status()


func _render_boot() -> void:
	_beam.visible = _time < 0.44
	_beam.scale = Vector2(smoothstep(0.08, 0.33, _time), 1.0)
	_post.visible = _time >= 0.35 and _time < 1.12
	var count := 1 + int(_time >= 0.66) + int(_time >= 0.90)
	var lines := PackedStringArray(["RAM     32768K", "CRT     640×480", "I/O     OK"])
	_post.text = "\n".join(lines.slice(0, count))
	_logo.visible = _time >= 1.12 and _time < BOOT_SECONDS
	_progress.visible = _logo.visible
	_progress.value = clampf((_time - 1.12) / (BOOT_SECONDS - 1.12), 0.0, 1.0)
	_check.visible = _first and _time >= BOOT_SECONDS
	# First operation hesitates; the next two land in quick succession. This is the
	# protagonist's input in the staged beat, not a game played for the player.
	var key_index := int(_time >= 3.43) + int(_time >= 3.63) + int(_time >= 3.78)
	_check_keys.text = CHECK_KEYS[key_index]
	$Startup/InputCheck/State.text = L10n.t("terminal.ready" if key_index == 3 else "terminal.keyboard")


func _show_desktop() -> void:
	page = Page.DESKTOP
	set_process(false)
	_startup.hide()
	_game.hide()
	_desktop.show()
	_launch[_launch_index].grab_focus()


func back() -> void:
	if page == Page.MINES or page == Page.SNAKE:
		_show_desktop()
	elif page != Page.OFF:
		shutdown_requested.emit()


func _start_mines() -> void:
	_launch_index = 0
	page = Page.MINES
	_restart()


func _start_snake() -> void:
	_launch_index = 1
	page = Page.SNAKE
	_restart()


func _restart() -> void:
	_board.mines_active = page == Page.MINES
	if _board.mines_active:
		_board.minefield.reset()
		_board.selected = Vector2i(4, 4)
		_board.flag_mode = false
	else:
		_board.snake.reset()
	_desktop.hide()
	_game.show()
	_snake_controls.visible = page == Page.SNAKE
	_snake_running = false
	_ticks = 0.0
	_board.redraw()
	set_process(false)
	_refresh_status()


func _mode_pressed() -> void:
	if page == Page.MINES:
		_board.flag_mode = not _board.flag_mode
	elif page == Page.SNAKE:
		if _board.snake.lost or _board.snake.won:
			return
		_snake_running = not _snake_running
		set_process(_snake_running)
	_refresh_status()


func _move(direction: Vector2i) -> void:
	if page == Page.DESKTOP:
		_launch_index = 1 - _launch_index
		_launch[_launch_index].grab_focus()
	elif page == Page.MINES:
		_board.move_cursor(direction)
	elif page == Page.SNAKE and not _board.snake.lost and not _board.snake.won:
		_board.snake.turn(direction)


func handle_event(event: InputEvent) -> bool:
	if page == Page.OFF or page == Page.BOOT:
		return false
	for i in MOVE_ACTIONS.size():
		if event.is_action_pressed(MOVE_ACTIONS[i], page == Page.MINES):
			_move(ARROWS[i])
			return true
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return false
		match event.physical_keycode:
			KEY_1, KEY_2:
				if page == Page.DESKTOP:
					_launch_index = int(event.physical_keycode == KEY_2)
					_accept()
					return true
			KEY_R:
				if page != Page.DESKTOP:
					_restart()
					return true
			KEY_F:
				if page == Page.MINES:
					_board.act_on_selected(true)
					return true
			KEY_SPACE, KEY_ENTER:
				_accept()
				return true
	elif event.is_action_pressed(&"interact") and not event is InputEventMouseButton:
		_accept()
		return true
	elif event.is_action_pressed(&"backlog") and page != Page.DESKTOP:
		if page == Page.MINES:
			_board.act_on_selected(true)
		else:
			_restart()
		return true
	return false


func _accept() -> void:
	match page:
		Page.DESKTOP:
			if _launch_index == 0:
				_start_mines()
			else:
				_start_snake()
		Page.MINES:
			_board.act_on_selected(_board.flag_mode)
		Page.SNAKE:
			_mode_pressed()


func _localize(_locale: String) -> void:
	$DesktopLauncher/Label.text = L10n.t("terminal.games")
	_launch[0].text = L10n.t("terminal.mines")
	_launch[1].text = L10n.t("terminal.snake")
	$Game/Restart.text = L10n.t("terminal.restart")
	$BottomBar/Power.text = L10n.t("terminal.shutdown")
	$BottomBar/Label.text = L10n.t("terminal.station")
	$Startup/InputCheck/Heading.text = L10n.t("terminal.input_check")
	_refresh_status()


func _refresh_status() -> void:
	if page != Page.MINES and page != Page.SNAKE:
		return
	var mines := page == Page.MINES
	$Game/Heading.text = L10n.t("terminal.mines" if mines else "terminal.snake")
	var won := _board.minefield.won if mines else _board.snake.won
	var lost := _board.minefield.lost if mines else _board.snake.lost
	var ended := won or lost
	$Game/Result.text = L10n.t("terminal.won" if won else "terminal.lost") if ended else ""
	$Game/Result.add_theme_color_override("font_color", Color("245a44") if won else Color("8e2e4e"))
	if mines:
		_status.text = L10n.t("terminal.remaining", {"count": Rules.Minefield.MINE_COUNT - _board.minefield.flags})
		_mode.text = L10n.t("terminal.marking" if _board.flag_mode else "terminal.revealing")
		_hint.text = L10n.t("terminal.mines_hint")
	else:
		_status.text = L10n.t("terminal.score", {"count": _board.snake.score()})
		_mode.text = L10n.t("terminal.pause" if _snake_running else "terminal.play")
		_hint.text = L10n.t("terminal.snake_hint")
	_mode.disabled = ended
