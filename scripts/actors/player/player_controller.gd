extends CharacterBody3D
class_name PlayerController
## Camera-relative movement controller.
##
## The player scene keeps its own camera rig (per docs/ARCHITECTURE.md §4), but the
## camera now lives in a rig node so it can be aimed once and then follow the body
## without the 2.5D angle changing as the player turns.
##
## Control is gated by [member input_enabled]: PrologueFlow disables it while the
## prologue is staging the wake-up beat and while a conversation is on screen.

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.1
@export_range(1.0, 40.0, 0.5) var acceleration: float = 22.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8

@export_category("Camera")
## Horizontal direction the camera looks along, in degrees. The prologue uses one
## fixed angle for the whole slice so navigation stays readable.
## Camera sits on the +x/+z side, looking toward the far (-x, -z) corner.
@export_range(-180.0, 180.0, 1.0) var camera_yaw_degrees: float = 40.0
@export_range(5.0, 75.0, 0.5) var camera_pitch_degrees: float = 44.0
@export_range(3.0, 30.0, 0.5) var camera_distance: float = 8.4
@export_range(0.0, 20.0, 0.5) var camera_height: float = 1.4
@export_range(0.0, 30.0, 0.1) var camera_follow_smoothing: float = 12.0

## When false the player cannot move and the body decelerates to a stop.
@export var input_enabled: bool = true

var _gravity: float = 9.8

@onready var camera: Camera3D = %Camera3D
@onready var visual: Node3D = %Visual


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", gravity))
	_apply_camera_offset()
	snap_camera()


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

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
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()
	_face_movement(delta)
	_follow_camera(delta)


func set_input_enabled(value: bool) -> void:
	input_enabled = value


func set_camera_yaw(degrees: float) -> void:
	camera_yaw_degrees = degrees
	_apply_camera_offset()
	snap_camera()


## Places the body at a scene-authored spawn point and re-frames the camera
## immediately, so waking up does not slide the camera across the room.
func teleport_to(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	snap_camera()


func snap_camera() -> void:
	if camera == null:
		return
	_apply_camera_offset()
	camera.global_position = global_position + _camera_offset()
	camera.look_at(global_position + Vector3(0.0, camera_height, 0.0), Vector3.UP)


func _camera_offset() -> Vector3:
	var yaw: float = deg_to_rad(camera_yaw_degrees)
	var pitch: float = deg_to_rad(camera_pitch_degrees)
	var horizontal: float = cos(pitch) * camera_distance
	return Vector3(
		sin(yaw) * horizontal,
		sin(pitch) * camera_distance + camera_height,
		cos(yaw) * horizontal
	)


func _apply_camera_offset() -> void:
	if camera == null:
		return
	# Keep the camera as a sibling in world space rather than a child of the body,
	# so the 2.5D angle never rotates with the player's facing.
	camera.top_level = true


func _follow_camera(delta: float) -> void:
	if camera == null:
		return
	var desired: Vector3 = global_position + _camera_offset()
	if camera_follow_smoothing <= 0.0:
		camera.global_position = desired
	else:
		camera.global_position = camera.global_position.lerp(
			desired, clampf(camera_follow_smoothing * delta, 0.0, 1.0)
		)
	camera.look_at(global_position + Vector3(0.0, camera_height, 0.0), Vector3.UP)


func _face_movement(delta: float) -> void:
	if visual == null:
		return
	var flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.04:
		return
	var target_yaw: float = atan2(flat.x, flat.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(10.0 * delta, 0.0, 1.0))
