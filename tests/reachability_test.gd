extends SceneTree
## Proves every required interactable can actually be walked up to and targeted.
##
## Acceptance criterion 4 ("every required interactable can be reached, targeted,
## and inspected") is not something a pure data check can answer: a prop can exist
## in the scene and still be buried inside a desk, or sit behind a wall the camera
## and the player can never get to. This test uses the physics server to search for
## a standing position near each interactable and then checks that the real
## InteractionSensor picks it as the focused target from there.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node
var _director: PrologueDirector
var _player: PlayerController
var _sensor: InteractionSensor


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _load_classroom()
	await _check_required_interactables()
	await _check_door_after_release()
	await _check_other_locations()

	if _failures.is_empty():
		print("reachability_test passed (%d checks): every required interactable has a standing spot within reach." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("reachability_test failed with %d problem(s)." % _failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _load_classroom() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_director = _main.get_node("Director") as PrologueDirector
	_player = _main.get_node("Player") as PlayerController
	_sensor = _player.get_node("InteractionSensor") as InteractionSensor
	# Freeze context: the wake/Q beats must not interfere with geometry probing.
	_player.set_input_enabled(false)


func _find_interactable(interact_id: StringName) -> Interactable3D:
	var stack: Array[Node] = [_director.current_location]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var interactable := node as Interactable3D
		if interactable != null and interactable.interact_id == interact_id:
			return interactable
		for child: Node in node.get_children():
			stack.append(child)
	return null


## Returns every free floor position from which the player could plausibly stand
## and reach the target, nearest first. The caller then asks the real sensor which
## of them actually focuses the target: "there exists a reachable spot" is the
## question worth answering, not "the first spot I tried happens to work".
func _candidate_spots(target: Interactable3D) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var origin: Vector3 = target.global_position
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var radii: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2]
	for radius: float in radii:
		for step: int in 24:
			var angle: float = TAU * float(step) / 24.0
			var candidate := Vector3(
				origin.x + cos(angle) * radius,
				origin.y,
				origin.z + sin(angle) * radius
			)
			# Cast down onto the floor so we test a standing position, not mid-air.
			var query := PhysicsRayQueryParameters3D.create(
				candidate + Vector3(0, 2.0, 0), candidate + Vector3(0, -3.0, 0)
			)
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				continue
			var floor_point: Vector3 = hit["position"]
			var body_position: Vector3 = floor_point + Vector3(0.0, 0.1, 0.0)
			if body_position.distance_to(target.global_position) > _sensor.reach:
				continue
			# Is the capsule free at that spot?
			var shape := CapsuleShape3D.new()
			shape.radius = 0.32
			shape.height = 1.75
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(Basis(), body_position + Vector3(0, 0.95, 0))
			params.collision_mask = 1
			params.exclude = [_player.get_rid()]
			if space.intersect_shape(params, 1).is_empty():
				spots.append(body_position)
	return spots


func _probe(interact_id: StringName) -> void:
	var target: Interactable3D = _find_interactable(interact_id)
	_check(target != null, "interactable '%s' is missing from the classroom" % interact_id)
	if target == null:
		return
	var spots: Array[Vector3] = _candidate_spots(target)
	_check(not spots.is_empty(),
		"interactable '%s' has no free standing spot within %.1fm" % [interact_id, _sensor.reach])
	if spots.is_empty():
		return
	# Ask the real sensor. A prop that is inside a desk, or that can never outrank
	# the furniture in front of it, will fail every candidate and fail the test.
	var focused_from: Vector3 = Vector3.INF
	for spot: Vector3 in spots:
		_player.teleport_to(Transform3D(Basis(), spot))
		await physics_frame
		await physics_frame
		if _sensor.current == target:
			focused_from = spot
			break
	_check(focused_from != Vector3.INF,
		"no reachable position lets the player target '%s' (last focus: %s)" % [
			interact_id,
			_sensor.current.interact_id if _sensor.current != null else "nothing"
		])


func _check_required_interactables() -> void:
	for interact_id: StringName in [&"bag", &"set_square", &"teacher_desk", &"timetable", &"chair", &"window", &"q"]:
		await _probe(interact_id)


func _check_door_after_release() -> void:
	# The door is disabled until the release, but it must still be physically
	# reachable: a player who cannot stand next to it can never leave.
	var door: Interactable3D = _find_interactable(&"classroom_door")
	_check(door != null, "classroom door is missing")
	if door == null:
		return
	_check(not _candidate_spots(door).is_empty(),
		"the classroom door has no free standing spot in front of it")


## The corridor and the street must also let the player stand next to their
## thresholds, or the route out of the school is a dead end.
func _check_other_locations() -> void:
	for entry: Array in [
		[&"corridor", [&"corridor_exit", &"corridor_classroom"]],
		[&"street", [&"street_gate", &"street_corridor"]],
	]:
		_director.load_location(entry[0])
		await process_frame
		await process_frame
		_check(_director.current_location_id == entry[0], "failed to load location '%s'" % entry[0])
		for interact_id: StringName in entry[1]:
			var target: Interactable3D = _find_interactable(interact_id)
			_check(target != null, "interactable '%s' is missing from '%s'" % [interact_id, entry[0]])
			if target == null:
				continue
			_check(not _candidate_spots(target).is_empty(),
				"'%s' in '%s' has no free standing spot within reach" % [interact_id, entry[0]])
