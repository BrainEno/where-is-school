extends Node3D
## Classroom-only presentation. The shared imported desk and wrapper stay untouched.
## Replace (do not cover) the photographic PBR surface: an alpha wash leaves its
## normal/ORM maps and specular response underneath. No geometry or physics is edited.

const DESK_SURFACE: Material = preload("res://assets/materials/classroom/student_wood.tres")
const DESKS: Array[NodePath] = [
	^"../Furniture/DeskA1/Desk",
	^"../Furniture/DeskA2/Desk",
	^"../Furniture/DeskA3/Desk",
	^"../Furniture/DeskB1/Desk",
	^"../Furniture/DeskB2/Desk",
	^"../Furniture/DeskB3/Desk",
]


func _ready() -> void:
	for path in DESKS:
		var desk := get_node_or_null(path)
		if desk == null:
			push_error("ClassroomPresentation: missing desk at '%s'." % path)
			continue
		var meshes := desk.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			push_error("ClassroomPresentation: '%s' has no imported mesh to style." % path)
		for node in meshes:
			var mesh := node as MeshInstance3D
			mesh.material_override = DESK_SURFACE
			# Remove the wash, not just its opacity. The imported hard-normal mesh
			# cannot grow a clean inverted hull; leave its silhouette to geometry.
			mesh.material_overlay = null
