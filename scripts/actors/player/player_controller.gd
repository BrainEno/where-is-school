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
##
## Animation follows from that, not alongside it: the protagonist model carries a
## `CharacterVisualAnimation`, and this body hands itself to it in `_ready()`. The animator
## reads the velocity `_apply_movement()` leaves behind, so WASD and click-to-move walk with
## the same clip for the same reason — the body moved — and the animator never writes a
## transform, so the facing below stays this controller's alone.

signal path_finished
signal path_cancelled

## The step probe only lifts onto a near-horizontal tread. A continuous stair ramp is
## already a walkable floor; treating its slope as a new step makes the body fight the
## ramp contact and produces a visible vertical wobble.
const STEP_UP_SURFACE_DOT := 0.985

@export_category("Movement")
@export_range(0.5, 12.0, 0.1) var move_speed: float = 3.6
## Speed while the sprint input is held. The model picks it up on its own: above
## `character_visual_animation.gd`'s `jog_speed_threshold` (4.4 m/s) the walk clip becomes
## the jog clip, so the legs follow the body instead of being told separately.
@export_range(1.0, 12.0, 0.1) var jog_speed: float = 5.6
@export_range(1.0, 40.0, 0.5) var acceleration: float = 18.0
@export_range(1.0, 30.0, 0.5) var gravity: float = 9.8
## How quickly the visual turns toward the movement direction.
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 12.0
## How tall a step the body can walk up. `CharacterBody3D` treats every box as a wall,
## so without this a kerb stops the character dead and a click across the street walks
## into it and grinds. Kept equal to the navigation mesh's `agent_max_climb`, because the
## two have to agree: a mesh that promises a taller step than this produces routes the
## character walks into and grinds against, and a mesh that promises less produces routes
## around a kerb the player could have stepped over. The mesh bakes on a 0.25 m grid, so
## the only values that survive the bake are multiples of it, and 0.25 m is one voxel.
@export_range(0.0, 0.6, 0.01) var max_step_height: float = 0.25
## How far past the body's own radius the step probe looks for the surface it is about to
## step onto. A capsule stops when its *edge* touches the step, so the step's face is one
## radius away from the origin: a probe shorter than the radius always lands on the surface
## the body is already standing on, and the step-up never fires. The old probe was a fixed
## 0.30 m against a 0.35 m radius, which is why every kerb in the game was a wall.
const STEP_PROBE_MARGIN := 0.15

@export_category("Camera")
## The rig that frames this body. The offset, the field of view and the aim angle
## live there, not here: the player used to own them, which is why `player.tscn`'s
## `fov` was silently overwritten and why the camera could not move independently
## of the body. A player instantiated without a rig (a placement test, say) still
## walks, on world axes.
@export var camera_rig_path: NodePath = ^"../CameraRig"
## Small roll applied while waking up, in degrees.
@export_range(0.0, 20.0, 0.5) var wake_camera_roll: float = 3.5

@export_category("Wake pose")
## Forward slump of the body mesh while the protagonist is still coming to.
@export_range(0.0, 45.0, 1.0) var wake_tilt_degrees: float = 22.0
## Slump above which the model is *sitting* rather than standing: the protagonist wakes at a
## desk, so the fade-in happens in the seated pose and the settle is the get-up.
const SEATED_WAKE_POSE := 0.5
## The input action that asks for `jog_speed`.
const SPRINT_ACTION := &"sprint"

@onready var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
@onready var visual_pivot: Node3D = %VisualPivot
## The pivot the authored character model hangs from: a `Node3D` at hip height
## (`player.tscn` puts it at y = 0.9), with the model as its child. The wake beat
## tilts and lowers this node, so the model moves with it; it is not a mesh any
## more, and the model inside it carries its own foot offset.
@onready var visual: Node3D = %Visual
@onready var navigation_agent: NavigationAgent3D = %NavigationAgent3D

## How close to the requested point counts as arrived.
@export_category("Automatic movement")
@export_range(0.1, 2.0, 0.05) var arrival_radius: float = 0.45
## Any manual input this strong cancels an automatic walk.
@export_range(0.05, 1.0, 0.05) var manual_cancel_threshold: float = 0.2
## Give up on a walk that makes no progress for this long, instead of pressing into a
## wall forever.
@export_range(0.5, 10.0, 0.1) var stall_timeout: float = 2.0
## How close to a corner of the route counts as having reached it. The body then walks
## on to the next leg; the map's route is followed by this body rather than by the
## agent's own index, which lags a frame or two behind the body and can leave a walk
## rocking between two corners it has already passed.
@export_range(0.1, 1.5, 0.05) var waypoint_radius: float = 0.35

var _control_enabled: bool = true
## Whether the wake beat currently has the model seated. Mirrors the model's own state so a
## repeated `set_wake_pose(1.0)` does not restart the sit or the get-up.
var _wake_seated: bool = false
## Measured from the capsule in `_ready()`, not exported: it is the scene's shape.
var _body_radius: float = 0.4
var _facing_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _path_active: bool = false
var _path_target: Vector3 = Vector3.ZERO
var _path_progress_elapsed: float = 0.0
## How many times the current walk may ask the map for a fresh route after stalling before
## it gives up. One: a body that catches on a corner it was routed too tightly around can
## still walk the same destination from where it actually stands, and a route asked for
## from the wall the body is pressed against is a different route. A body that stalls
## twice has found something a second route does not fix.
var _stall_repaths_left: int = 0
var _path_last_position: Vector3 = Vector3.ZERO
## The route the navigation map returned for the current request, in order.
var _path_legs := PackedVector3Array()
## Which leg of that route the body is walking towards.
var _path_index: int = 0
## The protagonist model's idle/walk animator, found under `%Visual`.
var _character_animator: CharacterVisualAnimation = null


func _ready() -> void:
	_body_radius = _measure_body_radius()
	_character_animator = _find_character_animator()
	if _character_animator != null:
		_character_animator.bind_body(self)
	elif visual != null:
		push_warning("PlayerController: the model under %Visual has no CharacterVisualAnimation; the protagonist will not animate.")


func _find_character_animator() -> CharacterVisualAnimation:
	if visual == null:
		return null
	for node in visual.find_children("*", "Node3D", true, false):
		var animator := node as CharacterVisualAnimation
		if animator != null:
			return animator
	return null


## The protagonist's idle/walk animator, or null if the model has none.
func get_character_animator() -> CharacterVisualAnimation:
	return _character_animator


## The radius of the capsule the character is standing in, read once: it is what decides
## where the step probe has to look, and it is a property of the scene, not of the frame.
func _measure_body_radius() -> float:
	for child in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.disabled:
			continue
		var capsule := shape_node.shape as CapsuleShape3D
		if capsule != null:
			return capsule.radius
	return 0.4


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


## The speed `_apply_movement()` aims for right now: `move_speed`, or `jog_speed` while the
## sprint input is held. Public so the difference can be asserted without a floor to run on.
func target_speed() -> float:
	return jog_speed if Input.is_action_pressed(SPRINT_ACTION) else move_speed


## Turns stick input into a camera-relative world direction.
func _camera_relative(input_vector: Vector2) -> Vector3:
	var camera_right := camera_rig.planar_right() if camera_rig != null else Vector3.RIGHT
	var camera_forward := camera_rig.planar_forward() if camera_rig != null else Vector3.FORWARD

	var direction := (camera_right * input_vector.x + camera_forward * -input_vector.y)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


## The one place velocity is written. Manual and automatic movement share it so the
## character accelerates, slides and turns exactly the same way either way.
func _apply_movement(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.0001:
		_facing_direction = direction

	var speed := target_speed()
	var target_x := direction.x * speed
	var target_z := direction.z * speed

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
## Anything taller — a desk, a wall — still stops the character. The probe uses the
## body's collision mask and only accepts a horizontal tread: a smooth ramp is already
## walkable and must not be repeatedly lifted by this curb helper.
func _try_step_up(motion: Vector3) -> void:
	if max_step_height <= 0.0 or not is_on_floor() or motion.length() < 0.0001:
		return
	if not test_move(global_transform, motion):
		return
	var raised := global_transform.translated(Vector3.UP * max_step_height)
	if test_move(raised, motion):
		return
	# Past the body's edge, not from the middle of it: see `STEP_PROBE_MARGIN`.
	var reach := maxf(_body_radius + STEP_PROBE_MARGIN, motion.length() + STEP_PROBE_MARGIN)
	var ahead := motion.normalized() * reach
	var from := global_position + Vector3.UP * max_step_height + ahead
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3.UP * max_step_height * 2.0, collision_mask
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	if hit_normal.dot(Vector3.UP) < STEP_UP_SURFACE_DOT:
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
	# The first point is where the body already is.
	_path_index = 1
	_path_progress_elapsed = 0.0
	_stall_repaths_left = 1
	_path_last_position = global_position
	navigation_agent.target_position = target
	return true


## The route the current walk is following, for tests and diagnostics.
func get_path_legs() -> PackedVector3Array:
	return _path_legs


func get_path_index() -> int:
	return _path_index


func cancel_path() -> void:
	if not _path_active:
		return
	_path_active = false
	_path_legs = PackedVector3Array()
	_path_index = 0
	_stall_repaths_left = 0
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
	if _flat_distance(_path_target) <= arrival_radius:
		_finish_path()
		return Vector3.ZERO
	if _path_legs.size() < 2:
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
			# A route that rounds a corner more tightly than the body can follow presses
			# the body into the wall it should have walked around, and the body stops
			# without being anywhere it cannot go. Asking the map again from where the
			# body actually is gives a route around *that* corner; if the fresh route
			# stalls too, the walk ends as it always did.
			if _stall_repaths_left > 0:
				# Cleared before the fresh request: that request resets the budget for a
				# walk somebody asked for, and a walk that keeps re-routing itself is a
				# walk that never gives up.
				_stall_repaths_left = 0
				_path_progress_elapsed = 0.0
				if request_path_to(_path_target):
					return Vector3.ZERO
			_abort_path()
			return Vector3.ZERO

	# Walk the route: every corner the body has reached is dropped. The route comes
	# from the navigation map, so it already bends around everything the map knows
	# about; following it in order keeps a walk from turning back on itself.
	var here := Vector3(global_position.x, 0.0, global_position.z)
	while _path_index < _path_legs.size() - 1:
		var leg := Vector3(_path_legs[_path_index].x, 0.0, _path_legs[_path_index].z)
		if leg.distance_to(here) <= waypoint_radius:
			_path_index += 1
		else:
			break

	var next_point := _path_legs[_path_index]
	var to_next := next_point - global_position
	to_next.y = 0.0
	if to_next.length() < 0.05:
		# Standing on the last corner: the target itself is the only thing left.
		var to_target := _path_target - global_position
		to_target.y = 0.0
		return to_target.normalized() if to_target.length() > 0.05 else Vector3.ZERO
	return to_next.normalized()


func _finish_path() -> void:
	_path_active = false
	_path_legs = PackedVector3Array()
	_path_index = 0
	if navigation_agent != null:
		navigation_agent.target_position = global_position
	path_finished.emit()


func _abort_path() -> void:
	_path_active = false
	_path_legs = PackedVector3Array()
	_path_index = 0
	_stall_repaths_left = 0
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
##
## The pivot tilt and sink are the *whole* body moving; the model's own clips are what the
## body is doing. Above `SEATED_WAKE_POSE` the protagonist is sitting at the desk (the take
## opens asleep over it), and coming back to 0 is the get-up, so the two halves happen
## together instead of the model standing in the seated pose while the pivot straightens.
func set_wake_pose(amount: float) -> void:
	if visual == null:
		return
	var clamped := clampf(amount, 0.0, 1.0)
	visual.rotation_degrees.x = wake_tilt_degrees * clamped
	visual.position.y = 0.9 - 0.06 * clamped
	_set_wake_seated(clamped >= SEATED_WAKE_POSE)


func settle_wake_pose(duration: float) -> void:
	if visual == null:
		return
	_set_wake_seated(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "rotation_degrees:x", 0.0, duration)
	tween.tween_property(visual, "position:y", 0.9, duration)
	await tween.finished


## Moves the model between the seated pose and the get-up. Ignored on a model that has no
## animation driver (a placement test's capsule, or a rigless preview), so the wake beat
## never depends on the character assets being there.
func _set_wake_seated(seated: bool) -> void:
	if seated == _wake_seated:
		return
	_wake_seated = seated
	var wrapper := _animation_wrapper()
	if wrapper == null:
		return
	wrapper.call("set_seated", seated)
	if not seated:
		wrapper.call("play_action", "get_up")


## The model's animation driver, if the visual has one. Found by what it can do rather than
## by node name, because `player.tscn` names it `Model` and a test may not.
func _animation_wrapper() -> Node:
	if visual == null:
		return null
	for child in visual.get_children():
		if child.has_method("set_seated") and child.has_method("play_action"):
			return child
	return null


## The wake beat rolls the view. The rig owns the roll; the player keeps the two
## entry points the director already calls, so the sequencing code did not have to
## learn a second node name.
func set_camera_roll(degrees: float) -> void:
	if camera_rig != null:
		camera_rig.set_roll(degrees)


func settle_camera_roll(duration: float) -> void:
	if camera_rig == null:
		return
	await camera_rig.settle_roll(duration)


func teleport(target: Transform3D) -> void:
	# A teleport means a location change: any walk being followed belongs to the old
	# scene's navigation map.
	cancel_path()
	global_position = target.origin
	velocity = Vector3.ZERO
	if not target.basis.is_equal_approx(Basis.IDENTITY):
		_facing_direction = -target.basis.z
	# Snap the view in the same frame as the body: a camera that arrives a frame
	# late is a camera that spends a frame inside the wall the player just left.
	if camera_rig != null:
		camera_rig.snap()
