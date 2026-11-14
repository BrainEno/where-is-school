class_name NpcActor
extends Node3D
## A person in a location: Q, N, or the companion that follows the player.
##
## Silhouette and placement do the work: no facial animation, no collision. An
## actor can be hidden until an authored beat brings them in, and walk along
## markers the location provides.
##
## The graybox capsule and head are the default. An actor that has an authored
## model names it in `visual_scene`; the model becomes a child called `Visual` and
## the graybox parts are hidden rather than deleted, so the node paths every other
## system knows keep existing. The model is a *visual*: the body that collides is
## whatever parents the actor (a `CharacterBody3D`, for the companion), exactly as
## `docs/ASSET_PIPELINE.md` §10 asks. Q and N both have one; an actor that leaves it
## empty stays a graybox.

@export var npc_id: StringName = &""
## Development label only; the UI gets names from CharacterProfile.
@export var debug_name: String = ""
@export var body_color: Color = Color(0.63, 0.6, 0.54, 1.0)
@export var walk_speed: float = 1.5
## An authored visual, instanced under this actor instead of the graybox capsule.
## Leave empty for the blockout.
@export var visual_scene: PackedScene = null
## Yaw for the instanced visual, in degrees, around its own vertical axis.
##
## `face_towards()` follows the pipeline's convention that a model looks down −Z.
## Q and the protagonists look down +Z (`docs/ASSET_PIPELINE.md` §10.2), so their
## visual is turned 180° here — at the placement, in one place, on the visual node
## only. The GLB and this actor's own rotation stay untouched, which is what keeps
## a re-export from having two corrections to undo. Set 0 for a −Z model: N is one.
@export_range(-180.0, 180.0, 1.0) var visual_yaw_degrees: float = 180.0

## How quickly the body turns to help a watch the neck alone cannot make, and back.
const WATCH_TURN_SPEED := 5.0

var _body: MeshInstance3D = null
var _head: MeshInstance3D = null
var _visual: Node3D = null
var _nameplate: CharacterNameplate = null
## Watching someone (`watch()`): who, how high their eyes are, and the head-turn modifier.
var _gaze: NpcGaze = null
var _watch_target: Node3D = null
var _watch_height := 1.55
## The body's share of a watch: the yaw it rests at, the one it last wrote, and whether it
## is still the watch's to turn (a beat that turns the actor itself takes it back).
var _rest_yaw := 0.0
var _written_yaw := 0.0
var _body_turn_active := false


func _ready() -> void:
	# Grouped so a test can count how many of a given person exist in the tree: the
	# companion and an authored actor must never both be visible.
	add_to_group("npc_actor")
	_body = get_node_or_null(^"Body") as MeshInstance3D
	_head = get_node_or_null(^"Head") as MeshInstance3D
	if _body == null:
		push_error("NpcActor '%s' needs a MeshInstance3D child named 'Body'." % debug_name)
	_apply_color(body_color)
	_build_visual()
	# The label already exists in the actor scene; it only needs to know who it is
	# labelling. Doing it here means a new actor instance gets a name by setting
	# `npc_id`, with no extra node to wire up in the location scene.
	_nameplate = get_node_or_null(^"Nameplate") as CharacterNameplate
	if _nameplate != null and String(_nameplate.character_id).is_empty():
		_nameplate.character_id = npc_id
		_nameplate.refresh()
	# Only a watch turns the body every frame (see `watch()`).
	set_process(false)


## Instances the authored model, if this actor has one, and retires the graybox.
##
## The graybox parts are hidden, not freed: `Body` and `Head` are what the actor has
## always exposed, and a scene or a test that looks them up should find them and be
## able to ask why they are not drawn.
func _build_visual() -> void:
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if instance == null:
		push_error("NpcActor '%s' could not instantiate its visual_scene." % debug_name)
		return
	_visual = instance as Node3D
	if _visual == null:
		push_error("NpcActor '%s' has a visual_scene whose root is not a Node3D." % debug_name)
		instance.queue_free()
		return
	_visual.name = "Visual"
	_visual.rotation_degrees.y = visual_yaw_degrees
	add_child(_visual)
	if _body != null:
		_body.visible = false
	if _head != null:
		_head.visible = false


## The authored visual, or null while this actor is still a graybox.
func get_visual() -> Node3D:
	return _visual


func _apply_color(color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var material_copy := material
	if _body != null:
		_body.material_override = material_copy
	if _head != null:
		_head.material_override = material_copy


func set_visible_actor(is_visible: bool) -> void:
	visible = is_visible


## Places the actor at an entrance point without animating.
func place_at(position_point: Vector3, facing_point: Vector3 = Vector3.ZERO) -> void:
	global_position = position_point
	if not facing_point.is_zero_approx():
		face_towards(facing_point)
	visible = true


func face_towards(target_point: Vector3) -> void:
	var offset := target_point - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	rotation.y = atan2(offset.x, offset.z) + PI


## Turns towards `target_point` by at most a share of the way this frame, instead of
## snapping. Same convention as `face_towards()` (the half turn for a −Z model); used by the
## companion while it walks, so a corner of its route is a turn and not a jump.
func turn_towards(target_point: Vector3, delta: float, turn_speed: float) -> void:
	var offset := target_point - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	var target_angle := atan2(offset.x, offset.z) + PI
	rotation.y = lerp_angle(rotation.y, target_angle, clampf(turn_speed * delta, 0.0, 1.0))


## Looks at `target` - its eyes `height` metres above its origin - and keeps following it
## until `stop_watching()`.
##
## The head and neck turn first (`NpcGaze`, after the animation); only an angle past their
## reach turns the body, by the remainder. Where the actor stands, its route, its
## animation and every collider stay as they are, so a watch can begin and end at any
## moment without the scene noticing. Letting go eases the head back and returns the body
## to the yaw it had, unless a beat has turned the actor in the meantime: then the beat's
## facing is kept.
func watch(target: Node3D, height: float = 1.55) -> void:
	if target == null:
		return
	if not _body_turn_active:
		_rest_yaw = rotation.y
	_written_yaw = rotation.y
	_body_turn_active = true
	_watch_target = target
	_watch_height = height
	var gaze := _ensure_gaze()
	if gaze != null:
		gaze.look_at_node(target, height)
	set_process(true)


func stop_watching() -> void:
	_watch_target = null
	if _gaze != null:
		_gaze.let_go()


func is_watching() -> bool:
	return _watch_target != null and is_instance_valid(_watch_target)


## The head-turn modifier, or null for an actor without a skeleton (a graybox turns its
## whole body instead).
func get_gaze() -> NpcGaze:
	return _gaze


## The way this actor faces on the floor: `-Z`, the convention `face_towards()` keeps.
func get_facing_direction() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.000001 else Vector3.FORWARD


func _process(delta: float) -> void:
	if not _body_turn_active:
		set_process(false)
		return
	# Something else turned the actor (a beat's `face_towards()`, `walk_along()`): the
	# body is the story's again, and the watch keeps only the head.
	if absf(angle_difference(rotation.y, _written_yaw)) > 0.001:
		_body_turn_active = false
		return
	var target_yaw := _rest_yaw
	if is_watching():
		var offset := _watch_target.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() > 0.0001:
			var turn := angle_difference(_rest_yaw, atan2(offset.x, offset.z) + PI)
			var reach := deg_to_rad(_gaze.reach_degrees) if _gaze != null else 0.0
			if absf(turn) > reach:
				target_yaw = _rest_yaw + turn - signf(turn) * reach
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(WATCH_TURN_SPEED * delta, 0.0, 1.0))
	if not is_watching() and absf(angle_difference(rotation.y, _rest_yaw)) < 0.002:
		rotation.y = _rest_yaw
		_body_turn_active = false
	_written_yaw = rotation.y


func _ensure_gaze() -> NpcGaze:
	if _gaze != null and is_instance_valid(_gaze):
		return _gaze
	var animator := get_character_animator()
	var skeleton := animator.get_skeleton() if animator != null else null
	if skeleton == null:
		return null
	_gaze = NpcGaze.new()
	_gaze.name = "Gaze"
	_gaze.setup(self)
	skeleton.add_child(_gaze)
	return _gaze


## The locomotion animator of the authored visual, or null for a graybox actor.
func get_character_animator() -> CharacterVisualAnimation:
	return _visual as CharacterVisualAnimation


## Walks through the given points in order, turning at each one. Awaiting this
## function resolves when the actor reaches the last point.
##
## A tween has no physics velocity, so each leg reports the velocity it is actually moving at
## to the visual's animator — the same idle/walk rule the player and the companion use, fed
## the same kind of number.
func walk_along(points: Array) -> void:
	if points.is_empty():
		return
	for point: Vector3 in points:
		var distance := global_position.distance_to(point)
		if distance <= 0.01:
			continue
		face_towards(point)
		var duration := maxf(distance / maxf(walk_speed, 0.01), 0.05)
		_report_visual_velocity((point - global_position) / duration)
		var tween := create_tween()
		tween.tween_property(self, "global_position", point, duration)
		await tween.finished
	_end_visual_report()


func _report_visual_velocity(velocity: Vector3) -> void:
	var animator := get_character_animator()
	if animator != null:
		animator.report_velocity(velocity)


func _end_visual_report() -> void:
	var animator := get_character_animator()
	if animator != null:
		animator.clear_reported_velocity()
