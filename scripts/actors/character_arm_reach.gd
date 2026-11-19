extends Node
## Reaches an arm out to a point in the world, and lets go.
##
## The stand-up and the sit-down both involve a hand on the chair: you push a chair back to
## stand up out of it, and you draw one back in to sit down in it. Neither is a pose the rig
## was authored with, and the alternative - a per-character clip - would have to be rebuilt
## for every rig in the game and would still point at the wrong place in every room.
##
## So this drives the arm procedurally, from the target's actual position: the shoulder stays
## on the body, the arm swings towards wherever the chair is, and the reach eases in and out so
## the hand arrives rather than appearing. That is the whole contract - it is a *reach*, not an
## animation system, and it deliberately owns nothing but the two arm bones and their weights.
##
## ## How it composes with the clip
##
## The body is animated by `CharacterVisualAnimation`, which owns the skeleton through an
## `AnimationPlayer`. Writing bone poses directly would be overwritten the next time the
## player advances a frame. So the reach is applied *after* the animation each frame, from a
## `PROCESS_MODE_PROCESS` child, and it writes only the bones it needs. When the reach ends,
## the arm goes back to whatever the clip says.
##
## ## Why the weights are smoothstepped
##
## A hand that snaps to the chair reads as a glitch; a hand that eases out and arrives reads as
## reaching. `weight` is the 0..1 blend, and every caller drives it from a tween rather than
## jumping it.
##
## ## The priority
##
## `AnimationMixer` applies its tracks during `_process` at the default priority, so a node that
## writes bone poses from its own `_process` runs *before* the mixer half the time and has its
## work overwritten. `PROCESS_PRIORITY` puts this after it, which is the only reason the reach
## survives to be drawn.

## After the animation mixer, so this frame's bone writes are not overwritten by it.
const PROCESS_PRIORITY := 100

## How far the elbow bends past straight when the hand is at full extension. Negative is
## flexion for this rig (the arms hang with a rest rotation near 180 degrees; see
## `CharacterAnimation` on why offsets are composed onto the rest pose).
const ELBOW_BEND_DEGREES := -22.0

## The arm being driven, and the two bones under it.
var _skeleton: Skeleton3D = null
var _upper_arm := -1
var _fore_arm := -1
var _rest_upper := Quaternion.IDENTITY
var _rest_fore := Quaternion.IDENTITY

## 0 = the clip's pose, 1 = the hand is at the target.
var _weight := 0.0
var _target := Vector3.ZERO
var _has_target := false


## Binds to a character's skeleton. Returns false when the rig has no arms to bend, which is a
## rigless fixture - the caller then simply does not reach, and nothing else changes.
func bind(animator: Node) -> bool:
	if animator == null or not animator.has_method("get_skeleton"):
		return false
	_skeleton = animator.get_skeleton() as Skeleton3D
	if _skeleton == null:
		return false
	var resolved: Dictionary = {}
	if animator.has_method("get_bind_report"):
		resolved = animator.get_bind_report().get("resolved", {})
	# The right arm: the classroom chair is on the protagonist's right as he sits in it, and
	# the same side is what pushes it back when he stands.
	_upper_arm = _bone_named(resolved, "upper_arm.R", "UpperArm_R")
	_fore_arm = _bone_named(resolved, "fore_arm.R", "LowerArm_R")
	if _upper_arm < 0:
		return false
	_rest_upper = _skeleton.get_bone_rest(_upper_arm).basis.get_rotation_quaternion()
	if _fore_arm >= 0:
		_rest_fore = _skeleton.get_bone_rest(_fore_arm).basis.get_rotation_quaternion()
	set_process_priority(PROCESS_PRIORITY)
	set_process(false)
	return true


## Starts reaching for `target` (a world position - the chair's back, say). The tween drives
## `set_weight` from 0 to 1 over the reach; this only says where the hand is going.
func reach_to(target: Vector3) -> void:
	if _skeleton == null:
		return
	_target = target
	_has_target = true
	set_process(true)


## 0 = the clip's arm, 1 = fully reaching. Clamped, and smoothstepped on the way in so a
## one-frame jump cannot happen even if a caller drives it badly.
func set_weight(value: float) -> void:
	_weight = clampf(value, 0.0, 1.0)


func get_weight() -> float:
	return _weight


## Puts the arm back under the clip's control and stops tracking. Called when the hand lets go.
func release() -> void:
	_weight = 0.0
	_has_target = false
	_restore()
	set_process(false)


func _process(_delta: float) -> void:
	if _skeleton == null or not _has_target or _weight <= 0.0:
		return
	var shoulder := _skeleton.global_transform * _skeleton.get_bone_global_pose(_upper_arm).origin
	var to_target := _target - shoulder
	if to_target.length_squared() < 0.0001:
		return
	var want := _upper_arm_rotation_for(to_target.normalized())
	var blended := _rest_upper.slerp(want, _weight)
	_skeleton.set_bone_pose_rotation(_upper_arm, blended)
	if _fore_arm >= 0:
		var bend := Quaternion(Vector3.RIGHT, deg_to_rad(ELBOW_BEND_DEGREES * _weight))
		_skeleton.set_bone_pose_rotation(_fore_arm, _rest_fore * bend)


## The upper arm's local rotation that points the arm down `direction`.
##
## A shoulder points its bone along the arm's own -Y in this rig, so the rotation is the one
## that takes that axis onto `direction`, expressed in the bone's parent space - which for the
## upper arm is the chest, and the chest is upright for the whole of a stand or a sit.
func _upper_arm_rotation_for(direction: Vector3) -> Quaternion:
	var local := _skeleton.global_transform.basis.inverse() * direction
	var down := Vector3.DOWN
	var axis := down.cross(local)
	if axis.length_squared() < 0.000001:
		return _rest_upper
	axis = axis.normalized()
	var angle := acos(clampf(down.dot(local), -1.0, 1.0))
	return Quaternion(axis, angle) * _rest_upper


func _restore() -> void:
	if _skeleton == null:
		return
	if _upper_arm >= 0:
		_skeleton.set_bone_pose_rotation(_upper_arm, _rest_upper)
	if _fore_arm >= 0:
		_skeleton.set_bone_pose_rotation(_fore_arm, _rest_fore)


func _bone_named(resolved: Dictionary, canonical: String, fallback: String) -> int:
	# Not `name`: that is `Node.name`, and a local of that name is a parse error rather than a
	# shadow, which is a thing `gdparse` accepts and the engine does not.
	var bone_name := String(resolved.get(canonical, ""))
	if bone_name.is_empty():
		bone_name = fallback
	return _skeleton.find_bone(bone_name)


# --- holding a chair ---------------------------------------------------------------
#
# The two things a body does to a chair are take hold of it and let go, and both of them are
# the same performance in both directions: the hand arrives, the chair moves, the hand leaves.
# Keeping the choreography here rather than in the controller is what stops the controller
# growing another fifty lines for each prop that has a hand on it.


## Takes hold of `target` and returns the tween that lasts the reach. The caller waits on it
## before moving whatever the hand is on.
func take_hold(target: Vector3, seconds: float) -> Tween:
	reach_to(target)
	var tween := create_tween()
	tween.tween_method(_set_weight_from_tween, 0.0, 1.0, seconds)
	return tween


## Lets go over `seconds`, then hands the arm back to the clip.
func let_go(seconds: float) -> Tween:
	var tween := create_tween()
	tween.tween_method(_set_weight_from_tween, get_weight(), 0.0, seconds)
	tween.tween_callback(release)
	return tween


## `Tween.tween_method` needs a `Callable` with a concrete float parameter; `set_weight` is the
## one thing that changes, so the adapter is one line instead of a lambda at every call site.
func _set_weight_from_tween(value: float) -> void:
	set_weight(value)
