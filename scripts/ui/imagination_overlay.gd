class_name ImaginationOverlay
extends Control
## Visual frame that marks a subjective beat as *not part of the world*.
##
## The tint, the label, and the slowed fade exist so the player can never mistake
## an anticipated confrontation for something that happened in the room.

@onready var _tint: ColorRect = %Tint
@onready var _banner: Label = %Banner
@onready var _flavour: Label = %Flavour

@export var tint_color: Color = Color(0.298, 0.169, 0.129, 0.55)
@export var fade_time: float = 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	_tint.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.0)
	_banner.modulate = Color(1, 1, 1, 0)
	_flavour.modulate = Color(1, 1, 1, 0)


func show_overlay(banner_text: String, flavour_text: String = "") -> void:
	_banner.text = banner_text
	_flavour.text = flavour_text
	_flavour.visible = not flavour_text.is_empty()
	show()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_tint, "color:a", tint_color.a, fade_time)
	tween.tween_property(_banner, "modulate:a", 1.0, fade_time)
	tween.tween_property(_flavour, "modulate:a", 1.0, fade_time)


func hide_overlay() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_tint, "color:a", 0.0, fade_time)
	tween.tween_property(_banner, "modulate:a", 0.0, fade_time)
	tween.tween_property(_flavour, "modulate:a", 0.0, fade_time)
	await tween.finished
	hide()
