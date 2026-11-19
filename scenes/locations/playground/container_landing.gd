extends RefCounted
## Roof impact, bound into LocationFlow's arrival hook. The opening scene may already
## be freed. Show shoe/roof contact before handing off to the landing dialogue.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const METAL_IMPACT := preload("res://assets/audio/wake_thud.wav")


static func present(player: PlayerController, fade: Object, hurt: bool) -> void:
	var roof := player.global_position
	var physics := player.is_physics_processing()
	player.set_physics_process(false)
	player.face_toward(Vector3(0.55, 0.0, 1.0))
	var rig := player.camera_rig
	if rig != null:
		rig.frame_point(roof + Vector3(0.7, 0.24, 0.4), 0.0)
	var clip := "roof_impact" if hurt else "roof_brace"
	var duration := 1.55 if hurt else 0.84
	var touch := (0.22 if hurt else 0.16) / duration
	var sound_played := [false]
	# A short visible continuation from the cut, already over the roof. Gravity ramps
	# the last part of the drop; the contact itself is a joint bend, not body sinking.
	player.global_position = roof + Vector3.UP * 0.82
	fade.fade_from_black(0.14)
	await Motion.act(player, clip, duration, func(t: float) -> void:
		var entry := clampf(t / touch, 0.0, 1.0)
		player.global_position = roof + Vector3.UP * (0.82 * (1.0 - entry * entry))
		if t < touch:
			return
		if not sound_played[0]:
			sound_played[0] = true
			_impact_sound(player, hurt)
		var hit := clampf((t - touch) / (0.14 if hurt else 0.18), 0.0, 1.0)
		var rise := clampf((t - touch - (0.24 if hurt else 0.18)) / (0.62 if hurt else 0.36), 0.0, 1.0)
		var weight := smoothstep(0.0, 1.0, hit) * (1.0 - smoothstep(0.0, 1.0, rise))
		if player.visual != null:
			player.visual.position = Vector3(0.06 if hurt else 0.0, -0.33 if hurt else -0.12, 0.10) \
				* weight + Vector3.UP * PlayerController.STANDING_HIP_HEIGHT
	)
	Motion.reset_pose(player)
	player.set_physics_process(physics)
	if rig != null:
		rig.release_frame(0.4)


static func _impact_sound(player: PlayerController, hurt: bool) -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = METAL_IMPACT
	audio.volume_db = -2.0 if hurt else -10.0
	audio.pitch_scale = 0.88 if hurt else 1.22
	audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	player.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
