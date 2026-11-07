class_name CheckOverlay
extends Control
## The frame that shows a *visible* check while it is happening.
##
## A visible check is one the player asked for: they picked an inner voice and
## committed to the attempt. That means the screen owes them four things, and this
## panel shows exactly those and nothing else:
##
## 1. which voice carried the attempt,
## 2. what that voice is worth,
## 3. what the die did against the difficulty,
## 4. what came of it.
##
## Hidden checks never reach this node. A voice that speaks up on its own only
## shows the line its roll produced, so the player feels the result instead of
## reading a number.
##
## All strings come from the locale tables and are rebuilt on a language switch,
## so a check that is on screen when the player presses L keeps its numbers and
## changes its words.

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _verdict: Label = %Verdict

@export var success_color: Color = Color(0.62, 0.78, 0.56, 1.0)
@export var failure_color: Color = Color(0.85, 0.5, 0.42, 1.0)
@export var title_color: Color = Color(0.82, 0.553, 0.349, 1.0)
@export var detail_color: Color = Color(0.72, 0.66, 0.6, 1.0)

## Kept so the panel can redraw itself in the other language.
var _ability_id: StringName = &""
var _result: Dictionary = {}
var _ability_name: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null and loc.has_signal("locale_changed"):
		loc.locale_changed.connect(_on_locale_changed)


func is_showing() -> bool:
	return visible


## Shows the numbers for one resolved check. `ability_name` is the translated name
## of the voice (the caller owns the registry, this node owns no content).
func present(ability_id: StringName, ability_name: String, result: Dictionary) -> void:
	_ability_id = ability_id
	_ability_name = ability_name
	_result = result
	_render()
	show()


func hide_check() -> void:
	hide()
	_result = {}


func get_result() -> Dictionary:
	return _result


func _render() -> void:
	if _result.is_empty():
		return
	_title.text = _ability_name if not _ability_name.is_empty() else String(_ability_id)
	_title.add_theme_color_override("font_color", title_color)
	_detail.text = L10n.t("check.detail", {
		"value": int(_result.get("ability_value", 0)),
		"die": int(_result.get("die", 0)),
		"faces": int(_result.get("die_faces", CheckResolver.DIE_FACES)),
		"modifier": _modifier_text(int(_result.get("modifier", 0))),
		"total": int(_result.get("total", 0)),
		"difficulty": int(_result.get("difficulty", 0)),
	})
	_detail.add_theme_color_override("font_color", detail_color)
	var success := bool(_result.get("success", false))
	_verdict.text = L10n.t("check.success" if success else "check.failure")
	_verdict.add_theme_color_override(
		"font_color", success_color if success else failure_color
	)
	if bool(_result.get("reused", false)):
		# A repeated attempt does not pretend to roll again: it says so.
		_verdict.text = "%s · %s" % [_verdict.text, L10n.t("check.reused")]


func _modifier_text(modifier: int) -> String:
	if modifier == 0:
		return ""
	return " %s %d" % ["+" if modifier > 0 else "−", absi(modifier)]


func _on_locale_changed(_locale: String) -> void:
	if _result.is_empty():
		return
	_render()
