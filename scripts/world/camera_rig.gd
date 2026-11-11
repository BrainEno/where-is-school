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


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("CameraRig: target_path '%s' did not resolve." % target_path)
	if camera == null:
		push_error("CameraRig: no Camera3D child; the rig cannot frame anything.")
		return
	snap()


## Puts the rig on the target and aims the camera at it. Called once per physics
## frame, and directly after a teleport so the camera never spends a frame on the
## far side of a wall the player has already left.
func snap() -> void:
	if _target == null or camera == null:
		return
	global_position = _target.global_position
	camera.position = offset
	camera.fov = fov
	camera.look_at(_target.global_position + Vector3(0.0, target_height, 0.0), Vector3.UP)
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
