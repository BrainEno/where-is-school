extends CanvasLayer
## The trip inside the building under construction, as a screen filter
## (`site_trip_haze.gdshader`; the room is written by `tools/build_site_interior.py`).
##
## Nothing in the room carries a script except this layer and the key. Each frame it eases
## `trip` toward a floor that holds everywhere in the room, plus more the closer the
## protagonist stands to the column of light the scaffold stands in. Entering, it rises from
## nothing over a couple of seconds, so the room seems to come on rather than to be there.
##
## **Layering.** A world filter (group `world_filter`) at layer -3, like the stable's stench:
## under the concussion paste-up (-2), the outline overlay and the UI. Hidden at 0.

## Strength everywhere in the room.
const FLOOR := 0.42
## Strength standing at the foot of the scaffold.
const PEAK := 1.0
## Full strength within this distance of the column (metres, on the ground plane)...
const FULL_RANGE := 1.8
## ...and only the floor beyond this one.
const FADE_RANGE := 7.0
## How fast the drawn strength follows the walk, in strength per second.
const EASE_RATE := 0.45

## The column's centre, in the room's frame (set by the generator).
@export var column: Vector3 = Vector3.ZERO
@export var sheet_path: NodePath = ^"Sheet"
@export var player_group: StringName = &"protagonist"

var _sheet: ColorRect = null
var _player: Node3D = null
var _strength := 0.0


## The strength at a point in the room's frame: the floor, rising to `PEAK` at the column.
static func trip_at(local_point: Vector3, column_point: Vector3) -> float:
	var away := Vector2(local_point.x - column_point.x, local_point.z - column_point.z).length()
	return lerpf(FLOOR, PEAK, 1.0 - smoothstep(FULL_RANGE, FADE_RANGE, away))


func _ready() -> void:
	_sheet = get_node_or_null(sheet_path) as ColorRect
	_apply(0.0)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
	var room := get_parent() as Node3D
	var target := FLOOR
	if _player != null and _player.is_inside_tree() and room != null:
		target = trip_at(room.to_local(_player.global_position), column)
	_strength = move_toward(_strength, target, EASE_RATE * delta)
	_apply(_strength)


## The strength drawn this frame (eased), for tests and captures.
func get_strength() -> float:
	return _strength


func _apply(value: float) -> void:
	visible = value > 0.002
	if _sheet == null:
		return
	var material := _sheet.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"trip", value)
