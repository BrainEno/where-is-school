extends RefCounted
## Small helpers for a locked beat moving the real player. The caller owns the beat and
## the safe start/end positions; this does not add a locomotion state or drive input.

const Limb = preload("res://scripts/actors/character_limb_contact.gd")
## How far off the navigation mesh a staged mark may sit and still be walked onto.
const ROUTE_OFF_MESH := 0.75


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
	await _walk_leg(player, start + travel, speed)
	_stop_walking(player)
	return true


## Like `walk_to`, for a walk that may go down a flight of steps (an arrival that starts
## on a landing, `LocationHost.ENTRY_WALK_META`). The tween moves the body only across the
## floor and leaves its height to the controller's own gravity and floor snap, so the feet
## come down each tread instead of gliding out at the landing's height. Down or level
## only: on a rise the capsule would be pushed into the next riser.
static func walk_down_to(player: PlayerController, target: Vector3, speed: float = 1.45) -> bool:
	var start := player.global_position
	var travel := target - start
	travel.y = 0.0
	if travel.length() < 0.015:
		return true
	if player.test_move(player.global_transform.translated(Vector3.UP * 0.035), travel):
		return false
	var direction := travel.normalized()
	await turn_to(player, direction)
	var animator := player.get_character_animator()
	if animator != null:
		animator.report_velocity(direction * speed)
	var across := func(t: float) -> void:
		var point := start + travel * t
		player.global_position = Vector3(point.x, player.global_position.y, point.z)
	var tween := player.create_tween()
	tween.tween_method(across, 0.0, 1.0, travel.length() / speed)
	await tween.finished
	_stop_walking(player)
	return true


## Like `walk_to`, but when something stands on the straight line (a chair, the end of a
## desk row) it goes round it the way a click would: along the navigation map, which is
## baked with the body's own radius, then the last short step from the mesh onto the mark.
## False only when the map has no route there either.
static func walk_route_to(player: PlayerController, target: Vector3, speed: float = 1.45) -> bool:
	if await walk_to(player, target, speed):
		return true
	var legs := route_to(player, target)
	if legs.is_empty():
		return false
	for point: Vector3 in legs:
		await _walk_leg(player, point, speed)
	_stop_walking(player)
	return true


## The points a staged walk from where the player stands to `target` passes through,
## ending on `target`, or an empty array when the map has no such route. A mark a little
## off the mesh (the lip of the cut, a step) is reached from the mesh's closest point.
static func route_to(player: PlayerController, target: Vector3) -> PackedVector3Array:
	var legs := PackedVector3Array()
	var agent := player.navigation_agent
	if agent == null:
		return legs
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty():
		return legs
	var goal := NavigationServer3D.map_get_closest_point(map, target)
	if Vector2(goal.x - target.x, goal.z - target.z).length() > ROUTE_OFF_MESH:
		return legs
	var path := NavigationServer3D.map_get_path(map, player.global_position, goal, true)
	if path.size() < 2:
		return legs
	var floor_y := player.global_position.y
	for index in range(1, path.size()):
		var point := path[index]
		if Vector2(point.x - target.x, point.z - target.z).length() < 0.015:
			continue
		legs.append(Vector3(point.x, floor_y, point.z))
	legs.append(Vector3(target.x, floor_y, target.z))
	return legs


static func _walk_leg(player: PlayerController, point: Vector3, speed: float) -> void:
	var travel := point - player.global_position
	travel.y = 0.0
	if travel.length() < 0.015:
		return
	var direction := travel.normalized()
	await turn_to(player, direction)
	var animator := player.get_character_animator()
	if animator != null:
		animator.report_velocity(direction * speed)
	var tween := player.create_tween()
	var finish := player.global_position + travel
	tween.tween_property(player, "global_position", finish, travel.length() / speed)
	await tween.finished


static func _stop_walking(player: PlayerController) -> void:
	var animator := player.get_character_animator()
	if animator != null:
		animator.clear_reported_velocity()


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
