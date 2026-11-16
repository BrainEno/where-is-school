extends SkeletonModifier3D
## Experiment A of the character art review (issue #188): body language layered on top of
## whatever the production clips play, without touching the clips, the motion profiles, the
## GLBs or `CharacterAnimation`.
##
## It is a `SkeletonModifier3D` like the production `NpcGaze`: added under a character's
## `Skeleton3D` at run time, it runs after the `AnimationPlayer` every frame and rotates bone
## poses about *character-space* axes, around each bone's own joint. Godot discards a
## modifier's result before the next frame, so nothing accumulates and removing the node (or
## setting `intensity` to 0) gives back exactly the production pose.
##
## Why character-space axes rather than the clips' semantic frames: the two things this
## experiment needs most are bones no clip keys — the protagonist's clavicles (shoulders up
## and forward) and his thirty finger joints (half-closed hands) — and a clavicle runs along
## the skeleton's side axis, where `CharacterAnimation.semantic_frame()` has no frame.
## Skeleton space on both models is the character's own space (+Y up, +Z forward, +X the
## character's left), measured from the GLBs, so "about Z" is the same movement on both rigs.
##
## Axis sign conventions used in `PROFILES` (all in skeleton space, degrees):
##   about X, positive   leans a spine/neck/head forward, nods down; swings a hanging limb's
##                       far end backward (so elbow flexion is negative); turns an eye down
##   about Y, positive   turns the front towards +X (the character's left)
##   about Z, positive   moves the far end of a +X-side limb up (a clavicle rises); moves a
##                       vertical bone's top towards -X
## An entry marked mirrored is multiplied by the side the bone is on (+1 at +X, -1 at -X), so
## one number describes both sides symmetrically: "+9 about Z, mirrored" raises both
## shoulders, "-12 about Z, mirrored" draws both arms in.

## Per-character tables. `static` is the stance; the rest are small dynamic behaviours.
const PROFILES := {
	"protagonist_withdrawn": {
		"label": "protagonist: tense, withdrawn, hesitant",
		# [bone candidates, axis, degrees, mirrored]
		"static": [
			[["Chest"], Vector3.RIGHT, 4.0, false],
			# Shoulders hitched up towards the ears and rolled forward: the held neck.
			[["Clavicle_L", "Clavicle_R"], Vector3.BACK, 9.0, true],
			[["Clavicle_L", "Clavicle_R"], Vector3.UP, -9.0, true],
			# The head carried forward of the chest, then dropped.
			[["Neck"], Vector3.RIGHT, 7.0, false],
			[["Head"], Vector3.RIGHT, 6.0, false],
			# The A-pose gap closed: arms against the body, a little in front of it.
			[["UpperArm_L", "UpperArm_R"], Vector3.BACK, -13.0, true],
			[["UpperArm_L", "UpperArm_R"], Vector3.RIGHT, -4.0, false],
			[["Forearm_L", "Forearm_R"], Vector3.RIGHT, -12.0, false],
			[["Forearm_L", "Forearm_R"], Vector3.BACK, -6.0, true],
		],
		# Degrees per phalanx (01, 02, 03): a hand that is half closed, thumb tucked.
		"finger_curl": [32.0, 44.0, 30.0],
		"thumb_curl": [14.0, 20.0, 12.0],
		# Eyes: [down, towards +X] in degrees.
		"eyes": Vector2(9.0, 0.0),
		# How the trunk answers a change of speed: stiff and damped, no follow-through.
		"spring": {"frequency": 3.6, "damping": 1.0, "gain": 0.35, "limit": 3.0},
		# Stopping is followed by a glance aside, shoulders hitched: hesitation.
		"hesitate": {"seconds": 1.7, "head_yaw": 24.0, "neck_pitch": 5.0, "shoulder": 5.0},
		# Starting to walk: for the first half second the head goes lower and the arms tighter.
		"reluctant_start": {"seconds": 0.6, "head_pitch": 6.0, "arm_in": 4.0},
		"walk_roll": 0.0,
		"idle_sway": 0.0,
		# Facing a talking partner: the body and gaze turn away, the near shoulder rises.
		"converse": "avoid",
	},
	"q_overfamiliar": {
		"label": "Q: loose, heavy, over-familiar",
		"static": [
			# Head cocked and the chin a little up: at ease, slightly brash.
			[["Head"], Vector3.BACK, 6.0, false],
			[["Head"], Vector3.RIGHT, -4.0, false],
			# Arms hang out from the belly with their own weight, not pinned.
			[["UpperArm.L", "UpperArm.R"], Vector3.BACK, 3.0, true],
			# The right forearm is modelled pointing forward (a held, presenting hand that
			# reads as a permanent gesture); lowered here to a loose bent elbow.
			[["LowerArm.R"], Vector3.RIGHT, 52.0, false],
		],
		"finger_curl": [0.0, 0.0, 0.0],
		"thumb_curl": [0.0, 0.0, 0.0],
		"eyes": Vector2.ZERO,
		# The belly carries momentum: a stop rocks the trunk forward and back.
		"spring": {"frequency": 1.5, "damping": 0.28, "gain": 2.6, "limit": 9.0},
		"hesitate": {},
		"reluctant_start": {},
		# Weight shifted from foot to foot on every stride, and a slow sway when standing.
		"walk_roll": 4.5,
		"idle_sway": 2.4,
		"converse": "approach",
	},
}

@export var profile_name: String = "protagonist_withdrawn"
## 0 is the production pose exactly; 1 the full experiment.
@export_range(0.0, 1.5, 0.05) var intensity: float = 1.0

## The wrapper whose clips this rides on (for the locomotion state and walk phase).
var animator: CharacterVisualAnimation = null
## Someone to talk to: `converse` turns towards or away from them. Null: nobody.
var partner: Node3D = null

var _resolved_for: Skeleton3D = null
var _bones := {}  # bone name -> index
var _side := {}  # bone index -> +1 / -1 / 0
var _depth := {}  # bone index -> depth in the hierarchy
var _finger_axes := {}  # bone index -> [rest curl axis (skeleton space), phalanx 0..2, thumb]
var _rest_basis := {}  # bone index -> global rest basis
var _time := 0.0
var _last_state: StringName = &""
var _hesitate_left := 0.0
var _hesitate_sign := 1.0
var _start_left := 0.0
var _speed_prev := 0.0
var _accel := 0.0
var _spring_x := 0.0
var _spring_v := 0.0
var _converse_weight := 0.0
var _last_applied := {}


func setup(with_animator: CharacterVisualAnimation, with_profile: String, with_intensity: float = 1.0) -> void:
	animator = with_animator
	profile_name = with_profile
	intensity = with_intensity


func get_profile() -> Dictionary:
	return PROFILES.get(profile_name, {})


## Bone name -> degrees of the largest rotation applied in the last frame, for the capture log.
func get_last_applied() -> Dictionary:
	return _last_applied


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var profile := get_profile()
	if skeleton == null or profile.is_empty():
		return
	if _resolved_for != skeleton:
		_resolve(skeleton)
	_time += delta
	_update_state(profile, delta)
	if intensity <= 0.0:
		_last_applied = {}
		return
	# bone index -> Basis to pre-multiply onto its global pose, accumulated, then applied
	# parents first so every child sees its parent's new pose.
	var turns := {}
	for entry: Array in profile["static"]:
		for bone_name: String in entry[0]:
			_add_turn(turns, bone_name, entry[1], float(entry[2]) * (_side_of(bone_name) if bool(entry[3]) else 1.0))
	_add_dynamic(turns, profile, skeleton)
	var order := turns.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return int(_depth[a]) < int(_depth[b]))
	_last_applied = {}
	for index: int in order:
		var turn: Basis = turns[index]
		var pose := skeleton.get_bone_global_pose(index)
		pose.basis = turn * pose.basis
		skeleton.set_bone_global_pose(index, pose)
		_last_applied[skeleton.get_bone_name(index)] = snappedf(rad_to_deg(turn.get_rotation_quaternion().get_angle()), 0.1)
	_apply_fingers(skeleton, profile)
	_apply_reach(skeleton, profile)


func _update_state(profile: Dictionary, delta: float) -> void:
	var state: StringName = &"idle"
	var speed := 0.0
	if animator != null and is_instance_valid(animator):
		state = animator.get_locomotion_state()
		speed = animator.get_planar_speed()
	if state != _last_state:
		var hesitate: Dictionary = profile.get("hesitate", {})
		if state == &"idle" and (_last_state == &"walk" or _last_state == &"jog") and not hesitate.is_empty():
			_hesitate_left = float(hesitate["seconds"])
			_hesitate_sign = -_hesitate_sign
		var start: Dictionary = profile.get("reluctant_start", {})
		if state == &"walk" and _last_state == &"idle" and not start.is_empty():
			_start_left = float(start["seconds"])
		_last_state = state
	_hesitate_left = maxf(_hesitate_left - delta, 0.0)
	_start_left = maxf(_start_left - delta, 0.0)
	# A damped spring driven by the change of speed: the trunk's inertia.
	if delta > 0.0:
		var raw := (speed - _speed_prev) / delta
		_accel = lerpf(_accel, clampf(raw, -12.0, 12.0), clampf(delta * 12.0, 0.0, 1.0))
		_speed_prev = speed
		var spring: Dictionary = profile["spring"]
		var omega := TAU * float(spring["frequency"])
		var force := -omega * omega * _spring_x - 2.0 * float(spring["damping"]) * omega * _spring_v - float(spring["gain"]) * _accel * omega
		_spring_v += force * minf(delta, 0.05)
		_spring_x += _spring_v * minf(delta, 0.05)
		var limit := float(spring["limit"])
		_spring_x = clampf(_spring_x, -limit, limit)
	var wanted := 1.0 if partner != null and is_instance_valid(partner) else 0.0
	_converse_weight = move_toward(_converse_weight, wanted, delta / 0.6)


func _add_dynamic(turns: Dictionary, profile: Dictionary, skeleton: Skeleton3D) -> void:
	var spine := "Spine"
	_add_turn(turns, spine, Vector3.RIGHT, _spring_x)
	# Walk: the trunk rolls over the standing leg once per stride; the head rights itself.
	var walk_roll := float(profile.get("walk_roll", 0.0))
	var phase := _walk_phase()
	if walk_roll > 0.0 and phase >= 0.0:
		var roll := sin(TAU * phase) * walk_roll
		_add_turn(turns, spine, Vector3.BACK, roll)
		_add_turn(turns, "Head", Vector3.BACK, -roll * 0.6)
	var sway := float(profile.get("idle_sway", 0.0))
	if sway > 0.0 and phase < 0.0:
		var s := sin(TAU * _time / 3.4)
		_add_turn(turns, spine, Vector3.BACK, s * sway)
		_add_turn(turns, "Head", Vector3.BACK, -s * sway * 0.4)
		_add_turn(turns, spine, Vector3.UP, sin(TAU * _time / 5.1) * sway * 0.8)
	var hesitate: Dictionary = profile.get("hesitate", {})
	if _hesitate_left > 0.0 and not hesitate.is_empty():
		var total := float(hesitate["seconds"])
		var bell := sin(PI * (1.0 - _hesitate_left / total))
		_add_turn(turns, "Head", Vector3.UP, float(hesitate["head_yaw"]) * bell * _hesitate_sign)
		_add_turn(turns, "Neck", Vector3.RIGHT, float(hesitate["neck_pitch"]) * bell)
		for clavicle: String in ["Clavicle_L", "Clavicle_R"]:
			_add_turn(turns, clavicle, Vector3.BACK, float(hesitate["shoulder"]) * bell * _side_of(clavicle))
	var start: Dictionary = profile.get("reluctant_start", {})
	if _start_left > 0.0 and not start.is_empty():
		var w := _start_left / float(start["seconds"])
		_add_turn(turns, "Head", Vector3.RIGHT, float(start["head_pitch"]) * w)
		for arm: String in ["UpperArm_L", "UpperArm_R"]:
			_add_turn(turns, arm, Vector3.BACK, -float(start["arm_in"]) * w * _side_of(arm))
	var eyes: Vector2 = profile.get("eyes", Vector2.ZERO)
	var eye_yaw := eyes.y
	var eye_down := eyes.x
	# Conversation.
	var mode := String(profile.get("converse", ""))
	if _converse_weight > 0.0 and partner != null and is_instance_valid(partner):
		var local := skeleton.global_transform.affine_inverse() * partner.global_position
		var bearing := rad_to_deg(atan2(local.x, local.z))
		var toward := signf(bearing) if absf(bearing) > 0.5 else 1.0
		var w := _converse_weight
		if mode == "avoid":
			_add_turn(turns, "Spine", Vector3.UP, -toward * 9.0 * w)
			_add_turn(turns, "Neck", Vector3.UP, -toward * 8.0 * w)
			_add_turn(turns, "Head", Vector3.UP, -toward * 14.0 * w)
			_add_turn(turns, "Head", Vector3.RIGHT, 4.0 * w)
			for clavicle: String in ["Clavicle_L", "Clavicle_R"]:
				if signf(_side_of(clavicle)) == toward:
					_add_turn(turns, clavicle, Vector3.BACK, 6.0 * w * _side_of(clavicle))
			eye_yaw += -toward * 16.0 * w
			eye_down += 6.0 * w
		elif mode == "approach":
			var turn := clampf(bearing, -55.0, 55.0)
			_add_turn(turns, "Spine", Vector3.UP, turn * 0.35 * w)
			# Leaning in instead of back: into the other person's space.
			_add_turn(turns, "Spine", Vector3.RIGHT, 11.0 * w)
			_add_turn(turns, "Neck", Vector3.UP, turn * 0.3 * w)
			_add_turn(turns, "Head", Vector3.UP, turn * 0.35 * w)
			_add_turn(turns, "Neck", Vector3.RIGHT, 4.0 * w)
	for eye: String in ["Eye_L", "Eye_R"]:
		if eye_down != 0.0:
			_add_turn(turns, eye, Vector3.RIGHT, eye_down)
		if eye_yaw != 0.0:
			_add_turn(turns, eye, Vector3.UP, eye_yaw)


## Fingers curl about an axis taken from the rest pose (the finger's direction crossed with
## the palm's, the palm facing the body) and carried along with the hand's current pose.
func _apply_fingers(skeleton: Skeleton3D, profile: Dictionary) -> void:
	var curls: Array = profile.get("finger_curl", [])
	var thumbs: Array = profile.get("thumb_curl", [])
	if _finger_axes.is_empty():
		return
	var order := _finger_axes.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return int(_depth[a]) < int(_depth[b]))
	for index: int in order:
		var info: Array = _finger_axes[index]
		var phalanx: int = info[1]
		var degrees := float((thumbs if bool(info[2]) else curls)[phalanx]) * intensity
		if is_zero_approx(degrees):
			continue
		var pose := skeleton.get_bone_global_pose(index)
		var carried: Basis = pose.basis.orthonormalized() * (_rest_basis[index] as Basis).inverse()
		var axis: Vector3 = (carried * (info[0] as Vector3)).normalized()
		pose.basis = Basis(axis, deg_to_rad(degrees)) * pose.basis
		skeleton.set_bone_global_pose(index, pose)


## Q, in conversation, puts a hand towards the other person's near shoulder: the arm on that
## side is turned (from the shoulder only) until the hand points at the shoulder.
func _apply_reach(skeleton: Skeleton3D, profile: Dictionary) -> void:
	if String(profile.get("converse", "")) != "approach" or _converse_weight <= 0.0:
		return
	if partner == null or not is_instance_valid(partner):
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var local := to_skeleton * partner.global_position
	var side := 1.0 if local.x >= 0.0 else -1.0
	var arm_name := "UpperArm.R" if side > 0.0 else "UpperArm.L"
	var hand_name := "Hand.R" if side > 0.0 else "Hand.L"
	if not _bones.has(arm_name) or not _bones.has(hand_name):
		return
	var arm: int = _bones[arm_name]
	var hand: int = _bones[hand_name]
	# The partner's upper arm on Q's side: a hand put on someone, not a point at their face.
	var toward_q := (Vector3(-local.x, 0.0, -local.z)).normalized()
	var target := local + Vector3.UP * 1.18 + toward_q * 0.18
	var shoulder := skeleton.get_bone_global_pose(arm).origin
	var hand_at := skeleton.get_bone_global_pose(hand).origin
	var current := (hand_at - shoulder).normalized()
	var wanted := (target - shoulder).normalized()
	if current.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
		return
	var arc := Quaternion(current, wanted)
	var weighted := Quaternion.IDENTITY.slerp(arc, 0.85 * _converse_weight * clampf(intensity, 0.0, 1.0))
	var pose := skeleton.get_bone_global_pose(arm)
	pose.basis = Basis(weighted) * pose.basis
	skeleton.set_bone_global_pose(arm, pose)


func _add_turn(turns: Dictionary, bone_name: String, axis: Vector3, degrees: float) -> void:
	if not _bones.has(bone_name) or is_zero_approx(degrees):
		return
	var index: int = _bones[bone_name]
	var turn := Basis(axis.normalized(), deg_to_rad(degrees * intensity))
	turns[index] = turn * (turns[index] as Basis) if turns.has(index) else turn


func _side_of(bone_name: String) -> float:
	if not _bones.has(bone_name):
		return 0.0
	return float(_side.get(_bones[bone_name], 0.0))


## Walk / jog phase 0..1 of the clip the animator is playing, or -1 when it is not moving.
func _walk_phase() -> float:
	if animator == null or not is_instance_valid(animator):
		return -1.0
	var player := animator.get_animation_player()
	if player == null or player.current_animation.is_empty():
		return -1.0
	var clip := String(player.current_animation)
	if not (clip.ends_with("/walk") or clip.ends_with("/jog")):
		return -1.0
	var length := player.current_animation_length
	return fposmod(player.current_animation_position, length) / length if length > 0.0 else -1.0


func _resolve(skeleton: Skeleton3D) -> void:
	_resolved_for = skeleton
	_bones.clear()
	_side.clear()
	_depth.clear()
	_finger_axes.clear()
	_rest_basis.clear()
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		_bones[bone_name] = index
		var rest := skeleton.get_bone_global_rest(index)
		_rest_basis[index] = rest.basis.orthonormalized()
		var x := rest.origin.x
		_side[index] = 0.0 if absf(x) < 0.005 else signf(x)
		var depth := 0
		var parent := skeleton.get_bone_parent(index)
		while parent >= 0:
			depth += 1
			parent = skeleton.get_bone_parent(parent)
		_depth[index] = depth
	# `Neck_2` is how Godot names the protagonist's neck (a glTF node name clash).
	if not _bones.has("Neck") and _bones.has("Neck_2"):
		_bones["Neck"] = _bones["Neck_2"]
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		var finger := -1
		var thumb := bone_name.begins_with("Thumb_")
		for stem: String in ["Index_", "Middle_", "Ring_", "Little_", "Thumb_"]:
			if bone_name.begins_with(stem):
				finger = int(bone_name.substr(stem.length(), 2)) - 1
		if finger < 0 or finger > 2:
			continue
		var along: Vector3 = (_rest_basis[index] as Basis).y.normalized()
		var palm := Vector3(-float(_side[index]), 0.0, 0.0)
		palm = (palm - along * along.dot(palm))
		if palm.length_squared() < 0.0001:
			continue
		var axis := along.cross(palm.normalized()).normalized()
		_finger_axes[index] = [axis, finger, thumb]
