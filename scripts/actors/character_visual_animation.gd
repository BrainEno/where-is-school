class_name CharacterVisualAnimation
extends Node3D
## The one animation state machine every authored character uses.
##
## Hangs off a character wrapper (`protagonist.tscn`, `q.tscn`), builds that model's clips
## with `CharacterAnimation.bind()` on an `AnimationPlayer` of its own, and decides each frame
## which clip the character holds. Three things can hold a clip, in this order of precedence:
##
##   1. an *action*: a one-shot transition (`get_up`), started by `play_action()`, which owns
##      the body until its clip reports `animation_finished` and then hands back;
##   2. *seated*: `set_seated(true)` holds `sit_idle` and ignores the body's velocity,
##      because a character sitting on a chair is not walking no matter what the capsule does.
##      The wake beat uses this: the protagonist starts slumped at a desk;
##   3. *locomotion*: `idle`, `walk` or `jog`, from the planar velocity the character's own
##      controller already produces. It is the same decision for everyone:
##
##   the player, WASD           PlayerController._apply_movement()    -> body velocity
##   the player, click-to-move  PlayerController._path_direction()    -> body velocity
##   Q following                CompanionController._apply_movement() -> body velocity
##   an NPC walking a route     NpcActor.walk_along()                 -> reported velocity
##
##   all four                   -> _update_locomotion()
##
## No controller has a second, animation-only notion of "moving". A `CharacterBody3D` reports
## its velocity *after* `move_and_slide()`, so a body pressed against a wall reads as still
## and stands instead of walking on the spot. The locomotion decision keeps running while an
## action or the seated pose holds the clip, so the character resumes in the right state.
##
## What this node never does: write a transform. The clips are bone-rotation tracks on the
## skeleton and nothing else (no root motion, no yaw, no position), so the controller's
## facing (`VisualPivot` for the player, the actor's own rotation for an NPC) and the wake
## beat's slump stay exactly where the controller put them.

signal locomotion_changed(state: StringName)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_JOG := &"jog"
## The clip a seated character holds.
const SEATED_CLIP := "sit_idle"

## Planar speed (m/s) above which a standing character starts walking...
@export_range(0.01, 2.0, 0.01) var walk_enter_speed: float = 0.2
## ...and below which a walking one stops. The gap is the hysteresis that keeps a body that
## is just settling (the last few centimetres of a deceleration) from flickering between clips.
@export_range(0.0, 2.0, 0.01) var walk_exit_speed: float = 0.08
## Above this horizontal speed, walking becomes jogging. `PlayerController.move_speed` is
## 3.6 m/s and its sprint speed 5.6, so 4.4 sits between the two: a walker accelerating
## towards a sprint passes through `walk` for a moment, and an `NpcActor` (1.6 m/s) never
## gets near it.
@export_range(0.5, 12.0, 0.1) var jog_speed_threshold: float = 4.4
## A jogging character drops back to walking below this, so a speed hovering at the
## threshold (Q catching up runs at exactly 4.4) does not alternate between the two clips.
@export_range(0.5, 12.0, 0.1) var jog_exit_speed: float = 4.0
## The ground speed the walk clip is authored for at playback speed 1. Faster characters play
## it faster so the feet keep roughly in step with the ground instead of skating.
@export_range(0.3, 6.0, 0.05) var stride_speed: float = 1.6
## The same for the jog clip.
@export_range(0.5, 12.0, 0.1) var jog_stride_speed: float = 5.0
@export_range(0.1, 2.0, 0.05) var min_walk_playback: float = 0.7
@export_range(0.5, 4.0, 0.05) var max_walk_playback: float = 1.9
## Cross-fade between locomotion clips, in seconds. Every clip keys every animated bone, so
## the fade always has a pose to fade *to*. Actions and the seated pose cut: `get_up` starts
## on exactly the pose `sit_idle` holds.
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
var _seated := false
var _action := ""
var _state: StringName = STATE_IDLE
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
	_player.animation_finished.connect(_on_animation_finished)
	print("CharacterVisualAnimation: %s — %s" % [name, CharacterAnimation.describe(_bind_report)])
	if _body == null:
		_body = _find_body_ancestor()
	_show(String(STATE_IDLE), 0.0)


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


## Holds the seated pose until `set_seated(false)`. Ignored while an action is playing; the
## state is remembered and applied when the action ends.
func set_seated(seated: bool) -> void:
	_seated = seated
	if _bound and _action.is_empty():
		_show(_resume_clip(), 0.0 if seated else blend_time)


func is_seated() -> bool:
	return _seated


## Plays a transition clip once. Returns false when this rig cannot play it, so a caller can
## fall back instead of freezing in the last frame of a clip that is not there.
func play_action(clip_name: String) -> bool:
	if not _bound:
		return false
	if not CharacterAnimation.play(_player, clip_name, 0.0):
		return false
	_player.speed_scale = 1.0
	_action = clip_name
	_current_clip = clip_name
	return true


func is_playing_action() -> bool:
	return not _action.is_empty()


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


## The whole locomotion rule, shared by every character. Public so a test can feed it a
## velocity directly and get the same answer the game would.
func _update_locomotion(planar_velocity: Vector3) -> void:
	_planar_speed = Vector2(planar_velocity.x, planar_velocity.z).length()
	var next := _next_state(_state, _planar_speed)
	if next != _state:
		_state = next
		_transitions += 1
		locomotion_changed.emit(_state)
	# An action or the seated pose owns the clip; the decision above still ran, so the
	# character comes out of either into what its body is doing now.
	if not _action.is_empty() or _seated:
		return
	_show(String(_state), blend_time)
	_player.speed_scale = playback_for(_state, _planar_speed)


func _next_state(state: StringName, speed: float) -> StringName:
	match state:
		STATE_JOG:
			if speed < walk_exit_speed:
				return STATE_IDLE
			if speed < jog_exit_speed:
				return STATE_WALK
		STATE_WALK:
			if speed < walk_exit_speed:
				return STATE_IDLE
			if speed > jog_speed_threshold:
				return STATE_JOG
		_:
			if speed > jog_speed_threshold:
				return STATE_JOG
			if speed > walk_enter_speed:
				return STATE_WALK
	return state


## Playback speed of a locomotion clip for a ground speed: 1 for idle, the stride ratio for
## walk and jog.
func playback_for(state: StringName, speed: float) -> float:
	if state == STATE_WALK:
		return walk_playback_for(speed)
	if state == STATE_JOG:
		return clampf(speed / maxf(jog_stride_speed, 0.01), 0.8, 1.4)
	return 1.0


## Playback speed of the walk clip for a ground speed.
func walk_playback_for(speed: float) -> float:
	return clampf(speed / maxf(stride_speed, 0.01), min_walk_playback, max_walk_playback)


## The clip that follows an action or the seated pose: sitting if the character still is,
## otherwise whatever the body is doing.
func _resume_clip() -> String:
	return SEATED_CLIP if _seated else String(_state)


func _on_animation_finished(clip_name: StringName) -> void:
	if _action.is_empty():
		return
	if String(clip_name) != "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), _action]:
		return
	_action = ""
	_show(_resume_clip(), blend_time)
	_player.speed_scale = 1.0 if _seated else playback_for(_state, _planar_speed)


func _show(clip_name: String, blend: float) -> void:
	if clip_name == _current_clip:
		return
	if not CharacterAnimation.play(_player, clip_name, blend):
		return
	_current_clip = clip_name
	if clip_name == SEATED_CLIP or clip_name == String(STATE_IDLE):
		_player.speed_scale = 1.0


# --- Read-outs --------------------------------------------------------------


## The locomotion decision (`idle`, `walk`, `jog`), whatever clip currently holds the body.
func get_locomotion_state() -> StringName:
	return _state


## The clip actually playing: an action, `sit_idle`, or the locomotion clip.
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
