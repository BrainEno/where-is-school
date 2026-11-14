extends MeshInstance3D
## The one part of the laboratory that moves.
##
## The mixing drum in the middle of the room is running, and nothing on the machine says how
## to stop it: the control box has a running light, a blank plate where a switch would be, and
## no label. This script is the whole of that motion - a vane on the motor shaft, turning at a
## constant speed. It is deliberately not a game clock, not a puzzle and not a signal: a room
## where one thing moves and everything else is still reads as a room that is switched on.

## Degrees the vane turns per second. One turn every few seconds is enough to be seen at the
## gameplay camera's distance, and slow enough not to look like a warning.
@export var degrees_per_second: float = 96.0


func _process(delta: float) -> void:
	rotate_y(deg_to_rad(degrees_per_second) * delta)
