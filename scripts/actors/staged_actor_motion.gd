extends RefCounted
## Small helpers for a locked beat moving the real player. The caller owns the beat and
## the safe start/end positions; this does not add a locomotion state or drive input.


static func walk_to(player: PlayerController, target: Vector3, speed: float = 1.45) -> bool:
	var start := player.global_position
	var travel := target - start
	travel.y = 0.0
	if travel.length() < 0.015:
		return true
	# Test the actual capsule, just off the floor. Never pull the player through a desk
	# because a cinematic mark happened to be just beyond it.
	if player.test_move(player.global_transform.translated(Vector3.UP * 0.035), travel):
		return false
	var animator := player.get_character_animator()
	var direction := travel.normalized()
	await turn_to(player, direction)
	if animator != null:
		animator.report_velocity(direction * speed)
	var tween := player.create_tween()
	tween.tween_property(player, "global_position", start + travel, travel.length() / speed)
	await tween.finished
	if animator != null:
		animator.clear_reported_velocity()
	return true


static func turn_to(player: PlayerController, direction: Vector3) -> void:
	var facing := player.get_facing_direction()
	var start := atan2(facing.x, facing.z)
	var finish := atan2(direction.x, direction.z)
	if absf(angle_difference(start, finish)) < 0.05:
		return
	var tween := player.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t: float) -> void:
		var yaw := lerp_angle(start, finish, t)
		player.face_toward(Vector3(sin(yaw), 0, cos(yaw)))
	, 0.0, 1.0, 0.24)
	await tween.finished


static func act(
	player: PlayerController, clip: String, seconds: float, travel: Callable
) -> void:
	var tween := player.create_tween()
	var animator := player.get_character_animator()
	var sample := func(t: float) -> void:
		if animator != null:
			animator.sample_action(clip, t)
		if travel.is_valid():
			travel.call(t)
	sample.call(0.0)
	tween.tween_method(sample, 0.0, 1.0, seconds)
	await tween.finished


static func reset_pose(player: PlayerController) -> void:
	var animator := player.get_character_animator()
	if animator != null:
		animator.release_sampled_action()
		animator.clear_reported_velocity()
	player.set_wake_pose(0.0)
	if player.visual != null:
		player.visual.position = Vector3.UP * PlayerController.STANDING_HIP_HEIGHT
	player.set_camera_roll(0.0)


## Lock a wrist or ankle to a set mark during the support part of a staged pose.
## Start from the sampled FK pose each frame; the contact only turns the two joints
## and does not stretch the rig, modify a clip or affect ordinary locomotion.
class Limb extends RefCounted:
	var skeleton: Skeleton3D
	var joints: Vector3i
	var rest_end: Transform3D

	func _init(rig: Skeleton3D, indices: Vector3i) -> void:
		skeleton = rig
		joints = indices
		rest_end = rig.get_bone_global_rest(indices.z)

	func plant(sole: Vector3, bend: Vector3, weight: float = 1.0) -> void:
		# The rig stands on y=0; its rest ankle is above the sole, not on it.
		hold_at(sole + skeleton.global_basis * Vector3.UP * rest_end.origin.y, bend, weight, true)

	func hold_at(target: Vector3, bend: Vector3, weight: float, level_boot: bool = false) -> void:
		if weight <= 0.001:
			return
		var upper := skeleton.get_bone_global_pose(joints.x)
		var lower := skeleton.get_bone_global_pose(joints.y)
		var tip := skeleton.get_bone_global_pose(joints.z)
		var first := lower.origin - upper.origin
		var second := tip.origin - lower.origin
		var a := first.length()
		var b := second.length()
		var reach := tip.origin.lerp(skeleton.to_local(target), weight) - upper.origin
		if minf(a, b) < 0.01 or reach.length_squared() < 0.0001:
			return
		var axis := reach.normalized()
		var pole := skeleton.global_basis.inverse() * bend
		var side := (pole - axis * axis.dot(pole)).normalized()
		if side.length_squared() < 0.1:
			return
		var distance := clampf(reach.length(), absf(a - b) + 0.005, a + b - 0.005)
		var along := (a * a - b * b + distance * distance) / (2.0 * distance)
		var knee := axis * along + side * sqrt(maxf(0.0, a * a - along * along))
		upper.basis = Basis(Quaternion(first.normalized(), knee.normalized())) * upper.basis
		skeleton.set_bone_global_pose(joints.x, upper)
		lower = skeleton.get_bone_global_pose(joints.y)
		tip = skeleton.get_bone_global_pose(joints.z)
		var lower_axis := (tip.origin - lower.origin).normalized()
		var aim := (upper.origin + axis * distance - lower.origin).normalized()
		lower.basis = Basis(Quaternion(lower_axis, aim)) * lower.basis
		skeleton.set_bone_global_pose(joints.y, lower)
		if level_boot:
			tip = skeleton.get_bone_global_pose(joints.z)
			tip.basis = tip.basis.orthonormalized().slerp(rest_end.basis.orthonormalized(), weight)
			skeleton.set_bone_global_pose(joints.z, tip)


## Resolve once per beat, using the same semantic bone names as the existing clips.
static func contacts(actor: PlayerController) -> Dictionary:
	var animator := actor.get_character_animator()
	if animator == null:
		return {}
	var rigs := CharacterAnimation.skeletons_in(animator)
	if rigs.is_empty():
		return {}
	var skeleton: Skeleton3D = rigs[0]
	var resolved: Dictionary = CharacterAnimation.resolve_rig(skeleton, true, animator.faces_negative_z)["resolved"]
	var result := {}
	for side: String in [".L", ".R"]:
		for chain: Array in [["thigh", "shin", "foot"], ["upper_arm", "fore_arm", "hand"]]:
			var ids := Vector3i(-1, -1, -1)
			for i in 3:
				ids[i] = skeleton.find_bone(String(resolved.get(chain[i] + side, "")))
			if mini(ids.x, mini(ids.y, ids.z)) >= 0:
				result[chain[2] + side] = Limb.new(skeleton, ids)
	return result
