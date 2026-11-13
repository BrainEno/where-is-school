class_name SwingDoor
extends Node3D
## A hinge for a door leaf that is already in the room.
##
## The classroom's blackboard wall has a second, framed doorway with its own leaf
## (`WallNorth/RearDoorAnomalyMount`: `DoorLeaf` and `AnomalyDoorInlay`). The leaf is
## authored shut and has no pivot of its own, so it cannot swing as it comes. A
## SwingDoor placed on the leaf's hinge edge adopts the leaf meshes at load - they move
## under this node keeping their world transforms, so the shut door looks exactly as
## authored - and the door opens by turning this node about its own Y axis.
##
## Nothing about the leaf is changed but its parent: its meshes, materials and size are
## the room's. The leaf never gets collision (the opening behind it already has none).

## Emitted when an animated swing has finished, with the new state.
signal swung(is_open: bool)

## The meshes that make up the leaf, relative to this node.
@export var leaf_paths: Array[NodePath] = []
## Degrees the leaf turns when open. Positive turns about +Y, which swings a leaf that
## extends towards this node's -X into the room's +Z (the classroom side of WallNorth).
@export var open_degrees: float = 80.0
@export var swing_seconds: float = 0.9

var _open := false
var _tween: Tween = null
var _built := false
var _leaves: Array[Node3D] = []


func _ready() -> void:
	_build()


func is_open() -> bool:
	return _open


## Current leaf angle in degrees (0 = shut).
func get_angle() -> float:
	return rotation_degrees.y


## The pivot the leaf turns on (this node; kept as a method for callers and tests).
func get_hinge() -> Node3D:
	_build()
	return self


## The leaf meshes this hinge carries.
func get_leaves() -> Array[Node3D]:
	_build()
	return _leaves


func open(animated: bool = true) -> void:
	await _swing_to(true, animated)


func close(animated: bool = true) -> void:
	await _swing_to(false, animated)


func _swing_to(want_open: bool, animated: bool) -> void:
	_build()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_open = want_open
	var target := open_degrees if want_open else 0.0
	if not animated or not is_inside_tree():
		rotation_degrees.y = target
		swung.emit(_open)
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if want_open else Tween.EASE_IN_OUT)
	_tween.tween_property(self, "rotation_degrees:y", target, swing_seconds)
	await _tween.finished
	swung.emit(_open)


func _build() -> void:
	if _built or not is_inside_tree():
		return
	_built = true
	for path in leaf_paths:
		var leaf := get_node_or_null(path) as Node3D
		if leaf == null:
			push_error("SwingDoor '%s': leaf path '%s' does not resolve." % [name, path])
			continue
		_leaves.append(leaf)
	# Deferred: the leaf's parent may still be setting up its children this frame.
	_adopt.call_deferred()


func _adopt() -> void:
	# Move the leaves under the hinge in its shut pose, so they keep their authored shut
	# transforms; then put back any angle a restored story state already asked for.
	var angle := rotation_degrees.y
	rotation_degrees.y = 0.0
	for leaf in _leaves:
		if is_instance_valid(leaf) and leaf.get_parent() != self:
			leaf.reparent(self, true)
	rotation_degrees.y = angle
