extends Node3D
class_name InteractionSensor
## Picks the interactable the player is most plausibly attending to.
##
## Selection is deliberately simple and predictable: everything inside a forward
## cone within [member reach] is scored by alignment with the camera's forward
## direction, with [member Interactable3D.focus_priority] breaking ties. There is
## no line-of-sight raycast, because a classroom with desks should not require
## the player to thread a crosshair between chair legs.

signal target_changed(target: Interactable3D)

@export_range(1.0, 8.0, 0.1) var reach: float = 2.6
@export_range(10.0, 180.0, 1.0) var cone_degrees: float = 100.0
## Vertical tolerance, so a chest-height bag can still be targeted.
@export_range(0.2, 3.0, 0.1) var vertical_tolerance: float = 1.6
@export var enabled: bool = true

var _current: Interactable3D


func _physics_process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if not enabled:
		_set_current(null)
		return
	var next_target: Interactable3D = _find_best_target()
	_set_current(next_target)


func current_target() -> Interactable3D:
	return _current


func _find_best_target() -> Interactable3D:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return null
	forward = forward.normalized()
	var half_cone: float = cos(deg_to_rad(cone_degrees * 0.5))

	var best: Interactable3D = null
	var best_score: float = -INF
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var candidate := node as Interactable3D
		if candidate == null or not candidate.is_enabled():
			continue
		var offset: Vector3 = candidate.global_position - global_position
		var vertical: float = absf(offset.y)
		if vertical > vertical_tolerance:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach:
			continue
		var alignment: float = 1.0
		if distance > 0.01:
			alignment = forward.dot(offset / distance)
			if alignment < half_cone:
				continue
		else:
			alignment = 1.0
		var score: float = float(candidate.focus_priority) * 10.0 + alignment * 2.0 - distance * 0.05
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _set_current(target: Interactable3D) -> void:
	if _current == target:
		return
	_current = target
	target_changed.emit(target)
