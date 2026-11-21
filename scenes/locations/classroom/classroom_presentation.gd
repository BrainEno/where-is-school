extends Node3D
## Classroom-only presentation: desk finish, the imagined teacher's wall mark and her
## imagined lesson (`ImaginedLesson`), and the draft on the timetable. The shared desks and the room's physics stay unchanged.

const PAPER_CYCLE := 11.7
const PAPER_MAX_TILT := deg_to_rad(4.0)
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
@onready var _imagined := get_node_or_null(^"../ImaginedLesson") as ImaginedLesson
@onready var _paper: MeshInstance3D = $"../TimetableSheet"
@onready var _clip: MeshInstance3D = $"../TimetableClip"
@onready var _paper_rest := _paper.transform
@onready var _paper_pin := _paper_rest.affine_inverse() * _clip.position

var _paper_phase := PAPER_CYCLE - 1.2
var _paper_tilt := 0.0


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


func _process(delta: float) -> void:
	if not _paper.is_visible_in_tree():
		return
	# A quick lift, a quieter echo and a long rest. Tilt into the room only, around
	# the clip, so the print and its outline stay on the sheet instead of sliding.
	_paper_phase = fposmod(_paper_phase + delta, PAPER_CYCLE)
	var lift := sin(PI * clampf(_paper_phase / 1.45, 0.0, 1.0))
	var echo := sin(PI * clampf((_paper_phase - 1.2) / 1.05, 0.0, 1.0))
	var tilt := PAPER_MAX_TILT * (lift * lift + 0.32 * echo * echo)
	if is_equal_approx(_paper_tilt, tilt):
		return
	_paper_tilt = tilt
	var basis := _paper_rest.basis * Basis(Vector3.RIGHT, _paper_tilt)
	_paper.transform = Transform3D(basis, _clip.position - basis * _paper_pin)


## The painted figure on the wall and the imagined lesson (B in the aisle, her
## after-images, the repainted room) follow the imagined exchange together. The floor's
## set-square mark remains scenery.
func set_b_impression_visible(show_impression: bool) -> void:
	if _b_impression != null:
		_b_impression.visible = show_impression
	if _imagined != null:
		_imagined.set_active(show_impression)
