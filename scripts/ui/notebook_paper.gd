extends Control
## Presentation only: a cut notebook leaf beneath the measured dialogue layout.
## No texture imports, animation, input handling or narrative state.

const PAPER := Color("f7f4eb")
const INK := Color("49424d")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	# Two offset leaves, not a rounded notification card.
	draw_rect(Rect2(Vector2(5, 7), size), Color(0.08, 0.06, 0.12, 0.22))
	draw_rect(Rect2(Vector2(3, 3), size), Color("c9c1b3"))
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_line(Vector2(24, 7), Vector2(24, size.y - 8), Color(0.61, 0.27, 0.24, 0.3), 1.0)
	# Very quiet ruling: it must never compete with long Chinese prose.
	for y in range(54, int(size.y) - 12, 32):
		draw_line(Vector2(31, y), Vector2(size.x - 16, y), Color(0.25, 0.34, 0.42, 0.065))
	for y in range(27, int(size.y) - 8, 40):
		draw_circle(Vector2(12, y), 2.3, Color("b4aaa0"), true, -1.0, true)
	# The damaged wooden set square is a corner device, outside the text column.
	var outer := PackedVector2Array([Vector2(-13, -24), Vector2(43, -20), Vector2(-10, 36)])
	draw_colored_polygon(outer, Color("bfa16c"))
	draw_polyline(PackedVector2Array([outer[0], outer[1], outer[2], outer[0]]), INK, 1.4, true)
	var inner := PackedVector2Array([Vector2(-2, -12), Vector2(22, -10), Vector2(-1, 15)])
	draw_colored_polygon(inner, PAPER)
	draw_polyline(PackedVector2Array([inner[0], inner[1], inner[2], inner[0]]), INK, 1.0, true)
	for x in range(-5, 32, 6):
		draw_line(Vector2(x, -22), Vector2(x, -17), INK, 1.0, true)
	draw_line(Vector2(-12, 22), Vector2(-1, 19), Color("ded0aa"), 7.0, true)
	# An imperfect cut along the bottom edge, kept out of the content padding.
	for x in range(8, int(size.x) - 8, 19):
		draw_line(Vector2(x, size.y), Vector2(x + 8, size.y - 1), Color("b9b0a3"), 1.0)
