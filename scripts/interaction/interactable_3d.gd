extends Area3D
class_name Interactable3D
## A thing the player can look at or use.
##
## It knows its own id and whether it is currently enabled, and nothing else. It
## does not know what its id means, who is listening, or what dialogue follows.
## [PrologueFlow] is the single owner that turns ids into inspections,
## conversations, doors, and thresholds.

## Stable id consumed by the flow owner. Rename only with a save migration.
@export var interact_id: StringName = &""
## Shown in the contextual prompt, e.g. "Check the schoolbag".
@export var prompt_text: String = "Look closer"
## Higher priority wins when two interactables overlap in the sensor cone.
@export var focus_priority: int = 0
## Optional label under the prompt (speaker-free description of the thing).
@export var short_label: String = ""

## Whether the target can be interacted with at boot. The classroom door starts
## disabled: the lesson has not released the class yet.
@export var start_enabled: bool = true

var _enabled: bool = true


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_enabled = start_enabled
	add_to_group(&"interactable")


func is_enabled() -> bool:
	return _enabled and is_visible_in_tree() and process_mode != Node.PROCESS_MODE_DISABLED


func set_enabled(value: bool) -> void:
	_enabled = value


func get_prompt_text() -> String:
	return prompt_text
