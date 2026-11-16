extends CharacterBody3D
## The visitor of the visual experiments lab: the protagonist, seen from a third-person
## follow camera, as in the game.
##
## The game frames its player with a high three-quarter camera whose angle is authored
## per location (`CameraRig`, offset (3.4, 6.4, 3.4)). The lab works the same way: each
## room asks for its own framing (`set_framing`), the camera glides to it, and walking
## is relative to where the camera looks. Deliberately not the game's `PlayerController`
## / `CameraRig`: the lab must not depend on (or change) production code, so this is a
## small stand-in with the same habits. The character is the game's own protagonist
## scene, instanced read-only; it animates itself from this body's velocity.
##
## The game fades scenery that comes between the camera and the player. The lab's rooms
## are open-topped sets, so its camera simply cranes up over a wall that gets in the way
## and pushes in only if nothing clears even from overhead.
##
## Keys are read directly (not through the project's input map) so nothing here can
## collide with a binding the settings screen owns.
##   WASD / arrows  walk (relative to the camera)    Shift  jog
##   Q / E          turn the view                    wheel  zoom      R  reset the view
##   mouse          orbit while captured (click; Esc releases)
##   F              free camera on/off (WASD fly, Q / E down / up, mouse look)

const TARGET_HEIGHT: float = 1.1
const WALK_SPEED: float = 3.6
const JOG_SPEED: float = 5.6
const TURN_SPEED: float = 12.0
const VIEW_TURN_SPEED: float = 1.6
const FREE_SPEED: float = 7.0
const MOUSE_SENSITIVITY: float = 0.0035
const FRAMING_BLEND: float = 3.5
const CAMERA_MARGIN: float = 0.2
const MIN_CAMERA_DISTANCE: float = 0.9
const PITCH_MIN: float = 5.0
const PITCH_MAX: float = 85.0
const CRANE_STEP: float = 5.0
const CRANE_RISE: float = 10.0
const CRANE_RELEASE: float = 1.5
## The game's own framing: (yaw degrees, pitch degrees, distance) for offset (3.4, 6.4, 3.4).
const GAME_FRAMING := Vector3(45.0, 53.1, 8.0)

## How many times `teleport_by()` moved the visitor (the corridor loop counts on it).
var teleports: int = 0
## True while the camera flies on its own and the character waits.
var free_camera: bool = false
## Last camera distance after the wall ray (for tests and the HUD).
var camera_distance: float = 0.0
## Degrees the camera has craned up above the room's framing to see over a wall.
var crane: float = 0.0

var _framing_target: Vector3 = GAME_FRAMING
var _framing: Vector3 = GAME_FRAMING
var _user_yaw: float = 0.0
var _user_pitch: float = 0.0
var _zoom: float = 1.0
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _animator: Node = null
var _gliding: bool = false
var _move_yaw: float = GAME_FRAMING.x

@onready var visual: Node3D = $Visual
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D


func _ready() -> void:
	camera_rig.top_level = true
	camera.current = true
	for child: Node in visual.get_children():
		if child.has_method("report_velocity"):
			_animator = child
	if _animator != null and _animator.has_method("bind_body"):
		_animator.call("bind_body", self)
	snap_camera()


## The character model (the game's protagonist scene), or null if it failed to load.
func character() -> Node3D:
	return _animator as Node3D


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if free_camera:
			_free_yaw -= motion.relative.x * MOUSE_SENSITIVITY
			_free_pitch = clampf(_free_pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		else:
			_user_yaw -= rad_to_deg(motion.relative.x * MOUSE_SENSITIVITY)
			_user_pitch += rad_to_deg(motion.relative.y * MOUSE_SENSITIVITY)
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom * 0.9, 0.35, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom / 0.9, 0.35, 2.0)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_F:
			set_free_camera(not free_camera)
		KEY_R:
			reset_view()


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
	if free_camera:
		_fly_camera(input, delta)
		input = Vector2.ZERO
	elif Input.is_key_pressed(KEY_Q):
		_user_yaw -= rad_to_deg(VIEW_TURN_SPEED * delta)
	elif Input.is_key_pressed(KEY_E):
		_user_yaw += rad_to_deg(VIEW_TURN_SPEED * delta)
	# While a key is held, "forward" keeps meaning what it meant when you pressed it, even
	# if the next room swings the camera round; it catches up when you let go. Turning the
	# view yourself (Q / E, mouse) steers at once.
	if input == Vector2.ZERO:
		_move_yaw = _framing.x
	var direction := Vector3.ZERO
	if input != Vector2.ZERO:
		var yaw := deg_to_rad(_move_yaw + _user_yaw)
		var forward := -Vector3(sin(yaw), 0.0, cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		direction = (right * input.x - forward * input.y).normalized()
	var speed := JOG_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.8 * delta
	if not _gliding:
		move_and_slide()
		if direction != Vector3.ZERO:
			_face(direction, TURN_SPEED * delta)
	_blend_framing(delta)
	if not free_camera:
		_follow(delta)


# --- Camera -----------------------------------------------------------------------------


## The framing a room asks for: (yaw degrees, pitch degrees, distance). Yaw 0 puts the
## camera south of the character (+Z) looking north; 90 puts it east looking west.
func set_framing(framing: Vector3, instant: bool = false) -> void:
	_framing_target = framing
	if instant:
		_framing = framing
		_move_yaw = framing.x
		if not free_camera:
			_follow()


func get_framing() -> Vector3:
	return _framing_target


## Drops the visitor's own orbit and zoom (R, and every scripted placement).
func reset_view() -> void:
	_user_yaw = 0.0
	_user_pitch = 0.0
	_zoom = 1.0


func set_free_camera(enabled: bool) -> void:
	free_camera = enabled
	if enabled:
		# The rig stops turning; the camera keeps exactly the view it had.
		var view := camera.global_transform
		camera_rig.global_basis = Basis.IDENTITY
		camera.global_transform = view
		var euler := camera.global_basis.get_euler()
		_free_pitch = euler.x
		_free_yaw = euler.y
	else:
		snap_camera()


## A free camera at `eye` looking at `target` (stations and captures); the character
## stays where it is.
func director(eye: Vector3, target: Vector3) -> void:
	set_free_camera(true)
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
	var euler := camera.global_basis.get_euler()
	_free_pitch = euler.x
	_free_yaw = euler.y


## Puts the camera where the framing wants it, with no blending.
func snap_camera() -> void:
	_framing = _framing_target
	_move_yaw = _framing.x
	if not free_camera:
		_follow()


func _blend_framing(delta: float) -> void:
	var weight := 1.0 - exp(-FRAMING_BLEND * delta)
	var yaw := lerp_angle(deg_to_rad(_framing.x), deg_to_rad(_framing_target.x), weight)
	_framing.x = rad_to_deg(yaw)
	_framing.y = lerpf(_framing.y, _framing_target.y, weight)
	_framing.z = lerpf(_framing.z, _framing_target.z, weight)


## `delta` < 0: jump straight to the answer (placements, snaps).
func _follow(delta: float = -1.0) -> void:
	var yaw := deg_to_rad(_framing.x + _user_yaw)
	var base := clampf(_framing.y + _user_pitch, PITCH_MIN, PITCH_MAX)
	var distance := _framing.z * _zoom
	var focus := global_position + Vector3(0.0, TARGET_HEIGHT, 0.0)
	# The rooms are open-topped sets. When a wall stands between the character and the
	# camera, the camera cranes up over it, the way a stage is watched from the flies,
	# rather than pushing into the back of the character's head.
	var needed := base
	while needed < PITCH_MAX and not _ray(focus, focus + _orbit(yaw, needed, distance)).is_empty():
		needed = minf(needed + CRANE_STEP, PITCH_MAX)
	var target_crane := needed - base
	if delta < 0.0:
		crane = target_crane
	else:
		var rate := CRANE_RISE if target_crane > crane else CRANE_RELEASE
		crane = lerpf(crane, target_crane, 1.0 - exp(-rate * delta))
	var offset := _orbit(yaw, minf(base + crane, PITCH_MAX), distance)
	var wanted := focus + offset
	# Whatever is still in the way (rising, or nothing clears even overhead): push in.
	var hit := _ray(focus, wanted)
	if not hit.is_empty():
		var reach := maxf(
			MIN_CAMERA_DISTANCE, focus.distance_to(hit["position"] as Vector3) - CAMERA_MARGIN
		)
		wanted = focus + offset.normalized() * reach
	camera_rig.global_position = wanted
	camera.position = Vector3.ZERO
	camera_distance = focus.distance_to(wanted)
	if not wanted.is_equal_approx(focus):
		camera_rig.look_at(focus, Vector3.UP)
	camera.rotation = Vector3.ZERO


func _orbit(yaw: float, pitch_degrees: float, distance: float) -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _fly_camera(input: Vector2, delta: float) -> void:
	camera.global_basis = Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0.0))
	var move := camera.global_basis * Vector3(input.x, 0.0, input.y)
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if move.length_squared() > 0.0:
		var fast := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		camera.global_position += move.normalized() * FREE_SPEED * fast * delta


# --- Placement --------------------------------------------------------------------------


## Stands the character at `feet`, turned toward `target`, and puts the camera behind
## it in the room's framing. Used by the stations, the captures and the test.
func place(feet: Vector3, target: Vector3) -> void:
	free_camera = false
	_gliding = false
	global_position = feet
	velocity = Vector3.ZERO
	reset_view()
	var toward := target - feet
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		_face(toward, 1.0)
	if _animator != null:
		_animator.call("clear_reported_velocity")
	reset_physics_interpolation()
	snap_camera()


## Scripted walking (the walkthrough film): moves the character to `feet` over `delta`
## seconds and lets it animate and turn as if it had walked there.
func glide_to(feet: Vector3, delta: float) -> void:
	free_camera = false
	_gliding = true
	var moved := feet - global_position
	moved.y = 0.0
	global_position = feet
	var planar := moved / maxf(delta, 0.0001)
	if planar.length() > 0.05:
		_face(planar, TURN_SPEED * delta)
	if _animator != null:
		_animator.call("report_velocity", planar)


## Ends scripted walking: the character stands, and the keys move it again.
func stop_gliding() -> void:
	_gliding = false
	velocity = Vector3.ZERO
	if _animator != null:
		_animator.call("clear_reported_velocity")


## Moves the visitor by `offset` without turning it, and the camera with it, so the
## view is identical before and after: how the corridor's far door returns you to its
## near end.
func teleport_by(offset: Vector3) -> void:
	global_position += offset
	camera_rig.global_position += offset
	teleports += 1
	reset_physics_interpolation()


func eye_position() -> Vector3:
	return camera.global_position


## Which way the character faces (its model looks down +Z).
func facing() -> Vector3:
	return visual.global_basis.z


func _face(direction: Vector3, weight: float) -> void:
	var target_angle := atan2(direction.x, direction.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_angle, clampf(weight, 0.0, 1.0))
