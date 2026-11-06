extends Node3D
class_name PrologueRoot
## Top-level composition for the biology-class prologue.
##
## Owns the running order of the session and nothing else. It loads the
## classroom, wires the flow to the room's markers, and handles the two
## thresholds (classroom → corridor → yard). Story facts live in GameState and
## NarrativeLedger; presentation lives in the UI scenes; beat logic lives in
## PrologueFlow.
##
## This is the node the smoke tests instantiate, so every reference here must be
## resolvable without a mouse or a window.

const CLASSROOM_SCENE := preload("res://scenes/locations/classroom/classroom.tscn")

@export var autostart: bool = true

@onready var location_root: Node3D = %LocationRoot
@onready var player: PlayerController = %Player
@onready var hud: PrologueHud = %Hud
@onready var dialogue_panel: DialoguePanel = %DialoguePanel
@onready var inspection_card: InspectionCard = %InspectionCard
@onready var note_book: NoteBook = %NoteBook
@onready var flow: PrologueFlow = %PrologueFlow
@onready var director: SceneDirector = %SceneDirector

var _classroom: ClassroomLocation


func _ready() -> void:
	director.location_root = location_root
	director.player = player
	director.threshold_crossed.connect(_on_threshold_crossed)

	# The classroom is instantiated through the director so that a single code
	# path positions the player, both at boot and after every transition.
	director.load_location(&"classroom", &"seated")
	_classroom = director.current_location() as ClassroomLocation
	if _classroom == null:
		push_error("PrologueRoot: classroom scene did not produce a ClassroomLocation root.")
		return

	flow.player = player
	flow.hud = hud
	flow.dialogue_panel = dialogue_panel
	flow.inspection_card = inspection_card
	flow.note_book = note_book
	flow.camera_focus_front = _classroom.front_focus
	flow.camera_focus_hall = _classroom.hall_focus
	flow.flow_finished.connect(_on_flow_finished)

	if autostart:
		flow.begin.call_deferred()


func get_classroom() -> ClassroomLocation:
	return _classroom


func get_flow() -> PrologueFlow:
	return flow


func _on_threshold_crossed(threshold_id: StringName) -> void:
	match threshold_id:
		&"yard":
			await _change_location(&"corridor", &"")
			# Corridor is a passage: the yard door is the next beat, so the player
			# keeps walking rather than stopping to interact.
			await get_tree().create_timer(0.2).timeout
		&"gate":
			flow.call(&"_reach_gate")


func _change_location(location_id: StringName, spawn: StringName) -> void:
	await hud.fade_to(1.0, 0.32)
	director.load_location(location_id, spawn)
	_classroom = null
	var location := director.current_location()
	if location is ClassroomLocation:
		_classroom = location
		flow.camera_focus_front = _classroom.front_focus
		flow.camera_focus_hall = _classroom.hall_focus
	hud.show_caption(_location_caption(location_id), 2.8)
	await get_tree().create_timer(0.24).timeout
	await hud.fade_to(0.0, 0.42)


func _location_caption(location_id: StringName) -> String:
	match location_id:
		&"corridor":
			return "The corridor smells of floor polish and wet shoes."
		&"yard":
			return "Outside. The light is still orange."
		&"classroom":
			return "Classroom 2-C."
	return ""


func _on_flow_finished() -> void:
	# Milestone boundary: the prologue ends at the school exit, not at the street.
	await get_tree().create_timer(1.2).timeout
	hud.show_caption("Milestone ends here. The street and the animal are the next slice.", 6.0)
