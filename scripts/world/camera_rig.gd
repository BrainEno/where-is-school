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
##
## **Focus on important interactions** (`focus_on` / `release_focus` / `clear_focus`,
## driven by `CameraFocusDirector`): a `CameraShot` moves the view centre toward the
## subject, brings the camera closer, swings it a little and narrows the lens. Each shot is
## a layer with a weight that glides by a critically damped spring - it eases in, never
## overshoots, and keeps its velocity when a new target arrives mid-glide, so walking from
## one important point straight to the next cross-fades the two shots instead of dipping
## back to the default in between. The layers compose under `frame_point`, which still has
## the last word on what is centred (ExitWatch uses it at the blocked door). With no layer
## the pose is exactly the default one, and `camera.fov == fov`.
##
## Movement is read against the default framing (`planar_right` / `planar_forward`), not
## against a shot, so a focus never turns the controls.

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
## Focus layers: {"subject": Node3D (may be freed), "shot": CameraShot, "point": Vector3
## (the last known look point), "weight": float, "velocity": float, "target": 0.0 or 1.0}.
var _focus_layers: Array[Dictionary] = []


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
	var camera_offset := offset
	var lens := fov
	var total := 0.0
	for layer: Dictionary in _focus_layers:
		total += float(layer["weight"])
	if total > 0.0:
		# Cross-fading layers can briefly add up past 1; they then share the full move.
		var share := 1.0 / maxf(total, 1.0)
		var base_anchor := anchor
		for layer: Dictionary in _focus_layers:
			var weight := float(layer["weight"]) * share
			if weight <= 0.0:
				continue
			var shot := layer["shot"] as CameraShot
			var point := _focus_point(layer, base_anchor)
			anchor += (base_anchor.lerp(point, shot.subject_mix) - base_anchor) * weight
			camera_offset += (_shot_offset(shot) - offset) * weight
			lens += (shot.fov - fov) * weight
	if _frame_weight > 0.0:
		anchor = anchor.lerp(_frame_point, _frame_weight)
	global_position = anchor
	camera.position = camera_offset
	camera.fov = lens
	camera.look_at(anchor + Vector3(0.0, target_height, 0.0), Vector3.UP)
	if not is_zero_approx(_roll_degrees):
		camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(_roll_degrees))


func _physics_process(delta: float) -> void:
	# The body moves in its own `_physics_process`, which runs first because the rig
	# is a later sibling. Following here therefore reads this frame's position, not
	# the previous one, and the rendered frame is the one the player is standing in.
	_step_focus(delta)
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


## The horizontal axis the camera shows as "right" in the default framing, which is the
## axis player movement is expressed in (a focus swing does not turn it). Falls back to
## world axes when the rig has no camera, so a scene that instantiates the player without
## one still moves.
func planar_right() -> Vector3:
	if camera == null:
		return Vector3.RIGHT
	var right := _default_basis().x
	right.y = 0.0
	return right.normalized()


## The horizontal axis the camera shows as "forward" (away from the viewer), in the
## default framing.
func planar_forward() -> Vector3:
	if camera == null:
		return Vector3.FORWARD
	var forward := -_default_basis().z
	forward.y = 0.0
	return forward.normalized()


## The camera's orientation with no focus and no framed point: looking from `offset` at
## the eye, with the current roll.
func _default_basis() -> Basis:
	var look := Vector3(0.0, target_height, 0.0) - offset
	var view := Basis.looking_at(look, Vector3.UP)
	if not is_zero_approx(_roll_degrees):
		view = view * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(_roll_degrees))
	return global_basis * view


# --- Focus on important interactions ---------------------------------------------------


## Glides the view to `shot` of `subject` (an interactable). Any other shot fades out at
## the same time, from wherever it is. Calling it again for the subject already in focus
## changes nothing.
func focus_on(subject: Node3D, shot: CameraShot) -> void:
	if subject == null or shot == null:
		release_focus()
		return
	var found := false
	for layer: Dictionary in _focus_layers:
		if layer["subject"] == subject and layer["shot"] == shot:
			layer["target"] = 1.0
			found = true
		else:
			layer["target"] = 0.0
	if not found:
		_focus_layers.append({
			"subject": subject,
			"shot": shot,
			"point": subject.global_position,
			"weight": 0.0,
			"velocity": 0.0,
			"target": 1.0,
		})


## Glides the view back to the default framing.
func release_focus() -> void:
	for layer: Dictionary in _focus_layers:
		layer["target"] = 0.0


## Back to the default framing at once (a location change: nothing to glide from).
func clear_focus() -> void:
	_focus_layers.clear()
	snap()


## How far the view is in a focus: 0 = the default framing, 1 = fully in a shot.
func get_focus_weight() -> float:
	var total := 0.0
	for layer: Dictionary in _focus_layers:
		total += float(layer["weight"])
	return minf(total, 1.0)


## The subject the view is gliding to or holding (null while none, or while releasing).
func get_focus_subject() -> Node3D:
	for layer: Dictionary in _focus_layers:
		if float(layer["target"]) > 0.0 and is_instance_valid(layer["subject"]):
			return layer["subject"] as Node3D
	return null


## The lens the camera is drawing with right now (`fov` unless a shot narrows it).
func get_effective_fov() -> float:
	return camera.fov if camera != null else fov


func _step_focus(delta: float) -> void:
	if _focus_layers.is_empty() or delta <= 0.0:
		return
	var kept: Array[Dictionary] = []
	for layer: Dictionary in _focus_layers:
		var shot := layer["shot"] as CameraShot
		if not is_instance_valid(layer["subject"]):
			# A freed subject (the room went away under a shot) fades from its last point.
			layer["target"] = 0.0
		var target := float(layer["target"])
		var seconds := shot.glide_seconds if target > 0.0 else shot.release_seconds
		var stepped := _smooth_damp(float(layer["weight"]), target, float(layer["velocity"]), seconds, delta)
		layer["weight"] = stepped.x
		layer["velocity"] = stepped.y
		if target > 0.0 or stepped.x > 0.0:
			kept.append(layer)
	_focus_layers = kept


## A critically damped step toward `target` that reaches ~95% in `seconds` and never
## crosses the target. Returns (value, velocity). Settles exactly on the target.
static func _smooth_damp(current: float, target: float, velocity: float, seconds: float, delta: float) -> Vector2:
	var smooth_time := maxf(0.0001, seconds * 0.42)
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + omega * change) * delta
	var next_velocity := (velocity - omega * temp) * decay
	var value := target + (change + temp) * decay
	if (target - current > 0.0) == (value > target):
		value = target
		next_velocity = 0.0
	if absf(value - target) < 0.0005 and absf(next_velocity) < 0.01:
		value = target
		next_velocity = 0.0
	return Vector2(clampf(value, 0.0, 1.0), next_velocity)


## Where a layer looks, on the target's floor: the subject's position plus the shot's
## offset (remembered, so a freed subject leaves the view where it was).
func _focus_point(layer: Dictionary, base_anchor: Vector3) -> Vector3:
	var shot := layer["shot"] as CameraShot
	if is_instance_valid(layer["subject"]):
		var subject := layer["subject"] as Node3D
		layer["point"] = subject.global_position + shot.look_offset
	var point: Vector3 = layer["point"]
	point.y = base_anchor.y
	return point


## The camera's offset from the view centre under a shot.
func _shot_offset(shot: CameraShot) -> Vector3:
	var swung := offset.rotated(Vector3.UP, deg_to_rad(shot.yaw_degrees)) * shot.distance_scale
	swung.y *= shot.height_scale
	return swung
