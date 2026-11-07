extends Node3D
## The green animal: a neutral blockout that behaves like a small animal.
##
## It breathes, sways its head, and does not approach or threaten the player. The
## scene is deliberately built from primitives with a flat colour, so nothing in
## the model claims what species it is. Nothing here decides what the animal
## means: the dialogue does the noticing, and it keeps its conclusions open.

## Vertical breathing amplitude in metres.
@export var bob_height: float = 0.015
## Head sway in degrees.
@export var sway_degrees: float = 5.0
@export var sway_speed: float = 0.35

@onready var _head: Node3D = get_node_or_null(^"Head")

var _time: float = 0.0
var _rest_y: float = 0.0


func _ready() -> void:
	_rest_y = position.y


func _process(delta: float) -> void:
	_time += delta
	position.y = _rest_y + sin(_time * 1.7) * bob_height
	if _head != null:
		_head.rotation.y = deg_to_rad(sway_degrees) * sin(_time * sway_speed)
		_head.rotation.x = deg_to_rad(sway_degrees * 0.25) * sin(_time * 1.1 + 1.3)
