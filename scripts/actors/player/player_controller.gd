extends CharacterBody3D
class_name PlayerController
## Camera-relative movement for the 2.5D presentation.
##
## The body never rotates: the camera keeps its authored angle and the visual
## pivot turns to face the direction of travel. Movement can be locked by the
## sequence director (during the wake beat and while dialogue is open) without
## the player losing their physical position.
##
## There is **one** movement implementation. Manual (WASD) and automatic
## (click-to-move) input both end up in `_apply_movement()`: same acceleration, same
## `move_and_slide()`, same facing. Automatic movement only decides which direction to
## ask for, by following the `NavigationAgent3D` path this body owns.

signal path_finished
signal path_cancelled

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.6
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8
## How quickly the visual turns toward the movement direction.
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 12.0
## How tall a step the body can walk up. `CharacterBody3D` treats every box as a wall,
## so without this a 15 cm kerb stops the character dead and a click across the street
## walks into it and grinds. Kept equal to the navigation mesh's `agent_max_climb`.
@export_range(0.0, 0.6, 0.01) var max_step_height: float = 0.3

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
@onready var navigation_agent: NavigationAgent3D = %NavigationAgent3D

## How close to the requested point counts as arrived.
@export_category("Automatic movement")
@export_range(0.1, 2.0, 0.05) var arrival_radius: float = 0.45
## Any manual input this strong cancels an automatic walk.
@export_range(0.05, 1.0, 0.05) var manual_cancel_threshold: float = 0.2
## Give up on a walk that makes no progress for this long, instead of pressing into a
## wall forever.
@export_range(0.5, 10.0, 0.1) var stall_timeout: float = 2.0

var _control_enabled: bool = true
var _camera_roll: float = 0.0
var _facing_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _path_active: bool = false
var _path_target: Vector3 = Vector3.ZERO
var _path_progress_elapsed: float = 0.0
var _path_last_position: Vector3 = Vector3.ZERO
## The route this body asked the map for, kept for the frames before the agent has a
## path of its own.
var _path_legs := PackedVector3Array()
## Whether the agent has produced a path for the current request. Until it has, it
## reports "navigation finished", which must not be mistaken for arrival.
var _path_armed := false
## Seconds since the current request, used to stop waiting for an agent that never
## answers.
var _path_age: float = 0.0


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

	if _path_active and input_vector.length() > manual_cancel_threshold:
		# A hand on the keys always wins over an automatic walk.
		cancel_path()

	var move_direction := Vector3.ZERO
	if _path_active:
		move_direction = _path_direction(delta)
	elif input_vector.length_squared() > 0.0001:
		move_direction = _camera_relative(input_vector)

	_apply_movement(move_direction, delta)


## Turns stick input into a camera-relative world direction.
func _camera_relative(input_vector: Vector2) -> Vector3:
	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var direction := (camera_right * input_vector.x + camera_forward * -input_vector.y)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


## The one place velocity is written. Manual and automatic movement share it so the
## character accelerates, slides and turns exactly the same way either way.
func _apply_movement(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.0001:
		_facing_direction = direction

	var target_x := direction.x * move_speed
	var target_z := direction.z * move_speed

	velocity.x = move_toward(velocity.x, target_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	_try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	move_and_slide()
	_update_visual_facing(delta)


## Lifts the body onto a low step instead of letting it press against one.
##
## Only when the body is on the floor, moving, and actually blocked: the block has to
## be low enough to step over (a kerb, a threshold) and there has to be room above it.
## Anything taller — a desk, a wall — still stops the character.
func _try_step_up(motion: Vector3) -> void:
	if max_step_height <= 0.0 or not is_on_floor() or motion.length() < 0.0001:
		return
	if not test_move(global_transform, motion):
		return
	var raised := global_transform.translated(Vector3.UP * max_step_height)
	if test_move(raised, motion):
		return
	var ahead := motion.normalized() * maxf(0.3, motion.length() + 0.15)
	var from := global_position + Vector3.UP * max_step_height + ahead
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3.UP * max_step_height * 2.0
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var rise := float(hit["position"].y) - global_position.y
	if rise <= 0.02 or rise > max_step_height:
		return
	global_position.y += rise + 0.01


func _update_visual_facing(delta: float) -> void:
	if visual_pivot == null:
		return
	var target_angle := atan2(_facing_direction.x, _facing_direction.z)
	visual_pivot.rotation.y = lerp_angle(visual_pivot.rotation.y, target_angle, turn_speed * delta)


# --- Automatic movement -----------------------------------------------------


## Asks to walk to `destination` along the navigation map.
##
## Returns false when the request cannot be honoured — control is locked, there is no
## navigation map, the point is off the mesh, or there is no route — so callers can
## react instead of watching the character walk into a wall. A false return leaves any
## previous walk untouched; call `cancel_path()` first if that is not what you want.
func request_path_to(destination: Vector3) -> bool:
	if not _control_enabled or navigation_agent == null:
		return false
	var map := navigation_agent.get_navigation_map()
	if not _map_has_geometry(map):
		return false
	var closest := NavigationServer3D.map_get_closest_point(map, destination)
	if Vector2(closest.x - destination.x, closest.z - destination.z).length() > 0.75:
		return false
	if absf(closest.y - destination.y) > 1.5:
		# A point well above or below the mesh is not a place to walk to: without this
		# a request fifteen metres in the air would collapse onto the floor below and
		# look like it had been accepted.
		return false
	var target := Vector3(closest.x, destination.y + 0.05, closest.z)
	if _flat_distance(target) <= arrival_radius:
		# Already standing there: nothing to walk, but the request is satisfied.
		_path_target = target
		_finish_path()
		return true
	var path := NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2:
		return false
	_path_active = true
	_path_target = target
	_path_legs = path
	_path_armed = false
	_path_age = 0.0
	_path_progress_elapsed = 0.0
	_path_last_position = global_position
	navigation_agent.target_position = target
	return true


func cancel_path() -> void:
	if not _path_active:
		return
	_path_active = false
	if navigation_agent != null:
		# Pointing the agent at the body clears the path it is holding.
		navigation_agent.target_position = global_position
	path_cancelled.emit()


func is_path_active() -> bool:
	return _path_active


func get_path_target() -> Vector3:
	return _path_target


## Direction to ask for this frame while following the navigation path. Ends the walk
## (with the matching signal) when it has arrived, lost its path, or stalled.
func _path_direction(delta: float) -> Vector3:
	_path_age += delta
	var remaining := _flat_distance(_path_target)
	if remaining <= arrival_radius:
		_finish_path()
		return Vector3.ZERO

	var agent_path := navigation_agent.get_current_navigation_path()
	if agent_path.size() >= 2:
		_path_armed = true
	var agent_finished := navigation_agent.is_navigation_finished()
	if agent_finished and _path_armed:
		# The agent thinks it is done but the body is not inside the arrival radius:
		# either it stopped at the edge of the mesh or the target drifted. Do not
		# creep towards it in a straight line past geometry.
		_finish_path()
		return Vector3.ZERO
	if agent_finished and _path_age > 0.5:
		# Half a second and the agent still has no path of its own: nothing is coming.
		_finish_path()
		return Vector3.ZERO

	# Progress watchdog, measured by how far the *body* actually moved rather than by
	# the straight-line distance to the target: going around a wall can legitimately
	# take the character away from its destination for a moment.
	var moved := global_position.distance_to(_path_last_position)
	_path_last_position = global_position
	if moved > 0.01:
		_path_progress_elapsed = 0.0
	else:
		_path_progress_elapsed += delta
		if _path_progress_elapsed > stall_timeout:
			_abort_path()
			return Vector3.ZERO

	# Before the agent has answered, follow the first leg of the route this body asked
	# the map for. Waiting instead would leave the character standing on the first
	# frame of every walk that starts before the agent has built its path.
	var next_point: Vector3
	if _path_armed and not agent_finished:
		next_point = navigation_agent.get_next_path_position()
	elif _path_legs.size() >= 2:
		next_point = _path_legs[1]
	else:
		next_point = _path_target
	var to_next := next_point - global_position
	to_next.y = 0.0
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	var step := heading.length() * delta
	if to_next.length() < 0.05:
		# The agent's next point is under the body and it has not advanced yet. Keep the
		# current heading; standing still here would be counted as a stall above.
		return heading.normalized() if heading.length() > 0.2 else Vector3.ZERO
	var just_passed := to_next.dot(heading) < 0.0 and to_next.length() <= maxf(0.35, step * 1.5)
	if heading.length() > 0.2 and just_passed:
		# A point the body has just stepped past. Turning back to touch it is how a
		# character ends up rocking east and west around a corner instead of walking:
		# the agent advances its own index on its next process step, so hold the
		# heading for this frame rather than reversing.
		return heading.normalized()

	return to_next.normalized()


func _finish_path() -> void:
	_path_active = false
	if navigation_agent != null:
		navigation_agent.target_position = global_position
	path_finished.emit()


func _abort_path() -> void:
	_path_active = false
	if navigation_agent != null:
		navigation_agent.target_position = global_position
	path_cancelled.emit()


func _flat_distance(point: Vector3) -> float:
	var delta := point - global_position
	return Vector2(delta.x, delta.z).length()


func _map_has_geometry(map: RID) -> bool:
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_regions(map).size() > 0


# --- Director API -----------------------------------------------------------


## Locked during the wake beat and whenever a presentation is open.
func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if not enabled:
		# Dialogue, a scripted beat or a transition owns the body now; a walk in
		# progress must not resume afterwards.
		cancel_path()


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
	# A teleport means a location change: any walk being followed belongs to the old
	# scene's navigation map.
	cancel_path()
	global_position = target.origin
	velocity = Vector3.ZERO
	if not target.basis.is_equal_approx(Basis.IDENTITY):
		_facing_direction = -target.basis.z
	_apply_camera_transform()
