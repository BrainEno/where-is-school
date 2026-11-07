class_name NpcActor
extends Node3D
## Graybox person blockout for Q and N.
##
## Silhouette and placement do the work: no facial animation, no collision. An
## actor can be hidden until an authored beat brings them in, and walk along
## markers the location provides.

@export var npc_id: StringName = &""
## Development label only; the UI gets names from CharacterProfile.
@export var debug_name: String = ""
@export var body_color: Color = Color(0.63, 0.6, 0.54, 1.0)
@export var walk_speed: float = 1.5

var _body: MeshInstance3D = null
var _head: MeshInstance3D = null


func _ready() -> void:
	_body = get_node_or_null(^"Body") as MeshInstance3D
	_head = get_node_or_null(^"Head") as MeshInstance3D
	if _body == null:
		push_error("NpcActor '%s' needs a MeshInstance3D child named 'Body'." % debug_name)
	_apply_color(body_color)


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


## Walks through the given points in order, turning at each one. Awaiting this
## function resolves when the actor reaches the last point.
func walk_along(points: Array) -> void:
	if points.is_empty():
		return
	for point: Vector3 in points:
		var distance := global_position.distance_to(point)
		if distance <= 0.01:
			continue
		face_towards(point)
		var duration := maxf(distance / maxf(walk_speed, 0.01), 0.05)
		var tween := create_tween()
		tween.tween_property(self, "global_position", point, duration)
		await tween.finished
