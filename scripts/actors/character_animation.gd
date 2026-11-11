class_name CharacterAnimation
extends RefCounted
## Clips for the game's characters, built in code against *semantic* bone names.
##
## The two rigged characters in `scenes/dev/animation_retarget_test/` do not name their bones
## the same way, and neither does the production protagonist:
##
##   production protagonist   Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, Thigh.L, …
##   rigged Q                 Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, Thigh.L, …
##   retargeted protagonist   Root, Hips, Spine, Chest, UpperChest, LeftUpperArm, …
##
## and the animation library that was attempted first used a third convention
## (`root, pelvis, spine_01, upperarm_l, calf_l, …`). A clip authored against one set of names
## plays on exactly one of them. So the clips here are authored against canonical names —
## `hips`, `spine`, `upper_arm.L`, `shin.R` — and every rig resolves those against its own
## bone names at bind time. A bone a rig does not have is reported and its track is left out;
## nothing is silently dropped and nothing is played on a bone that is not there.
##
## Nothing here needs a third-party animation library, an external `.glb`, or a retarget pass
## in the editor: an `Animation` is a resource, its track paths are
## `"<skeleton path>:<bone name>"`, and its keys are quaternions relative to the rest pose.

## Bones the clips talk about, in the order the resolver prefers them. The first name that
## exists on a rig wins, so a rig that has both `Hips` and `Root` binds the hips to `Hips`.
const BONE_ALIASES := {
	"hips": ["Hips", "Pelvis", "Root", "root", "pelvis"],
	"spine": ["Spine", "Spine1", "spine_01", "spine"],
	"chest": ["UpperChest", "Chest", "Spine2", "spine_03", "spine_02"],
	"neck": ["Neck", "neck_01", "neck"],
	"head": ["Head", "head"],
	"shoulder.L": ["LeftShoulder", "Shoulder.L", "clavicle_l", "Shoulder_L"],
	"shoulder.R": ["RightShoulder", "Shoulder.R", "clavicle_r", "Shoulder_R"],
	"upper_arm.L": ["UpperArm.L", "LeftUpperArm", "LeftArm", "upperarm_l"],
	"upper_arm.R": ["UpperArm.R", "RightUpperArm", "RightArm", "upperarm_r"],
	"fore_arm.L": ["LowerArm.L", "LeftLowerArm", "LeftForeArm", "lowerarm_l", "forearm_l"],
	"fore_arm.R": ["LowerArm.R", "RightLowerArm", "RightForeArm", "lowerarm_r", "forearm_r"],
	"hand.L": ["Hand.L", "LeftHand", "hand_l"],
	"hand.R": ["Hand.R", "RightHand", "hand_r"],
	"thigh.L": ["Thigh.L", "LeftUpperLeg", "LeftUpLeg", "thigh_l", "upleg_l"],
	"thigh.R": ["Thigh.R", "RightUpperLeg", "RightUpLeg", "thigh_r", "upleg_r"],
	"shin.L": ["Shin.L", "LeftLowerLeg", "LeftLeg", "calf_l", "lowerleg_l"],
	"shin.R": ["Shin.R", "RightLowerLeg", "RightLeg", "calf_r", "lowerleg_r"],
	"foot.L": ["Foot.L", "LeftFoot", "foot_l"],
	"foot.R": ["Foot.R", "RightFoot", "foot_r"],
}

## The clips, authored in canonical names. Each key is `[time in seconds, degrees about the
## bone's own axes]`; the last key repeats the first so a looping clip closes the cycle.
## Rotations are about the bone's local X for swing (forward and back) and local Z for
## reaching out, which is what the rest poses of both rigs want: every bone in them points
## up or down its own Y.
const CLIPS := {
	"idle": {
		"length": 2.0,
		"tracks": {
			"spine": [[0.0, Vector3(-1.5, 0.0, 0.0)], [1.0, Vector3(1.5, 0.0, 0.0)], [2.0, Vector3(-1.5, 0.0, 0.0)]],
			"chest": [[0.0, Vector3(1.0, 0.0, 0.0)], [1.0, Vector3(-1.0, 0.0, 0.0)], [2.0, Vector3(1.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(0.0, 0.0, 1.0)], [1.0, Vector3(-1.5, 0.0, -1.0)], [2.0, Vector3(0.0, 0.0, 1.0)]],
			"upper_arm.L": [[0.0, Vector3(3.0, 0.0, 3.0)], [1.0, Vector3(5.0, 0.0, 4.0)], [2.0, Vector3(3.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(3.0, 0.0, -3.0)], [1.0, Vector3(5.0, 0.0, -4.0)], [2.0, Vector3(3.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(8.0, 0.0, 0.0)], [2.0, Vector3(6.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(8.0, 0.0, 0.0)], [2.0, Vector3(6.0, 0.0, 0.0)]],
		},
	},
	"walk": {
		"length": 1.0,
		"tracks": {
			"thigh.L": [[0.0, Vector3(22.0, 0.0, 0.0)], [0.5, Vector3(-22.0, 0.0, 0.0)], [1.0, Vector3(22.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(-22.0, 0.0, 0.0)], [0.5, Vector3(22.0, 0.0, 0.0)], [1.0, Vector3(-22.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(4.0, 0.0, 0.0)], [0.5, Vector3(30.0, 0.0, 0.0)], [1.0, Vector3(4.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(30.0, 0.0, 0.0)], [0.5, Vector3(4.0, 0.0, 0.0)], [1.0, Vector3(30.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-8.0, 0.0, 0.0)], [0.5, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(-8.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(6.0, 0.0, 0.0)], [0.5, Vector3(-8.0, 0.0, 0.0)], [1.0, Vector3(6.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-18.0, 0.0, 3.0)], [0.5, Vector3(18.0, 0.0, 3.0)], [1.0, Vector3(-18.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(18.0, 0.0, -3.0)], [0.5, Vector3(-18.0, 0.0, -3.0)], [1.0, Vector3(18.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(14.0, 0.0, 0.0)], [0.5, Vector3(24.0, 0.0, 0.0)], [1.0, Vector3(14.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(24.0, 0.0, 0.0)], [0.5, Vector3(14.0, 0.0, 0.0)], [1.0, Vector3(24.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(2.0, 0.0, 1.5)], [0.5, Vector3(2.0, 0.0, -1.5)], [1.0, Vector3(2.0, 0.0, 1.5)]],
			"head": [[0.0, Vector3(-2.0, 0.0, -1.0)], [0.5, Vector3(-2.0, 0.0, 1.0)], [1.0, Vector3(-2.0, 0.0, -1.0)]],
		},
	},
	"wave": {
		"length": 1.6,
		"tracks": {
			"upper_arm.R": [[0.0, Vector3(-10.0, 0.0, -70.0)], [0.8, Vector3(-10.0, 0.0, -80.0)], [1.6, Vector3(-10.0, 0.0, -70.0)]],
			"fore_arm.R": [[0.0, Vector3(0.0, 0.0, -20.0)], [0.4, Vector3(0.0, 0.0, 25.0)], [0.8, Vector3(0.0, 0.0, -25.0)], [1.2, Vector3(0.0, 0.0, 25.0)], [1.6, Vector3(0.0, 0.0, -20.0)]],
			"hand.R": [[0.0, Vector3(0.0, 0.0, 10.0)], [0.8, Vector3(0.0, 0.0, -10.0)], [1.6, Vector3(0.0, 0.0, 10.0)]],
			"head": [[0.0, Vector3(0.0, 0.0, -3.0)], [0.8, Vector3(-2.0, 0.0, -5.0)], [1.6, Vector3(0.0, 0.0, -3.0)]],
			"upper_arm.L": [[0.0, Vector3(3.0, 0.0, 3.0)], [0.8, Vector3(5.0, 0.0, 4.0)], [1.6, Vector3(3.0, 0.0, 3.0)]],
		},
	},
	"talk": {
		"length": 1.2,
		"tracks": {
			"head": [[0.0, Vector3(3.0, 0.0, 0.0)], [0.4, Vector3(-3.0, 0.0, 2.0)], [0.8, Vector3(2.0, 0.0, -2.0)], [1.2, Vector3(3.0, 0.0, 0.0)]],
			"chest": [[0.0, Vector3(0.0, 0.0, 0.0)], [0.6, Vector3(-2.0, 0.0, 1.5)], [1.2, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(20.0, 0.0, 0.0)], [0.4, Vector3(40.0, 0.0, -10.0)], [0.8, Vector3(25.0, 0.0, 0.0)], [1.2, Vector3(20.0, 0.0, 0.0)]],
			"upper_arm.R": [[0.0, Vector3(6.0, 0.0, -4.0)], [0.6, Vector3(14.0, 0.0, -8.0)], [1.2, Vector3(6.0, 0.0, -4.0)]],
		},
	},
}

## Name the built library is registered under, so clips play as `char/idle`.
const LIBRARY_NAME := &"char"


## Every skeleton under `model_root`, in tree order.
static func skeletons_in(model_root: Node) -> Array[Skeleton3D]:
	var found: Array[Skeleton3D] = []
	for node in model_root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton != null:
			found.append(skeleton)
	return found


## Which of a rig's bones each canonical name resolved to, and which canonical names the rig
## cannot express. `resolved` maps canonical → the rig's own bone name.
static func resolve_rig(skeleton: Skeleton3D) -> Dictionary:
	var by_lower := {}
	var bones: Array[String] = []
	for index in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(index)
		bones.append(name)
		by_lower[name.to_lower()] = name
	var resolved := {}
	var missing: Array[String] = []
	for canonical in BONE_ALIASES:
		for alias: String in BONE_ALIASES[canonical]:
			var hit: Variant = by_lower.get(alias.to_lower())
			if hit != null:
				resolved[canonical] = String(hit)
				break
		if not resolved.has(canonical):
			missing.append(canonical)
	return {"skeleton": skeleton, "bones": bones, "resolved": resolved, "missing": missing}


## Builds the four clips for one rig and registers them on `player` as `char/…`.
##
## `player.root_node` must be the model root, so that a track path of `"Skeleton3D:Spine"`
## means "this model's skeleton, this bone". Returns the report the caller can print:
## the resolved and missing bones, and the track count of each clip.
static func bind(model_root: Node3D, player: AnimationPlayer) -> Dictionary:
	var skeletons := skeletons_in(model_root)
	if skeletons.is_empty():
		return {"ok": false, "reason": "the model has no Skeleton3D", "resolved": {}, "missing": [], "clips": {}}
	var skeleton := skeletons[0]
	if skeletons.size() > 1:
		push_warning(
			"%s has %d skeletons; binding the first (%s)."
			% [model_root.name, skeletons.size(), skeleton.name]
		)
	if player.get_parent() != model_root:
		# Track paths are resolved against the player's root node, so the player has to sit
		# inside the model for `..` to be the model and the skeleton path to be relative to it.
		push_warning("AnimationPlayer should be a child of the model root; binding anyway.")
	var rig := resolve_rig(skeleton)
	var skeleton_path := model_root.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	var clip_report := {}
	for clip_name in CLIPS:
		var spec: Dictionary = CLIPS[clip_name]
		var animation := Animation.new()
		animation.length = float(spec["length"])
		animation.loop_mode = Animation.LOOP_LINEAR
		var tracks: Dictionary = spec["tracks"]
		var used := 0
		for canonical in tracks:
			var bone: Variant = rig["resolved"].get(canonical)
			if bone == null:
				continue
			var path := NodePath("%s:%s" % [String(skeleton_path), String(bone)])
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, path)
			for key: Array in tracks[canonical]:
				var degrees: Vector3 = key[1]
				animation.rotation_track_insert_key(
					track,
					float(key[0]),
					Quaternion.from_euler(
						Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
					)
				)
			used += 1
		library.add_animation(clip_name, animation)
		clip_report[clip_name] = {
			"tracks": used,
			"requested": tracks.size(),
			"length": animation.length,
		}
	if player.has_animation_library(LIBRARY_NAME):
		player.remove_animation_library(LIBRARY_NAME)
	player.add_animation_library(LIBRARY_NAME, library)
	return {
		"ok": true,
		"resolved": rig["resolved"],
		"missing": rig["missing"],
		"clips": clip_report,
		"library": library,
	}


## Plays `clip_name` on a bound player. Returns false (and says why) rather than leaving a
## character in whatever pose the last clip stopped at.
static func play(player: AnimationPlayer, clip_name: String) -> bool:
	var full := "%s/%s" % [String(LIBRARY_NAME), clip_name]
	if not player.has_animation(full):
		push_error("CharacterAnimation: '%s' is not bound on this player." % full)
		return false
	player.play(full)
	return true


## A one-line description of what a rig can and cannot do, for a log or a notice.
static func describe(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return "not bound: %s" % String(report.get("reason", "unknown"))
	var resolved: Dictionary = report["resolved"]
	var missing: Array = report["missing"]
	var clips: Dictionary = report["clips"]
	var parts: PackedStringArray = []
	for clip_name in clips:
		var info: Dictionary = clips[clip_name]
		parts.append(
			"%s %d/%d tracks %.1fs" % [clip_name, int(info["tracks"]), int(info["requested"]), float(info["length"])]
		)
	return "%d bone(s) resolved, %d not on this rig (%s) | %s" % [
		resolved.size(),
		missing.size(),
		", ".join(PackedStringArray(missing)) if not missing.is_empty() else "none",
		" | ".join(parts),
	]
