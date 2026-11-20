extends Node3D
## An isolated inspection stage; it owns no dialogue, NPC spawn or game state.

const IDS := [&"thin_classmate", &"gentle_classmate", &"court_classmate"]
const LABELS := ["01 / New classmate", "02 / Close friend", "03 / Court classmate"]
const HEIGHTS := [1.60, 1.62, 1.80]
const GESTURES := [&"mutter", &"listen_offer", &"check_court"]
const BEATS := [1.34, 1.78, 1.42]
const LINEUP := -1
const COMPARE_Q := -2

@onready var performers: Array[Node3D] = [$Actors/Thin, $Actors/Gentle, $Actors/Court]
@onready var reference_q := $Actors/Q as Node3D
@onready var camera := $Camera as Camera3D
@onready var hud := $Hud as CanvasLayer
@onready var title := $Hud/Title as Label

var selection := LINEUP
var yaw := 0.0
var detail := false


func _ready() -> void:
	select_cast(LINEUP)


func player(index: int) -> AnimationPlayer:
	var matches := performers[index].find_children("*", "AnimationPlayer", true, false)
	return matches.front() as AnimationPlayer if not matches.is_empty() else null


func rig(index: int) -> Skeleton3D:
	var matches := performers[index].find_children("*", "Skeleton3D", true, false)
	return matches.front() as Skeleton3D if not matches.is_empty() else null


func bind(index: int) -> void:
	var motion := player(index)
	if motion != null:
		motion.stop()
	var skeleton := rig(index)
	if skeleton != null:
		skeleton.reset_bone_poses()
	for part in performers[index].find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		for i in mesh.get_blend_shape_count():
			mesh.set_blend_shape_value(i, 0.0)


func select_cast(which: int) -> void:
	selection = which
	detail = false
	yaw = 0.0
	for i in performers.size():
		var member := performers[i]
		bind(i)
		member.visible = which == LINEUP or which == i or (which == COMPARE_Q and i == 1)
		member.position.x = [0.69, 0.0, -0.69][i] if which == LINEUP else 0.38 if which == COMPARE_Q else 0.0
	reference_q.visible = which == COMPARE_Q
	reference_q.position.x = -0.39
	set_view(0.0)


func set_view(degrees: float, close_up := false, gesture := false) -> void:
	yaw = fposmod(degrees, 360.0)
	detail = close_up and selection >= 0
	var center := Vector3(0.0, 0.91, -0.04)
	var span := 2.02
	if selection >= 0:
		var h: float = HEIGHTS[selection]
		center.y = h * 0.51
		span = h + 0.24
		if detail:
			center = Vector3(0.0, h - 0.157, -0.085)
			span = 0.405
		elif gesture:
			center.y = h * 0.747
			center.x = 0.08 if selection == 1 else -0.04
			span = 1.02
	var a := deg_to_rad(yaw)
	camera.position = center + Vector3(sin(a) * 3.6, 0.17 if detail else 0.28, -cos(a) * 3.6)
	camera.look_at(center)
	camera.size = span
	if selection >= 0:
		title.text = "%s    ·    %.2f m" % [LABELS[selection], HEIGHTS[selection]]
	else:
		title.text = "Friend 1.62 m   /   Current Q" if selection == COMPARE_Q else "Classmate scale lineup   /   1.60 · 1.62 · 1.80 m"


func play_clip(clip: StringName) -> bool:
	if selection < 0:
		return false
	var motion := player(selection)
	if motion == null or not motion.has_animation(clip):
		return false
	bind(selection)
	motion.play(clip)
	motion.advance(0.0)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_0:
			select_cast(LINEUP)
		KEY_1, KEY_2, KEY_3:
			select_cast(key.keycode - KEY_1)
		KEY_Q:
			select_cast(COMPARE_Q)
		KEY_LEFT, KEY_RIGHT:
			set_view(yaw + (45.0 if key.keycode == KEY_RIGHT else -45.0), detail)
		KEY_F:
			set_view(yaw, not detail)
		KEY_I:
			play_clip(&"idle")
		KEY_W:
			play_clip(&"walk_in_place")
		KEY_G:
			if selection >= 0:
				play_clip(GESTURES[selection])
		KEY_R:
			if selection >= 0:
				bind(selection)
		_:
			return
	get_viewport().set_input_as_handled()
