class_name Interactable3D
extends Area3D
## A thing the player can target and use.
##
## Ownership: this node knows only its own identity and prompt text. It does not
## know what the interaction does. It emits [signal interacted] and lets
## PrologueFlow decide whether that means "inspect", "talk", "open", or nothing.
##
## PrologueFlow finds these through the "interactable" group rather than through
## hard-coded node paths, so props can be moved between scenes freely.

signal interacted(interactable: Interactable3D)

enum Kind {
	INSPECT = 0,
	TALK = 1,
	DOOR = 2,
	THRESHOLD = 3,
	SIT = 4,
}

@export var interact_id: StringName = &""
@export var kind: int = Kind.INSPECT
@export var prompt_zh: String = "查看"
@export var prompt_en: String = "Look"
@export var target_name_zh: String = ""
@export var target_name_en: String = ""
## When true, the interactable stays targetable but PrologueFlow will explain why
## nothing happens (e.g. a closed door during a lesson).
@export var enabled: bool = true
## Tie-breaker when two interactables are both in reach. A small object sitting on
## or beside larger furniture (the set square on the teacher's desk, the schoolbag
## beside the classmate) must win over the furniture, otherwise the player can
## never target it. Higher wins; distance only decides between equal priorities.
@export_range(0, 5, 1) var focus_priority: int = 0


func _ready() -> void:
	add_to_group(&"interactable")
	if interact_id == &"":
		push_error("Interactable3D '%s' has no interact_id." % get_path())
	monitoring = true
	monitorable = true


func display_name_zh() -> String:
	return target_name_zh if not target_name_zh.is_empty() else interact_id


func display_name_en() -> String:
	return target_name_en if not target_name_en.is_empty() else interact_id


## Called by the interaction sensor when the player presses the interact action.
func request_interaction() -> void:
	interacted.emit(self)
