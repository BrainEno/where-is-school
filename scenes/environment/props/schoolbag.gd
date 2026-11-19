extends Node3D
## Props at the desk are presentation only. The room hands the existing inspection
## to OpeningSequence after this choreography, not from inside the prop.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const SEARCH_CLIP := "schoolbag_search"
const SEARCH_SECONDS := 1.72

@onready var _lid: Node3D = $Lid
@onready var _lid_grip: Marker3D = $Lid/LidGrip
@onready var _brace: Marker3D = $MouthBrace
@onready var _pocket: Marker3D = $PocketGrip
@onready var _position: Marker3D = $SearchPosition


func search_position() -> Vector3:
	return _position.global_position


func rummage(player: PlayerController) -> void:
	var contacts := Motion.contacts(player)
	await Motion.act(player, SEARCH_CLIP, SEARCH_SECONDS, _sample.bind(player, contacts))
	var animator := player.get_character_animator()
	if animator != null:
		animator.release_sampled_action()


func _sample(t: float, player: PlayerController, joints: Dictionary) -> void:
	var bend := smoothstep(0.04, 0.36, t) * (1.0 - smoothstep(0.73, 1.0, t))
	var opened := smoothstep(0.19, 0.40, t) * (1.0 - smoothstep(0.75, 0.92, t))
	_lid.rotation_degrees.x = -105.0 * opened
	player.visual.position = Vector3(0, PlayerController.STANDING_HIP_HEIGHT - 0.185 * bend, 0.065 * bend)
	var face := -global_basis.z
	var side := global_basis.x
	for suffix: String in [".L", ".R"]:
		var boot: Motion.Limb = joints.get("foot" + suffix)
		if boot != null:
			var side_sign := 1.0 if suffix == ".L" else -1.0
			var foot := _position.global_position + side * (0.105 * side_sign) + face * 0.03 * side_sign
			boot.plant_flat(foot, face + side * (side_sign * 0.15), bend)

	var left: Motion.Limb = joints.get("hand.L")
	var right: Motion.Limb = joints.get("hand.R")
	# One hand steadies the bag while the other lifts the flap, sweeps the mouth
	# and checks the side pouch. The hand returns to the flap before closing it.
	if right != null:
		right.hold_at(_brace.global_position, -side, smoothstep(0.07, 0.25, t) * (1.0 - smoothstep(0.84, 0.98, t)))
	if left != null:
		var inside := to_global(Vector3(lerpf(-0.048, 0.092, smoothstep(0.43, 0.56, t)), 0.322, 0.038))
		inside = inside.lerp(_pocket.global_position, smoothstep(0.57, 0.66, t))
		var reach_in := smoothstep(0.37, 0.46, t) * (1.0 - smoothstep(0.67, 0.75, t))
		var hand := _lid_grip.global_position.lerp(inside, reach_in)
		left.hold_at(hand, side - Vector3.UP * 0.2, smoothstep(0.06, 0.19, t) * (1.0 - smoothstep(0.90, 1.0, t)))
