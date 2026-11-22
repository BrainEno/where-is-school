extends Control
## The thumb pad draws only; TouchActions owns the finger, PlayerController owns motion.

const DEAD_ZONE := 0.16

var _offset := Vector2.ZERO
var _engaged := false


func steer(point: Vector2) -> Vector2:
	_engaged = true
	var travel := size.x * 0.28
	var axis := ((point - size * 0.5) / travel).limit_length()
	_offset = axis * travel
	queue_redraw()
	var strength := axis.length()
	if strength <= DEAD_ZONE:
		return Vector2.ZERO
	return axis.normalized() * inverse_lerp(DEAD_ZONE, 1.0, strength)


func center_thumb() -> void:
	_engaged = false
	_offset = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.5
	if radius < 8.0:
		return
	var rim := Color(MenuStyle.OCHRE, 0.92) if _engaged else Color(MenuStyle.PAPER, 0.56)
	draw_circle(center, radius - 2.0, Color(MenuStyle.INK, 0.64), true, -1.0, true)
	draw_arc(center, radius - 2.0, 0.0, TAU, 64, rim, 2.0, true)
	for i in range(8):
		var tick := Vector2.from_angle(float(i) * TAU / 8.0)
		draw_line(center + tick * radius * 0.79, center + tick * radius * 0.88, rim, 2.0, true)
	var thumb := center + _offset
	draw_circle(thumb, radius * 0.33, Color(MenuStyle.INK, 0.95), true, -1.0, true)
	draw_arc(thumb, radius * 0.33, 0.0, TAU, 40, rim, 2.0, true)
	draw_circle(thumb, radius * 0.22, Color(MenuStyle.PAPER, 0.82), true, -1.0, true)
