class_name AnimationRetarget
extends RefCounted
## Retargets another rig's clips onto one of this project's characters, as real `Animation`
## resources with this character's bone names — so the result can be scrubbed in the editor's
## animation panel, not only watched at runtime.
##
## The characters and the animation library name their bones three different ways:
##
##   Universal Animation Library   root, pelvis, spine_01..03, upperarm_l, lowerarm_l, calf_l
##   protagonist (retargeted)      Root, Hips, Spine, Chest, LeftUpperArm, LeftLowerArm, …
##   protagonist (production)      Root, Spine, Neck_2, UpperArm.L, LowerArm.L, Shin.L, …
##
## `CharacterAnimation.resolve_rig()` already answers "which bone on this rig is the upper
## arm", and its canonical names are the humanoid profile's (`LeftUpperArm`, `LeftUpperLeg`,
## `Hips`, …) — which is exactly what the `BoneMap` in both `.import` sidecars says. So the
## pairing is the intersection of the two resolutions, and every pair is reported.
##
## Retargeting is rest-relative, in skeleton space: for each pair, take the source bone's
## rotation *change* since its rest pose, apply it to the target bone's rest rotation, and
## convert the result to a parent-relative rotation. A bone whose rest pose differs between
## the rigs therefore still lands where the animation puts it, instead of inheriting the
## library's twist. Positions are not copied: these clips have no root motion to give away,
## and lifting a character off the floor is worse than not bobbing the hips.


## Canonical name → `{"source": source bone index, "target": target bone index}` for every
## bone both rigs have. `missing` lists the canonical names one of them does not have.
static func map_bones(source: Skeleton3D, target: Skeleton3D) -> Dictionary:
	var source_rig := CharacterAnimation.resolve_rig(source)
	var target_rig := CharacterAnimation.resolve_rig(target)
	var pairs: Array = []
	var resolved := {}
	for canonical in CharacterAnimation.BONE_ALIASES:
		var source_bone: Variant = source_rig["resolved"].get(canonical)
		var target_bone: Variant = target_rig["resolved"].get(canonical)
		if source_bone == null or target_bone == null:
			continue
		var source_index := source.find_bone(String(source_bone))
		var target_index := target.find_bone(String(target_bone))
		if source_index < 0 or target_index < 0:
			continue
		resolved[canonical] = {"source": String(source_bone), "target": String(target_bone)}
		pairs.append({"canonical": canonical, "source": source_index, "target": target_index})
	return {
		"pairs": pairs,
		"resolved": resolved,
		"missing": {
			"source": source_rig["missing"],
			"target": target_rig["missing"],
		},
	}


## Samples every clip on `player` and writes the retargeted version into a new library.
##
## `skeleton_path` is the target skeleton's path *relative to the node that will play the
## result*, so `"Skeleton3D:UpperChest"` means the right bone on the right character. `fps`
## is the sampling rate; the source clips key at 30 fps and are re-sampled onto a fixed grid,
## which keeps every clip's keys at the same times regardless of which channels the source
## happened to animate.
static func bake(
	source: Skeleton3D,
	player: AnimationPlayer,
	target: Skeleton3D,
	clip_names: Array,
	fps: float,
	skeleton_path: NodePath
) -> Dictionary:
	var mapping := map_bones(source, target)
	var pairs: Array = mapping["pairs"]
	if pairs.is_empty():
		return {"library": null, "reason": "the two rigs share no bones", "clips": {}, "pairs": []}

	# Rest rotations in skeleton space, for both rigs.
	var source_rest: Array = []
	for index in source.get_bone_count():
		source_rest.append(source.get_bone_global_rest(index).basis.get_rotation_quaternion())
	var target_rest: Array = []
	for index in target.get_bone_count():
		target_rest.append(target.get_bone_global_rest(index).basis.get_rotation_quaternion())

	var library := AnimationLibrary.new()
	var clip_report := {}
	for clip_name: String in clip_names:
		var source_animation := player.get_animation(clip_name)
		if source_animation == null:
			clip_report[clip_name] = {"error": "the source player has no clip called that"}
			continue
		var length := source_animation.length
		var frames := maxi(2, roundi(length * fps) + 1)
		var step := length / float(frames - 1)

		var keys := {}
		for pair: Dictionary in pairs:
			keys[int(pair["target"])] = []

		player.play(clip_name)
		for frame in frames:
			player.seek(float(frame) * step, true)
			# Global rotations this character should have at this instant, in hierarchy order
			# is not needed: each is the target's own rest rotation with the source's change
			# applied, so the bones are independent of each other here.
			var target_global: Array = target_rest.duplicate()
			for pair: Dictionary in pairs:
				var source_index := int(pair["source"])
				var change: Quaternion = (
					source_rest[source_index].inverse()
					* source.get_bone_global_pose(source_index).basis.get_rotation_quaternion()
				)
				target_global[int(pair["target"])] = (
					target_rest[int(pair["target"])] * change.normalized()
				)
			for pair: Dictionary in pairs:
				var target_index := int(pair["target"])
				var parent := target.get_bone_parent(target_index)
				var parent_global := Quaternion.IDENTITY
				if parent >= 0:
					parent_global = target_global[parent]
				# `Skeleton3D` stores the *whole* local transform as the bone's pose and composes
				# `global = parent_global · pose`, so the pose to store is the global taken back
				# through the parent — the bone's rest is already part of it. Putting the rest
				# back in on top (which is what "rest-relative" suggests and what an earlier
				# version of this did) leaves the inverse of the rest rotation in every key, and
				# only the bones whose rest is far from identity show it: the legs came out 180°
				# wrong while the spine looked right.
				(keys[target_index] as Array).append(
					(parent_global.inverse() * target_global[target_index]).normalized()
				)

		var animation := Animation.new()
		animation.length = length
		# Copy the source's own loop setting rather than guessing from the name: the glTF
		# importer strips the `_Loop` suffix and records looping in the animation, so a clip
		# called `Walk` is the looping one and `Jump_Land` is not.
		animation.loop_mode = source_animation.loop_mode
		var widest := 0.0
		var widest_bone := ""
		for pair: Dictionary in pairs:
			var target_index := int(pair["target"])
			var bone_name := target.get_bone_name(target_index)
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(
				track, NodePath("%s:%s" % [String(skeleton_path), String(bone_name)])
			)
			var values: Array = keys[target_index]
			var previous := Quaternion.IDENTITY
			for index in values.size():
				var value: Quaternion = values[index]
				# Keep the quaternion on the same hemisphere as the previous key, so a clip
				# that turns 200° is a 200° turn and not a 160° one the short way round.
				if index > 0 and value.dot(previous) < 0.0:
					value = Quaternion(-value.x, -value.y, -value.z, -value.w)
				previous = value
				animation.rotation_track_insert_key(track, float(index) * step, value)
				var deviation := _degrees(value.angle_to(Quaternion.IDENTITY))
				if deviation > widest:
					widest = deviation
					widest_bone = String(bone_name)
		library.add_animation(clip_name, animation)
		clip_report[clip_name] = {
			"tracks": animation.get_track_count(),
			"length": length,
			"keys": frames,
			"widest": widest,
			"widest_bone": widest_bone,
		}
	player.stop()
	return {
		"library": library,
		"clips": clip_report,
		"pairs": pairs,
		"missing": mapping["missing"],
	}


## How far a quaternion turns, in degrees, the short way round: `get_angle()` reports up to
## 360°, so a bone that leans 3° the other way would otherwise read as 357°.
static func _degrees(radians: float) -> float:
	var degrees := absf(rad_to_deg(radians))
	return minf(degrees, 360.0 - degrees)


## One line per clip, for a notice or a log: every clip in the library, and how far it moves
## the bone it moves furthest (a clip that moves nothing is a clip whose tracks are wrong).
static func describe(report: Dictionary) -> String:
	var clips: Dictionary = report.get("clips", {})
	if clips.is_empty():
		return "nothing baked (%s)" % String(report.get("reason", "?"))
	var parts: PackedStringArray = []
	for clip_name in clips:
		var info: Dictionary = clips[clip_name]
		if info.has("error"):
			parts.append("%s: %s" % [String(clip_name), String(info["error"])])
			continue
		parts.append(
			"%s %.2fs %d tracks, %s turns %.1f°"
			% [
				String(clip_name),
				float(info["length"]),
				int(info["tracks"]),
				String(info["widest_bone"]),
				float(info["widest"]),
			]
		)
	return ", ".join(parts)
