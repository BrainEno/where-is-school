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
## The current walk stalled, asked the map for a fresh route from where the body stands,
## and got one. At most `STALL_REPATHS_PER_WALK` times per requested walk.
signal path_rerouted

## How many fresh routes one requested walk may ask for after stalling. See
## `_stall_repaths_left`.
const STALL_REPATHS_PER_WALK := 1

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
## A deliberate stand takes 0.75 s, including the whole profiled get_up clip. The
## animator normalizes its actual length (2.025 s on this rig), not just the pivot.
const WAKE_GET_UP_SECONDS := 0.75
## The hip height the model hangs at when standing (`player.tscn` puts `Visual` at y = 0.9).
##
## The seated pose is 0.06 m below that, not 0.45 m: the *clip* folds the legs and the
## pelvis stays where the pivot holds it. That is only right while the body is a seated
## silhouette with nothing behind it. Once the chair is geometry the body can be compared
## to, the hip has to travel the real distance between `sit_idle`'s thigh angle and the
## standing one, or the shins sweep through the seat while the pivot barely moves.
const STANDING_HIP_HEIGHT := 0.9
## How far the body sinks below `STANDING_HIP_HEIGHT` in the seated pose.
##
## This is a *slump*, not a descent to seat height, and the difference cost a working build
## to learn: `%Visual` carries the whole body, with the model hung 0.9 m under it so its feet
## sit at y = 0. Lowering the node is lowering the character into the floor. A drop sized to
## the seat (0.42 m - what it takes to put a pelvis on a 0.45 m seat) drove the feet that far
## under the ground and the model through it, while the pelvis was computed to be in exactly
## the right place.
##
## The chair is met by the *clip*: `sit_idle` folds the legs and puts the body in the chair,
## and the pivot only adds the slump on top of that. Six centimetres is that slump.
const SEATED_HIP_DROP := 0.06
## The hip's rise across the stand-up, as (fraction of the clip, fraction of the total rise).
##
## A sine curve - the obvious choice, and the one this used - is wrong here because the hips
## do not rise at a constant share of the clock: they rise *with the legs*. The clip spends
## its first half unfolding the knees to roughly half-straight, which lifts the pelvis most
## of the way, and its second half straightening the last few degrees and bringing the spine
## upright, which barely lifts it at all.
##
## What matters here is the *shape*, not the metres: the rise is front-loaded, because the
## knees unfold before the spine straightens. A sine puts its fastest rise in the middle
## instead, which draws the body hanging in the air through the first third of the stand.
## These keys put most of whatever rise there is in that first half, where the legs work.
const HIP_RISE_KEYS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.467, 0.78),
	Vector2(1.0, 1.0),
]

## The chair the protagonist wakes up in, and the one thing that makes the stand-up possible.
##
## Found by the node group the classroom puts on it rather than by a path: this controller is
## on the player, in another scene, and a hard path into a room's furniture would be wrong for
## every other room.
const SEATED_CHAIR_GROUP := &"seated_chair"
## How long the chair takes to slide out from under the body at the start of the stand-up.
##
## Shorter than the stand itself (0.75 s): the chair leaves in the first half, while the body
## is still folded over its feet and the legs are unloading, which is when a real chair
## actually goes. A chair that kept travelling after the body was upright would look pushed.
const CHAIR_PUSH_SECONDS := 0.35
## How long the chair takes to come back under a body that is sitting down again.
##
## Longer, and it runs *after* the body has mostly lowered: a chair is pulled in behind you,
## not slid under you while you are still in the air.
const CHAIR_PULL_SECONDS := 0.45
## How long the hand takes to get to the chair before it starts moving, and to leave it after.
##
## The hand arrives first and leaves last: a chair that moves with no hand on it is a chair
## being pushed by the air. Short, because a person does not reach slowly for a chair they are
## already touching - the reach is the *look* of taking hold, not a journey.
const CHAIR_REACH_SECONDS := 0.18
## A beat after the chair arrives before the sit is considered over, so a caller does not get
## control back on the same frame the chair stops.
const CHAIR_PULL_SETTLE_SECONDS := 0.08
## The input action that asks for `jog_speed`.
const SPRINT_ACTION := &"sprint"
## In toggle mode, a jog that was switched on ends by itself after the player has stood
## still this long, so walking off after a conversation or a look around is a walk again.
const SPRINT_LATCH_IDLE_SECONDS := 0.6

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
## Standing up owns horizontal movement until BOTH bones and pivot are upright.
## The pending path remains live, but its corners/watchdog are not advanced.
var _getting_up: bool = false
var _get_up_animated: bool = false
var _get_up_elapsed: float = 0.0
var _get_up_tilt: float = 0.0
var _get_up_height: float = STANDING_HIP_HEIGHT
## How far through the clip the pose is, kept so the tail of the stand-up and the completion
## signal can both find it without recomputing the clock.
var _get_up_progress: float = 0.0
## The chair this body wakes up in, if the room has one to push. Resolved on the way up, not
## in `_ready()`: the player exists before the location is loaded under it.
var _seated_chair: Node3D = null
## The arm that pushes and draws the chair. Built lazily, and only if the rig has arms.
var _arm_reach: Node = null
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
##
## Only `request_path_to()` - a walk somebody asked for - fills it. The re-route itself
## goes through `_route_to()`, which leaves it alone: a re-route that refilled the budget
## would let a body pressed against something the map does not know about re-route
## forever (#145).
var _stall_repaths_left: int = 0
var _path_last_position: Vector3 = Vector3.ZERO
## The route the navigation map returned for the current request, in order.
var _path_legs := PackedVector3Array()
## Which leg of that route the body is walking towards.
var _path_index: int = 0
## The protagonist model's idle/walk animator, found under `%Visual`.
var _character_animator: CharacterVisualAnimation = null
## How the sprint input works (`Settings.SPRINT_MODES`): "hold" (the default; jog while it
## is down) or "toggle" (one press jogs, the next walks). Followed from the setting.
var sprint_mode: StringName = &"hold"
## In toggle mode: whether the jog is on.
var _sprint_latched := false
## In toggle mode: how long the body has stood still with the jog on.
var _sprint_idle := 0.0


func _ready() -> void:
	_body_radius = _measure_body_radius()
	_character_animator = _find_character_animator()
	if _character_animator != null:
		_character_animator.bind_body(self)
		_character_animator.action_finished.connect(_on_get_up_action_finished)
	elif visual != null:
		push_warning("PlayerController: the model under %Visual has no CharacterVisualAnimation; the protagonist will not animate.")
	_follow_sprint_setting()


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
		# A hand on the keys always wins, including while a path awaits standing.
		cancel_path()
	update_sprint_latch(input_vector, delta)

	if _wake_seated and (input_vector.length_squared() > 0.0001 or _path_active):
		_begin_get_up_from_seat()
	if _getting_up:
		_update_get_up_pose(delta)
		if _getting_up:
			# Do not call _path_direction(): sitting is not a navigation stall, nor
			# permission to skip corners. Keep gravity, but discard residual drift.
			velocity.x = 0.0
			velocity.z = 0.0
			_apply_movement(Vector3.ZERO, delta)
			return

	var move_direction := Vector3.ZERO
	if _path_active:
		move_direction = _path_direction(delta)
	elif input_vector.length_squared() > 0.0001:
		move_direction = _camera_relative(input_vector)

	_apply_movement(move_direction, delta)


## The speed `_apply_movement()` aims for right now: `move_speed`, or `jog_speed` while the
## sprint input is held. Public so the difference can be asserted without a floor to run on.
func target_speed() -> float:
	if sprint_mode == &"toggle":
		return jog_speed if _sprint_latched else move_speed
	return jog_speed if Input.is_action_pressed(SPRINT_ACTION) else move_speed


## Switches between holding the sprint input and pressing it once. Any jog that was on stops.
func set_sprint_mode(mode: StringName) -> void:
	if mode != &"hold" and mode != &"toggle":
		return
	sprint_mode = mode
	_sprint_latched = false
	_sprint_idle = 0.0


## In toggle mode, whether a press has switched the jog on.
func is_sprint_latched() -> bool:
	return _sprint_latched


## Toggle mode: a press flips the jog; standing still for `SPRINT_LATCH_IDLE_SECONDS`, or
## losing control to a conversation or a scene, ends it. Called every physics frame;
## public so a test can drive it with a fake clock and no floor to run on.
func update_sprint_latch(input_vector: Vector2, delta: float) -> void:
	if sprint_mode != &"toggle":
		_sprint_latched = false
		return
	if not _control_enabled:
		_sprint_latched = false
		_sprint_idle = 0.0
		return
	if Input.is_action_just_pressed(SPRINT_ACTION):
		_sprint_latched = not _sprint_latched
		_sprint_idle = 0.0
	if not _sprint_latched:
		return
	if input_vector.length_squared() > 0.0001 or _path_active:
		_sprint_idle = 0.0
		return
	_sprint_idle += delta
	if _sprint_idle >= SPRINT_LATCH_IDLE_SECONDS:
		_sprint_latched = false
		_sprint_idle = 0.0


func _follow_sprint_setting() -> void:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null or not settings.has_method("get_sprint_mode"):
		return
	set_sprint_mode(StringName(settings.call("get_sprint_mode")))
	if not settings.is_connected("setting_changed", _on_setting_changed):
		settings.connect("setting_changed", _on_setting_changed)


func _on_setting_changed(key: StringName) -> void:
	if key == &"sprint_mode" or key == &"all":
		var settings := get_node_or_null(^"/root/Settings")
		if settings != null:
			set_sprint_mode(StringName(settings.call("get_sprint_mode")))


## Turns stick input into a camera-relative world direction.
func _camera_relative(input_vector: Vector2) -> Vector3:
	var camera_right := camera_rig.planar_right() if camera_rig != null else Vector3.RIGHT
	var camera_forward := camera_rig.planar_forward() if camera_rig != null else Vector3.FORWARD

	var direction := (camera_right * input_vector.x + camera_forward * -input_vector.y)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


## How far the body travels between footfalls. The stride is measured against distance
## rather than time on purpose: a walk and a jog move the same feet, so a fixed timer would
## put a jog's steps at the same rate as a walk's and turn fast movement into a slow shuffle.
const STEP_STRIDE_METRES := 1.35
## Below this the body is sliding into place rather than walking: no footstep.
const STEP_MIN_SPEED := 0.35

## Distance travelled since the last footfall was heard.
var _stride_accumulator: float = 0.0


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
	var before := global_position
	move_and_slide()
	_update_visual_facing(delta)
	# Horizontal only: a fall is not a stride, and `velocity.length()` would count the drop.
	var moved := global_position - before
	_track_steps(Vector2(moved.x, moved.z).length())


## Looks the world-audio autoload up by path, the way the interaction cues do: a headless
## test that registers no autoloads gets silence rather than a compile error.
func _play_world_sound(method: String) -> void:
	var audio: Node = get_node_or_null("/root/WorldAudio")
	if audio != null and audio.has_method(method):
		audio.call(method)


## A footstep every `STEP_STRIDE_METRES` of ground covered, and never while standing.
##
## The distance is read from where the body actually ended up, not from `velocity`: a body
## pressed against a wall has velocity and no movement, and footsteps on the spot are the
## classic sign that nobody checked.
func _track_steps(travelled: float) -> void:
	if travelled <= 0.0001 or Vector2(velocity.x, velocity.z).length() < STEP_MIN_SPEED:
		# Standing still resets the stride, so the first step after a stop is immediate
		# rather than arriving after a leftover half stride.
		_stride_accumulator = STEP_STRIDE_METRES
		return
	_stride_accumulator += travelled
	if _stride_accumulator < STEP_STRIDE_METRES:
		return
	_stride_accumulator = 0.0
	_play_world_sound("play_step")


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
	if not _route_to(map, target):
		return false
	# A new walk: it gets its own re-route, whatever the walk it replaces had left.
	_stall_repaths_left = STALL_REPATHS_PER_WALK
	return true


## Asks the map for a route from where the body stands to `target` and starts following
## it. Shared by a requested walk and by the stall re-route; it never touches the re-route
## budget, which belongs to the request (see `_stall_repaths_left`). Returns false, leaving
## the current walk as it was, when the map has no route.
func _route_to(map: RID, target: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2:
		return false
	_path_active = true
	_path_target = target
	_path_legs = path
	# The first point is where the body already is.
	_path_index = 1
	_path_progress_elapsed = 0.0
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
			if _stall_repaths_left > 0 and _reroute():
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


## Spends one re-route on a fresh route to the same target from where the body stands.
## The target is kept as the request settled it: it is already a point on the mesh, so
## it is not snapped (or raised) again. Returns false when there is no route, and the
## caller ends the walk; the re-route is spent either way.
func _reroute() -> bool:
	_stall_repaths_left -= 1
	if not _control_enabled or navigation_agent == null:
		return false
	var map := navigation_agent.get_navigation_map()
	if not _map_has_geometry(map) or not _route_to(map, _path_target):
		return false
	path_rerouted.emit()
	return true


func _finish_path() -> void:
	_path_active = false
	_path_legs = PackedVector3Array()
	_path_index = 0
	_stall_repaths_left = 0
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


## The rule lives in `NavMapUtil`, which the companion and the pointer use too: a walk may
## only be planned on a map that holds geometry (issue #212).
func _map_has_geometry(map: RID) -> bool:
	return NavMapUtil.has_geometry(map)


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
	# The seated amount is a *slump*, and the hip drop is the seat: they run on the same
	# 0..1 dial because at 1.0 the protagonist is asleep over the desk and at
	# `SEATED_WAKE_POSE` he is sitting up in the chair. Below that he is on his feet and the
	# hip is back at the standing height, so the dial is scaled by the seated fraction rather
	# than used raw - otherwise half-asleep would be half a hip below the floor.
	var seated_fraction := clampf(clamped / SEATED_WAKE_POSE, 0.0, 1.0)
	visual.position.y = STANDING_HIP_HEIGHT - SEATED_HIP_DROP * seated_fraction
	_set_wake_seated(clamped >= SEATED_WAKE_POSE)


func settle_wake_pose(duration: float) -> void:
	if visual == null:
		return
	_set_wake_seated(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "rotation_degrees:x", 0.0, duration)
	tween.tween_property(visual, "position:y", STANDING_HIP_HEIGHT, duration)
	await tween.finished


## Straightens the protagonist from the waking slump into an upright seated pose. Returns
## the posture tween so the opening director can keep control locked until it finishes.
func settle_wake_seated_pose(duration: float) -> Tween:
	if visual == null:
		return null
	_set_wake_seated(true)
	var amount := SEATED_WAKE_POSE
	var target_tilt := wake_tilt_degrees * amount
	var target_height := STANDING_HIP_HEIGHT - SEATED_HIP_DROP
	if duration <= 0.0:
		visual.rotation_degrees.x = target_tilt
		visual.position.y = target_height
		return null
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "rotation_degrees:x", target_tilt, duration)
	tween.tween_property(visual, "position:y", target_height, duration)
	return tween


## A deliberate first move gets the protagonist out of the chair, once. Inputs may
## replace/cancel the path during this state, but never restart or accelerate the action.
##
## The stand-up has two halves that used to be one: the *clip* unfolds the legs, and the
## *chair* gets out of the way. The body does not step anywhere - it rises where it sat, and
## the seat slides back out from under it, which is what a person in a classroom chair does
## because 9.7 cm of legroom is not room to stand up in.
##
## The chair is pushed on the same frame the clip starts, and the two clocks run independently
## (the chair is faster, and done first). Waiting for the chair to stop before starting to
## rise would break the beat: the push and the rise are one movement, the legs unloading into
## the chair as the body comes up over them.
func _begin_get_up_from_seat() -> void:
	if not _wake_seated or _getting_up:
		return
	_getting_up = true
	_get_up_elapsed = 0.0
	_get_up_tilt = visual.rotation.x if visual != null else 0.0
	_get_up_height = visual.position.y if visual != null else STANDING_HIP_HEIGHT
	_get_up_progress = 0.0
	_push_seat_back()
	_set_wake_seated(false, WAKE_GET_UP_SECONDS)
	_get_up_animated = _character_animator != null and _character_animator.is_playing_action()


## Drops a stand-up that can no longer be finished where it started.
##
## Deliberately leaves the *pose* alone: this is not "the stand-up finished", it is "there
## is no stand-up any more", and the next thing to set a pose (a wake beat, or the model's
## own idle) owns it from here.
func _abandon_get_up() -> void:
	_getting_up = false
	_get_up_animated = false
	_get_up_elapsed = 0.0
	_get_up_progress = 0.0


func is_getting_up() -> bool:
	return _getting_up


## Whether the body is sitting in a chair right now, i.e. the state the stand-up leaves.
func is_seated() -> bool:
	return _wake_seated


## Sits the protagonist back down in the chair it got up from, if that chair is still there.
##
## Three things move together, because they are one movement:
##
## - the body lowers and folds onto `sit_idle` (the clip holds the folded pose; the tween adds
##   the slump on top of it, so the last frame of the transition is the first frame of the loop);
## - the hand goes back to the chair's back and *draws it in*, then lets go;
## - the chair arrives under the body as the body arrives in it.
##
## Returns a tween that is done when the body is seated and the chair is home, so the room can
## hold its beat until then rather than handing control back in the middle of a sit.
##
## Refused while already seated or still standing up: two transitions running at once is how a
## body ends up halfway into a chair.
func sit_down(duration: float = WAKE_GET_UP_SECONDS) -> Tween:
	if _wake_seated or _getting_up or visual == null:
		return null
	_seated_chair = _find_seated_chair()
	_set_wake_seated(true)
	var chair_tween := _sit_chair_under_body(duration)
	var body_tween := create_tween()
	body_tween.set_parallel(true)
	body_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	body_tween.tween_property(visual, "rotation_degrees:x", wake_tilt_degrees * SEATED_WAKE_POSE, duration)
	body_tween.tween_property(visual, "position:y", STANDING_HIP_HEIGHT - SEATED_HIP_DROP, duration)
	# The whole sit is over when the *chair* is home: the body reaches the seat first, and
	# letting go of the chair is the last thing that happens.
	var total := create_tween()
	total.tween_interval(duration)
	if chair_tween != null:
		total.chain().tween_interval(CHAIR_PULL_SETTLE_SECONDS)
	return total


## Stands the protagonist up out of the chair it is sitting in, for a body that got there by
## sitting rather than by waking up. The mirror of `sit_down`, and refused in the same states.
func stand_up() -> void:
	if not _wake_seated or _getting_up:
		return
	_begin_get_up_from_seat()


## The chair half of a sit-down: hand back to the chair, draw it in under the body, let go.
##
## The hand reaches *first* - it has to already be holding the chair when the chair starts
## moving, or the body is being pushed by a chair nobody is touching.
func _sit_chair_under_body(duration: float) -> Tween:
	if _seated_chair == null:
		return null
	_reach_for_chair()
	# The order is the whole of the performance: take hold, let the body get most of the way
	# down, *then* draw the chair in behind it. Drawing first would slide the chair out from
	# under a body still in the air; drawing late would leave the body landing on nothing.
	var reach_seconds := minf(CHAIR_REACH_SECONDS, duration * 0.25)
	var settle_seconds := maxf(duration * SEATED_WAKE_POSE - CHAIR_REACH_SECONDS, 0.0)
	var pull_seconds := minf(CHAIR_PULL_SECONDS, maxf(duration - reach_seconds - settle_seconds, 0.05))
	var tween := create_tween()
	tween.tween_interval(reach_seconds)
	tween.tween_interval(settle_seconds)
	tween.tween_callback(_pull_seat_home)
	# The hand stays on the chair for as long as the chair is travelling.
	tween.tween_interval(pull_seconds)
	tween.tween_callback(_release_chair)
	return tween


## One clock, not a separate tween racing the profiled skeleton. Physics samples the
## action; its actual completion signal snaps the pivot's final pose before movement
## may resume. The timed fallback is only for rigless placement/preview fixtures.
##
## This sets the *visual* pose only. The body's own travel is applied by the caller, after
## `move_and_slide()`: this runs before it, and a position written here would be recomputed
## away by the physics step every frame.
func _update_get_up_pose(delta: float) -> void:
	_get_up_elapsed += delta
	var progress := clampf(_get_up_elapsed / WAKE_GET_UP_SECONDS, 0.0, 1.0)
	if _get_up_animated:
		progress = _character_animator.get_action_progress()
	_get_up_progress = progress
	if visual != null:
		var weight := 0.5 - cos(PI * progress) * 0.5
		visual.rotation.x = lerpf(_get_up_tilt, 0.0, weight)
		visual.position.y = lerpf(_get_up_height, STANDING_HIP_HEIGHT, _hip_rise_weight(progress))
	if progress >= 1.0:
		_finish_get_up()


## How much of the hip's rise has happened by `progress` of the stand-up.
##
## A sine curve - the obvious choice, and the one this used - is wrong here because the
## hips do not rise at a constant share of the clock: they rise *with the legs*. The clip
## spends its first half unfolding the knees to roughly half-straight, which lifts the
## pelvis most of the way, and its second half straightening the last few degrees and
## bringing the spine upright, which barely lifts it at all.
##
## Sampling the clip's own thigh and shin keys gives the shape the skeleton expects: the
## hip is at ~0.51 m when the legs are folded, ~0.79 m at the half-way key, and 0.90 m
## standing. The sine sat 12 cm below that through the middle of the movement, which is
## what made the feet sink and the knees drop: the legs were being straight, and were
## being drawn as a body in a hole. These three numbers are that curve, normalised.
func _hip_rise_weight(progress: float) -> float:
	var clamped := clampf(progress, 0.0, 1.0)
	for index in range(HIP_RISE_KEYS.size() - 1):
		var a := HIP_RISE_KEYS[index]
		var b := HIP_RISE_KEYS[index + 1]
		if clamped <= b.x:
			var span := maxf(b.x - a.x, 0.0001)
			var local := (clamped - a.x) / span
			# Smoothstep inside the segment, so the two halves meet without a crease.
			var eased := local * local * (3.0 - 2.0 * local)
			return lerpf(a.y, b.y, eased)
	return HIP_RISE_KEYS[-1].y


## Pushes the chair the body woke in back out of the way, once.
##
## Silent when the room has no chair for this body (`_find_seated_chair` returns null): a
## fixture that drops a `PlayerController` into an empty scene still gets a working stand-up,
## it just does not move furniture that is not there.
func _push_seat_back() -> void:
	_seated_chair = _find_seated_chair()
	if _seated_chair == null:
		return
	# The hand is on the chair before it moves, and stays on it until it stops: the push is
	# what the arm is *doing*, not something that happens to the chair nearby.
	_reach_for_chair()
	if _seated_chair.has_method("push_back"):
		_seated_chair.call("push_back", CHAIR_PUSH_SECONDS)
	var tween := create_tween()
	tween.tween_interval(CHAIR_PUSH_SECONDS + CHAIR_REACH_SECONDS * 0.5)
	tween.tween_callback(_release_chair)


## Pulls that same chair back under the body, for a sit-down.
func _pull_seat_home() -> void:
	if _seated_chair == null:
		_seated_chair = _find_seated_chair()
	if _seated_chair == null:
		return
	if _seated_chair.has_method("pull_home"):
		_seated_chair.call("pull_home", CHAIR_PULL_SECONDS)
	# The chair is what makes the sound here, not the body: a chair drawn in under
	# someone is wood on wood, and it is the loudest thing in the wake sequence.
	_play_world_sound("play_chair")


## Puts a hand on the chair's back and keeps it there while the chair moves.
##
## The target is the chair's own back, read from the chair rather than assumed: the reach has
## to end where the chair is, or the body is holding the air beside it.
func _reach_for_chair() -> void:
	var reach := _ensure_arm_reach()
	if reach == null or _seated_chair == null:
		return
	var at := _seated_chair.global_position
	if _seated_chair.has_method("get_back_point"):
		at = _seated_chair.call("get_back_point")
	# The choreography of a hand on a prop lives in the reach itself; this only says which
	# point of which chair.
	reach.call("take_hold", at, CHAIR_REACH_SECONDS)


## Lets go: the arm eases back under the clip's control.
func _release_chair() -> void:
	if _arm_reach == null or not is_instance_valid(_arm_reach):
		return
	_arm_reach.call("let_go", CHAIR_REACH_SECONDS)


## The reach, built on first use against this body's model.
func _ensure_arm_reach() -> Node:
	if _arm_reach != null and is_instance_valid(_arm_reach):
		return _arm_reach
	if _character_animator == null:
		return null
	var reach := preload("res://scripts/actors/character_arm_reach.gd").new()
	reach.name = "ArmReach"
	# A child of the controller, not of the model: the model may be replaced by a look
	# treatment, and the reach has to survive that.
	add_child(reach)
	if not bool(reach.call("bind", _character_animator)):
		reach.queue_free()
		return null
	_arm_reach = reach
	return _arm_reach


## The chair nearest this body, found by group so no scene path is hard-coded.
##
## Nearest, not first: a room may have a chair per desk, and the one to push is the one the
## body is standing in front of.
func _find_seated_chair() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(SEATED_CHAIR_GROUP):
		var chair := node as Node3D
		if chair == null or not chair.is_inside_tree():
			continue
		var distance := chair.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = chair
	return best


func _on_get_up_action_finished(clip_name: StringName) -> void:
	if _getting_up and clip_name == &"get_up":
		_finish_get_up()


func _finish_get_up() -> void:
	if visual != null:
		visual.rotation.x = 0.0
		visual.position.y = STANDING_HIP_HEIGHT
	_getting_up = false
	_get_up_animated = false


## Moves the model between the seated pose and the get-up. Ignored on a model that has no
## animation driver (a placement test's capsule, or a rigless preview), so the wake beat
## never depends on the character assets being there.
func _set_wake_seated(seated: bool, get_up_duration: float = 0.0) -> void:
	if seated == _wake_seated:
		return
	_wake_seated = seated
	var wrapper := _animation_wrapper()
	if wrapper == null:
		return
	wrapper.call("set_seated", seated)
	if not seated:
		if wrapper is CharacterVisualAnimation:
			(wrapper as CharacterVisualAnimation).play_action("get_up", get_up_duration)
		else:
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


## Turns the body to face `direction` (flattened onto the floor) without moving it or
## touching the camera. The turn is kept: the per-frame facing lerp aims at it too, so a
## staged beat that turns the player is not undone a frame later.
func face_toward(direction: Vector3, snap: bool = true) -> void:
	direction.y = 0.0
	if direction.length() < 0.001:
		return
	_facing_direction = direction.normalized()
	if snap and visual_pivot != null:
		visual_pivot.rotation.y = atan2(_facing_direction.x, _facing_direction.z)


func teleport(target: Transform3D) -> void:
	# A teleport means a location change: any walk being followed belongs to the old
	# scene's navigation map - and so does any stand-up. The stand-up's travel is stored as
	# an offset from where it began, so a body moved while one is still running would be
	# dragged back towards the chair it was teleported away from, one frame later. Drop the
	# travel instead of letting it interpolate from a place the body is no longer in.
	cancel_path()
	# A body that is teleported is a body that is no longer standing up out of that chair.
	# Leaving the stand-up half-run would keep `_update_get_up_pose` owning the pivot and the
	# `get_up` clip playing over a body that has been moved to another part of the room - which
	# is what the capture fixtures do when they place a character for a frame.
	_abandon_get_up()
	global_position = target.origin
	velocity = Vector3.ZERO
	if not target.basis.is_equal_approx(Basis.IDENTITY):
		_facing_direction = -target.basis.z
	# Snap the view in the same frame as the body: a camera that arrives a frame
	# late is a camera that spends a frame inside the wall the player just left.
	if camera_rig != null:
		camera_rig.snap()
