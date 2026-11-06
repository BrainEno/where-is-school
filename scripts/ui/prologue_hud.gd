extends Control
class_name PrologueHud
## Everything that is not the dialogue box: the interaction prompt, the wake
## fade, transient captions, and the controls reminder.
##
## The HUD is told what to show. It does not query the world, decide what is
## interactable, or know any story flag names.

signal notebook_requested

const CONTROLS_TEXT := "WASD move    E/click look    Tab backlog    N notes    Esc controls"

@onready var prompt_container: Control = %PromptContainer
@onready var prompt_key: Label = %PromptKey
@onready var prompt_text: Label = %PromptText
@onready var prompt_label: Label = %PromptLabel
@onready var fade: ColorRect = %Fade
@onready var caption: Label = %Caption
@onready var objective_label: Label = %Objective
@onready var controls_label: Label = %Controls
@onready var controls_panel: PanelContainer = %ControlsPanel

var _caption_timer: float = 0.0
var _objective_timer: float = 0.0


func _ready() -> void:
	prompt_container.visible = false
	caption.visible = false
	objective_label.visible = false
	controls_panel.visible = false
	controls_label.text = CONTROLS_TEXT
	fade.color = Color(0.02, 0.03, 0.03, 1.0)
	fade.visible = true


func _process(delta: float) -> void:
	if _caption_timer > 0.0:
		_caption_timer -= delta
		if _caption_timer <= 0.0:
			caption.visible = false
	if _objective_timer > 0.0:
		_objective_timer -= delta
		objective_label.modulate.a = clampf(_objective_timer, 0.0, 1.0)
		if _objective_timer <= 0.0:
			objective_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("notebook"):
		notebook_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("show_controls"):
		controls_panel.visible = not controls_panel.visible
		get_viewport().set_input_as_handled()


func show_prompt(prompt: String, label: String = "") -> void:
	prompt_container.visible = true
	prompt_text.text = prompt
	prompt_key.text = "E"
	prompt_label.text = label
	prompt_label.visible = not label.is_empty()


func hide_prompt() -> void:
	prompt_container.visible = false


func set_objective(text: String, hold_seconds: float = 0.0) -> void:
	objective_label.text = text
	objective_label.visible = not text.is_empty()
	objective_label.modulate.a = 1.0
	_objective_timer = hold_seconds


func show_caption(text: String, hold_seconds: float = 2.4) -> void:
	caption.text = text
	caption.visible = true
	caption.modulate.a = 1.0
	_caption_timer = hold_seconds


## Fades the black overlay to [param alpha] over [param seconds]. Awaitable.
func fade_to(alpha: float, seconds: float) -> void:
	if seconds <= 0.0:
		fade.color.a = alpha
		fade.visible = alpha > 0.001
		return
	var tween := create_tween()
	tween.tween_property(fade, "color:a", alpha, seconds)
	fade.visible = true
	await tween.finished
	if alpha <= 0.001:
		fade.visible = false


func set_controls_visible(value: bool) -> void:
	controls_panel.visible = value
