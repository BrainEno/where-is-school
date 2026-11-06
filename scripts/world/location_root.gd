class_name LocationRoot
extends Node3D
## Script on every authored location scene.
##
## Gives the sequence director a small, explicit contract for talking to a
## location instead of hard-coding node paths from outside: spawn points,
## waypoint paths, actors, and interactables are looked up here.

func get_spawn(spawn_id: StringName) -> Node3D:
	var spawns := find_children("*", "Marker3D", true, false)
	for node in spawns:
		if not node.is_in_group("spawn_point"):
			continue
		if String(spawn_id).is_empty() or node.name == String(spawn_id):
			return node as Node3D
	var fallback := find_children("*", "Marker3D", true, false)
	for node in fallback:
		if node.is_in_group("spawn_point"):
			return node as Node3D
	return null


## Returns the positions of a location's marker path, in tree order.
func get_waypoint_path(path_node_name: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var path_root := get_node_or_null(NodePath(String(path_node_name)))
	if path_root == null:
		push_error(
			"LocationRoot '%s': waypoint path '%s' does not exist." % [name, path_node_name]
		)
		return points
	for child in path_root.get_children():
		var marker := child as Marker3D
		if marker != null:
			points.append(marker.global_position)
	return points


func find_actor(actor_id: StringName) -> NpcActor:
	for node in _descendants(self):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == actor_id:
			return actor
	return null


func get_interactables() -> Array[Interactable]:
	var result: Array[Interactable] = []
	for node in _descendants(self):
		var interactable := node as Interactable
		if interactable != null:
			result.append(interactable)
	return result


func find_interactable(interact_id: StringName) -> Interactable:
	for interactable in get_interactables():
		if interactable.interact_id == interact_id:
			return interactable
	return null


## Depth-first walk that uses GDScript `is` checks instead of native class names,
## so script classes and their subclasses (e.g. LocationExit) are matched too.
func _descendants(root_node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root_node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
