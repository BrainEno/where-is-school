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

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")

signal location_entered(location: LocationRoot, spawn_id: StringName)
## In-place recovery, not an arrival: no story flags, hooks or saves are replayed.
signal player_recovered

const SAFE_SAMPLE_INTERVAL := 0.12
## Marker metadata: the marker's rotation is the heading the player arrives with. Without
## it, an identity rotation means "keep the previous heading" (PlayerController.teleport),
## which is only right for restoring or interrupting a location, not for a doorway.
const ENTRY_FACING_META := &"entry_facing"
const SUPPORT_MARGIN := 0.38 # Wider than the playable capsule's 0.35 m radius.
const SUPPORT_VERTICAL := 0.30 # Allows contact on either side of a normal stair slope.
const WORLD_SOLIDS := 1
const SUPPORT_DIRECTIONS: Array[Vector3] = [
	Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
]
var _player: PlayerController = null
var _entry_pose := Transform3D.IDENTITY
var _safe_pose := Transform3D.IDENTITY
var _sample_in := 0.0

## Kept for error messages and for tests that assert the old scene survived.
var _current: LocationRoot = null
var _current_path: String = ""
## The marker the player was placed on when the current location was entered. A save
## needs it: the room says where the player *may* arrive, this says where they did.
var _current_spawn: StringName = &""

## How far the body may end up from the marker before the placement counts as failed.
## A teleport assigns the position exactly; anything larger means the player refused
## the transform, and committing the swap around it would hide that.
const PLACEMENT_TOLERANCE := 0.05

## Diagnostics, not a feature: a transition is timed and counted so the cost of a location
## can be measured instead of guessed, and the numbers are printed only by debug builds and
## tests. Release players are not given a console line per door.
const PERF_HISTORY := 16

## The last `PERF_HISTORY` transitions, oldest first. Read by the pressure test and by
## anyone asking where a transition's time went; each entry is documented in `_record()`.
var transition_history: Array[Dictionary] = []

## Cumulative marks of the transition in flight, in microseconds since it started. Filled by
## `_mark()` inside the transaction and consumed by `_record()` when it returns, whichever
## way it returned.
var _marks: Dictionary = {}


func _ready() -> void:
	# Sample the result of move_and_slide(), not the previous tick's floor.
	process_physics_priority = 1


func _physics_process(delta: float) -> void:
	if _current == null or not is_instance_valid(_player) or not _player.is_control_enabled():
		# Staged departures (curtain, ladder) own the body until they release the beat.
		return
	var feet := _player.global_position
	if _current.is_below_playable_space(feet):
		var target := _recovery_pose()
		_player.teleport(target)
		# A recovered pose has a real heading even when it points along the default -Z
		# axis, so it is set explicitly rather than read as "keep facing".
		_player.face_toward(-target.basis.z)
		player_recovered.emit()
		return
	_sample_in -= delta
	if _sample_in > 0.0 or not _player.is_on_floor() or _player.velocity.y > 0.001:
		return
	_sample_in = SAFE_SAMPLE_INTERVAL
	if _has_support(feet):
		_safe_pose = Transform3D(Basis.looking_at(_player.get_facing_direction(), Vector3.UP), feet)


## A save taken during a deep fall can keep all its flags without putting Continue in
## the void. Normal grounded saves still preserve the exact live position and facing.
func needs_safe_checkpoint(player: PlayerController) -> bool:
	return player == _player and _current != null and (
		_current.is_below_playable_space(player.global_position)
		or (not player.is_on_floor() and player.velocity.y < -1.5)
	)


func get_safe_checkpoint() -> Transform3D:
	# Called by the save writer, which may be outside the physics step. The pose was
	# already verified in physics; a live recovery checks it again before placing.
	return _safe_pose


func _recovery_pose() -> Transform3D:
	if _has_support(_safe_pose.origin):
		# Give the capsule a little room to settle instead of restoring exactly on a contact.
		return _safe_pose.translated(Vector3.UP * 0.04)
	_safe_pose = _entry_pose
	return _entry_pose


func _has_support(feet: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = WORLD_SOLIDS
	query.exclude = [_player.get_rid()]
	# A capsule can report floor contact with only a sliver of its rim over a drop.
	# Require a cushion of stationary world geometry around the contact, not Q or glass.
	for direction in SUPPORT_DIRECTIONS:
		var probe := feet + direction * SUPPORT_MARGIN
		query.from = probe + Vector3.UP * SUPPORT_VERTICAL
		query.to = probe - Vector3.UP * SUPPORT_VERTICAL
		var hit := space.intersect_ray(query)
		var body := hit.get("collider") as StaticBody3D
		if body == null or not _current.is_ancestor_of(body):
			return false
		var normal: Vector3 = hit["normal"]
		if normal.y < cos(_player.floor_max_angle):
			return false
	return true


func get_current() -> LocationRoot:
	return _current


func get_current_path() -> String:
	return _current_path


## The spawn marker the current location was entered through.
func get_current_spawn() -> StringName:
	return _current_spawn


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
	# The wrapper exists so the timing covers every exit of the transaction, including the
	# failures, without a single `return` inside the transaction having to know about it.
	var from_id := _current.location_id if _current != null else &""
	var started := Time.get_ticks_usec()
	_marks = {}
	var reason := _swap(scene_path, spawn_id, player, expected_location_id, started)
	var ok := reason == &"entered"
	_record(scene_path, spawn_id, ok, started)
	if not ok:
		OfflineDiagnostics.note("world.transition_refused", {
			"from_location": from_id, "to_location": expected_location_id, "reason": reason,
		})
	return ok


## The transaction itself. Returns a diagnostic code; the public method still returns bool.
func _swap(
	scene_path: String,
	spawn_id: StringName,
	player: Node3D,
	expected_location_id: StringName,
	started: int
) -> StringName:
	# --- Stage 1: pre-flight. Nothing outside this function may change. ---------
	if scene_path.is_empty():
		push_error("LocationHost: empty scene path; keeping %s." % _describe_current())
		return &"no_scene"
	if not ResourceLoader.exists(scene_path):
		push_error(
			"LocationHost: location scene not found: %s; keeping %s."
			% [scene_path, _describe_current()]
		)
		return &"scene_missing"
	var packed := load(scene_path) as PackedScene
	_mark("loaded", started)
	if packed == null:
		push_error(
			"LocationHost: '%s' is not a PackedScene; keeping %s."
			% [scene_path, _describe_current()]
		)
		return &"not_packed_scene"
	var instance := packed.instantiate()
	_mark("instantiated", started)
	if instance == null:
		push_error(
			"LocationHost: '%s' could not be instantiated; keeping %s."
			% [scene_path, _describe_current()]
		)
		return &"instantiation_failed"
	var location := instance as LocationRoot
	if location == null:
		push_error(
			"LocationHost: '%s' root must use the LocationRoot script (got %s); keeping %s."
			% [scene_path, instance.get_class(), _describe_current()]
		)
		_discard(instance)
		return &"invalid_root"
	if String(location.location_id).is_empty():
		push_error(
			"LocationHost: '%s' declares no location_id; keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return &"no_location_id"
	if (
		not String(expected_location_id).is_empty()
		and location.location_id != expected_location_id
	):
		push_error(
			"LocationHost: expected location_id '%s' but '%s' declares '%s'; keeping %s."
			% [expected_location_id, scene_path, location.location_id, _describe_current()]
		)
		_discard(location)
		return &"mismatched_location"
	# The player has to be placeable *before* anything moves: there is no second player
	# and no fallback placement, because a swap into a scene the body cannot stand in is
	# not a transition.
	if player == null:
		push_error(
			"LocationHost: no player to place; refusing to enter '%s' and keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return &"no_player"
	if not player.has_method("teleport"):
		push_error(
			"LocationHost: the player node has no teleport(); refusing to enter '%s' and keeping %s."
			% [scene_path, _describe_current()]
		)
		_discard(location)
		return &"no_teleport"
	var spawn := location.get_spawn(spawn_id)
	if spawn == null:
		# get_spawn() already named the location, the id and the markers it does have.
		push_error(
			"LocationHost: refusing to enter '%s' (spawn '%s'); keeping %s."
			% [scene_path, _describe_spawn(spawn_id), _describe_current()]
		)
		_discard(location)
		return &"no_spawn"
	# --- Stage 2: commit. From here on the new scene is in the tree. -----------
	var previous := _current
	var previous_path := _current_path
	add_child(location)
	_mark("in_tree", started)
	# Read the marker now that the scene has a parent: its global transform is then the
	# one the player will stand on, whatever transform the host itself carries.
	var target: Transform3D = spawn.global_transform
	var face_entry: bool = spawn.get_meta(ENTRY_FACING_META, false)
	if not _place_player(player, target, face_entry):
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
		return &"placement_failed"
	_mark("placed", started)
	_current = location
	_current_path = scene_path
	_current_spawn = spawn_id
	_player = player as PlayerController
	_entry_pose = target
	_safe_pose = target
	_sample_in = 0.0
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	_mark("committed", started)
	OfflineDiagnostics.note("world.entered", {
		"from_location": previous.location_id if previous != null else &"",
		"to_location": location.location_id,
	})
	location_entered.emit(location, spawn_id)
	return &"entered"


## Places `player` at `target` and reports whether the body actually took it. With
## `face_entry`, the heading is the marker's own -Z even when its basis is identity.
func _place_player(player: Node3D, target: Transform3D, face_entry: bool) -> bool:
	player.call("teleport", target)
	if face_entry:
		player.call("face_toward", -target.basis.z)
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


## Records the cumulative time of a stage, in microseconds from the transition's start.
func _mark(stage: String, started: int) -> void:
	if not _perf_enabled():
		return
	_marks[stage] = Time.get_ticks_usec() - started


## Adds one entry to `transition_history` and prints it. The entry is a plain Dictionary so
## the pressure test can assert on it: which scene, how long each stage took, how many nodes
## the incoming and outgoing scenes carried, and how many location scenes were alive at the
## moment of the swap (two is correct in flight, more than two is a leak).
func _record(scene_path: String, spawn_id: StringName, ok: bool, started: int) -> void:
	if not _perf_enabled():
		return
	var total := Time.get_ticks_usec() - started
	var entry := {
		"scene": scene_path,
		"spawn": String(spawn_id),
		"ok": ok,
		"stage": _last_stage(),
		"load_usec": _span("loaded"),
		"instantiate_usec": _span("instantiated") - _span("loaded"),
		"tree_usec": _span("in_tree") - _span("instantiated"),
		"placement_usec": _span("placed") - _span("in_tree"),
		"commit_usec": _span("committed") - _span("placed"),
		"total_usec": total,
		"scene_nodes": _live_node_count(),
		"live_locations": _location_child_count(),
	}
	transition_history.append(entry)
	while transition_history.size() > PERF_HISTORY:
		transition_history.pop_front()
	if not ok:
		print(
			"LocationHost: %s FAILED at '%s' after %.1f ms (%d live location scene(s))."
			% [scene_path, entry["stage"], total / 1000.0, entry["live_locations"]]
		)
		return
	print(
		(
			"LocationHost: %s in %.1f ms "
			+ "(load %.1f, instantiate %.1f, tree %.1f, place %.1f, commit %.1f), "
			+ "%d nodes, %d live location(s)."
		)
		% [
			scene_path,
			total / 1000.0,
			entry["load_usec"] / 1000.0,
			entry["instantiate_usec"] / 1000.0,
			entry["tree_usec"] / 1000.0,
			entry["placement_usec"] / 1000.0,
			entry["commit_usec"] / 1000.0,
			entry["scene_nodes"],
			entry["live_locations"],
		]
	)


func _span(stage: String) -> int:
	return int(_marks.get(stage, 0))


func _last_stage() -> String:
	var stages := ["loaded", "instantiated", "in_tree", "placed", "committed"]
	var reached := "pre-flight"
	for stage: String in stages:
		if _marks.has(stage):
			reached = stage
	return reached


## Nodes in the current scene, counted from the scene root down.
func _live_node_count() -> int:
	if _current == null:
		return 0
	return _count_nodes(_current)


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _location_child_count() -> int:
	var total := 0
	for child in get_children():
		if child is LocationRoot:
			total += 1
	return total


func _perf_enabled() -> bool:
	return OS.is_debug_build()


func get_last_transition() -> Dictionary:
	if transition_history.is_empty():
		return {}
	return transition_history[transition_history.size() - 1]


func _describe_current() -> String:
	if _current == null:
		return "no current location"
	return "current location '%s' (%s)" % [String(_current.location_id), _current_path]


func _describe_spawn(spawn_id: StringName) -> String:
	return "<default>" if String(spawn_id).is_empty() else String(spawn_id)
