class_name SeeThroughProp
extends Node3D
## A ceiling-hung prop that thins out while it would hide the player (issue #159).
##
## The biology classroom's projector hangs under the ceiling in the middle of the room,
## where the steep game camera looks down past it at the floor. Classroom decoration has
## no collider (`classroom_visual_slice_test.gd` keeps the room's solids a closed list),
## so the camera's occluder fader cannot see it. Instead it watches the camera rig's
## target itself - the same rule the suspended staircase uses - and while any of the
## body's sample points (shins, waist, eye line) is behind one of its pieces it fades to
## `see_through_alpha`, then comes back to exactly its authored materials.
##
## The thinned look is a set of alpha-blended copies of its own materials, made once,
## because the Compatibility renderer the captures use ignores
## `GeometryInstance3D.transparency`.

## Opacity while it would hide the player.
@export_range(0.0, 1.0, 0.01) var see_through_alpha: float = 0.25
@export var fade_speed: float = 6.0
## Heights on the watched body that should stay visible.
@export var watched_heights: PackedFloat32Array = [0.3, 0.9, 1.5]

## 1 = fully drawn, `see_through_alpha` = thinned.
var _opacity := 1.0
var _pieces: Array[MeshInstance3D] = []
## Piece -> {"authored": its own material, "copy": the alpha copy drawn while thinned}.
var _copies: Dictionary = {}


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		_pieces.append(node as MeshInstance3D)


func _physics_process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var goal := see_through_alpha if is_hiding(_watched()) else 1.0
	var next := move_toward(_opacity, goal, fade_speed * delta)
	if not is_equal_approx(next, _opacity):
		_set_opacity(next)


## True while a sample point on `body` is behind one of the pieces, seen from the current
## camera. False for a hidden prop or a missing body or camera.
func is_hiding(body: Node3D) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if body == null or camera == null or not is_visible_in_tree():
		return false
	var eye := camera.global_position
	for piece in _pieces:
		if piece.mesh == null:
			continue
		var box := piece.global_transform * piece.mesh.get_aabb()
		for height in watched_heights:
			if box.intersects_segment(eye, body.global_position + Vector3(0.0, height, 0.0)):
				return true
	return false


func get_opacity() -> float:
	return _opacity


func get_pieces() -> Array[MeshInstance3D]:
	return _pieces


func _watched() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	var node: Node = camera
	while node != null:
		if node is CameraRig:
			return (node as CameraRig).get_target()
		node = node.get_parent()
	return null


func _set_opacity(opacity: float) -> void:
	_opacity = opacity
	var thinned := opacity < 0.999
	for piece in _pieces:
		if not thinned:
			if _copies.has(piece):
				piece.material_override = _copies[piece]["authored"]
			continue
		if not _copies.has(piece):
			var authored := piece.material_override
			var copy: BaseMaterial3D = null
			if authored is BaseMaterial3D:
				copy = (authored as BaseMaterial3D).duplicate() as BaseMaterial3D
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				# An ink outline around a see-through piece would still hide the body.
				copy.next_pass = null
			_copies[piece] = {"authored": authored, "copy": copy}
		var copy_material: BaseMaterial3D = _copies[piece]["copy"]
		if copy_material == null:
			continue
		copy_material.albedo_color.a = opacity
		piece.material_override = copy_material
