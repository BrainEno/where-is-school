extends Node3D
## Open `scenes/dev/animation_retarget_test/animation_preview.tscn` (F6) to watch the clips on
## both rigged characters side by side.
##
## The two characters have independently resolved rigs; Q instances its sole production
## wrapper, including native hand/finger actions. No old-Q development copy is loaded.
## Keys 1–7 select the shared states. Q-only: 8 head, 9 hands, 0 lean, P pose, F face.
## Space pauses, R re-binds. `get_up` is a one-shot; use sit_idle before it.

const CLIP_KEYS := {
	KEY_1: "idle",
	KEY_2: "walk",
	KEY_3: "jog",
	KEY_4: "sit_idle",
	KEY_5: "get_up",
	KEY_6: "wave",
	KEY_7: "talk",
	KEY_8: "head_movement",
	KEY_9: "hand_gesture",
	KEY_0: "body_lean",
	KEY_P: "pose_preview",
	KEY_F: "face_test",
}

const MODELS := [
	{"node": "Protagonist", "label": "protagonist (retargeted)"},
	{"node": "Q", "label": "Q (production new-Q)"},
]

var _clip := "idle"
var _paused := false
var _entries: Array[Dictionary] = []
var _status: Label = null
var _face_player: AnimationPlayer = null
var _face_values: Dictionary[MeshInstance3D, PackedFloat32Array] = {}


func _ready() -> void:
	_status = Label.new()
	_status.position = Vector2(24.0, 18.0)
	_status.add_theme_font_size_override("font_size", 16)
	var layer := CanvasLayer.new()
	layer.add_child(_status)
	add_child(layer)
	_bind_all()
	_play(_clip)


## Binds every character in the scene and records what each rig could and could not express.
func _bind_all() -> void:
	_restore_face()
	for entry: Dictionary in _entries:
		var old_player: AnimationPlayer = entry.get("player")
		if old_player != null and is_instance_valid(old_player) and bool(entry.get("owned", false)):
			old_player.get_parent().remove_child(old_player)
			old_player.free()
	_entries.clear()
	for spec: Dictionary in MODELS:
		var model := get_node_or_null(String(spec["node"])) as Node3D
		if model == null:
			push_error("animation_preview: the scene has no '%s'." % String(spec["node"]))
			continue
		# Q is its production wrapper, including its native hand/finger layers. Do not
		# bind a second procedural-only player over it or erase its adopted actions.
		var animator := model as CharacterVisualAnimation
		if animator != null:
			animator.set_process(false)
			_entries.append({"label": String(spec["label"]),
				"player": animator.get_animation_player(), "report": animator.get_bind_report(),
				"owned": false})
			continue
		var player := model.get_node_or_null("BoundAnimationPlayer") as AnimationPlayer
		if player == null:
			player = AnimationPlayer.new()
			player.name = "BoundAnimationPlayer"
			model.add_child(player)
			# Track paths are relative to the player's root node, so this makes
			# "Skeleton3D:Spine" mean *this* model's skeleton.
			player.root_node = player.get_path_to(model)
		var report := CharacterAnimation.bind(model, player)
		_entries.append({"label": String(spec["label"]), "player": player, "report": report, "owned": true})
		print(
			"animation_preview: %s — %s"
			% [String(spec["label"]), CharacterAnimation.describe(report)]
		)
	_update_status()


func _play(clip_name: String) -> void:
	_restore_face()
	_clip = clip_name
	for entry: Dictionary in _entries:
		var player: AnimationPlayer = entry["player"]
		# A Q-only diagnostic is not an absent protagonist animation: the other rig
		# stays on its real idle while Q demonstrates the supplied action.
		var target := clip_name if player.has_animation("char/%s" % clip_name) else "idle"
		if CharacterAnimation.play(player, target) and _paused:
			player.pause()
	if clip_name == "face_test":
		_preview_face()
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	var lines: PackedStringArray = ["clip: %s%s" % [_clip, " (paused)" if _paused else ""]]
	for entry: Dictionary in _entries:
		var report: Dictionary = entry["report"]
		if not bool(report.get("ok", false)):
			lines.append("%s: not bound (%s)" % [String(entry["label"]), String(report.get("reason", "?"))])
			continue
		var resolved: Dictionary = report["resolved"]
		var missing: Array = report["missing"]
		var clips: Dictionary = report["clips"]
		var tracks: Dictionary = clips.get(_clip, {})
		lines.append(
			"%s: %d bone(s), %d unused, %s %d track(s)"
			% [
				String(entry["label"]), resolved.size(), missing.size(), _clip,
				int(tracks.get("tracks", 0)),
			]
		)
	lines.append(
		"1 idle  2 walk  3 jog  4 sit_idle  5 get_up  6 wave  7 talk\n"
		+ "Q only: 8 head  9 hands  0 lean  P pose  F face    space pause   R re-bind"
	)
	_status.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if CLIP_KEYS.has(key.keycode):
		_play(String(CLIP_KEYS[key.keycode]))
	elif key.keycode == KEY_SPACE:
		_paused = not _paused
		for entry: Dictionary in _entries:
			var player: AnimationPlayer = entry["player"]
			if _paused:
				player.pause()
			else:
				player.play()
		if _face_player != null:
			if _paused:
				_face_player.pause()
			else:
				_face_player.play()
		_update_status()
	elif key.keycode == KEY_R:
		_bind_all()
		_play(_clip)


## The supplied face diagnostic is a morph-only source clip. It may run beside a
## bound idle because it writes no bones. Temporarily pause the dev wrapper's blink
## writer so two systems never compete for the same eyelid, then restore exact values.
func _preview_face() -> void:
	var q := get_node("Q") as CharacterVisualAnimation
	var model := q.get_node("Model")
	_face_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _face_player == null or not _face_player.has_animation("Q_Face_Test"):
		push_error("animation_preview: approved Q has no supplied facial diagnostic.")
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var values := PackedFloat32Array()
		for index in mesh.mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(index))
		if not values.is_empty():
			_face_values[mesh] = values
	q.get_node("Look").set_process(false)
	_face_player.play("Q_Face_Test", 0.0)
	if _paused:
		_face_player.pause()


func _restore_face() -> void:
	if _face_player == null:
		return
	_face_player.stop()
	_face_player = null
	for mesh: MeshInstance3D in _face_values:
		if is_instance_valid(mesh):
			var values := _face_values[mesh]
			for index in values.size():
				mesh.set_blend_shape_value(index, values[index])
	_face_values.clear()
	get_node("Q/Look").set_process(true)
