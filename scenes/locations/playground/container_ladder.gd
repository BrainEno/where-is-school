extends StaticBody3D
## The roof ladder is a staged route, not a slope in the navigation mesh. The player
## turns to the steel, backs onto the top rung, places alternate feet, then steps down.
## All marks are local to the prop, so moving the whole container keeps the route intact.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")

@onready var _use: StagedInteractable = $LadderUse
@onready var _roof: Marker3D = $Ladder/RoofMark
@onready var _rungs: Node3D = $Ladder/Steps
@onready var _ground: Marker3D = $Ladder/GroundMark
@onready var _grabs: Array[Node3D] = [$Ladder/GrabLeft, $Ladder/GrabRight]


func _ready() -> void:
	_use.stage_handler = _descend


func _descend(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if absf(player.global_position.y - _roof.global_position.y) > 0.19:
		return {}
	var style := get_node_or_null(^"/root/GameState")
	var hurt: bool = style != null and style.get_flag(StoryFlags.CURTAIN_LANDING_INJURED, false) == true
	var duration_scale := 1.24 if hurt else 1.0
	var physics := player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	if not await Motion.walk_to(player, _roof.global_position, 1.24):
		player.set_physics_process(physics)
		return {}
	await Motion.turn_to(player, -global_basis.z)
	var rig := player.camera_rig
	if rig != null:
		# Hold a wide enough view to show both the roof departure and the ground below.
		rig.frame_point(to_global(Vector3(1.79, 1.23, 1.04)), 0.5)
	var roof := _roof.global_position
	var steps := _rungs.get_children()
	var contacts := Motion.contacts(player)
	var top := (steps[0] as Marker3D).global_position
	await Motion.act(player, "ladder_mount", duration_scale, func(t: float) -> void:
		var gap := smoothstep(0.24, 0.91, t)
		player.global_position = roof.lerp(top, gap)
		var crouch := sin(smoothstep(0.0, 1.0, t) * PI)
		_hips(player, -0.19 * crouch, 0.0, 0.0)
		for side in 2:
			var travel := smoothstep(0.26 + side * 0.18, 0.78 + side * 0.20, t)
			var tread := roof.lerp(top, travel) + Vector3.UP * 0.055 * sin(travel * PI)
			_boot(contacts, side, tread, smoothstep(0.1, 0.31, t))
			var reach := smoothstep(0.57, 0.99, t)
			_grasp(contacts, side, _grabs[side].global_position.y, reach, smoothstep(0.12, 0.30, t))
	)
	for step in range(1, steps.size()):
		var high := (steps[step - 1] as Marker3D).global_position
		var low := (steps[step] as Marker3D).global_position
		var above := (steps[maxi(0, step - 2)] as Marker3D).global_position
		var lead_side := (step + 1) % 2
		var shift := 0.042 if lead_side == 0 else -0.042
		var clip := "ladder_right" if lead_side == 0 else "ladder_left"
		await Motion.act(player, clip, 0.58 * duration_scale, func(t: float) -> void:
			# A support then a weight transfer on each rung. This is intentionally not
			# one linear slide: hands and feet trade support as the body lowers.
			player.global_position = high.lerp(low, smoothstep(0.12, 0.88, t))
			_hips(player, 0.017 * sin(PI * t), 0.0, shift * sin(PI * t))
			var travel := smoothstep(0.06, 0.65, t)
			var moving := above.lerp(low, travel) + global_basis.z * 0.12 * sin(travel * PI)
			_boot(contacts, lead_side, moving, 1.0)
			_boot(contacts, 1 - lead_side, high, 1.0)
			for side in 2:
				# One palm slides to its next grip while the other still takes weight.
				var palm := smoothstep(0.08, 0.45, t) if side == lead_side else smoothstep(0.55, 0.94, t)
				var grip := minf(_grabs[side].global_position.y, lerpf(high.y, low.y, palm) + 1.28)
				_grasp(contacts, side, grip, 1.0, 1.0)
		)
	var last := (steps.back() as Marker3D).global_position
	await Motion.act(player, "ladder_dismount", 0.64 * duration_scale, func(t: float) -> void:
		player.global_position = last.lerp(_ground.global_position, smoothstep(0.12, 0.91, t))
		_hips(player, -0.048 * sin(PI * t), 0.0, 0.0)
		for side in 2:
			var travel := smoothstep(0.07 + 0.24 * side, 0.64 + 0.24 * side, t)
			var step := last if side == 0 else (steps[steps.size() - 2] as Marker3D).global_position
			var tread := step.lerp(_ground.global_position, travel) + Vector3.UP * 0.055 * sin(travel * PI)
			_boot(contacts, side, tread, 1.0 - smoothstep(0.82, 1.0, t))
			_grasp(contacts, side, last.y + 1.28, 1.0, 1.0 - smoothstep(0.28, 0.69, t))
	)
	Motion.reset_pose(player)
	player.set_physics_process(physics)
	await Motion.turn_to(player, global_basis.x)
	if rig != null:
		await rig.release_frame(0.42)
	return {"checkpoint": "playground:container_ladder"}


func _hips(player: PlayerController, lift: float, reach: float, shift: float) -> void:
	if player.visual != null:
		player.visual.position = Vector3(shift, PlayerController.STANDING_HIP_HEIGHT + lift, reach)


func _boot(contacts: Dictionary, side: int, tread: Vector3, weight: float) -> void:
	# The actor faces -Z at the ladder, so the prop's -X rail is on the actor's +X.
	var limb: Motion.Limb = contacts.get("foot.R" if side == 0 else "foot.L")
	if limb == null:
		return
	# The trace is just behind the ladder. Put the ball of the boot over the rung,
	# with the ankle about 0.18 m behind the trace's front edge.
	var ankle := tread - global_basis.z * 0.18 + global_basis.x * (-0.12 if side == 0 else 0.12)
	limb.plant(ankle, -global_basis.z, weight)


func _grasp(contacts: Dictionary, side: int, y: float, rail: float, weight: float) -> void:
	var limb: Motion.Limb = contacts.get("hand.R" if side == 0 else "hand.L")
	if limb == null:
		return
	var point := _grabs[side].global_position + global_basis.z * lerpf(-0.10, 0.21, rail)
	point.y = y
	var elbow := global_basis.x * (-1.0 if side == 0 else 1.0) + Vector3.DOWN * 0.6
	limb.hold_at(point, elbow, weight)
