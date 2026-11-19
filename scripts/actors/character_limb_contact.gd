class_name CharacterLimbContact
extends RefCounted
## Lock a wrist or ankle to a set mark during the support part of a staged pose.
## Start from the sampled FK pose each frame; the contact only turns the two joints
## and does not stretch the rig, modify a clip or affect ordinary locomotion.
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

func plant_flat(sole: Vector3, bend: Vector3, weight: float = 1.0) -> void:
	var up_scale := skeleton.global_basis.y.length()
	var forward := skeleton.global_basis.z.slide(Vector3.UP).normalized()
	var level := Basis.looking_at(-forward, Vector3.UP)
	var boot := skeleton.global_basis.orthonormalized().inverse() * level * rest_end.basis.orthonormalized()
	hold_at(sole + Vector3.UP * up_scale * rest_end.origin.y, bend, weight, true, boot)


func hold_at(
	target: Vector3, bend: Vector3, weight: float, level_boot: bool = false,
	boot_basis: Basis = Basis()
) -> void:
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
		var aim_basis := rest_end.basis.orthonormalized() if boot_basis == Basis() else boot_basis
		tip.basis = tip.basis.orthonormalized().slerp(aim_basis, weight)
		skeleton.set_bone_global_pose(joints.z, tip)


static func bind(animator: CharacterVisualAnimation) -> Dictionary:
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
				result[chain[2] + side] = CharacterLimbContact.new(skeleton, ids)
	return result
