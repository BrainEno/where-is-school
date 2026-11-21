extends RefCounted
## Rules for the two school terminal games. The desktop owns input, rendering and time.

class Minefield extends RefCounted:
	const SIDE := 9
	const MINE_COUNT := 10
	const COVERED := 0
	const FLAGGED := 1
	const OPEN := 2

	var cells := PackedByteArray()
	var mines: Array[Vector2i] = []
	var opened := 0
	var flags := 0
	var won := false
	var lost := false
	var _random := RandomNumberGenerator.new()

	func _init() -> void:
		reset()

	func reset(seed_value: int = -1) -> void:
		_random.randomize()
		if seed_value >= 0:
			_random.seed = seed_value
		cells.resize(SIDE * SIDE)
		cells.fill(COVERED)
		mines.clear()
		opened = 0
		flags = 0
		won = false
		lost = false

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < SIDE and cell.y < SIDE

	func at(cell: Vector2i) -> int:
		return cells[cell.y * SIDE + cell.x]

	func toggle_flag(cell: Vector2i) -> void:
		if won or lost or not in_bounds(cell) or at(cell) == OPEN:
			return
		var index := cell.y * SIDE + cell.x
		if cells[index] == FLAGGED:
			cells[index] = COVERED
			flags -= 1
		elif flags < MINE_COUNT:
			cells[index] = FLAGGED
			flags += 1

	func reveal(cell: Vector2i) -> void:
		if won or lost or not in_bounds(cell) or at(cell) != COVERED:
			return
		if mines.is_empty():
			_place_mines(cell)
		if mines.has(cell):
			lost = true
			return
		var queue: Array[Vector2i] = [cell]
		while not queue.is_empty():
			var next: Vector2i = queue.pop_back()
			if at(next) != COVERED:
				continue
			cells[next.y * SIDE + next.x] = OPEN
			opened += 1
			if nearby(next) == 0:
				for neighbor: Vector2i in _neighbors(next):
					if at(neighbor) == COVERED:
						queue.append(neighbor)
		won = opened == cells.size() - MINE_COUNT

	func nearby(cell: Vector2i) -> int:
		var count := 0
		for neighbor: Vector2i in _neighbors(cell):
			if mines.has(neighbor):
				count += 1
		return count

	func _neighbors(cell: Vector2i) -> Array[Vector2i]:
		var neighbors: Array[Vector2i] = []
		for y in range(-1, 2):
			for x in range(-1, 2):
				var neighbor := cell + Vector2i(x, y)
				if neighbor != cell and in_bounds(neighbor):
					neighbors.append(neighbor)
		return neighbors

	func _place_mines(first: Vector2i) -> void:
		var eligible: Array[Vector2i] = []
		for y in SIDE:
			for x in SIDE:
				if absi(x - first.x) > 1 or absi(y - first.y) > 1:
					eligible.append(Vector2i(x, y))
		for i in MINE_COUNT:
			var index := _random.randi_range(0, eligible.size() - 1)
			mines.append(eligible.pop_at(index))


class Snake extends RefCounted:
	const SIZE := Vector2i(16, 12)
	const START_LENGTH := 3

	var body: Array[Vector2i] = []
	var direction := Vector2i.RIGHT
	var food := Vector2i.ZERO
	var won := false
	var lost := false
	var _queued := Vector2i.ZERO
	var _random := RandomNumberGenerator.new()

	func _init() -> void:
		reset()

	func reset(seed_value: int = -1) -> void:
		_random.randomize()
		if seed_value >= 0:
			_random.seed = seed_value
		body.assign([Vector2i(5, 6), Vector2i(4, 6), Vector2i(3, 6)])
		direction = Vector2i.RIGHT
		_queued = Vector2i.ZERO
		won = false
		lost = false
		_place_food()

	func turn(next: Vector2i) -> void:
		if absi(next.x) + absi(next.y) == 1 and next != -direction \
				and next != direction and _queued == Vector2i.ZERO:
			_queued = next

	func step() -> void:
		if lost or won:
			return
		if _queued != Vector2i.ZERO:
			direction = _queued
			_queued = Vector2i.ZERO
		var head := body[0] + direction
		var eating := head == food
		if not Rect2i(Vector2i.ZERO, SIZE).has_point(head) \
				or (body.has(head) and (eating or head != body[-1])):
			lost = true
			return
		body.push_front(head)
		if eating:
			_place_food()
		else:
			body.pop_back()

	func score() -> int:
		return body.size() - START_LENGTH

	func _place_food() -> void:
		var available: Array[Vector2i] = []
		for y in SIZE.y:
			for x in SIZE.x:
				var cell := Vector2i(x, y)
				if not body.has(cell):
					available.append(cell)
		won = available.is_empty()
		food = Vector2i(-1, -1) if won else available[_random.randi_range(0, available.size() - 1)]
