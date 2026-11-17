class_name DialogueModeBar
extends Control
## The two words at the start of the dialogue band's hint line that switch auto and skip.
##
## A keyboard or controller player has the `dialogue_auto` / `dialogue_skip` inputs and the
## hint names them; a player who only uses the mouse needs something to click, and this is
## it: "Auto" and "Skip", set in the hint's own small size, lit in the options' apricot while
## that mode is on and muted otherwise.
##
## It is a child of the hint label, not a row of its own, on purpose: the band's layout is
## measured and tested node by node (`tests/dialogue_layout_test.gd`), and a new row would
## make every band taller. The hint is right-aligned, so the start of its line is normally
## empty; the bar takes that space and hides itself when the hint's own text needs it
## (`fit_into`), so it never draws over a word. Hiding it loses nothing a key cannot do.

signal auto_pressed
signal skip_pressed

const GAP := 18.0
const SPACING := 12.0

const MUTED := Color(0.37, 0.35, 0.38, 1.0)
const LIT := Color(0.30, 0.15, 0.12, 1.0)
const HOVER := Color(0.52, 0.24, 0.16, 1.0)

var _auto: Button = null
var _skip: Button = null
var _font: Font = null
var _font_size := 13
var _auto_on := false
var _skip_on := false


func _init() -> void:
	name = "ModeBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto = _make_button("Auto")
	_skip = _make_button("Skip")
	_auto.pressed.connect(func() -> void: auto_pressed.emit())
	_skip.pressed.connect(func() -> void: skip_pressed.emit())


## The type the hint is set in, so the bar reads as part of the same line.
func set_type(font: Font, font_size: int) -> void:
	_font = font
	_font_size = maxi(font_size, 1)
	for button: Button in [_auto, _skip]:
		if font != null:
			button.add_theme_font_override(&"font", font)
		button.add_theme_font_size_override(&"font_size", _font_size)


func set_labels(auto_text: String, skip_text: String) -> void:
	_auto.text = auto_text
	_skip.text = skip_text


## Lights the word of the mode that is on.
func set_state(auto_on: bool, skip_on: bool) -> void:
	_auto_on = auto_on
	_skip_on = skip_on
	_color(_auto, auto_on)
	_color(_skip, skip_on)


func get_auto_button() -> Button:
	return _auto


func get_skip_button() -> Button:
	return _skip


## Width the two words need, in pixels.
func needed_width() -> float:
	return _button_size(_auto).x + SPACING + _button_size(_skip).x


## Places the bar at the start of `area` (the hint label's rect, in the label's own space)
## and shows it only if it leaves `text_width` pixels of the area, plus a gap, to the hint.
## Returns whether it is shown.
func fit_into(area: Vector2, text_width: float) -> bool:
	var width := needed_width()
	var height := maxf(_button_size(_auto).y, _button_size(_skip).y)
	# The words may not be taller than the line they sit on, or they would hang below it.
	var fits := area.x > 0.0 and width + GAP + text_width <= area.x and height <= area.y + 0.5
	visible = fits
	if not fits:
		return false
	position = Vector2.ZERO
	size = Vector2(width, area.y)
	var x := 0.0
	for button: Button in [_auto, _skip]:
		var word := _button_size(button)
		button.position = Vector2(x, (area.y - word.y) * 0.5)
		button.size = word
		x += word.x + SPACING
	return true


## What a word needs: never smaller than the button's own minimum, so nothing is clipped.
func _button_size(button: Button) -> Vector2:
	var minimum := button.get_combined_minimum_size()
	var width := minimum.x
	if _font != null:
		width = maxf(width, ceilf(
			_font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x
		))
	return Vector2(ceilf(width), ceilf(minimum.y))


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_constant_override(&"outline_size", 0)
	_color(button, false)
	add_child(button)
	return button


func _color(button: Button, lit: bool) -> void:
	var rest := LIT if lit else MUTED
	button.add_theme_color_override(&"font_color", rest)
	button.add_theme_color_override(&"font_pressed_color", LIT)
	button.add_theme_color_override(&"font_hover_color", LIT if lit else HOVER)
	button.add_theme_color_override(&"font_hover_pressed_color", LIT)
	button.add_theme_color_override(&"font_focus_color", rest)
