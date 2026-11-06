extends Control
class_name InspectionCard
## A small, quiet card that shows what the protagonist saw when inspecting a
## prop. It is not dialogue: no speaker, no choices, no history entries.
##
## The card distinguishes first inspection from repeated inspection, which is how
## the player can tell a thing was already checked (a soft narrative-state test
## with no UI bookkeeping in gameplay scripts).

signal dismissed

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var status_label: Label = %StatusLabel
@onready var frame: PanelContainer = %Frame

var _open: bool = false


func _ready() -> void:
	visible = false
	_open = false


func is_open() -> bool:
	return _open


func show_entry(title: String, text: String, repeated: bool) -> void:
	_open = true
	visible = true
	title_label.text = title
	body_label.text = text
	status_label.text = ("Already in your notes.    E to close" if repeated else "Note added.    E to close")
	status_label.add_theme_color_override(
		"font_color",
		Color(0.58, 0.6, 0.58) if repeated else Color(0.65, 0.76, 0.66)
	)
	frame.modulate = Color(1, 1, 1, 0.94)


func dismiss() -> void:
	if not _open:
		return
	_open = false
	visible = false
	dismissed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("advance") or event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		dismiss()
		get_viewport().set_input_as_handled()
