extends SceneTree
## The protagonist is `Protagonist_Character.glb` (PR #118), the first protagonist model is a
## student sitting in the classroom, and Q is unchanged.
##
##   godot --headless --path . --script res://tests/protagonist_model_test.gd
##
## What it proves, in the engine and measured off the skeletons:
##
##   1. the new model imports with one Skeleton3D at `Protagonist_Armature/Skeleton3D`, its 60
##      bones in their hierarchy, and all nine meshes skinned to that skeleton;
##   2. its five embedded clips import, every track resolves, none autoplays, and the game's
##      own clips play on a separate player (the embedded ones are left alone);
##   3. the semantic bone mapping is complete and exact: every canonical bone resolves, the
##      sides are positional (`upper_arm.L` → `UpperArm_R`, see `CharacterAnimation`), and
##      the joints that animate are exactly the fifteen listed below — the other 45 (root, IK
##      targets, pelvis, Spine_01/02, clavicles, one hand, 30 finger joints, eyes, toes) are
##      never keyed and stay at rest;
##   4. every key clip's tracks point at real bones, on all three rigs;
##   5. the clips move the bodies the way they say, on all three rigs: seated knees forward
##      and shins down; walking and jogging feet travel along the facing, knees fold forward
##      and never back, elbows never bend backwards, hands stay below the shoulders and on
##      their own side of the body, and hands and feet do not twist about their own length;
##   6. the player scene shows the new model, the classroom seats the former protagonist as a
##      plain student (no controller, no input, no collision, no interaction), the old asset
##      and its sidecar are still there, and Q binds exactly as before.

const Harness = preload("res://tests/test_harness.gd")

const NEW_MODEL := "res://assets/models/protagonist/Protagonist_Character.glb"
const FORMER_MODEL := "res://assets/models/protagonist/protagonist.glb"
const Q_MODEL := "res://assets/models/q/q.glb"
const PROTAGONIST_WRAPPER := "res://scenes/environment/characters/protagonist.tscn"
const STUDENT_WRAPPER := "res://scenes/environment/characters/classroom_student.tscn"
const Q_WRAPPER := "res://scenes/environment/characters/q.tscn"
const PLAYER_SCENE := "res://scenes/actors/player/player.tscn"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"

const SKELETON_PATH := "Protagonist_Armature/Skeleton3D"
const BONE_COUNT := 60
const MESH_COUNT := 9
## The parent of every bone that is not a finger joint. Fingers are checked by pattern.
const HIERARCHY := {
	"Root": "",
	"IK_Foot_L": "Root",
	"IK_Foot_R": "Root",
	"IK_Hand_L": "Root",
	"IK_Hand_R": "Root",
	"Pelvis": "Root",
	"Spine": "Pelvis",
	"Spine_01": "Spine",
	"Spine_02": "Spine_01",
	"Chest": "Spine_02",
	"Clavicle_L": "Chest",
	"UpperArm_L": "Clavicle_L",
	"Forearm_L": "UpperArm_L",
	"Hand_L": "Forearm_L",
	"Clavicle_R": "Chest",
	"UpperArm_R": "Clavicle_R",
	"Forearm_R": "UpperArm_R",
	"Hand_R": "Forearm_R",
	"Neck": "Chest",
	"Head": "Neck",
	"Eye_L": "Head",
	"Eye_R": "Head",
	"Thigh_L": "Pelvis",
	"Shin_L": "Thigh_L",
	"Foot_L": "Shin_L",
	"Toe_L": "Foot_L",
	"Thigh_R": "Pelvis",
	"Shin_R": "Thigh_R",
	"Foot_R": "Shin_R",
	"Toe_R": "Foot_R",
}
const FINGERS := ["Index", "Middle", "Ring", "Little", "Thumb"]

## Name → length in seconds, as Godot imports them (none loops).
const EMBEDDED_CLIPS := {
	"Idle_Breathing": 2.5,
	"Protagonist_Idle_Breathing": 4.0417,
	"Slight_Posture_Shift": 3.75,
	"Subtle_Head_Movement": 3.0,
	"Protagonist_Face_Test": 4.0417,
}

## Canonical → bone on the new rig. `.L` is the skeleton's −X side; this rig names its limbs
## anatomically, with `*_L` at +X, so every pair is crossed.
const NEW_MAPPING := {
	"hips": "Pelvis",
	"spine": "Spine",
	"chest": "Chest",
	"neck": "Neck",
	"head": "Head",
	"shoulder.L": "Clavicle_R",
	"shoulder.R": "Clavicle_L",
	"upper_arm.L": "UpperArm_R",
	"upper_arm.R": "UpperArm_L",
	"fore_arm.L": "Forearm_R",
	"fore_arm.R": "Forearm_L",
	"hand.L": "Hand_R",
	"hand.R": "Hand_L",
	"thigh.L": "Thigh_R",
	"thigh.R": "Thigh_L",
	"shin.L": "Shin_R",
	"shin.R": "Shin_L",
	"foot.L": "Foot_R",
	"foot.R": "Foot_L",
}
const NEW_MIRRORED := ["shoulder", "upper_arm", "fore_arm", "hand", "thigh", "shin", "foot"]
## The new rig's bones the clips key. `hand.R` (the +X hand) is keyed by `wave` only.
const NEW_ANIMATED := [
	"Spine",
	"Chest",
	"Neck",
	"Head",
	"UpperArm_L",
	"UpperArm_R",
	"Forearm_L",
	"Forearm_R",
	"Hand_L",
	"Thigh_L",
	"Thigh_R",
	"Shin_L",
	"Shin_R",
	"Foot_L",
	"Foot_R",
]

## What Q resolved to before the protagonist changed. Q has to bind exactly the same bones.
const Q_MAPPING := {
	"hips": "Root",
	"spine": "Spine",
	"neck": "Neck",
	"head": "Head",
	"upper_arm.L": "UpperArm.L",
	"upper_arm.R": "UpperArm.R",
	"fore_arm.L": "LowerArm.L",
	"fore_arm.R": "LowerArm.R",
	"hand.L": "Hand.L",
	"hand.R": "Hand.R",
	"thigh.L": "Thigh.L",
	"thigh.R": "Thigh.R",
	"shin.L": "Shin.L",
	"shin.R": "Shin.R",
	"foot.L": "Foot.L",
	"foot.R": "Foot.R",
}
const Q_POSED := ["fore_arm.R", "hand.L", "hand.R"]
const FORMER_MAPPING := {
	"hips": "Root",
	"spine": "Spine",
	"neck": "Neck_2",
	"head": "Head",
	"upper_arm.L": "UpperArm.L",
	"upper_arm.R": "UpperArm.R",
	"fore_arm.L": "LowerArm.L",
	"fore_arm.R": "LowerArm.R",
	"hand.L": "Hand.L",
	"hand.R": "Hand.R",
	"thigh.L": "Thigh.L",
	"thigh.R": "Thigh.R",
	"shin.L": "Shin.L",
	"shin.R": "Shin.R",
	"foot.L": "Foot.L",
	"foot.R": "Foot.R",
}

## The clips whose limbs are measured, and how many samples per clip.
const MEASURED_CLIPS := ["idle", "walk", "jog", "sit_idle", "get_up"]
const SAMPLES := 12
## Twist of a bone about its own length, against its rest, in any key of any clip.
const MAX_TWIST_DEGREES := 8.0
const MAX_HAND_FOOT_TWIST_DEGREES := 1.0
## The classroom seat the former protagonist sits at (desk A1 and its chair).
const SEAT_DESK := Vector3(-2.5, 0.0, -1.5)
const SEAT_TOP := 0.475
## How far the former protagonist's soles sit above its own origin (its recorded model base).
const FORMER_SOLE := 0.017

var _failures: Array[String] = []
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "protagonist_model_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)

	Harness.stage = "the new model's import"
	await _check_new_model()

	Harness.stage = "the bone mapping"
	await _check_mapping("protagonist", NEW_MODEL, NEW_MAPPING, NEW_MIRRORED, [])
	await _check_mapping("former protagonist", FORMER_MODEL, FORMER_MAPPING, [], [])
	await _check_mapping("Q", Q_MODEL, Q_MAPPING, [], Q_POSED)

	Harness.stage = "the clips move the bodies the way they say"
	for model_path: String in [NEW_MODEL, FORMER_MODEL, Q_MODEL]:
		await _check_motion(model_path.get_file(), model_path)

	Harness.stage = "the scenes"
	await _check_player_scene()
	await _check_classroom_student()
	_check_assets_kept()

	_report()
	Harness.finish(
		self,
		_failures,
		(
			"the player is Protagonist_Character.glb with a complete, positional bone mapping; its "
			+ "clips resolve and move the limbs the right way on all three rigs; the former "
			+ "protagonist sits in the classroom as a student; Q binds as before."
		)
	)


# --- 1, 2: the import --------------------------------------------------------


func _check_new_model() -> void:
	var model := await _instance(NEW_MODEL)
	if model == null:
		return
	var skeleton := model.get_node_or_null(SKELETON_PATH) as Skeleton3D
	if skeleton == null:
		_failures.append("%s has no Skeleton3D at %s." % [NEW_MODEL, SKELETON_PATH])
		model.queue_free()
		return
	if CharacterAnimation.skeletons_in(model).size() != 1:
		_failures.append("%s imports more than one Skeleton3D." % NEW_MODEL)
	if skeleton.get_bone_count() != BONE_COUNT:
		_failures.append(
			"The new skeleton has %d bones, not %d." % [skeleton.get_bone_count(), BONE_COUNT]
		)
	_check_hierarchy(skeleton)
	_check_skinning(model, skeleton)
	_check_embedded_clips(model)
	model.queue_free()
	await process_frame


func _check_hierarchy(skeleton: Skeleton3D) -> void:
	var expected := HIERARCHY.duplicate()
	for side in ["L", "R"]:
		for finger: String in FINGERS:
			expected["%s_01_%s" % [finger, side]] = "Hand_%s" % side
			expected["%s_02_%s" % [finger, side]] = "%s_01_%s" % [finger, side]
			expected["%s_03_%s" % [finger, side]] = "%s_02_%s" % [finger, side]
	if expected.size() != BONE_COUNT:
		_failures.append(
			"This test lists %d bones, the rig has %d." % [expected.size(), BONE_COUNT]
		)
	for bone: String in expected:
		var index := skeleton.find_bone(bone)
		if index < 0:
			_failures.append("The new skeleton has no bone '%s'." % bone)
			continue
		var parent := skeleton.get_bone_parent(index)
		var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else ""
		if parent_name != String(expected[bone]):
			_failures.append(
				"'%s' hangs from '%s', expected '%s'." % [bone, parent_name, String(expected[bone])]
			)
	# The rig stands on its own origin: +Y up, toes forward (+Z), its `*_L` side at +X.
	var toe := skeleton.get_bone_global_rest(skeleton.find_bone("Toe_L")).origin
	var heel := skeleton.get_bone_global_rest(skeleton.find_bone("Foot_L")).origin
	if toe.z <= heel.z:
		_failures.append(
			"The new rig's toes do not point +Z (toe z %.3f, ankle z %.3f)." % [toe.z, heel.z]
		)
	var left := skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm_L")).origin
	_notes.append(
		"new rig: UpperArm_L at x %+.3f, toe z %+.3f vs ankle %+.3f" % [left.x, toe.z, heel.z]
	)


func _check_skinning(model: Node3D, skeleton: Skeleton3D) -> void:
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != MESH_COUNT:
		_failures.append("The new model has %d meshes, not %d." % [meshes.size(), MESH_COUNT])
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.skin == null:
			_failures.append("'%s' has no skin, so it would not follow the skeleton." % mesh.name)
			continue
		if mesh.get_node_or_null(mesh.skeleton) != skeleton:
			_failures.append(
				"'%s' is skinned to '%s', not the skeleton." % [mesh.name, String(mesh.skeleton)]
			)
		if mesh.skin.get_bind_count() != BONE_COUNT:
			_failures.append(
				(
					"'%s' binds %d joints, not %d."
					% [mesh.name, mesh.skin.get_bind_count(), BONE_COUNT]
				)
			)
		for bind in mesh.skin.get_bind_count():
			var bone_name := String(mesh.skin.get_bind_name(bind))
			if not bone_name.is_empty() and skeleton.find_bone(bone_name) < 0:
				_failures.append(
					"'%s' binds joint '%s', which is not a bone." % [mesh.name, bone_name]
				)


func _check_embedded_clips(model: Node3D) -> void:
	var player := model.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if player == null:
		_failures.append("The new model's embedded AnimationPlayer did not import.")
		return
	if not player.autoplay.is_empty() or player.is_playing():
		_failures.append(
			(
				"The embedded AnimationPlayer autoplays '%s'; the game drives the model."
				% player.autoplay
			)
		)
	var names := player.get_animation_list()
	if names.size() != EMBEDDED_CLIPS.size():
		_failures.append("The new model embeds %d clips: %s." % [names.size(), str(names)])
	var anim_root := player.get_node_or_null(player.root_node)
	for clip_name: String in EMBEDDED_CLIPS:
		if not player.has_animation(clip_name):
			_failures.append("The embedded clip '%s' is missing." % clip_name)
			continue
		var animation := player.get_animation(clip_name)
		if absf(animation.length - float(EMBEDDED_CLIPS[clip_name])) > 0.01:
			_failures.append(
				(
					"'%s' is %.4f s, recorded %.4f s."
					% [clip_name, animation.length, EMBEDDED_CLIPS[clip_name]]
				)
			)
		if animation.loop_mode != Animation.LOOP_NONE:
			_failures.append("'%s' imports looping (%d)." % [clip_name, animation.loop_mode])
		var unresolved := _unresolved_tracks(anim_root, animation)
		if not unresolved.is_empty():
			_failures.append(
				"'%s' has tracks that resolve to nothing: %s" % [clip_name, str(unresolved)]
			)
		_notes.append(
			(
				"embedded '%s': %.3f s, %d track(s)"
				% [clip_name, animation.length, animation.get_track_count()]
			)
		)


func _unresolved_tracks(anim_root: Node, animation: Animation) -> Array[String]:
	var unresolved: Array[String] = []
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var target: Node = null
		if anim_root != null:
			target = anim_root.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
		var sub := String(path.get_concatenated_subnames())
		if target == null:
			unresolved.append(String(path))
		elif target is Skeleton3D and (target as Skeleton3D).find_bone(sub) < 0:
			unresolved.append(String(path))
		elif (
			target is MeshInstance3D
			and animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE
		):
			if (target as MeshInstance3D).find_blend_shape_by_name(StringName(sub)) < 0:
				unresolved.append(String(path))
	return unresolved


# --- 3, 4: the mapping and the tracks ----------------------------------------


func _check_mapping(
	label: String, path: String, expected: Dictionary, mirrored: Array, posed: Array
) -> void:
	var model := await _instance(path)
	if model == null:
		return
	var player := _player_for(model)
	var report := CharacterAnimation.bind(model, player)
	if not bool(report.get("ok", false)):
		_failures.append("%s did not bind: %s" % [label, String(report.get("reason", "?"))])
		model.queue_free()
		return
	_notes.append("%s: %s" % [label, CharacterAnimation.describe(report)])
	var resolved: Dictionary = report["resolved"]
	for canonical: String in expected:
		if String(resolved.get(canonical, "")) != String(expected[canonical]):
			_failures.append(
				(
					"%s: '%s' resolved to '%s', expected '%s'."
					% [
						label,
						canonical,
						String(resolved.get(canonical, "")),
						String(expected[canonical])
					]
				)
			)
	for canonical: String in resolved:
		if not expected.has(canonical):
			_failures.append(
				(
					"%s: '%s' resolved to '%s', which this test does not expect."
					% [label, canonical, resolved[canonical]]
				)
			)
	if path == NEW_MODEL and not (report["missing"] as Array).is_empty():
		_failures.append(
			"%s: canonical bones with no bone on this rig: %s" % [label, str(report["missing"])]
		)
	if _sorted(report.get("mirrored", [])) != _sorted(mirrored):
		_failures.append(
			(
				"%s: mirrored pairs %s, expected %s."
				% [label, str(report.get("mirrored", [])), str(mirrored)]
			)
		)
	if _sorted(report.get("posed", [])) != _sorted(posed):
		_failures.append(
			(
				"%s: held at the modelled pose %s, expected %s."
				% [label, str(report.get("posed", [])), str(posed)]
			)
		)

	var skeleton := CharacterAnimation.skeletons_in(model)[0]
	var keyed := {}
	for clip_name in player.get_animation_list():
		var animation := player.get_animation(clip_name)
		for track in animation.get_track_count():
			var bone := String(animation.track_get_path(track).get_concatenated_subnames())
			if skeleton.find_bone(bone) < 0:
				_failures.append(
					(
						"%s: clip '%s' track %d points at '%s', not a bone."
						% [label, clip_name, track, bone]
					)
				)
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				_failures.append(
					"%s: clip '%s' has a track that is not a bone rotation." % [label, clip_name]
				)
			# A track holding rest at both ends keys nothing; one with any other key animates.
			var rest := (
				skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.get_rotation_quaternion()
			)
			for key in animation.track_get_key_count(track):
				var value: Quaternion = animation.track_get_key_value(track, key)
				if rad_to_deg(value.angle_to(rest)) > 0.01:
					keyed[bone] = true
	if path == NEW_MODEL:
		if _sorted(keyed.keys()) != _sorted(NEW_ANIMATED):
			_failures.append(
				(
					"The new rig animates %s; expected exactly %s."
					% [str(_sorted(keyed.keys())), str(NEW_ANIMATED)]
				)
			)
		var held: Array[String] = []
		for index in skeleton.get_bone_count():
			if not keyed.has(skeleton.get_bone_name(index)):
				held.append(skeleton.get_bone_name(index))
		_notes.append("new rig: %d joints animate, %d stay at rest" % [keyed.size(), held.size()])
		if keyed.size() + held.size() != BONE_COUNT:
			_failures.append("Animated and static joints do not add up to %d." % BONE_COUNT)
	model.queue_free()
	await process_frame


# --- 5: the limbs -------------------------------------------------------------


func _check_motion(label: String, path: String) -> void:
	var model := await _instance(path)
	if model == null:
		return
	var player := _player_for(model)
	var report := CharacterAnimation.bind(model, player)
	if not bool(report.get("ok", false)):
		model.queue_free()
		return
	var skeleton := CharacterAnimation.skeletons_in(model)[0]
	var resolved: Dictionary = report["resolved"]
	var posed: Array = report.get("posed", [])
	var rest := {}
	for canonical: String in resolved:
		rest[canonical] = _joint(skeleton, String(resolved[canonical]), true)
	var worst_twist := 0.0
	for clip_name: String in MEASURED_CLIPS:
		if not CharacterAnimation.play(player, clip_name):
			_failures.append("%s: '%s' would not play." % [label, clip_name])
			continue
		var length := (
			player
			. get_animation("%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name])
			. length
		)
		var travel_min := Vector3(INF, INF, INF)
		var travel_max := Vector3(-INF, -INF, -INF)
		var knee_low := INF
		var knee_high := -INF
		for step in SAMPLES + 1:
			player.seek(length * float(step) / float(SAMPLES), true)
			var at := {}
			for canonical: String in resolved:
				at[canonical] = _joint(skeleton, String(resolved[canonical]), false)
			worst_twist = maxf(worst_twist, _check_twists(label, clip_name, skeleton, resolved))
			for side in ["L", "R"]:
				var knee := (
					_bend(at, side, ["thigh", "shin", "foot"])
					- _bend(rest, side, ["thigh", "shin", "foot"])
				)
				if side == "L":
					knee_low = minf(knee_low, knee)
					knee_high = maxf(knee_high, knee)
				if knee < -0.1:
					_failures.append(
						(
							"%s: '%s' bends the %s knee backwards (%+.2f against rest)."
							% [label, clip_name, side, knee]
						)
					)
				if not posed.has("fore_arm.%s" % side) and not posed.has("upper_arm.%s" % side):
					var elbow := (
						_bend(at, side, ["upper_arm", "fore_arm", "hand"])
						- _bend(rest, side, ["upper_arm", "fore_arm", "hand"])
					)
					if elbow > 0.1:
						_failures.append(
							(
								"%s: '%s' bends the %s elbow backwards (%+.2f against rest)."
								% [label, clip_name, side, elbow]
							)
						)
				_check_hand(label, clip_name, side, at, rest, posed)
			if clip_name == "sit_idle" and step == 0:
				_check_seated(label, at)
			travel_min = travel_min.min(at["foot.L"])
			travel_max = travel_max.max(at["foot.L"])
		var travel := travel_max - travel_min
		if clip_name == "walk" or clip_name == "jog":
			_notes.append(
				(
					"%s %s: foot.L travel z %.3f x %.3f m, knee %+.2f..%+.2f"
					% [label, clip_name, travel.z, travel.x, knee_low, knee_high]
				)
			)
			if travel.z < 0.12:
				_failures.append(
					(
						"%s: '%s' moves the foot only %.3f m forward and back."
						% [label, clip_name, travel.z]
					)
				)
			if travel.x > travel.z * 0.5:
				_failures.append(
					(
						"%s: '%s' swings the foot %.3f m sideways against %.3f m forward."
						% [label, clip_name, travel.x, travel.z]
					)
				)
			if knee_high < 0.2:
				_failures.append(
					"%s: '%s' barely bends the knee (%+.2f)." % [label, clip_name, knee_high]
				)
		player.stop()
	_notes.append("%s: widest twist about a bone's own length %.1f°" % [label, worst_twist])
	model.queue_free()
	await process_frame


## Seated: the knees are in front of the hips and the shins hang down from them.
func _check_seated(label: String, at: Dictionary) -> void:
	for side in ["L", "R"]:
		var thigh: Vector3 = at["shin.%s" % side] - at["thigh.%s" % side]
		var shin: Vector3 = at["foot.%s" % side] - at["shin.%s" % side]
		_notes.append(
			(
				"%s seated %s: knee %+.2f m ahead of the hip, foot %.2f m below the knee"
				% [label, side, thigh.z, -shin.y]
			)
		)
		if thigh.z < 0.2:
			_failures.append(
				"%s: seated, the %s knee is %+.2f m ahead of the hip." % [label, side, thigh.z]
			)
		if -shin.y < 0.2:
			_failures.append(
				(
					"%s: seated, the %s shin does not hang (foot %.2f m below the knee)."
					% [label, side, -shin.y]
				)
			)


## A hand stays below its shoulder, on its own side of the body. A limb held at its modelled
## pose (Q's carried forearm) is measured against that pose instead of a hanging arm.
func _check_hand(
	label: String, clip_name: String, side: String, at: Dictionary, rest: Dictionary, posed: Array
) -> void:
	var shoulder: Vector3 = at["upper_arm.%s" % side]
	var hand: Vector3 = at["hand.%s" % side]
	var rest_drop: float = (
		(rest["upper_arm.%s" % side] as Vector3).y - (rest["hand.%s" % side] as Vector3).y
	)
	var drop := shoulder.y - hand.y
	if drop < 0.03 or (not posed.has("hand.%s" % side) and drop < minf(rest_drop, 0.2)):
		_failures.append(
			(
				"%s: '%s' raises the %s hand (%.2f m below the shoulder, modelled %.2f)."
				% [label, clip_name, side, drop, rest_drop]
			)
		)
	if signf(hand.x) != signf((rest["hand.%s" % side] as Vector3).x):
		_failures.append(
			(
				"%s: '%s' carries the %s hand across the body (x %+.3f)."
				% [label, clip_name, side, hand.x]
			)
		)


## The twist each animated bone carries about its own length, against its rest.
func _check_twists(
	label: String, clip_name: String, skeleton: Skeleton3D, resolved: Dictionary
) -> float:
	var widest := 0.0
	for canonical: String in resolved:
		var index := skeleton.find_bone(String(resolved[canonical]))
		var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var delta := rest.inverse() * skeleton.get_bone_pose_rotation(index)
		if delta.w < 0.0:
			delta = -delta
		var twist := absf(rad_to_deg(2.0 * atan2(delta.y, delta.w)))
		widest = maxf(widest, twist)
		var limit := (
			MAX_HAND_FOOT_TWIST_DEGREES
			if canonical.begins_with("hand") or canonical.begins_with("foot")
			else MAX_TWIST_DEGREES
		)
		if twist > limit:
			_failures.append(
				(
					"%s: '%s' twists '%s' %.1f° about its own length (allowed %.1f°)."
					% [label, clip_name, canonical, twist, limit]
				)
			)
	return widest


## Signed fold of a three-joint chain about the character's side axis (X of upper × lower).
func _bend(at: Dictionary, side: String, chain: Array) -> float:
	var a: Vector3 = at["%s.%s" % [chain[0], side]]
	var b: Vector3 = at["%s.%s" % [chain[1], side]]
	var c: Vector3 = at["%s.%s" % [chain[2], side]]
	return (b - a).normalized().cross((c - b).normalized()).x


## A bone's position in skeleton space, composed from the local poses (or rests) up the chain,
## so it does not depend on when the skeleton next refreshes its cached global poses.
func _joint(skeleton: Skeleton3D, bone: String, rest: bool) -> Vector3:
	var index := skeleton.find_bone(bone)
	var transform := Transform3D.IDENTITY
	while index >= 0:
		var local := skeleton.get_bone_rest(index) if rest else skeleton.get_bone_pose(index)
		transform = local * transform
		index = skeleton.get_bone_parent(index)
	return transform.origin


# --- 6: the scenes ------------------------------------------------------------


func _check_player_scene() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_failures.append("%s could not be loaded." % PLAYER_SCENE)
		return
	var player := packed.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var wrapper := player.get_node_or_null(^"VisualPivot/Visual/Model") as CharacterVisualAnimation
	if wrapper == null or wrapper.scene_file_path != PROTAGONIST_WRAPPER:
		_failures.append("The player's visual is not %s." % PROTAGONIST_WRAPPER)
	else:
		var model := wrapper.get_node_or_null(^"Model")
		if model == null or model.scene_file_path != NEW_MODEL:
			_failures.append(
				(
					"The player's protagonist instances '%s', not %s."
					% [model.scene_file_path if model != null else "nothing", NEW_MODEL]
				)
			)
		if (
			not wrapper.is_bound()
			or wrapper.get_skeleton() == null
			or wrapper.get_skeleton().get_bone_count() != BONE_COUNT
		):
			_failures.append("The player's protagonist did not bind to the 60-bone skeleton.")
		elif wrapper.get_current_clip() != "idle":
			_failures.append(
				"The player's protagonist opens on '%s', not idle." % wrapper.get_current_clip()
			)
		var embedded := wrapper.get_node_or_null(^"Model/AnimationPlayer") as AnimationPlayer
		if embedded != null and embedded.is_playing():
			_failures.append("The model's own embedded clips are playing under the game's clips.")
	player.queue_free()
	await process_frame


func _check_classroom_student() -> void:
	var packed := load(CLASSROOM) as PackedScene
	if packed == null:
		_failures.append("%s could not be loaded." % CLASSROOM)
		return
	var classroom := packed.instantiate() as Node3D
	root.add_child(classroom)
	await process_frame
	await process_frame
	var student := classroom.get_node_or_null(^"Actors/SeatedStudent") as CharacterVisualAnimation
	if student == null or student.scene_file_path != STUDENT_WRAPPER:
		_failures.append(
			"The classroom has no seated student from %s at Actors/SeatedStudent." % STUDENT_WRAPPER
		)
		classroom.queue_free()
		return
	var model := student.get_node_or_null(^"Model")
	if model == null or model.scene_file_path != FORMER_MODEL:
		_failures.append("The classroom student is not the former protagonist (%s)." % FORMER_MODEL)
	if (
		not student.is_bound()
		or not student.is_seated()
		or student.get_current_clip() != "sit_idle"
	):
		_failures.append(
			"The classroom student is not seated (clip '%s')." % student.get_current_clip()
		)
	if student.get_locomotion_body() != null:
		_failures.append(
			(
				"The classroom student found a body to be driven by: %s."
				% student.get_locomotion_body()
			)
		)
	for node in student.find_children("*", "", true, false):
		if (
			node is CollisionObject3D
			or node is CollisionShape3D
			or node is Interactable
			or node is PlayerController
		):
			_failures.append(
				(
					"The classroom student carries '%s' (%s); it is scenery."
					% [node.name, node.get_class()]
				)
			)
	var everything := classroom.find_children("*", "", true, false)
	for node in everything:
		if node is PlayerController:
			_failures.append("The classroom contains a player controller ('%s')." % node.name)
	if student.is_in_group("player"):
		_failures.append("The classroom student is in the 'player' group.")
	for node in everything:
		if not node is Interactable:
			continue
		var interactable := node as Interactable
		for outline: String in interactable.outline_paths:
			var target := interactable.get_node_or_null(NodePath(outline))
			if target != null and (target == student or student.is_ancestor_of(target)):
				_failures.append("'%s' outlines the classroom student." % interactable.name)
	if absf(student.global_basis.z.normalized().dot(Vector3.FORWARD) - 1.0) > 0.05:
		_failures.append(
			"The classroom student does not face the blackboard (−Z): %s." % student.global_basis.z
		)
	await _check_student_on_seat(student)
	classroom.queue_free()
	await process_frame


## Measured off the seated skeleton: the soles on the floor, the hips on the seat, the knees
## towards the desk, and all of it at desk A1's chair.
func _check_student_on_seat(student: CharacterVisualAnimation) -> void:
	await process_frame
	var skeleton := student.get_skeleton()
	var resolved: Dictionary = student.get_bind_report().get("resolved", {})
	if skeleton == null or not resolved.has("thigh.L") or not resolved.has("foot.L"):
		_failures.append("The classroom student has no legs to measure.")
		return
	var to_world := skeleton.global_transform
	var hip := to_world * _joint(skeleton, String(resolved["thigh.L"]), false)
	var knee := to_world * _joint(skeleton, String(resolved["shin.L"]), false)
	var ankle := to_world * _joint(skeleton, String(resolved["foot.L"]), false)
	# Seated, the soles are on the floor, so the ankle is as high above it as it is above the
	# soles standing.
	var ankle_rest := _joint(skeleton, String(resolved["foot.L"]), true).y - FORMER_SOLE
	_notes.append("classroom student: hip %s, knee %s, ankle %s" % [hip, knee, ankle])
	if absf(ankle.y - ankle_rest) > 0.05:
		_failures.append(
			(
				"The student's ankle is %.3f m up; seated on the floor it is %.3f m."
				% [ankle.y, ankle_rest]
			)
		)
	if hip.y < SEAT_TOP or hip.y > SEAT_TOP + 0.15:
		_failures.append(
			"The student's hip joint is at %.3f m; the seat top is %.3f m." % [hip.y, SEAT_TOP]
		)
	if knee.z > hip.z - 0.2:
		_failures.append(
			(
				"The student's knee is not towards the desk (hip z %.2f, knee z %.2f)."
				% [hip.z, knee.z]
			)
		)
	var seat := SEAT_DESK + Vector3(0.0, 0.0, 0.65)
	if Vector2(hip.x - seat.x, hip.z - seat.z).length() > 0.15:
		_failures.append("The student's hips are at %s, not on desk A1's chair (%s)." % [hip, seat])


func _check_assets_kept() -> void:
	for path: String in [
		FORMER_MODEL, FORMER_MODEL + ".import", NEW_MODEL, NEW_MODEL + ".import", Q_MODEL
	]:
		if not FileAccess.file_exists(path):
			_failures.append("%s is missing." % path)
	var q_wrapper := load(Q_WRAPPER) as PackedScene
	if q_wrapper == null:
		_failures.append("%s could not be loaded." % Q_WRAPPER)
		return
	var q := q_wrapper.instantiate()
	var q_model := q.get_node_or_null(^"Model")
	if q_model == null or q_model.scene_file_path != Q_MODEL:
		_failures.append("q.tscn no longer instances %s." % Q_MODEL)
	q.free()


# --- helpers -----------------------------------------------------------------


func _instance(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("%s could not be loaded." % path)
		return null
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	return model


func _player_for(model: Node3D) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "BoundAnimationPlayer"
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	return player


func _sorted(values: Array) -> Array:
	var copy: Array = []
	for value in values:
		copy.append(String(value))
	copy.sort()
	return copy


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	var chunk := ""
	var index := 0
	for line in _notes:
		if chunk != "" and chunk.length() + line.length() > 2800:
			index += 1
			print("::notice title=protagonist model (%d)::%s" % [index, chunk])
			chunk = ""
		chunk = line if chunk == "" else "%s|%s" % [chunk, line]
	if chunk != "":
		print("::notice title=protagonist model (%d)::%s" % [index + 1, chunk])
