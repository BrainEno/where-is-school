class_name Classroom
extends Node3D
## Beat A–G location: the biology classroom.
##
## Owns geometry, lighting mood, the NPC actors standing in it, and the two
## authored presentation states that the prologue actually needs:
##   - "lesson": the room at the start; the door is shut.
##   - "released": N has let the class go; students have thinned out and the door
##     can be used.
##
## It does not own dialogue content, flags, or the player. PrologueFlow calls the
## public methods here; this script never reads narrative data itself.

signal transition_requested(target_location: StringName)
signal lesson_attention_requested

## NPC scenes placed by this location. Kept here so composition is visible in one
## place instead of being scattered through node paths.
@onready var q_actor: Node3D = %QActor
@onready var n_actor: Node3D = %NActor
@onready var door: Interactable3D = %ClassroomDoor
## Resolved lazily: these two interactables are optional presentation details, and
## a %UniqueName lookup here would fail hard if a scene edit removed them. A
## missing prompt should degrade, not crash the room.
@onready var think_area: Interactable3D = get_node_or_null("%DeskThinkArea") as Interactable3D
@onready var n_talk: Interactable3D = get_node_or_null("%NTalkArea") as Interactable3D
@onready var background_students: Node3D = %BackgroundStudents

var _released: bool = false


func _ready() -> void:
	n_actor.visible = false
	n_actor.process_mode = Node.PROCESS_MODE_DISABLED
	door.enabled = false
	# N is not in the room yet.
	_set_talk_enabled(false)


## N enters the room. Called by PrologueFlow when the bell beat starts.
func bring_in_substitute() -> void:
	n_actor.visible = true
	n_actor.process_mode = Node.PROCESS_MODE_INHERIT
	if n_actor.has_method("play_enter"):
		n_actor.call("play_enter")
	_set_talk_enabled(true)


func set_released(released: bool) -> void:
	_released = released
	unlock_exit()
	if released and background_students != null:
		background_students.visible = false


## The private "think" prompt is only offered once Q has stopped talking and
## disappears entirely once the lesson has actually begun.
func set_think_available(available: bool) -> void:
	if think_area == null:
		push_warning("Classroom has no DeskThinkArea; the anticipation beat will be unreachable here.")
		return
	think_area.enabled = available
	think_area.visible = available


func _set_talk_enabled(enabled: bool) -> void:
	if n_talk == null:
		return
	n_talk.enabled = enabled


func unlock_exit() -> void:
	door.enabled = true
	door.prompt_zh = "开门"
	door.prompt_en = "Open"


## Forwarded by PrologueFlow when the player uses the door.
func request_transition(target_location: StringName) -> void:
	transition_requested.emit(target_location)


func is_released() -> bool:
	return _released
