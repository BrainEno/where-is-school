extends Node3D
## Runtime animation driver for an authored character visual.
##
## The model wrapper owns this node, so CharacterAnimation can build track paths
## relative to the wrapper and find the Skeleton3D no matter how the GLB is nested.
## Locomotion is read from the nearest CharacterBody3D ancestor. Tween-driven NpcActor
## walks can explicitly call set_walking() as they do not have a physics velocity.

@export_range(0.01, 1.0, 0.01) var movement_speed_threshold: float = 0.08

var _player: AnimationPlayer
var _bound := false
var _manual_walking := false
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
	print("CharacterVisualAnimation: %s — %s" % [name, CharacterAnimation.describe(report)])
	_set_clip("idle")


func _process(_delta: float) -> void:
	if not _bound:
		return
	var moving := _manual_walking or _ancestor_horizontal_speed() > movement_speed_threshold
	_set_clip("walk" if moving else "idle")


## For authored NPCs that move by tween rather than CharacterBody3D velocity.
func set_walking(walking: bool) -> void:
	_manual_walking = walking
	if _bound:
		_set_clip("walk" if walking or _ancestor_horizontal_speed() > movement_speed_threshold else "idle")


func get_current_clip() -> String:
	return _current_clip


func is_bound() -> bool:
	return _bound


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
