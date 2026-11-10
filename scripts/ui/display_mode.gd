extends Node
## The window: how big it opens, where it sits, and what F11 does.
##
## Three jobs, all of them about the frame around the game rather than the game:
##
## - **Open at the design size, centred, and never off-screen.** The design viewport is
##   1600x900. The window opens at that size on a screen that can hold it, and is fitted and
##   centred on one that cannot (a 1366x768 laptop, a scaled 4K display, a remote session).
## - **A minimum size the layout actually survives.** 1280x720 is the smallest size the HUD,
##   the dialogue panel and the choice list are checked at in CI, so it is the smallest size
##   the window may be dragged to.
## - **F11 toggles fullscreen, and leaving it puts the window back where it was.** The size
##   and position are remembered on the way in, restored on the way out, and clamped to the
##   screen on the way back in case the display changed while the game was fullscreen. Two
##   toggles in a row — or a toggle while the window is already being resized — cannot leave
##   the window in a state with no size and no position.
##
## Nothing here touches the world: no scene is reloaded, no autoload is reset, the player is
## not moved and the dialogue is not interrupted. Switching display mode is a property of the
## window, and the state that matters is inside the game's own nodes.
##
## `DisplayServer` is only called when there is a real window; under `--headless` (every CI
## test) the state machine still runs, so the logic that could lose the window is testable
## without a display.

## The smallest window the layout is verified at (tests/ui_resolution_test.gd runs here).
const MIN_WINDOW_SIZE := Vector2i(1280, 720)
## The design size, and the size the window opens at when the screen can hold it.
const DESIGN_WINDOW_SIZE := Vector2i(1600, 900)
## Ignore a second toggle this soon after the first. A held key repeats, and a mode change
## costs a frame; without this, key repeat can bounce in and out of fullscreen.
const TOGGLE_GUARD_MSEC := 150

var _windowed_size := Vector2i.ZERO
var _windowed_position := Vector2i.ZERO
var _fullscreen := false
var _last_toggle_msec := -1000000
var _applied_min_size := false


func _ready() -> void:
	# The window is the game's, not the scene's: it has to survive a location swap and it
	# must not be reset when one happens, so this node lives in main.tscn and never reloads.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_at_the_design_size()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if not key.is_action_pressed(&"toggle_fullscreen"):
		return
	get_viewport().set_input_as_handled()
	toggle_fullscreen()


## The window state this node believes in: `true` after a toggle into fullscreen.
func is_fullscreen() -> bool:
	return _fullscreen


## The size and position the window will be put back to when fullscreen ends. Empty before
## the first toggle, which is the state a first toggle has to survive.
func get_windowed_rect() -> Rect2i:
	return Rect2i(_windowed_position, _windowed_size)


## Switches between fullscreen and windowed, remembers where the window was, and puts it
## back. Safe to call when the display is headless, and safe to call twice.
func toggle_fullscreen() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_toggle_msec < TOGGLE_GUARD_MSEC:
		return false
	_last_toggle_msec = now
	if _headless():
		# No display to change: keep the state machine honest anyway, so the tests can
		# exercise the remembering and restoring without a window. The remembered rectangle
		# is the one a real window would have had, never an empty one: leaving fullscreen
		# with nothing remembered is exactly the state that loses the window.
		_fullscreen = not _fullscreen
		if _windowed_size == Vector2i.ZERO:
			_windowed_size = DESIGN_WINDOW_SIZE
			_windowed_position = centred_rect(DESIGN_WINDOW_SIZE).position
		return true
	var window := get_window()
	if window == null:
		return false
	# Trust the display over our own flag: the user may have used the OS shortcut, and a
	# stale flag is how a "leave fullscreen" ends up doing nothing.
	var mode := DisplayServer.window_get_mode()
	var actually_fullscreen := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	if actually_fullscreen or _fullscreen:
		_leave_fullscreen(window)
	else:
		_enter_fullscreen(window)
	return true


## Whether the window is currently in a fullscreen mode, asked of the display.
func is_window_fullscreen() -> bool:
	if _headless():
		return _fullscreen
	var mode := DisplayServer.window_get_mode()
	return (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


## Where the window would be centred at `size` on the screen it is currently on, clamped so
## the whole frame is inside the usable area. Public because the tests check it.
func centred_rect(size: Vector2i, screen: int = -1) -> Rect2i:
	var usable := _usable_rect(screen)
	var clamped_size := Vector2i(
		mini(size.x, usable.size.x), mini(size.y, usable.size.y)
	)
	return Rect2i(
		Vector2i(
			usable.position.x + maxi((usable.size.x - clamped_size.x) / 2, 0),
			usable.position.y + maxi((usable.size.y - clamped_size.y) / 2, 0)
		),
		clamped_size
	)


func _open_at_the_design_size() -> void:
	var window := get_window()
	if window == null or _headless():
		return
	if not _applied_min_size:
		window.min_size = MIN_WINDOW_SIZE
		_applied_min_size = true
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var rect := centred_rect(DESIGN_WINDOW_SIZE)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)
	_windowed_size = rect.size
	_windowed_position = rect.position
	_fullscreen = false


func _enter_fullscreen(window: Window) -> void:
	# Remember the windowed frame before the mode changes: afterwards the display reports
	# the fullscreen size, and that is not where the player wants to go back to.
	var size := DisplayServer.window_get_size()
	var position := DisplayServer.window_get_position()
	if size.x >= MIN_WINDOW_SIZE.x and size.y >= MIN_WINDOW_SIZE.y:
		_windowed_size = size
		_windowed_position = position
	elif _windowed_size == Vector2i.ZERO:
		_windowed_size = DESIGN_WINDOW_SIZE
		_windowed_position = centred_rect(DESIGN_WINDOW_SIZE).position
	_fullscreen = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _leave_fullscreen(window: Window) -> void:
	_fullscreen = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Restore, then clamp: the screen may have changed while the game was fullscreen (a
	# different monitor, a resolution change, a scaled display), and a remembered position
	# off the current screen is a window the player cannot reach.
	var size := _windowed_size
	if size.x < MIN_WINDOW_SIZE.x or size.y < MIN_WINDOW_SIZE.y:
		size = DESIGN_WINDOW_SIZE
	var usable := _usable_rect(-1)
	var clamped_size := Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
	var position := _windowed_position
	if position == Vector2i.ZERO:
		position = centred_rect(clamped_size).position
	position.x = clampi(
		position.x, usable.position.x, usable.position.x + maxi(usable.size.x - clamped_size.x, 0)
	)
	position.y = clampi(
		position.y, usable.position.y, usable.position.y + maxi(usable.size.y - clamped_size.y, 0)
	)
	DisplayServer.window_set_size(clamped_size)
	DisplayServer.window_set_position(position)
	_windowed_size = clamped_size
	_windowed_position = position


func _usable_rect(screen: int) -> Rect2i:
	if _headless():
		return Rect2i(Vector2i.ZERO, DESIGN_WINDOW_SIZE)
	var index := screen
	if index < 0:
		index = DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(index)
	if usable.size.x <= 0 or usable.size.y <= 0:
		# A display that reports nothing usable (some remote sessions) is not a reason to
		# compute a window at zero size.
		usable = Rect2i(Vector2i.ZERO, DESIGN_WINDOW_SIZE)
	return usable


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"
