class_name Interactable
extends Area3D
## Interaction contract for anything the player can use in the world.
## Owns only targeting metadata and a signal; it never draws UI or mutates story state.
## Behavior lives in subclasses or in nodes connected to the `interacted` signal.

signal interacted(player: Node)

## Short verb shown in the prompt, e.g. "Search the schoolbag".
@export var prompt: String = "Interact"
## Stable identifier used by tests, analytics of flow, and future save data.
@export var interaction_id: StringName = &""
## Disabled interactables stay in the world but cannot be focused or used.
@export var enabled: bool = true
## Higher priority wins when two focusable targets overlap (e.g. a small prop on a big desk).
@export var interact_priority: int = 0


func _ready() -> void:
	add_to_group("interactables")
	monitoring = false
	monitorable = false


func interact(player: Node) -> void:
	if not enabled:
		return
	interacted.emit(player)
