extends CharacterBody3D
class_name PlayerController
## Camera-relative movement and the player's small graybox pose only.

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.4
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8

@onready var camera: Camera3D = %Camera3D
@onready var standing: Node3D = %Standing
@onready var seated: Node3D = %Seated
@onready var visual: Node3D = %Visual
var control_enabled: bool = false
var _camera_home: Vector3
var _camera_tween: Tween


func _ready() -> void:
	add_to_group("player")
	_camera_home = camera.position
	camera.look_at(global_position + Vector3(0.0, 0.85, 0.0), Vector3.UP)


func set_control_enabled(value: bool) -> void:
	control_enabled = value
	if not value:
		velocity.x = 0.0
		velocity.z = 0.0


func set_seated(value: bool) -> void:
	seated.visible = value
	standing.visible = not value
	if value:
		visual.rotation.y = 0.0


func focus_camera_on(world_point: Vector3, duration: float = 0.8) -> void:
	if _camera_tween and _camera_tween.is_running():
		_camera_tween.kill()
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "global_position", world_point + _camera_home, duration)


func reset_camera(duration: float = 0.8) -> void:
	if _camera_tween and _camera_tween.is_running():
		_camera_tween.kill()
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "position", _camera_home, duration)


func snap_camera_home() -> void:
	if _camera_tween and _camera_tween.is_running():
		_camera_tween.kill()
	camera.position = _camera_home


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	if control_enabled:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var camera_right: Vector3 = camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward: Vector3 = -camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var move_direction: Vector3 = (
		camera_right * input_vector.x + camera_forward * -input_vector.y
	).normalized()

	velocity.x = move_toward(velocity.x, move_direction.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, move_direction.z * move_speed, acceleration * delta)
	if move_direction.length_squared() > 0.01 and standing.visible:
		var facing: float = atan2(-move_direction.x, -move_direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, facing, minf(delta * 10.0, 1.0))

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
