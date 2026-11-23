extends RefCounted
## How much of the screen the story editor may use: the safe area, less the phone's own
## keyboard when it is up.
##
## Kept out of `author_overlay.gd` because it is the one piece of the drawer's layout that
## is about the operating system rather than the editor, and because both the launcher and
## the drawer ask the same question. The arithmetic is the same as Godot's own pixel-to-
## canvas transform: the keyboard reports pixels, the scene is in canvas units, and the
## screen's scale is what turns one into the other.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

## How much room the keyboard takes under the editor, in the editor's own units, or 0.
static func height() -> int:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0
	return DisplayServer.virtual_keyboard_get_height()


## The rectangle the editor may place its launcher, drawer and preview in. `open` says the
## drawer owns the screen, so the keyboard only shrinks the area then; a closed editor never
## pays for a keyboard it is not using.
static func usable_rect(anchor: Control, open: bool) -> Rect2:
	var area := MobileLayout.safe_rect(anchor).grow(-MobileLayout.EDGE)
	if not open or not MobileLayout.enabled:
		return area
	var pixels := height()
	if pixels <= 0:
		return area
	var scale_y := maxf(anchor.get_window().get_screen_transform().get_scale().y, 0.01)
	var bottom := anchor.get_viewport_rect().end.y - float(pixels) / scale_y
	area.size.y = maxf(70.0, minf(area.end.y, bottom) - area.position.y)
	return area
