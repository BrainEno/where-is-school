extends RefCounted
## Small helpers for a locked beat moving the real player. The caller owns the beat and
## the safe start/end positions; this does not add a locomotion state or drive input.

const Limb = preload("res://scripts/actors/character_limb_contact.gd")


static func walk_to(player: PlayerController, target: Vector3, speed: float = 1.45) -> bool:
	var start := player.global_position
	var travel := target - start
	travel.y = 0.0
	if travel.length() < 0.015:
		return true
	# Test the actual capsule, just off the floor. Never pull the player through a desk
	# because a cinematic mark happened to be just beyond it.
	if player.test_move(player.global_transform.translated(Vector3.UP * 0.035), travel):
		return false
	var animator := player.get_character_animator()
	var direction := travel.normalized()
	await turn_to(player, direction)
	if animator != null:
		animator.report_velocity(direction * speed)
	var tween := player.create_tween()
	tween.tween_property(player, "global_position", start + travel, travel.length() / speed)
	await tween.finished
	if animator != null:
		animator.clear_reported_velocity()
	return true


static func turn_to(player: PlayerController, direction: Vector3) -> void:
	var facing := player.get_facing_direction()
	var start := atan2(facing.x, facing.z)
	var finish := atan2(direction.x, direction.z)
	if absf(angle_difference(start, finish)) < 0.05:
		return
	var tween := player.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t: float) -> void:
		var yaw := lerp_angle(start, finish, t)
		player.face_toward(Vector3(sin(yaw), 0, cos(yaw)))
	, 0.0, 1.0, 0.24)
	await tween.finished


static func act(
	player: PlayerController, clip: String, seconds: float, travel: Callable
) -> void:
	var tween := player.create_tween()
	var animator := player.get_character_animator()
	var sample := func(t: float) -> void:
		if animator != null:
			animator.sample_action(clip, t)
		if travel.is_valid():
			travel.call(t)
	sample.call(0.0)
	tween.tween_method(sample, 0.0, 1.0, seconds)
	await tween.finished


static func reset_pose(player: PlayerController) -> void:
	var animator := player.get_character_animator()
	if animator != null:
		animator.release_sampled_action()
		animator.clear_reported_velocity()
	player.set_wake_pose(0.0)
	if player.visual != null:
		player.visual.position = Vector3.UP * PlayerController.STANDING_HIP_HEIGHT
	player.set_camera_roll(0.0)


## Resolve once per beat, using the same semantic bone names as the existing clips.
static func contacts(actor: PlayerController) -> Dictionary:
	return Limb.bind(actor.get_character_animator())
