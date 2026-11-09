class_name LocationHost
extends Node3D
## Owns the currently loaded location scene and moves the player to its spawn.
##
## Scene swapping lives here so no prop, NPC, or dialogue node has to know how
## locations are loaded or freed.
##
## A transition is a **transaction**: everything that can fail is checked against the
## new scene before the old one is touched. A broken exit therefore leaves the player
## standing in the room they were already in, with the story flag that describes that
## room still correct, and the call still returns false.

signal location_entered(location: LocationRoot, spawn_id: StringName)

## Kept for error messages and for tests that assert the old scene survived.
var _current: LocationRoot = null
var _current_path: String = ""

## How far the body may end up from the marker before the placement counts as failed.
## A teleport assigns the position exactly; anything larger means the player refused
## the transform, and committing the swap around it would hide that.
const PLACEMENT_TOLERANCE := 0.05


func get_current() -> LocationRoot:
	return _current


func get_current_path() -> String:
	return _current_path


## Loads `scene_path` and places `player` at the marker named `spawn_id`.
##
## `spawn_id` empty means "the location's default spawn"; a named spawn must exist.
## `expected_location_id`, when given (normally an exit's `destination_id`), is the id
## the caller believes it is entering, and is refused when the scene disagrees — that
## is what keeps `StoryFlags.CURRENT_LOCATION` describing the room the player is in.
##
## Returns false and keeps the previous location, the player and the emitted-signal
## state untouched when anything is missing.
func load_location(
	scene_path: String,
	spawn_id: StringName,
	player: Node3D,
	expected_location_id: StringName = &""
) -> bool:
	# --- Stage 1: pre-flight. Nothing outside this function may change. ---------
	if scene_path.is_empty():
		push_error("LocationHost: empty scene path; keeping %s." % _describe_current())
		return false
	if not ResourceLoader.exists(scene_path):
		push_error(
			"LocationHost: location scene not found: %s; keeping %s."
			% [scene_path, _describe_current()]
		)
		return false
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error(
			"LocationHost: '%s' is not a PackedScene; keeping %s."
			% [scene_path, _describe_current()]
		)
		return false
	var instance := packed.instantiate()
	if instance == null:
		push_error(
			"LocationHost: '%s' could not be instantiated; keeping %s."
			% [scene_path, _describe_current()]
		)
		return false
	var location := instance as LocationRoot
	if location == null:
		push_error(
			"LocationHost: '%s' root must use the LocationRoot script (got %s); keeping %s."
			% [scene_path, instance.get_class(), _describe_current()]
		)
		_discard(instance)
		return false
	if String(location.location_id).is_empty():
		push_error(
			"LocationHost: '%s' declares no location_id; keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return false
	if (
		not String(expected_location_id).is_empty()
		and location.location_id != expected_location_id
	):
		push_error(
			"LocationHost: expected location_id '%s' but '%s' declares '%s'; keeping %s."
			% [expected_location_id, scene_path, location.location_id, _describe_current()]
		)
		_discard(location)
		return false
	# The player has to be placeable *before* anything moves: there is no second player
	# and no fallback placement, because a swap into a scene the body cannot stand in is
	# not a transition.
	if player == null:
		push_error(
			"LocationHost: no player to place; refusing to enter '%s' and keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return false
	if not player.has_method("teleport"):
		push_error(
			"LocationHost: the player node has no teleport(); refusing to enter '%s' and keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return false
	var spawn := location.get_spawn(spawn_id)
	if spawn == null:
		# get_spawn() already named the location, the id and the markers it does have.
		push_error(
			"LocationHost: refusing to enter '%s' (spawn '%s'); keeping %s."
			% [scene_path, _describe_spawn(spawn_id), _describe_current()]
		)
		_discard(location)
		return false
	# --- Stage 2: commit. From here on the new scene is in the tree. -----------
	var previous := _current
	var previous_path := _current_path
	add_child(location)
	# Read the marker now that the scene has a parent: its global transform is then the
	# one the player will stand on, whatever transform the host itself carries.
	var target: Transform3D = spawn.global_transform
	if not _place_player(player, target):
		# Roll back: the rejected scene leaves the tree again and is freed now, so no
		# frame ever sees it standing next to the old one. `_current` and `_current_path`
		# were not replaced yet; they are restated here so a later reordering of this
		# function cannot quietly skip the restore.
		remove_child(location)
		_discard(location)
		_current = previous
		_current_path = previous_path
		push_error(
			"LocationHost: '%s' was not entered (spawn '%s'); keeping %s."
			% [scene_path, _describe_spawn(spawn_id), _describe_current()]
		)
		return false
	_current = location
	_current_path = scene_path
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	location_entered.emit(location, spawn_id)
	return true


## Places `player` at `target` and reports whether the body actually took it.
func _place_player(player: Node3D, target: Transform3D) -> bool:
	player.call("teleport", target)
	var offset := player.global_position.distance_to(target.origin)
	if offset > PLACEMENT_TOLERANCE:
		push_error(
			"LocationHost: the player did not take the spawn transform (%.3f m off)." % offset
		)
		return false
	return true


## Drops an instance that was never accepted. It is not in the tree, so it can go now
## instead of waiting for a frame: a rejected transition leaves no orphan behind.
func _discard(instance: Node) -> void:
	if is_instance_valid(instance):
		instance.free()


func _describe_current() -> String:
	if _current == null:
		return "no current location"
	return "current location '%s' (%s)" % [String(_current.location_id), _current_path]


func _describe_spawn(spawn_id: StringName) -> String:
	return "<default>" if String(spawn_id).is_empty() else String(spawn_id)
