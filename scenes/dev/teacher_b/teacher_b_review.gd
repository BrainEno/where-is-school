extends Node3D
## Review stage only. It uses the room's actual light and materials, but no actor,
## interactable, save data or opening director. F6 runs this scene, not the prologue.

const CLASSROOM := preload("res://scenes/locations/classroom/classroom.tscn")
const POSE_DATA := "res://scenes/dev/teacher_b/review_poses.json"
const MARK := Vector3(-1.52, 0.123, -3.46)
const SHOTS := ["body", "face", "back", "demonstrate", "stride", "game"]
const TITLES := ["全身", "脸部", "背面", "手臂与手指", "走步定格", "游戏镜头"]
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const CLIPS := ["idle", "walk", "explain"]
const MOTION_SHOTS := ["body", "walk", "demonstrate"]
const MOTION_TITLES := ["站立待机", "短步行走", "抬手讲解"]

@onready var teacher: Node3D = $TeacherB
@onready var lead: CharacterVisualAnimation = $Protagonist
@onready var look: CharacterLookApplier = $TeacherB/Look
@onready var motion: AnimationPlayer = $TeacherB/Motion
@onready var camera: Camera3D = $InspectionCamera
@onready var game_camera: Camera3D = $GameCameraRig/Camera3D
@onready var label: Label = $Help/Label
@onready var buttons: HBoxContainer = $Help/Actions/Buttons
@onready var pause_button: Button = buttons.get_node(^"Pause")
@onready var restart_button: Button = buttons.get_node(^"Restart")

var skeleton: Skeleton3D
var poses: Dictionary
var shot := "body"
var is_lead := false
var turn := 0.0
var clip := ""
var clip_finished := false


func _ready() -> void:
	var room := CLASSROOM.instantiate()
	for name_to_remove: String in ["Actors", "Interactables", "Navigation", "Ambience", "ScreenControl", "ChairControl", "VoidStep"]:
		var node := room.get_node_or_null(NodePath(name_to_remove))
		if node != null:
			node.free()
	# Keep the curtain mesh and remove only its story controller, whose
	# _ready() would otherwise try to wire the removed Interactables.
	var anomalies := room.get_node_or_null(^"Anomalies")
	if anomalies != null:
		anomalies.set_script(null)
	add_child(room)
	$CameraMark.position = MARK
	# Resolve the same real rig the project's shared binder inspects, but use
	# native B-only tracks (including Root position and finger rotations).
	var rigs := CharacterAnimation.skeletons_in(teacher)
	if rigs.size() != 1:
		push_error("Teacher B review needs exactly one imported Skeleton3D.")
		return
	skeleton = rigs[0]
	motion.root_node = motion.get_path_to(skeleton)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POSE_DATA))
	if not parsed is Dictionary:
		push_error("Teacher B review could not read its pose data.")
		return
	poses = parsed
	for i in CLIPS.size():
		(buttons.get_child(i) as Button).pressed.connect(play_motion.bind(CLIPS[i]))
	pause_button.pressed.connect(_toggle_pause)
	restart_button.pressed.connect(_restart_motion)
	motion.animation_finished.connect(_on_motion_finished)
	play_motion("idle")


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


## Frozen inspection / side-by-side comparison. Never leaves keys from a clip.
func show_shot(next_shot: String, show_lead: bool = false) -> void:
	if not SHOTS.has(next_shot):
		return
	motion.stop()
	clip = ""
	clip_finished = false
	_place_shot(next_shot, show_lead)
	apply_pose(shot if shot in ["demonstrate", "stride"] else "bind")
	if shot == "stride":
		# A held pose, not the walk clip. Correct the sole height for inspection.
		teacher.position.y -= .01934
	_refresh_help()


func play_motion(name_to_play: String) -> bool:
	var index := CLIPS.find(name_to_play)
	var full_name := StringName("teacher_b/" + name_to_play)
	if index < 0 or skeleton == null or not motion.has_animation(full_name):
		push_error("Missing Teacher B review action: '%s'." % name_to_play)
		return false
	var next_shot: String = MOTION_SHOTS[index]
	if shot == "game" or (name_to_play == "idle" and shot in ["face", "back"]):
		next_shot = shot
	clip = name_to_play
	clip_finished = false
	motion.stop()
	skeleton.reset_bone_poses()
	_place_shot(next_shot)
	motion.play(full_name)
	motion.advance(0.0)
	_refresh_help()
	return true


func _place_shot(next_shot: String, show_lead: bool = false) -> void:
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
	# Native front axes differ; neither mesh is resized for its comparison.
	var angle := -.28 if shot != "back" else PI + .28
	if shot in ["stride", "walk"]:
		angle = -1.12 if shot == "walk" else -.92
	if shot == "game":
		angle = .50
	teacher.rotation.y = PI + angle + turn
	lead.rotation.y = angle + turn
	var target := MARK + Vector3(0, .878, 0)
	var eye := Vector3(0, .51, 2.28)
	camera.size = 1.98
	match shot:
		"face":
			target.y = MARK.y + (1.611 if is_lead else 1.497)
			eye = Vector3(0, .116, .80)
			camera.size = .414
		"demonstrate":
			target.y = MARK.y + 1.19
			eye = Vector3(0, .26, 1.89)
			camera.size = 1.06
		"walk":
			# Frame the whole short path and keep both shoes in shot.
			target += teacher.basis * Vector3(0, 0, -.45)
			target.y = MARK.y + .85
			eye.y = .31
			camera.size = 2.16
	camera.position = target + eye
	camera.look_at(target, Vector3.UP)
	if shot == "game":
		game_camera.make_current()
	else:
		camera.make_current()


func _refresh_help() -> void:
	var title: String = TITLES[SHOTS.find(shot)] if shot in SHOTS else "全身侧面"
	if not clip.is_empty():
		title += " · " + String(MOTION_TITLES[CLIPS.find(clip)])
		if clip_finished:
			title += "（结束）"
		elif not motion.is_playing():
			title += "（暂停）"
	label.text = "%s  /  %s\n1 全身 · 2 脸 · 3 背 · 4 手部 · 5 走步定格 · 6 游戏镜头   |   Tab 对照 · ←/→ 转面 · M 材质" % [
		"现任主角" if is_lead else "生物老师 B", title]
	for i in CLIPS.size():
		(buttons.get_child(i) as Button).set_pressed_no_signal(clip == CLIPS[i])
	pause_button.disabled = clip.is_empty() or clip_finished
	pause_button.text = "空格 暂停" if motion.is_playing() else "空格 继续"
	restart_button.disabled = clip.is_empty()


func _toggle_pause() -> void:
	if clip.is_empty() or clip_finished:
		return
	if motion.is_playing():
		motion.pause()
	else:
		motion.play()
	_refresh_help()


func _restart_motion() -> void:
	if not clip.is_empty():
		play_motion(clip)


func _on_motion_finished(animation: StringName) -> void:
	if animation == StringName("teacher_b/" + clip):
		clip_finished = true
		_refresh_help()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		turn = 0.0
		show_shot(SHOTS[key.keycode - KEY_1], is_lead)
	elif key.keycode >= KEY_7 and key.keycode <= KEY_9:
		play_motion(CLIPS[key.keycode - KEY_7])
	elif key.keycode == KEY_TAB and shot in ["body", "face", "game"]:
		show_shot(shot, not is_lead)
	elif key.keycode in [KEY_LEFT, KEY_RIGHT]:
		turn += .28 if key.keycode == KEY_RIGHT else -.28
		if clip.is_empty():
			show_shot(shot, is_lead)
		else:
			_place_shot(shot)
	elif key.keycode == KEY_M:
		look.apply_treatment(CharacterLookApplier.Treatment.ORIGINAL if look.treatment == CharacterLookApplier.Treatment.PAINTED else CharacterLookApplier.Treatment.PAINTED)
	elif key.keycode == KEY_SPACE:
		_toggle_pause()
	elif key.keycode == KEY_R:
		_restart_motion()
	else:
		return
	get_viewport().set_input_as_handled()
