class_name GameHud
extends Control
## Non-dialogue HUD: the current objective line, the contextual interaction
## prompt, and the language switch hint. Thin views over state the sequence
## director owns; every string it shows is resolved through L10n at draw time so
## a language switch only has to ask for a redraw.

@onready var _objective_label: Label = $ObjectiveLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _language_label: Label = $LanguageLabel

var _objective_tween: Tween = null
var _prompt_tween: Tween = null
## True while the dialogue panel is on screen. The panel carries its own key
## hints at the bottom right, so the HUD's language hint steps aside to keep the
## two from printing on top of each other.
var _dialogue_open: bool = false
## Locale key of the current objective, so it can be re-translated in place.
var _objective_key: String = ""
## The action text of the prompt on screen, so it can be re-drawn with another key name.
var _prompt_action: String = ""
## The contextual prompt arrives and leaves with a short fade. It is the one piece of
## interface that appears while the player is moving the mouse around the world, so a line
## that switches on and off between two frames reads as a glitch in the pointer code; a
## line that arrives reads as the game answering. The fade is short (0.12 s) because the
## prompt is also information the player is waiting for.
const PROMPT_FADE_IN_SECONDS := 0.12
const PROMPT_FADE_OUT_SECONDS := 0.1


func _ready() -> void:
	_prompt_label.hide()
	_prompt_label.text = ""
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	refresh_language_text()
	var loc := _loc()
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_input_changed)
		settings.connect("bindings_changed", _on_input_changed.bind(&""))
	set_text_scale(UiTextScale.current(self))


## The player's text size, applied to every line the HUD draws.
func set_text_scale(factor: float) -> void:
	UiTextScale.apply(self, factor)


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		set_text_scale(UiTextScale.current(self))


## Another device or binding: the prompt and the language hint name the new key.
func _on_input_changed(_device: StringName) -> void:
	refresh_language_text()
	if _prompt_label.visible and not _prompt_action.is_empty():
		_prompt_label.text = "[%s] %s" % [_interact_key_label(), _prompt_action]


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
##
## The text is set synchronously — it is what `get_prompt_text()` reports and what the
## tests and the capture run wait for — and only the fade is asynchronous. Re-showing the
## same text is a no-op: the interaction controller re-resolves its target every physics
## frame, and restarting the fade on every resolve would make the line stutter.
func set_prompt_text(action: String) -> void:
	if action.strip_edges().is_empty():
		clear_prompt()
		return
	_prompt_action = action
	var text := "[%s] %s" % [_interact_key_label(), action]
	if _prompt_label.visible and _prompt_label.text == text:
		return
	_prompt_label.text = text
	_prompt_label.show()
	_kill_prompt_tween()
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_label, "modulate:a", 1.0, PROMPT_FADE_IN_SECONDS)


func get_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


func get_objective_text() -> String:
	return _objective_label.text if _objective_label != null else ""


## Empties the line at once and fades what is left of it out. The text is gone
## immediately, so nothing can read a stale prompt; only the pixels linger for a tenth of
## a second.
func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_action = ""
	_kill_prompt_tween()
	if not _prompt_label.visible:
		return
	if _prompt_label.modulate.a <= 0.001:
		_prompt_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_prompt_label.hide()
		return
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_label, "modulate:a", 0.0, PROMPT_FADE_OUT_SECONDS)
	_prompt_tween.tween_callback(_prompt_label.hide)


func _kill_prompt_tween() -> void:
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_tween = null


func refresh_language_text() -> void:
	if _language_label == null:
		return
	_language_label.text = L10n.t(
		"ui.language_switch",
		{
			"name": L10n.locale_name(L10n.other_locale()),
			"key": MenuStyle.key(self, &"toggle_language"),
		}
	)
	_language_label.visible = not _dialogue_open


## Called by the UI root when the dialogue panel opens or closes.
func set_dialogue_open(open: bool) -> void:
	_dialogue_open = open
	if _language_label != null:
		_language_label.visible = not open


## Shared device-aware presentation; no scene-local device branching or binding lookup.
func _interact_key_label() -> String:
	return InputHint.action_key(self, &"interact")
