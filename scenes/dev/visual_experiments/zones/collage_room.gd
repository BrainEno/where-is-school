extends Node3D
## Experiment A — the handmade collage. A classroom assembled from paper.
##
## The walls are real boxes (you collide with them) under about forty pasted sheets:
## ruled, graph, newsprint halftone, kraft, crayon hatching, each with its own torn edge.
## Some sheets are other media entirely — the game's own painted window, blackboard,
## timetable and clock, reprinted at the wrong scale or the wrong way up. The furniture is
## mixed too: desks drawn in oblique projection and stood upright (flat as soon as you walk
## round them), one real 3D desk and chair among them, and three pupils cut out of a
## magazine who turn on their own vertical axis to keep facing you, as cardboard does not.
## A Decal stamps the seal of the school across the real desk and the floor; it is also the
## renderer probe, because Compatibility does not draw decals.
##
## Local frame: the room spans x -6..6, z -6..6, open-topped like a set seen from the flies.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const HALF := 6.0
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.2
const NORTH_DOOR_HALF := 1.1
const SOUTH_DOOR_HALF := 1.6
const DOOR_HEIGHT := 2.7
const SHEET_SEED := 1979
const SHEETS_PER_WALL := 11

## Reprinted from the game (read only; nothing in assets/ is changed or re-imported).
const PHOTO_WINDOW := "res://assets/materials/classroom/textures/window_view.png"
const PHOTO_BOARD := "res://assets/materials/classroom/textures/board_front.png"
const PHOTO_TIMETABLE := "res://assets/materials/classroom/textures/timetable.png"
const PHOTO_CLOCK := "res://assets/materials/classroom/textures/clock_face.png"
const REAL_DESK := "res://assets/models/classroom/classroom_student_desk.glb"
const REAL_CHAIR := "res://assets/models/classroom/classroom_student_chair.glb"

const PAPERS: Array[Color] = [
	Color(0.94, 0.91, 0.83), Color(0.86, 0.85, 0.8), Color(0.78, 0.86, 0.9),
	Color(0.93, 0.8, 0.45), Color(0.92, 0.76, 0.74), Color(0.7, 0.78, 0.66),
	Color(0.97, 0.96, 0.92),
]
const INKS: Array[Color] = [
	Color(0.24, 0.33, 0.58), Color(0.16, 0.15, 0.16), Color(0.5, 0.28, 0.2),
	Color(0.2, 0.38, 0.33),
]
const WALL_PATTERNS: Array[int] = [
	Kit.RULED, Kit.GRAPH, Kit.HALFTONE, Kit.KRAFT, Kit.HATCH, Kit.PLAIN, Kit.RULED, Kit.HALFTONE
]

var sheets: Array[MeshInstance3D] = []
var cut_outs: Array[Sprite3D] = []
var photo_sheets: Array[MeshInstance3D] = []
var decal: Decal = null
var _built: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = SHEET_SEED
	_build_walls()
	_build_floor(rng)
	_paste_wall_sheets(rng)
	_paste_photographs()
	_place_furniture()
	_place_figures()
	_stamp_seal()
	_write_caption()


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var kraft := Kit.paper(Kit.KRAFT, Color(0.62, 0.5, 0.36), Color.BLACK, Vector2(12, 4), 3.0)
	kraft.set_shader_parameter("tear_depth", 0.0)
	kraft.set_shader_parameter("flatness", 0.15)
	var y := WALL_HEIGHT * 0.5
	var t := WALL_THICKNESS
	var side := HALF - NORTH_DOOR_HALF
	Kit.box(walls, "WestWall", Vector3(t, WALL_HEIGHT, HALF * 2.0), Vector3(-HALF, y, 0), kraft)
	Kit.box(walls, "EastWall", Vector3(t, WALL_HEIGHT, HALF * 2.0), Vector3(HALF, y, 0), kraft)
	Kit.box(walls, "NorthWallWest", Vector3(side, WALL_HEIGHT, t),
		Vector3(-HALF + side * 0.5, y, -HALF), kraft)
	Kit.box(walls, "NorthWallEast", Vector3(side, WALL_HEIGHT, t),
		Vector3(HALF - side * 0.5, y, -HALF), kraft)
	Kit.box(walls, "NorthLintel", Vector3(NORTH_DOOR_HALF * 2.0, WALL_HEIGHT - DOOR_HEIGHT, t),
		Vector3(0, DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) * 0.5, -HALF), kraft)
	var south := HALF - SOUTH_DOOR_HALF
	Kit.box(walls, "SouthWallWest", Vector3(south, WALL_HEIGHT, t),
		Vector3(-HALF + south * 0.5, y, HALF), kraft)
	Kit.box(walls, "SouthWallEast", Vector3(south, WALL_HEIGHT, t),
		Vector3(HALF - south * 0.5, y, HALF), kraft)


func _build_floor(rng: RandomNumberGenerator) -> void:
	var floor_node := Node3D.new()
	floor_node.name = "Floor"
	add_child(floor_node)
	var base := Kit.paper(Kit.KRAFT, Color(0.7, 0.58, 0.42), Color.BLACK, Vector2(11.8, 11.8), 7.0)
	base.set_shader_parameter("tear_depth", 0.12)
	sheets.append(Kit.sheet(floor_node, "KraftGround", Vector2(11.8, 11.8),
		Transform3D(Kit.floor_basis(0.0), Vector3(0, 0.004, 0)), base))
	# A floor drawn in one-point perspective, lying on a real floor whose perspective is
	# different: the two vanishing points never agree.
	var drawn := Kit.paper(Kit.PERSPECTIVE, Color(0.93, 0.9, 0.8), Color(0.25, 0.25, 0.3),
		Vector2(6.0, 5.0), 11.0)
	drawn.set_shader_parameter("vanishing_point", Vector2(0.78, -0.6))
	drawn.set_shader_parameter("tear_depth", 0.18)
	sheets.append(Kit.sheet(floor_node, "DrawnFloor", Vector2(6.0, 5.0),
		Transform3D(Kit.floor_basis(0.21), Vector3(-1.4, 0.008, -1.6)), drawn))
	for index in 5:
		var strip := Kit.paper(Kit.RULED, PAPERS[index % PAPERS.size()], INKS[0],
			Vector2(0.5, 3.2), 20.0 + index)
		strip.set_shader_parameter("tear_depth", 0.04)
		var at := Vector3(rng.randf_range(-4.5, 4.5), 0.012 + index * 0.002, rng.randf_range(-4.5, 4.5))
		sheets.append(Kit.sheet(floor_node, "FloorStrip%d" % index, Vector2(0.5, 3.2),
			Transform3D(Kit.floor_basis(rng.randf_range(-PI, PI)), at), strip))


## Inner faces of the four walls: [name, centre of the face, yaw that turns +Z inward,
## door half-width or 0].
func _wall_faces() -> Array:
	var inset := HALF - WALL_THICKNESS * 0.5
	return [
		["North", Vector3(0, 0, -inset), 0.0, NORTH_DOOR_HALF],
		["South", Vector3(0, 0, inset), PI, SOUTH_DOOR_HALF],
		["West", Vector3(-inset, 0, 0), PI * 0.5, 0.0],
		["East", Vector3(inset, 0, 0), -PI * 0.5, 0.0],
	]


func _paste_wall_sheets(rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "WallSheets"
	add_child(holder)
	var layer := 0
	for face: Array in _wall_faces():
		var face_name: String = face[0]
		var centre: Vector3 = face[1]
		var yaw: float = face[2]
		var door_half: float = face[3]
		var along := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var inward := Basis(Vector3.UP, yaw) * Vector3.BACK
		var placed := 0
		var attempts := 0
		while placed < SHEETS_PER_WALL and attempts < 80:
			attempts += 1
			var size := Vector2(rng.randf_range(0.7, 2.2), rng.randf_range(0.6, 1.8))
			var u := rng.randf_range(-HALF + 0.9, HALF - 0.9)
			var v := rng.randf_range(0.5, WALL_HEIGHT - 0.4)
			# Keep doorways open: a sheet may hang over a lintel, never across the gap.
			if door_half > 0.0 and absf(u) - size.x * 0.5 < door_half and v - size.y * 0.5 < DOOR_HEIGHT:
				continue
			var pattern: int = WALL_PATTERNS[rng.randi_range(0, WALL_PATTERNS.size() - 1)]
			var paper_colour: Color = PAPERS[rng.randi_range(0, PAPERS.size() - 1)]
			var ink: Color = INKS[rng.randi_range(0, INKS.size() - 1)]
			var material := Kit.paper(pattern, paper_colour, ink, size, rng.randf_range(0.0, 100.0))
			material.set_shader_parameter("tear_depth", rng.randf_range(0.02, 0.09))
			material.set_shader_parameter("pattern_density", rng.randf_range(0.7, 1.5))
			var roll := rng.randf_range(-0.14, 0.14)
			var sheet_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll)
			var origin := centre + along * u + Vector3.UP * v + inward * (0.012 + layer * 0.0015)
			sheets.append(Kit.sheet(holder, "%sSheet%02d" % [face_name, placed], size,
				Transform3D(sheet_basis, origin), material))
			placed += 1
			layer += 1


func _paste_photographs() -> void:
	var holder := Node3D.new()
	holder.name = "Photographs"
	add_child(holder)
	var inset := HALF - WALL_THICKNESS * 0.5 - 0.03
	# [name, path, size, origin, yaw, roll, posterize]
	var prints: Array = [
		# The painted classroom window, reprinted crooked on a wall with no window.
		["WindowPrint", PHOTO_WINDOW, Vector2(4.2, 1.21), Vector3(inset, 2.2, 0.4), -PI * 0.5, 0.06, 0.0],
		# The blackboard as a torn print: you cannot write on a photograph of a board.
		["BoardPrint", PHOTO_BOARD, Vector2(4.6, 1.24), Vector3(-inset, 1.9, -0.6), PI * 0.5, -0.025, 5.0],
		# The timetable, turned on its side so nothing on it can be read in order.
		["TimetableSideways", PHOTO_TIMETABLE, Vector2(0.62, 0.86), Vector3(-3.6, 1.6, -inset), 0.0, PI * 0.5, 0.0],
		# The clock, at the size of a door.
		["ClockTooLarge", PHOTO_CLOCK, Vector2(1.9, 1.9), Vector3(3.5, 2.85, -inset), 0.0, 0.08, 4.0],
	]
	for entry: Array in prints:
		var texture := load(String(entry[1])) as Texture2D
		if texture == null:
			push_warning("Visual lab: %s is missing; the print is left blank." % String(entry[1]))
			texture = PlaceholderTexture2D.new()
		var size: Vector2 = entry[2]
		var material := Kit.textured_paper(texture, size, float(photo_sheets.size()) * 7.0, 0.045)
		material.set_shader_parameter("posterize_levels", float(entry[6]))
		material.set_shader_parameter("flatness", 0.5)
		var print_basis := Basis(Vector3.UP, float(entry[4])) * Basis(Vector3.BACK, float(entry[5]))
		var print_origin: Vector3 = entry[3]
		var instance := Kit.sheet(
			holder, String(entry[0]), size, Transform3D(print_basis, print_origin), material
		)
		photo_sheets.append(instance)
		sheets.append(instance)


func _place_furniture() -> void:
	var holder := Node3D.new()
	holder.name = "Furniture"
	add_child(holder)
	var desk_texture := Kit.desk_texture(41)
	var chair_texture := Kit.chair_texture(43, Color(0.33, 0.47, 0.62))
	var desk_spots: Array[Vector3] = [
		Vector3(-3.8, 0, -1.2), Vector3(-1.9, 0, -1.2), Vector3(1.9, 0, -1.2), Vector3(3.8, 0, -1.2),
		Vector3(-3.8, 0, 1.6), Vector3(-1.9, 0, 1.6), Vector3(3.8, 0, 1.6),
	]
	for index in desk_spots.size():
		var spot := desk_spots[index]
		var desk := _flat_cut_out(holder, "PaperDesk%d" % index, desk_texture, 1.15, spot)
		desk.rotation.y = 0.05 * float(index % 3 - 1)
		# You bump into a drawing: each paper desk has a collider as thin as the paper.
		Kit.solid(holder, "PaperDeskCollider%d" % index, Vector3(1.3, 0.8, 0.06),
			spot + Vector3(0, 0.4, 0), desk.rotation.y)
		var chair := _flat_cut_out(holder, "PaperChair%d" % index, chair_texture, 0.9,
			spot + Vector3(0.15, 0, 0.7))
		chair.rotation.y = desk.rotation.y + 0.12
	# The one real desk and chair, where the eighth paper desk would stand.
	var real_spot := Vector3(1.9, 0, 1.6)
	for entry: Array in [[REAL_DESK, "RealDesk", Vector3.ZERO], [REAL_CHAIR, "RealChair", Vector3(0, 0, 0.62)]]:
		var packed := load(String(entry[0])) as PackedScene
		if packed == null:
			push_warning("Visual lab: %s is missing." % String(entry[0]))
			continue
		var model := packed.instantiate() as Node3D
		model.name = String(entry[1])
		model.position = real_spot + (entry[2] as Vector3)
		holder.add_child(model)
	Kit.solid(holder, "RealDeskCollider", Vector3(1.0, 0.8, 0.6), real_spot + Vector3(0, 0.4, 0))


func _flat_cut_out(
	parent: Node, node_name: String, texture: Texture2D, height: float, feet: Vector3
) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.pixel_size = height / float(texture.get_height())
	sprite.position = feet + Vector3(0, height * 0.5, 0)
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = true
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(sprite)
	cut_outs.append(sprite)
	return sprite


func _place_figures() -> void:
	var holder := Node3D.new()
	holder.name = "Figures"
	add_child(holder)
	var navy := Kit.figure_texture(Color(0.16, 0.22, 0.38), Color(0.12, 0.1, 0.1), 7)
	var sage := Kit.figure_texture(Color(0.36, 0.45, 0.38), Color(0.24, 0.16, 0.12), 8)
	var spots: Array[Vector3] = [Vector3(-4.6, 0, -4.2), Vector3(4.7, 0, -3.0), Vector3(-2.7, 0, 4.0)]
	for index in spots.size():
		var figure := _flat_cut_out(holder, "Pupil%d" % index, navy if index != 1 else sage, 1.62,
			spots[index])
		# A cardboard pupil that turns to face you: Sprite3D's Y-billboard.
		figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		figure.shaded = false


func _stamp_seal() -> void:
	decal = Decal.new()
	decal.name = "SchoolSeal"
	decal.texture_albedo = Kit.seal_texture(5)
	decal.size = Vector3(2.6, 1.6, 2.6)
	decal.position = Vector3(1.9, 0.5, 1.9)
	decal.rotation.y = 0.35
	decal.modulate = Color(1, 1, 1, 0.85)
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05
	add_child(decal)


func _write_caption() -> void:
	var strip := Kit.paper(Kit.PLAIN, Color(0.97, 0.96, 0.9), Color.BLACK, Vector2(3.4, 0.36), 2.0)
	strip.set_shader_parameter("tear_depth", 0.03)
	var origin := Vector3(0, DOOR_HEIGHT + 0.42, -HALF + WALL_THICKNESS * 0.5 + 0.03)
	sheets.append(Kit.sheet(self, "CaptionStrip", Vector2(3.4, 0.36),
		Transform3D(Basis(Vector3.BACK, -0.03), origin), strip))
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.text = "this room is a drawing of a room"
	caption.font_size = 64
	caption.pixel_size = 0.0035
	caption.modulate = Color(0.14, 0.13, 0.16)
	caption.outline_size = 0
	caption.position = origin + Vector3(0, 0, 0.01)
	caption.rotation.z = -0.03
	add_child(caption)
