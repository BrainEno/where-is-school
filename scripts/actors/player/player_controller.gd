extends CharacterBody3D
class_name PlayerController
## Camera-relative movement for the 2.5D presentation.
##
## The body never rotates: the camera keeps its authored angle and the visual
## pivot turns to face the direction of travel. Movement can be locked by the
## sequence director (during the wake beat and while dialogue is open) without
## the player losing their physical position.

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.6
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8
## How quickly the visual turns toward the movement direction.
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 12.0

@export_category("Camera")
@export var camera_offset: Vector3 = Vector3(3.4, 6.4, 3.4)
@export_range(30.0, 90.0, 1.0) var camera_fov: float = 60.0
## Height above the player's origin the camera looks at.
@export var camera_target_height: float = 0.9
## Small roll applied while waking up, in degrees.
@export_range(0.0, 20.0, 0.5) var wake_camera_roll: float = 3.5

@export_category("Wake pose")
## Forward slump of the body mesh while the protagonist is still coming to.
@export_range(0.0, 45.0, 1.0) var wake_tilt_degrees: float = 22.0

@onready var camera: Camera3D = %Camera3D
@onready var visual_pivot: Node3D = %VisualPivot
@onready var visual: MeshInstance3D = %Visual

var _control_enabled: bool = true
var _camera_roll: float = 0.0
var _facing_direction: Vector3 = Vector3(0.0, 0.0, -1.0)


func _ready() -> void:
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	camera.position = camera_offset
	camera.fov = camera_fov
	camera.look_at(global_position + Vector3(0.0, camera_target_height, 0.0), Vector3.UP)
	if not is_zero_approx(_camera_roll):
		camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(_camera_roll))


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if _control_enabled:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var move_direction := (camera_right * input_vector.x + camera_forward * -input_vector.y)
	if move_direction.length_squared() > 0.0001:
		move_direction = move_direction.normalized()
		_facing_direction = move_direction

	var target_x := move_direction.x * move_speed
	var target_z := move_direction.z * move_speed

	velocity.x = move_toward(velocity.x, target_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()
	_update_visual_facing(delta)


func _update_visual_facing(delta: float) -> void:
	if visual_pivot == null:
		return
	var target_angle := atan2(_facing_direction.x, _facing_direction.z)
	visual_pivot.rotation.y = lerp_angle(visual_pivot.rotation.y, target_angle, turn_speed * delta)


# --- Director API -----------------------------------------------------------


## Locked during the wake beat and whenever a presentation is open.
func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled


func is_control_enabled() -> bool:
	return _control_enabled


func get_facing_direction() -> Vector3:
	return _facing_direction


## Zero-based slump used by the wake beat. 0 = upright.
func set_wake_pose(amount: float) -> void:
	if visual == null:
		return
	var clamped := clampf(amount, 0.0, 1.0)
	visual.rotation_degrees.x = wake_tilt_degrees * clamped
	visual.position.y = 0.9 - 0.06 * clamped


func settle_wake_pose(duration: float) -> void:
	if visual == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "rotation_degrees:x", 0.0, duration)
	tween.tween_property(visual, "position:y", 0.9, duration)
	await tween.finished


func set_camera_roll(degrees: float) -> void:
	_camera_roll = degrees
	_apply_camera_transform()


func settle_camera_roll(duration: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_camera_roll_degrees, _camera_roll, 0.0, duration)
	await tween.finished


func _set_camera_roll_degrees(value: float) -> void:
	set_camera_roll(value)


func teleport(target: Transform3D) -> void:
	global_position = target.origin
	velocity = Vector3.ZERO
	if not target.basis.is_equal_approx(Basis.IDENTITY):
		_facing_direction = -target.basis.z
	_apply_camera_transform()
