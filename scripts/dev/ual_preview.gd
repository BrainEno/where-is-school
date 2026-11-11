extends Node3D
## Open `scenes/dev/animation_retarget_test/protagonist_ual_preview.tscn`, press F6, and the
## protagonist plays clips that were authored for a different skeleton entirely.
##
## How to look at this without running anything: select `Protagonist/UalPlayer`, open the
## Animation panel, pick any `ual/…` animation from the list and scrub the timeline. That is
## what baking bought — the retargeting happened when the file was made, so what is in the
## player is ordinary animation data with this character's bone names on it.
##
## Keys: ← → previous/next clip, 1 … 6 favourites (idle, walk, jog, dance, sit, punch),
## space pause.

const FAVOURITES := ["idle", "walk", "jog", "dance", "sitting", "punch"]

var _player: AnimationPlayer = null
var _label: Label = null
var _clips: Array[String] = []
var _index := 0
var _paused := false


func _ready() -> void:
	_player = get_node_or_null("Protagonist/UalPlayer") as AnimationPlayer
	if _player == null:
		push_error("ual_preview: the scene has no Protagonist/UalPlayer.")
		return
	for animation_name in _player.get_animation_list():
		_clips.append(String(animation_name))
	_clips.sort()

	_label = Label.new()
	_label.position = Vector2(24.0, 18.0)
	_label.add_theme_font_size_override("font_size", 16)
	var layer := CanvasLayer.new()
	layer.add_child(_label)
	add_child(layer)

	var start := _find("idle")
	_play(start if start >= 0 else 0)


func _find(fragment: String) -> int:
	for index in _clips.size():
		if _clips[index].to_lower().contains(fragment):
			return index
	return -1


func _play(index: int) -> void:
	if _clips.is_empty():
		return
	_index = wrapi(index, 0, _clips.size())
	var clip_name := _clips[_index]
	if not _player.has_animation(clip_name):
		return
	_player.play(clip_name)
	_player.paused = _paused
	_player.seek(0.0, true)
	_update_label(_player.get_animation(clip_name))


func _update_label(animation: Animation) -> void:
	if _label == null:
		return
	var length := 0.0
	if animation != null:
		length = animation.length
	var loop := "loop" if animation != null and animation.loop_mode != Animation.LOOP_NONE else "once"
	_label.text = "%s/%s  %.2fs  %s  [%d/%d]%s\n← → clip   1 idle  2 walk  3 jog  4 dance  5 sit  6 punch   space pause" % [
		"ual", _clips[_index] if not _clips.is_empty() else "?", length, loop,
		_index + 1, _clips.size(), "  (paused)" if _paused else "",
	]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_paused = not _paused
		if _player != null:
			_player.paused = _paused
		_update_label(_player.get_animation(_player.current_animation) if _player else null)
	elif key.keycode == KEY_LEFT:
		_play(_index - 1)
	elif key.keycode == KEY_RIGHT:
		_play(_index + 1)
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + FAVOURITES.size():
		var found := _find(String(FAVOURITES[key.keycode - KEY_1]))
		if found >= 0:
			_play(found)
