class_name InteractionController
extends Node
## Finds the best interaction target near the player and forwards the player's
## intent. Owns no UI and no narrative logic.
##
## Two ways to pick a target, one of them always wins the same way:
##
## 1. **The pointer.** If the mouse is over an interactable that is close enough
##    and not behind a wall, that object is the target, whatever the player is
##    facing. A pointer is an explicit statement of intent.
## 2. **Facing.** Otherwise the object in front of the player and nearest to them
##    wins, so two props in the same aisle do not produce a flickering prompt.
##
## To stop the prompt blinking at the edge of a prop, a pointer pick has to hold
## still for `mouse_hold_frames` frames before it takes over from a different
## target. Nothing else about the two paths differs: both end in the same
## `_set_current`, the same highlight, and the same E/`request_activation` call,
## so what the cue shows is what the key uses.

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
## Whether the mouse can pick a target. Turning this off leaves facing-only
## targeting, which is what the headless tests for the old behaviour assume.
@export var mouse_targeting: bool = true
## Frames a new pointer pick must survive before it replaces a different target.
## One frame is ~16 ms: enough to swallow a jitter at a prop's edge, invisible to
## a player who means to point at something.
@export var mouse_hold_frames: int = 1

var _player: Node3D = null
var _sensor: Area3D = null
var _current: Interactable = null
var _enabled: bool = true
var _highlighted: Interactable = null
## A pointer pick that has not yet been adopted, and how many frames it has held.
var _mouse_pending: Interactable = null
var _mouse_pending_frames: int = 0
## Test seam: a pinned pointer position, used instead of the real cursor. Headless
## runs have no cursor, and the capture run uses the real one, so this exists only
## so a headless test can ask the same question the mouse asks.
var _mouse_override := Vector2.ZERO
var _has_mouse_override := false
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


## Every interactable currently marked as the target (there is at most one, and it
## is the same node `get_current_target` returns). Kept as a helper so a test can
## assert the cue and the key cannot drift apart.
func get_highlighted() -> Interactable:
	return _highlighted


func _physics_process(_delta: float) -> void:
	if not _enabled or _player == null or _sensor == null:
		_set_current(null)
		return
	# A location swap frees the old props; never hold a dangling target.
	if _current != null and not is_instance_valid(_current):
		_set_current(null)
	if _highlighted != null and not is_instance_valid(_highlighted):
		_set_highlighted(null)
	_set_current(_resolve_target())
	_scan_count += 1


## The screen-space ray ask: which interactable is under this point, if any?
## Public so a test (and the capture run) can ask the exact question the mouse
## path asks, without needing a real cursor.
##
## `require_reach` is what separates the two callers: hovering and the E key only care
## about something the player could use right now, while a click may legitimately name
## an object across the room that the character should walk to first.
func get_target_at_screen_position(screen_position: Vector2, require_reach: bool = true) -> Interactable:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _player == null:
		return null
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.length_squared() <= 0.0001:
		return null
	var far_point := from + direction * 60.0
	var query := PhysicsRayQueryParameters3D.create(from, far_point, Interactable.INTERACTION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := _player.get_world_3d().direct_space_state if _player.get_world_3d() != null else null
	if space == null:
		return null
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var candidate := hit.get("collider") as Interactable
	if candidate == null or not candidate.can_interact():
		return null
	if require_reach and not _in_reach(candidate):
		return null
	if not _has_line_of_sight(candidate):
		return null
	return candidate


## Pins the pointer to a screen position (tests only). The real cursor path is
## unchanged for the game and for the capture run.
func set_mouse_override(screen_position: Vector2) -> void:
	_has_mouse_override = true
	_mouse_override = screen_position


func clear_mouse_override() -> void:
	_has_mouse_override = false


func _find_mouse_target() -> Interactable:
	if not mouse_targeting or not is_inside_tree():
		return null
	if _has_mouse_override:
		return get_target_at_screen_position(_mouse_override)
	if DisplayServer.get_name() == "headless":
		# There is no cursor and no window; the pointer path stays dormant instead
		# of returning a meaningless (0, 0) hit.
		return null
	return get_target_at_screen_position(get_viewport().get_mouse_position())


## Public view of the reach test, used by the pointer navigator before it activates
## something it walked to.
func is_in_reach(candidate: Interactable) -> bool:
	return _in_reach(candidate)


## Public view of the line-of-sight test. Kept as a wrapper so the "can I see it"
## rule has exactly one implementation.
func has_line_of_sight(candidate: Interactable) -> bool:
	return _has_line_of_sight(candidate)


func _in_reach(candidate: Interactable) -> bool:
	if _player == null:
		return false
	return is_in_reach_at(_player.global_position, candidate)


## The same reach test measured from an arbitrary point, so a caller looking for
## somewhere to stand can ask "would this spot be close enough?" without moving the
## character to find out.
func is_in_reach_at(from: Vector3, candidate: Interactable) -> bool:
	if candidate == null:
		return false
	var offset := candidate.global_position - from
	offset.y = 0.0
	return offset.length() <= max_distance and offset.length() > 0.001


## Pointer first, facing second, with one frame of hysteresis in between.
func _resolve_target() -> Interactable:
	var facing_target := _find_best_target()
	if not mouse_targeting:
		return facing_target
	var mouse_target := _find_mouse_target()
	if mouse_target == null:
		_mouse_pending = null
		_mouse_pending_frames = 0
		return facing_target
	if mouse_target == _current:
		_mouse_pending = null
		_mouse_pending_frames = 0
		return _current
	if _mouse_pending != mouse_target:
		_mouse_pending = mouse_target
		_mouse_pending_frames = 0
	if _mouse_pending_frames < mouse_hold_frames:
		_mouse_pending_frames += 1
		return _current if _current != null and is_instance_valid(_current) else facing_target
	return mouse_target


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
	return has_line_of_sight_from(_player.global_position + Vector3.UP * eye_height, candidate) \
		if _player != null else true


## The same probe from an arbitrary eye position, so a caller choosing where to stand
## can ask "could I see it from there?" without walking there first.
func has_line_of_sight_from(from: Vector3, candidate: Interactable) -> bool:
	if _player == null or occluder_mask == 0:
		return true
	var world := _player.get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
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
		_set_highlighted(_current)
		return
	_current = interactable
	# The highlight follows the target, never the other way round: one call site
	# keeps the cue and the E key describing the same object.
	_set_highlighted(_current)
	target_changed.emit(_current)


func _set_highlighted(interactable: Interactable) -> void:
	if _highlighted == interactable:
		return
	if _highlighted != null and is_instance_valid(_highlighted):
		_highlighted.set_highlighted(false)
	_highlighted = interactable
	if _highlighted != null and is_instance_valid(_highlighted):
		_highlighted.set_highlighted(true)
