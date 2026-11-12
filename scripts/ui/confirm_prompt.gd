class_name ConfirmPrompt
extends Control
## A yes/no question over whatever is on screen: used before anything is deleted.
##
## The safe answer has the focus when it opens, so a stray Enter, Space or A press keeps the
## progress. Esc, B (`ui_cancel`) and clicking outside the panel all mean "cancel".
##
## It is set like the menus that ask it: the question in the serif on a dark box with the
## ember rule down its left edge, the two answers as page entries.

signal confirmed
signal cancelled

var _factor := 1.0
var _message: Label = null
var _confirm: Button = null
var _cancel: Button = null
var _panel: PanelContainer = null


func _init() -> void:
	name = "ConfirmPrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_factor = UiTextScale.current(self)
	var shade := MenuStyle.backdrop(Color(0.02, 0.025, 0.025, 0.74))
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", MenuStyle.prompt_panel_style())
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	_panel.add_child(column)
	_message = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.PAPER)
	var serif := MenuStyle.serif()
	if serif != null:
		_message.add_theme_font_override(&"font", serif)
	_message.add_theme_constant_override(&"line_spacing", 6)
	column.add_child(_message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	column.add_child(row)
	_cancel = MenuStyle.page_entry("", MenuStyle.ENTRY_SIZE, _factor)
	_cancel.name = "Cancel"
	_cancel.pressed.connect(_answer.bind(false))
	row.add_child(_cancel)
	_confirm = MenuStyle.page_entry("", MenuStyle.ENTRY_SIZE, _factor)
	_confirm.name = "Confirm"
	_confirm.add_theme_color_override(&"font_color", MenuStyle.WARN)
	_confirm.pressed.connect(_answer.bind(true))
	row.add_child(_confirm)
	# The focus stays on the two answers: arrows, the D-pad and Tab move between them and
	# never to whatever menu is behind the question.
	_trap_focus(_cancel, _confirm)
	_trap_focus(_confirm, _cancel)
	get_viewport().size_changed.connect(_fit)


static func _trap_focus(button: Button, other: Button) -> void:
	var own := button.get_path_to(button)
	var to_other := button.get_path_to(other)
	button.focus_neighbor_left = to_other
	button.focus_neighbor_right = to_other
	button.focus_neighbor_top = own
	button.focus_neighbor_bottom = own
	button.focus_next = to_other
	button.focus_previous = to_other


## Shows the question. Focus goes to "cancel".
func ask(message: String, confirm_text: String, cancel_text: String) -> void:
	set_text_scale(UiTextScale.current(self))
	_message.text = message
	_confirm.text = confirm_text
	_cancel.text = cancel_text
	show()
	_fit()
	_cancel.call_deferred("grab_focus")


## The question's text, for the tests and for a language switch.
func get_message() -> String:
	return _message.text if _message != null else ""


func get_confirm_button() -> Button:
	return _confirm


func get_cancel_button() -> Button:
	return _cancel


func get_panel() -> PanelContainer:
	return _panel


func set_text_scale(factor: float) -> void:
	_factor = factor
	UiTextScale.apply(self, factor)
	_fit()


func _fit() -> void:
	if _message == null:
		return
	var view := get_viewport_rect().size
	# A readable measure, never wider than the screen allows.
	var width := minf(view.x - 120.0, 640.0 * maxf(_factor, 1.0))
	_message.custom_minimum_size = Vector2(maxf(width - 68.0, 200.0), 0.0)


func _answer(yes: bool) -> void:
	if not visible:
		return
	hide()
	if yes:
		confirmed.emit()
	else:
		cancelled.emit()


func _on_shade_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_answer(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)
		return
	# Nothing behind the question may react while it is up.
	if event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
