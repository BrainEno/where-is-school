extends Node3D
## Open `scenes/dev/animation_retarget_test/animation_preview.tscn` (F6) to watch the clips on
## both rigged characters side by side.
##
## The two characters are rigged differently — Q says `UpperArm.L`, the retargeted
## protagonist says `LeftUpperArm` — and neither matches the animation library that was tried
## first (`upperarm_l`). `CharacterAnimation` resolves canonical bone names against whichever
## rig it is handed, so both characters play the same seven clips; this scene is the visual
## proof, and `tests/character_animation_test.gd` is the headless one.
##
## Keys: 1 idle, 2 walk, 3 jog, 4 sit_idle, 5 get_up, 6 wave, 7 talk. Space pauses. R
## re-binds (after re-importing a model in the editor, which reloads it without restarting
## the scene). `get_up` is a transition, so it plays once and stops on its last frame here —
## use `sit_idle` before it to see the movement it belongs to.

const CLIP_KEYS := {
	KEY_1: "idle",
	KEY_2: "walk",
	KEY_3: "jog",
	KEY_4: "sit_idle",
	KEY_5: "get_up",
	KEY_6: "wave",
	KEY_7: "talk",
}

const MODELS := [
	{"node": "Protagonist", "label": "protagonist (retargeted)"},
	{"node": "Q", "label": "Q (rigged)"},
]

var _clip := "idle"
var _paused := false
var _entries: Array[Dictionary] = []
var _status: Label = null


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
	for entry: Dictionary in _entries:
		var old_player: AnimationPlayer = entry.get("player")
		if old_player != null and is_instance_valid(old_player):
			old_player.queue_free()
	_entries.clear()
	for spec: Dictionary in MODELS:
		var model := get_node_or_null(String(spec["node"])) as Node3D
		if model == null:
			push_error("animation_preview: the scene has no '%s'." % String(spec["node"]))
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
		_entries.append({"label": String(spec["label"]), "player": player, "report": report})
		print(
			"animation_preview: %s — %s"
			% [String(spec["label"]), CharacterAnimation.describe(report)]
		)
	_update_status()


func _play(clip_name: String) -> void:
	_clip = clip_name
	for entry: Dictionary in _entries:
		var player: AnimationPlayer = entry["player"]
		if not CharacterAnimation.play(player, clip_name):
			continue
		player.paused = _paused
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
		"1 idle  2 walk  3 jog  4 sit_idle  5 get_up  6 wave  7 talk    space pause   R re-bind"
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
			(entry["player"] as AnimationPlayer).paused = _paused
		_update_status()
	elif key.keycode == KEY_R:
		_bind_all()
		_play(_clip)
