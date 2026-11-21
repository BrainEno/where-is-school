class_name ImaginedLesson
extends Node3D
## The biology teacher B as the protagonist pictures her (`expected_b`), drawn in the
## classroom itself (docs/IMAGINED_LESSON.md).
##
## Nothing here is an actor. B's real entrance is `BPresence.present()` and an `NpcActor`
## with npc_id `b`; this is presentation only, switched by `ClassroomPresentation` while the
## imagined exchange is on screen and off as soon as it ends (skipped or not). It has no
## collision, no interactable and no save state.
##
## While it is on:
##
## - **B** (the shipped `teacher_b.glb`) stands in the aisle beside the protagonist's desk,
##   half again her size, leaning over him, in `dream_figure.gdshader`: swollen head, drawn-out
##   body, an S-wave running up it, recoloured into expressionist fields with Munch's bands.
## - **Two after-images** of her stand at the front of the room, at the lectern and the
##   blackboard, flat ink silhouettes on a slower wave: the teacher who is everywhere.
## - **The room** is repainted on screen by `munch_wave.gdshader`, a Scream-like swirl centred
##   on her head, in a canvas layer under the dialogue UI. The room's geometry is untouched:
##   the same place, in another style.
##
## `set_active()` fades all of it in from her head outwards (`FADE_IN`) and back out
## (`FADE_OUT`); `get_dream()` is the current amount (0 off, 1 fully imagined).

const FIGURE: PackedScene = preload("res://assets/models/teacher_b/teacher_b.glb")
const MOTION: AnimationLibrary = preload("res://assets/models/teacher_b/teacher_b_motion.tres")
const FIGURE_SHADER: Shader = preload("res://assets/shaders/imagined/dream_figure.gdshader")
const INK_SHADER: Shader = preload("res://assets/shaders/imagined/dream_ink.gdshader")
const LIBRARY: StringName = &"teacher_b"
## The lead figure alternates these; the after-images only explain.
const LEAD_MOTIONS: Array[StringName] = [&"explain", &"idle", &"explain"]
const FADE_IN := 1.6
const FADE_OUT := 0.9
## Where the swirl centres, in the figure's own metres (her face).
const HEAD := Vector3(0.0, 1.62, -0.12)
## The wave's `reach` that covers the whole screen from any vortex.
const FULL_REACH := 2.5

## The lead figure's scale: a seated pupil's view of a standing teacher.
@export var lead_scale := 1.5
## The after-images' scale: the shadows a projector throws are always larger.
@export var echo_scale := 1.55

var _figures: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []
var _materials: Array[ShaderMaterial] = []
var _lead_motion := 0
var _dream := 0.0
var _active := false
var _tween: Tween = null

@onready var _lead_mark: Marker3D = $Lead
@onready var _gaze: Marker3D = $Gaze
@onready var _echo_marks: Array[Marker3D] = [$EchoLectern, $EchoBlackboard]
@onready var _layer: CanvasLayer = $Wave
@onready var _filter: ColorRect = $Wave/Filter


func _ready() -> void:
	_build_figure(_lead_mark, lead_scale, false, 0.0)
	for index in _echo_marks.size():
		_build_figure(_echo_marks[index], echo_scale, true, 1.7 + 2.3 * index)
	_set_dream(0.0)


func _process(_delta: float) -> void:
	_follow_head()


## Shows (fading in) or hides (fading out) the imagined lesson. Calling it again with the
## current state changes nothing.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if active:
		_show(true)
		_restart_motion()
		_follow_head()
	if not is_inside_tree():
		_set_dream(1.0 if active else 0.0)
		return
	var target := 1.0 if active else 0.0
	var seconds := (FADE_IN if active else FADE_OUT) * absf(target - _dream)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if active else Tween.EASE_IN)
	_tween.tween_method(_set_dream, _dream, target, seconds)


func is_active() -> bool:
	return _active


## 0 when nothing is imagined, 1 when the room is fully repainted.
func get_dream() -> float:
	return _dream


## The figures (lead first), for tests and captures.
func get_figures() -> Array[Node3D]:
	return _figures


## The screen filter's material, for tests and captures.
func get_wave_material() -> ShaderMaterial:
	return _filter.material as ShaderMaterial


func _set_dream(value: float) -> void:
	_dream = clampf(value, 0.0, 1.0)
	for material in _materials:
		material.set_shader_parameter(&"dream", _dream)
		var ink := material.next_pass as ShaderMaterial
		if ink != null:
			ink.set_shader_parameter(&"dream", _dream)
	var wave := get_wave_material()
	if wave != null:
		wave.set_shader_parameter(&"strength", _dream)
		wave.set_shader_parameter(&"reach", FULL_REACH * _dream)
	if _dream <= 0.0 and not _active:
		_show(false)


func _show(on: bool) -> void:
	visible = on
	_layer.visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _build_figure(mark: Marker3D, figure_scale: float, echo: bool, phase: float) -> void:
	var gaze := _gaze.global_position
	mark.look_at(Vector3(gaze.x, mark.global_position.y, gaze.z), Vector3.UP)
	var figure := FIGURE.instantiate() as Node3D
	figure.name = "Figure"
	figure.scale = Vector3.ONE * figure_scale
	mark.add_child(figure)
	var material := ShaderMaterial.new()
	material.shader = FIGURE_SHADER
	material.set_shader_parameter(&"phase", phase)
	var ink := ShaderMaterial.new()
	ink.shader = INK_SHADER
	ink.set_shader_parameter(&"phase", phase)
	if echo:
		material.set_shader_parameter(&"echo", 1.0)
		material.set_shader_parameter(&"sway_speed", 0.45)
		material.set_shader_parameter(&"lean", 0.12)
		material.set_shader_parameter(&"head_swell", 0.2)
		ink.set_shader_parameter(&"sway_speed", 0.45)
		ink.set_shader_parameter(&"lean", 0.12)
		ink.set_shader_parameter(&"head_swell", 0.2)
	material.next_pass = ink
	for node in figure.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var rest := CharacterLookApplier.rest_coordinate_mesh(mesh_instance.mesh as ArrayMesh)
		if rest != null:
			mesh_instance.mesh = rest
		mesh_instance.material_override = material
		if echo:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_materials.append(material)
	_figures.append(figure)
	var skeletons := figure.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		push_error("ImaginedLesson: teacher_b.glb should hold exactly one Skeleton3D.")
		return
	var player := AnimationPlayer.new()
	player.name = "Motion"
	figure.add_child(player)
	player.add_animation_library(LIBRARY, MOTION)
	player.root_node = player.get_path_to(skeletons[0])
	player.animation_finished.connect(_on_motion_finished.bind(player, echo))
	_players.append(player)


func _restart_motion() -> void:
	_lead_motion = 0
	for index in _players.size():
		var player := _players[index]
		player.play(_motion_name(LEAD_MOTIONS[0]))
		# The after-images are behind her in time as well.
		if index > 0:
			player.seek(0.6 * index, true)


func _on_motion_finished(_animation: StringName, player: AnimationPlayer, echo: bool) -> void:
	if not _active:
		return
	if echo:
		player.play(_motion_name(&"explain"))
		return
	_lead_motion = (_lead_motion + 1) % LEAD_MOTIONS.size()
	player.play(_motion_name(LEAD_MOTIONS[_lead_motion]))


func _motion_name(motion: StringName) -> StringName:
	return StringName("%s/%s" % [LIBRARY, motion])


## Centres the swirl on the lead figure's face, wherever the camera is.
func _follow_head() -> void:
	var wave := get_wave_material()
	if wave == null or _figures.is_empty() or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var head := _figures[0].to_global(HEAD)
	if camera.is_position_behind(head):
		return
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var screen := camera.unproject_position(head) / size
	wave.set_shader_parameter(&"vortex", screen.clamp(Vector2(-0.25, -0.25), Vector2(1.25, 1.25)))
