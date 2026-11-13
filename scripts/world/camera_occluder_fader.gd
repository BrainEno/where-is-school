class_name CameraOccluderFader
extends Node3D
## Fades geometry that sits between the camera and the player.
##
## The 2.5D camera is fixed and fairly steep, so a near wall can still cover the
## player when they walk up to it. Anything in the `camera_occluder` group is
## dithered out while it blocks the view and restored afterwards, which keeps
## navigation readable without moving the camera.
##
## **How the fade is drawn (issue #115, classroom art regression).** Exactly one
## renderer owns opacity. Forward+ supports `GeometryInstance3D.transparency` directly;
## multiplying a material's alpha by the same fade made a requested 18% wall only 3.24%
## opaque (confirmed by tests/classroom_wall_render_test.gd on real frames). Forward+
## therefore leaves all authored materials alone. Mobile and Compatibility ignore instance
## transparency, so they still need alpha-blended BaseMaterial3D copies whose albedo alpha
## follows the fade (`_apply_fade`), restored to the exact resources when the wall clears.
## Their alpha pass writes no depth, and InteractionController/outline masks see the same
## relief. On those two renderers only StandardMaterial3D/ORMMaterial3D can be copied;
## a ShaderMaterial (or no material) stays opaque and is counted as opaque. Forward+
## can instance-fade those too. `material_overlay`, ray selection, fade speed and collision
## are unchanged. Do not replace this renderer distinction with unconditional alpha copies.
##
## **What is faded (issue #115).** Two rays: camera to the target's eye, and camera to the
## point the target faces, `facing_reach` ahead at the same height. The second one is there
## because interaction now asks the camera too: an object is only usable while the camera
## can see it (`InteractionController.is_seen_by_camera`). Standing in front of the
## classroom timetable, the first ray passes the south wall through the door gap and that
## wall stayed opaque, hiding the sheet the player was facing; the facing ray crosses the
## wall and fades it. The facing comes from the target if it reports one
## (`get_facing_direction`), or else from what the target itself follows through its
## `target_path` - in the game the fader's target is the `CameraRig`, which follows the
## player. With no facing there is no second ray. Both rays skip that actor's own body.

@export var target_path: NodePath = ^"../.."
@export var occluder_group: StringName = &"camera_occluder"
@export var faded_transparency: float = 0.82
@export var fade_speed: float = 6.0
## Height on the target the camera should still see.
@export var target_eye_height: float = 1.1
## How far ahead of the target its facing ray aims. 0 turns the facing ray off.
@export var facing_reach: float = 0.9

@onready var _camera: Camera3D = get_parent() as Camera3D

var _target: Node3D = null
## Who the facing comes from: the target, or what it follows (resolved once, lazily).
var _actor: Node = null
var _actor_resolved := false
var _faded: Array[Node] = []
## Geometry -> {"override": its authored material_override, "surfaces": its authored
## surface override materials, "copies": the alpha-blended copies drawn instead}, for
## every piece whose materials are currently swapped.
var _swapped: Dictionary = {}
## Rendering method is fixed for the lifetime of the process.
var _uses_instance_fade := false


func _ready() -> void:
	_uses_instance_fade = RenderingServer.get_current_rendering_method() == "forward_plus"
	# Before the player's InteractionController in every physics tick: it asks whether the
	# camera sees an object through these walls (#115), and it should get the answer the
	# frame about to be rendered shows, not last tick's. The cost is that the fade itself
	# follows the camera a tick late, which an 8-frame fade hides.
	process_physics_priority = -1
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("CameraOccluderFader: target_path '%s' did not resolve." % target_path)
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _target == null or _camera == null:
		return
	var space := _camera.get_world_3d().direct_space_state
	if space == null:
		return
	var eye := _target.global_position + Vector3(0.0, target_eye_height, 0.0)
	var blockers: Array[Node] = [_first_occluder(space, eye)]
	var facing := _target_facing()
	if facing != Vector3.ZERO:
		blockers.append(_first_occluder(space, eye + facing * facing_reach))

	# Rebuild the set every frame instead of appending to it. Each ray has at most one
	# blocker, and "what blocks the view now" is the whole truth. Appending made the set a
	# history: when the blocker changed from one wall to another with no unobstructed
	# frame in between - the normal case in a corridor, or when the player walks along a
	# wall - the first wall stayed in the set, was never restored, and stayed dithered
	# after the player had walked away from it.
	_faded.clear()
	for blocker in blockers:
		if blocker != null and not _faded.has(blocker):
			_faded.append(blocker)

	_update_materials(delta)


## The occluder (group root) a ray from the camera to `to` meets first, or null. The
## target's own body is skipped, so a ray that ends inside the player is not stopped by it.
func _first_occluder(space: PhysicsDirectSpaceState3D, to: Vector3) -> Node:
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var own := _facing_actor() as CollisionObject3D
	if own != null:
		query.exclude = [own.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return _find_occluder_root(hit.get("collider") as Node)


## The target's flat facing, normalised, or zero when it reports none (or facing is off).
func _target_facing() -> Vector3:
	var actor := _facing_actor()
	if facing_reach <= 0.0 or actor == null:
		return Vector3.ZERO
	var facing: Variant = actor.call(&"get_facing_direction")
	if not facing is Vector3:
		return Vector3.ZERO
	var flat: Vector3 = facing
	flat.y = 0.0
	if flat.length_squared() <= 0.0001:
		return Vector3.ZERO
	return flat.normalized()


## The node that reports the facing: the target, or the node the target follows through
## its own `target_path` (the camera rig's player). Null when neither reports one.
func _facing_actor() -> Node:
	if _actor_resolved and (_actor == null or is_instance_valid(_actor)):
		return _actor
	_actor_resolved = true
	_actor = null
	if _target.has_method(&"get_facing_direction"):
		_actor = _target
		return _actor
	var followed: Variant = _target.get(&"target_path")
	if followed is NodePath:
		var path: NodePath = followed
		var node: Node = null
		if not path.is_empty():
			node = _target.get_node_or_null(path)
		if node != null and node.has_method(&"get_facing_direction"):
			_actor = node
	return _actor


func _find_occluder_root(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group(occluder_group):
			return current
		current = current.get_parent()
	return null


func _update_materials(delta: float) -> void:
	var step := fade_speed * delta
	for node in _faded:
		for geometry in _collect_geometry(node):
			geometry.transparency = move_toward(geometry.transparency, faded_transparency, step)
			_apply_fade(geometry)
	# Restore everything that is no longer blocking.
	var faded_nodes := get_tree().get_nodes_in_group(occluder_group) if is_inside_tree() else []
	for node in faded_nodes:
		if _faded.has(node):
			continue
		for geometry in _collect_geometry(node):
			if geometry.transparency > 0.0:
				geometry.transparency = move_toward(geometry.transparency, 0.0, step)
				_apply_fade(geometry)
	# Anything freed while swapped (a location swap) is forgotten, not restored.
	for key: Variant in _swapped.keys():
		if not is_instance_valid(key):
			_swapped.erase(key)


## Material-alpha fallback only where instance transparency is not drawn.
## Forward+ must not multiply both opacity paths. At 0 restore exact resources.
func _apply_fade(geometry: GeometryInstance3D) -> void:
	if _uses_instance_fade or geometry.transparency <= 0.0:
		_restore(geometry)
		return
	var alpha := clampf(1.0 - geometry.transparency, 0.0, 1.0)
	if not _swapped.has(geometry):
		_swap(geometry)
	var entry: Dictionary = _swapped.get(geometry, {})
	for copy: Variant in entry.get("copies", []):
		var material := copy as BaseMaterial3D
		if material != null:
			var colour := material.albedo_color
			colour.a = alpha * float(material.get_meta(&"authored_alpha", 1.0))
			material.albedo_color = colour


func _swap(geometry: GeometryInstance3D) -> void:
	var entry := {"override": geometry.material_override, "surfaces": [], "copies": []}
	var copies: Array = entry["copies"]
	if geometry.material_override != null:
		var copy := _faded_copy(geometry.material_override)
		if copy != null:
			geometry.material_override = copy
			copies.append(copy)
	else:
		var mesh := geometry as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var surfaces: Array = entry["surfaces"]
			for index in mesh.get_surface_override_material_count():
				surfaces.append(mesh.get_surface_override_material(index))
				var copy := _faded_copy(mesh.get_active_material(index))
				if copy != null:
					mesh.set_surface_override_material(index, copy)
					copies.append(copy)
	_swapped[geometry] = entry


func _restore(geometry: GeometryInstance3D) -> void:
	if not _swapped.has(geometry):
		return
	var entry: Dictionary = _swapped[geometry]
	_swapped.erase(geometry)
	if not is_instance_valid(geometry):
		return
	geometry.material_override = entry["override"] as Material
	var mesh := geometry as MeshInstance3D
	var surfaces: Array = entry["surfaces"]
	if mesh != null:
		for index in mini(surfaces.size(), mesh.get_surface_override_material_count()):
			mesh.set_surface_override_material(index, surfaces[index] as Material)


## An alpha-blended copy of `material`, or null when it cannot be faded this way (not a
## `BaseMaterial3D`). Depth is left at the default, opaque-only, so the copy writes none.
func _faded_copy(material: Material) -> BaseMaterial3D:
	var base := material as BaseMaterial3D
	if base == null:
		return null
	var copy := base.duplicate() as BaseMaterial3D
	copy.set_meta(&"authored_alpha", base.albedo_color.a)
	if copy.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			or copy.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
			or copy.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if copy.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS:
		copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return copy


## Every piece drawn under `node`, internal children excluded: the outline overlay's key
## twins are internal children of the meshes they copy, and a twin's material is the
## outline's, not the fader's to swap.
func _collect_geometry(node: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	_collect_into(node, result)
	return result


func _collect_into(node: Node, result: Array[GeometryInstance3D]) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		result.append(geometry)
	for child in node.get_children():
		_collect_into(child, result)
