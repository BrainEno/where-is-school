extends Node3D
## Runtime animation driver for an authored character visual.
##
## The model wrapper owns this node, so CharacterAnimation can build track paths
## relative to the wrapper and find the Skeleton3D no matter how the GLB is nested.
## Locomotion is read from the nearest CharacterBody3D ancestor. Tween-driven NpcActor
## walks can explicitly call set_walking() as they do not have a physics velocity.
##
## Three things can hold a clip, in this order of precedence:
##
##   1. an *action* — a one-shot transition (`get_up`), started by `play_action()`, which
##      owns the body until its clip reports `animation_finished` and then hands back;
##   2. *seated* — `set_seated(true)` holds `sit_idle` and ignores the body's velocity,
##      because a character sitting on a chair is not walking no matter what the capsule
##      does. The wake beat uses this: the protagonist starts slumped at a desk;
##   3. locomotion, from the nearest ancestor `CharacterBody3D`: `idle`, `walk`, or `jog`
##      above `jog_speed_threshold` (the player's sprint input is what reaches it).
##
## It never moves the body. Every track is a bone rotation, so the `CharacterBody3D` owns
## position, the `VisualPivot` owns the wake tilt and sink, and this node owns the skeleton.

@export_range(0.01, 1.0, 0.01) var movement_speed_threshold: float = 0.08
## Above this horizontal speed, walking becomes jogging. `PlayerController.move_speed` is
## 3.6 m/s and its sprint speed 5.6, so 4.4 sits between the two: a walker accelerating
## towards a sprint passes through `walk` for a moment and stays there, and an `NpcActor`
## (1.6 m/s) never gets near it.
@export_range(0.5, 12.0, 0.1) var jog_speed_threshold: float = 4.4

## The clip a seated character holds.
const SEATED_CLIP := "sit_idle"

var _player: AnimationPlayer
var _bound := false
var _manual_walking := false
var _seated := false
var _action := ""
var _current_clip := ""


func _ready() -> void:
	_player = AnimationPlayer.new()
	_player.name = "BoundAnimationPlayer"
	add_child(_player)
	_player.root_node = _player.get_path_to(self)

	var report := CharacterAnimation.bind(self, _player)
	_bound = bool(report.get("ok", false))
	if not _bound:
		push_error(
			"CharacterVisualAnimation on '%s' could not bind: %s"
			% [name, String(report.get("reason", "unknown"))]
		)
		return
	_player.animation_finished.connect(_on_animation_finished)
	print("CharacterVisualAnimation: %s — %s" % [name, CharacterAnimation.describe(report)])
	_set_clip("idle")


func _process(_delta: float) -> void:
	if not _bound or not _action.is_empty():
		return
	if _seated:
		_set_clip(SEATED_CLIP)
		return
	_set_clip(_locomotion_clip())


## For authored NPCs that move by tween rather than CharacterBody3D velocity.
func set_walking(walking: bool) -> void:
	_manual_walking = walking
	if _bound and _action.is_empty():
		_set_clip(_locomotion_clip())


## Holds the seated pose until `set_seated(false)`. Ignored while an action is playing; the
## state is remembered and applied when the action ends.
func set_seated(seated: bool) -> void:
	_seated = seated
	if _bound and _action.is_empty():
		_set_clip(SEATED_CLIP if seated else _locomotion_clip())


func is_seated() -> bool:
	return _seated


## Plays a transition clip once. Returns false when this rig cannot play it, so a caller can
## fall back instead of freezing in the last frame of a clip that is not there.
func play_action(clip_name: String) -> bool:
	if not _bound:
		return false
	if not CharacterAnimation.play(_player, clip_name):
		return false
	_action = clip_name
	_current_clip = clip_name
	return true


func is_playing_action() -> bool:
	return not _action.is_empty()


func get_current_clip() -> String:
	return _current_clip


func is_bound() -> bool:
	return _bound


## What the body's own movement is worth right now.
func _locomotion_clip() -> String:
	var speed := _ancestor_horizontal_speed()
	if not _manual_walking and speed <= movement_speed_threshold:
		return "idle"
	return "jog" if speed > jog_speed_threshold else "walk"


## The clip that follows an action: the seated pose if the character is still holding one,
## otherwise whatever the body is doing.
func _resume_clip() -> String:
	return SEATED_CLIP if _seated else _locomotion_clip()


func _on_animation_finished(clip_name: StringName) -> void:
	if _action.is_empty():
		return
	if String(clip_name) != "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), _action]:
		return
	_action = ""
	_set_clip(_resume_clip())


func _set_clip(clip_name: String) -> void:
	if clip_name == _current_clip:
		return
	if CharacterAnimation.play(_player, clip_name):
		_current_clip = clip_name


func _ancestor_horizontal_speed() -> float:
	var ancestor := get_parent()
	while ancestor != null:
		var body := ancestor as CharacterBody3D
		if body != null:
			return Vector2(body.velocity.x, body.velocity.z).length()
		ancestor = ancestor.get_parent()
	return 0.0
