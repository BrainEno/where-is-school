extends Node3D
class_name NpcActor
## A minimal 3D stand-in for a speaking character: a body, a head, and an
## optional seated pose. No facial animation, no skeletal rig, no lip sync — the
## art bible puts portraiture in the dialogue UI, not on the model.

enum Pose { STANDING, SEATED, LEANING }

@export var display_name: String = "NPC"
@export var pose: Pose = Pose.SEATED
@export var shirt_material: Material
@export var hair_material: Material
@export var skin_material: Material
@export var seated_offset: float = 0.0

@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/Body
@onready var head_mesh: MeshInstance3D = $VisualRoot/Head
@onready var shoulders: MeshInstance3D = $VisualRoot/Shoulders
@onready var hair_mesh: MeshInstance3D = $VisualRoot/Hair


func _ready() -> void:
	_apply_materials()
	_apply_pose()


func _apply_materials() -> void:
	if shirt_material != null and body_mesh != null:
		body_mesh.material_override = shirt_material
	if shirt_material != null and shoulders != null:
		shoulders.material_override = shirt_material
	if skin_material != null and head_mesh != null:
		head_mesh.material_override = skin_material
	if hair_material != null and hair_mesh != null:
		hair_mesh.material_override = hair_material


func _apply_pose() -> void:
	match pose:
		Pose.SEATED:
			visual_root.position.y = -0.36 + seated_offset
			visual_root.rotation.x = -0.04
		Pose.LEANING:
			visual_root.position.y = -0.1
			visual_root.rotation.x = 0.16
		_:
			visual_root.position.y = seated_offset
			visual_root.rotation.x = 0.0


func face_point(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) < 0.05:
		return
	look_at(flat, Vector3.UP)


func set_visible_actor(value: bool) -> void:
	visible = value
