class_name NpcGaze
extends SkeletonModifier3D
## A person turning to look at someone, on top of whatever their body is playing.
##
## Added under a character's `Skeleton3D` (by `NpcActor.watch()`), so it runs after the
## animation every frame, as a `SkeletonModifier3D` is designed to. It turns the trunk,
## the neck and the head about the world's vertical axis, a share each, until the face
## points at the target - or as far as `reach_degrees` allows, the rest being the
## body's job (`NpcActor` turns the actor for an angle the neck cannot make).
##
## Why a turn about the vertical and not an aim along a bone axis: every rig here was
## exported from Blender with its own bone rolls, and "which axis of the head bone is the
## face" differs between them. Rotating each bone's pose about the up axis, around its own
## joint, needs no such knowledge and cannot aim the face backwards: the turn is measured
## from the way the actor faces (`-Z`, the convention `NpcActor.face_towards()` keeps), so
## zero is always "straight ahead" and the largest turn is `reach_degrees` either way.
##
## Nothing here writes a transform outside the skeleton's pose: the actor's position, its
## rotation, its route and any collider are untouched, and letting go eases the pose back
## to exactly what the animation plays.

## Bones that share the turn, trunk first, and the share each takes. Bones a rig does not
## have are skipped and the remaining shares are scaled up, so the head still reaches.
const CHAIN: Array = [["Spine", 0.2], ["Neck", 0.35], ["Head", 0.45]]

## The furthest the face turns away from the way the body faces, in degrees.
@export_range(0.0, 90.0, 1.0) var reach_degrees: float = 70.0
## Seconds to turn fully towards the target, or to let go of it.
@export_range(0.01, 2.0, 0.01) var blend_seconds: float = 0.25
## How fast the turn follows a target that moves, in degrees per second.
@export_range(30.0, 1080.0, 1.0) var follow_speed_degrees: float = 360.0

var _actor: Node3D = null
var _target: Node3D = null
var _target_height := 1.55
var _wanted := false
var _weight := 0.0
## The turn being followed (before the blend weight), and the one actually applied.
var _yaw := 0.0
var _applied := 0.0
## The head's turn as the skeleton reported it, before and after this modifier, for
## tests and diagnostics: proof that bones moved, not only that a number was computed.
var _measured := 0.0
var _resolved_for: Skeleton3D = null
var _bones := PackedInt32Array()
var _shares := PackedFloat32Array()


## The node whose `-Z` is "straight ahead" for this gaze: the actor, not the visual (a
## +Z model's visual is turned 180° under its actor).
func setup(actor: Node3D) -> void:
	_actor = actor


## Starts looking at `target`, `height` metres above its origin, and keeps following it.
func look_at_node(target: Node3D, height: float) -> void:
	_target = target
	_target_height = height
	_wanted = target != null


## Eases back to the animation over `blend_seconds`.
func let_go() -> void:
	_wanted = false


func is_looking() -> bool:
	return _wanted and is_instance_valid(_target)


## 0 when the pose is the animation's, 1 when the turn is fully applied.
func get_weight() -> float:
	return _weight


## The turn applied in the last processed frame, in degrees (positive is to the left).
func get_applied_yaw_degrees() -> float:
	return _applied


## The head's turn the skeleton itself reported for the last processed frame.
func get_measured_head_turn_degrees() -> float:
	return _measured


## Bone names this gaze moves on its skeleton (empty until the first frame).
func get_bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	if _resolved_for == null:
		return names
	for index in _bones:
		names.append(_resolved_for.get_bone_name(index))
	return names


## The signed angle, in degrees, from where the actor faces to the target, measured
## about the vertical from the head (unclamped; 0 when there is nothing to look at).
func get_desired_yaw_degrees() -> float:
	if _actor == null or not is_instance_valid(_target):
		return 0.0
	var forward := -_actor.global_basis.z
	forward.y = 0.0
	var to_target := _target.global_position + Vector3.UP * _target_height - _eye_position()
	to_target.y = 0.0
	if forward.length_squared() < 0.000001 or to_target.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP))


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _actor == null:
		return
	if _resolved_for != skeleton:
		_resolve(skeleton)
	var looking := is_looking()
	_weight = move_toward(_weight, 1.0 if looking else 0.0, delta / blend_seconds)
	if looking:
		var desired := clampf(get_desired_yaw_degrees(), -reach_degrees, reach_degrees)
		_yaw = move_toward(_yaw, desired, follow_speed_degrees * delta)
	_applied = _yaw * _weight
	_measured = 0.0
	if is_zero_approx(_applied) or _bones.is_empty():
		return
	# The vertical in the skeleton's own space: a turn about it there is a turn about the
	# world's vertical on screen, whatever the actor and the visual are rotated by.
	var up := (skeleton.global_basis.inverse() * Vector3.UP).normalized()
	var head := _bones[_bones.size() - 1]
	var before := skeleton.get_bone_global_pose(head).basis
	for index in _bones.size():
		var bone := _bones[index]
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(up, deg_to_rad(_applied * _shares[index])) * pose.basis
		skeleton.set_bone_global_pose(bone, pose)
	_measured = _turn_about(up, before, skeleton.get_bone_global_pose(head).basis)


func _resolve(skeleton: Skeleton3D) -> void:
	_resolved_for = skeleton
	_bones = PackedInt32Array()
	_shares = PackedFloat32Array()
	var total := 0.0
	for entry: Array in CHAIN:
		var index := skeleton.find_bone(String(entry[0]))
		if index < 0:
			continue
		_bones.append(index)
		_shares.append(float(entry[1]))
		total += float(entry[1])
	if total > 0.0:
		for index in _shares.size():
			_shares[index] = _shares[index] / total
	if _bones.is_empty():
		push_warning("NpcGaze: skeleton '%s' has none of the bones %s." % [skeleton.name, str(CHAIN)])


## The head's world position, or a standing eye height over the actor without one.
func _eye_position() -> Vector3:
	var skeleton := get_skeleton()
	if skeleton != null and _resolved_for == skeleton and not _bones.is_empty():
		return skeleton.global_transform * skeleton.get_bone_global_pose(_bones[_bones.size() - 1]).origin
	return _actor.global_position + Vector3.UP * 1.5


## How far `after` is turned from `before` about `up`, in degrees.
static func _turn_about(up: Vector3, before: Basis, after: Basis) -> float:
	var reference := up.cross(Vector3.RIGHT)
	if reference.length_squared() < 0.01:
		reference = up.cross(Vector3.FORWARD)
	reference = reference.normalized()
	var turned := (after * before.inverse()) * reference
	turned -= up * turned.dot(up)
	if turned.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(reference.signed_angle_to(turned.normalized(), up))
