extends CharacterBody3D
class_name PlayerController
## Camera-relative movement plus the controlled 2.5D camera.
##
## The camera keeps a fixed offset from the player (a high three-quarter view)
## and eases toward it, so the framing is authored rather than free. It is
## detached with [code]top_level[/code] so that smoothing does not fight the
## character's own transforms. Nothing here knows *why* movement stops: the
## wake beat, dialogue, and scene transitions all ask for the same two switches.

signal interaction_pressed(target: Interactable3D)
signal movement_blocked_changed(blocked: bool)
signal sitting_changed(sitting: bool)

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.0
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8
@export_range(0.5, 20.0, 0.1) var turn_speed: float = 12.0

@export_category("Camera")
@export var camera_offset: Vector3 = Vector3(6.2, 7.4, 6.2)
@export_range(0.0, 20.0, 0.1) var camera_follow_speed: float = 6.0
@export_range(0.5, 4.0, 0.1) var camera_focus_distance: float = 1.6
@export var camera_look_height: float = 0.75

@export_category("Seated pose")
@export var seated_head_height: float = 1.2
@export var seated_shoulder_height: float = 0.98
@export var seated_body_scale_y: float = 0.6

@onready var camera: Camera3D = %Camera3D
@onready var sensor: InteractionSensor = %InteractionSensor
@onready var visual_root: Node3D = %VisualRoot
@onready var collision: CollisionShape3D = %CollisionShape3D
@onready var body_mesh: MeshInstance3D = %Body
@onready var head_mesh: MeshInstance3D = %Head
@onready var shoulders: MeshInstance3D = %Shoulders

var _input_enabled: bool = true
var _sitting: bool = false
var _camera_target: Vector3 = Vector3.ZERO
var _focus_point: Vector3 = Vector3.INF
var _focus_weight: float = 0.0
var _base_body_y: float = 0.85
var _base_head_y: float = 1.66
var _base_shoulder_y: float = 1.38


func _ready() -> void:
	_base_body_y = body_mesh.position.y
	_base_head_y = head_mesh.position.y
	_base_shoulder_y = shoulders.position.y
	camera.top_level = true
	_apply_camera(true)


func _apply_camera(snap: bool) -> void:
	var look_target: Vector3 = global_position + Vector3(0, camera_look_height, 0)
	var desired: Vector3 = global_position + camera_offset
	if _focus_weight > 0.0 and _focus_point != Vector3.INF:
		var weighted: Vector3 = look_target.lerp(_focus_point, _focus_weight)
		desired = weighted + camera_offset * (1.0 - 0.12 * _focus_weight)
		look_target = weighted
	if snap or _camera_target == Vector3.ZERO:
		_camera_target = desired
	else:
		_camera_target = _camera_target.lerp(desired, clampf(camera_follow_speed * get_process_delta_time(), 0.0, 1.0))
	camera.global_position = _camera_target
	if camera.global_position.distance_squared_to(look_target) > 0.01:
		camera.look_at(look_target, Vector3.UP)


func _process(delta: float) -> void:
	if _focus_weight > 0.0:
		_focus_weight = move_toward(_focus_weight, 0.0, delta * 0.35)
	_apply_camera(false)


## Subtly shifts the framing toward a point (used by the rehearsal and by N's
## entrance). This only moves the camera; it changes nothing in the world.
func emphasise(point: Vector3, weight: float = 0.55) -> void:
	_focus_point = point
	_focus_weight = clampf(weight, 0.0, 1.0)


func set_input_enabled(enabled: bool) -> bool:
	var previous: bool = _input_enabled
	if _input_enabled == enabled:
		return previous
	_input_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
	if sensor != null:
		sensor.enabled = enabled
	movement_blocked_changed.emit(not enabled)
	return previous


func is_input_enabled() -> bool:
	return _input_enabled


func set_sitting(sitting: bool) -> void:
	if _sitting == sitting:
		return
	_sitting = sitting
	_apply_sitting_pose()
	sitting_changed.emit(sitting)


func _apply_sitting_pose() -> void:
	if _sitting:
		body_mesh.scale.y = seated_body_scale_y
		body_mesh.position.y = 0.42
		head_mesh.position.y = seated_head_height
		shoulders.position.y = seated_shoulder_height
		if collision != null:
			collision.shape = _short_capsule()
			collision.position.y = 0.62
	else:
		body_mesh.scale.y = 1.0
		body_mesh.position.y = _base_body_y
		head_mesh.position.y = _base_head_y
		shoulders.position.y = _base_shoulder_y
		if collision != null:
			collision.shape = _full_capsule()
			collision.position.y = 0.9


var _full_shape: CapsuleShape3D
var _sitting_shape: CapsuleShape3D


func _full_capsule() -> CapsuleShape3D:
	if _full_shape == null:
		_full_shape = CapsuleShape3D.new()
		_full_shape.radius = 0.32
		_full_shape.height = 1.7
	return _full_shape


func _short_capsule() -> CapsuleShape3D:
	if _sitting_shape == null:
		_sitting_shape = CapsuleShape3D.new()
		_sitting_shape.radius = 0.3
		_sitting_shape.height = 1.1
	return _sitting_shape


func is_sitting() -> bool:
	return _sitting


func get_camera() -> Camera3D:
	return camera


func teleport_to(target: Transform3D) -> void:
	global_position = target.origin
	global_rotation.y = target.basis.get_euler().y
	velocity = Vector3.ZERO
	_apply_camera(true)


## Turns the body (not the camera) toward a world point. Used when a
## conversation starts so the player faces the speaker instead of a wall.
func look_at_point(point: Vector3) -> void:
	if visual_root == null:
		return
	var flat := Vector3(point.x, global_position.y, point.z)
	var offset := flat - global_position
	if offset.length_squared() < 0.0025:
		return
	visual_root.rotation.y = atan2(offset.x, offset.z)


func current_target() -> Interactable3D:
	return sensor.current_target() if sensor != null else null


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if event.is_action_pressed("interact"):
		var target: Interactable3D = current_target()
		if target != null:
			interaction_pressed.emit(target)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	if not _input_enabled or _sitting:
		input_vector = Vector2.ZERO

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

	if move_direction.length_squared() > 0.01:
		_rotate_body_toward(move_direction, delta)


func _rotate_body_toward(direction: Vector3, delta: float) -> void:
	if visual_root == null:
		return
	var target_yaw: float = atan2(direction.x, direction.z)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
