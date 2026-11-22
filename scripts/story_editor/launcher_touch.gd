extends RefCounted
## Whose finger the story editor's launcher owns, kept out of the overlay so the rule and
## its two pieces of state read in one place.
##
## Godot can send the emulated mouse pair ahead of the native screen pair, so the launcher
## lets only the native release activate: a touch that starts on the button and is cancelled
## or dragged off never opens the editor. The same rule is what makes the launcher usable
## with a finger while the world's own touch controls ignore it.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

## The touch currently on the launcher, or -1.
var _touch := -1
## Whether the emulated mouse press began on the launcher.
var _mouse := false


## True when this event belongs to the launcher and must not reach the world. `entry` is the
## button, `open` asks the host to show the editor (the release on it is the click).
func handle(event: InputEvent, entry: Control, open: Callable) -> bool:
	if entry == null or not entry.visible:
		return false
	if event is InputEventMouse:
		if MobileLayout.is_emulated_mouse(event):
			return _emulated_mouse(event as InputEventMouse, entry)
		return false
	if event is InputEventScreenTouch:
		return _screen_touch(event as InputEventScreenTouch, entry, open)
	return event is InputEventScreenDrag and event.index == _touch


## Drops a finger that a pause or a lost focus interrupted; the next touch starts clean.
func forget() -> void:
	_touch = -1
	_mouse = false


func _emulated_mouse(event: InputEventMouse, entry: Control) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var owned := _hit(entry, event.position) if event.pressed else _mouse
		_mouse = owned and event.pressed
		return owned
	return _mouse and event is InputEventMouseMotion


func _screen_touch(event: InputEventScreenTouch, entry: Control, open: Callable) -> bool:
	if event.pressed and _hit(entry, event.position):
		if _touch < 0:
			_touch = event.index
		return true
	if not event.pressed and event.index == _touch:
		_touch = -1
		if not event.canceled and _hit(entry, event.position):
			open.call_deferred()
		return true
	return false


static func _hit(entry: Control, point: Vector2) -> bool:
	return entry.get_global_rect().has_point(point)
