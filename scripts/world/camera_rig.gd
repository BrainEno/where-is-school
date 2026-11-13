class_name CameraRig
extends Node3D
## The camera as an object of its own, instead of a child of the player.
##
## Two problems came from parenting the camera to the body:
##
## 1. **The framing was a property of the player.** The only way to move the
##    camera was to move the body, so a cut, a nudge for a close-up, or a shake had
##    nowhere to live.
## 2. **The field of view had two sources.** `player.tscn` declared `fov = 58.0`
##    and `PlayerController` overwrote it with `camera_fov = 60.0` every time it
##    touched the transform, so the scene value was dead config: a number an author
##    could edit with no effect. One of them had to go, and it is not the one in the
##    scene.
##
## The rig owns the camera, the offset, the field of view and the roll. It follows
## the target's *position* once per physics frame - after the body has moved, since
## the rig is a later sibling - and keeps its own orientation: the framed angle is
## authored, not derived from where the player happens to be facing.
##
## It follows a position rather than a transform on purpose. A rig that inherited
## the body's rotation would swing the camera every time the character turned,
## which is the behaviour this exists to avoid.
##
## A beat can borrow the framing for a moment (`frame_point`): the rig glides off the
## target to a point in the world and back again (`release_frame`). The angle and the
## distance never change, only what the camera is centred on - a staged discovery shows
## the player where to look without cutting away from the game camera.

## What the rig frames. The player, in the game scene.
@export var target_path: NodePath = ^"../Player"
## Where the camera sits, relative to the target, in world axes.
@export var offset: Vector3 = Vector3(3.4, 6.4, 3.4)
## The one field of view in the project. Any other `fov` is a bug.
@export_range(30.0, 90.0, 1.0) var fov: float = 60.0
## Height above the target's origin the camera looks at.
@export var target_height: float = 0.9

@onready var camera: Camera3D = %Camera3D

var _target: Node3D = null
var _roll_degrees: float = 0.0
## Where a beat wants the view centred, and how far the view has moved there from the
## target (0 = on the target, the normal state; 1 = on the point).
var _frame_point := Vector3.ZERO
var _frame_weight := 0.0
var _frame_tween: Tween = null


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("CameraRig: target_path '%s' did not resolve." % target_path)
	if camera == null:
		push_error("CameraRig: no Camera3D child; the rig cannot frame anything.")
		return
	snap()


## What the rig follows (the player in the game). Scenery that has no collider - and so
## is invisible to the occluder fader - can ask whose view it might be blocking.
func get_target() -> Node3D:
	return _target


## Puts the rig on the target and aims the camera at it. Called once per physics
## frame, and directly after a teleport so the camera never spends a frame on the
## far side of a wall the player has already left.
func snap() -> void:
	if _target == null or camera == null:
		return
	var anchor := _target.global_position
	if _frame_weight > 0.0:
		anchor = anchor.lerp(_frame_point, _frame_weight)
	global_position = anchor
	camera.position = offset
	camera.fov = fov
	camera.look_at(anchor + Vector3(0.0, target_height, 0.0), Vector3.UP)
	if not is_zero_approx(_roll_degrees):
		camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(_roll_degrees))


func _physics_process(_delta: float) -> void:
	# The body moves in its own `_physics_process`, which runs first because the rig
	# is a later sibling. Following here therefore reads this frame's position, not
	# the previous one, and the rendered frame is the one the player is standing in.
	snap()


## Roll in degrees around the view axis, used by the wake beat.
func set_roll(degrees: float) -> void:
	_roll_degrees = degrees
	snap()


func get_roll() -> float:
	return _roll_degrees


## Unwinds the roll over `duration` seconds.
func settle_roll(duration: float) -> void:
	if duration <= 0.0 or is_zero_approx(_roll_degrees):
		set_roll(0.0)
		return
	var tween := create_tween()
	tween.tween_method(set_roll, _roll_degrees, 0.0, duration)
	await tween.finished


## Glides the view off the target until it is centred on `point` (a floor point; the
## usual `target_height` is added), over `duration` seconds. Awaitable. The target is
## still followed underneath, so the view comes back to wherever it is now.
func frame_point(point: Vector3, duration: float) -> void:
	_frame_point = point
	await _glide_frame(1.0, duration)


## Gives the view back to the target. Awaitable; 0 seconds is a cut.
func release_frame(duration: float) -> void:
	await _glide_frame(0.0, duration)


## 0 while the camera is on its target, 1 while a beat holds it on a point.
func get_frame_weight() -> float:
	return _frame_weight


func _glide_frame(weight: float, duration: float) -> void:
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = null
	if duration <= 0.0 or not is_inside_tree():
		_set_frame_weight(weight)
		return
	_frame_tween = create_tween()
	_frame_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_frame_tween.tween_method(_set_frame_weight, _frame_weight, weight, duration)
	await _frame_tween.finished


func _set_frame_weight(weight: float) -> void:
	_frame_weight = clampf(weight, 0.0, 1.0)
	snap()


## The horizontal axis the camera shows as "right", which is the axis player
## movement is expressed in. Falls back to world axes when the rig has no camera,
## so a scene that instantiates the player without one still moves.
func planar_right() -> Vector3:
	if camera == null:
		return Vector3.RIGHT
	var right := camera.global_basis.x
	right.y = 0.0
	return right.normalized()


## The horizontal axis the camera shows as "forward" (away from the viewer).
func planar_forward() -> Vector3:
	if camera == null:
		return Vector3.FORWARD
	var forward := -camera.global_basis.z
	forward.y = 0.0
	return forward.normalized()
