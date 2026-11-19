extends StaticBody3D
## The roof ladder is a staged route, not a slope in the navigation mesh. The player
## turns to the steel, backs onto the top rung, places alternate feet, then steps down.
## All marks are local to the prop, so moving the whole container keeps the route intact.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")

@onready var _use: StagedInteractable = $LadderUse
@onready var _roof: Marker3D = $Ladder/RoofMark
@onready var _rungs: Node3D = $Ladder/Steps
@onready var _ground: Marker3D = $Ladder/GroundMark


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
	var top := (steps[0] as Marker3D).global_position
	await Motion.act(player, "ladder_mount", duration_scale, func(t: float) -> void:
		var gap := smoothstep(0.24, 0.91, t)
		player.global_position = roof.lerp(top, gap)
		var crouch := sin(smoothstep(0.0, 1.0, t) * PI)
		_hips(player, -0.15 * crouch, 0.08 * gap, 0.0)
	)
	for step in range(1, steps.size()):
		var high := (steps[step - 1] as Marker3D).global_position
		var low := (steps[step] as Marker3D).global_position
		var lead := 1.0 if step % 2 == 1 else -1.0
		var clip := "ladder_right" if lead > 0 else "ladder_left"
		await Motion.act(player, clip, 0.58 * duration_scale, func(t: float) -> void:
			# A support then a weight transfer on each rung. This is intentionally not
			# one linear slide: hands and feet trade support as the body lowers.
			player.global_position = high.lerp(low, smoothstep(0.12, 0.88, t))
			_hips(player, 0.017 * sin(PI * t), 0.08 - 0.024 * sin(PI * t), lead * 0.042 * sin(PI * t))
		)
	var last := (steps.back() as Marker3D).global_position
	await Motion.act(player, "ladder_dismount", 0.64 * duration_scale, func(t: float) -> void:
		player.global_position = last.lerp(_ground.global_position, smoothstep(0.12, 0.91, t))
		_hips(player, -0.048 * sin(PI * t), 0.08 * (1.0 - t), 0.0)
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
