extends CharacterBody3D
class_name PlayerController
## Camera-relative movement for the 2.5D presentation.
## Owns locomotion only: interaction targeting lives in InteractionSensor,
## dialogue and story state live elsewhere. Emits nothing global.

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 4.0
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8

@onready var camera: Camera3D = %Camera3D
@onready var visual: Node3D = $Visual
@onready var sensor: InteractionSensor = $InteractionSensor

var _facing: Vector3 = Vector3(0.0, 0.0, -1.0)


func _ready() -> void:
	camera.look_at(global_position + Vector3(0.0, 0.85, 0.0), Vector3.UP)
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	if _can_act():
		input_vector = Input.get_vector(
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

	var move_direction: Vector3 = Vector3.ZERO
	if input_vector.length() > 0.01:
		move_direction = (
			camera_right * input_vector.x
			+ camera_forward * -input_vector.y
		).normalized()

	if move_direction.length() > 0.01:
		_facing = move_direction
		var target_yaw: float = atan2(_facing.x, _facing.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, minf(1.0, delta * 10.0))

	var target_x: float = move_direction.x * move_speed
	var target_z: float = move_direction.z * move_speed

	velocity.x = move_toward(velocity.x, target_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_act():
		return
	if event.is_action_pressed("interact"):
		var target: Interactable = sensor.focused
		if target != null:
			target.interact(self)
			get_viewport().set_input_as_handled()


func facing_direction() -> Vector3:
	return _facing


func _can_act() -> bool:
	if not is_inside_tree():
		return false
	var game_ui := get_tree().get_first_node_in_group("game_ui")
	if game_ui != null and game_ui.has_method("is_busy"):
		return not game_ui.is_busy()
	return true
