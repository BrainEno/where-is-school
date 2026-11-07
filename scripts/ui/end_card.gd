class_name EndCard
extends Control
## Deliberate stop at the end of the implemented slice.
##
## This is a build marker, not a story event: it names where the milestone ends
## instead of inventing narrative content that the brief defers.

@onready var _title: Label = %EndTitle
@onready var _body: Label = %EndBody
@onready var _hint: Label = %EndHint


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func present(title: String, body: String, hint: String = "") -> void:
	_title.text = title
	_body.text = body
	_hint.text = hint
	_hint.visible = not hint.is_empty()
	show()
	move_to_front()
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.9)
