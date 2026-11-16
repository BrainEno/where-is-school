extends CharacterBody3D
## A free observer for the visual experiments lab: a first-person body that walks, can
## fly, and keeps colliding with the world either way — the point of experiment D is that
## the world stays physical when it stops looking it.
##
## Deliberately not the game's `PlayerController` / `CameraRig`: the lab must not depend on
## (or change) the production controller, and an eye-level camera is the right instrument
## for looking at paper, flats and colour fields up close.
##
## Keys are read directly (not through the project's input map) so nothing here can
## collide with a binding the settings screen owns.
##   WASD / arrows  walk         Shift  faster        Mouse (click to capture)  look
##   F              fly on/off   Q / E  down / up      N  pass through walls (fly only)
##   Esc            release the mouse

const EYE_HEIGHT: float = 1.55
const WALK_SPEED: float = 3.0
const FAST_SPEED: float = 7.0
const FLY_SPEED: float = 6.0
const MOUSE_SENSITIVITY: float = 0.0024
const KEY_TURN_SPEED: float = 1.8
const PITCH_LIMIT: float = 1.45

var flying: bool = false
var passing_through: bool = false
## How many times `teleport_by()` moved the observer (the corridor loop counts on it).
var teleports: int = 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	head.position.y = EYE_HEIGHT
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn(-motion.relative.x * MOUSE_SENSITIVITY, -motion.relative.y * MOUSE_SENSITIVITY)
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_F:
			set_flying(not flying)
		KEY_N:
			set_passing_through(not passing_through)


func set_flying(enabled: bool) -> void:
	flying = enabled
	motion_mode = (
		CharacterBody3D.MOTION_MODE_FLOATING if enabled else CharacterBody3D.MOTION_MODE_GROUNDED
	)
	if not enabled:
		set_passing_through(false)


## Only while flying: walking through walls on foot would make the floor optional too.
func set_passing_through(enabled: bool) -> void:
	passing_through = enabled and flying
	_shape.disabled = passing_through


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		_turn(KEY_TURN_SPEED * delta, 0.0)
	if Input.is_key_pressed(KEY_RIGHT):
		_turn(-KEY_TURN_SPEED * delta, 0.0)
	var speed := FAST_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var planar := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	planar.y = 0.0
	planar = planar.normalized() * speed if planar.length_squared() > 0.0 else Vector3.ZERO
	if flying:
		var vertical := 0.0
		if Input.is_key_pressed(KEY_E):
			vertical += 1.0
		if Input.is_key_pressed(KEY_Q):
			vertical -= 1.0
		velocity = Vector3(planar.x, vertical * FLY_SPEED, planar.z)
		if passing_through:
			global_position += velocity * delta
			return
	else:
		velocity.x = planar.x
		velocity.z = planar.z
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= 9.8 * delta
	move_and_slide()


func _turn(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	head.rotation.x = clampf(head.rotation.x + pitch, -PITCH_LIMIT, PITCH_LIMIT)


## Stands the observer at `feet`, looking at `target`. Used by the lab's stations, the
## capture scripts and the test; it is the same body the keys move.
func place(feet: Vector3, target: Vector3) -> void:
	global_position = feet
	velocity = Vector3.ZERO
	var direction := target - (feet + Vector3.UP * EYE_HEIGHT)
	rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	var horizontal := Vector2(direction.x, direction.z).length()
	head.rotation.x = clampf(atan2(direction.y, horizontal), -PITCH_LIMIT, PITCH_LIMIT)
	reset_physics_interpolation()


## Moves the observer by `offset` without turning it: how the corridor's far door
## returns you to its near end.
func teleport_by(offset: Vector3) -> void:
	global_position += offset
	teleports += 1
	reset_physics_interpolation()


func eye_position() -> Vector3:
	return camera.global_position
