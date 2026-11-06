extends Node3D
class_name PrologueMain
## Entry scene composition for the Biology Class prologue.
##
## Wiring only: it connects the director, the flow, the player's interaction
## sensor, and the three UI surfaces. All story decisions stay in PrologueFlow.
## All location decisions stay in PrologueDirector.

@onready var director: PrologueDirector = %Director
@onready var flow: PrologueFlow = %Flow
@onready var player: PlayerController = %Player
@onready var location_container: Node3D = %LocationContainer
## The HUD scene's root is a CanvasLayer, so it is referenced by path rather than
## by scene-unique name (unique names only cover nodes owned by this scene).
@onready var hud: PrologueHud = $Hud
@onready var notebook: NoteBook = %NoteBook
@onready var dialogue_panel: DialoguePanel = %DialoguePanel
@onready var interaction_sensor: InteractionSensor = %Player/InteractionSensor
@onready var room_tone: RoomTone = %RoomTone


func _ready() -> void:
	notebook.bind_ledger(flow.ledger)
	hud.note_book_requested.connect(_toggle_notebook)
	hud.language_toggle_requested.connect(_toggle_language)
	notebook.close_requested.connect(_toggle_notebook)
	interaction_sensor.focus_changed.connect(flow.set_focused_interactable)
	flow.prompt_changed.connect(_on_prompt_changed)
	flow.ledger_changed.connect(_on_ledger_changed)
	flow.dialogue_started.connect(_on_dialogue_started)
	flow.dialogue_ended.connect(_on_dialogue_ended)
	director.setup(location_container, player, flow)
	director.bell_rung.connect(_on_bell_rung)
	director.start_prologue()


## The bell is staged by the director; the sound is the main scene's job.
func _on_bell_rung() -> void:
	if room_tone != null:
		room_tone.ring_bell()


func _on_prompt_changed(_text_zh: String, _text_en: String) -> void:
	pass


## Language is a presentation setting: switching it re-renders every surface that
## is currently on screen and never touches narrative state.
func _toggle_language() -> void:
	Language.toggle()
	apply_language_to_all()


## Re-renders every surface that can be on screen. Public so the language test
## drives exactly the same path the key press does.
func apply_language_to_all() -> void:
	dialogue_panel.apply_language()
	notebook.apply_language()
	hud.refresh_language()
	flow.refresh_language()


func _on_ledger_changed() -> void:
	if notebook.visible:
		notebook.refresh()
	hud.set_note_available(flow.ledger.count())


func _on_dialogue_started(_script_id: StringName) -> void:
	interaction_sensor.enabled = false
	interaction_sensor.clear()
	hud.set_prompt("", "")
	notebook.close_notebook()


func _on_dialogue_ended(_script_id: StringName) -> void:
	interaction_sensor.enabled = true


func _unhandled_input(event: InputEvent) -> void:
	# The language switch is reachable at any time, including mid-conversation and
	# with the notebook open, because the player may need it to understand the
	# line they are stuck on.
	if event.is_action_pressed("toggle_language"):
		_toggle_language()
		get_viewport().set_input_as_handled()
		return
	if notebook.visible:
		return
	if flow.is_dialogue_active():
		return
	if event.is_action_pressed("interact"):
		interaction_sensor.interact_with_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("note_book"):
		_toggle_notebook()
		get_viewport().set_input_as_handled()


func _toggle_notebook() -> void:
	if flow.is_dialogue_active():
		return
	if notebook.visible:
		notebook.close_notebook()
		player.set_input_enabled(true)
	else:
		notebook.open_notebook()
		player.set_input_enabled(false)
