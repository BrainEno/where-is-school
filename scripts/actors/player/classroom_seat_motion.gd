extends RefCounted
## One timeline for the rig's pivot, wrist, boots and chair slide. The actor's feet
## remain on the seat mark during the transfer; reach for a tucked chair from the side first.

const Limb = preload("res://scripts/actors/character_limb_contact.gd")
const STAND := "classroom_rise"
const SIT := "classroom_sit"
const STAND_SECONDS := 0.94
const SIT_SECONDS := 0.99
const PULL_SECONDS := 0.78
const CUSHION_TO_THIGH := 0.061

var chair: PushableChair
var _visual: Node3D
var _animator: CharacterVisualAnimation
var _floor: Vector3
var _standing: float
var _seated: float
var _from_tilt: float
var _slide := false
var _joints: Dictionary


func _init(
	at: PushableChair, visual: Node3D, animator: CharacterVisualAnimation, standing: float
) -> void:
	chair = at
	_visual = visual
	_animator = animator
	_standing = standing
	_floor = at.home_mark()
	_joints = Limb.bind(animator)
	# Measure the thigh/seat relationship on the live rig. The thigh joint sits one
	# trouser radius above the wooden surface; the boot straps don't determine hip height.
	var leg: Limb = _joints.get("foot.L")
	var rest_thigh := 0.86
	if leg != null:
		rest_thigh = leg.skeleton.get_bone_global_rest(leg.joints.x).origin.y * leg.skeleton.global_basis.y.length()
	_seated = _standing + chair.seat_surface_height() - _floor.y + CUSHION_TO_THIGH - rest_thigh


func set_seated_pivot(tilt: float) -> void:
	_visual.position = Vector3.UP * _seated
	_visual.rotation.x = tilt


func plant_seated() -> void:
	_plant(1.0, 1.0)


func start() -> void:
	_from_tilt = _visual.rotation.x
	_slide = chair.is_pushed_back()
	chair.start_slide()


func sample_stand(t: float) -> void:
	_animator.sample_action(STAND, t)
	# Tuck the heels, hinge over them, then extend. The last part is a shoulder
	# settle, not a second lift. The pivot tilts only to come out of the waking slump.
	var lift := smoothstep(0.24, 0.88, t)
	var forward := 0.09 * smoothstep(0.08, 0.43, t) * (1.0 - smoothstep(0.46, 1.0, t))
	_visual.position = Vector3(0, lerpf(_seated, _standing, lift), forward)
	_visual.rotation.x = lerpf(_from_tilt, 0.0, smoothstep(0.0, 0.3, t))
	chair.sample_slide(smoothstep(0.20, 0.68, t))
	var near_foot := 1.0 - smoothstep(0.04, 0.28, t)
	var far_foot := 1.0 - smoothstep(0.11, 0.32, t)
	# The feet stay by the knees until the body has come over them; unload IK into
	# the neutral feet only while the stand straightens all the way.
	_plant(near_foot, far_foot, (1.0 - smoothstep(0.74, 1.0, t)), 0.12)
	_hold_chair(smoothstep(0.03, 0.20, t) * (1.0 - smoothstep(0.43, 0.66, t)))


## A standing actor reaches from the flank, not from inside the tucked chair.
## Use the early brace of the existing sit with the feet planted on this mark.
func pull_out(actor: Node3D, flank: float) -> void:
	chair.start_slide()
	var feet := actor.global_position
	var tween := actor.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_sample_pull.bind(feet, flank), 0.0, 1.0, PULL_SECONDS)
	await tween.finished
	chair.snap_back()
	_animator.release_sampled_action()


func _sample_pull(t: float, feet: Vector3, flank: float) -> void:
	var reach := smoothstep(0.0, 0.23, t) * (1.0 - smoothstep(0.73, 1.0, t))
	if _animator.prologue_actions:
		_animator.sample_action(SIT, 0.23 * reach)
	else:
		_animator.sample_action("get_up", 1.0 - 0.32 * reach)
	var outside := chair.global_basis.x * flank
	var toward_chair := _visual.get_parent_node_3d().global_basis.inverse() * -outside
	_visual.position = Vector3.UP * (_standing - 0.24 * reach) + toward_chair * (0.08 * reach)
	chair.sample_slide(smoothstep(0.23, 0.73, t))
	for side: String in [".L", ".R"]:
		var leg: Limb = _joints.get("foot" + side)
		if leg != null:
			var stance := (leg.skeleton.global_basis * leg.rest_end.origin).slide(Vector3.UP)
			leg.plant_flat(feet + stance, -chair.global_basis.z, reach)
	# Both actors face -Z. Reach with the arm and rim on the flank being used;
	# the sit/rise brace still uses the same corner of the seat for each actor.
	var hand: Limb = _joints.get("hand.R" if flank > 0.0 else "hand.L")
	if hand != null:
		hand.hold_at(chair.backrest_grip_point(flank), outside + 0.45 * chair.global_basis.z, reach)


func sample_sit(t: float) -> void:
	if _animator.prologue_actions:
		_animator.sample_action(SIT, t)
	else:
		# Q's rig already has the shared get-up. Reuse its rotations in reverse,
		# with the same chair, pelvis and IK timeline rather than moving his root.
		_animator.sample_action("get_up", 1.0 - t)
	# A shallow brace leaves clearance while the chair travels in. Only once the
	# front edge is underneath the thighs does the body settle its last centimetres.
	var down := 0.78 * smoothstep(0.08, 0.38, t) + 0.22 * smoothstep(0.59, 0.93, t)
	_visual.position = Vector3(0, lerpf(_standing, _seated, down), 0.04 * sin(PI * t))
	_visual.rotation.x = 0.0
	if _slide:
		chair.sample_slide(1.0 - smoothstep(0.38, 0.68, t))
		_hold_chair(smoothstep(0.20, 0.38, t) * (1.0 - smoothstep(0.68, 0.93, t)))
	_plant(smoothstep(0.01, 0.23, t), smoothstep(0.11, 0.31, t), smoothstep(0.0, 0.09, t))


func _plant(near_blend: float, far_blend: float, weight: float = 1.0, minimum: float = 0.0) -> void:
	var forward := -chair.global_basis.z
	var right := chair.global_basis.x
	for side: String in [".L", ".R"]:
		var leg: Limb = _joints.get("foot" + side)
		if leg == null:
			continue
		var near := side == ".L"
		var stride := near_blend if near else far_blend
		var side_sign := 1.0 if near else -1.0
		var foot := _floor + right * (0.087 + 0.020 * stride) * side_sign
		foot += forward * lerpf(minimum, 0.33 if near else 0.29, stride)
		foot.y += sin(stride * PI) * 0.029
		leg.plant_flat(foot, forward + right * (0.18 * side_sign), weight)


func _hold_chair(weight: float) -> void:
	var hand: Limb = _joints.get("hand.L")
	if hand != null:
		hand.hold_at(chair.grip_point(), chair.global_basis.x - Vector3.UP * 0.2, weight)
