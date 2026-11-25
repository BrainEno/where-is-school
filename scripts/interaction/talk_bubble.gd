class_name TalkBubble
extends Control
## The talk mark of a person: a small speech bubble drawn on the screen beside the pointer.
##
## It replaces the first version, a bubble over the person's head: a head-high mark made the
## player look up from the pointer to find it, so the mark moves to where the pointer already
## is. The rule:
##
## * while the pointer is on the person, the bubble's tail touches the pointer and the bubble
##   sits up and to the right of it, so it moves with the cursor and never covers the spot
##   being pointed at;
## * when the person is the target without the pointer on them (the keyboard facing the
##   person, a controller), the tail touches the point above their head instead.
##
## The bubble is one shared node per scene tree, like `OutlineOverlay`: a `HoverCue` claims it
## with `set_bubble(owner, anchor, opacity)` while it is the talk target and gives it back with
## `release(owner)`. A late release from a previous owner is ignored, so a hand-over never
## hides the new bubble. It lives on its own `CanvasLayer` under the root, below the HUD and the
## dialogue, and it ignores the mouse, so it can never swallow a click on the world.
##
## Every size is in pixels at a 900-pixel-high window and scales with the window height, as the
## ring does. The shape is built in code (`shape_points`) so the geometry can be tested and so
## the bubble can be mirrored when it would run off the right edge of the screen.

const GROUP := &"talk_bubble"
## Layer 0 draws with the world, below the HUD (layer 1) and the dialogue.
const LAYER := 0
const REFERENCE_HEIGHT := 900.0
const BODY_WIDTH := 26.0
const BODY_HEIGHT := 18.0
const CORNER_RADIUS := 4.0
## The tail: its tip sits this far left of and below the body's lower-left corner.
const TAIL_GAP_X := 3.0
const TAIL_GAP_Y := 8.0
## Where the tail leaves the bottom edge, measured from the body's left edge.
const TAIL_BASE_START := 6.0
const TAIL_BASE_END := 12.0
const ARC_STEPS := 6
const EDGE_WIDTH := 1.8
const HALO_WIDTH := 3.4
const DOT_RADIUS := 1.7
const DOT_SPACING := 5.0
const BREATH_SECONDS := 1.8
## The pointer counts as being on the person this far outside their screen box too.
const POINTER_MARGIN := 12.0
## Keep the bubble this far inside the screen edge before it is mirrored.
const SCREEN_MARGIN := 4.0
const PAPER := Color(0.96, 0.98, 0.93)
const INK := Color(0.04, 0.08, 0.05)
## The same green as the look ring (`Palette.LOOK_GREEN`), so the two marks read as one set.
const GREEN := Palette.LOOK_GREEN
const SHADOW := Color(0.0, 0.0, 0.0, 0.22)

static var _fallback: WeakRef = null

var _owner_id: int = 0
var _anchor := Vector2.ZERO
var _opacity: float = 0.0
var _time: float = 0.0


## The bubble serving `node`'s tree: the one already in the tree, otherwise one created under the
## root for this run. Null when `node` is not in a tree.
static func for_node(node: Node) -> TalkBubble:
	if node == null or not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	var found := tree.get_first_node_in_group(GROUP) as TalkBubble
	if found != null and not found.is_queued_for_deletion():
		return found
	if _fallback != null:
		var pending := _fallback.get_ref() as TalkBubble
		if pending != null and is_instance_valid(pending) and not pending.is_queued_for_deletion():
			return pending
	var holder := CanvasLayer.new()
	holder.name = "TalkBubbleLayer"
	holder.layer = LAYER
	var created := TalkBubble.new()
	created.name = "TalkBubble"
	holder.add_child(created)
	_fallback = weakref(created)
	# Deferred: the request usually arrives from inside a physics step, where the root may be busy.
	tree.root.add_child.call_deferred(holder)
	return created


## Where the tail touches: the pointer when it is on the person's screen box (with a margin),
## otherwise the point above their head. Pure, so the rule can be tested without a window.
static func choose_anchor(pointer: Vector2, person_box: Rect2, above_head: Vector2) -> Vector2:
	if person_box.size != Vector2.ZERO and person_box.grow(POINTER_MARGIN).has_point(pointer):
		return pointer
	return above_head


## The body of the bubble, in screen pixels, for a tail touching `anchor`. `unit` is the window
## height over 900. Mirrored puts the body up and to the left of the anchor instead.
static func body_rect(anchor: Vector2, unit: float, mirrored: bool) -> Rect2:
	var width := BODY_WIDTH * unit
	var height := BODY_HEIGHT * unit
	var gap_x := TAIL_GAP_X * unit
	var gap_y := TAIL_GAP_Y * unit
	var left := anchor.x + gap_x
	if mirrored:
		left = anchor.x - gap_x - width
	return Rect2(Vector2(left, anchor.y - gap_y - height), Vector2(width, height))


## The closed outline of the bubble, body and tail as one polygon, clockwise on screen. The tail
## tip is exactly `anchor`, so tests and the pointer rule can rely on it.
static func shape_points(anchor: Vector2, unit: float, mirrored: bool) -> PackedVector2Array:
	var body := body_rect(anchor, unit, mirrored)
	var width := body.size.x
	var height := body.size.y
	var radius := CORNER_RADIUS * unit
	var x0 := TAIL_BASE_START * unit
	var x1 := TAIL_BASE_END * unit
	# Built in a frame whose origin is the body's top-left corner; mirrored afterwards.
	var local := PackedVector2Array()
	_append_arc(local, Vector2(radius, radius), radius, 180.0, 270.0)
	_append_arc(local, Vector2(width - radius, radius), radius, 270.0, 360.0)
	_append_arc(local, Vector2(width - radius, height - radius), radius, 0.0, 90.0)
	local.append(Vector2(x1, height))
	local.append(Vector2(-TAIL_GAP_X * unit, height + TAIL_GAP_Y * unit))
	local.append(Vector2(x0, height))
	_append_arc(local, Vector2(radius, height - radius), radius, 90.0, 180.0)
	var shape := PackedVector2Array()
	for point in local:
		var x := width - point.x if mirrored else point.x
		shape.append(body.position + Vector2(x, point.y))
	return shape


## The three dots of the bubble's body, left to right.
static func dot_centres(anchor: Vector2, unit: float, mirrored: bool) -> PackedVector2Array:
	var body := body_rect(anchor, unit, mirrored)
	var centre := body.get_center()
	var spacing := DOT_SPACING * unit
	return PackedVector2Array([
		centre + Vector2(-spacing, 0.0),
		centre,
		centre + Vector2(spacing, 0.0),
	])


static func _append_arc(
	points: PackedVector2Array, centre: Vector2, radius: float, from_degrees: float, to_degrees: float
) -> void:
	for step in range(ARC_STEPS + 1):
		var degrees := lerpf(from_degrees, to_degrees, float(step) / float(ARC_STEPS))
		var angle := deg_to_rad(degrees)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)


## Claims the bubble for `owner` (a `HoverCue`), tail at `anchor`, at `opacity`.
func set_bubble(owner: Object, anchor: Vector2, opacity: float) -> void:
	if owner == null:
		return
	_owner_id = owner.get_instance_id()
	_anchor = anchor
	_opacity = clampf(opacity, 0.0, 1.0)
	queue_redraw()


## Gives the bubble back. Ignored when `owner` is not the one showing it.
func release(owner: Object) -> void:
	if owner == null or _owner_id != owner.get_instance_id():
		return
	_owner_id = 0
	_opacity = 0.0
	queue_redraw()


func is_showing_for(owner: Object) -> bool:
	return owner != null and _owner_id != 0 and _owner_id == owner.get_instance_id() \
		and _opacity > 0.0


func get_anchor() -> Vector2:
	return _anchor


func get_opacity() -> float:
	return _opacity


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _owner_id != 0 and _opacity > 0.0:
		queue_redraw()


func _draw() -> void:
	if _owner_id == 0 or _opacity <= 0.0:
		return
	var screen := size if size.y > 0.0 else get_viewport_rect().size
	var unit := screen.y / REFERENCE_HEIGHT
	var body := body_rect(_anchor, unit, false)
	var mirrored := body.end.x > screen.x - SCREEN_MARGIN * unit
	var shape := shape_points(_anchor, unit, mirrored)
	var closed := shape.duplicate()
	closed.append(shape[0])
	var alpha := _opacity
	var shadow := PackedVector2Array()
	for point in shape:
		shadow.append(point + Vector2(unit, unit * 1.5))
	draw_colored_polygon(shadow, Color(SHADOW, SHADOW.a * alpha))
	draw_polyline(closed, Color(INK, alpha), HALO_WIDTH * unit, true)
	draw_colored_polygon(shape, Color(PAPER, 0.96 * alpha))
	draw_polyline(closed, Color(GREEN, alpha), EDGE_WIDTH * unit, true)
	var breath := 0.5 + 0.5 * sin(_time * TAU / BREATH_SECONDS)
	var radius := DOT_RADIUS * unit * (0.9 + 0.2 * breath)
	for centre in dot_centres(_anchor, unit, mirrored):
		draw_circle(centre, radius, Color(GREEN, alpha))
