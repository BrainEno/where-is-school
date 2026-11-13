class_name WindowCurtain
extends Node3D
## One classroom window's curtain: the owner's `classroom_window_curtains.glb`, drawn in
## the classroom's own materials, that can really be drawn aside.
##
## The model ships in its closed pose and with no animation, so the opening is done here,
## on the model's own parts, and is driven by one number (`set_open_amount`, 0 = closed,
## 1 = drawn aside). Each panel and its hem are moved under a pivot on the panel's outer
## edge, and opening squeezes the pivot toward that edge - the fabric gathers at the
## sides the way a curtain on rings does - while the rings slide along the rail with it and
## the tiebacks come into view. Driving everything from one value keeps the open state
## exact and testable: a curtain loaded open (a save, or the window that was never closed)
## is in the same pose the animation ends in.
##
## The model's materials are replaced at load by the classroom's (`assets/materials/
## classroom/`): the room has one colour system and `classroom_visual_slice_test.gd` holds
## every surface in it to that.

## Emitted when an animated opening has finished.
signal opened

## Fraction of a panel's width that is left once it is drawn aside.
const GATHERED_WIDTH := 0.24
## How much deeper the gathered fabric is than the flat panel.
const GATHERED_DEPTH := 1.6
## The panels' outer edges in the model, metres (the model is symmetric about x = 0).
const OUTER_EDGE := 0.884
## The outermost ring sits this far in from the outer edge.
const RING_MARGIN := 0.064

## Loaded drawn aside (the ordinary window) or closed (the window that hides something).
@export var start_open: bool = false
## Seconds an animated opening takes.
@export var open_seconds: float = 1.6
## Path to the instanced model.
@export var model_path: NodePath = ^"Model"
@export var left_fabric: Material
@export var right_fabric: Material
@export var trim_material: Material
@export var rail_material: Material
@export var finial_material: Material
@export var ring_material: Material

var _open_amount := 0.0
var _left_pivot: Node3D = null
var _right_pivot: Node3D = null
## Ring -> [its node's closed x, its centre's closed x], both in the model's space.
var _rings: Dictionary = {}
var _tiebacks: Array[Node3D] = []
var _tween: Tween = null
var _built := false


func _ready() -> void:
	_build()
	set_open_amount(1.0 if start_open else 0.0)


## True once the curtain is fully drawn aside.
func is_open() -> bool:
	return _open_amount >= 0.999


func get_open_amount() -> float:
	return _open_amount


## Draws the curtain aside. Animated by default; awaiting it waits for the end. Calling it
## on an open curtain does nothing, so a replayed state change cannot jerk it shut and
## open again.
func open(animated: bool = true) -> void:
	_build()
	if is_open():
		return
	if _tween != null and _tween.is_valid():
		await _tween.finished
		return
	if not animated or not is_inside_tree():
		set_open_amount(1.0)
		opened.emit()
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(set_open_amount, _open_amount, 1.0, open_seconds)
	await _tween.finished
	opened.emit()


## Puts every moving part where `amount` says (0 closed, 1 drawn aside).
func set_open_amount(amount: float) -> void:
	_build()
	_open_amount = clampf(amount, 0.0, 1.0)
	var width := lerpf(1.0, GATHERED_WIDTH, _open_amount)
	var depth := lerpf(1.0, GATHERED_DEPTH, _open_amount)
	for pivot in [_left_pivot, _right_pivot]:
		if pivot != null:
			(pivot as Node3D).scale = Vector3(width, 1.0, depth)
	for ring: Node3D in _rings:
		if not is_instance_valid(ring):
			continue
		var closed: Array = _rings[ring]
		var node_x: float = closed[0]
		var centre_x: float = closed[1]
		var edge := -OUTER_EDGE if centre_x < 0.0 else OUTER_EDGE
		var anchor := edge + (RING_MARGIN if centre_x < 0.0 else -RING_MARGIN)
		var target := anchor + (centre_x - anchor) * width
		ring.position.x = node_x + (target - centre_x)
	for tieback in _tiebacks:
		if is_instance_valid(tieback):
			tieback.visible = _open_amount > 0.5


## The meshes a player sees as "the curtain" (panels, hems, rail): what an interactable
## outlines.
func get_fabric_meshes() -> Array[MeshInstance3D]:
	_build()
	var meshes: Array[MeshInstance3D] = []
	for pivot in [_left_pivot, _right_pivot]:
		if pivot == null:
			continue
		for child in (pivot as Node3D).get_children():
			if child is MeshInstance3D:
				meshes.append(child as MeshInstance3D)
	return meshes


## World-space box the drawn fabric covers right now.
func get_fabric_aabb() -> AABB:
	var result := AABB()
	var first := true
	for mesh in get_fabric_meshes():
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _build() -> void:
	if _built:
		return
	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		push_error("WindowCurtain '%s': model_path '%s' does not resolve." % [name, model_path])
		return
	_built = true
	_left_pivot = _make_pivot(model, &"LeftGather", -OUTER_EDGE)
	_right_pivot = _make_pivot(model, &"RightGather", OUTER_EDGE)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.name)
		if part.begins_with("Curtain_left_panel"):
			_dress(mesh, left_fabric)
			mesh.reparent(_left_pivot, true)
		elif part.begins_with("Curtain_right_panel"):
			_dress(mesh, right_fabric)
			mesh.reparent(_right_pivot, true)
		elif part.begins_with("Curtain_left_hem"):
			_dress(mesh, trim_material)
			mesh.reparent(_left_pivot, true)
		elif part.begins_with("Curtain_right_hem"):
			_dress(mesh, trim_material)
			mesh.reparent(_right_pivot, true)
		elif part.begins_with("Curtain_tieback"):
			_dress(mesh, trim_material)
			_tiebacks.append(mesh)
		elif part.begins_with("Curtain_rail_ring"):
			_dress(mesh, ring_material)
			_rings[mesh] = [mesh.position.x, _centre_x(mesh)]
		elif part.begins_with("Curtain_rail_finial"):
			_dress(mesh, finial_material)
		else:
			# The rail and its two wall brackets.
			_dress(mesh, rail_material)


func _make_pivot(model: Node3D, pivot_name: StringName, edge_x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = Vector3(edge_x, 0.0, 0.0)
	model.add_child(pivot)
	return pivot


## A ring's centre along the rail, in its parent's (the model's) space. Rings are moved
## by their node position, and whether the exporter put the ring's offset in the node or
## in the vertices, moving the node by "target centre - closed centre" is exact.
func _centre_x(mesh: MeshInstance3D) -> float:
	return (mesh.transform * mesh.get_aabb().get_center()).x


func _dress(mesh: MeshInstance3D, material: Material) -> void:
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material != null:
		mesh.material_override = material
