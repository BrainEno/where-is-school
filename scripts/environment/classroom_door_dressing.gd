class_name ClassroomDoorDressing
extends Node3D
## Both sides of the biology classroom's two doors use the owner's
## `classroom_door_assembly.glb` and the same classroom materials.
##
## The corridor shows the imported -Z face with its hinge barrels. The classroom
## shows the +Z face with matching fittings on the same latch edge. The painted
## glass is opaque; the wall and interactables own collision and passage.

@export var model_path: NodePath = ^"Model"
@export var leaf_material: Material
@export var frame_material: Material
@export var hardware_material: Material
@export var shadow_material: Material
@export var glazing_material: Material
@export var dress_reverse: bool = true

var _dressed := false


func _ready() -> void:
	dress()


## Replaces every model material. Idempotent; public so a test can call it on a scene
## that is not in the tree.
func dress() -> void:
	if _dressed:
		return
	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		push_error("ClassroomDoorDressing '%s': model_path '%s' does not resolve." % [name, model_path])
		return
	_dressed = true
	var reverse := get_node_or_null(^"Reverse") as Node3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.name)
		var material := shadow_material
		if part.begins_with("Door_wear_mark"):
			# The classroom doors are unmarked; keep even the hidden meshes in the palette.
			mesh.visible = false
		elif part == "Door_vision_glass":
			material = glazing_material
		elif part.begins_with("Door_frame") or part.begins_with("Door_vision"):
			material = frame_material
		elif _is_painted_leaf(part):
			material = leaf_material
		elif (
			part.begins_with("Door_handle")
			or part.begins_with("Door_hinge_barrel")
			or part == "Door_kick_plate"
		):
			material = hardware_material
		mesh.material_override = material
		if dress_reverse and reverse != null and _is_face_fitting(part):
			_add_reverse_fitting(reverse, mesh)


func _add_reverse_fitting(reverse: Node3D, front: MeshInstance3D) -> void:
	# Turn the fitting in place and keep its X (latch/hinge side). Turning the whole
	# assembly about its centre would put the two handles on different edges.
	var fitting := MeshInstance3D.new()
	fitting.name = front.name
	fitting.mesh = front.mesh
	fitting.material_override = front.material_override
	fitting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fitting.transform = Transform3D(
		Basis(Vector3.UP, PI) * front.basis,
		Vector3(front.position.x, front.position.y, -front.position.z)
	)
	reverse.add_child(fitting)


static func _is_painted_leaf(part: String) -> bool:
	return part == "Door_leaf" or part.begins_with("Door_panel_inset")


static func _is_face_fitting(part: String) -> bool:
	return (
		part.begins_with("Door_panel")
		or part.begins_with("Door_vision")
		or part.begins_with("Door_handle")
		or part == "Door_lock_escutcheon"
		or part == "Door_kick_plate"
	)


## The painted parts of the leaf, excluding the separate glass, gasket and fittings.
func get_leaf_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in find_children("Door_*", "MeshInstance3D", true, false):
		if _is_painted_leaf(String(node.name)):
			meshes.append(node as MeshInstance3D)
	return meshes
