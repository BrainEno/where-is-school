@tool
extends Node3D
## Photo study authored as cut, folded and rolled solid forms. +Z is the tube elevation.
## Meshes live under the layout nodes in the scene, so the building can be instanced without
## its presentation lights/camera. The scene owns no gameplay, imported textures or layout IO.

const CardMesh := preload("res://scenes/dev/folded_drum/card_mesh.gd")
const STOCK := preload("res://scenes/dev/folded_drum/card_stock.gdshader")
const PIGMENTS := {
	&"ivory": "eee1c4", &"chalk": "f4ebd4", &"cream": "d9c6a5", &"cut": "b29a78",
	&"shade": "877866", &"base": "bcb2a1", &"ink": "283346", &"glass": "263248",
	&"recess": "19242f", &"rib": "53525a", &"blue": "34488d", &"blue_light": "4763a9",
	&"teal": "376e72", &"dark_teal": "284f55", &"red": "ba4053", &"rose": "c75378",
	&"orange": "b95841", &"yellow": "dbad59", &"tube_inside": "74584d",
}
const FLOORS := [2.28, 4.08, 5.88]
const EAVE := 7.72

var _palette: Dictionary[StringName, Material] = {}


func _ready() -> void:
	for ink: StringName in PIGMENTS:
		var paper := ShaderMaterial.new()
		paper.resource_name = String(ink)
		paper.shader = STOCK
		paper.set_shader_parameter("pigment", Color.html(PIGMENTS[ink]))
		_palette[ink] = paper
	_site($Site)
	_front($FrontWing)
	_side($ScreenWing)
	_returns($Returns)
	_round_hall($RoundHall)
	_corner_tower($CornerTower)


func _site(parent: Node3D) -> void:
	var board := CardMesh.new()
	var outline := PackedVector2Array([
		Vector2(-11.36, -10.75), Vector2(7.30, -10.75), Vector2(8.94, -9.40),
		Vector2(8.94, 8.32), Vector2(7.65, 9.68), Vector2(-10.50, 9.68),
		Vector2(-12.02, 8.49), Vector2(-12.02, -9.98),
	])
	board.plate(outline, -0.46, -0.37, &"dark_teal", &"dark_teal")
	board.plate(outline, -0.37, 0.0, &"base", &"cut")
	board.plate(_rounded(Vector2(3.96, 5.35), Vector2(5.25, 7.78), 2.10),
		0.002, 0.026, &"teal", &"dark_teal")
	board.plate(_rounded(Vector2(5.8, -2.39), Vector2(5.18, 13.80), 0.77),
		0.003, 0.020, &"teal", &"dark_teal")
	board.plate(_rounded(Vector2(-6.18, 4.71), Vector2(9.8, 6.3), 0.37),
		0.005, 0.022, &"dark_teal", &"dark_teal")
	# Stacked ramp cheeks and a darker central run, not faces painted on the plinth.
	var ramp: Array[Vector2] = [Vector2(2.65, 0.038), Vector2(8.81, 0.038),
		Vector2(8.81, 0.084), Vector2(3.54, 1.45), Vector2(2.65, 1.45)]
	for i: int in 2:
		var x := -3.38 + i * 2.16
		board.prism_x(x - 0.98, x + 0.98, ramp, &"cut", [&"cut", &"chalk", &"ivory", &"chalk", &"cut"])
		board.face(&"shade" if i == 1 else &"cream", [
			Vector3(x - 0.58, 0.091, 8.81), Vector3(x + 0.58, 0.091, 8.81),
			Vector3(x + 0.58, 1.457, 3.54), Vector3(x - 0.58, 1.457, 3.54),
		], Vector3.UP)
	for i: int in 5:
		var tread := 4.55 + (4 - i) * 0.47
		var rise := 0.245
		board.box(Vector3((tread + 3.74) * 0.5, (i + 0.5) * rise + 0.02, 0.98),
			Vector3(tread - 3.74, rise, 2.96), &"ivory" if i % 2 == 0 else &"cream")
	board.box(Vector3(6.37, 0.26, -1.21), Vector3(2.03, 0.49, 0.69), &"cream")
	board.box(Vector3(6.12, 0.53, -1.21), Vector3(1.55, 0.08, 0.64), &"chalk")
	for i: int in 4:
		board.box(Vector3(6.88, 0.026, -3.43 - i * 1.45),
			Vector3(0.88, 0.018, 0.35), &"yellow")
	board.box(Vector3(-8.96, 0.05, 7.37), Vector3(0.53, 0.039, 0.91), &"yellow")
	board.commit(parent, "CutSiteBoard", _palette)


func _rounded(center: Vector2, size: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: int in 4:
		var angle := corner * PI * 0.5
		var sign_pair := Vector2.from_angle(angle + PI * 0.25).sign()
		var anchor := center + sign_pair * (size * 0.5 - Vector2.ONE * radius)
		for i: int in 9:
			points.append(anchor + Vector2.from_angle(angle + i * PI / 16.0) * radius)
	return points


func _front(parent: Node3D) -> void:
	var wall := CardMesh.new()
	wall.box(Vector3(0, 4.99, -1.92), Vector3(14.12, 5.42, 3.82), &"cream")
	for i: int in 4:
		var y: float = FLOORS[i] if i < FLOORS.size() else EAVE
		wall.box(Vector3(0, y, -1.62), Vector3(14.27, 0.25, 4.47), &"ivory")
		wall.box(Vector3(0, y + 0.135, 0.54), Vector3(14.19, 0.064, 0.24), &"chalk")
	for x: float in [-6.55, -4.55, -1.85, 1.16, 5.68, 6.56]:
		wall.box(Vector3(x, 1.14, -0.62), Vector3(0.54, 2.28, 1.48), &"cream")
		wall.box(Vector3(x, 0.17, -0.62), Vector3(0.71, 0.34, 1.56), &"cut")
	wall.box(Vector3(0.4, 1.1, -2.59), Vector3(12.8, 2.2, 0.18), &"ink")
	wall.box(Vector3(0.16, 1.48, -0.84), Vector3(4.08, 0.14, 3.0), &"cream")
	for y: float in FLOORS:
		_screen(wall, 2.72, 6.77, y + 0.19, y + 1.58, 17, true)
		_screen(wall, -6.83, -5.19, y + 0.18, y + 1.56, 6, true)
	wall.box(Vector3(2.47, 5.00, 0.26), Vector3(0.40, 5.57, 0.53), &"ivory")
	wall.box(Vector3(6.95, 5.00, 0.19), Vector3(0.43, 5.57, 0.46), &"chalk")
	wall.box(Vector3(-1.27, 3.02, 0.039), Vector3(7.38, 0.81, 0.18), &"recess")
	wall.box(Vector3(-1.26, 3.54, 0.21), Vector3(7.41, 0.20, 0.56), &"ivory")
	for i: int in 4:
		wall.box(Vector3(-4.62 + i * 1.85, 3.06, 0.15), Vector3(0.18, 0.88, 0.19), &"cut")
	_sign_panel(wall)
	wall.prism_x(-5.09, 2.25, [Vector2(0.01, 7.45), Vector2(1.18, 7.30),
		Vector2(1.23, 7.68), Vector2(0.23, 7.94)], &"cream", [&"cut", &"chalk", &"ivory", &"ivory"])
	for i: int in 4:
		var x := -3.22 + i * 1.04
		var drop := 5.97 + (0.26 if i == 0 or i == 3 else 0.0)
		wall.prism_x(x, x + 0.79, [Vector2(0.055, drop), Vector2(0.16, drop + 0.025),
			Vector2(0.78 + i * 0.041, 7.30), Vector2(0.045, 7.35)],
			&"cut", [&"orange", &"orange" if i % 2 == 0 else &"red", &"cut", &"orange"])
	for i: int in 3:
		var x := -6.78 + i * 1.39
		wall.prism_x(x, x + 0.81, [Vector2(0.33, 0.036), Vector2(1.64, 0.036),
			Vector2(2.89 - i * 0.22, 2.69), Vector2(0.34, 2.69)],
			&"cut", [&"cut", &"yellow" if i == 1 else &"shade", &"ivory", &"cream"])
		wall.roll([Vector2(0.72, 1.68), Vector2(0.81, 1.81), Vector2(0.82, 2.57),
			Vector2(0.79, 2.63)], [&"ink", &"blue", &"blue_light"],
			Vector3(x + 0.51, 0, 2.30 - i * 0.17), 1.05, 36)
	wall.commit(parent, "ArcadeAndFrontPanels", _palette)
	_folded_roof(parent, [-5.98, -3.41, -0.83, 1.75, 4.26], [0.48, 0.1, -0.03, 0.1, -0.20], true)
	_tube(parent, "LongTube", Vector3(3.52, 4.70, 0.10), Vector3(96.0, -1.6, 0), 6.29, 0.81)
	_tube(parent, "ShortTube", Vector3(-5.96, 4.75, 0.12), Vector3(95.0, -3.0, 0), 4.99, 0.73)


func _screen(mesh: CardMesh, low: float, high: float, sill: float, head: float,
		count: int, pale: bool = false) -> void:
	var width := high - low
	var height := head - sill
	var center := Vector3((low + high) / 2.0, (sill + head) / 2.0, 0.025)
	mesh.box(center, Vector3(width, height, 0.13), &"recess")
	mesh.box(center + Vector3(0.0, -0.052, 0.07), Vector3(width - 0.18, height - 0.21, 0.025), &"glass")
	for y: float in [sill, head]:
		mesh.box(Vector3(center.x, y, 0.16), Vector3(width + 0.16, 0.10, 0.33), &"cut" if pale else &"rib")
	for i: int in count + 1:
		var x := low + width * i / count
		mesh.box(Vector3(x, center.y, 0.20), Vector3(0.075 if pale else 0.087, height, 0.22),
			&"cream" if pale else &"rib")


func _sign_panel(mesh: CardMesh) -> void:
	var left := -3.89
	var right := 1.27
	var base_y := 4.35
	var top_y := 5.43
	var depth := 0.51
	mesh.box(Vector3((left + right) / 2.0, (base_y + top_y) / 2.0, depth - 0.116),
		Vector3(right - left, top_y - base_y, 0.232), &"chalk")
	for i: int in 10:
		var x := left - 0.68 + 0.64 * i
		var band: Array[Vector2] = [Vector2(x, base_y), Vector2(x + 0.34, base_y),
			Vector2(x + 1.05, top_y), Vector2(x + 0.71, top_y)]
		band = _clip_x(_clip_x(band, left, 1.0), right, -1.0)
		if band.size() < 3:
			continue
		var strip: Array[Vector3] = []
		for point: Vector2 in band:
			strip.append(Vector3(point.x, point.y, depth + 0.007))
		mesh.face(&"red", strip, Vector3.BACK)


func _clip_x(points: Array[Vector2], edge: float, sign_x: float) -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	for i: int in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var a_inside := (a.x - edge) * sign_x >= 0.0
		var b_inside := (b.x - edge) * sign_x >= 0.0
		if a_inside:
			clipped.append(a)
		if a_inside != b_inside:
			clipped.append(a.lerp(b, inverse_lerp(a.x, b.x, edge)))
	return clipped


func _side(parent: Node3D) -> void:
	var wall := CardMesh.new()
	wall.box(Vector3(0.03, 4.97, -1.83), Vector3(13.48, 5.53, 3.57), &"ink")
	wall.box(Vector3(0.00, 0.93, -1.83), Vector3(13.17, 1.86, 3.36), &"shade")
	for i: int in 4:
		var y: float = FLOORS[i] if i < FLOORS.size() else EAVE
		wall.box(Vector3(0.02, y, -1.44), Vector3(13.64, 0.27, 4.03), &"ivory")
		wall.box(Vector3(0.02, y + 0.14, 0.48), Vector3(13.59, 0.05, 0.26), &"chalk")
	for i: int in FLOORS.size():
		var y: float = FLOORS[i]
		_screen(wall, -6.34, -0.88 - i * 0.19, y + 0.16, y + 1.59, 22)
		for j: int in 4:
			var x := 0.11 + j * 1.65
			wall.box(Vector3(x + 0.72, y + 0.88, 0.031), Vector3(1.44, 1.40, 0.16),
				&"recess" if i < 2 else (&"rib" if j % 2 == 0 else &"tube_inside"))
			if i < 2:
				var ink: StringName = &"rose" if (i + j) % 3 != 1 else &"yellow"
				var depth := 0.98 + j * 0.08 - i * 0.14
				wall.prism_x(x + 0.10, x + 1.43, [Vector2(0.116, y + 0.24),
					Vector2(depth, y + 0.29), Vector2(0.13, y + 1.50)],
					&"blue", [&"blue_light", ink, &"ink"])
				var edge_ink: StringName = &"cream" if ink == &"yellow" else &"orange"
				wall.face(edge_ink, [Vector3(x + 0.10, y + 0.29, depth + 0.005),
					Vector3(x + 0.14, y + 0.29, depth + 0.005), Vector3(x + 0.14, y + 1.50, 0.135),
					Vector3(x + 0.10, y + 1.50, 0.135)], Vector3.BACK)
	wall.box(Vector3(-3.97, 1.16, -0.026), Vector3(2.83, 0.81, 0.165), &"recess")
	wall.box(Vector3(6.56, 5.0, 0.16), Vector3(0.39, 5.48, 0.63), &"cream")
	wall.commit(parent, "ScreenWallAndFoldedBays", _palette)
	_folded_roof(parent, [-4.95, -2.48, 0.01, 2.51, 5.01], [-0.48, -0.09, 0.10, 0.04, 0.31], false)
	var stanchion := CardMesh.new()
	_cup(stanchion, Vector3(-3.80, 0, 0.18), 7.69, 13.16, 0.44)
	stanchion.commit(parent, "LongPaperStanchion", _palette)


func _folded_roof(parent: Node3D, centers: Array[float], heights: Array[float], front: bool) -> void:
	var roof := CardMesh.new()
	for i: int in centers.size():
		var x := centers[i]
		var h := heights[i]
		var outer := 0.36 + 0.07 * (i % 2)
		var half_width := 1.105 if front else 1.03
		var edges: Array[StringName] = [&"cut", &"chalk" if i % 3 != 1 else &"ivory", &"ivory", &"cream", &"cream"]
		roof.prism_x(x - half_width, x + half_width, [Vector2(-3.52, 7.82), Vector2(outer, 7.82),
			Vector2(-0.59, 9.65 + h * 0.60), Vector2(-1.32, 10.44 + h),
			Vector2(-3.51, 8.99 + h * 0.38)], &"cream", edges)
		# Thin return at the long side of each sheet, and a small tab below the pitch.
		roof.prism_x(x + half_width - 0.09, x + half_width + 0.043, [Vector2(-0.01, 7.78),
			Vector2(outer + 0.067, 7.80), Vector2(-0.59, 9.67 + h * 0.60),
			Vector2(-1.32, 10.46 + h)], &"cream", [&"cut", &"ivory", &"chalk", &"cut"])
		roof.prism_x(x - 0.46, x - 0.28, [Vector2(-0.17, 7.83), Vector2(0.44, 7.83),
			Vector2(-0.004, 8.80 + 0.13 * (i % 2))], &"ivory", [&"cut", &"chalk", &"cream"])
	var end := -7.02 if front else 6.59
	roof.prism_x(end - 0.093, end + 0.10, [Vector2(-3.14, 7.80), Vector2(0.53, 7.80),
		Vector2(-1.37, 11.54 if front else 11.26), Vector2(-2.98, 9.12)],
		&"ivory", [&"cut", &"chalk", &"cream", &"ivory"])
	roof.commit(parent, "CutAndFoldedRoof", _palette)


func _tube(parent: Node3D, part_name: String, base: Vector3, aim: Vector3, length: float, r: float) -> void:
	var mount := CardMesh.new()
	var barrel := Node3D.new()
	barrel.name = part_name
	barrel.position = base
	barrel.rotation_degrees = aim
	parent.add_child(barrel, false, Node.INTERNAL_MODE_BACK)
	mount.roll([Vector2(r + 0.22, -0.18), Vector2(r + 0.22, 0.09),
		Vector2(r + 0.15, 0.25), Vector2(r * 0.92, 0.30)],
		[&"cut", &"cream", &"ivory"], Vector3.ZERO, 1.0, 48)
	mount.commit(barrel, "ReinforcedSocket", _palette)
	var model := CardMesh.new()
	model.roll([Vector2(r, 0.20), Vector2(r, length - 0.16), Vector2(r + 0.055, length - 0.15),
		Vector2(r + 0.055, length - 0.055), Vector2(r + 0.016, length), Vector2(r - 0.073, length),
		Vector2(r - 0.105, length - 0.085), Vector2(r - 0.105, length - 0.28),
		Vector2(r - 0.105, length - 1.2), Vector2(r - 0.09, 0.31)],
		[&"ink", &"red", &"red", &"red", &"red", &"red", &"tube_inside", &"tube_inside", &"recess"],
		Vector3.ZERO, 1.0, 64)
	# Layers of pasted paper wrap the shell as polygons; their edges follow the actual barrel.
	_arc(model, Vector3.ZERO, r + 0.013, 0.29, length - 0.17, 3, 27, &"cream", 64)
	_arc(model, Vector3.ZERO, r + 0.018, 0.35, length - 0.18, 20, 23, &"ivory", 64)
	_arc(model, Vector3.ZERO, r + 0.011, 0.46, length - 0.19, 40, 42, &"rib", 64)
	model.commit(barrel, "OpenCardboardBarrel", _palette)


func _arc(mesh: CardMesh, offset: Vector3, radius: float, bottom: float, top: float,
		start: int, end: int, ink: StringName, sides: int) -> void:
	for i: int in range(start, end):
		var a := Vector2.from_angle(TAU * i / sides)
		var b := Vector2.from_angle(TAU * (i + 1) / sides)
		var na := Vector3(a.x, 0, a.y)
		var nb := Vector3(b.x, 0, b.y)
		var p := offset + na * radius
		var q := offset + nb * radius
		mesh.face(ink, [p + Vector3.UP * bottom, q + Vector3.UP * bottom, q + Vector3.UP * top,
			p + Vector3.UP * top], na, [na, nb, nb, na])


func _cup(mesh: CardMesh, xz: Vector3, low: float, high: float, r: float) -> void:
	mesh.roll([Vector2(r - 0.025, low), Vector2(r, low + 0.045), Vector2(r, high - 0.04),
		Vector2(r - 0.02, high), Vector2(r - 0.071, high), Vector2(r - 0.093, high - 0.055),
		Vector2(r - 0.093, high - 0.39)],
		[&"cream", &"ivory", &"chalk", &"chalk", &"cream", &"shade"], xz, 1.0, 40)


func _round_hall(parent: Node3D) -> void:
	var tower := CardMesh.new()
	tower.roll([Vector2(2.96, 2.0), Vector2(3.10, 7.43), Vector2(2.89, 9.62),
		Vector2(3.23, 10.36), Vector2(4.0, 11.13)], [&"shade", &"ink", &"recess", &"ink"])
	tower.roll([Vector2(3.9, 10.88), Vector2(4.17, 11.10), Vector2(4.19, 11.98),
		Vector2(4.10, 12.09), Vector2(3.84, 12.09)], [&"cut", &"ivory", &"chalk", &"cream"],
		Vector3.ZERO, 1.0, 64)
	tower.roll([Vector2(3.865, 12.055), Vector2(3.865, 12.90)], [&"glass"], Vector3.ZERO, 1.0, 64)
	tower.roll([Vector2(3.81, 12.80), Vector2(4.18, 12.86), Vector2(4.17, 13.07),
		Vector2(3.95, 13.17)], [&"cream", &"ivory", &"chalk"], Vector3.ZERO, 1.0, 64)
	for i: int in 8:
		_arc(tower, Vector3.ZERO, 3.881, 12.13, 12.24, i * 8 + 1, i * 8 + 7, &"blue_light", 64)
		var angle := TAU * i / 8.0
		var p := Vector2.from_angle(angle) * 3.86
		tower.box(Vector3(p.x, 12.47, p.y), Vector3(0.24, 0.84, 0.24), &"cream")
	# Slightly raised, individually cut petals on the lid, with narrow seams down to the skin.
	for i: int in 6:
		var angle := TAU * i / 6.0
		var loop := PackedVector2Array()
		loop.append(Vector2.from_angle(angle + 0.045) * 0.74)
		for j: int in 7:
			loop.append(Vector2.from_angle(angle + lerpf(0.021, TAU / 6.0 - 0.025, j / 6.0)) * 3.81)
		loop.append(Vector2.from_angle(angle + TAU / 6.0 - 0.058) * 0.74)
		tower.plate(loop, 13.162, 13.237 + (i % 3) * 0.066,
			&"ivory" if i % 2 == 0 else &"chalk", &"cream")
	tower.roll([Vector2(0.96, 13.17), Vector2(0.96, 13.31), Vector2(0.78, 13.44)], [&"cream", &"ivory"])
	tower.commit(parent, "RaisedDrumAndClerestory", _palette)
	var vents := CardMesh.new()
	for i: int in 5:
		var point := Vector2.from_angle(deg_to_rad([7.0, 59.0, 133.0, 206.0, 274.0][i])) * 3.41
		_cup(vents, Vector3(point.x, 0, point.y), 11.03 if i == 1 else 12.91,
			[14.04, 13.96, 14.21, 14.34, 13.88][i], [0.50, 0.59, 0.55, 0.49, 0.53][i])
	vents.commit(parent, "RolledRoofVents", _palette)


func _corner_tower(parent: Node3D) -> void:
	var stack := CardMesh.new()
	stack.roll([Vector2(0.96, 0.024), Vector2(1.10, 0.11), Vector2(1.24, 1.01)],
		[&"ink", &"blue"], Vector3.ZERO, 1.16, 56)
	var start := 0.79
	var heights := [1.59, 1.44, 1.37, 1.32, 1.49]
	for i: int in heights.size():
		var r := 1.66 - i * 0.081
		var top: float = start + heights[i]
		var offset := Vector3(-i * 0.050, 0, -i * 0.115)
		stack.roll([Vector2(r - 0.16, start), Vector2(r - 0.012, start + 0.16),
			Vector2(r - 0.006, top - 0.34), Vector2(r + 0.065, top - 0.20),
			Vector2(r + 0.065, top - 0.078), Vector2(r - 0.014, top)],
			[&"cut", &"ivory", &"ivory", &"cream", &"chalk"], offset, 1.12, 56)
		if i < heights.size() - 1:
			stack.roll([Vector2(r - 0.32, top - 0.06), Vector2(r - 0.32, top + 0.19)],
				[&"shade"], offset, 1.12, 48)
		start = top + 0.042
	stack.commit(parent, "FiveRoundedStoreys", _palette)
	var spine := Node3D.new()
	spine.name = "FoldedConnector"
	spine.position = Vector3(-0.40, 0, -0.43)
	spine.rotation_degrees.y = 35.0
	parent.add_child(spine, false, Node.INTERNAL_MODE_BACK)
	var elbow := CardMesh.new()
	var outside := [Vector2(0.83, 7.57), Vector2(0.33, 9.21),
		Vector2(-0.82, 10.75), Vector2(-3.98, 11.43)]
	var inside := [Vector2(-0.77, 7.57), Vector2(-0.96, 9.04),
		Vector2(-1.53, 9.95), Vector2(-3.98, 10.52)]
	for i: int in 3:
		elbow.prism_x(-0.94, 0.94, [inside[i], outside[i], outside[i + 1], inside[i + 1]],
			&"ivory", [&"cream", &"chalk", &"cream", &"shade"])
	elbow.commit(spine, "BentPaperBox", _palette)


func _returns(parent: Node3D) -> void:
	var rear := CardMesh.new()
	rear.box(Vector3(-2.70, 3.52, -8.28), Vector3(12.36, 7.04, 2.84), &"cream")
	rear.box(Vector3(-7.52, 3.25, -3.07), Vector3(3.05, 6.50, 9.72), &"ivory")
	rear.box(Vector3(-1.10, 3.40, -5.23), Vector3(7.03, 6.80, 3.32), &"shade")
	rear.box(Vector3(-2.70, 7.16, -8.21), Vector3(12.48, 0.28, 3.15), &"ivory")
	rear.box(Vector3(-7.52, 6.59, -3.12), Vector3(3.34, 0.28, 10.07), &"chalk")
	for i: int in 6:
		var x := -7.55 + i * 1.76
		rear.box(Vector3(x, 5.23, -9.692), Vector3(1.42, 1.32, 0.12), &"ink")
		rear.box(Vector3(x, 4.54, -9.77), Vector3(1.53, 0.12, 0.31), &"chalk")
		if i % 2 == 0:
			rear.box(Vector3(x, 7.47, -8.62), Vector3(1.23, 0.62, 1.36), &"chalk")
	for i: int in 4:
		var z := -6.90 + i * 2.05
		rear.box(Vector3(-9.06, 4.75, z), Vector3(0.091, 1.39, 1.66), &"glass")
		rear.box(Vector3(-9.13, 4.02, z), Vector3(0.29, 0.11, 1.73), &"cream")
	rear.box(Vector3(-6.04, 1.42, -9.73), Vector3(2.23, 2.53, 0.20), &"blue")
	rear.box(Vector3(-4.15, 0.22, -10.04), Vector3(6.34, 0.44, 0.74), &"cream")
	rear.box(Vector3(-4.48, 0.061, -10.49), Vector3(6.95, 0.12, 0.30), &"dark_teal")
	rear.commit(parent, "QuietServiceReturns", _palette)
