extends RefCounted
## Builders shared by the visual experiments lab: paper materials, colour-field meshes,
## solid boxes, and the cut-out textures drawn at runtime.
##
## Nothing here is used by the game. The lab lives under `scenes/dev/`, which every export
## preset excludes and `tools/verify_build.py` refuses to find in a package.
##
## Textures are generated, not shipped: a few hundred lines of drawing code instead of a
## folder of PNGs, deterministic for a given seed, and small (see `generated_bytes()`).

const PAPER_SHADER := preload("res://scenes/dev/visual_experiments/shaders/paper_cutout.gdshader")
const FIELD_SHADER := preload("res://scenes/dev/visual_experiments/shaders/colour_field.gdshader")
const BACKDROP_SHADER := preload(
	"res://scenes/dev/visual_experiments/shaders/painted_backdrop.gdshader"
)

const PLAIN := 0
const RULED := 1
const GRAPH := 2
const HALFTONE := 3
const KRAFT := 4
const TEXTURED := 5
const PERSPECTIVE := 6
const HATCH := 7

## Every texture this kit generated in this session, so the lab can report its own cost.
static var _generated_bytes: int = 0
static var _generated_count: int = 0


static func generated_bytes() -> int:
	return _generated_bytes


static func generated_count() -> int:
	return _generated_count


# --- Materials ------------------------------------------------------------------------


static func paper(
	pattern: int, paper_color: Color, ink: Color, sheet: Vector2, seed_value: float
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAPER_SHADER
	material.set_shader_parameter("pattern", pattern)
	material.set_shader_parameter("paper_color", paper_color)
	material.set_shader_parameter("ink_color", ink)
	material.set_shader_parameter("sheet_size", sheet)
	material.set_shader_parameter("seed", seed_value)
	return material


static func textured_paper(
	texture: Texture2D, sheet: Vector2, seed_value: float, tear: float = 0.05
) -> ShaderMaterial:
	var material := paper(TEXTURED, Color.WHITE, Color.BLACK, sheet, seed_value)
	material.set_shader_parameter("source_texture", texture)
	material.set_shader_parameter("tear_depth", tear)
	return material


static func field(base: Color = Color.WHITE, streaks: float = 0.08) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FIELD_SHADER
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("streak_strength", streaks)
	return material


static func backdrop(vanishing: Vector2, aspect: float, seed_value: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	material.set_shader_parameter("vanishing_point", vanishing)
	material.set_shader_parameter("aspect", aspect)
	material.set_shader_parameter("seed", seed_value)
	return material


static func flat(colour: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


# --- Geometry ---------------------------------------------------------------------------


## A box that is drawn and, when `solid`, collides. Returns the outermost node.
static func box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: Material,
	solid: bool = true,
	yaw: float = 0.0
) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	var root: Node3D = instance
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		instance.name = "Mesh"
		body.add_child(instance)
		root = body
	root.name = node_name
	root.position = position
	root.rotation.y = yaw
	parent.add_child(root)
	return root


## Collision only: for walls whose visible faces are colour fields or paper.
static func solid(
	parent: Node, node_name: String, size: Vector3, position: Vector3, yaw: float = 0.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = position
	body.rotation.y = yaw
	parent.add_child(body)
	return body


## One flat sheet. A QuadMesh faces +Z, so `basis` decides which way the sheet looks.
static func sheet(
	parent: Node, node_name: String, size: Vector2, xform: Transform3D, material: Material
) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = xform
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Basis for a sheet lying on the floor, rotated `yaw` about the vertical.
static func floor_basis(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)


## Appends one colour-field quad to `tool`. `a b c d` run counter-clockwise as seen from
## the side that faces the viewer; Godot's front faces wind clockwise, hence a-c-b.
static func field_quad(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colours: Array[Color]
) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var corners: Array[Vector3] = [a, b, c, d]
	var order: Array[int] = [0, 2, 1, 0, 3, 2]
	for index: int in order:
		tool.set_color(colours[mini(index, colours.size() - 1)])
		tool.set_normal(normal)
		tool.set_uv(Vector2(float(index == 1 or index == 2), float(index >= 2)))
		tool.add_vertex(corners[index])


## Appends an axis-aligned box (all six faces) in one colour.
static func field_box(tool: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return centre + Vector3(x, y, z)
	var colours: Array[Color] = [colour]
	var top: Array[Color] = [colour.lightened(0.08)]
	field_quad(tool, p.call(-h.x, h.y, h.z), p.call(h.x, h.y, h.z), p.call(h.x, h.y, -h.z), p.call(-h.x, h.y, -h.z), top)
	field_quad(tool, p.call(-h.x, -h.y, -h.z), p.call(h.x, -h.y, -h.z), p.call(h.x, -h.y, h.z), p.call(-h.x, -h.y, h.z), colours)
	field_quad(tool, p.call(-h.x, -h.y, h.z), p.call(h.x, -h.y, h.z), p.call(h.x, h.y, h.z), p.call(-h.x, h.y, h.z), colours)
	field_quad(tool, p.call(h.x, -h.y, -h.z), p.call(-h.x, -h.y, -h.z), p.call(-h.x, h.y, -h.z), p.call(h.x, h.y, -h.z), colours)
	field_quad(tool, p.call(h.x, -h.y, h.z), p.call(h.x, -h.y, -h.z), p.call(h.x, h.y, -h.z), p.call(h.x, h.y, h.z), colours)
	field_quad(tool, p.call(-h.x, -h.y, -h.z), p.call(-h.x, -h.y, h.z), p.call(-h.x, h.y, h.z), p.call(-h.x, h.y, -h.z), colours)


static func begin_field() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


## Commits a colour-field mesh into a MeshInstance3D, optionally with a two-sided
## trimesh collider built from the same triangles.
static func commit_field(
	parent: Node, node_name: String, tool: SurfaceTool, material: Material, collide: bool
) -> MeshInstance3D:
	var mesh := tool.commit()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	if collide:
		var body := StaticBody3D.new()
		body.name = "Collider"
		var shape := CollisionShape3D.new()
		var trimesh := mesh.create_trimesh_shape()
		trimesh.backface_collision = true
		shape.shape = trimesh
		body.add_child(shape)
		instance.add_child(body)
	return instance


# --- Cut-out textures -------------------------------------------------------------------
#
# Shapes are filled one scanline at a time with `Image.fill_rect`, which is native and
# fast, and each span's ends drift a pixel or two from row to row: the edge a pair of
# scissors leaves, not the edge a rasteriser leaves.


static func ellipse(centre: Vector2, radii: Vector2, points: int = 28) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for index in points:
		var angle := TAU * float(index) / float(points)
		polygon.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return polygon


static func fill_polygon(
	image: Image, polygon: PackedVector2Array, colour: Color, rng: RandomNumberGenerator,
	jitter: float = 1.5
) -> void:
	if polygon.size() < 3:
		return
	var top := INF
	var bottom := -INF
	for point: Vector2 in polygon:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	var drift_left := 0.0
	var drift_right := 0.0
	var first_row := maxi(0, int(floor(top)))
	var last_row := mini(image.get_height() - 1, int(ceil(bottom)))
	for row in range(first_row, last_row + 1):
		var y := float(row) + 0.5
		var crossings: Array[float] = []
		for index in polygon.size():
			var a: Vector2 = polygon[index]
			var b: Vector2 = polygon[(index + 1) % polygon.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		drift_left = lerpf(drift_left, rng.randf_range(-jitter, jitter), 0.35)
		drift_right = lerpf(drift_right, rng.randf_range(-jitter, jitter), 0.35)
		var pair := 0
		while pair + 1 < crossings.size():
			var x0 := int(round(crossings[pair] + drift_left))
			var x1 := int(round(crossings[pair + 1] + drift_right))
			x0 = clampi(x0, 0, image.get_width())
			x1 = clampi(x1, 0, image.get_width())
			if x1 > x0:
				image.fill_rect(Rect2i(x0, row, x1 - x0, 1), colour)
			pair += 2


## The shape in white, grown by `rim` pixels, then the shape itself: a cut-out's margin.
static func cut_out(
	image: Image, polygon: PackedVector2Array, colour: Color, rng: RandomNumberGenerator,
	rim: float = 5.0
) -> void:
	if rim > 0.0:
		var grown := Geometry2D.offset_polygon(polygon, rim)
		for outline: PackedVector2Array in grown:
			fill_polygon(image, outline, Color(0.97, 0.95, 0.9), rng, 2.5)
	fill_polygon(image, polygon, colour, rng, 1.2)


## An ink line: a chain of small squares whose width breathes along the stroke.
static func stroke(
	image: Image, from: Vector2, to: Vector2, width: float, colour: Color,
	rng: RandomNumberGenerator
) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(length))
	for step in steps + 1:
		var t := float(step) / float(steps)
		var point := from.lerp(to, t)
		var size := maxi(1, int(round(width * rng.randf_range(0.75, 1.2))))
		var corner := Vector2i(int(point.x) - size / 2, int(point.y) - size / 2)
		var rect := Rect2i(corner, Vector2i(size, size)).intersection(
			Rect2i(Vector2i.ZERO, image.get_size())
		)
		if rect.has_area():
			image.fill_rect(rect, colour)


static func _finish(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	_generated_bytes += image.get_data_size()
	_generated_count += 1
	return ImageTexture.create_from_image(image)


static func _canvas(size: Vector2i) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


## A pupil cut out of a magazine: no face, only the silhouette and the uniform.
static func figure_texture(uniform_colour: Color, hair: Color, seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _canvas(Vector2i(256, 512))
	var skin := Color(0.86, 0.73, 0.62)
	var legs := PackedVector2Array([
		Vector2(96, 330), Vector2(124, 330), Vector2(122, 492), Vector2(98, 492)
	])
	var legs_right := PackedVector2Array([
		Vector2(134, 330), Vector2(162, 330), Vector2(158, 492), Vector2(136, 492)
	])
	var body := PackedVector2Array([
		Vector2(84, 150), Vector2(172, 150), Vector2(188, 250), Vector2(180, 350),
		Vector2(76, 350), Vector2(68, 250)
	])
	var arm_left := PackedVector2Array([
		Vector2(70, 160), Vector2(88, 166), Vector2(74, 300), Vector2(56, 296)
	])
	var arm_right := PackedVector2Array([
		Vector2(168, 166), Vector2(186, 160), Vector2(200, 296), Vector2(182, 300)
	])
	for polygon: PackedVector2Array in [legs, legs_right, arm_left, arm_right, body]:
		cut_out(image, polygon, Color(0, 0, 0, 1), rng, 6.0)
	fill_polygon(image, legs, Color(0.16, 0.16, 0.2), rng)
	fill_polygon(image, legs_right, Color(0.16, 0.16, 0.2), rng)
	fill_polygon(image, arm_left, uniform_colour.darkened(0.15), rng)
	fill_polygon(image, arm_right, uniform_colour.darkened(0.15), rng)
	fill_polygon(image, body, uniform_colour, rng)
	cut_out(image, ellipse(Vector2(128, 104), Vector2(40, 48)), skin, rng, 6.0)
	fill_polygon(image, ellipse(Vector2(128, 86), Vector2(43, 32)), hair, rng)
	# A white collar and the one crease every uniform has.
	fill_polygon(image, PackedVector2Array([
		Vector2(104, 150), Vector2(152, 150), Vector2(128, 186)
	]), Color(0.95, 0.94, 0.9), rng)
	stroke(image, Vector2(128, 186), Vector2(124, 340), 2.0, uniform_colour.darkened(0.4), rng)
	return _finish(image)


## A desk drawn in oblique projection: the top is seen from above, the front from the
## side, at once. Stood upright in 3D it is the wrong way round from every angle.
static func desk_texture(seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _canvas(Vector2i(512, 384))
	var wood := Color(0.78, 0.6, 0.36)
	var ink := Color(0.15, 0.12, 0.12)
	var top := PackedVector2Array([
		Vector2(60, 110), Vector2(380, 110), Vector2(470, 40), Vector2(150, 40)
	])
	var front := PackedVector2Array([
		Vector2(60, 110), Vector2(380, 110), Vector2(380, 160), Vector2(60, 160)
	])
	var side := PackedVector2Array([
		Vector2(380, 110), Vector2(470, 40), Vector2(470, 90), Vector2(380, 160)
	])
	for leg_x: float in [70.0, 360.0]:
		cut_out(image, PackedVector2Array([
			Vector2(leg_x, 160), Vector2(leg_x + 16, 160), Vector2(leg_x + 14, 370),
			Vector2(leg_x + 2, 370)
		]), ink.lightened(0.25), rng, 5.0)
	for leg_x: float in [452.0, 160.0]:
		var height := 300.0 if leg_x > 400.0 else 290.0
		cut_out(image, PackedVector2Array([
			Vector2(leg_x, 90), Vector2(leg_x + 12, 90), Vector2(leg_x + 11, height),
			Vector2(leg_x + 1, height)
		]), ink.lightened(0.4), rng, 4.0)
	cut_out(image, top, wood.lightened(0.12), rng, 6.0)
	cut_out(image, front, wood.darkened(0.1), rng, 6.0)
	cut_out(image, side, wood.darkened(0.3), rng, 6.0)
	# Pencil marks someone left in the wood, drawn in the same projection.
	for _mark in 7:
		var start := Vector2(rng.randf_range(170, 400), rng.randf_range(55, 100))
		stroke(image, start, start + Vector2(rng.randf_range(20, 60), rng.randf_range(-6, 6)), 2.0, ink, rng)
	for edge: Array in [[top, true], [front, false], [side, false]]:
		var outline: PackedVector2Array = edge[0]
		for index in outline.size():
			stroke(image, outline[index], outline[(index + 1) % outline.size()], 3.0, ink, rng)
	return _finish(image)


static func chair_texture(seed_value: int, colour: Color) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _canvas(Vector2i(256, 384))
	var ink := Color(0.12, 0.1, 0.1)
	var back := PackedVector2Array([
		Vector2(70, 30), Vector2(190, 24), Vector2(186, 170), Vector2(74, 176)
	])
	var seat := PackedVector2Array([
		Vector2(50, 200), Vector2(206, 196), Vector2(228, 236), Vector2(36, 244)
	])
	for leg: PackedVector2Array in [
		PackedVector2Array([Vector2(44, 244), Vector2(58, 244), Vector2(54, 372), Vector2(42, 372)]),
		PackedVector2Array([Vector2(212, 236), Vector2(226, 236), Vector2(230, 368), Vector2(216, 368)]),
		PackedVector2Array([Vector2(82, 176), Vector2(94, 176), Vector2(92, 200), Vector2(80, 200)]),
		PackedVector2Array([Vector2(168, 172), Vector2(180, 172), Vector2(180, 198), Vector2(168, 198)]),
	]:
		cut_out(image, leg, ink.lightened(0.3), rng, 4.0)
	cut_out(image, back, colour, rng, 6.0)
	cut_out(image, seat, colour.darkened(0.2), rng, 6.0)
	for outline: PackedVector2Array in [back, seat]:
		for index in outline.size():
			stroke(image, outline[index], outline[(index + 1) % outline.size()], 3.0, ink, rng)
	return _finish(image)


## The seal of a school nobody can find: a ring, its ticks, a small house in the middle.
static func seal_texture(seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := _canvas(Vector2i(256, 256))
	var ink := Color(0.16, 0.24, 0.5, 0.9)
	fill_polygon(image, ellipse(Vector2(128, 128), Vector2(118, 118), 64), ink, rng, 1.0)
	fill_polygon(image, ellipse(Vector2(128, 128), Vector2(104, 104), 64), Color(0, 0, 0, 0), rng, 1.0)
	fill_polygon(image, ellipse(Vector2(128, 128), Vector2(96, 96), 64), ink, rng, 1.0)
	fill_polygon(image, ellipse(Vector2(128, 128), Vector2(92, 92), 64), Color(0, 0, 0, 0), rng, 1.0)
	for tick in 36:
		var angle := TAU * float(tick) / 36.0
		var direction := Vector2(cos(angle), sin(angle))
		stroke(image, Vector2(128, 128) + direction * 98.0, Vector2(128, 128) + direction * 103.0, 3.0, ink, rng)
	fill_polygon(image, PackedVector2Array([
		Vector2(80, 130), Vector2(128, 82), Vector2(176, 130), Vector2(166, 130),
		Vector2(166, 176), Vector2(90, 176), Vector2(90, 130)
	]), ink, rng, 1.0)
	fill_polygon(image, PackedVector2Array([
		Vector2(118, 176), Vector2(118, 146), Vector2(138, 146), Vector2(138, 176)
	]), Color(0, 0, 0, 0), rng, 0.5)
	# The stamp was pressed unevenly: knock random flecks out of it.
	for _fleck in 260:
		var spot := Vector2i(rng.randi_range(8, 247), rng.randi_range(8, 247))
		image.fill_rect(Rect2i(spot, Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 3))), Color(0, 0, 0, 0))
	return _finish(image)
