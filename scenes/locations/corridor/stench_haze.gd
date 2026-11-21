extends CanvasLayer
## The smell of the stable behind 01 as a screen filter (docs/EXAM_DREAM_ART.md).
##
## The stink stable in the dream annex (`tools/build_dream_annex.py`) is dressing only: no
## script lives under it. This layer is the one moving part, and it sits in the corridor
## beside the annex. Each frame it measures how close the protagonist stands to the stall
## fronts and the muck heap and eases `stench` in `stench_haze.gdshader` toward that: a
## yellow-green riso cast, a wobbling and doubled frame, stink contours and an olive
## vignette, as if the smell were knocking him out. Walking away clears it the same way.
##
## **Layering.** A world filter (group `world_filter`) at layer -3: under the concussion
## paste-up (-2), the outline overlay and the UI. Hidden at 0, so the rest of the
## teaching block pays nothing for it.

## Where the smell comes from: the three stall fronts and the muck heap, on the yard (01).
const SOURCES: Array[Vector3] = [
	Vector3(-33.0, -3.4, 5.9),
	Vector3(-33.0, -3.4, 7.5),
	Vector3(-33.0, -3.4, 9.3),
	Vector3(-31.6, -3.4, 5.4),
]
## Full strength within this distance of a source (metres, on the ground plane).
const FULL_RANGE := 2.4
## Nothing beyond this distance: the lane mouth and the glass entrance are clear.
const FADE_RANGE := 9.5
## A point further than this above or below the yard is another floor and smells of nothing.
const FLOOR_BAND := 1.8
## How fast the drawn strength follows the walk, in strength per second.
const EASE_RATE := 1.5

@export var sheet_path: NodePath = ^"Sheet"
@export var player_group: StringName = &"protagonist"

var _sheet: ColorRect = null
var _player: Node3D = null
var _strength := 0.0


## The strength of the smell at a world point: 1 at the stalls, 0 past `FADE_RANGE`.
static func stench_at(point: Vector3) -> float:
	var nearest := INF
	for source in SOURCES:
		if absf(point.y - source.y) > FLOOR_BAND:
			continue
		nearest = minf(nearest, Vector2(point.x - source.x, point.z - source.z).length())
	if is_inf(nearest):
		return 0.0
	return 1.0 - smoothstep(FULL_RANGE, FADE_RANGE, nearest)


func _ready() -> void:
	_sheet = get_node_or_null(sheet_path) as ColorRect
	_apply(0.0)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
	var target := 0.0
	if _player != null and _player.is_inside_tree():
		target = stench_at(_player.global_position)
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
		material.set_shader_parameter(&"stench", value)
