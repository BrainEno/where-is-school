extends RefCounted
## Getting off the container roof while the woken resident stands in his doorway.
##
## The roof ladder (`container_ladder.gd`) asks first (`ask()`): climb down the ladder in
## front of him, creep bent over to the closed rear end (left of the ladder, as the yard
## sees it) and drop off there, or wait. The ladder is slow and seen: at the bottom he tells
## the protagonist to stop (`STOP_CONVERSATION`). The drop is a second fall (`jump()`): the
## protagonist lands hard on the yard behind the container, the dazed look comes back
## heavier (`ConcussionView.begin(…, true)`), and a visible orientation check decides
## whether the landing was heard. Unheard, the resident looks round the container for a
## while (`RoofEncounter.search()`, story time) and the player hides by moving: crouched,
## slow (`PlayerController.set_crouching()`), never frozen. Kept out of his sight, the
## protagonist has the yard once he goes back in; held in it, or heard landing, they are
## stopped as on the ladder. Marks are local to the container, so moving the prop keeps
## the route.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const RoofEncounter = preload("res://scenes/locations/playground/roof_encounter.gd")
const IMPACT := preload("res://assets/audio/wake_thud.wav")

const CHOICE_CONVERSATION := &"pg_roof_way_down"
const STOP_CONVERSATION := &"pg_collector_stop"
const JUMP_CONVERSATION := &"pg_roof_jump"
const JUMP_CHECK := &"prj_check"
const LADDER := &"ladder"
const JUMP := &"jump"
const STAY := &"stay"
const CHECKPOINT := "playground:container_jump"

## Where the protagonist steps off: the closed rear end of the roof, the whole container
## between them and his doorway.
const EDGE := Vector3(-2.55, 2.6, 0.2)
## Where the drop lands: the yard behind that closed end, out of sight of the doorstep and
## of every stop on the search route.
const HIDE := Vector3(-3.6, 0.0, 0.2)
## The bent-over walk along the roof to `EDGE`, m/s.
const ROOF_CREEP_SPEED := 1.1
## The point of the impact clip held while the check is read, and where the rise from it
## hands over to the crouch.
const HOLD := 0.42
const CROUCH_FROM := 0.6
## How far the hips sink at the impact, and in the crouch that follows.
const SINK := 0.48
const CROUCH := 0.38


## Plays the choice and returns `LADDER`, `JUMP` or `STAY` (the `roof_way_down` flag).
static func ask(director: Node, state: Node) -> StringName:
	if state == null:
		return LADDER
	state.set_flag(StoryFlags.ROOF_WAY_DOWN, String(STAY))
	await director.play_conversation(CHOICE_CONVERSATION)
	return StringName(String(state.get_flag(StoryFlags.ROOF_WAY_DOWN, String(STAY))))


## Seen on the ladder or heard landing: he stops the protagonist. The lines are the
## story's to write (`STOP_CONVERSATION`).
static func stopped(director: Node, encounter: RoofEncounter, player: PlayerController) -> void:
	if encounter != null:
		encounter.confront(player)
	await director.play_conversation(STOP_CONVERSATION)


## The drop off the closed rear. Returns the beat's request (see StagedInteractable).
static func jump(container: Node3D, encounter: RoofEncounter, director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	var physics := player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	# Bent over across the roof, below the line of the edge from his doorway.
	player.set_crouching(true)
	if not await Motion.walk_to(player, container.to_global(EDGE), ROOF_CREEP_SPEED):
		player.set_crouching(false, true)
		player.set_physics_process(physics)
		return {}
	var out := -container.global_basis.x
	await Motion.turn_to(player, out)
	# Up off the knees at the edge (eased), then over.
	player.set_crouching(false)
	await player.get_tree().create_timer(PlayerController.CROUCH_BLEND_SECONDS + 0.1, false).timeout
	var ground := _floor_under(container, container.to_global(HIDE))
	var rig := player.camera_rig
	if rig != null:
		rig.frame_point(ground + Vector3.UP * 0.8, 0.25)
	var start := player.global_position
	var height := start.y - ground.y
	# Crouch, push off, and fall the whole height of the container: no ledge to hang from.
	await Motion.act(
		player,
		"void_step",
		0.92,
		func(t: float) -> void:
			var travel := smoothstep(0.10, 0.78, t)
			var drop := clampf((t - 0.30) / 0.70, 0.0, 1.0)
			var hop := 0.10 * sin(clampf(t / 0.36, 0.0, 1.0) * PI)
			var flat := start.lerp(ground, travel)
			player.global_position = Vector3(flat.x, start.y + hop - height * drop * drop, flat.z)
			_hips(player, -0.12 * sin(smoothstep(0.0, 0.5, t) * PI), 0.0)
			player.set_camera_roll(-3.0 * drop)
	)
	player.global_position = ground
	_impact_sound(player)
	ConcussionView.begin(player, true)
	var contacts := Motion.contacts(player)
	var right := Vector3.UP.cross(out)
	var soles: Array[Vector3] = [ground - right * 0.12, ground + right * 0.14 + out * 0.16]
	var palm_at := ground + right * 0.28 + out * 0.30 + Vector3.UP * 0.08
	await _act_range(
		player,
		"roof_impact",
		0.0,
		HOLD,
		0.8,
		func(t: float) -> void:
			var hit := smoothstep(0.0, 0.35, t)
			_hips(player, -lerpf(SINK * hit, CROUCH, smoothstep(0.55, 1.0, t)), 0.04 * hit)
			player.set_camera_roll(-3.0 * (1.0 - t))
			_plant(contacts, soles, palm_at, right, smoothstep(0.0, 0.2, t))
	)
	await director.play_conversation(JUMP_CONVERSATION)
	var hidden := heard_nothing(player) and encounter != null
	if hidden:
		var found: bool = await _hide(
			player, contacts, soles, palm_at, right, encounter, director, physics
		)
		hidden = not found
	else:
		await _act_range(
			player,
			"roof_impact",
			HOLD,
			1.0,
			0.7,
			func(t: float) -> void:
				_hips(player, -CROUCH * (1.0 - smoothstep(0.1, 0.9, t)), 0.0)
				_plant(contacts, soles, palm_at, right, 1.0 - smoothstep(0.6, 1.0, t))
		)
		Motion.reset_pose(player)
		player.set_physics_process(physics)
	if not hidden:
		await stopped(director, encounter, player)
	if rig != null:
		await rig.release_frame(0.42)
	return {"checkpoint": CHECKPOINT}


## Unheard: up from the impact into a crouch, and the player moves the protagonist while
## the resident searches - bent over, at `PlayerController.crouch_speed`, the camera
## following them again. Interaction stays off with the beat. Returns whether he found
## them; either way they stand up when it is over.
static func _hide(
	player: PlayerController,
	contacts: Dictionary,
	soles: Array[Vector3],
	palm_at: Vector3,
	right: Vector3,
	encounter: RoofEncounter,
	director: Node,
	physics: bool
) -> bool:
	await _act_range(
		player,
		"roof_impact",
		HOLD,
		CROUCH_FROM,
		0.5,
		func(t: float) -> void:
			var low := lerpf(CROUCH, PlayerController.CROUCH_HIP_DROP, smoothstep(0.1, 0.9, t))
			_hips(player, -low, 0.0)
			_plant(contacts, soles, palm_at, right, 1.0 - smoothstep(0.4, 1.0, t))
	)
	Motion.reset_pose(player)
	player.set_crouching(true, true)
	player.set_physics_process(physics)
	var rig := player.camera_rig
	if rig != null:
		rig.release_frame(0.6)
	player.set_control_enabled(true)
	var found: bool = await encounter.search(director, player)
	player.set_control_enabled(false)
	player.velocity = Vector3(0.0, player.velocity.y, 0.0)
	player.set_crouching(false)
	return found


## The recorded result of the landing's check: true when the drop went unheard.
static func heard_nothing(from: Node) -> bool:
	var state := from.get_node_or_null(^"/root/GameState")
	if state == null:
		return false
	var record: Variant = state.get_flag(
		StoryFlags.check_record_flag(JUMP_CONVERSATION, JUMP_CHECK), null
	)
	return record is Dictionary and bool((record as Dictionary).get("success", false))


static func _floor_under(from: Node3D, point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 1.2, point + Vector3.DOWN * 1.0
	)
	var hit := from.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("position"):
		return hit["position"] as Vector3
	return point


## Like `Motion.act`, over the part `from`..`to` of the clip.
static func _act_range(
	player: PlayerController, clip: String, from: float, to: float, seconds: float, travel: Callable
) -> void:
	var animator := player.get_character_animator()
	var tween := player.create_tween()
	var sample := func(t: float) -> void:
		if animator != null:
			animator.sample_action(clip, lerpf(from, to, t))
		travel.call(t)
	tween.tween_method(sample, 0.0, 1.0, seconds)
	await tween.finished


static func _hips(player: PlayerController, lift: float, forward: float) -> void:
	if player.visual != null:
		player.visual.position = Vector3(
			-0.07 * absf(lift) / SINK, PlayerController.STANDING_HIP_HEIGHT + lift, forward
		)


static func _plant(
	contacts: Dictionary, soles: Array[Vector3], palm_at: Vector3, right: Vector3, weight: float
) -> void:
	var forward := Vector3.UP.cross(-right)
	for side in 2:
		var boot: Motion.Limb = contacts.get("foot.L" if side == 0 else "foot.R")
		if boot != null:
			boot.plant(soles[side], forward, weight)
	var palm: Motion.Limb = contacts.get("hand.R")
	if palm != null:
		palm.hold_at(palm_at, right + Vector3.BACK * 0.28, weight)


static func _impact_sound(player: PlayerController) -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = IMPACT
	audio.volume_db = -4.0
	audio.pitch_scale = 0.78
	audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
