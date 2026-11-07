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

## Locale keys behind the current text, so a language switch can re-translate a
## banner that is already on screen.
var _banner_key: String = ""
var _flavour_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	_tint.color = Color(tint_color.r, tint_color.g, tint_color.b, 0.0)
	_banner.modulate = Color(1, 1, 1, 0)
	_flavour.modulate = Color(1, 1, 1, 0)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_locale: String) -> void:
	refresh_language()


## Localized entry point used by the sequence director.
func show_localized_overlay(banner_key: String, flavour_key: String = "") -> void:
	_banner_key = banner_key
	_flavour_key = flavour_key
	show_overlay(
		L10n.t(banner_key), L10n.t(flavour_key) if not flavour_key.is_empty() else ""
	)


## Re-translates the banner in place; a literal banner (no key) is left alone.
func refresh_language() -> void:
	if _banner_key.is_empty():
		return
	_banner.text = L10n.t(_banner_key)
	_flavour.text = L10n.t(_flavour_key) if not _flavour_key.is_empty() else ""
	_flavour.visible = not _flavour.text.is_empty()


func show_overlay(banner_text: String, flavour_text: String = "") -> void:
	_banner_key = ""
	_flavour_key = ""
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
