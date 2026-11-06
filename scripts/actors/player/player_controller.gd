extends CharacterBody3D
class_name PlayerController
## Minimal camera-relative movement controller for the graybox foundation.

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 4.0
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8

@onready var camera: Camera3D = %Camera3D


func _ready() -> void:
	camera.look_at(global_position + Vector3(0.0, 0.85, 0.0), Vector3.UP)


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var camera_right: Vector3 = camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var camera_forward: Vector3 = -camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var move_direction: Vector3 = (
		camera_right * input_vector.x
		+ camera_forward * -input_vector.y
	).normalized()

	var target_x: float = move_direction.x * move_speed
	var target_z: float = move_direction.z * move_speed

	velocity.x = move_toward(velocity.x, target_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()
