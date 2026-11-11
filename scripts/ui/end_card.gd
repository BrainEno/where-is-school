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


## Text currently on the card, for the language switch and for tests.
func get_title() -> String:
	return _title.text if _title != null else ""


func get_body() -> String:
	return _body.text if _body != null else ""


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


## Fades the card out and hides it. The end of the slice leaves its card up on purpose;
## a card that is only reporting something - a save that could not be read - has to be
## able to leave again without the player doing anything.
func dismiss(duration: float = 0.6) -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	await tween.finished
	hide()
