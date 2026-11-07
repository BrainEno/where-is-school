class_name GameHud
extends Control
## Non-dialogue HUD: the current objective line and the contextual interaction
## prompt. Both are thin views over state the sequence director owns.

@onready var _objective_label: Label = %ObjectiveLabel
@onready var _prompt_label: Label = %PromptLabel

var _objective_tween: Tween = null


func _ready() -> void:
	_prompt_label.hide()
	_prompt_label.text = ""


func set_objective(text: String) -> void:
	var trimmed := text.strip_edges()
	_objective_label.text = trimmed
	_objective_label.visible = not trimmed.is_empty()
	if not _objective_label.visible:
		return
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_label.modulate = Color(1, 1, 1, 0.25)
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_label, "modulate", Color(1, 1, 1, 1), 0.5)


func set_prompt(interactable: Interactable) -> void:
	if interactable == null:
		clear_prompt()
		return
	_prompt_label.text = "[%s] %s" % [_interact_key_label(), interactable.get_prompt()]
	_prompt_label.show()


func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_label.hide()


## Reads the actual interact binding so the hint cannot drift from the input map.
func _interact_key_label() -> String:
	for event: InputEvent in InputMap.action_get_events("interact"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode != 0:
			return OS.get_keycode_string(key_event.physical_keycode)
	return "E"
