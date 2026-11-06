extends Node3D
class_name Interactable
## A local target. Its owner decides what an activation means.

@export var interaction_id: StringName
@export var prompt: String = "Inspect"
@export_range(0.2, 4.0, 0.05) var interaction_radius: float = 1.45
@export var available: bool = true


func _ready() -> void:
	if interaction_id == &"":
		push_error("Interactable at %s needs an interaction_id." % get_path())
	add_to_group("interactable")
