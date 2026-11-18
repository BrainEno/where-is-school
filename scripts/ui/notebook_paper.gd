class_name NotebookPaper
extends Control
## The dialogue band's ground: a sheet torn out of an exercise book, with the set square's
## corner lying over its top-left corner.
##
## This is the dialogue strip of the biology-classroom experiment (its torn paper and ink
## wedge; see docs/BIOLOGY_CLASSROOM_EXPERIMENT.md) brought to the production panel: warm white
## paper with torn top and bottom edges, pale blue rules, a red margin line, and the set
## square as an ink-blue wedge with its pale hole drawn inside it.
##
## It is drawn, not a texture: the band's size is measured from the text it holds
## (`DialoguePanel._settle_layout`), so the sheet is redrawn to whatever rect it is given.
## The tear is seeded, so the same size always tears the same way. The rules follow the
## body's own line pitch (`set_rules`), so the sentence sits on them as handwriting would.
##
## It never takes a click (the band itself does, see `DialoguePanel._make_band_clickable`).
## The set square lies over the band's top-left corner, its long leg down the sheet's left
## edge and its short leg along the top, overhanging both edges. The portrait sits over its
## top end; the rest stays in the strip the text column never uses, left of the red margin.

const PAPER := Color(0.93, 0.9, 0.82, 1.0)
## The sheet's lower edge, a shade darker where the paper curls a little away from the light.
const PAPER_FOOT := Color(0.88, 0.845, 0.76, 1.0)
const SHADOW := Color(0.02, 0.02, 0.05, 0.36)
const RULE := Color(0.55, 0.65, 0.82, 0.62)
const MARGIN := Color(0.8, 0.38, 0.36, 0.7)
## The set square, as the experiment drew it: ink blue, nearly opaque.
const WEDGE := Color(0.12, 0.1, 0.22, 0.94)
const WEDGE_HOLE := Color(0.88, 0.83, 0.7, 0.85)
const WEDGE_TICK := Color(0.88, 0.83, 0.7, 0.6)

## Horizontal spacing of the tear's points, and how far the tear wanders.
const TEAR_STEP := 18.0
const TEAR_DEPTH := 4.0
const SHADOW_OFFSET := Vector2(5.0, 7.0)

## The red margin line, from the band's left edge. The text column starts to its right.
@export var margin_x: float = 24.0
## Where the first rule is drawn and the distance between rules (the body's line pitch).
@export var rule_top: float = 64.0
@export var rule_pitch: float = 38.0
## The set square: the two legs of its right angle, and where that corner sits relative to
## the band's top-left corner (negative: past it, over the edge of the sheet).
@export var wedge_legs: Vector2 = Vector2(74.0, 150.0)
@export var wedge_corner: Vector2 = Vector2(-34.0, -30.0)
@export var tear_seed: int = 5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


## Lines the rules up with the body text: the first rule under the first line, then one per
## line pitch, down to the torn bottom edge.
func set_rules(top: float, pitch: float) -> void:
	pitch = maxf(pitch, 12.0)
	if is_equal_approx(top, rule_top) and is_equal_approx(pitch, rule_pitch):
		return
	rule_top = top
	rule_pitch = pitch
	queue_redraw()


## The sheet's outline in local coordinates: torn along the top and bottom, cut straight
## down the sides.
func sheet_outline() -> PackedVector2Array:
	var outline := PackedVector2Array()
	var width := maxf(size.x, 1.0)
	var height := maxf(size.y, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = tear_seed
	var steps := maxi(int(ceilf(width / TEAR_STEP)), 2)
	var drift := 0.0
	for step in steps + 1:
		drift = lerpf(drift, rng.randf_range(-TEAR_DEPTH, TEAR_DEPTH), 0.5)
		outline.append(Vector2(width * step / steps, TEAR_DEPTH + drift))
	drift = 0.0
	for step in range(steps, -1, -1):
		drift = lerpf(drift, rng.randf_range(-TEAR_DEPTH, TEAR_DEPTH), 0.5)
		outline.append(Vector2(width * step / steps, height - TEAR_DEPTH + drift))
	return outline


## The set square's triangle (the right angle first), in local coordinates.
func wedge_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		wedge_corner,
		wedge_corner + Vector2(wedge_legs.x, 0.0),
		wedge_corner + Vector2(0.0, wedge_legs.y),
	])


func _draw() -> void:
	# Before the band is measured the rect can be a sliver; a torn outline that small would
	# cross itself, and there is nothing to read on it yet.
	if size.x < TEAR_STEP * 3.0 or size.y < TEAR_DEPTH * 8.0:
		return
	var outline := sheet_outline()
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + SHADOW_OFFSET)
	draw_colored_polygon(shadow, SHADOW)
	draw_colored_polygon(outline, PAPER)
	var height := size.y
	var width := size.x
	# The foot of the sheet: a faint darker band along the torn bottom (the outline's second
	# half runs along it, right to left).
	var foot_top := height - TEAR_DEPTH * 5.0
	var foot := PackedVector2Array([Vector2(width, foot_top)])
	for index in range(outline.size() >> 1, outline.size()):
		foot.append(outline[index])
	foot.append(Vector2(0.0, foot_top))
	draw_colored_polygon(foot, Color(PAPER_FOOT, 0.55))
	# Pale blue rules at the body's line pitch, inside the torn edges.
	var y := rule_top
	var last := height - TEAR_DEPTH * 3.0
	while y < last:
		if y > TEAR_DEPTH * 3.0:
			draw_line(Vector2(6.0, y), Vector2(width - 6.0, y), RULE, 1.0)
		y += rule_pitch
	# The red margin line, top to bottom.
	draw_line(
		Vector2(margin_x, TEAR_DEPTH * 2.5), Vector2(margin_x, height - TEAR_DEPTH * 2.5), MARGIN, 1.5
	)
	_draw_wedge()


## The set square over the corner: the ink wedge, the pale outline of its hole, and the
## ruler ticks along its top edge.
func _draw_wedge() -> void:
	var triangle := wedge_polygon()
	draw_colored_polygon(triangle, WEDGE)
	# A pale edge, so the ink still reads where it hangs over the dark scene.
	var edge := PackedVector2Array(triangle)
	edge.append(triangle[0])
	draw_polyline(edge, WEDGE_TICK, 1.5, true)
	var corner := wedge_corner
	var legs := wedge_legs
	# The hole: the same triangle, a third of the size, set in from the right angle.
	var inset := Vector2(legs.x * 0.2, legs.y * 0.28)
	var hole := PackedVector2Array([
		corner + inset,
		corner + inset + Vector2(legs.x * 0.42, 0.0),
		corner + inset + Vector2(0.0, legs.y * 0.42),
		corner + inset,
	])
	draw_polyline(hole, WEDGE_HOLE, 2.0, true)
	# Ruler ticks along the long leg, every 8 px, every fourth one longer.
	var along_x := legs.x >= legs.y
	var reach := maxf(legs.x, legs.y) * 0.78
	var tick := 0
	var at := 10.0
	while at < reach:
		var length := 7.0 if tick % 4 == 0 else 4.0
		if along_x:
			draw_line(corner + Vector2(at, 2.0), corner + Vector2(at, 2.0 + length), WEDGE_TICK, 1.0)
		else:
			draw_line(corner + Vector2(2.0, at), corner + Vector2(2.0 + length, at), WEDGE_TICK, 1.0)
		at += 8.0
		tick += 1
