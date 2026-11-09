class_name LocationRoot
extends Node3D
## Script on every authored location scene.
##
## Gives the sequence director a small, explicit contract for talking to a
## location instead of hard-coding node paths from outside: spawn points,
## waypoint paths, actors, and interactables are looked up here.

## Stable identifier matching the key used by narrative flags and inspection
## data ("classroom", "corridor"). Set by each location scene.
@export var location_id: StringName = &""

## Returns the marker the player should be placed on.
##
## The two cases are deliberately different, and mixing them up sends the player into
## the wrong room while the story flag still names the right one:
##
## - an **empty** id means "this location's default": the first `spawn_point` marker in
##   tree order, which is how the game has always opened the classroom;
## - a **named** id must match a marker exactly. There is no fallback: a name nobody
##   authored is a content error, and it is reported as one.
func get_spawn(spawn_id: StringName) -> Node3D:
	if String(spawn_id).is_empty():
		var default_spawn := get_default_spawn()
		if default_spawn == null:
			push_error(
				"%s: no spawn point is marked 'spawn_point', so there is no default "
				% _spawn_context()
			)
		return default_spawn
	for marker: Node3D in _spawn_markers():
		if String(marker.name) == String(spawn_id):
			return marker
	push_error(
		"%s: spawn point '%s' does not exist. Available: %s."
		% [_spawn_context(), spawn_id, _spawn_id_list()]
	)
	return null


## The default spawn: the first `spawn_point` marker in tree order.
func get_default_spawn() -> Node3D:
	var markers := _spawn_markers()
	return markers[0] if not markers.is_empty() else null


## Every spawn id this location declares, in tree order. Used for diagnostics and by
## the transition test, which cross-references exits against real markers.
func get_spawn_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for marker: Node3D in _spawn_markers():
		ids.append(StringName(marker.name))
	return ids


## `spawn_point` markers in tree order. Markers that are not in the group are props, not
## places to stand, so they are ignored.
func _spawn_markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	for node in find_children("*", "Marker3D", true, false):
		var marker := node as Node3D
		if marker != null and marker.is_in_group("spawn_point"):
			markers.append(marker)
	return markers


## Identifies the location in an error message well enough to fix it without a search:
## its id, its node name and the scene file it came from (when it has one).
func _spawn_context() -> String:
	var scene_path := scene_file_path
	if scene_path.is_empty():
		scene_path = "<packed at run time>"
	var location := String(location_id)
	if location.is_empty():
		location = "<no location_id>"
	return "LocationRoot '%s' (location_id '%s', scene %s)" % [
		name, location, scene_path
	]


func _spawn_id_list() -> String:
	var ids := get_spawn_ids()
	if ids.is_empty():
		return "none"
	var names: Array[String] = []
	for spawn_id: StringName in ids:
		names.append(String(spawn_id))
	return ", ".join(names)


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
