class_name CharacterVisualAnimation
extends Node3D
## The one locomotion state machine every authored character uses: idle or walk.
##
## Hangs off a character wrapper (`protagonist.tscn`, `q.tscn`), builds that model's clips
## with `CharacterAnimation.bind()` on an `AnimationPlayer` of its own, and decides each frame
## whether the character is standing or walking. It is the same decision for everyone:
##
##   the player, WASD          `PlayerController._apply_movement()` → body velocity ┐
##   the player, click-to-move `PlayerController._path_direction()` → body velocity ┤
##   Q following               `CompanionController._apply_movement()` → body velocity ┼→ _update_locomotion()
##   an NPC walking a route    `NpcActor.walk_along()` → reported velocity ─────────────┘
##
## The input is the planar velocity the character's own controller already produces; no
## controller has a second, animation-only notion of "moving". A `CharacterBody3D` reports
## its velocity *after* `move_and_slide()`, so a body pressed against a wall reads as still
## and stands instead of walking on the spot.
##
## What this node never does: write a transform. The clips are bone-rotation tracks on the
## skeleton and nothing else — no root motion, no yaw, no position — so the controller's
## facing (`VisualPivot` for the player, the actor's own rotation for an NPC) and the wake
## beat's slump stay exactly where the controller put them.

signal locomotion_changed(state: StringName)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"

## Planar speed (m/s) above which a standing character starts walking...
@export_range(0.01, 2.0, 0.01) var walk_enter_speed: float = 0.2
## ...and below which a walking one stops. The gap is the hysteresis that keeps a body that
## is just settling (the last few centimetres of a deceleration) from flickering between clips.
@export_range(0.0, 2.0, 0.01) var walk_exit_speed: float = 0.08
## The ground speed the walk clip is authored for at playback speed 1. Faster characters play
## it faster so the feet keep roughly in step with the ground instead of skating.
@export_range(0.3, 6.0, 0.05) var stride_speed: float = 1.6
@export_range(0.1, 2.0, 0.05) var min_walk_playback: float = 0.7
@export_range(0.5, 4.0, 0.05) var max_walk_playback: float = 1.9
## Cross-fade between idle and walk, in seconds. Every clip keys every animated bone, so the
## fade always has a pose to fade *to*.
@export_range(0.0, 1.0, 0.01) var blend_time: float = 0.18

var _player: AnimationPlayer
var _bound := false
var _bind_report: Dictionary = {}
## The body whose velocity drives this character. Found as the nearest `CharacterBody3D`
## ancestor at `_ready()`; a controller can also hand itself over with `bind_body()`.
var _body: CharacterBody3D = null
## A velocity reported by a controller that moves without physics (a tween walk).
var _reported_velocity := Vector3.ZERO
var _reporting := false
var _state: StringName = &""
var _current_clip := ""
var _planar_speed := 0.0
var _transitions := 0


func _ready() -> void:
	_player = AnimationPlayer.new()
	_player.name = "BoundAnimationPlayer"
	add_child(_player)
	_player.root_node = _player.get_path_to(self)

	_bind_report = CharacterAnimation.bind(self, _player)
	_bound = bool(_bind_report.get("ok", false))
	if not _bound:
		push_error(
			"CharacterVisualAnimation on '%s' could not bind: %s"
			% [name, String(_bind_report.get("reason", "unknown"))]
		)
		return
	print("CharacterVisualAnimation: %s — %s" % [name, CharacterAnimation.describe(_bind_report)])
	if _body == null:
		_body = _find_body_ancestor()
	_enter_state(STATE_IDLE, 0.0)


func _process(_delta: float) -> void:
	if not _bound:
		return
	_update_locomotion(get_planar_velocity())


# --- Inputs -----------------------------------------------------------------


## Drives this character from `body`'s velocity. Controllers call it so the wiring is
## explicit; a wrapper without a call still finds its nearest `CharacterBody3D` ancestor.
func bind_body(body: CharacterBody3D) -> void:
	_body = body


## For a controller that moves the character without physics: the velocity it is moving
## at, in world space. `report_velocity(Vector3.ZERO)` ends the walk; `clear_reported_velocity()`
## hands the decision back to the body, if there is one.
func report_velocity(velocity: Vector3) -> void:
	_reported_velocity = velocity
	_reporting = true
	if _bound:
		_update_locomotion(get_planar_velocity())


func clear_reported_velocity() -> void:
	_reported_velocity = Vector3.ZERO
	_reporting = false
	if _bound:
		_update_locomotion(get_planar_velocity())


## Compatibility with the first wiring: a walking flag is a reported velocity at the clip's
## own stride speed.
func set_walking(walking: bool) -> void:
	if walking:
		report_velocity(global_basis.z.normalized() * stride_speed)
	else:
		clear_reported_velocity()


# --- The decision -----------------------------------------------------------


## The planar velocity this character is moving at: the reported one while a controller is
## reporting, otherwise the body's.
func get_planar_velocity() -> Vector3:
	var velocity := Vector3.ZERO
	if _reporting:
		velocity = _reported_velocity
	elif _body != null and is_instance_valid(_body):
		velocity = _body.velocity
	velocity.y = 0.0
	return velocity


## The whole idle/walk rule, shared by every character. Public so a test can feed it a
## velocity directly and get the same answer the game would.
func _update_locomotion(planar_velocity: Vector3) -> void:
	_planar_speed = Vector2(planar_velocity.x, planar_velocity.z).length()
	var next := _state
	if _state == STATE_WALK:
		if _planar_speed < walk_exit_speed:
			next = STATE_IDLE
	elif _planar_speed > walk_enter_speed:
		next = STATE_WALK
	if next != _state:
		_enter_state(next, blend_time)
	if _state == STATE_WALK:
		_player.speed_scale = walk_playback_for(_planar_speed)


## Playback speed of the walk clip for a ground speed.
func walk_playback_for(speed: float) -> float:
	return clampf(speed / maxf(stride_speed, 0.01), min_walk_playback, max_walk_playback)


func _enter_state(state: StringName, blend: float) -> void:
	if not CharacterAnimation.play(_player, String(state), blend):
		return
	_state = state
	_current_clip = String(state)
	_transitions += 1
	if state == STATE_IDLE:
		_player.speed_scale = 1.0
	locomotion_changed.emit(state)


# --- Read-outs --------------------------------------------------------------


func get_locomotion_state() -> StringName:
	return _state


func get_current_clip() -> String:
	return _current_clip


func get_planar_speed() -> float:
	return _planar_speed


func get_transition_count() -> int:
	return _transitions


func is_bound() -> bool:
	return _bound


func get_bind_report() -> Dictionary:
	return _bind_report


func get_animation_player() -> AnimationPlayer:
	return _player


## The body this character reads its velocity from, or null.
func get_locomotion_body() -> CharacterBody3D:
	return _body


## The first `Skeleton3D` of the model, for tests and diagnostics.
func get_skeleton() -> Skeleton3D:
	var skeletons := CharacterAnimation.skeletons_in(self)
	return skeletons[0] if not skeletons.is_empty() else null


func _find_body_ancestor() -> CharacterBody3D:
	var ancestor := get_parent()
	while ancestor != null:
		var body := ancestor as CharacterBody3D
		if body != null:
			return body
		ancestor = ancestor.get_parent()
	return null
