extends RefCounted
## The class, in cut paper: no card behind anybody. Each pupil is cut from different
## papers (dyed, kraft, newsprint, graph, sugar paper, a magazine page, a pencil drawing),
## in several pieces laid over one another a few millimetres apart: torso, head, arms,
## collar, the odd extra. The thicker papers show their edge (a copy of the cut, set back
## and filled with the paper's core colour). Some pieces are folded and stand out of the
## plane: a spine creased into a V, an arm folded at the elbow onto the desk, a head
## turned, a head laid down.
##
## Each pupil sits on a real chair, behind a real desk: the chair back covers the small of
## the back, the desk the legs. One is not in his seat: he is at the back wall, pinning a
## sheet to the class board.
##
## Every pupil is one mesh with one material (`shaders/cut_paper.gdshader`) sampling that
## pupil's own sheet (`paint_sheet`): seven draw calls for the class.
##
## Development only (scenes/dev/ is excluded from every export preset).

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")
const SHADER := preload(
	"res://scenes/dev/visual_experiments/biology_classroom/shaders/cut_paper.gdshader"
)

const SHEET := 256
## Where each piece is painted on a pupil's sheet (pixels).
const R_TORSO := Rect2i(0, 0, 144, 176)
const R_HEAD := Rect2i(144, 0, 112, 120)
const R_ARM_A := Rect2i(144, 120, 56, 136)
const R_ARM_B := Rect2i(200, 120, 56, 136)
const R_EXTRA := Rect2i(0, 176, 144, 80)

enum Paper { DYED, KRAFT, NEWSPRINT, GRAPH, SUGAR, MAGAZINE, PENCIL }

const SKIN := Color(0.86, 0.72, 0.6)
const COLLAR := Color(0.95, 0.94, 0.9)

## The pupils. `seat`: desk (column, row), or Vector2i(-1, -1) for the one standing.
## `pose`: upright, turned, asleep, ponytail, elbow, hand_up, standing.
const PUPILS: Array[Dictionary] = [
	{"seat": Vector2i(0, 0), "pose": &"upright", "paper": Paper.DYED, "colour": Color(0.2, 0.26, 0.44),
		"hair": Color(0.08, 0.08, 0.1), "hair_paper": Paper.SUGAR, "fold": 22.0},
	{"seat": Vector2i(2, 0), "pose": &"turned", "paper": Paper.NEWSPRINT, "colour": Color(0.62, 0.66, 0.7),
		"hair": Color(0.22, 0.16, 0.12), "hair_paper": Paper.KRAFT, "fold": 0.0},
	{"seat": Vector2i(3, 0), "pose": &"asleep", "paper": Paper.KRAFT, "colour": Color(0.55, 0.45, 0.33),
		"hair": Color(0.1, 0.09, 0.1), "hair_paper": Paper.DYED, "fold": 0.0},
	{"seat": Vector2i(2, 1), "pose": &"ponytail", "paper": Paper.GRAPH, "colour": Color(0.78, 0.82, 0.76),
		"hair": Color(0.12, 0.1, 0.1), "hair_paper": Paper.SUGAR, "fold": 0.0},
	{"seat": Vector2i(3, 1), "pose": &"elbow", "paper": Paper.MAGAZINE, "colour": Color(0.38, 0.3, 0.46),
		"hair": Color(0.9, 0.88, 0.82), "hair_paper": Paper.PENCIL, "fold": 28.0},
	{"seat": Vector2i(1, 2), "pose": &"hand_up", "paper": Paper.SUGAR, "colour": Color(0.36, 0.46, 0.56),
		"hair": Color(0.16, 0.12, 0.1), "hair_paper": Paper.DYED, "fold": 0.0},
	{"seat": Vector2i(-1, -1), "pose": &"standing", "paper": Paper.DYED, "colour": Color(0.26, 0.36, 0.34),
		"hair": Color(0.08, 0.08, 0.1), "hair_paper": Paper.SUGAR, "fold": 30.0},
]
## Where the standing pupil stands (feet), his back to the room, at the class board.
const STANDING_AT := Vector3(0.45, 0.0, 4.68)

static var _generated_bytes: int = 0
## Painted sheets by seed: a second instance of the scene (the test makes several) reuses
## them instead of painting again.
static var _sheets: Dictionary = {}


static func generated_bytes() -> int:
	return _generated_bytes


## Builds the class under `parent`. Returns [meshes, materials].
## `desk_columns`/`desk_rows` and `chair_back` are the room's plan.
static func build(
	parent: Node3D, desk_columns: Array[float], desk_rows: Array[float], chair_back: float,
	focus_point: Vector3
) -> Array:
	var meshes: Array[MeshInstance3D] = []
	var materials: Array[ShaderMaterial] = []
	for index in PUPILS.size():
		var pupil: Dictionary = PUPILS[index]
		var seat: Vector2i = pupil["seat"]
		var origin := STANDING_AT
		var yaw := PI
		if seat.x >= 0:
			# Feet between the desk's back edge and the chair's back.
			origin = Vector3(desk_columns[seat.x], 0.0, desk_rows[seat.y] + chair_back - 0.08)
			yaw = deg_to_rad(float(index % 3 - 1) * 3.0)
		var sheet := paint_sheet(pupil, 300 + index * 7)
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("paper_sheet", sheet)
		material.set_shader_parameter("focus_point", focus_point)
		materials.append(material)
		var tool := Kit.begin_field()
		_assemble(tool, pupil, 300 + index * 7)
		var instance := MeshInstance3D.new()
		instance.name = "Classmate%d" % index
		instance.mesh = tool.commit()
		instance.material_override = material
		instance.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
		parent.add_child(instance)
		meshes.append(instance)
	return [meshes, materials]


# --- Pieces in space (the pupil's frame: feet at the origin, facing -Z, +Z behind) --------


static func _assemble(tool: SurfaceTool, pupil: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pose: StringName = pupil["pose"]
	var paper: int = pupil["paper"]
	var core := _core_colour(paper, pupil["colour"])
	var hair_core := _core_colour(pupil["hair_paper"], pupil["hair"])
	var thick := 0.012 if paper == Paper.KRAFT or paper == Paper.SUGAR else 0.006
	var fold := deg_to_rad(float(pupil["fold"]))
	var lean := rng.randf_range(-0.03, 0.03)
	var seat_y := 0.47
	if pose == &"standing":
		_standing(tool, pupil, core, hair_core, fold)
		return
	# The torso: from the seat to the shoulders, in front of the chair back.
	var slump := deg_to_rad(8.0) if pose == &"asleep" or pose == &"elbow" else deg_to_rad(-3.0)
	var torso_basis := Basis(Vector3.RIGHT, -slump)
	var torso_centre := Vector3(lean, seat_y + 0.31, 0.0)
	var torso_size := Vector2(0.46, 0.64)
	if fold > 0.0:
		_folded(tool, torso_centre, torso_size, torso_basis, _uv(R_TORSO), core, thick, fold)
	else:
		_piece(tool, torso_centre, torso_size, torso_basis, _uv(R_TORSO), core, thick)
	var shoulders := torso_centre + torso_basis.y * 0.3
	# The collar, a layer on top.
	_piece(tool, shoulders + Vector3(0.0, -0.04, 0.035), Vector2(0.2, 0.09), torso_basis,
		_uv(R_EXTRA, Rect2(0.0, 0.0, 0.5, 0.5)), COLLAR.darkened(0.08), 0.004)
	# The head: in front of the torso by a few centimetres, its own paper.
	var head_basis := Basis.IDENTITY
	var head_centre := shoulders + Vector3(lean * 0.5, 0.17, 0.05)
	match pose:
		&"turned":
			head_basis = Basis(Vector3.UP, deg_to_rad(-34.0))
		&"asleep":
			head_basis = Basis(Vector3.RIGHT, deg_to_rad(-72.0))
			head_centre = Vector3(lean, 0.86, -0.36)
		&"elbow":
			head_basis = Basis(Vector3.FORWARD, deg_to_rad(-12.0))
			head_centre += Vector3(0.05, -0.03, 0.0)
	var head_size := Vector2(0.27, 0.3)
	_piece(tool, head_centre, head_size, head_basis, _uv(R_HEAD), hair_core, 0.008)
	# An ear: skin paper, behind the hair.
	if pose != &"asleep":
		var ear_at := head_centre + head_basis.x * 0.125 + head_basis.y * -0.02 - head_basis.z * 0.012
		_piece(tool, ear_at, Vector2(0.05, 0.07), head_basis, _uv(R_EXTRA, Rect2(0.5, 0.0, 0.18, 0.5)),
			SKIN.darkened(0.15), 0.0)
	if pose == &"ponytail":
		_piece(tool, head_centre + Vector3(0.02, -0.12, 0.03), Vector2(0.1, 0.24),
			Basis(Vector3.FORWARD, deg_to_rad(8.0)), _uv(R_EXTRA, Rect2(0.7, 0.0, 0.3, 1.0)), hair_core, 0.006)
	# Arms: strips folded at the elbow, the forearm lying on the desk.
	var desk_y := 0.775
	var right := shoulders + torso_basis.x * 0.21
	var left := shoulders - torso_basis.x * 0.21
	match pose:
		&"hand_up":
			_strip(tool, [left, left + Vector3(-0.06, -0.26, -0.3), Vector3(left.x - 0.04, desk_y, -0.6)],
				0.085, _uv(R_ARM_A), core, thick)
			_strip(tool, [right, right + Vector3(0.05, 0.3, -0.06), right + Vector3(0.03, 0.62, -0.1)],
				0.08, _uv(R_ARM_B), core, thick)
		&"elbow":
			_strip(tool, [right, right + Vector3(0.05, -0.26, -0.32), Vector3(right.x + 0.02, desk_y, -0.5)],
				0.085, _uv(R_ARM_A), core, thick)
			_strip(tool, [left, left + Vector3(-0.02, -0.24, -0.34), head_centre + Vector3(-0.1, -0.12, -0.02)],
				0.08, _uv(R_ARM_B), core, thick)
		&"asleep":
			_strip(tool, [right, Vector3(right.x + 0.04, desk_y + 0.02, -0.3), Vector3(-0.1, desk_y + 0.02, -0.5)],
				0.09, _uv(R_ARM_A), core, thick)
			_strip(tool, [left, Vector3(left.x - 0.04, desk_y + 0.03, -0.3), Vector3(0.1, desk_y + 0.03, -0.46)],
				0.09, _uv(R_ARM_B), core, thick)
		_:
			_strip(tool, [right, right + Vector3(0.04, -0.26, -0.3), Vector3(right.x - 0.02, desk_y, -0.62)],
				0.085, _uv(R_ARM_A), core, thick)
			_strip(tool, [left, left + Vector3(-0.04, -0.26, -0.3), Vector3(left.x + 0.05, desk_y, -0.58)],
				0.085, _uv(R_ARM_B), core, thick)


## The pupil at the back wall: standing, a spine folded into a V, arms up to the board
## with a sheet between his hands.
static func _standing(tool: SurfaceTool, pupil: Dictionary, core: Color, hair_core: Color, fold: float) -> void:
	# Legs: two strips, kraft-dark trousers (the extra region's lower half).
	for side: float in [-1.0, 1.0]:
		_piece(tool, Vector3(side * 0.08, 0.42, 0.0), Vector2(0.12, 0.84), Basis.IDENTITY,
			_uv(R_EXTRA, Rect2(0.0, 0.5, 0.5, 0.5)), Color(0.2, 0.2, 0.24), 0.006)
	var torso_centre := Vector3(0.0, 1.12, 0.02)
	_folded(tool, torso_centre, Vector2(0.44, 0.62), Basis.IDENTITY, _uv(R_TORSO), core, 0.008, fold)
	var shoulders := torso_centre + Vector3(0.0, 0.3, 0.0)
	_piece(tool, shoulders + Vector3(0.0, -0.04, 0.045), Vector2(0.2, 0.09), Basis.IDENTITY,
		_uv(R_EXTRA, Rect2(0.0, 0.0, 0.5, 0.5)), COLLAR.darkened(0.08), 0.004)
	var head_centre := shoulders + Vector3(0.0, 0.17, 0.06)
	_piece(tool, head_centre, Vector2(0.27, 0.3), Basis(Vector3.RIGHT, deg_to_rad(-8.0)), _uv(R_HEAD), hair_core, 0.008)
	# Arms up past his head to the board. He faces the wall, which is his -Z: the pieces
	# face his +Z, the room, so the class sees his back.
	var right := shoulders + Vector3(0.21, 0.0, 0.0)
	var left := shoulders - Vector3(0.21, 0.0, 0.0)
	_strip(tool, [right, right + Vector3(0.1, 0.26, -0.1), Vector3(0.3, 1.88, -0.24)], 0.08, _uv(R_ARM_A), core, 0.008)
	_strip(tool, [left, left + Vector3(-0.1, 0.24, -0.1), Vector3(-0.28, 1.86, -0.24)], 0.08, _uv(R_ARM_B), core, 0.008)


## One flat piece: `basis.x` its width, `.y` its height, `.z` the way its face looks.
## `depth` > 0 adds its thickness: the same cut, set back, in the core colour.
static func _piece(
	tool: SurfaceTool, centre: Vector3, size: Vector2, basis: Basis, uv: Rect2, core: Color,
	depth: float
) -> void:
	var half_x := basis.x * size.x * 0.5
	var half_y := basis.y * size.y * 0.5
	var a := centre - half_x - half_y
	var b := centre + half_x - half_y
	var c := centre + half_x + half_y
	var d := centre - half_x + half_y
	if depth > 0.0:
		var back := -basis.z * depth + basis.x * depth * 0.4 - basis.y * depth * 0.5
		_quad(tool, a + back, b + back, c + back, d + back, uv, Color(core, 0.0))
	_quad(tool, a, b, c, d, uv, Color.WHITE)


## A piece creased down its middle into a V, the crease toward the viewer.
static func _folded(
	tool: SurfaceTool, centre: Vector3, size: Vector2, basis: Basis, uv: Rect2, core: Color,
	depth: float, angle: float
) -> void:
	var half_w := size.x * 0.5
	var up := basis.y * size.y * 0.5
	var ridge_low := centre - up + basis.z * half_w * sin(angle) * 0.5
	var ridge_high := centre + up + basis.z * half_w * sin(angle) * 0.5
	var out_right := basis.x * half_w * cos(angle) - basis.z * half_w * sin(angle)
	var out_left := -basis.x * half_w * cos(angle) - basis.z * half_w * sin(angle)
	var left_uv := Rect2(uv.position, Vector2(uv.size.x * 0.5, uv.size.y))
	var right_uv := Rect2(uv.position + Vector2(uv.size.x * 0.5, 0.0), Vector2(uv.size.x * 0.5, uv.size.y))
	var back := -basis.z * depth
	if depth > 0.0:
		_quad(tool, ridge_low + out_left + back, ridge_low + back, ridge_high + back, ridge_high + out_left + back,
			left_uv, Color(core, 0.0))
		_quad(tool, ridge_low + back, ridge_low + out_right + back, ridge_high + out_right + back, ridge_high + back,
			right_uv, Color(core, 0.0))
	_quad(tool, ridge_low + out_left, ridge_low, ridge_high, ridge_high + out_left, left_uv, Color.WHITE)
	_quad(tool, ridge_low, ridge_low + out_right, ridge_high + out_right, ridge_high, right_uv, Color.WHITE)


## A strip folded at its middle point: shoulder -> elbow -> hand. The sheet region's top
## half is the upper arm, the bottom half the forearm.
static func _strip(tool: SurfaceTool, points: Array, width: float, uv: Rect2, core: Color, depth: float) -> void:
	var halves: Array[Rect2] = [
		Rect2(uv.position, Vector2(uv.size.x, uv.size.y * 0.5)),
		Rect2(uv.position + Vector2(0.0, uv.size.y * 0.5), Vector2(uv.size.x, uv.size.y * 0.5)),
	]
	for segment in 2:
		var top: Vector3 = points[segment]
		var bottom: Vector3 = points[segment + 1]
		var along := (bottom - top).normalized()
		var side := Vector3.RIGHT * width * 0.5
		# The face looks up and back (toward the room's cameras); `_quad`'s winding gives
		# a face normal of -(side x along), so pick the side's sign to match.
		var normal := side.cross(along).normalized()
		if normal.dot(Vector3(0.0, 0.6, 0.8)) < 0.0:
			normal = -normal
		if side.cross(along).dot(normal) > 0.0:
			side = -side
		var back := -normal * depth
		var segment_uv := halves[segment]
		if depth > 0.0:
			_quad(tool, bottom - side + back, bottom + side + back, top + side + back, top - side + back,
				segment_uv, Color(core, 0.0))
		_quad(tool, bottom - side, bottom + side, top + side, top - side, segment_uv, Color.WHITE)


## a b c d: bottom-left, bottom-right, top-right, top-left of the face.
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Rect2, colour: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var corners: Array[Vector3] = [a, b, c, d]
	var uvs: Array[Vector2] = [
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y),
		Vector2(uv.end.x, uv.position.y), Vector2(uv.position.x, uv.position.y),
	]
	var order: Array[int] = [0, 2, 1, 0, 3, 2]
	for index: int in order:
		tool.set_color(colour)
		tool.set_normal(normal)
		tool.set_uv(uvs[index])
		tool.add_vertex(corners[index])


## A region of the sheet as UVs; `part` is a fraction of the region.
static func _uv(region: Rect2i, part: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)) -> Rect2:
	var size := float(SHEET)
	var origin := Vector2(region.position) + Vector2(region.size) * part.position
	var extent := Vector2(region.size) * part.size
	return Rect2(origin / size, extent / size)


static func _core_colour(paper: int, colour: Color) -> Color:
	match paper:
		Paper.KRAFT:
			return Color(0.62, 0.5, 0.36)
		Paper.NEWSPRINT:
			return Color(0.82, 0.8, 0.74)
		Paper.SUGAR:
			return colour.lightened(0.35)
		Paper.PENCIL:
			return Color(0.93, 0.92, 0.88)
	return Color(0.95, 0.93, 0.87)


# --- The sheet: every piece of one pupil, painted on one image ---------------------------


static func paint_sheet(pupil: Dictionary, seed_value: int) -> ImageTexture:
	if _sheets.has(seed_value):
		return _sheets[seed_value] as ImageTexture
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create_empty(SHEET, SHEET, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var colour: Color = pupil["colour"]
	var hair: Color = pupil["hair"]
	var paper: int = pupil["paper"]
	var hair_paper: int = pupil["hair_paper"]
	var accent := colour.lightened(0.4) if paper == Paper.MAGAZINE else colour
	# Torso: the back of a school jacket, shoulders to hem.
	var t := Vector2(R_TORSO.position)
	var slope := rng.randf_range(-6.0, 6.0)
	var torso := PackedVector2Array([
		t + Vector2(28, 14 + slope), t + Vector2(72, 8), t + Vector2(116, 14 - slope),
		t + Vector2(134, 40), t + Vector2(130, 168), t + Vector2(14, 168), t + Vector2(10, 40),
	])
	Kit.fill_polygon(image, torso, colour, rng, 2.2)
	Kit.stroke(image, t + Vector2(72, 30), t + Vector2(73, 160), 1.5, colour.darkened(0.3), rng)
	Kit.stroke(image, t + Vector2(30, 60), t + Vector2(40, 150), 1.2, colour.darkened(0.22), rng)
	Kit.stroke(image, t + Vector2(114, 60), t + Vector2(104, 150), 1.2, colour.darkened(0.22), rng)
	# Head: the back of it, hair; a bob, a crop or a scribble.
	var h := Vector2(R_HEAD.position)
	var head := Kit.ellipse(h + Vector2(56, 62), Vector2(46 + rng.randf_range(-3.0, 3.0), 54))
	Kit.fill_polygon(image, head, hair, rng, 1.8)
	if hair_paper == Paper.PENCIL:
		Kit.fill_polygon(image, PackedVector2Array([h + Vector2(30, 104), h + Vector2(82, 104),
			h + Vector2(78, 118), h + Vector2(34, 118)]), SKIN, rng, 1.0)
	else:
		Kit.fill_polygon(image, PackedVector2Array([h + Vector2(36, 100), h + Vector2(76, 100),
			h + Vector2(72, 118), h + Vector2(40, 118)]), SKIN.darkened(0.1), rng, 1.0)
	# Arms: two strips, sleeve to cuff, a crease across the middle and a hand at the end.
	for region: Rect2i in [R_ARM_A, R_ARM_B]:
		var r := Vector2(region.position)
		Kit.fill_polygon(image, PackedVector2Array([r + Vector2(8, 4), r + Vector2(48, 4),
			r + Vector2(50, 112), r + Vector2(6, 112)]), colour, rng, 1.6)
		Kit.fill_polygon(image, PackedVector2Array([r + Vector2(10, 112), r + Vector2(46, 112),
			r + Vector2(42, 132), r + Vector2(14, 132)]), SKIN, rng, 1.2)
		Kit.stroke(image, r + Vector2(8, 68), r + Vector2(48, 67), 1.2, colour.darkened(0.35), rng)
	# Extras: a collar, an ear, a ponytail, trousers.
	var e := Vector2(R_EXTRA.position)
	Kit.fill_polygon(image, PackedVector2Array([e + Vector2(6, 8), e + Vector2(66, 8), e + Vector2(36, 36)]),
		COLLAR, rng, 1.0)
	Kit.fill_polygon(image, Kit.ellipse(e + Vector2(85, 20), Vector2(10, 15), 14), SKIN, rng, 0.8)
	Kit.fill_polygon(image, PackedVector2Array([e + Vector2(110, 4), e + Vector2(136, 6),
		e + Vector2(132, 60), e + Vector2(122, 76), e + Vector2(112, 58)]), hair, rng, 1.4)
	Kit.fill_polygon(image, PackedVector2Array([e + Vector2(6, 44), e + Vector2(66, 44),
		e + Vector2(64, 78), e + Vector2(8, 78)]), Color(0.26, 0.26, 0.3), rng, 1.6)
	# Now the papers: each region gets its paper's surface and its kind of edge.
	_surface(image, R_TORSO, paper, accent, _core_colour(paper, colour), true, rng)
	_surface(image, R_HEAD, hair_paper, hair, _core_colour(hair_paper, hair), hair_paper != Paper.DYED, rng)
	_surface(image, R_ARM_A, paper, accent, _core_colour(paper, colour), false, rng)
	_surface(image, R_ARM_B, paper, accent, _core_colour(paper, colour), true, rng)
	_surface(image, R_EXTRA, Paper.DYED, COLLAR, Color(0.97, 0.96, 0.92), false, rng)
	image.generate_mipmaps()
	_generated_bytes += image.get_data_size()
	var texture := ImageTexture.create_from_image(image)
	_sheets[seed_value] = texture
	return texture


## Gives the opaque pixels of `region` the paper's surface, and its edge: torn paper shows
## a band of pale fibre (the core) that comes and goes; a scissor cut shows none.
static func _surface(
	image: Image, region: Rect2i, paper: int, accent: Color, core: Color, torn: bool,
	rng: RandomNumberGenerator
) -> void:
	var width := image.get_width()
	var data := image.get_data()
	var x0 := region.position.x
	var y0 := region.position.y
	var x1 := region.end.x
	var y1 := region.end.y
	var phase := rng.randf() * 100.0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var at := (y * width + x) * 4
			if data[at + 3] < 128:
				continue
			var colour := Color(data[at] / 255.0, data[at + 1] / 255.0, data[at + 2] / 255.0)
			var cell := _hash(floorf(x / 3.0) + phase, floorf(y / 3.0))
			match paper:
				Paper.DYED:
					colour *= 1.0 + (cell - 0.5) * 0.07
				Paper.KRAFT:
					var fibre := _hash(floorf(y * 0.8 + sin(x * 0.07 + phase) * 3.0), floorf(x / 11.0))
					colour *= 1.0 + (fibre - 0.5) * 0.2
				Paper.NEWSPRINT:
					var u := (x + y) * 0.7071
					var v := (x - y) * 0.7071
					var dot := Vector2(fposmod(u, 5.0) - 2.5, fposmod(v, 5.0) - 2.5).length()
					var tone := 0.6 + 0.4 * sin(y * 0.05 + phase) * sin(x * 0.04)
					if dot < 1.6 * tone + 0.4:
						colour = colour.darkened(0.42)
					colour = colour.lerp(Color(0.86, 0.85, 0.8), 0.12)
				Paper.GRAPH:
					if x % 8 == 0 or y % 8 == 0:
						colour = colour.lerp(Color(0.42, 0.58, 0.78), 0.4 if (x % 40 == 0 or y % 40 == 0) else 0.22)
				Paper.SUGAR:
					colour *= 1.0 + (cell - 0.5) * 0.12
					if _hash(float(x) + phase, float(y)) > 0.985:
						colour = colour.lightened(0.3)
				Paper.MAGAZINE:
					if int(floorf((x + 2.0 * y) / 9.0)) % 2 == 0:
						colour = colour.lerp(accent, 0.55)
					colour *= 1.0 + (cell - 0.5) * 0.05
				Paper.PENCIL:
					var hatch := (x * 2 + y) % 5 == 0 or ((x + y * 3) % 7 == 0 and _hash(float(x), float(y) + phase) > 0.4)
					if hatch:
						colour = colour.lerp(Color(0.24, 0.23, 0.27), 0.75)
			if torn:
				var band := 1 + int(_hash(floorf(x / 5.0) + phase * 3.0, floorf(y / 5.0)) * 3.2)
				if _near_edge(data, width, region, x, y, band):
					colour = colour.lerp(core, 0.85)
			data[at] = int(clampf(colour.r, 0.0, 1.0) * 255.0)
			data[at + 1] = int(clampf(colour.g, 0.0, 1.0) * 255.0)
			data[at + 2] = int(clampf(colour.b, 0.0, 1.0) * 255.0)
	image.set_data(width, image.get_height(), false, Image.FORMAT_RGBA8, data)


static func _near_edge(data: PackedByteArray, width: int, region: Rect2i, x: int, y: int, band: int) -> bool:
	for offset: Vector2i in [Vector2i(band, 0), Vector2i(-band, 0), Vector2i(0, band), Vector2i(0, -band)]:
		var px := x + offset.x
		var py := y + offset.y
		if px < region.position.x or py < region.position.y or px >= region.end.x or py >= region.end.y:
			return true
		if data[(py * width + px) * 4 + 3] < 128:
			return true
	return false


static func _hash(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
