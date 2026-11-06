class_name GameUI
extends CanvasLayer
## Thin UI coordinator for the prologue presentation.
## Owns the HUD, prompt, settings overlay, end card, and forwards
## conversation lifecycle for anyone listening (LessonDirector, GateExit).
## Never decides story state; it asks GameState and dialogue data instead.

signal conversation_finished(conversation_id: StringName)

@onready var _objective_panel: PanelContainer = $HUD/ObjectivePanel
@onready var _objective_text: Label = $HUD/ObjectivePanel/VBox/ObjectiveText
@onready var _prompt_panel: PanelContainer = $HUD/PromptPanel
@onready var _prompt_text: Label = $HUD/PromptPanel/PromptText
@onready var _dialogue: DialogueBox = $DialogueBox
@onready var _backlog_hint: Label = $HUD/BacklogHint
@onready var _settings_panel: Control = $SettingsPanel
@onready var _settings_speed_button: Button = $SettingsPanel/PanelContainer/VBox/SpeedButton
@onready var _settings_size_button: Button = $SettingsPanel/PanelContainer/VBox/SizeButton
@onready var _settings_close_button: Button = $SettingsPanel/PanelContainer/VBox/CloseButton
@onready var _end_card: Control = $EndCard
@onready var _end_card_title: Label = $EndCard/Panel/VBox/Title
@onready var _end_card_summary: Label = $EndCard/Panel/VBox/Summary
@onready var _end_card_note: Label = $EndCard/Panel/VBox/Note
@onready var _restart_button: Button = $EndCard/Panel/VBox/RestartButton

var _objective: String = ""


func _ready() -> void:
	add_to_group("game_ui")
	_prompt_panel.visible = false
	_settings_panel.visible = false
	_end_card.visible = false
	_objective_panel.visible = true
	_dialogue.conversation_closed.connect(_on_dialogue_closed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_settings_speed_button.pressed.connect(_cycle_text_speed)
	_settings_size_button.pressed.connect(_cycle_text_scale)
	_refresh_settings_labels()
	var settings: Node = _settings()
	apply_text_scale(settings.font_scale() if settings != null else 1.0)


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_backlog"):
		_dialogue.toggle_backlog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_settings"):
		toggle_settings()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings_panel.visible:
			_settings_panel.visible = false
			get_viewport().set_input_as_handled()
		elif _dialogue.is_backlog_open():
			_dialogue.close_backlog()
			get_viewport().set_input_as_handled()
		return
	if _dialogue.is_open():
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			_dialogue.advance_pressed()
			get_viewport().set_input_as_handled()


func is_busy() -> bool:
	return (
		_dialogue.is_open()
		 or _dialogue.is_backlog_open()
		 or _settings_panel.visible
		 or _end_card.visible
	)


func start_conversation(conversation: DialogueConversation, start_override: StringName = &"") -> bool:
	return _dialogue.start(conversation, start_override)


func set_objective(text: String) -> void:
	_objective = text
	_objective_text.text = text
	_objective_panel.visible = not text.strip_edges().is_empty()


func get_objective() -> String:
	return _objective


func toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
	_refresh_settings_labels()


func apply_text_scale(factor: float) -> void:
	_dialogue.apply_text_scale(factor)
	_objective_text.add_theme_font_size_override("font_size", int(round(19 * factor)))
	_prompt_text.add_theme_font_size_override("font_size", int(round(20 * factor)))
	_backlog_hint.add_theme_font_size_override("font_size", int(round(12 * factor)))


func show_end_card() -> void:
	var root := get_tree().get_root()
	var state: Node = root.get_node_or_null("GameState") if root else null
	_end_card_title.text = "END OF THE BIOLOGY CLASS"
	_end_card_summary.text = (
		"The textbook is still missing.\n"
		+ "B never arrived. N let the class go.\n"
		+ "You walked out anyway."
	)
	_end_card_note.text = "Prologue complete — next up: the street and the green animal."
	if state != null:
		var inspects: int = state.count_flags_with_prefix("observed.inspect.")
		_end_card_note.text += "\n(things inspected: %d · imagination seen: %s)" % [
			inspects,
			"yes" if state.get_flag(&"imagination.b_confrontation_seen", false) == true else "no",
		]
	_end_card.visible = true


func _update_prompt() -> void:
	if is_busy():
		_prompt_panel.visible = false
		return
	var sensor := get_tree().get_first_node_in_group("interaction_sensor")
	if sensor == null or not (sensor is InteractionSensor):
		_prompt_panel.visible = false
		return
	var focused: Interactable = sensor.focused
	if focused == null or not focused.enabled:
		_prompt_panel.visible = false
		return
	_prompt_text.text = "[E]  " + focused.prompt
	_prompt_panel.visible = true


func _refresh_settings_labels() -> void:
	var settings: Node = _settings()
	var speed: String = settings.text_speed if settings != null else "normal"
	var scale: String = settings.text_scale if settings != null else "normal"
	_settings_speed_button.text = "Text speed:  %s" % speed.capitalize()
	_settings_size_button.text = "Text size:  %s" % scale.capitalize()


func _cycle_text_speed() -> void:
	var settings: Node = _settings()
	if settings == null:
		return
	var order: Array[String] = ["slow", "normal", "fast"]
	var index: int = order.find(settings.text_speed)
	settings.set_text_speed(order[(index + 1) % order.size()])
	_refresh_settings_labels()


func _cycle_text_scale() -> void:
	var settings: Node = _settings()
	if settings == null:
		return
	var order: Array[String] = ["small", "normal", "large"]
	var index: int = order.find(settings.text_scale)
	settings.set_text_scale(order[(index + 1) % order.size()])
	apply_text_scale(settings.font_scale())
	_refresh_settings_labels()


func _on_restart_pressed() -> void:
	var root := get_tree().get_root()
	var state: Node = root.get_node_or_null("GameState") if root else null
	if state != null and state.has_method("clear"):
		state.clear()
	var scene_flow: Node = root.get_node_or_null("SceneFlow") if root else null
	if scene_flow != null:
		scene_flow.travel("res://scenes/main/main.tscn", &"")
	else:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _settings() -> Node:
	var root := get_tree().get_root()
	return root.get_node_or_null("Settings") if root else null


func _on_dialogue_closed(conversation_id: StringName) -> void:
	conversation_finished.emit(conversation_id)
