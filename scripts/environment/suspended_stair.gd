class_name SuspendedStair
extends Node3D
## The staircase that is in the classroom once the rear door has been opened.
##
## It comes down out of the ceiling plane, crosses the room over the front of the
## teacher's lectern and stops in the air, two metres up. Nothing holds it: no posts, no
## wall fixings, no landing. It is not walkable and has no collision - it is something to
## see, not a route (the art bible's "impossible rear door"; its traversal is a later
## decision).
##
## The scene is authored complete and hidden. `reveal()` shows it once: the stringers
## run out of the ceiling and the treads arrive one after another, top first, each from a
## few centimetres above its place. It is the same node every time, so revealing it again
## - another opening of the door, a reload - can never make a second staircase.
##
## **It gets out of the way.** The staircase hangs between one and three metres up, where
## the steep game camera looks down through it at the floor in front of the board. It has
## no collider (classroom decoration never has one), so the camera's occluder fader cannot
## see it; instead it watches the camera rig's target itself, and while any of the body's
## sample points (shins, waist, eye line) is behind one of its pieces it thins to
## `see_through_alpha`. The thinned look is a set of alpha-blended copies of its own
## materials, made once, because the Compatibility renderer the captures use ignores
## `GeometryInstance3D.transparency`.

## Emitted once, when an animated reveal has finished (or straight away if not animated).
signal revealed

## Seconds between one tread arriving and the next.
@export var tread_interval: float = 0.11
## How far above its place each tread starts.
@export var tread_drop: float = 0.12
## Seconds the stringers take to run out of the ceiling.
@export var stringer_seconds: float = 1.1

## Opacity while it would hide the player.
@export_range(0.0, 1.0, 0.01) var see_through_alpha: float = 0.25
@export var fade_speed: float = 6.0
## Heights on the watched body that should stay visible.
@export var watched_heights: PackedFloat32Array = [0.3, 0.9, 1.5]

var _revealed := false
var _tween: Tween = null
## 1 = fully drawn, `see_through_alpha` = thinned.
var _opacity := 1.0
## Each piece's authored material, and the alpha copy drawn while thinned.
var _pieces: Array[MeshInstance3D] = []
var _copies: Dictionary = {}


func _ready() -> void:
	if not _revealed:
		visible = false
	for node in find_children("*", "MeshInstance3D", true, false):
		_pieces.append(node as MeshInstance3D)


func _physics_process(delta: float) -> void:
	if not visible:
		return
	var goal := see_through_alpha if is_hiding(_watched()) else 1.0
	var next := move_toward(_opacity, goal, fade_speed * delta)
	if not is_equal_approx(next, _opacity):
		_set_opacity(next)


## True while a sample point on `body` is behind one of the staircase's pieces, seen from
## the current camera. False for a hidden staircase or a missing body or camera.
func is_hiding(body: Node3D) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if body == null or camera == null or not visible:
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


## Every visible piece of the staircase (treads, nosings, stringers).
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


func is_revealed() -> bool:
	return _revealed


## Every tread, top first.
func get_treads() -> Array[Node3D]:
	var treads: Array[Node3D] = []
	var holder := get_node_or_null(^"Treads")
	if holder == null:
		return treads
	for child in holder.get_children():
		if child is Node3D:
			treads.append(child as Node3D)
	return treads


func reveal(animated: bool = true) -> void:
	if _revealed:
		if _tween != null and _tween.is_valid():
			await _tween.finished
		return
	_revealed = true
	visible = true
	if not animated or not is_inside_tree():
		revealed.emit()
		return
	var stringers := get_node_or_null(^"Stringers") as Node3D
	var treads := get_treads()
	var rest: Dictionary = {}
	for tread in treads:
		rest[tread] = tread.position
		tread.position.y += tread_drop
		tread.visible = false
	_tween = create_tween()
	_tween.set_parallel(true)
	if stringers != null:
		stringers.scale = Vector3(1.0, 1.0, 0.02)
		_tween.tween_property(stringers, "scale:z", 1.0, stringer_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var delay := 0.25
	for tread in treads:
		_tween.tween_callback(tread.show).set_delay(delay)
		_tween.tween_property(tread, "position", rest[tread], 0.22) \
			.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		delay += tread_interval
	await _tween.finished
	revealed.emit()
