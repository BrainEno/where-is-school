class_name NpcActor
extends Node3D
## A person standing in the room. Presentation only.
##
## The actor knows nothing about what it will say: PrologueFlow finds the
## Interactable3D child and decides which DialogueScript to play. This keeps a
## character's body reusable if their role changes between scenes.

@export var idle_sway_degrees: float = 1.6
@export var idle_speed: float = 0.7
@export var enter_from_offset: Vector3 = Vector3(-4.0, 0.0, 0.0)
@export var enter_duration: float = 1.1

var _idle_time: float = 0.0
var _base_rotation_y: float = 0.0
var _entering: bool = false
var _enter_time: float = 0.0
var _enter_start: Vector3
var _enter_target: Vector3


func _ready() -> void:
	_base_rotation_y = rotation.y
	_idle_time = randf() * TAU


func _process(delta: float) -> void:
	if _entering:
		_enter_time += delta
		var t: float = clampf(_enter_time / maxf(enter_duration, 0.01), 0.0, 1.0)
		position = _enter_start.lerp(_enter_target, ease(t, 0.4))
		if t >= 1.0:
			_entering = false
		return
	_idle_time += delta * idle_speed
	rotation.y = _base_rotation_y + deg_to_rad(sin(_idle_time) * idle_sway_degrees)


## Used when a character walks in rather than being present at load.
func play_enter() -> void:
	_enter_target = position
	_enter_start = position + enter_from_offset
	position = _enter_start
	_enter_time = 0.0
	_entering = true


## Turns to look at a world position (used when someone addresses the room).
func face_position(target: Vector3) -> void:
	var flat: Vector3 = target - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.001:
		return
	_base_rotation_y = atan2(flat.x, flat.z)
	rotation.y = _base_rotation_y
