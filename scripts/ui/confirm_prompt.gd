class_name ConfirmPrompt
extends Control
## A yes/no question over whatever is on screen: used before anything is deleted.
##
## The safe answer has the focus when it opens, so a stray Enter, Space or A press keeps the
## progress. Esc, B (`ui_cancel`) and clicking outside the card all mean "cancel".
##
## It is a page laid over the menu that asks it, not an alert: a short heading in the serif
## with a brush of ember under it, the question set as reading text, and the two answers -
## **Cancel** and **Confirm** - as page entries on the right, on a dark sheet whose sides
## are cut by hand like the pause menu's. No coloured frame and no warning colour: what the
## answer costs is said in the sentence.
##
## The answers never wrap. A Button that may wrap reports almost no minimum width, and in
## a row that does not stretch it it was laid out narrower than one character, which is
## how the first version of this card showed two empty answers.

signal confirmed
signal cancelled


## The sheet behind the card and the brush under the heading. Drawn here rather than as a
## StyleBox because the edges are hand-cut (`MenuStyle.draw_rough_slab`).
class Card:
	extends Control

	var panel: Control = null
	var heading: Control = null

	func _init() -> void:
		name = "Card"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if panel == null or not panel.is_visible_in_tree():
			return
		var box := Rect2(panel.global_position - global_position, panel.size)
		MenuStyle.draw_rough_slab(
			self, Rect2(box.position + Vector2(10.0, 8.0), box.size),
			Color(MenuStyle.OCHRE, 0.14), 29, 9.0
		)
		MenuStyle.draw_rough_slab(self, box, Color(0.04, 0.047, 0.048, 0.98), 23, 7.0)
		if heading != null and heading.visible:
			var under := Rect2(heading.global_position - global_position, heading.size)
			var y := under.end.y + 8.0
			MenuStyle.draw_dry_brush(
				self, Vector2(under.position.x, y), Vector2(under.position.x + 72.0, y + 1.0),
				MenuStyle.EMBER, 41, 4.0
			)


var _factor := 1.0
var _heading: Label = null
var _message: Label = null
var _confirm: Button = null
var _cancel: Button = null
var _panel: PanelContainer = null
var _card: Card = null


func _init() -> void:
	name = "ConfirmPrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	theme = MenuStyle.page_theme()
	_factor = UiTextScale.current(self)
	var shade := MenuStyle.backdrop(Color(MenuStyle.INK, 0.62))
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)
	_card = Card.new()
	add_child(_card)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", MenuStyle.prompt_content_style())
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	_panel.add_child(column)
	_heading = MenuStyle.serif_label("", MenuStyle.ENTRY_SIZE, _factor, MenuStyle.PAPER, 0.5, 2)
	_heading.name = "Heading"
	column.add_child(_heading)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	column.add_child(gap)
	_message = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.PAGE_TEXT)
	_message.name = "Message"
	_message.add_theme_constant_override(&"line_spacing", 6)
	column.add_child(_message)
	var row := HBoxContainer.new()
	row.name = "Answers"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_cancel = _answer_button("Cancel")
	_cancel.pressed.connect(_answer.bind(false))
	row.add_child(_cancel)
	_confirm = _answer_button("Confirm")
	_confirm.pressed.connect(_answer.bind(true))
	row.add_child(_confirm)
	_card.panel = _panel
	_card.heading = _heading
	_panel.item_rect_changed.connect(_card.queue_redraw)
	# The focus stays on the two answers: arrows, the D-pad and Tab move between them and
	# never to whatever menu is behind the question.
	_trap_focus(_cancel, _confirm)
	_trap_focus(_confirm, _cancel)
	get_viewport().size_changed.connect(_fit)


func _answer_button(id: String) -> Button:
	var button := MenuStyle.page_entry("", MenuStyle.ENTRY_SIZE, _factor)
	button.name = id
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	return button


static func _trap_focus(button: Button, other: Button) -> void:
	var own := button.get_path_to(button)
	var to_other := button.get_path_to(other)
	button.focus_neighbor_left = to_other
	button.focus_neighbor_right = to_other
	button.focus_neighbor_top = own
	button.focus_neighbor_bottom = own
	button.focus_next = to_other
	button.focus_previous = to_other


## Shows the question. Focus goes to "cancel". `heading` is the short title above it
## ("New game"); without one the card starts with the question.
func ask(message: String, confirm_text: String, cancel_text: String, heading: String = "") -> void:
	set_text_scale(UiTextScale.current(self))
	_heading.text = heading
	_heading.visible = not heading.is_empty()
	_message.text = message
	_confirm.text = confirm_text
	_cancel.text = cancel_text
	show()
	_fit()
	_cancel.call_deferred("grab_focus")


## The question's text, for the tests and for a language switch.
func get_message() -> String:
	return _message.text if _message != null else ""


func get_heading() -> String:
	return _heading.text if _heading != null and _heading.visible else ""


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
	var width := minf(view.x - 120.0, 600.0 * maxf(_factor, 1.0))
	_message.custom_minimum_size = Vector2(maxf(width - 92.0, 200.0), 0.0)
	if _card != null:
		_card.queue_redraw()


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
