class_name SwingDoor
extends Node3D
## A hinged door built from the owner's `classroom_door_assembly.glb`.
##
## The model is one flat list of parts (frame, leaf, hinges, handle, glass...) under its
## root, with no animation, so the leaf cannot swing as it comes. At load the parts that
## belong to the leaf are moved under a hinge pivot on the leaf's hinge axis, and the door
## opens by turning that pivot. The frame, threshold and hinge barrels stay put.
##
## `leaf_width_scale` narrows the door without touching its height or thickness: the
## rear door of the classroom stands between the west wall and the back board, and the
## stock 1.2 m frame does not fit there. The scale is applied under the hinge, so the
## turning leaf is never sheared.
##
## The model's materials are replaced by the classroom's at load, by the role of each
## part, so the door belongs to the room's colour system like everything else in it.

## Emitted when an animated swing has finished, with the new state.
signal swung(is_open: bool)

## The hinge axis in the model: the leaf's hinge edge, on the room-side face.
const HINGE_X := -0.545
const HINGE_Z := -0.04
## Parts that move with the leaf (name prefixes; the importer may turn "Part.001" into
## "Part_001"). Everything else - the frame, the threshold, the hinge barrels and the scuff
## on the frame (`Door_wear_mark_02`) - stays put.
const LEAF_PARTS: Array[String] = [
	"Door_leaf", "Door_handle", "Door_hinge_leaf", "Door_kick_plate", "Door_lock",
	"Door_panel", "Door_vision", "Door_wear_mark_01",
]

@export var model_path: NodePath = ^"Model"
## Degrees the leaf turns when open. Positive swings the free edge into the room (-Z).
@export var open_degrees: float = 80.0
@export var swing_seconds: float = 0.9
## 1 = the model's own width; smaller narrows frame and leaf alike.
@export var leaf_width_scale: float = 1.0
@export_group("Materials")
@export var frame_material: Material
@export var leaf_material: Material
@export var panel_material: Material
@export var shadow_material: Material
@export var rail_material: Material
@export var metal_material: Material
@export var glass_material: Material

var _hinge: Node3D = null
var _open := false
var _tween: Tween = null
var _built := false


func _ready() -> void:
	_build()


func is_open() -> bool:
	return _open


## Current leaf angle in degrees (0 = shut).
func get_angle() -> float:
	return _hinge.rotation_degrees.y if _hinge != null else 0.0


func get_hinge() -> Node3D:
	_build()
	return _hinge


func open(animated: bool = true) -> void:
	await _swing_to(true, animated)


func close(animated: bool = true) -> void:
	await _swing_to(false, animated)


func _swing_to(want_open: bool, animated: bool) -> void:
	_build()
	if _hinge == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_open = want_open
	var target := open_degrees if want_open else 0.0
	if not animated or not is_inside_tree():
		_hinge.rotation_degrees.y = target
		swung.emit(_open)
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if want_open else Tween.EASE_IN_OUT)
	_tween.tween_property(_hinge, "rotation_degrees:y", target, swing_seconds)
	await _tween.finished
	swung.emit(_open)


func _build() -> void:
	if _built:
		return
	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		push_error("SwingDoor '%s': model_path '%s' does not resolve." % [name, model_path])
		return
	_built = true
	model.scale = Vector3(leaf_width_scale, 1.0, 1.0)
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = model.position + Vector3(HINGE_X * leaf_width_scale, 0.0, HINGE_Z)
	add_child(_hinge)
	# The leaf's parts move under the hinge keeping their world transforms (the model's
	# width scale included), so the shut door looks exactly like the model and the hinge
	# turning is the only thing that moves them.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.name)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dress(mesh, part)
		if _is_leaf_part(part):
			mesh.reparent(_hinge, true)


func _is_leaf_part(part: String) -> bool:
	for prefix in LEAF_PARTS:
		if part.begins_with(prefix):
			return true
	return false


func _dress(mesh: MeshInstance3D, part: String) -> void:
	var material: Material = metal_material
	if part.begins_with("Door_frame"):
		material = frame_material
	elif part == "Door_leaf":
		material = leaf_material
	elif part.begins_with("Door_panel_inset"):
		material = panel_material
	elif part.begins_with("Door_panel_shadow") or part.begins_with("Door_wear_mark"):
		material = shadow_material
	elif part.begins_with("Door_vision_glass_rail") or part.begins_with("Door_vision_glass_stile"):
		material = rail_material
	elif part.begins_with("Door_vision_glass"):
		material = glass_material
	if material != null:
		mesh.material_override = material
