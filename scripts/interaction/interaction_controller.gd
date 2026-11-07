class_name InteractionController
extends Node
## Finds the best interaction target near the player and forwards the player's
## intent. Owns no UI and no narrative logic.
##
## Target choice prefers the object the player is facing, then distance, so two
## props in the same isle do not produce a flickering prompt.

signal target_changed(interactable: Interactable)
signal activation_requested(interactable: Interactable)

@export var player_path: NodePath = ^".."
@export var sensor_path: NodePath = ^"../InteractionSensor"
@export var max_distance: float = 2.4
## How strongly facing direction outweighs raw distance when ranking targets.
@export var facing_weight: float = 0.9
## Physics layer(s) that can hide an interactable (walls, floors, props).
@export_flags_3d_physics var occluder_mask: int = 1
## Eyeball height used for the line-of-sight probe.
@export var eye_height: float = 1.1

var _player: Node3D = null
var _sensor: Area3D = null
var _current: Interactable = null
var _enabled: bool = true
## Counts completed target scans. Diagnostics only: it proves the scan is alive.
var _scan_count: int = 0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		push_error("InteractionController: player_path '%s' did not resolve." % player_path)
	_sensor = get_node_or_null(sensor_path) as Area3D
	if _sensor == null:
		push_error("InteractionController: sensor_path '%s' did not resolve." % sensor_path)
	set_process_input(false)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if enabled:
		set_process_input(true)
	else:
		set_process_input(false)
		_set_current(null)


func is_enabled() -> bool:
	return _enabled


func get_scan_count() -> int:
	return _scan_count


func get_current_target() -> Interactable:
	return _current


func _physics_process(_delta: float) -> void:
	if not _enabled or _player == null or _sensor == null:
		_set_current(null)
		return
	# A location swap frees the old props; never hold a dangling target.
	if _current != null and not is_instance_valid(_current):
		_set_current(null)
	_set_current(_find_best_target())
	_scan_count += 1


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if not event.is_action_pressed("interact"):
		return
	# Held keys repeat; only a fresh press may trigger a new interaction, so the
	# player can let go and press again for the next object.
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _current == null or not is_instance_valid(_current):
		return
	get_viewport().set_input_as_handled()
	request_activation(_current)


## The single activation intent path: input, automated tests, and any future
## remapping layer all come through here. The interactable still decides whether
## it can be used, so callers do not need to pre-check.
func request_activation(interactable: Interactable) -> void:
	if not _enabled or interactable == null:
		return
	if not interactable.activate():
		return
	activation_requested.emit(interactable)


func _find_best_target() -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var origin := _player.global_position
	# The actor's own facing, not the node's basis: the player turns its visual
	# pivot and reports the direction separately, so the body itself never rotates.
	var facing := -_player.global_basis.z
	var actor := _actor_with_facing(_player)
	if actor != null:
		facing = actor.get_facing_direction()
	facing.y = 0.0
	if facing.length_squared() <= 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()

	for area: Area3D in _sensor.get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.can_interact():
			continue
		var offset := candidate.global_position - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance > max_distance or distance <= 0.001:
			continue
		var alignment := facing.dot(offset.normalized())
		if not _has_line_of_sight(candidate):
			continue
		var score := distance + facing_weight * (1.0 - maxf(alignment, 0.0))
		if score < best_score:
			best_score = score
			best = candidate
	return best


## You cannot read a notice through a wall. Two probes are cast (upper body and
## knee height) and either one being clear is enough, so a desk in front of a
## schoolbag does not make the bag unusable.
##
## The object's own furniture is the usual thing a ray hits first: a desk hides the
## desk. Colliders standing next to the candidate are therefore treated as part of
## it and ignored, while anything further away (a wall, a door) still blocks.
## The node that knows where the player is looking: the body that reports its own
## facing direction. The controller may be attached to the body, to one of its
## pivots, or to a wrapper, so this walks up instead of assuming a path.
func _actor_with_facing(start: Node) -> Node:
	var node := start
	while node != null:
		if node.has_method("get_facing_direction"):
			return node
		node = node.get_parent()
	return null


func _has_line_of_sight(candidate: Interactable) -> bool:
	if _player == null or occluder_mask == 0:
		return true
	var world := _player.get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var from := _player.global_position + Vector3.UP * eye_height
	var own_limit := maxf(candidate.radius + 1.0, 1.6)
	var excluded: Array[RID] = []
	var player_body := _player as CollisionObject3D
	if player_body != null:
		excluded.append(player_body.get_rid())
	var candidate_distance := from.distance_to(candidate.global_position)
	var probes: Array[Vector3] = [
		candidate.global_position + Vector3.UP * 0.35,
		candidate.global_position + Vector3.UP * 0.05,
		Vector3(candidate.global_position.x, from.y, candidate.global_position.z),
	]
	for probe in probes:
		var to: Vector3 = probe
		var blocked := false
		for _attempt in 6:
			var query := PhysicsRayQueryParameters3D.create(from, to, occluder_mask)
			query.exclude = excluded
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				blocked = false
				break
			blocked = true
			# A surface that is not clearly in front of the object is the object's own
			# backing: a notice on a wall, a gate in a doorway, a bag on a desk.
			var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
			if from.distance_to(hit_position) > candidate_distance - 0.35:
				blocked = false
				break
			var collider := hit.get("collider") as Node3D
			if collider == null:
				break
			if collider.global_position.distance_to(candidate.global_position) > own_limit:
				break
			var own_body := collider as CollisionObject3D
			if own_body == null:
				break
			excluded.append(own_body.get_rid())
		if not blocked:
			return true
	return false


func _set_current(interactable: Interactable) -> void:
	if _current == interactable:
		return
	_current = interactable
	target_changed.emit(_current)
