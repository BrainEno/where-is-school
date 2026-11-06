extends TestCaseHelper
## Navigation checks that do not need input: the player is spawned on solid
## floor, the exit route is walkable, and the camera stays inside the room.
##
## These are geometric assertions rather than a playthrough. A real playthrough
## is listed in the manual checklist in the PR; this test catches the specific
## regressions that kept happening while building the slice — a spawn point
## inside a chair, a doorway with invisible collision, a camera below floor level.

const CLASSROOM_SCENE := preload("res://scenes/locations/classroom/classroom.tscn")

var _room: ClassroomLocation
var _player: PlayerController


func _run() -> void:
	_room = CLASSROOM_SCENE.instantiate() as ClassroomLocation
	if _room == null:
		check(false, "classroom instantiates")
		return
	make_tree().root.add_child(_room)
	var player_scene := preload("res://scenes/actors/player/player.tscn")
	_player = player_scene.instantiate() as PlayerController
	make_tree().root.add_child(_player)
	await flush_frames(2)

	_player.teleport_to(_room.spawn_transform(&"standing"))
	await flush_frames(2)

	_test_spawn_is_clear()
	_test_spawn_is_on_floor()
	_test_camera_is_inside_the_room()
	_test_route_to_door()
	_test_route_to_yard_gate_exists()
	await _cleanup()


func _test_spawn_is_clear() -> void:
	var space := _room.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	query.shape = shape
	# Lift the capsule clear of the floor plane: this checks for furniture, and the
	# floor is proved separately by _test_spawn_is_on_floor().
	query.transform = Transform3D(Basis.IDENTITY, _room.spawn_transform(&"standing").origin + Vector3(0, 1.15, 0))
	query.collision_mask = 1
	var blockers: Array = []
	for hit in space.intersect_shape(query, 8):
		var body := hit["collider"] as Node
		# The room shell (floor/walls) and the deliberately invisible camera guards
		# are structure, not furniture.
		if body == null or String(body.name) == "ShellCollision" or String(body.name).begins_with("CameraGuard"):
			continue
		blockers.append(String(body.name))
	check(blockers.is_empty(), "the standing spawn is not inside furniture", str(blockers))


## A spawn that floats or clips is worse than an awkward one: prove there is floor
## under it by casting down.
func _test_spawn_is_on_floor() -> void:
	var space := _room.get_world_3d().direct_space_state
	var origin: Vector3 = _room.spawn_transform(&"standing").origin
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3(0, 1.0, 0), origin + Vector3(0, -1.0, 0)
	)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	check_false(hit.is_empty(), "there is solid floor under the standing spawn")
	if not hit.is_empty():
		check(float(hit["position"].y) > -0.2, "the floor under the spawn is at ground level")


func _test_camera_is_inside_the_room() -> void:
	var position := _player.camera.global_position
	check(position.y > 1.0, "the camera is above the desks")
	check(position.y < 12.0, "the camera is not so high the room reads as a plan view")
	var flat := Vector2(position.x, position.z)
	check(flat.length() > 2.0, "the camera keeps a 2.5D three-quarter offset from the player")


## Walk a straight line from the spawn to the doorway and confirm nothing static
## blocks it. Step size is small enough not to tunnel.
func _test_route_to_door() -> void:
	var start := _room.spawn_transform(&"standing").origin
	var door := Vector3(3.6, 0.1, 4.9)
	# Walk the aisle between desk columns rather than straight through a chair.
	var aisle := Vector3(2.48, 0, 1.7)
	var blocked_at := _first_block(start + Vector3(0, 0.9, 0), aisle + Vector3(0, 0.9, 0), 0.3)
	if blocked_at == Vector3.INF:
		blocked_at = _first_block(aisle + Vector3(0, 0.9, 0), door + Vector3(0, 0.9, 0), 0.3)
	check_eq(blocked_at, Vector3.INF, "there is a clear walking route from the seat to the door")


func _test_route_to_yard_gate_exists() -> void:
	# The corridor and yard are separate scenes; this asserts the classroom exit
	# marker is reachable and points toward them rather than into a wall.
	var exit_point := _room.exit_point.global_position
	check(exit_point.z > 4.0, "the exit marker is at the back of the room, past the desks")
	var aisle := Vector3(2.48, 0.9, 1.7)
	var blocked := _first_block(
		_room.spawn_transform(&"standing").origin + Vector3(0, 0.9, 0),
		aisle,
		0.3
	)
	if blocked == Vector3.INF:
		blocked = _first_block(aisle, exit_point + Vector3(0, 0.9, 0), 0.3)
	check_eq(blocked, Vector3.INF, "the classroom exit marker is reachable")


func _first_block(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var space := _room.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	query.shape = shape
	query.collision_mask = 1
	var distance := from.distance_to(to)
	var steps := int(ceil(distance / 0.2))
	for index in steps + 1:
		var t := float(index) / float(max(steps, 1))
		var point := from.lerp(to, t)
		query.transform = Transform3D(Basis.IDENTITY, point)
		if not space.intersect_shape(query, 1).is_empty():
			return point
	return Vector3.INF


func _cleanup() -> void:
	if _player != null:
		_player.queue_free()
		_player = null
	if _room != null:
		_room.queue_free()
		_room = null
	await flush_frames(2)
