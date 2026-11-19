extends Node3D
## Review stage only. It uses the room's actual light and materials, but no actor,
## interactable, save data or opening director. F6 runs this scene, not the prologue.

const CLASSROOM := preload("res://scenes/locations/classroom/classroom.tscn")
const POSE_DATA := "res://scenes/dev/teacher_b/review_poses.json"
const MARK := Vector3(-1.52, 0.123, -3.46)
const SHOTS := ["body", "face", "back", "demonstrate", "stride", "game"]
const TITLES := ["全身", "脸部", "背面", "屈肘与手指", "迈步", "游戏镜头"]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

@onready var teacher: Node3D = $TeacherB
@onready var lead: CharacterVisualAnimation = $Protagonist
@onready var look: CharacterLookApplier = $TeacherB/Look
@onready var camera: Camera3D = $InspectionCamera
@onready var game_camera: Camera3D = $GameCameraRig/Camera3D
@onready var label: Label = $Help/Label

var skeleton: Skeleton3D
var poses: Dictionary
var shot := "body"
var is_lead := false
var turn := 0.0


func _ready() -> void:
	var room := CLASSROOM.instantiate()
	for name_to_remove: String in ["Actors", "Interactables", "Navigation", "Ambience", "ScreenControl", "ChairControl"]:
		var node := room.get_node_or_null(NodePath(name_to_remove))
		if node != null:
			node.free()
	add_child(room)
	$CameraMark.position = MARK
	var rigs := CharacterAnimation.skeletons_in(teacher)
	if rigs.size() != 1:
		push_error("Teacher B review needs exactly one imported Skeleton3D.")
		return
	skeleton = rigs[0]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POSE_DATA))
	if not parsed is Dictionary:
		push_error("Teacher B review could not read its pose data.")
		return
	poses = parsed
	show_shot("body")


func apply_pose(pose: String) -> bool:
	if skeleton == null or not poses.has(pose):
		return false
	skeleton.reset_bone_poses()
	var keys: Dictionary = poses[pose]
	for bone_name: String in keys:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			push_error("Teacher B review pose '%s': no '%s' bone." % [pose, bone_name])
			return false
		# X, then Y, then Z about the GLB's bind axes. Convert them to this
		# joint's local rest basis, not the currently posed parent's axes.
		var inverse := skeleton.get_bone_global_rest(bone).basis.inverse()
		var offset := Quaternion.IDENTITY
		for i in 3:
			var axis: Vector3 = inverse * AXES[i]
			offset = Quaternion(axis.normalized(), deg_to_rad(float(keys[bone_name][i]))) * offset
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * offset)
	skeleton.force_update_all_bone_transforms()
	return true


func show_shot(next_shot: String, show_lead: bool = false) -> void:
	if not SHOTS.has(next_shot):
		return
	shot = next_shot
	# The two comparison figures never stand in each other's shadow. Both
	# are photographed on the same marks, using the same camera and light.
	is_lead = show_lead and shot in ["body", "face", "game"]
	teacher.visible = not is_lead
	lead.visible = is_lead
	lead.get_animation_player().pause()
	lead.get_skeleton().reset_bone_poses()
	var lead_look := lead.get_node("Look") as CharacterLookApplier
	lead_look.blinking = false
	teacher.position = MARK
	lead.position = MARK
	# Their native front axes differ; the meshes themselves are not turned or resized.
	var angle := -.28 if shot != "back" else PI + .28
	if shot == "stride":
		angle = -.92
	if shot == "game":
		angle = .50
	teacher.rotation.y = PI + angle + turn
	lead.rotation.y = angle + turn
	apply_pose(shot if shot in ["demonstrate", "stride"] else "bind")
	if shot == "stride":
		# The held pose is not locomotion. Lower the inspection mark to
		# keep the low shoe on the same floor; the GLB bind height still starts at zero.
		teacher.position.y -= .01934
	var target := MARK + Vector3(0, .878, 0)
	var eye := Vector3(0, .51, 2.28)
	camera.size = 1.98
	match shot:
		"face":
			target.y = MARK.y + (1.611 if is_lead else 1.497)
			eye = Vector3(0, .116, .80)
			camera.size = .414
		"demonstrate":
			target.y = MARK.y + 1.204
			eye = Vector3(0, .260, 1.89)
			camera.size = 1.06
	camera.position = target + eye
	camera.look_at(target, Vector3.UP)
	if shot == "game":
		game_camera.make_current()
	else:
		camera.make_current()
	label.text = "%s  /  %s\n1 全身 · 2 脸 · 3 背 · 4 屈肘 · 5 步态 · 6 游戏镜头   |   Tab 对照 · ←/→ 转面 · M 材质" % [
		"现任主角" if is_lead else "生物老师 B（独立审看）", TITLES[SHOTS.find(shot)]]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		turn = 0.0
		show_shot(SHOTS[key.keycode - KEY_1], is_lead)
	elif key.keycode == KEY_TAB:
		show_shot(shot, not is_lead)
	elif key.keycode in [KEY_LEFT, KEY_RIGHT]:
		turn += .28 if key.keycode == KEY_RIGHT else -.28
		show_shot(shot, is_lead)
	elif key.keycode == KEY_M:
		look.apply_treatment(CharacterLookApplier.Treatment.ORIGINAL if look.treatment == CharacterLookApplier.Treatment.PAINTED else CharacterLookApplier.Treatment.PAINTED)
	else:
		return
	get_viewport().set_input_as_handled()
