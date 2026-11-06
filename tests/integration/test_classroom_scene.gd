extends TestCaseHelper
## Scene-level checks for the classroom: collision, spawns, camera framing, and
## the inspectable contract. These are the acceptance criteria that cannot be
## proven by a logic test.

const CLASSROOM_SCENE := preload("res://scenes/locations/classroom/classroom.tscn")

var _room: ClassroomLocation


func _run() -> void:
	_room = CLASSROOM_SCENE.instantiate() as ClassroomLocation
	check_not_null(_room, "classroom scene instantiates as a ClassroomLocation")
	if _room == null:
		return
	make_tree().root.add_child(_room)
	await flush_frames(2)

	_test_markers()
	_test_interactables()
	_test_collision()
	_test_camera_targets()
	await _cleanup()


func _test_markers() -> void:
	check_not_null(_room.seated_spawn, "seated spawn exists")
	check_not_null(_room.standing_spawn, "standing spawn exists")
	check_not_null(_room.exit_point, "exit point exists")
	check_not_null(_room.front_focus, "front-of-room camera focus exists")
	check_not_null(_room.npc_anchor_q, "Q has an anchor")
	var seated := _room.spawn_transform(&"seated")
	var standing := _room.spawn_transform(&"standing")
	check_ne(seated.origin, standing.origin, "seated and standing spawns are distinct")


func _test_interactables() -> void:
	var ids: Dictionary = {}
	for node in make_tree().get_nodes_in_group(&"interactable"):
		var interactable := node as Interactable3D
		if interactable == null:
			continue
		check(not String(interactable.interact_id).is_empty(), "every interactable declares an id")
		check_false(ids.has(interactable.interact_id), "interactable ids are unique (%s)" % String(interactable.interact_id))
		ids[interactable.interact_id] = true
		check(not interactable.get_prompt_text().is_empty(), "interactable '%s' has a prompt" % String(interactable.interact_id))

	for required in [&"schoolbag", &"own_desk", &"set_square", &"teacher_desk", &"chalkboard", &"timetable", &"window", &"door"]:
		check_true(ids.has(required), "classroom contains a '%s' interactable" % String(required))
	check(ids.size() >= 8, "classroom has a useful number of inspectables", str(ids.size()))


## Collision must exist where the player cannot walk, and *not* exist in the
## doorway: a camera-facing parapet with an invisible wall behind it while the
## door is a visual-only prop is exactly the trap this project cannot ship.
func _test_collision() -> void:
	var bodies: Array[Node] = []
	for child in _room.get_children():
		if child is StaticBody3D:
			bodies.append(child)
	check(bodies.size() >= 3, "the room has static collision bodies", str(bodies.size()))

	var door_point := Vector3(3.6, 1.0, 4.6)
	var not_door_point := Vector3(-1.3, 1.0, 4.3)
	var door_hit := _point_hit(door_point)
	var wall_hit := _point_hit(not_door_point)
	check_false(door_hit, "the doorway is a real gap in collision, not an invisible wall")
	check_true(wall_hit, "the rest of the back wall still contains the player")


func _point_hit(point: Vector3) -> bool:
	var space := _room.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_areas = false
	var hits := space.intersect_point(query, 4)
	return not hits.is_empty()


func _test_camera_targets() -> void:
	# The controlled camera sits above and behind the player; the front focus must
	# be far enough from the seated spawn that the emphasis is perceptible.
	var seated := _room.spawn_transform(&"seated")
	var front := _room.front_focus.global_position
	check(seated.origin.distance_to(front) > 3.0, "front focus is clearly ahead of the player's seat")


func _cleanup() -> void:
	if _room != null:
		_room.queue_free()
		_room = null
	await flush_frames(2)
