class_name LocationHost
extends Node3D
## Owns the currently loaded location scene and moves the player to its spawn.
##
## Scene swapping lives here so no prop, NPC, or dialogue node has to know how
## locations are loaded or freed.

signal location_entered(location: LocationRoot, spawn_id: StringName)

var _current: LocationRoot = null
var _current_path: String = ""


func get_current() -> LocationRoot:
	return _current


func get_current_path() -> String:
	return _current_path


## Loads `scene_path` and places `player` at the marker named `spawn_id`.
## Returns false and keeps the previous location when anything is missing.
func load_location(scene_path: String, spawn_id: StringName, player: Node3D) -> bool:
	if scene_path.is_empty():
		push_error("LocationHost: empty scene path.")
		return false
	if not ResourceLoader.exists(scene_path):
		push_error("LocationHost: location scene not found: %s" % scene_path)
		return false
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("LocationHost: '%s' is not a PackedScene." % scene_path)
		return false
	var instance := packed.instantiate()
	if not (instance is LocationRoot):
		push_error("LocationHost: '%s' root must use the LocationRoot script." % scene_path)
		instance.queue_free()
		return false

	var location: LocationRoot = instance
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null

	_current = location
	_current_path = scene_path
	add_child(location)

	if player != null:
		var spawn := location.get_spawn(spawn_id)
		if spawn != null:
			if player.has_method("teleport"):
				player.call("teleport", spawn.global_transform)
			else:
				player.global_position = spawn.global_position
		else:
			push_warning(
				"LocationHost: no spawn point '%s' in %s; player kept its position."
				% [spawn_id, scene_path]
			)

	location_entered.emit(location, spawn_id)
	return true
