class_name FadeLayer
extends ColorRect
## Full-screen fade used for waking up, scene transitions, and the beat that
## ends this build. Presentation only.

@export var default_duration: float = 0.8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 0.0)
	visible = false


func fade_from_black(duration: float = -1.0) -> void:
	var use_duration := duration if duration >= 0.0 else default_duration
	visible = true
	color = Color(0.043, 0.051, 0.051, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "color:a", 0.0, use_duration)
	await tween.finished
	visible = false


func fade_to_black(duration: float = -1.0) -> void:
	var use_duration := duration if duration >= 0.0 else default_duration
	visible = true
	color = Color(0.043, 0.051, 0.051, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "color:a", 1.0, use_duration)
	await tween.finished


func set_opaque() -> void:
	visible = true
	color = Color(0.043, 0.051, 0.051, 1.0)


func set_clear() -> void:
	color = Color(0.043, 0.051, 0.051, 0.0)
	visible = false
