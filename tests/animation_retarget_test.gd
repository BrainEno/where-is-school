extends SceneTree
## First-party synthetic fixtures. Keep the retarget algorithm covered without importing
## or committing an external animation library. The rigs have the same semantic joints
## but different local rest rotations and naming conventions.

const Harness = preload("res://tests/test_harness.gd")
const FPS := 8.0
const ROTATION_TOLERANCE_DEGREES := 0.2
const SOURCE_NAMES := ["pelvis", "spine_01", "upperarm_l", "lowerarm_l"]
const TARGET_NAMES := ["Hips", "Spine", "LeftUpperArm", "LeftLowerArm"]
const EXPECTED_PAIRS := {
	"hips": {"source": "pelvis", "target": "Hips"},
	"spine": {"source": "spine_01", "target": "Spine"},
	"upper_arm.L": {"source": "upperarm_l", "target": "LeftUpperArm"},
	"fore_arm.L": {"source": "lowerarm_l", "target": "LeftLowerArm"},
}

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 30.0, "animation_retarget_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "synthetic rig mapping"
	var source := _rig(SOURCE_NAMES, [0.2, -0.4, 0.3, 0.6])
	# The target has an extra unmapped pivot; corresponding bone indices differ.
	var target := _rig(["RigPivot"] + TARGET_NAMES, [-0.3, -0.8, 0.5, -0.6, 1.1])
	var mapping := AnimationRetarget.map_bones(source, target)
	if mapping["resolved"] != EXPECTED_PAIRS:
		_failures.append("incorrect semantic bone mapping: %s" % str(mapping["resolved"]))

	Harness.stage = "bake synthetic looping and one-shot clips"
	var source_player := _player(source)
	var source_library := AnimationLibrary.new()
	source_library.add_animation(&"looped", _source_clip(source, true))
	source_library.add_animation(&"one_shot", _source_clip(source, false))
	source_player.add_animation_library(&"", source_library)
	var report := AnimationRetarget.bake(
		source, source_player, target, ["looped", "one_shot"], FPS, ^"Skeleton3D"
	)
	var baked := report.get("library") as AnimationLibrary
	if baked == null or baked.get_animation_list().size() != 2:
		_failures.append("bake did not produce both animations: %s" % AnimationRetarget.describe(report))
	else:
		var target_player := _player(target)
		target_player.add_animation_library(&"", baked)
		for clip: StringName in source_library.get_animation_list():
			Harness.stage = "play and compare %s" % clip
			if not baked.has_animation(clip):
				_failures.append("bake lost the %s animation" % clip)
				continue
			_check_tracks(source_library.get_animation(clip), baked.get_animation(clip))
			_check_motion(source, target, source_player, target_player, clip)
	source.get_parent().free()
	target.get_parent().free()
	Harness.finish(self, _failures, "synthetic retarget pairs bones and preserves rest-relative motion")


func _rig(names: Array, rests: Array) -> Skeleton3D:
	var rig := Node3D.new()
	root.add_child(rig)
	var skeleton := Skeleton3D.new()
	skeleton.name = &"Skeleton3D"
	rig.add_child(skeleton)
	for index in names.size():
		skeleton.add_bone(String(names[index]))
		if index > 0:
			skeleton.set_bone_parent(index, index - 1)
		var basis := Basis(Vector3.FORWARD if index % 2 == 0 else Vector3.UP, float(rests[index]))
		skeleton.set_bone_rest(index, Transform3D(basis, Vector3(0.0, 0.3, 0.0)))
	skeleton.reset_bone_poses()
	return skeleton


func _player(skeleton: Skeleton3D) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	skeleton.get_parent().add_child(player)
	player.root_node = ^".."
	return player


func _source_clip(source: Skeleton3D, looped: bool) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	clip.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	for index in source.get_bone_count():
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:%s" % source.get_bone_name(index)))
		var rest := source.get_bone_rest(index).basis.get_rotation_quaternion()
		var pose := rest * Quaternion(Vector3.RIGHT, 0.18 * (index + 1))
		clip.rotation_track_insert_key(track, 0.0, rest)
		clip.rotation_track_insert_key(track, 0.5, pose)
		clip.rotation_track_insert_key(track, 1.0, rest if looped else pose)
	var position := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(position, ^"Skeleton3D:pelvis")
	var origin := source.get_bone_rest(0).origin
	clip.position_track_insert_key(position, 0.0, origin)
	clip.position_track_insert_key(position, 0.5, origin + Vector3.UP)
	clip.position_track_insert_key(position, 1.0, origin)
	return clip


func _check_tracks(original: Animation, baked: Animation) -> void:
	if baked.loop_mode != original.loop_mode or not is_equal_approx(baked.length, original.length):
		_failures.append("baked clip changed the source length or loop mode")
	var paths: Array[NodePath] = []
	for track in baked.get_track_count():
		if baked.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			_failures.append("retarget unexpectedly copied a non-rotation track")
		paths.append(baked.track_get_path(track))
		if baked.track_get_key_count(track) != roundi(FPS * original.length) + 1:
			_failures.append("baked track has the wrong sampling grid")
	if paths.size() != TARGET_NAMES.size():
		_failures.append("baked clip has a different number of tracks than mapped bones")
	for name: String in TARGET_NAMES:
		if not paths.has(NodePath("Skeleton3D:%s" % name)):
			_failures.append("baked clip has no track addressing %s" % name)


func _check_motion(
		source: Skeleton3D, target: Skeleton3D, source_player: AnimationPlayer,
		target_player: AnimationPlayer, clip: StringName
) -> void:
	source_player.play(clip)
	target_player.play(clip)
	var movement := 0.0
	var worst := 0.0
	for sample in roundi(FPS) + 1:
		var moment := float(sample) / FPS
		source_player.seek(moment, true)
		target_player.seek(moment, true)
		source.force_update_all_bone_transforms()
		target.force_update_all_bone_transforms()
		for index in TARGET_NAMES.size():
			var target_index := target.find_bone(TARGET_NAMES[index])
			var source_delta := _rotation_delta(source, index)
			var target_delta := _rotation_delta(target, target_index)
			worst = maxf(worst, _degrees_between(source_delta, target_delta))
			movement = maxf(movement, _degrees_between(Quaternion.IDENTITY, target_delta))
			var origin := target.get_bone_rest(target_index).origin
			if not target.get_bone_pose_position(target_index).is_equal_approx(origin):
				_failures.append("%s retarget unexpectedly moved a target bone's position" % clip)
	source_player.stop()
	target_player.stop()
	if movement < 3.0 or worst > ROTATION_TOLERANCE_DEGREES:
		_failures.append("%s: target moved %.2f degrees, worst rotation error %.2f" % [clip, movement, worst])


func _rotation_delta(skeleton: Skeleton3D, index: int) -> Quaternion:
	var rest := skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
	var pose := skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion()
	return (rest.inverse() * pose).normalized()


func _degrees_between(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)))
