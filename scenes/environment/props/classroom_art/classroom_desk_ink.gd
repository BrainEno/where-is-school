extends Node3D
## Lays the classroom's wash and ink over the imported student desk.
##
## The desk is a photographed model (Poly Haven, see docs/ASSET_PROVENANCE.md) and the
## room around it is painted, so on its own it reads as a photograph pasted into a
## drawing. Rather than edit the model or its wrapper, this puts one overlay on the
## desk's meshes: a thin unshaded wash of the room's honey colour, followed by the same
## ink outline every piece of classroom furniture carries. The model, its collider and
## its bounds are untouched - an overlay adds no geometry - so everything that measures
## the desk measures the same desk.

const DESK_OVERLAY: Material = preload("res://assets/materials/classroom/desk_wash.tres")

## The node the overlay is laid over (the imported desk wrapper).
@export var desk_path: NodePath = ^"Desk"


func _ready() -> void:
	var desk := get_node_or_null(desk_path)
	if desk == null:
		return
	for node in desk.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null and geometry.material_overlay == null:
			geometry.material_overlay = DESK_OVERLAY
