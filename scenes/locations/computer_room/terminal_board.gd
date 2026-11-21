extends Control
## Pixel board with one physical input surface, separate from both games' rules.

const Rules = preload("res://scenes/locations/computer_room/terminal_games.gd")
const FACE := Color("d2cbc4")
const HIGHLIGHT := Color("fff3da")
const SHADOW := Color("6b6377")
const WELL := Color("211c36")
const MINE_INK := Color("6d294d")
const MINT := Color("92e0b4")
const PEACH := Color("ffaf8c")
const BLUE := Color("244772")
const CURSOR := Color("513796")
const FONT := preload("res://assets/fonts/NotoSansSC-Regular.ttf")

var minefield := Rules.Minefield.new()
var snake := Rules.Snake.new()
var mines_active := true
var flag_mode := false
var selected := Vector2i(4, 4)

signal action_taken


func redraw() -> void:
	queue_redraw()


func move_cursor(direction: Vector2i) -> void:
	var edge := Rules.Minefield.SIDE - 1
	selected = (selected + direction).clamp(Vector2i.ZERO, Vector2i(edge, edge))
	queue_redraw()


func act_on_selected(mark: bool = false) -> void:
	if mark:
		minefield.toggle_flag(selected)
	else:
		minefield.reveal(selected)
	queue_redraw()
	action_taken.emit()


func _gui_input(event: InputEvent) -> void:
	if not mines_active:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var bounds := _bounds(Vector2i.ONE * Rules.Minefield.SIDE, 31)
		if bounds.has_point(event.position):
			selected = Vector2i((event.position - bounds.position) / 31.0)
			act_on_selected(event.button_index == MOUSE_BUTTON_RIGHT or flag_mode)
			accept_event()


func _draw() -> void:
	if mines_active:
		_draw_mines()
	else:
		_draw_snake()


func _bounds(dimensions: Vector2i, cell: int) -> Rect2:
	var extent := Vector2(dimensions * cell)
	return Rect2(((size - extent) * 0.5).floor(), extent)


func _draw_mines() -> void:
	var side := Rules.Minefield.SIDE
	var bounds := _bounds(Vector2i.ONE * side, 31)
	draw_rect(bounds.grow(4), SHADOW)
	for y in side:
		for x in side:
			var cell := Vector2i(x, y)
			var position_px := bounds.position + Vector2(cell * 31)
			var tile := Rect2(position_px, Vector2(30, 30))
			var state := minefield.at(cell)
			var exposed := state == Rules.Minefield.OPEN
			draw_rect(tile, FACE if exposed else SHADOW)
			if not exposed:
				draw_rect(Rect2(tile.position, tile.size - Vector2(2, 2)), HIGHLIGHT)
				draw_rect(Rect2(tile.position + Vector2(2, 2), tile.size - Vector2(4, 4)), FACE)
			if (minefield.lost or minefield.won) and minefield.mines.has(cell):
				draw_circle(tile.get_center(), 6, MINE_INK)
			elif state == Rules.Minefield.FLAGGED:
				draw_colored_polygon(PackedVector2Array([position_px + Vector2(10, 7),
					position_px + Vector2(22, 12), position_px + Vector2(10, 17)]), MINE_INK)
				draw_line(position_px + Vector2(10, 7), position_px + Vector2(10, 23), WELL, 2)
			elif exposed and minefield.nearby(cell) > 0:
				var count := minefield.nearby(cell)
				draw_string(FONT, position_px + Vector2(0, 22), str(count),
					HORIZONTAL_ALIGNMENT_CENTER, 30, 18, BLUE if count < 3 else MINE_INK)
			if cell == selected and not minefield.won and not minefield.lost:
				draw_rect(tile.grow(-1), CURSOR, false, 2)


func _draw_snake() -> void:
	var bounds := _bounds(Rules.Snake.SIZE, 18)
	draw_rect(bounds.grow(4), SHADOW)
	draw_rect(bounds, WELL)
	for y in Rules.Snake.SIZE.y:
		for x in Rules.Snake.SIZE.x:
			draw_rect(Rect2(bounds.position + Vector2(x * 18 + 8, y * 18 + 8), Vector2(2, 2)), SHADOW)
	if not snake.won:
		var food_px := bounds.position + Vector2(snake.food * 18 + Vector2i(9, 9))
		draw_circle(food_px, 6, PEACH)
	for i in snake.body.size():
		var rect := Rect2(bounds.position + Vector2(snake.body[i] * 18) + Vector2(1, 1), Vector2(16, 16))
		draw_rect(rect, HIGHLIGHT if i == 0 else MINT)
		if i == 0:
			var eye := rect.get_center() + Vector2(snake.direction * 4)
			draw_rect(Rect2(eye - Vector2.ONE, Vector2(3, 3)), WELL)
