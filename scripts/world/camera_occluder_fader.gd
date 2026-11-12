class_name CameraOccluderFader
extends Node3D
## Fades geometry that sits between the camera and the player.
##
## The 2.5D camera is fixed and fairly steep, so a near wall can still cover the
## player when they walk up to it. Anything in the `camera_occluder` group is
## dithered out while it blocks the view and restored afterwards, which keeps
## navigation readable without moving the camera.
##
## **How the fade is drawn (issue #115).** `GeometryInstance3D.transparency` is what is
## animated, but on its own it draws nothing in this project: the Godot documentation says
## it is only supported by the Forward+ renderer and is ignored (treated as 0.0) by Mobile
## and Compatibility, and the game ships on Compatibility. A real frame confirmed it: the
## classroom's south wall at transparency 0.82 was drawn fully opaque, and the timetable
## behind it was invisible. So while a piece is faded, its materials are swapped for
## alpha-blended copies whose albedo alpha follows the same value (`_apply_fade`), and the
## authored materials are put back exactly when it is restored. An alpha-blended material
## is drawn in the transparent pass and writes no depth, so what is behind the wall shows in
## the frame and in the outline's depth mask alike, and `InteractionController` counts the
## wall as see-through for the same reason. Only `StandardMaterial3D`/`ORMMaterial3D` can be
## copied this way; a piece drawn with a `ShaderMaterial` (or nothing) stays opaque, and is
## counted as opaque. `material_overlay` is never touched.

@export var target_path: NodePath = ^"../.."
@export var occluder_group: StringName = &"camera_occluder"
@export var faded_transparency: float = 0.82
@export var fade_speed: float = 6.0
## Height on the target the camera should still see.
@export var target_eye_height: float = 1.1

@onready var _camera: Camera3D = get_parent() as Camera3D

var _target: Node3D = null
var _faded: Array[Node] = []
## Geometry -> {"override": its authored material_override, "surfaces": its authored
## surface override materials, "copies": the alpha-blended copies drawn instead}, for
## every piece whose materials are currently swapped.
var _swapped: Dictionary = {}


func _ready() -> void:
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
	var to := _target.global_position + Vector3(0.0, target_eye_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)

	var blocker: Node = null
	if not hit.is_empty():
		blocker = _find_occluder_root(hit.get("collider") as Node)

	# Rebuild the set every frame instead of appending to it. There is one ray, so
	# there is at most one blocker, and "what blocks the view now" is the whole
	# truth. Appending made the set a history: when the blocker changed from one wall
	# to another with no unobstructed frame in between - the normal case in a
	# corridor, or when the player walks along a wall - the first wall stayed in the
	# set, was never restored, and stayed dithered after the player had walked away
	# from it.
	_faded.clear()
	if blocker != null:
		_faded.append(blocker)

	_update_materials(delta)


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


## Draws `geometry.transparency` with materials, so the fade shows on every renderer.
## At 0 the authored materials are back, exactly as they were.
func _apply_fade(geometry: GeometryInstance3D) -> void:
	var alpha := clampf(1.0 - geometry.transparency, 0.0, 1.0)
	if geometry.transparency <= 0.0:
		_restore(geometry)
		return
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
