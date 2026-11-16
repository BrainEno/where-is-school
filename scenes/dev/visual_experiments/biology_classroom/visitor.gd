extends CharacterBody3D
## The protagonist as a visitor to the biology classroom experiment: walks, turns, falls
## under gravity, animates. It owns no camera. The room's fixed camera
## (`fixed_camera.gd`) frames it, and the keys are read relative to that camera's view
## (`view_yaw`). A camera change does not swing the controls round under a held key: the
## keys keep meaning what they meant when they were pressed, until they are let go.
##
## Development only (scenes/dev/ is excluded from every export preset). Written for this
## experiment so the visual lab's `observer.gd` (a following camera) stays as it is.

const WALK_SPEED: float = 3.6
const JOG_SPEED: float = 5.6
const TURN_SPEED: float = 12.0
const GRAVITY: float = 9.8

## The yaw of the view the keys are read against (radians; 0 = looking toward -Z).
var view_yaw: float = 0.0

var _held_yaw: float = 0.0
var _animator: Node = null
var _gliding: bool = false

@onready var visual: Node3D = $Visual


func _ready() -> void:
	for child: Node in visual.get_children():
		if child.has_method("report_velocity"):
			_animator = child
	if _animator != null and _animator.has_method("bind_body"):
		_animator.call("bind_body", self)


## The character model (the game's protagonist scene), or null if it failed to load.
func character() -> Node3D:
	return _animator as Node3D


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if input == Vector2.ZERO:
		_held_yaw = view_yaw
	var direction := Vector3.ZERO
	if input != Vector2.ZERO:
		var forward := -Vector3(sin(_held_yaw), 0.0, cos(_held_yaw))
		var right := Vector3(cos(_held_yaw), 0.0, -sin(_held_yaw))
		direction = (right * input.x - forward * input.y).normalized()
	var speed := JOG_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	if not _gliding:
		move_and_slide()
		if direction != Vector3.ZERO:
			_face(direction, TURN_SPEED * delta)


## Stands the character at `feet`, turned toward `target`.
func place(feet: Vector3, target: Vector3) -> void:
	_gliding = false
	global_position = feet
	velocity = Vector3.ZERO
	var toward := target - feet
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		_face(toward, 1.0)
	if _animator != null and _animator.has_method("clear_reported_velocity"):
		_animator.call("clear_reported_velocity")
	reset_physics_interpolation()


## Ends any scripted movement: the character stands, and the keys move it again.
func stop_gliding() -> void:
	_gliding = false
	velocity = Vector3.ZERO
	if _animator != null and _animator.has_method("clear_reported_velocity"):
		_animator.call("clear_reported_velocity")


## Which way the character faces (its model looks down +Z).
func facing() -> Vector3:
	return visual.global_basis.z


func _face(direction: Vector3, weight: float) -> void:
	var target_angle := atan2(direction.x, direction.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_angle, clampf(weight, 0.0, 1.0))
