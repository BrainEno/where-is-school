class_name PointerNavigator
extends Node
## Turns a left-click in the world into a walk, and a left-click on an interactable
## into a walk followed by that interactable's normal activation.
##
## It owns no dialogue, no transitions and no narrative state. When the character
## arrives it calls `InteractionController.request_activation()` — the exact call the
## E key makes — so a clicked object behaves identically to a pressed one and there is
## only ever one activation path to reason about.
##
## Order of resolution for one click, first match wins:
##
## 1. Control is locked (dialogue, scripted beat, transition) — the click is ignored,
##    apart from cancelling a walk that was already in progress.
## 2. An interactable is under the cursor. That becomes the target: walk to a spot
##    inside its interaction radius, then activate it if it is still there, still
##    enabled, and still in reach.
## 3. Otherwise the click is a ground click: walk to the point if the point is on the
##    navigation mesh and the surface is walkable. A wall, a fence or a tree is not a
##    destination and produces restrained feedback instead of a walk.
##
## Input arrives through `_unhandled_input`, so a click that a `Control` consumed
## (a dialogue choice, an overlay) never reaches the world.

## Emitted when a ground destination was accepted.
signal destination_accepted(point: Vector3)
## Emitted when a click landed somewhere the character cannot walk.
signal destination_rejected(point: Vector3)
## Emitted when an interactable was accepted as the automatic-interaction target.
signal approach_started(interactable: Interactable)
## Emitted when the walk finished and the interactable was activated.
signal approach_activated(interactable: Interactable)
## Emitted when the walk ended without activating: gone, disabled, out of reach,
## unreachable, or cancelled by the player.
signal approach_abandoned(interactable: Interactable)

@export var player_path: NodePath = ^".."
@export var interaction_path: NodePath = ^"../InteractionController"
## Physics layers that can be walked on.
@export_flags_3d_physics var ground_mask: int = 1
## Radii tried around an interactable when looking for somewhere to stand, in metres,
## as fractions of its interaction radius plus a body's width.
@export var ring_fractions: PackedFloat32Array = PackedFloat32Array([0.35, 0.6, 0.85])
## How many evenly spaced candidate spots are tried on each ring.
@export_range(4, 48, 1) var ring_samples: int = 16
## A ground click further than this from the navigation mesh is refused rather than
## snapped onto it.
@export var max_snap_distance: float = 0.9
## Highest surface normal that still counts as ground (1 = perfectly flat).
@export_range(0.0, 1.0, 0.01) var min_ground_normal_y: float = 0.6
## Show the quiet ring at the destination (turn off for a bare capture).
@export var marker_enabled: bool = true

var _player: PlayerController = null
var _interaction: InteractionController = null
var _marker: MeshInstance3D = null
var _marker_tween: Tween = null
var _pending: Interactable = null
var _approaching := false
var _enabled := true
var _last_click_accepted := false
## Clicks handed to `click_at_screen_position` (tests and the capture run).
var _click_count := 0
## Mouse presses that actually reached the world as unhandled input. A click consumed
## by a `Control` — a dialogue choice, an overlay — never shows up here, which is how
## the tests prove the two input paths stay separate.
var _world_click_events := 0
## Best-effort point to mark when a click is refused; never used for movement.
var _last_ground_hint: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	if _player == null:
		push_error("PointerNavigator: player_path '%s' did not resolve." % player_path)
		return
	_interaction = get_node_or_null(interaction_path) as InteractionController
	if _interaction == null:
		push_error("PointerNavigator: interaction_path '%s' did not resolve." % interaction_path)
	_player.path_finished.connect(_on_path_finished)
	_player.path_cancelled.connect(_on_path_cancelled)


func set_enabled(interact: bool) -> void:
	_enabled = interact
	if not interact:
		cancel()


func is_enabled() -> bool:
	return _enabled


## Diagnostics: how many clicks reached the world, and whether the last one was
## accepted. The capture run and the tests use these instead of guessing.
func get_click_count() -> int:
	return _click_count


func was_last_click_accepted() -> bool:
	return _last_click_accepted


func get_world_click_event_count() -> int:
	return _world_click_events


func get_pending_target() -> Interactable:
	return _pending


func is_approaching() -> bool:
	return _approaching


## Forgets the current walk and target. Safe to call at any time.
func cancel() -> void:
	var abandoned := _pending
	_pending = null
	_approaching = false
	_hide_marker()
	if _player != null:
		_player.cancel_path()
	if abandoned != null and is_instance_valid(abandoned):
		approach_abandoned.emit(abandoned)


## A click at a screen position, in the same shape the real mouse produces. Public so
## a headless test or the capture run can click the world without a real cursor.
func click_at_screen_position(screen_position: Vector2) -> void:
	if not _enabled:
		return
	_click_count += 1
	_last_click_accepted = false
	if _player == null or _interaction == null:
		return
	if not _player.is_control_enabled():
		# Presentation owns input. Do not queue the click for later.
		cancel()
		return
	var target := _interaction.get_target_at_screen_position(screen_position, false)
	if target != null:
		_begin_approach(target)
		return
	var point: Variant = _ground_point_at(screen_position)
	if point == null:
		_reject_point(_screen_hint(screen_position))
		return
	_last_ground_hint = point
	_walk_to(point)


## The walkable point a click at this screen position would use, or null. Public so a
## test or the capture run can aim at the floor without guessing where it is.
func get_ground_point_at(screen_position: Vector2) -> Variant:
	if _player == null:
		return null
	return _ground_point_at(screen_position)


## Whether a click at this screen position would land on walkable ground.
func can_walk_to_screen_position(screen_position: Vector2) -> bool:
	return get_ground_point_at(screen_position) != null


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	get_viewport().set_input_as_handled()
	_world_click_events += 1
	click_at_screen_position(mouse.position)


# --- Ground picking ---------------------------------------------------------


## Where a ground click lands, or null when there is no walkable surface there.
##
## The ray only asks for static world geometry (`ground_mask`) and skips the player and
## the interaction areas, so an NPC's body cannot be mistaken for floor. The hit must
## face up, and the point must be on the navigation mesh: a click on a desk top, a
## fence rail or a roof is a click on nothing walkable.
func _ground_point_at(screen_position: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return null
	var world := _player.get_world_3d()
	if world == null:
		return null
	var space := world.direct_space_state
	if space == null:
		return null
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.length_squared() <= 0.0001:
		return null
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 60.0, ground_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.normalized().dot(Vector3.UP) < min_ground_normal_y:
		return null
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	var map := _player.navigation_agent.get_navigation_map()
	if not _map_has_geometry(map):
		return null
	var snapped := NavigationServer3D.map_get_closest_point(map, point)
	if Vector2(snapped.x - point.x, snapped.z - point.z).length() > max_snap_distance:
		return null
	if absf(snapped.y - point.y) > 1.2:
		return null
	return snapped


func _walk_to(point: Vector3) -> void:
	_pending = null
	_approaching = false
	if _player.request_path_to(point):
		_last_click_accepted = true
		_show_marker(point)
		destination_accepted.emit(point)
		return
	_reject_point(point)


func _reject_point(point: Vector3) -> void:
	_last_click_accepted = false
	_last_ground_hint = point
	destination_rejected.emit(point)
	# Restrained: a brief dim ring where the click landed, nothing modal, no walk.
	_show_marker(point, true)


## Where a refused click visually lands: the camera ray against the plane the player
## stands on. Only used to place the "not here" feedback.
func _screen_hint(screen_position: Vector2) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return _player.global_position
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var plane := Plane(Vector3.UP, _player.global_position.y)
	var hit = plane.intersects_ray(from, direction)
	if hit == null:
		return _player.global_position + _player.get_facing_direction() * 1.5
	return hit as Vector3


# --- Automatic interaction --------------------------------------------------


## Walk to `target` and activate it on arrival, unless the player is already close
## enough — then it activates immediately, which is what a click on a nearby prop
## should feel like.
func _begin_approach(target: Interactable) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _pending != null and _pending != target:
		# A new click on another object replaces the old target.
		_abandon_pending()
	_pending = null
	_approaching = false
	_player.cancel_path()
	_hide_marker()
	_pending = target
	if _can_activate_now(target):
		_activate_pending()
		return
	var spot: Variant = _find_approach_spot(target)
	if spot == null:
		# Nothing the character can stand next to, or no route to it: say so with the
		# same quiet ring a refused ground click gets, and stay put.
		_abandon_pending()
		_show_marker(target.global_position, true)
		return
	if not _player.request_path_to(spot):
		_abandon_pending()
		_show_marker(target.global_position, true)
		return
	_approaching = true
	_last_click_accepted = true
	_show_marker(spot)
	approach_started.emit(target)


## A spot inside the object's interaction radius, on the navigation mesh, with a real
## route to it and a clear view of the object. The nearest one wins.
func _find_approach_spot(target: Interactable) -> Variant:
	if not is_instance_valid(target):
		return null
	var map := _player.navigation_agent.get_navigation_map()
	if not _map_has_geometry(map):
		return null
	var origin := target.global_position
	var reach := maxf(target.radius, 0.4)
	var best: Vector3 = Vector3.ZERO
	var best_cost := INF
	for fraction: float in ring_fractions:
		var radius: float = clampf(reach * fraction + 0.35, 0.45, reach * 1.35)
		for index in ring_samples:
			var angle := TAU * float(index) / float(ring_samples)
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.6:
				continue
			var to_player := candidate - _player.global_position
			var to_player_flat := Vector2(to_player.x, to_player.z).length()
			if to_player_flat < 0.35:
				# Standing on top of the target is not an approach.
				continue
			var path := NavigationServer3D.map_get_path(
				map, _player.global_position, Vector3(snapped.x, candidate.y + 0.05, snapped.z), true
			)
			if path.size() < 2:
				continue
			if not _interaction.has_line_of_sight_from(
				Vector3(snapped.x, candidate.y + _interaction.eye_height, snapped.z), target
			):
				# Standing there would put a wall or a desk between the character and
				# the thing they meant to use.
				continue
			var cost := _path_length(path)
			if cost < best_cost:
				best_cost = cost
				best = Vector3(snapped.x, candidate.y + 0.05, snapped.z)
	return null if best_cost == INF else best


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += Vector2(path[index].x - path[index - 1].x, path[index].z - path[index - 1].z).length()
	return total


func _can_activate_now(target: Interactable) -> bool:
	if not is_instance_valid(target) or not target.can_interact():
		return false
	if not _interaction.is_in_reach(target):
		return false
	return _interaction.has_line_of_sight(target)


func _activate_pending() -> void:
	var target := _pending
	_pending = null
	_approaching = false
	_hide_marker()
	if target == null or not is_instance_valid(target):
		return
	# Re-validated at the last moment: the object may have been disabled or freed
	# while the character was walking.
	if not _can_activate_now(target):
		approach_abandoned.emit(target)
		return
	_interaction.request_activation(target)
	_last_click_accepted = true
	approach_activated.emit(target)


func _abandon_pending() -> void:
	var target := _pending
	_pending = null
	_approaching = false
	_hide_marker()
	if target != null and is_instance_valid(target):
		approach_abandoned.emit(target)


func _on_path_finished() -> void:
	if _pending != null:
		_activate_pending()
		return
	if _approaching:
		_approaching = false


func _on_path_cancelled() -> void:
	# Cancelled from outside (manual input, control lock, transition): drop the target
	# so a later arrival in another room cannot activate it.
	if _pending != null:
		_abandon_pending()
	else:
		_approaching = false
		_hide_marker()


# --- Destination marker -----------------------------------------------------


## A flat ring at the destination. Deliberately quiet: it answers "did that click
## register, and where?" and then gets out of the way.
func _ensure_marker() -> void:
	if not marker_enabled or _marker != null:
		return
	var parent: Node = _player.get_parent() if _player != null else null
	# Created on first use, never in _ready(): adding a child to a node that is still
	# setting up its own children fails, and an orphan marker would report a transform
	# error on every click.
	if parent == null or not parent.is_inside_tree():
		return
	_marker = MeshInstance3D.new()
	_marker.name = "DestinationMarker"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.3
	ring.rings = 16
	ring.ring_segments = 8
	_marker.mesh = ring
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.86, 0.85, 0.78, 0.55)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.88, 0.8)
	material.emission_energy_multiplier = 0.6
	_marker.material_override = material
	_marker.rotation_degrees.x = 90.0
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	parent.add_child(_marker)


func _show_marker(point: Vector3, rejected: bool = false) -> void:
	_ensure_marker()
	if _marker == null:
		return
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
	_marker.global_position = point + Vector3.UP * 0.03
	_marker.scale = Vector3.ONE * (1.0 if not rejected else 0.7)
	var material := _marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(0.75, 0.6, 0.55, 0.45) if rejected \
			else Color(0.86, 0.85, 0.78, 0.55)
	_marker.visible = true
	if rejected:
		_marker_tween = create_tween()
		_marker_tween.tween_interval(0.35)
		_marker_tween.tween_callback(_hide_marker)


func _hide_marker() -> void:
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
	_marker_tween = null
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = false


func _map_has_geometry(map: RID) -> bool:
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_regions(map).size() > 0
