class_name GameHud
extends Control
## Non-dialogue HUD: the current objective line, the contextual interaction
## prompt, and the language switch hint. Thin views over state the sequence
## director owns; every string it shows is resolved through L10n at draw time so
## a language switch only has to ask for a redraw.

@onready var _objective_label: Label = %ObjectiveLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _language_label: Label = %LanguageLabel

var _objective_tween: Tween = null
## Locale key of the current objective, so it can be re-translated in place.
var _objective_key: String = ""


func _ready() -> void:
	_prompt_label.hide()
	_prompt_label.text = ""
	refresh_language_text()
	var loc := _loc()
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)


func _loc() -> Node:
	return get_node_or_null(^"/root/Loc")


func _on_locale_changed(_locale: String) -> void:
	refresh_language_text()
	set_objective(_objective_key)


## Shows the objective by locale key. Empty clears the line.
func set_objective(objective_key: String) -> void:
	_objective_key = objective_key.strip_edges()
	var text := L10n.objective_text(_objective_key)
	_objective_label.text = text
	_objective_label.visible = not text.is_empty()
	if not _objective_label.visible:
		return
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_label.modulate = Color(1, 1, 1, 0.25)
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_label, "modulate", Color(1, 1, 1, 1), 0.5)


func get_objective_key() -> String:
	return _objective_key


## The prompt text is already localized by the dialogue controller.
func set_prompt_text(action: String) -> void:
	if action.strip_edges().is_empty():
		clear_prompt()
		return
	_prompt_label.text = "[%s] %s" % [_interact_key_label(), action]
	_prompt_label.show()


func get_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


func get_objective_text() -> String:
	return _objective_label.text if _objective_label != null else ""


func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_label.hide()


func refresh_language_text() -> void:
	if _language_label == null:
		return
	_language_label.text = L10n.t("ui.language_switch", {"name": L10n.locale_name(L10n.other_locale())})


## Reads the actual interact binding so the hint cannot drift from the input map.
func _interact_key_label() -> String:
	for event: InputEvent in InputMap.action_get_events("interact"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode != 0:
			return OS.get_keycode_string(key_event.physical_keycode)
	return "E"
