class_name CameraOccluderFader
extends Node3D
## Fades geometry that sits between the camera and the player.
##
## The 2.5D camera is fixed and fairly steep, so a near wall can still cover the
## player when they walk up to it. Anything in the `camera_occluder` group is
## dithered out while it blocks the view and restored afterwards, which keeps
## navigation readable without moving the camera.

@export var target_path: NodePath = ^"../.."
@export var occluder_group: StringName = &"camera_occluder"
@export var faded_transparency: float = 0.82
@export var fade_speed: float = 6.0
## Height on the target the camera should still see.
@export var target_eye_height: float = 1.1

@onready var _camera: Camera3D = get_parent() as Camera3D

var _target: Node3D = null
var _faded: Array[Node] = []


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

	if blocker != null and not _faded.has(blocker):
		_faded.append(blocker)
	elif blocker == null and not _faded.is_empty():
		_faded.clear()

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
	# Restore everything that is no longer blocking.
	var faded_nodes := get_tree().get_nodes_in_group(occluder_group) if is_inside_tree() else []
	for node in faded_nodes:
		if _faded.has(node):
			continue
		for geometry in _collect_geometry(node):
			if geometry.transparency > 0.0:
				geometry.transparency = move_toward(geometry.transparency, 0.0, step)


func _collect_geometry(node: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var self_geometry := node as GeometryInstance3D
	if self_geometry != null:
		result.append(self_geometry)
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		var geometry := child as GeometryInstance3D
		if geometry != null:
			result.append(geometry)
	return result
