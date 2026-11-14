class_name ClassroomDoorDressing
extends Node3D
## One of the biology classroom's two doors (issue #159): the owner's
## `classroom_door_assembly.glb` - frame, leaf, panels, hinges, lever handle - drawn in
## the classroom's own materials.
##
## Both doors are the same model, so they share one design language; only the leaf
## colour tells them apart (the front door grey, the rear door white). The model's own
## blue paint and wood are replaced at load (`assets/materials/classroom/`): the room has
## one colour system and `classroom_visual_slice_test.gd` holds every surface to it. The
## two small wear marks the model carries are hidden - the brief asks for doors with no
## marks on them - and the vision panel is painted as part of the leaf, because the
## doors do not open onto anything the room shows.
##
## The model faces -Z (its handle side). Nothing here collides: the wall's collision is
## whole across both openings, so neither door changes where anyone can walk.

@export var model_path: NodePath = ^"Model"
@export var leaf_material: Material
@export var frame_material: Material
@export var hardware_material: Material
@export var shadow_material: Material

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
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := String(mesh.name)
		var material: Material = hardware_material
		if part.begins_with("Door_wear_mark"):
			# Hidden, but still given a classroom material: the camera fader and the wall
			# contract treat every mesh under a wall alike, drawn or not.
			mesh.visible = false
		elif part.begins_with("Door_frame"):
			material = frame_material
		elif part.begins_with("Door_panel_shadow"):
			material = shadow_material
		elif (
			part.begins_with("Door_leaf")
			or part.begins_with("Door_panel_inset")
			or part.begins_with("Door_vision")
		):
			material = leaf_material
		mesh.material_override = material


## The leaf meshes (leaf, inset panels, vision panel), in the leaf's colour; the panel
## shadow lines are not part of it.
func get_leaf_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var model := get_node_or_null(model_path) as Node3D
	if model == null:
		return meshes
	for node in model.find_children("Door_*", "MeshInstance3D", true, false):
		var part := String(node.name)
		if (
			part.begins_with("Door_leaf")
			or part.begins_with("Door_panel_inset")
			or part.begins_with("Door_vision")
		):
			meshes.append(node as MeshInstance3D)
	return meshes
