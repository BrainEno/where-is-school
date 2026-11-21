extends Node3D
## Joint poses for this rigid, painted figure. The encounter moves the NpcActor;
## the mesh follows its measured travel, never driving navigation or collision.

const HIP_HEIGHT := 0.872
const UPPER := 0.445
const LOWER := 0.345
const SOLE := 0.082
const SEATED_THIGH := 88.0
const STRIDE := 0.90

@onready var _hip: Node3D = $Hip
@onready var _trunk: Node3D = $Hip/Trunk
@onready var _head: Node3D = $Hip/Trunk/Head
@onready var _arms: Array[Node3D] = [$Hip/Trunk/ArmL, $Hip/Trunk/ArmR]
@onready var _elbows: Array[Node3D] = [$Hip/Trunk/ArmL/Elbow, $Hip/Trunk/ArmR/Elbow]
@onready var _thighs: Array[Node3D] = [$Hip/ThighL, $Hip/ThighR]
@onready var _shins: Array[Node3D] = [$Hip/ThighL/Shin, $Hip/ThighR/Shin]
@onready var _boots: Array[Node3D] = [$Hip/ThighL/Shin/Boot, $Hip/ThighR/Shin/Boot]

var _pulse: Tween
var _last_position := Vector3.ZERO
var _phase := 0.0


func _ready() -> void:
	stand()


func sleep_on_bedding() -> void:
	set_process(false)
	if _pulse != null and _pulse.is_running():
		_pulse.kill()
	_react(0.0)


func stir() -> void:
	_pulse = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pulse.tween_method(_react, 0.0, 1.0, 0.24)


func _react(t: float) -> void:
	_hip.position = Vector3(0.0, lerpf(0.181, 0.194, t), 0.0)
	_trunk.rotation_degrees = Vector3(88.0 - 12.0 * t, 0.0, -3.0)
	_head.rotation_degrees = Vector3(-9.0 - 19.0 * t, -7.0, 2.0)
	_arm(0, 24.0 + 17.0 * t, -15.0, 42.0)
	_arm(1, 6.0 + 8.0 * t, 12.0, 24.0)
	_leg(0, 83.0, 10.0, 62.0)
	_leg(1, 90.0, -7.0, 55.0)


## Lift from the sheet, gather the boots, then bring the pelvis over the soles.
## Returns the little forward displacement to transfer to the actor before walking.
func rise() -> Vector3:
	if _pulse != null and _pulse.is_running():
		_pulse.kill()
	var motion := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(_sit, 0.0, 1.0, 0.68)
	motion.tween_method(_push_up, 0.0, 1.0, 0.66)
	await motion.finished
	return Vector3(0.0, 0.0, _hip.position.z)


func _sit(t: float) -> void:
	_hip.position = Vector3(0.0, lerpf(0.194, _seat_height(), t), 0.0)
	_trunk.rotation_degrees = Vector3(lerpf(76.0, -11.0, t), 0.0, -3.0 * (1.0 - t))
	_head.rotation_degrees = Vector3(lerpf(-28.0, 0.0, t), -7.0 * (1.0 - t), 0.0)
	_arm(0, lerpf(41.0, 30.0, t), lerpf(-15.0, -7.0, t), 42.0)
	_arm(1, lerpf(14.0, 24.0, t), lerpf(12.0, 6.0, t), 24.0)
	_leg(0, lerpf(83.0, SEATED_THIGH, t), lerpf(10.0, -SEATED_THIGH, t), 62.0 * (1.0 - t))
	_leg(1, lerpf(90.0, SEATED_THIGH, t), lerpf(-7.0, -SEATED_THIGH, t), 55.0 * (1.0 - t))


func _seat_height() -> float:
	return SOLE + LOWER + UPPER * cos(deg_to_rad(SEATED_THIGH))


func _push_up(t: float) -> void:
	var angle := lerpf(SEATED_THIGH, 0.0, t)
	var knee := deg_to_rad(angle)
	_hip.position = Vector3(0.0, SOLE + LOWER + UPPER * cos(knee),
		-UPPER * (sin(deg_to_rad(SEATED_THIGH)) - sin(knee)))
	_trunk.rotation_degrees.x = lerpf(-11.0, -5.0, t) - sin(PI * t) * 21.0
	for side in 2:
		_leg(side, angle, -angle, 0.0)
		_arm(side, lerpf(30.0 - side * 6.0, 2.0, t), (-1.0 if side == 0 else 1.0) * 7.0,
			lerpf(42.0 - side * 18.0, 13.0, t))


func stand(look_up: bool = false) -> void:
	set_process(false)
	_hip.position = Vector3(0.0, HIP_HEIGHT, 0.0)
	_trunk.rotation_degrees = Vector3(-5.0, 0.0, -1.0)
	_head.rotation_degrees = Vector3(31.0 if look_up else 4.0, -5.0, 1.0)
	for side in 2:
		_arm(side, 2.0, -8.0 if side == 0 else 8.0, 13.0)
		_leg(side, 0.0, 0.0, 0.0)


func start_walking() -> void:
	stand()
	_last_position = global_position
	_phase = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	var travel := global_position - _last_position
	_last_position = global_position
	_phase = fposmod(_phase + Vector2(travel.x, travel.z).length() * TAU / STRIDE, TAU)
	var swing := sin(_phase)
	_hip.position.y = HIP_HEIGHT - (0.5 + 0.5 * cos(2.0 * _phase)) * 0.027
	_trunk.rotation_degrees = Vector3(-7.0, swing * 4.0, swing * 2.0)
	for side in 2:
		var cycle := _phase + PI * side
		var stride := sin(cycle)
		_leg(side, stride * 25.0, -maxf(0.0, cos(cycle)) * 36.0, 5.0 * stride)
		_arm(side, -stride * 17.0, -8.0 if side == 0 else 8.0, 17.0 + 5.0 * stride)


func _arm(side: int, pitch: float, spread: float, bend: float) -> void:
	_arms[side].rotation_degrees = Vector3(pitch, 0.0, spread)
	_elbows[side].rotation_degrees.x = bend


func _leg(side: int, thigh: float, knee: float, sole_pitch: float) -> void:
	_thighs[side].rotation_degrees.x = thigh
	_shins[side].rotation_degrees.x = knee
	_boots[side].rotation_degrees.x = sole_pitch - thigh - knee
