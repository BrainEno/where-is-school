extends Node3D
## Classroom-only presentation: desk finish and the imagined teacher's wall mark.
## Replace (do not cover) the photographic PBR surface: an alpha wash leaves its
## normal/ORM maps and specular response underneath. The shared desk and wrapper
## stay untouched. No geometry or physics is edited.

const DESK_SURFACE: Material = preload("res://assets/materials/classroom/student_wood.tres")
const DESKS: Array[NodePath] = [
	^"../Furniture/DeskA1/Desk",
	^"../Furniture/DeskA2/Desk",
	^"../Furniture/DeskA3/Desk",
	^"../Furniture/DeskA4/Desk",
	^"../Furniture/DeskB1/Desk",
	^"../Furniture/DeskB2/Desk",
	^"../Furniture/DeskB3/Desk",
	^"../Furniture/DeskB4/Desk",
	^"../Furniture/DeskC1/Desk",
	^"../Furniture/DeskC2/Desk",
	^"../Furniture/DeskC3/Desk",
	^"../Furniture/DeskC4/Desk",
]

@onready var _b_impression := get_node_or_null(^"../WallNorth/InkShadowFigure") as MeshInstance3D


func _ready() -> void:
	# The room is drawn before anyone has imagined the teacher, even on a revisit.
	set_b_impression_visible(false)
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


## Only this painted figure changes. The floor's set-square mark remains scenery.
func set_b_impression_visible(show_impression: bool) -> void:
	if _b_impression != null:
		_b_impression.visible = show_impression
