extends RefCounted
## Every picture the biology classroom experiment paints for itself, generated at load
## time so the experiment carries no image files: the shadow on the front wall, the set
## square's shadow on the floor, the red pencil ring, the outline of the book that is not
## there, the chalk ghosts on the board, the two wall charts, the clock face, the cut-out
## classmates, the torn paper of the dialogue strip, the washing and the trees outside.
##
## Shapes are filled with the visual lab's scissor fill (`collage_kit.gd`): each span's
## ends drift a pixel or two from row to row, so an edge reads as cut, not rasterised.
## Marks are white with an alpha silhouette; the `ink_mark` shader tints them.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

static var _bytes: int = 0
static var _count: int = 0


static func generated_bytes() -> int:
	return _bytes


static func generated_count() -> int:
	return _count


static func _blank(size: Vector2i, fill: Color = Color(1, 1, 1, 0)) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return image


static func _done(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	_bytes += image.get_data_size()
	_count += 1
	return ImageTexture.create_from_image(image)


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A pencil line that goes round: `turns` > 1 overlaps itself, the way a hand circles.
static func _circle_stroke(
	image: Image, centre: Vector2, radius: float, width: float, colour: Color,
	rng: RandomNumberGenerator, turns: float = 1.0, wobble: float = 3.0
) -> void:
	var steps := int(radius * TAU * turns / 3.0) + 8
	var previous := Vector2.ZERO
	var drift := 0.0
	for step in steps + 1:
		var angle := TAU * turns * float(step) / float(steps) - 0.6
		drift = lerpf(drift, rng.randf_range(-wobble, wobble), 0.08)
		var reach := radius + drift + float(step) / float(steps) * width * 1.5
		var point := centre + Vector2(cos(angle), sin(angle)) * reach
		if step > 0:
			Kit.stroke(image, previous, point, width, colour, rng)
		previous = point


static func _polyline(
	image: Image, points: PackedVector2Array, width: float, colour: Color,
	rng: RandomNumberGenerator
) -> void:
	for index in range(1, points.size()):
		Kit.stroke(image, points[index - 1], points[index], width, colour, rng)


# --- Marks (white, alpha only; tinted by ink_mark.gdshader) ------------------------------


## The shadow on the front wall that no one in the room casts: tall, stooped, the head
## thrust forward with a long hard nose, a bun, one arm out holding a set square. Twice
## the height of a person. Only an impression: no face, no hands, no feet.
static func b_shadow() -> ImageTexture:
	var rng := _rng(1951)
	var image := _blank(Vector2i(512, 1024))
	var ink := Color(1, 1, 1, 1)
	var coat := PackedVector2Array([
		Vector2(150, 360), Vector2(116, 420), Vector2(124, 560), Vector2(146, 640),
		Vector2(112, 1018), Vector2(372, 1018), Vector2(336, 640), Vector2(318, 420),
		Vector2(300, 340), Vector2(214, 318)
	])
	var neck := PackedVector2Array([
		Vector2(250, 236), Vector2(318, 226), Vector2(324, 340), Vector2(236, 352)
	])
	var upper_arm := PackedVector2Array([
		Vector2(286, 352), Vector2(318, 336), Vector2(392, 446), Vector2(366, 466)
	])
	var forearm := PackedVector2Array([
		Vector2(366, 466), Vector2(392, 446), Vector2(452, 352), Vector2(430, 336)
	])
	var nose := PackedVector2Array([Vector2(360, 178), Vector2(452, 214), Vector2(356, 230)])
	var square := PackedVector2Array([Vector2(408, 344), Vector2(508, 344), Vector2(408, 206)])
	var square_hole := PackedVector2Array([
		Vector2(424, 328), Vector2(468, 328), Vector2(424, 266)
	])
	for polygon: PackedVector2Array in [coat, neck, upper_arm, forearm, nose, square]:
		Kit.fill_polygon(image, polygon, ink, rng, 2.5)
	Kit.fill_polygon(image, Kit.ellipse(Vector2(308, 200), Vector2(60, 64)), ink, rng, 2.5)
	Kit.fill_polygon(image, Kit.ellipse(Vector2(244, 150), Vector2(36, 30)), ink, rng, 2.5)
	Kit.fill_polygon(image, square_hole, Color(1, 1, 1, 0), rng, 1.0)
	return _done(image)


## The set square's shadow on the floor: a long thin triangle with its hole, base at the
## bottom of the image (the lectern end) and the point at the top (the player's desk).
static func set_square_shadow() -> ImageTexture:
	var rng := _rng(7)
	var image := _blank(Vector2i(128, 512))
	var outer := PackedVector2Array([Vector2(8, 508), Vector2(124, 508), Vector2(18, 6)])
	var hole := PackedVector2Array([Vector2(28, 470), Vector2(86, 470), Vector2(32, 170)])
	Kit.fill_polygon(image, outer, Color(1, 1, 1, 1), rng, 1.6)
	Kit.fill_polygon(image, hole, Color(1, 1, 1, 0), rng, 1.0)
	return _done(image)


## A red pencil going round, twice, the way a mark is circled on a paper.
static func ring() -> ImageTexture:
	var rng := _rng(0)
	var image := _blank(Vector2i(256, 256))
	_circle_stroke(image, Vector2(128, 130), 104.0, 5.0, Color(1, 1, 1, 1), rng, 1.18, 4.0)
	_circle_stroke(image, Vector2(126, 128), 96.0, 3.0, Color(1, 1, 1, 0.8), rng, 0.55, 3.0)
	return _done(image)


## Where the textbook should be: a dashed rectangle, the outline of an absence.
static func book_outline() -> ImageTexture:
	var rng := _rng(42)
	var image := _blank(Vector2i(256, 192))
	var corners := PackedVector2Array([
		Vector2(20, 22), Vector2(236, 18), Vector2(238, 172), Vector2(18, 170)
	])
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		var length := a.distance_to(b)
		var dashes := int(length / 22.0)
		for dash in dashes:
			var t0 := float(dash) / float(dashes)
			var t1 := t0 + 0.55 / float(dashes)
			Kit.stroke(image, a.lerp(b, t0), a.lerp(b, t1), 4.0, Color(1, 1, 1, 1), rng)
	# The spine: one heavier line down the middle, as if the book had lain open.
	Kit.stroke(image, Vector2(128, 26), Vector2(127, 166), 2.0, Color(1, 1, 1, 0.7), rng)
	return _done(image)


## Half-erased chalk: a plant cell, a leaf and its veins, the bones of a wing, a column
## of short strokes where a list was, and the grey smear an eraser leaves.
static func chalk_ghosts() -> ImageTexture:
	var rng := _rng(311)
	var image := _blank(Vector2i(1024, 320))
	var chalk := Color(1, 1, 1, 0.85)
	var faint := Color(1, 1, 1, 0.3)
	for band in 7:
		var y := rng.randf_range(30.0, 290.0)
		var x := rng.randf_range(0.0, 600.0)
		Kit.stroke(image, Vector2(x, y), Vector2(x + rng.randf_range(160, 380), y + rng.randf_range(-8, 8)), 22.0, Color(1, 1, 1, 0.08), rng)
	# The cell.
	var cell := Kit.ellipse(Vector2(170, 165), Vector2(120, 92), 40)
	cell.append(cell[0])
	_polyline(image, cell, 4.0, chalk, rng)
	_circle_stroke(image, Vector2(196, 150), 26.0, 3.0, chalk, rng, 1.05, 2.0)
	for organelle in 5:
		var at := Vector2(rng.randf_range(90, 260), rng.randf_range(110, 225))
		Kit.stroke(image, at, at + Vector2(rng.randf_range(14, 30), rng.randf_range(-6, 6)), 3.0, faint, rng)
	# The leaf and its veins.
	var leaf := PackedVector2Array([
		Vector2(400, 260), Vector2(380, 180), Vector2(420, 90), Vector2(470, 60),
		Vector2(500, 120), Vector2(480, 210), Vector2(400, 260)
	])
	_polyline(image, leaf, 3.5, chalk, rng)
	Kit.stroke(image, Vector2(400, 260), Vector2(472, 70), 2.5, chalk, rng)
	for vein in 4:
		var t := 0.25 + 0.17 * float(vein)
		var on := Vector2(400, 260).lerp(Vector2(472, 70), t)
		Kit.stroke(image, on, on + Vector2(-34, -10), 2.0, faint, rng)
		Kit.stroke(image, on, on + Vector2(30, 6), 2.0, faint, rng)
	# A wing: the long bones and the feathers' quills, mostly wiped.
	var wing := PackedVector2Array([
		Vector2(600, 210), Vector2(680, 150), Vector2(760, 170), Vector2(860, 120)
	])
	_polyline(image, wing, 4.0, chalk, rng)
	for quill in 7:
		var root := wing[2].lerp(wing[3], float(quill) / 7.0)
		Kit.stroke(image, root, root + Vector2(10.0 + 6.0 * quill, 70.0 - 4.0 * quill), 2.0, faint, rng)
	# A list of names, reduced to strokes.
	for row in 8:
		var y := 40.0 + 30.0 * float(row)
		Kit.stroke(image, Vector2(930, y), Vector2(930 + rng.randf_range(30, 70), y), 3.0, faint, rng)
	return _done(image)


# --- Pictures (opaque paper) -------------------------------------------------------------


## A biology plate: the skeleton of a bird's wing, labelled with ruled blanks.
static func wing_chart() -> ImageTexture:
	var rng := _rng(88)
	var image := _blank(Vector2i(256, 336), Color(0.84, 0.78, 0.64, 1))
	var ink := Color(0.2, 0.17, 0.2, 1)
	var bones := PackedVector2Array([
		Vector2(40, 250), Vector2(96, 180), Vector2(150, 196), Vector2(220, 120)
	])
	_polyline(image, bones, 5.0, ink, rng)
	Kit.stroke(image, Vector2(96, 180), Vector2(150, 206), 3.0, ink, rng)
	for feather in 9:
		var root := bones[2].lerp(bones[3], float(feather) / 9.0)
		Kit.stroke(image, root, root + Vector2(-20.0 + feather * 3.0, 110.0 - feather * 6.0), 2.0, ink, rng)
	for joint: Vector2 in bones:
		_circle_stroke(image, joint, 6.0, 2.0, ink, rng, 1.0, 0.5)
	image.fill_rect(Rect2i(24, 22, 208, 26), Color(0.2, 0.17, 0.2, 1))
	for row in 3:
		Kit.stroke(image, Vector2(30, 290 + row * 14), Vector2(200, 290 + row * 14), 1.0, ink, rng)
	return _done(image)


## A biology plate: a plant cell, the one the board was trying to draw.
static func cell_chart() -> ImageTexture:
	var rng := _rng(89)
	var image := _blank(Vector2i(256, 336), Color(0.8, 0.84, 0.74, 1))
	var ink := Color(0.16, 0.24, 0.2, 1)
	image.fill_rect(Rect2i(40, 70, 176, 210), Color(0.62, 0.74, 0.5, 1))
	var wall := PackedVector2Array([
		Vector2(40, 70), Vector2(216, 70), Vector2(216, 280), Vector2(40, 280), Vector2(40, 70)
	])
	_polyline(image, wall, 4.0, ink, rng)
	Kit.fill_polygon(image, Kit.ellipse(Vector2(150, 140), Vector2(30, 26)), Color(0.42, 0.36, 0.5, 1), rng)
	for plastid in 6:
		var at := Vector2(rng.randf_range(64, 196), rng.randf_range(190, 260))
		Kit.fill_polygon(image, Kit.ellipse(at, Vector2(12, 6)), Color(0.3, 0.5, 0.26, 1), rng)
	image.fill_rect(Rect2i(24, 22, 208, 26), ink)
	return _done(image)


static func clock_face() -> ImageTexture:
	var rng := _rng(12)
	var image := _blank(Vector2i(128, 128))
	Kit.fill_polygon(image, Kit.ellipse(Vector2(64, 64), Vector2(60, 60), 40), Color(0.2, 0.18, 0.22, 1), rng, 0.5)
	Kit.fill_polygon(image, Kit.ellipse(Vector2(64, 64), Vector2(54, 54), 40), Color(0.9, 0.86, 0.76, 1), rng, 0.5)
	for tick in 12:
		var angle := TAU * float(tick) / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		Kit.stroke(image, Vector2(64, 64) + direction * 44.0, Vector2(64, 64) + direction * 51.0, 3.0, Color(0.2, 0.18, 0.22, 1), rng)
	return _done(image)


## A classmate seen from behind, cut from a magazine: shoulders, the back of a head, a
## uniform. No face; nobody turns round.
static func classmate(uniform_colour: Color, hair: Color, seed_value: int) -> ImageTexture:
	var rng := _rng(seed_value)
	var image := _blank(Vector2i(256, 320))
	var lean := rng.randf_range(-10.0, 10.0)
	var body := PackedVector2Array([
		Vector2(78 + lean, 150), Vector2(178 + lean, 150), Vector2(206, 230), Vector2(214, 318),
		Vector2(42, 318), Vector2(50, 230)
	])
	Kit.cut_out(image, body, uniform_colour, rng, 6.0)
	var head := Kit.ellipse(Vector2(128 + lean * 1.4, 96), Vector2(46, 54))
	Kit.cut_out(image, head, hair, rng, 6.0)
	Kit.fill_polygon(image, PackedVector2Array([
		Vector2(108 + lean, 150), Vector2(148 + lean, 150), Vector2(128 + lean, 168)
	]), Color(0.95, 0.94, 0.9, 1), rng)
	Kit.stroke(image, Vector2(128 + lean, 170), Vector2(126, 318), 2.0, uniform_colour.darkened(0.35), rng)
	return _done(image)


## The torn strip the dialogue sits on.
static func dialogue_paper() -> ImageTexture:
	var rng := _rng(5)
	var image := _blank(Vector2i(640, 160))
	var outline := PackedVector2Array()
	var top_drift := 0.0
	for step in 33:
		top_drift = lerpf(top_drift, rng.randf_range(-6.0, 6.0), 0.5)
		outline.append(Vector2(10.0 + step * 19.4, 14.0 + top_drift))
	var bottom_drift := 0.0
	for step in range(32, -1, -1):
		bottom_drift = lerpf(bottom_drift, rng.randf_range(-7.0, 7.0), 0.5)
		outline.append(Vector2(10.0 + step * 19.4, 146.0 + bottom_drift))
	Kit.cut_out(image, outline, Color(0.93, 0.9, 0.82, 1), rng, 4.0)
	for row in 4:
		var y := 48 + row * 26
		image.fill_rect(Rect2i(28, y, 584, 1), Color(0.62, 0.68, 0.8, 0.8))
	image.fill_rect(Rect2i(64, 22, 1, 118), Color(0.8, 0.42, 0.4, 0.7))
	return _done(image)


static func shirt(colour: Color, seed_value: int) -> ImageTexture:
	var rng := _rng(seed_value)
	var image := _blank(Vector2i(128, 128))
	var outline := PackedVector2Array([
		Vector2(40, 12), Vector2(88, 12), Vector2(124, 40), Vector2(106, 60), Vector2(96, 52),
		Vector2(96, 120), Vector2(32, 120), Vector2(32, 52), Vector2(22, 60), Vector2(4, 40)
	])
	Kit.cut_out(image, outline, colour, rng, 4.0)
	return _done(image)


static func tree(colour: Color, seed_value: int) -> ImageTexture:
	var rng := _rng(seed_value)
	var image := _blank(Vector2i(256, 384))
	Kit.fill_polygon(image, PackedVector2Array([
		Vector2(116, 200), Vector2(140, 200), Vector2(146, 382), Vector2(110, 382)
	]), Color(0.28, 0.22, 0.2, 1), rng)
	for blob in 6:
		var centre := Vector2(rng.randf_range(70, 186), rng.randf_range(70, 210))
		var radii := Vector2(rng.randf_range(50, 80), rng.randf_range(44, 70))
		Kit.cut_out(image, Kit.ellipse(centre, radii, 20), colour.darkened(rng.randf_range(0.0, 0.2)), rng, 3.0)
	return _done(image)
