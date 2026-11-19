class_name PushableChair
extends Node3D
## The wake chair is solid only at the pushed stop, while nobody is using it. Its
## layer (3) blocks the capsule, not the nav bake or picking. The performance owns
## the progress of the slide; the prop owns both stops and the collision boundary.

const PUSH_BACK_DISTANCE := 0.65
const SOLID_LAYER := 4

var _home_position: Vector3
var _pushed_position: Vector3
var _pushed := false
var _cue_pending := false

@onready var _body: StaticBody3D = get_node_or_null(^"Solid")
@onready var seat_mark: Marker3D = get_node_or_null(^"SeatMark")
@onready var _seat: MeshInstance3D = $Seat


func _ready() -> void:
	_home_position = position
	_pushed_position = position + basis.z * PUSH_BACK_DISTANCE
	_set_solid(false)


func is_pushed_back() -> bool:
	return _pushed


## The standing capsule's floor mark, not the centre of the seat mesh. It does not
## move with the slide, and there is just enough room for the capsule at this spot.
func home_mark() -> Vector3:
	return seat_mark.global_position + get_parent_node_3d().global_basis * (_home_position - position)


func seat_surface_height() -> float:
	return (_seat.global_transform * _seat.get_aabb()).end.y


## Wrist above the near corner of the seat, rather than on the wood where the
## hand itself goes. The moving mesh owns the point at every phase of the slide.
func grip_point() -> Vector3:
	return _seat.to_global(Vector3(0.218, 0.073, -0.197))


func start_slide() -> void:
	_cue_pending = true
	_set_solid(false)


func sample_slide(fraction: float) -> void:
	var previous := position
	position = _home_position.lerp(_pushed_position, clampf(fraction, 0.0, 1.0))
	# One cue when the chair actually starts moving; snaps and repeated samples
	# (including resuming a paused beat) never trigger a new scrape.
	if _cue_pending and not previous.is_equal_approx(position):
		_cue_pending = false
		var audio := get_node_or_null(^"/root/WorldAudio")
		if audio != null:
			audio.call(&"play_chair")


func snap_back() -> void:
	_cue_pending = false
	_pushed = true
	sample_slide(1.0)
	_set_solid(true)


func snap_home() -> void:
	_cue_pending = false
	_pushed = false
	sample_slide(0.0)
	_set_solid(false)


func _set_solid(solid: bool) -> void:
	if _body == null:
		return
	for shape in _body.get_children():
		var collider := shape as CollisionShape3D
		if collider != null:
			collider.set_deferred("disabled", not solid)
	_body.set_deferred("collision_layer", SOLID_LAYER if solid else 0)
