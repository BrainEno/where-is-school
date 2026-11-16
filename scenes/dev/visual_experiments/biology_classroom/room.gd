extends Node3D
## Builds the biology classroom of the experiment, and the outside it opens onto.
##
## The plan keeps the game's classroom where it matters (docs/MAP_PLAN.md, the production
## room): 14 x 10 m, the board on the north wall, the windows on the west, the doors on
## the east, twelve two-seat desks in four columns, the protagonist's desk second column
## second row, Q's beside it across the aisle. What changes is the teacher's corner:
##
## * the low teacher's desk is gone. A raised platform runs along the front wall, and at
##   its window end, where the low desk used to stand, a **tall standing lectern** carries
##   B's things: the taped wooden set square, the register and its red pencil, a box of
##   chalk, a pointer leaning on its side;
## * the back window is the curtained opening; behind the curtain is not the yard but a
##   blank sheet (see biology_classroom.gd for what drawing it does);
## * the front door opens, into a real outside: an open corridor along the building's
##   east face, a stair head at its north end down to the yard, the next class's door at
##   its south end. The yard lies below the west windows, where the fall lands.
##
## How it is drawn (the visual language of the experiment):
##
## * **Colour fields, not materials.** Every surface is a flat field of vertex colour lit
##   by a two-step terminator (`room_tone.gdshader`); shade is the room's ambient colour.
##   The whole static room is three meshes: the shell, the furniture, the ink.
## * **The fourth wall is drawn.** The two walls nearest the camera (south and east) are
##   built only to the dado line; above it they are a pencil contour: the top edge, the
##   corners, the door frames. The camera looks into the room the way one looks into a
##   drawing of it, and nothing has to fade out of the way.
## * **Furniture is outlined** (`ink_hull.gdshader`), the room's shell is not.
## * **The real light is the sun through the west wall**: the wall's shadow covers the
##   window side of the room, the front window lays a bright patch across the lectern.
##   The painted marks (`ink_mark.gdshader`) are the light and shadow that are not real.
##
## Everything here is decoration plus a closed list of box colliders; no navigation mesh.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")
const Art := preload("res://scenes/dev/visual_experiments/biology_classroom/room_art.gd")
const TONE_SHADER := preload(
	"res://scenes/dev/visual_experiments/biology_classroom/shaders/room_tone.gdshader"
)
const HULL_SHADER := preload(
	"res://scenes/dev/visual_experiments/biology_classroom/shaders/ink_hull.gdshader"
)
const MARK_SHADER := preload(
	"res://scenes/dev/visual_experiments/biology_classroom/shaders/ink_mark.gdshader"
)

# --- Plan (metres; Y up, the room's floor at 0, the yard at YARD_Y) -----------------------

const ROOM_MIN := Vector2(-7.0, -5.0)
const ROOM_MAX := Vector2(7.0, 5.0)
const WALL := 0.2
const WALL_HEIGHT := 3.2
const DADO := 1.1
const YARD_Y := -3.4
## The desks: x per column, z per row (the desk's centre; its chair is 0.58 behind it).
const DESK_COLUMNS: Array[float] = [-4.8, -1.6, 1.6, 4.8]
const DESK_ROWS: Array[float] = [-0.4, 1.6, 3.6]
const CHAIR_BACK := 0.58
const PLAYER_DESK := Vector3(-1.6, 0.0, 1.6)
const Q_DESK := Vector3(-4.8, 0.0, 1.6)
## Where a seated pupil's feet are (production: desk + 0.65).
const SEAT_OFFSET := 0.65
## The platform along the front wall and the tall lectern at its window end.
const PLATFORM_MIN := Vector2(-7.0, -5.0)
const PLATFORM_MAX := Vector2(3.6, -2.1)
const PLATFORM_HEIGHT := 0.15
const RAMP := 0.3
const LECTERN := Vector3(-4.7, PLATFORM_HEIGHT, -2.55)
const LECTERN_SIZE := Vector3(1.0, 1.1, 0.6)
const LECTERN_TOP := 0.05
## Openings in the west wall: z range and sill/head heights.
const FRONT_WINDOW := Rect2(-3.15, 1.1, 1.5, 1.3)
const BACK_OPENING := Rect2(0.95, 0.5, 2.5, 2.4)
## Doors in the east wall: the z of the hinge side and the width.
const FRONT_DOOR_Z := -3.55
const REAR_DOOR_Z := 3.55
const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.1
## Outside: the corridor along the east face and the yard below the west face.
const CORRIDOR_MIN := Vector2(7.2, -7.2)
const CORRIDOR_MAX := Vector2(10.4, 10.2)
const STAIR_MIN := Vector2(7.2, -7.2)
const STAIR_MAX := Vector2(9.2, -5.6)
const NEIGHBOUR_DOOR_Z := 7.6
const YARD_MIN := Vector2(-20.0, -5.2)
const YARD_MAX := Vector2(-7.2, 5.2)
const YARD_DOOR_Z := -3.5
const LANDING := Vector3(-9.2, YARD_Y, 2.2)

# --- Palette -------------------------------------------------------------------------------
# Cool chalky walls over an ink-teal dado, an ochre floor, bone desks, the teacher's corner
# in rose (docs/ART_BIBLE.md: the teacher's area), the curtain in ultramarine. The exit
# door is amber, the one cue colour on the shell. Broad planes stay low in chroma.

const C_WALL := Color(0.6, 0.63, 0.7)
const C_WALL_NORTH := Color(0.66, 0.66, 0.68)
const C_DADO := Color(0.2, 0.28, 0.32)
const C_FLOOR := Color(0.6, 0.51, 0.39)
const C_FLOOR_LINE := Color(0.52, 0.43, 0.33)
const C_PLATFORM := Color(0.36, 0.27, 0.24)
const C_DESK_TOP := Color(0.86, 0.8, 0.67)
const C_DESK_BODY := Color(0.7, 0.62, 0.5)
const C_IRON := Color(0.2, 0.19, 0.23)
const C_CHAIR := Color(0.58, 0.36, 0.3)
const C_LECTERN := Color(0.6, 0.34, 0.4)
const C_LECTERN_SIDE := Color(0.48, 0.27, 0.34)
const C_BONE := Color(0.88, 0.83, 0.7)
const C_BOARD := Color(0.13, 0.16, 0.2)
const C_CURTAIN := Color(0.17, 0.21, 0.42)
const C_DOOR := Color(0.78, 0.58, 0.3)
const C_REAR_DOOR := Color(0.78, 0.76, 0.68)
const C_INK := Color(0.16, 0.14, 0.2)
const C_FACADE := Color(0.82, 0.78, 0.7)
const C_FACADE_DARK := Color(0.3, 0.32, 0.38)
const C_CORRIDOR := Color(0.66, 0.64, 0.6)
const C_YARD := Color(0.74, 0.7, 0.6)
const C_BRICK := Color(0.62, 0.44, 0.36)
const C_WOOD := Color(0.66, 0.46, 0.28)

## Seats with a cut-out classmate (column, row). Q's and the protagonist's are not here.
const CLASSMATES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(1, 2), Vector2i(3, 2),
]

## The interior's one material: its uniforms are the room's registers.
var room_material: ShaderMaterial = null
## The outside's material: the same shader, never chilled.
var outside_material: ShaderMaterial = null
var hull_material: ShaderMaterial = null
var fine_hull_material: ShaderMaterial = null
var ink_material: StandardMaterial3D = null

var lectern: Node3D = null
var lectern_body: Node3D = null
var lectern_top: Node3D = null
var set_square: MeshInstance3D = null
var curtain: Node3D = null
var blank_sheet: MeshInstance3D = null
var door_pivot: Node3D = null
var door_blocker: CollisionShape3D = null
var b_shadow: MeshInstance3D = null
var square_shadow: MeshInstance3D = null
var chalk_overlay: MeshInstance3D = null
var ring_mark: MeshInstance3D = null
var book_mark: MeshInstance3D = null
var clock_minute: Node3D = null
var clock_hour: Node3D = null
var lamps: Array[MeshInstance3D] = []
var lamp_material: StandardMaterial3D = null
var classmates: Array[MeshInstance3D] = []
var marks: Array[MeshInstance3D] = []
var solids: Array[StaticBody3D] = []

var _solids_root: Node3D = null


func _ready() -> void:
	_make_materials()
	_solids_root = Node3D.new()
	_solids_root.name = "Solids"
	add_child(_solids_root)
	_build_shell()
	_build_outside()
	_build_furniture()
	_build_ink()
	_build_lectern()
	_build_front_wall()
	_build_curtain()
	_build_doors()
	_build_lamps()
	_build_classmates()
	_build_marks()


# --- Queries used by the experiment, the test and the captures ---------------------------


static func seat_feet(desk: Vector3) -> Vector3:
	return Vector3(desk.x, 0.0, desk.z + SEAT_OFFSET)


static func opening_centre() -> Vector3:
	return Vector3(ROOM_MIN.x - WALL * 0.5, BACK_OPENING.position.y + BACK_OPENING.size.y * 0.5,
		BACK_OPENING.position.x + BACK_OPENING.size.x * 0.5)


static func door_centre() -> Vector3:
	return Vector3(ROOM_MAX.x + WALL * 0.5, 0.0, FRONT_DOOR_Z)


static func is_inside_room(point: Vector3) -> bool:
	return (point.y > -1.0 and point.x > ROOM_MIN.x and point.x < ROOM_MAX.x
		and point.z > ROOM_MIN.y and point.z < ROOM_MAX.y)


static func is_in_corridor(point: Vector3) -> bool:
	return point.y > -1.0 and point.x >= ROOM_MAX.x + WALL * 0.5


static func is_in_yard(point: Vector3) -> bool:
	return point.y < YARD_Y + 2.0


func lectern_top_height() -> float:
	return lectern_top.global_position.y + LECTERN_TOP


# --- Materials -----------------------------------------------------------------------------


func _make_materials() -> void:
	room_material = ShaderMaterial.new()
	room_material.shader = TONE_SHADER
	room_material.set_shader_parameter("focus_point", seat_feet(PLAYER_DESK))
	outside_material = ShaderMaterial.new()
	outside_material.shader = TONE_SHADER
	outside_material.set_shader_parameter("streak_strength", 0.035)
	hull_material = ShaderMaterial.new()
	hull_material.shader = HULL_SHADER
	hull_material.set_shader_parameter("ink", C_INK)
	hull_material.set_shader_parameter("width", 0.012)
	fine_hull_material = ShaderMaterial.new()
	fine_hull_material.shader = HULL_SHADER
	fine_hull_material.set_shader_parameter("ink", C_INK)
	fine_hull_material.set_shader_parameter("width", 0.005)
	ink_material = StandardMaterial3D.new()
	ink_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink_material.vertex_color_use_as_albedo = true
	ink_material.albedo_color = Color.WHITE
	# A pen line close to the lens would be a bar across the picture (the follow camera
	# often sits beyond the drawn walls): it dissolves within a few metres of the camera.
	ink_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	ink_material.distance_fade_min_distance = 2.2
	ink_material.distance_fade_max_distance = 4.6
	lamp_material = StandardMaterial3D.new()
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_material.albedo_color = Color(0.46, 0.48, 0.47)


# --- Helpers -------------------------------------------------------------------------------


func _box(tool: SurfaceTool, low: Vector3, high: Vector3, colour: Color) -> void:
	Kit.field_box(tool, (low + high) * 0.5, high - low, colour)


func _solid(node_name: String, low: Vector3, high: Vector3) -> StaticBody3D:
	var body := Kit.solid(_solids_root, node_name, high - low, (low + high) * 0.5)
	solids.append(body)
	return body


func _commit(node_name: String, tool: SurfaceTool, material: Material) -> MeshInstance3D:
	var instance := Kit.commit_field(self, node_name, tool, material, false)
	return instance


## A pen line: a thin box from `a` to `b`, broken into three slightly misaligned lengths
## the way a hand draws a long line.
func _ink_line(
	tool: SurfaceTool, a: Vector3, b: Vector3, width: float, rng: RandomNumberGenerator
) -> void:
	var pieces := 3
	for piece in pieces:
		var p0 := a.lerp(b, float(piece) / pieces)
		var p1 := a.lerp(b, float(piece + 1) / pieces + 0.01)
		var wobble := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * width * 0.4
		var centre := (p0 + p1) * 0.5 + wobble
		var span := (p1 - p0).abs()
		var size := Vector3(maxf(span.x, width), maxf(span.y, width), maxf(span.z, width))
		Kit.field_box(tool, centre, size, C_INK)


func _mark(
	node_name: String, texture: Texture2D, size: Vector2, xform: Transform3D, tint: Color,
	mode: int, opacity: float, amount: float
) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = MARK_SHADER
	material.set_shader_parameter("mark", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("amount", amount)
	material.set_shader_parameter("seed", float(marks.size()) * 3.7)
	var instance := Kit.sheet(self, node_name, size, xform, material)
	marks.append(instance)
	return instance


# --- The shell -----------------------------------------------------------------------------


func _build_shell() -> void:
	var tool := Kit.begin_field()
	var x0 := ROOM_MIN.x
	var x1 := ROOM_MAX.x
	var z0 := ROOM_MIN.y
	var z1 := ROOM_MAX.y
	# Floor, and its boards: darker seams every 0.7 m, running toward the board.
	_box(tool, Vector3(x0, -0.2, z0), Vector3(x1, 0.0, z1), C_FLOOR)
	var seam := x0 + 0.7
	while seam < x1:
		_box(tool, Vector3(seam - 0.015, 0.0, z0), Vector3(seam + 0.015, 0.003, z1), C_FLOOR_LINE)
		seam += 0.7
	# North wall, full height, and its dado.
	_box(tool, Vector3(x0 - WALL, 0.0, z0 - WALL), Vector3(x1 + WALL, WALL_HEIGHT, z0), C_WALL_NORTH)
	_box(tool, Vector3(x0, 0.0, z0), Vector3(x1, DADO, z0 + 0.02), C_DADO)
	# West wall, full height, cut by the front window and the back opening.
	var wx0 := x0 - WALL
	var spans: Array = [
		[z0 - WALL, FRONT_WINDOW.position.x, 0.0, WALL_HEIGHT],
		[FRONT_WINDOW.position.x, FRONT_WINDOW.end.x, 0.0, FRONT_WINDOW.position.y],
		[FRONT_WINDOW.position.x, FRONT_WINDOW.end.x, FRONT_WINDOW.end.y, WALL_HEIGHT],
		[FRONT_WINDOW.end.x, BACK_OPENING.position.x, 0.0, WALL_HEIGHT],
		[BACK_OPENING.position.x, BACK_OPENING.end.x, 0.0, BACK_OPENING.position.y],
		[BACK_OPENING.position.x, BACK_OPENING.end.x, BACK_OPENING.end.y, WALL_HEIGHT],
		[BACK_OPENING.end.x, z1 + WALL, 0.0, WALL_HEIGHT],
	]
	for span: Array in spans:
		var low := Vector3(wx0, float(span[2]), float(span[0]))
		var high := Vector3(x0, float(span[3]), float(span[1]))
		_box(tool, low, high, C_WALL)
		var dado_top := minf(float(span[3]), DADO)
		if float(span[2]) < DADO:
			_box(tool, Vector3(x0, float(span[2]), low.z), Vector3(x0 + 0.02, dado_top, high.z), C_DADO)
	# Sills: the front window's is deep enough for a jar.
	_box(tool, Vector3(x0 - 0.05, FRONT_WINDOW.position.y - 0.04, FRONT_WINDOW.position.x - 0.05),
		Vector3(x0 + 0.16, FRONT_WINDOW.position.y, FRONT_WINDOW.end.x + 0.05), C_BONE)
	# East and south walls: only to the dado line. Above it they are drawn (_build_ink).
	var door_spans: Array = [
		[z0 - WALL, FRONT_DOOR_Z - DOOR_WIDTH * 0.5],
		[FRONT_DOOR_Z + DOOR_WIDTH * 0.5, REAR_DOOR_Z - DOOR_WIDTH * 0.5],
		[REAR_DOOR_Z + DOOR_WIDTH * 0.5, z1 + WALL],
	]
	for span: Array in door_spans:
		_box(tool, Vector3(x1, 0.0, float(span[0])), Vector3(x1 + WALL, DADO, float(span[1])), C_DADO)
		_box(tool, Vector3(x1 - 0.01, DADO - 0.02, float(span[0])),
			Vector3(x1 + WALL + 0.01, DADO + 0.02, float(span[1])), C_BONE)
	_box(tool, Vector3(x0 - WALL, 0.0, z1), Vector3(x1 + WALL, DADO, z1 + WALL), C_DADO)
	_box(tool, Vector3(x0 - WALL, DADO - 0.02, z1 - 0.01),
		Vector3(x1 + WALL, DADO + 0.02, z1 + WALL + 0.01), C_BONE)
	# The platform, its front and east edges bevelled down to the floor (the ramps the
	# feet take).
	var p_low := Vector3(PLATFORM_MIN.x, 0.0, PLATFORM_MIN.y)
	var p_high := Vector3(PLATFORM_MAX.x, PLATFORM_HEIGHT, PLATFORM_MAX.y)
	_box(tool, p_low, p_high, C_PLATFORM)
	var top := PLATFORM_HEIGHT
	var front: Array[Color] = [C_PLATFORM.darkened(0.15)]
	Kit.field_quad(tool, Vector3(p_low.x, top, p_high.z), Vector3(p_low.x, 0.0, p_high.z + RAMP),
		Vector3(p_high.x, 0.0, p_high.z + RAMP), Vector3(p_high.x, top, p_high.z), front)
	Kit.field_quad(tool, Vector3(p_high.x, top, p_high.z), Vector3(p_high.x + RAMP, 0.0, p_high.z),
		Vector3(p_high.x + RAMP, 0.0, p_low.z), Vector3(p_high.x, top, p_low.z), front)
	# The threshold strip under the east wall, so the doorway has a floor.
	_box(tool, Vector3(x1, -0.2, z0 - WALL), Vector3(x1 + WALL, 0.0, z1 + WALL), C_FLOOR_LINE)
	_commit("Shell", tool, room_material)
	# Colliders: the floor, the walls (the drawn walls collide only to their built height,
	# so the camera's ray goes over them), the platform and its ramps.
	_solid("Floor", Vector3(x0 - WALL, -0.4, CORRIDOR_MIN.y), Vector3(CORRIDOR_MAX.x, 0.0, CORRIDOR_MAX.y))
	_solid("WallNorth", Vector3(x0 - WALL, 0.0, z0 - WALL), Vector3(x1 + WALL, WALL_HEIGHT, z0))
	_solid("WallWest", Vector3(wx0, 0.0, z0 - WALL), Vector3(x0, WALL_HEIGHT, z1 + WALL))
	_solid("WallSouth", Vector3(x0 - WALL, 0.0, z1), Vector3(x1 + WALL, DADO + 0.15, z1 + WALL))
	for index in door_spans.size():
		var span: Array = door_spans[index]
		_solid("WallEast%d" % index, Vector3(x1, 0.0, float(span[0])),
			Vector3(x1 + WALL, DADO + 0.15, float(span[1])))
	_solid("Platform", p_low, p_high)
	_ramp("RampFront", Vector3((p_low.x + p_high.x) * 0.5, 0.0, p_high.z + RAMP * 0.5),
		p_high.x - p_low.x, Vector3.RIGHT, 1.0)
	_ramp("RampEast", Vector3(p_high.x + RAMP * 0.5, 0.0, (p_low.z + p_high.z) * 0.5),
		p_high.z - p_low.z, Vector3.FORWARD, 1.0)


## A thin slab whose top surface runs from the platform's edge down to the floor.
func _ramp(node_name: String, foot: Vector3, length: float, axis: Vector3, sense: float) -> void:
	var angle := atan2(PLATFORM_HEIGHT, RAMP)
	var slope := sqrt(PLATFORM_HEIGHT * PLATFORM_HEIGHT + RAMP * RAMP)
	var body := StaticBody3D.new()
	body.name = node_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var thickness := 0.06
	if axis == Vector3.RIGHT:
		box.size = Vector3(length, thickness, slope)
	else:
		box.size = Vector3(slope, thickness, length)
	shape.shape = box
	body.add_child(shape)
	body.basis = Basis(axis, angle * sense)
	var normal := body.basis.y
	body.position = foot + Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0) - normal * thickness * 0.5
	_solids_root.add_child(body)
	solids.append(body)


# --- Outside -------------------------------------------------------------------------------


func _build_outside() -> void:
	var tool := Kit.begin_field()
	var x0 := ROOM_MIN.x - WALL
	# The storey below: the classroom and corridor stand on it; its west face is the
	# building the yard looks at.
	# Under the classroom it is exactly as deep as the room (so nothing reaches south past
	# the drawn wall); under the corridor it runs the corridor's length.
	_box(tool, Vector3(x0, YARD_Y, YARD_MIN.y), Vector3(ROOM_MAX.x + WALL, -0.2, YARD_MAX.y), C_FACADE)
	_box(tool, Vector3(ROOM_MAX.x + WALL, YARD_Y, CORRIDOR_MIN.y), Vector3(CORRIDOR_MAX.x, -0.2, CORRIDOR_MAX.y),
		C_FACADE)
	# Ground-floor windows and the stair door, west face (the yard) and east face.
	for z: float in [-0.6, 3.2]:
		_box(tool, Vector3(x0 - 0.02, YARD_Y + 1.1, z - 0.7), Vector3(x0, YARD_Y + 2.5, z + 0.7), C_FACADE_DARK)
	_box(tool, Vector3(x0 - 0.02, YARD_Y, YARD_DOOR_Z - 0.55), Vector3(x0, YARD_Y + 2.2, YARD_DOOR_Z + 0.55), C_WOOD)
	for z: float in [-4.0, 0.0, 4.0, 8.0]:
		_box(tool, Vector3(CORRIDOR_MAX.x, YARD_Y + 1.1, z - 0.8), Vector3(CORRIDOR_MAX.x + 0.02, YARD_Y + 2.5, z + 0.8), C_FACADE_DARK)
	# The upper storey's skin, seen from the yard, cut by the same two openings.
	var skin := x0 - 0.02
	var spans: Array = [
		[ROOM_MIN.y - WALL, FRONT_WINDOW.position.x, 0.0, WALL_HEIGHT],
		[FRONT_WINDOW.position.x, FRONT_WINDOW.end.x, 0.0, FRONT_WINDOW.position.y],
		[FRONT_WINDOW.position.x, FRONT_WINDOW.end.x, FRONT_WINDOW.end.y, WALL_HEIGHT],
		[FRONT_WINDOW.end.x, BACK_OPENING.position.x, 0.0, WALL_HEIGHT],
		[BACK_OPENING.position.x, BACK_OPENING.end.x, 0.0, BACK_OPENING.position.y],
		[BACK_OPENING.position.x, BACK_OPENING.end.x, BACK_OPENING.end.y, WALL_HEIGHT],
		[BACK_OPENING.end.x, ROOM_MAX.y + WALL, 0.0, WALL_HEIGHT],
	]
	for span: Array in spans:
		_box(tool, Vector3(skin, float(span[2]), float(span[0])), Vector3(x0, float(span[3]), float(span[1])), C_FACADE)
	# The corridor: its floor, the next classroom's wall, the stairwell's wall, the rail.
	_box(tool, Vector3(ROOM_MAX.x + WALL, -0.2, CORRIDOR_MIN.y), Vector3(CORRIDOR_MAX.x, 0.0, CORRIDOR_MAX.y), C_CORRIDOR)
	_box(tool, Vector3(ROOM_MAX.x, 0.0, ROOM_MAX.y + WALL), Vector3(ROOM_MAX.x + WALL, WALL_HEIGHT, CORRIDOR_MAX.y), C_FACADE)
	_box(tool, Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MIN.y), Vector3(ROOM_MAX.x + WALL, WALL_HEIGHT, ROOM_MIN.y - WALL), C_FACADE)
	_box(tool, Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MAX.y), Vector3(CORRIDOR_MAX.x, WALL_HEIGHT, CORRIDOR_MAX.y + WALL), C_FACADE)
	_box(tool, Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MIN.y - WALL), Vector3(CORRIDOR_MAX.x, WALL_HEIGHT, CORRIDOR_MIN.y), C_FACADE)
	_box(tool, Vector3(ROOM_MAX.x + WALL - 0.02, 0.0, NEIGHBOUR_DOOR_Z - 0.5),
		Vector3(ROOM_MAX.x + WALL + 0.02, DOOR_HEIGHT, NEIGHBOUR_DOOR_Z + 0.5), C_REAR_DOOR.darkened(0.2))
	var rail_x := CORRIDOR_MAX.x - 0.08
	_box(tool, Vector3(rail_x - 0.04, 0.98, CORRIDOR_MIN.y), Vector3(rail_x + 0.04, 1.04, CORRIDOR_MAX.y), C_IRON)
	_box(tool, Vector3(rail_x - 0.02, 0.5, CORRIDOR_MIN.y), Vector3(rail_x + 0.02, 0.53, CORRIDOR_MAX.y), C_IRON)
	var post := CORRIDOR_MIN.y
	while post <= CORRIDOR_MAX.y:
		_box(tool, Vector3(rail_x - 0.03, 0.0, post - 0.03), Vector3(rail_x + 0.03, 1.0, post + 0.03), C_IRON)
		post += 1.2
	# The stair head: a dark well with the edges of the steps going down, railed off on
	# its open sides.
	_box(tool, Vector3(STAIR_MIN.x + 0.2, 0.0, STAIR_MIN.y), Vector3(STAIR_MAX.x, 0.004, STAIR_MAX.y), C_FACADE_DARK.darkened(0.4))
	for step in 6:
		var z := STAIR_MAX.y - 0.12 - step * 0.26
		_box(tool, Vector3(STAIR_MIN.x + 0.3, 0.004, z - 0.02), Vector3(STAIR_MAX.x - 0.1, 0.008, z + 0.02),
			C_FACADE.darkened(0.35 + step * 0.08))
	_box(tool, Vector3(STAIR_MIN.x + 1.0, 0.98, STAIR_MAX.y - 0.03), Vector3(STAIR_MAX.x, 1.04, STAIR_MAX.y + 0.03), C_IRON)
	_box(tool, Vector3(STAIR_MAX.x - 0.03, 0.98, STAIR_MIN.y), Vector3(STAIR_MAX.x + 0.03, 1.04, STAIR_MAX.y), C_IRON)
	# The ground, the yard's far wall, its fences, the washing line's posts.
	_box(tool, Vector3(-24.0, YARD_Y - 0.2, -14.0), Vector3(24.0, YARD_Y, 16.0), C_YARD)
	_box(tool, Vector3(YARD_MIN.x - 0.3, YARD_Y, YARD_MIN.y), Vector3(YARD_MIN.x, YARD_Y + 1.3, YARD_MAX.y), C_BRICK)
	for z: float in [YARD_MIN.y, YARD_MAX.y]:
		_box(tool, Vector3(YARD_MIN.x, YARD_Y + 0.85, z - 0.03), Vector3(x0, YARD_Y + 0.9, z + 0.03), C_IRON)
		var fence := YARD_MIN.x
		while fence < x0:
			_box(tool, Vector3(fence - 0.025, YARD_Y, z - 0.025), Vector3(fence + 0.025, YARD_Y + 0.9, z + 0.025), C_IRON)
			fence += 0.6
	for z: float in [-4.0, 4.0]:
		_box(tool, Vector3(-16.04, YARD_Y, z - 0.04), Vector3(-15.96, YARD_Y + 2.2, z + 0.04), C_IRON)
	_box(tool, Vector3(-16.01, YARD_Y + 2.1, -4.0), Vector3(-15.99, YARD_Y + 2.12, 4.0), C_IRON)
	_commit("Outside", tool, outside_material)
	# Washing on the line, and the trees: cut-outs (the visual lab's paper).
	var whites: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.7, 0.78, 0.88), Color(0.94, 0.86, 0.72)]
	for index in 5:
		var texture := Art.shirt(whites[index % whites.size()], 60 + index)
		var material := Kit.textured_paper(texture, Vector2(0.7, 0.7), 40.0 + index, 0.0)
		var where := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-16.0, YARD_Y + 1.78, -3.0 + index * 1.5))
		Kit.sheet(self, "Washing%d" % index, Vector2(0.7, 0.7), where, material)
	var trees: Array = [
		[Vector3(-13.0, YARD_Y, -8.6), -PI * 0.5], [Vector3(-11.5, YARD_Y, 7.2), -PI * 0.5],
		[Vector3(13.6, YARD_Y, -8.0), PI * 0.5], [Vector3(14.2, YARD_Y, 12.0), PI * 0.5],
		[Vector3(15.0, YARD_Y, 2.0), PI * 0.5],
	]
	for index in trees.size():
		var entry: Array = trees[index]
		var texture := Art.tree(Color(0.32, 0.46, 0.34), 70 + index)
		var material := Kit.textured_paper(texture, Vector2(4.0, 6.0), 50.0 + index, 0.0)
		var base: Vector3 = entry[0]
		var where := Transform3D(Basis(Vector3.UP, float(entry[1])), base + Vector3(0.0, 3.0, 0.0))
		Kit.sheet(self, "Tree%d" % index, Vector2(4.0, 6.0), where, material)
	# Colliders: the corridor's rail and ends, the stair well, the yard's ground and
	# bounds, the building's face below the windows.
	_solid("CorridorRail", Vector3(rail_x - 0.1, 0.0, CORRIDOR_MIN.y), Vector3(CORRIDOR_MAX.x + 0.2, 1.2, CORRIDOR_MAX.y))
	_solid("CorridorNeighbourWall", Vector3(ROOM_MAX.x, 0.0, ROOM_MAX.y), Vector3(ROOM_MAX.x + WALL, WALL_HEIGHT, CORRIDOR_MAX.y))
	_solid("CorridorStairWall", Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MIN.y), Vector3(ROOM_MAX.x + WALL, WALL_HEIGHT, ROOM_MIN.y))
	_solid("CorridorSouthEnd", Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MAX.y), Vector3(CORRIDOR_MAX.x, WALL_HEIGHT, CORRIDOR_MAX.y + WALL))
	_solid("CorridorNorthEnd", Vector3(ROOM_MAX.x, 0.0, CORRIDOR_MIN.y - WALL), Vector3(CORRIDOR_MAX.x, WALL_HEIGHT, CORRIDOR_MIN.y))
	_solid("StairWell", Vector3(STAIR_MIN.x + 0.2, 0.0, STAIR_MIN.y), Vector3(STAIR_MAX.x + 0.05, 1.1, STAIR_MAX.y + 0.05))
	_solid("YardGround", Vector3(-24.0, YARD_Y - 0.4, -14.0), Vector3(x0, YARD_Y, 16.0))
	_solid("YardFarWall", Vector3(YARD_MIN.x - 0.3, YARD_Y, YARD_MIN.y), Vector3(YARD_MIN.x, YARD_Y + 1.3, YARD_MAX.y))
	_solid("YardFenceNorth", Vector3(YARD_MIN.x, YARD_Y, YARD_MIN.y - 0.1), Vector3(x0, YARD_Y + 1.2, YARD_MIN.y))
	_solid("YardFenceSouth", Vector3(YARD_MIN.x, YARD_Y, YARD_MAX.y), Vector3(x0, YARD_Y + 1.2, YARD_MAX.y + 0.1))
	_solid("Facade", Vector3(x0 - 0.02, YARD_Y, YARD_MIN.y - 0.1), Vector3(x0, 0.0, YARD_MAX.y + 0.1))
	_solid("WashingPosts", Vector3(-16.08, YARD_Y, -4.1), Vector3(-15.92, YARD_Y + 2.2, -3.9))
	_solid("WashingPostsSouth", Vector3(-16.08, YARD_Y, 3.9), Vector3(-15.92, YARD_Y + 2.2, 4.1))


# --- Furniture -----------------------------------------------------------------------------


func _build_furniture() -> void:
	var tool := Kit.begin_field()
	for column: int in DESK_COLUMNS.size():
		for row: int in DESK_ROWS.size():
			var desk := Vector3(DESK_COLUMNS[column], 0.0, DESK_ROWS[row])
			_desk(tool, desk)
			_chair(tool, desk + Vector3(0.0, 0.0, CHAIR_BACK))
			_solid("Desk%d%d" % [column, row], desk + Vector3(-0.6, 0.0, -0.275), desk + Vector3(0.6, 0.76, 0.275))
			var is_player := desk.is_equal_approx(PLAYER_DESK)
			if not is_player:
				var chair := desk + Vector3(0.0, 0.0, CHAIR_BACK)
				_solid("Chair%d%d" % [column, row], chair + Vector3(-0.22, 0.0, -0.21), chair + Vector3(0.22, 0.9, 0.21))
	# The protagonist's schoolbag, on the hook at the side of his desk.
	var bag := PLAYER_DESK + Vector3(0.66, 0.0, 0.05)
	_box(tool, bag + Vector3(-0.06, 0.3, -0.17), bag + Vector3(0.06, 0.64, 0.17), Color(0.42, 0.34, 0.24))
	_box(tool, bag + Vector3(-0.07, 0.5, -0.17), bag + Vector3(0.07, 0.66, 0.17), Color(0.34, 0.27, 0.2))
	# A jar of bean sprouts on the front window's sill: the biology lesson's experiment.
	var sill := Vector3(ROOM_MIN.x + 0.08, FRONT_WINDOW.position.y, FRONT_WINDOW.position.x + 0.45)
	_box(tool, sill + Vector3(-0.06, 0.0, -0.06), sill + Vector3(0.06, 0.15, 0.06), Color(0.72, 0.8, 0.76))
	for sprout in 3:
		var at := sill + Vector3(-0.02 + sprout * 0.02, 0.15, -0.02 + sprout * 0.015)
		_box(tool, at + Vector3(-0.006, 0.0, -0.006), at + Vector3(0.006, 0.09 + sprout * 0.03, 0.006), Color(0.5, 0.66, 0.36))
	var instance := _commit("Furniture", tool, room_material)
	instance.material_overlay = hull_material


func _desk(tool: SurfaceTool, desk: Vector3) -> void:
	_box(tool, desk + Vector3(-0.6, 0.71, -0.275), desk + Vector3(0.6, 0.76, 0.275), C_DESK_TOP)
	_box(tool, desk + Vector3(-0.56, 0.56, -0.25), desk + Vector3(0.56, 0.71, 0.2), C_DESK_BODY)
	for corner: Vector2 in [Vector2(-0.55, -0.23), Vector2(0.55, -0.23), Vector2(-0.55, 0.23), Vector2(0.55, 0.23)]:
		var at := desk + Vector3(corner.x, 0.0, corner.y)
		_box(tool, at + Vector3(-0.02, 0.0, -0.02), at + Vector3(0.02, 0.71, 0.02), C_IRON)


func _chair(tool: SurfaceTool, chair: Vector3) -> void:
	_box(tool, chair + Vector3(-0.21, 0.43, -0.2), chair + Vector3(0.21, 0.47, 0.2), C_CHAIR)
	_box(tool, chair + Vector3(-0.21, 0.62, 0.17), chair + Vector3(0.21, 0.86, 0.2), C_CHAIR)
	for corner: Vector2 in [Vector2(-0.18, -0.17), Vector2(0.18, -0.17), Vector2(-0.18, 0.18), Vector2(0.18, 0.18)]:
		var at := chair + Vector3(corner.x, 0.0, corner.y)
		_box(tool, at + Vector3(-0.015, 0.0, -0.015), at + Vector3(0.015, 0.45, 0.015), C_IRON)
	_box(tool, chair + Vector3(-0.2, 0.45, 0.17), chair + Vector3(-0.17, 0.86, 0.2), C_IRON)
	_box(tool, chair + Vector3(0.17, 0.45, 0.17), chair + Vector3(0.2, 0.86, 0.2), C_IRON)


# --- The drawn fourth wall and the other pen lines ------------------------------------------


func _build_ink() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var tool := Kit.begin_field()
	var w := 0.03
	var ex := ROOM_MAX.x + WALL * 0.5
	var sz := ROOM_MAX.y + WALL * 0.5
	var nz := ROOM_MIN.y - WALL
	var wx := ROOM_MIN.x - WALL
	var h := WALL_HEIGHT
	# Where the east and south walls would be: their top edges and corners.
	_ink_line(tool, Vector3(ex, h, nz), Vector3(ex, h, sz), w, rng)
	_ink_line(tool, Vector3(wx, h, sz), Vector3(ex, h, sz), w, rng)
	_ink_line(tool, Vector3(ex, DADO, nz), Vector3(ex, h, nz), w, rng)
	_ink_line(tool, Vector3(ex, DADO, sz), Vector3(ex, h, sz), w, rng)
	_ink_line(tool, Vector3(wx, DADO, sz), Vector3(wx, h, sz), w, rng)
	# A ghost of the back board and the timetable that hang on the south wall.
	_ink_line(tool, Vector3(-4.0, 1.4, sz), Vector3(2.0, 1.4, sz), 0.018, rng)
	_ink_line(tool, Vector3(-4.0, 2.5, sz), Vector3(2.0, 2.5, sz), 0.018, rng)
	_ink_line(tool, Vector3(-4.0, 1.4, sz), Vector3(-4.0, 2.5, sz), 0.018, rng)
	_ink_line(tool, Vector3(2.0, 1.4, sz), Vector3(2.0, 2.5, sz), 0.018, rng)
	# Door frames, in the drawn wall.
	for door_z: float in [FRONT_DOOR_Z, REAR_DOOR_Z]:
		var a := door_z - DOOR_WIDTH * 0.5
		var b := door_z + DOOR_WIDTH * 0.5
		_ink_line(tool, Vector3(ex, 0.0, a), Vector3(ex, DOOR_HEIGHT + 0.05, a), w, rng)
		_ink_line(tool, Vector3(ex, 0.0, b), Vector3(ex, DOOR_HEIGHT + 0.05, b), w, rng)
		_ink_line(tool, Vector3(ex, DOOR_HEIGHT + 0.05, a), Vector3(ex, DOOR_HEIGHT + 0.05, b), w, rng)
	# The real walls' top edges, and the window and opening frames.
	_ink_line(tool, Vector3(wx, h, nz), Vector3(ex, h, nz), 0.02, rng)
	_ink_line(tool, Vector3(wx, h, nz), Vector3(wx, h, sz), 0.02, rng)
	for rect: Rect2 in [FRONT_WINDOW, BACK_OPENING]:
		var x := ROOM_MIN.x + 0.005
		_ink_line(tool, Vector3(x, rect.position.y, rect.position.x), Vector3(x, rect.end.y, rect.position.x), 0.025, rng)
		_ink_line(tool, Vector3(x, rect.position.y, rect.end.x), Vector3(x, rect.end.y, rect.end.x), 0.025, rng)
		_ink_line(tool, Vector3(x, rect.end.y, rect.position.x), Vector3(x, rect.end.y, rect.end.x), 0.025, rng)
		_ink_line(tool, Vector3(x, rect.position.y, rect.position.x), Vector3(x, rect.position.y, rect.end.x), 0.025, rng)
	# The front window's cross bar.
	var mid := FRONT_WINDOW.position.x + FRONT_WINDOW.size.x * 0.5
	_ink_line(tool, Vector3(ROOM_MIN.x - 0.1, FRONT_WINDOW.position.y, mid), Vector3(ROOM_MIN.x - 0.1, FRONT_WINDOW.end.y, mid), 0.035, rng)
	# The platform's lip.
	_ink_line(tool, Vector3(PLATFORM_MIN.x, PLATFORM_HEIGHT + 0.005, PLATFORM_MAX.y),
		Vector3(PLATFORM_MAX.x, PLATFORM_HEIGHT + 0.005, PLATFORM_MAX.y), 0.02, rng)
	var instance := _commit("Ink", tool, ink_material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The window shows a picture of outside, not outside: one-sided, seen only from in.
	var view := _window_view_texture()
	var pane := StandardMaterial3D.new()
	pane.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pane.albedo_texture = view
	pane.cull_mode = BaseMaterial3D.CULL_BACK
	var centre := Vector3(ROOM_MIN.x - 0.11, FRONT_WINDOW.position.y + FRONT_WINDOW.size.y * 0.5, mid)
	var sheet := Kit.sheet(self, "WindowView", Vector2(FRONT_WINDOW.size.x, FRONT_WINDOW.size.y),
		Transform3D(Basis(Vector3.UP, PI * 0.5), centre), pane)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The ordinary view through the front window: pale sky, the yard's low wall, the washing.
func _window_view_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var image := Image.create_empty(300, 260, false, Image.FORMAT_RGBA8)
	for row in 260:
		var t := float(row) / 260.0
		image.fill_rect(Rect2i(0, row, 300, 1), Color(0.74, 0.82, 0.88).lerp(Color(0.9, 0.88, 0.8), t))
	image.fill_rect(Rect2i(0, 170, 300, 90), C_YARD)
	image.fill_rect(Rect2i(0, 150, 300, 26), C_BRICK)
	Kit.stroke(image, Vector2(20, 96), Vector2(280, 104), 2.0, C_IRON, rng)
	for index in 4:
		var x := 40.0 + index * 62.0
		var shirt := PackedVector2Array([
			Vector2(x, 100), Vector2(x + 34, 101), Vector2(x + 44, 112), Vector2(x + 36, 118),
			Vector2(x + 34, 146), Vector2(x, 146), Vector2(x, 118), Vector2(x - 8, 112)
		])
		var colours: Array[Color] = [Color(0.96, 0.95, 0.9), Color(0.7, 0.78, 0.88)]
		Kit.fill_polygon(image, shirt, colours[index % 2], rng)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# --- The lectern ---------------------------------------------------------------------------


func _build_lectern() -> void:
	lectern = Node3D.new()
	lectern.name = "Lectern"
	lectern.position = LECTERN
	add_child(lectern)
	var size := LECTERN_SIZE
	var tool := Kit.begin_field()
	_box(tool, Vector3(-0.44, 0.0, -0.25), Vector3(0.44, 0.08, 0.25), C_IRON)
	_box(tool, Vector3(-size.x * 0.5, 0.08, -size.z * 0.5), Vector3(size.x * 0.5, size.y, size.z * 0.5), C_LECTERN)
	_box(tool, Vector3(-size.x * 0.5 - 0.01, 0.08, -size.z * 0.5), Vector3(-size.x * 0.5 + 0.04, size.y, size.z * 0.5), C_LECTERN_SIDE)
	_box(tool, Vector3(size.x * 0.5 - 0.04, 0.08, -size.z * 0.5), Vector3(size.x * 0.5 + 0.01, size.y, size.z * 0.5), C_LECTERN_SIDE)
	# One bone stripe down the front, toward the class: the lectern's only ornament.
	_box(tool, Vector3(-0.07, 0.12, size.z * 0.5), Vector3(0.07, size.y - 0.08, size.z * 0.5 + 0.012), C_BONE)
	var body := _commit_into(lectern, "Body", tool, room_material)
	body.material_overlay = hull_material
	lectern_body = body
	# The pointer, leaning on the side that faces the room.
	var pointer := Kit.begin_field()
	_box(pointer, Vector3(-0.012, 0.0, -0.012), Vector3(0.012, 1.15, 0.012), C_WOOD)
	var pointer_mesh := _commit_into(lectern, "Pointer", pointer, room_material)
	pointer_mesh.position = Vector3(size.x * 0.5 + 0.1, 0.0, 0.18)
	pointer_mesh.rotation = Vector3(0.0, 0.0, deg_to_rad(6.0))
	pointer_mesh.material_overlay = fine_hull_material
	# The top, and on it B's things. The top is its own node: when the lectern grows in
	# memory the body stretches and the top rides up with everything on it, unstretched.
	lectern_top = Node3D.new()
	lectern_top.name = "Top"
	lectern_top.position = Vector3(0.0, size.y, 0.0)
	lectern.add_child(lectern_top)
	var slab := Kit.begin_field()
	_box(slab, Vector3(-0.56, 0.0, -0.36), Vector3(0.56, LECTERN_TOP, 0.36), C_BONE)
	_box(slab, Vector3(-0.56, LECTERN_TOP, 0.33), Vector3(0.56, LECTERN_TOP + 0.03, 0.36), C_IRON)
	var slab_mesh := _commit_into(lectern_top, "Slab", slab, room_material)
	slab_mesh.material_overlay = hull_material
	set_square = _build_set_square()
	var register := Kit.begin_field()
	_box(register, Vector3(-0.15, 0.0, -0.11), Vector3(0.15, 0.03, 0.11), Color(0.18, 0.2, 0.34))
	_box(register, Vector3(-0.14, 0.03, -0.1), Vector3(0.14, 0.032, 0.1), Color(0.9, 0.88, 0.82))
	var register_mesh := _commit_into(lectern_top, "Register", register, room_material)
	register_mesh.position = Vector3(0.2, LECTERN_TOP, -0.08)
	register_mesh.rotation.y = deg_to_rad(-8.0)
	register_mesh.material_overlay = fine_hull_material
	var pencil := Kit.begin_field()
	_box(pencil, Vector3(-0.09, 0.0, -0.006), Vector3(0.09, 0.012, 0.006), Color(0.82, 0.16, 0.12))
	var pencil_mesh := _commit_into(lectern_top, "RedPencil", pencil, room_material)
	pencil_mesh.position = Vector3(0.22, LECTERN_TOP + 0.032, -0.05)
	pencil_mesh.rotation.y = deg_to_rad(24.0)
	var chalk := Kit.begin_field()
	_box(chalk, Vector3(-0.07, 0.0, -0.045), Vector3(0.07, 0.07, 0.045), Color(0.9, 0.88, 0.8))
	for stick in 4:
		var x := -0.045 + stick * 0.03
		_box(chalk, Vector3(x - 0.008, 0.07, -0.03), Vector3(x + 0.008, 0.085, 0.03), Color(0.98, 0.98, 0.95))
	var chalk_mesh := _commit_into(lectern_top, "ChalkBox", chalk, room_material)
	chalk_mesh.position = Vector3(0.4, LECTERN_TOP, 0.17)
	chalk_mesh.material_overlay = fine_hull_material
	var shape := Kit.solid(lectern, "Collider", Vector3(size.x, size.y + LECTERN_TOP, size.z),
		Vector3(0.0, (size.y + LECTERN_TOP) * 0.5, 0.0))
	solids.append(shape)


## B's set square: a wooden right triangle with its triangular hole, cracked across one
## leg and held with a strip of tape. Its hole is the lectern's top showing through.
func _build_set_square() -> MeshInstance3D:
	var tool := Kit.begin_field()
	var t := 0.014
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(0.55, 0.0, 0.0)
	var c := Vector3(0.0, 0.0, -0.42)
	var up := Vector3(0.0, t, 0.0)
	var wood: Array[Color] = [Color(0.78, 0.6, 0.38)]
	var edge: Array[Color] = [Color(0.6, 0.44, 0.26)]
	Kit.field_quad(tool, a + up, b + up, c + up, c + up, wood)
	Kit.field_quad(tool, a, c, b, b, wood)
	for pair: Array in [[a, b], [b, c], [c, a]]:
		var p: Vector3 = pair[0]
		var q: Vector3 = pair[1]
		Kit.field_quad(tool, p, q, q + up, p + up, edge)
	var inset_a := Vector3(0.07, t + 0.001, -0.06)
	var inset_b := Vector3(0.33, t + 0.001, -0.06)
	var inset_c := Vector3(0.07, t + 0.001, -0.26)
	var hole: Array[Color] = [C_BONE]
	Kit.field_quad(tool, inset_a, inset_b, inset_c, inset_c, hole)
	_box(tool, Vector3(0.36, t, -0.03), Vector3(0.38, t + 0.002, 0.002), C_INK)
	_box(tool, Vector3(0.32, t, -0.05), Vector3(0.42, t + 0.003, 0.004), Color(0.92, 0.9, 0.78, 1.0))
	var mesh := _commit_into(lectern_top, "SetSquare", tool, room_material)
	mesh.position = Vector3(-0.5, LECTERN_TOP, 0.24)
	mesh.rotation.y = deg_to_rad(10.0)
	mesh.material_overlay = fine_hull_material
	return mesh


func _commit_into(parent: Node3D, node_name: String, tool: SurfaceTool, material: Material) -> MeshInstance3D:
	return Kit.commit_field(parent, node_name, tool, material, false)


## Grows the lectern in memory: 0 = as built, 1 = as tall as it was. Collision is the
## built size either way; only the picture changes.
func set_lectern_stretch(amount: float) -> void:
	var stretch := 1.0 + 0.3 * clampf(amount, 0.0, 1.0)
	lectern_body.scale = Vector3(1.0, stretch, 1.0)
	lectern_top.position.y = LECTERN_SIZE.y * stretch


# --- The front wall: board, charts, clock ------------------------------------------------


func _build_front_wall() -> void:
	var z := ROOM_MIN.y
	var tool := Kit.begin_field()
	_box(tool, Vector3(-2.6, 0.95, z), Vector3(1.8, 2.25, z + 0.04), C_BOARD)
	_box(tool, Vector3(-2.64, 0.91, z), Vector3(1.84, 0.95, z + 0.1), C_WOOD)
	var board := _commit("Board", tool, room_material)
	board.material_overlay = hull_material
	var wing := Kit.textured_paper(Art.wing_chart(), Vector2(0.95, 1.25), 21.0, 0.03)
	Kit.sheet(self, "WingChart", Vector2(0.95, 1.25), Transform3D(Basis.IDENTITY, Vector3(-5.4, 1.95, z + 0.01)), wing)
	var cell := Kit.textured_paper(Art.cell_chart(), Vector2(0.95, 1.25), 22.0, 0.03)
	Kit.sheet(self, "CellChart", Vector2(0.95, 1.25), Transform3D(Basis.IDENTITY, Vector3(3.9, 1.85, z + 0.01)), cell)
	var face := StandardMaterial3D.new()
	face.albedo_texture = Art.clock_face()
	face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var clock_centre := Vector3(2.7, 2.55, z + 0.02)
	Kit.sheet(self, "Clock", Vector2(0.56, 0.56), Transform3D(Basis.IDENTITY, clock_centre), face)
	clock_hour = _clock_hand("ClockHour", clock_centre + Vector3(0, 0, 0.01), 0.14, 0.025)
	clock_minute = _clock_hand("ClockMinute", clock_centre + Vector3(0, 0, 0.015), 0.22, 0.016)
	set_clock(10, 52)


func _clock_hand(node_name: String, centre: Vector3, length: float, width: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = centre
	add_child(pivot)
	var tool := Kit.begin_field()
	Kit.field_box(tool, Vector3(0.0, length * 0.5 - 0.02, 0.0), Vector3(width, length, 0.004), C_INK)
	Kit.commit_field(pivot, "Hand", tool, ink_material, false)
	return pivot


func set_clock(hours: int, minutes: int) -> void:
	var minute_angle := TAU * float(minutes) / 60.0
	var hour_angle := TAU * (float(hours % 12) + float(minutes) / 60.0) / 12.0
	clock_minute.rotation.z = -minute_angle
	clock_hour.rotation.z = -hour_angle


# --- The curtain and what is behind it -----------------------------------------------------


func _build_curtain() -> void:
	# Behind the curtain: a blank sheet, both sides white, unlit. From the yard it is a
	# white rectangle in the face of the building.
	var blank := StandardMaterial3D.new()
	blank.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blank.cull_mode = BaseMaterial3D.CULL_DISABLED
	blank.albedo_color = Color(0.97, 0.96, 0.93)
	var opening := opening_centre()
	blank_sheet = Kit.sheet(self, "BlankSheet", Vector2(BACK_OPENING.size.x, BACK_OPENING.size.y),
		Transform3D(Basis(Vector3.UP, PI * 0.5), opening), blank)
	# The curtain: floor to rod, deep pleats. Its node sits at the south end of the
	# opening; drawing it squeezes the pleats toward that end.
	curtain = Node3D.new()
	curtain.name = "Curtain"
	curtain.position = Vector3(ROOM_MIN.x + 0.14, 0.0, BACK_OPENING.end.x + 0.2)
	add_child(curtain)
	var width := BACK_OPENING.size.x + 0.4
	var tool := Kit.begin_field()
	var strips := 22
	for strip in strips:
		var z0 := -width * float(strip) / strips
		var z1 := -width * float(strip + 1) / strips
		# Alternate deep and shallow: a pleat every strip.
		var x0 := 0.06 if strip % 2 == 0 else -0.02
		var x1 := -0.02 if strip % 2 == 0 else 0.06
		var shade := C_CURTAIN.lightened(0.12) if strip % 2 == 0 else C_CURTAIN.darkened(0.2)
		var colours: Array[Color] = [shade]
		Kit.field_quad(tool, Vector3(x0, 0.02, z0), Vector3(x1, 0.02, z1),
			Vector3(x1, WALL_HEIGHT - 0.08, z1), Vector3(x0, WALL_HEIGHT - 0.08, z0), colours)
	var cloth := Kit.commit_field(curtain, "Cloth", tool, room_material, false)
	cloth.material_overlay = fine_hull_material
	var rod := Kit.begin_field()
	_box(rod, Vector3(0.02, WALL_HEIGHT - 0.1, -width - 0.1), Vector3(0.06, WALL_HEIGHT - 0.06, 0.1), C_IRON)
	_commit("CurtainRod", rod, room_material).position = curtain.position


## 0 = closed across the opening, 1 = drawn to its south end.
func set_curtain_open(amount: float) -> void:
	var open := clampf(amount, 0.0, 1.0)
	curtain.scale = Vector3(1.0, 1.0, lerpf(1.0, 0.14, open))


# --- Doors ---------------------------------------------------------------------------------


func _build_doors() -> void:
	var x := ROOM_MAX.x + WALL * 0.5
	door_pivot = Node3D.new()
	door_pivot.name = "FrontDoor"
	door_pivot.position = Vector3(x, 0.0, FRONT_DOOR_Z + DOOR_WIDTH * 0.5)
	add_child(door_pivot)
	var tool := Kit.begin_field()
	_box(tool, Vector3(-0.025, 0.0, -DOOR_WIDTH + 0.02), Vector3(0.025, DOOR_HEIGHT, -0.02), C_DOOR)
	_box(tool, Vector3(-0.03, 1.5, -DOOR_WIDTH + 0.22), Vector3(0.03, 1.9, -0.22), C_DOOR.lightened(0.2))
	_box(tool, Vector3(-0.06, 0.98, -DOOR_WIDTH + 0.08), Vector3(0.06, 1.02, -DOOR_WIDTH + 0.16), C_IRON)
	var panel := Kit.commit_field(door_pivot, "Panel", tool, room_material, false)
	panel.material_overlay = hull_material
	var blocker := _solid("FrontDoorBlocker",
		Vector3(ROOM_MAX.x, 0.0, FRONT_DOOR_Z - DOOR_WIDTH * 0.5), Vector3(ROOM_MAX.x + WALL, DOOR_HEIGHT, FRONT_DOOR_Z + DOOR_WIDTH * 0.5))
	door_blocker = blocker.get_child(0) as CollisionShape3D
	var rear := Kit.begin_field()
	_box(rear, Vector3(x - 0.025, 0.0, REAR_DOOR_Z - DOOR_WIDTH * 0.5 + 0.02), Vector3(x + 0.025, DOOR_HEIGHT, REAR_DOOR_Z + DOOR_WIDTH * 0.5 - 0.02), C_REAR_DOOR)
	_box(rear, Vector3(x - 0.06, 0.98, REAR_DOOR_Z - 0.4), Vector3(x + 0.06, 1.02, REAR_DOOR_Z - 0.32), C_IRON)
	_commit("RearDoor", rear, room_material).material_overlay = hull_material
	_solid("RearDoorBlocker", Vector3(ROOM_MAX.x, 0.0, REAR_DOOR_Z - DOOR_WIDTH * 0.5), Vector3(ROOM_MAX.x + WALL, DOOR_HEIGHT, REAR_DOOR_Z + DOOR_WIDTH * 0.5))


## 0 = shut, 1 = open outward into the corridor. The doorway is passable past half-way.
func set_door_open(amount: float) -> void:
	var open := clampf(amount, 0.0, 1.0)
	door_pivot.rotation.y = -deg_to_rad(100.0) * open
	door_blocker.set_deferred("disabled", open > 0.5)


# --- The fluorescent tubes -----------------------------------------------------------------


func _build_lamps() -> void:
	for index in 2:
		var x := -1.6 + index * 3.2
		var tool := Kit.begin_field()
		Kit.field_box(tool, Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.06, 1.3), Color.WHITE)
		var tube := Kit.commit_field(self, "Lamp%d" % index, tool, lamp_material, false)
		tube.position = Vector3(x, 2.95, 1.4)
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamps.append(tube)
		var wires := Kit.begin_field()
		for end: float in [-0.5, 0.5]:
			Kit.field_box(wires, Vector3(0.0, 2.5, end), Vector3(0.01, 5.0, 0.01), C_INK)
		var wire_mesh := Kit.commit_field(tube, "Wires", wires, ink_material, false)
		wire_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The tubes are not there until the bell: they catch into being with their own flicker.
func set_lamps(level: float) -> void:
	for tube: MeshInstance3D in lamps:
		tube.visible = level > 0.0
	lamp_material.albedo_color = Color(0.46, 0.48, 0.47).lerp(Color(1.0, 1.0, 0.94), clampf(level, 0.0, 1.0))


# --- The class -----------------------------------------------------------------------------


func _build_classmates() -> void:
	var uniforms: Array[Color] = [
		Color(0.2, 0.26, 0.42), Color(0.3, 0.38, 0.36), Color(0.24, 0.24, 0.3), Color(0.36, 0.3, 0.4)
	]
	var hairs: Array[Color] = [Color(0.1, 0.09, 0.1), Color(0.18, 0.13, 0.1)]
	for index in CLASSMATES.size():
		var seat: Vector2i = CLASSMATES[index]
		var desk := Vector3(DESK_COLUMNS[seat.x], 0.0, DESK_ROWS[seat.y])
		var texture := Art.classmate(uniforms[index % uniforms.size()], hairs[index % hairs.size()], 100 + index)
		var material := Kit.textured_paper(texture, Vector2(0.62, 0.78), 80.0 + index, 0.0)
		var tilt := deg_to_rad(float(index % 3 - 1) * 4.0)
		var where := Transform3D(Basis(Vector3.UP, tilt), desk + Vector3(0.0, 0.84, CHAIR_BACK + 0.02))
		var sheet := Kit.sheet(self, "Classmate%d" % index, Vector2(0.62, 0.78), where, material)
		classmates.append(sheet)


# --- Painted marks: the light and shadow that are not real ---------------------------------


func _build_marks() -> void:
	var shadow_ink := Color(0.12, 0.1, 0.22, 1.0)
	b_shadow = _mark("BShadow", Art.b_shadow(), Vector2(1.9, 3.0),
		Transform3D(Basis.IDENTITY, Vector3(-4.95, PLATFORM_HEIGHT + 1.5, ROOM_MIN.y + 0.03)),
		shadow_ink, 0, 0.84, 0.0)
	# The set square's shadow: from the foot of the platform, below the lectern, across the
	# floor to the front edge of the protagonist's desk.
	var start := Vector3(LECTERN.x + 0.3, 0.006, PLATFORM_MAX.y + RAMP + 0.05)
	var end := Vector3(PLAYER_DESK.x - 0.35, 0.006, PLAYER_DESK.z - 0.3)
	var run := end - start
	var length := run.length()
	var direction := run / length
	var yaw := atan2(-direction.x, -direction.z)
	square_shadow = _mark("SquareShadow", Art.set_square_shadow(), Vector2(0.9, length),
		Transform3D(Kit.floor_basis(yaw), start + run * 0.5), shadow_ink, 0, 0.78, 0.0)
	chalk_overlay = _mark("ChalkGhosts", Art.chalk_ghosts(), Vector2(4.3, 1.25),
		Transform3D(Basis.IDENTITY, Vector3(-0.4, 1.6, ROOM_MIN.y + 0.045)),
		Color(0.92, 0.92, 0.86, 1.0), 2, 0.3, 1.0)
	ring_mark = _mark("RedRing", Art.ring(), Vector2(1.7, 1.7),
		Transform3D(Kit.floor_basis(0.0), Vector3(0.0, 0.008, 0.0)),
		Color(0.86, 0.1, 0.08, 1.0), 1, 0.95, 0.0)
	ring_mark.visible = false
	book_mark = _mark("BookOutline", Art.book_outline(), Vector2(0.42, 0.32),
		Transform3D(Kit.floor_basis(0.1), PLAYER_DESK + Vector3(-0.15, 0.765, 0.02)),
		Color(0.22, 0.18, 0.32, 1.0), 2, 0.9, 0.0)


static func set_mark_amount(mark: MeshInstance3D, amount: float) -> void:
	var material := mark.material_override as ShaderMaterial
	material.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))


static func set_mark_opacity(mark: MeshInstance3D, opacity: float) -> void:
	var material := mark.material_override as ShaderMaterial
	material.set_shader_parameter("opacity", clampf(opacity, 0.0, 1.0))
