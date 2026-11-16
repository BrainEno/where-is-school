extends Node3D
## Experiment C — the expressionist staff room. Colour fields, a hard light, blue shadows.
##
## - **Large unnatural fields.** Viridian floor, Prussian-blue and cadmium walls, one wall
##   split on the diagonal; the colour is in the vertex colours of procedural meshes, so a
##   whole wall is one field with no texture at all.
## - **A room that leans.** The north and south walls lean inward as they rise, and the
##   passage in narrows from two metres to one: you are made smaller on the way in.
## - **Chiaroscuro.** One SpotLight3D through a barred slot high in the east wall. The ceiling
##   is a single downward-facing quad, culled from above (the overview still sees in) but
##   casting shadows from both sides, so the sun does not reach the floor.
## - **Psychological composition.** A long table: twelve chairs on one side, one on the
##   other, and the light on the one.
## - **A painted shadow that disagrees.** On the floor, the single chair's shadow is painted
##   toward the light; on the north wall, a parallelogram of painted sunlight falls from a
##   window that does not exist.
##
## Local frame: room x -6..6, z -7..7; the passage runs from x -12.6 (corridor) to x -6.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const HALF_X := 6.0
const HALF_Z := 7.0
const HEIGHT := 3.6
const LEAN := 0.9
const DOOR_HALF := 0.6
const DOOR_HEIGHT := 2.3
const SLOT_BOTTOM := 2.35
const SLOT_TOP := 3.05
const PASSAGE_START := -12.6

const VIRIDIAN := Color(0.12, 0.33, 0.28)
const OCHRE := Color(0.78, 0.6, 0.18)
const PRUSSIAN := Color(0.1, 0.16, 0.36)
const CADMIUM := Color(0.85, 0.38, 0.1)
const MADDER := Color(0.42, 0.17, 0.29)
const LEMON := Color(0.82, 0.74, 0.34)
const NEAR_BLACK := Color(0.035, 0.035, 0.06)
const PAINTED_LIGHT := Color(0.93, 0.83, 0.48)

var spot: SpotLight3D = null
var ceiling: MeshInstance3D = null
var fields: Array[MeshInstance3D] = []
var _built: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	_build_passage()
	_build_floor()
	_build_leaning_walls()
	_build_east_wall()
	_build_west_wall()
	_build_ceiling()
	_build_table()
	_paint_lies()
	_light()


func _field(node_name: String, tool: SurfaceTool, collide: bool, streaks: float = 0.1) -> void:
	fields.append(Kit.commit_field(self, node_name, tool, Kit.field(Color.WHITE, streaks), collide))


func _build_passage() -> void:
	var tool := Kit.begin_field()
	var start_half := 1.0
	var end_half := DOOR_HALF
	var floor_colours: Array[Color] = [VIRIDIAN.darkened(0.3)]
	Kit.field_quad(tool, Vector3(PASSAGE_START, 0.003, start_half), Vector3(-HALF_X, 0.003, end_half),
		Vector3(-HALF_X, 0.003, -end_half), Vector3(PASSAGE_START, 0.003, -start_half), floor_colours)
	var wall: Array[Color] = [MADDER, MADDER, NEAR_BLACK, NEAR_BLACK]
	# North side (z < 0) faces +Z, south side faces -Z; both converge toward the room.
	Kit.field_quad(tool, Vector3(PASSAGE_START, 0, -start_half), Vector3(-HALF_X, 0, -end_half),
		Vector3(-HALF_X, DOOR_HEIGHT, -end_half), Vector3(PASSAGE_START, 3.0, -start_half), wall)
	Kit.field_quad(tool, Vector3(-HALF_X, 0, end_half), Vector3(PASSAGE_START, 0, start_half),
		Vector3(PASSAGE_START, 3.0, start_half), Vector3(-HALF_X, DOOR_HEIGHT, end_half), wall)
	_field("Passage", tool, true)


func _build_floor() -> void:
	var tool := Kit.begin_field()
	var green: Array[Color] = [VIRIDIAN]
	var ochre: Array[Color] = [OCHRE]
	# One diagonal field of ochre across the green, corner to corner of the light's path.
	var a := Vector3(-HALF_X, 0.002, HALF_Z)
	var b := Vector3(HALF_X, 0.002, HALF_Z)
	var c := Vector3(HALF_X, 0.002, -HALF_Z)
	var d := Vector3(-HALF_X, 0.002, -HALF_Z)
	var mid_south := Vector3(-1.0, 0.002, HALF_Z)
	var mid_north := Vector3(3.5, 0.002, -HALF_Z)
	Kit.field_quad(tool, a, mid_south, mid_north, d, green)
	Kit.field_quad(tool, mid_south, b, c, mid_north, ochre)
	_field("Floor", tool, false, 0.12)


## North and south walls lean inward by LEAN metres at the top.
func _build_leaning_walls() -> void:
	var tool := Kit.begin_field()
	var north: Array[Color] = [PRUSSIAN, PRUSSIAN, PRUSSIAN.darkened(0.45), PRUSSIAN.darkened(0.45)]
	Kit.field_quad(tool, Vector3(-HALF_X, 0, -HALF_Z), Vector3(HALF_X, 0, -HALF_Z),
		Vector3(HALF_X, HEIGHT, -HALF_Z + LEAN), Vector3(-HALF_X, HEIGHT, -HALF_Z + LEAN), north)
	var south: Array[Color] = [LEMON, LEMON, LEMON.darkened(0.3), LEMON.darkened(0.3)]
	Kit.field_quad(tool, Vector3(HALF_X, 0, HALF_Z), Vector3(-HALF_X, 0, HALF_Z),
		Vector3(-HALF_X, HEIGHT, HALF_Z - LEAN), Vector3(HALF_X, HEIGHT, HALF_Z - LEAN), south)
	_field("LeaningWalls", tool, true)


## One rectangle of a wall that lies in the plane x = `x`, facing +X (`facing` > 0) or -X.
func _wall_x(
	tool: SurfaceTool, x: float, facing: float, z_min: float, z_max: float, y0: float,
	y1: float, colours: Array[Color]
) -> void:
	if facing > 0.0:
		Kit.field_quad(tool, Vector3(x, y0, z_max), Vector3(x, y0, z_min), Vector3(x, y1, z_min),
			Vector3(x, y1, z_max), colours)
	else:
		Kit.field_quad(tool, Vector3(x, y0, z_min), Vector3(x, y0, z_max), Vector3(x, y1, z_max),
			Vector3(x, y1, z_min), colours)


## Cadmium, split on the diagonal with near-black, with the barred slot the light comes
## through and the door on to the medium-switch classroom.
func _build_east_wall() -> void:
	var holder := Node3D.new()
	holder.name = "EastWall"
	add_child(holder)
	var tool := Kit.begin_field()
	var x := HALF_X
	var orange: Array[Color] = [CADMIUM]
	var black: Array[Color] = [NEAR_BLACK]
	var lintel: Array[Color] = [CADMIUM.darkened(0.2)]
	# Below the slot, either side of the door.
	_wall_x(tool, x, -1.0, -HALF_Z, -DOOR_HALF, 0.0, SLOT_BOTTOM, orange)
	_wall_x(tool, x, -1.0, DOOR_HALF, HALF_Z, 0.0, SLOT_BOTTOM, orange)
	_wall_x(tool, x, -1.0, -DOOR_HALF, DOOR_HALF, DOOR_HEIGHT, SLOT_BOTTOM, lintel)
	_wall_x(tool, x, -1.0, -HALF_Z + LEAN, HALF_Z - LEAN, SLOT_TOP, HEIGHT, black)
	# The diagonal: a black triangle over the north half, painted a hair in front of it.
	var front := x - 0.004
	var triangle: Array[Color] = [NEAR_BLACK]
	Kit.field_quad(tool, Vector3(front, 0, -HALF_Z), Vector3(front, 0, -DOOR_HALF),
		Vector3(front, SLOT_BOTTOM, -HALF_Z), Vector3(front, SLOT_BOTTOM, -HALF_Z), triangle)
	Kit.commit_field(holder, "Fields", tool, Kit.field(Color.WHITE, 0.1), false)
	# The physical wall: boxes around the door and the slot, and the bars in the slot.
	var depth := 0.2
	var side_length := HALF_Z - DOOR_HALF
	Kit.solid(holder, "LowerNorth", Vector3(depth, SLOT_BOTTOM, side_length),
		Vector3(x + depth * 0.5, SLOT_BOTTOM * 0.5, -DOOR_HALF - side_length * 0.5))
	Kit.solid(holder, "LowerSouth", Vector3(depth, SLOT_BOTTOM, side_length),
		Vector3(x + depth * 0.5, SLOT_BOTTOM * 0.5, DOOR_HALF + side_length * 0.5))
	Kit.solid(holder, "Lintel", Vector3(depth, SLOT_BOTTOM - DOOR_HEIGHT, DOOR_HALF * 2.0),
		Vector3(x + depth * 0.5, (DOOR_HEIGHT + SLOT_BOTTOM) * 0.5, 0))
	Kit.box(holder, "Upper", Vector3(depth, HEIGHT - SLOT_TOP, HALF_Z * 2.0),
		Vector3(x + depth * 0.5 + 0.01, (SLOT_TOP + HEIGHT) * 0.5, 0), Kit.flat(NEAR_BLACK))
	var bar_material := Kit.flat(NEAR_BLACK)
	for index in 13:
		var z := -HALF_Z + LEAN + 0.4 + float(index) * (HALF_Z * 2.0 - LEAN * 2.0 - 0.8) / 12.0
		Kit.box(holder, "Bar%d" % index, Vector3(0.08, SLOT_TOP - SLOT_BOTTOM, 0.08),
			Vector3(x + 0.1, (SLOT_BOTTOM + SLOT_TOP) * 0.5, z), bar_material, false)
	# Below the slot, a sill the light skims.
	Kit.box(holder, "Sill", Vector3(depth + 0.1, 0.06, HALF_Z * 2.0 - LEAN * 2.0),
		Vector3(x + depth * 0.5, SLOT_BOTTOM - 0.03, 0), Kit.flat(CADMIUM.darkened(0.3)), false)


func _build_west_wall() -> void:
	var tool := Kit.begin_field()
	var x := -HALF_X
	var violet: Array[Color] = [MADDER, MADDER, MADDER.darkened(0.5), MADDER.darkened(0.5)]
	_wall_x(tool, x, 1.0, -HALF_Z, -DOOR_HALF, 0.0, HEIGHT, violet)
	_wall_x(tool, x, 1.0, DOOR_HALF, HALF_Z, 0.0, HEIGHT, violet)
	_wall_x(tool, x, 1.0, -DOOR_HALF, DOOR_HALF, DOOR_HEIGHT, HEIGHT, violet)
	_field("WestWall", tool, false)
	var side_length := HALF_Z - DOOR_HALF
	Kit.solid(self, "WestNorthBody", Vector3(0.2, HEIGHT, side_length),
		Vector3(x - 0.1, HEIGHT * 0.5, -DOOR_HALF - side_length * 0.5))
	Kit.solid(self, "WestSouthBody", Vector3(0.2, HEIGHT, side_length),
		Vector3(x - 0.1, HEIGHT * 0.5, DOOR_HALF + side_length * 0.5))


func _build_ceiling() -> void:
	var tool := Kit.begin_field()
	var dark: Array[Color] = [NEAR_BLACK]
	# Facing down: a, b, c, d counter-clockwise as seen from below.
	Kit.field_quad(tool, Vector3(-HALF_X, HEIGHT, -HALF_Z + LEAN), Vector3(HALF_X, HEIGHT, -HALF_Z + LEAN),
		Vector3(HALF_X, HEIGHT, HALF_Z - LEAN), Vector3(-HALF_X, HEIGHT, HALF_Z - LEAN), dark)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 1.0
	ceiling = MeshInstance3D.new()
	ceiling.name = "Ceiling"
	ceiling.mesh = tool.commit()
	ceiling.material_override = material
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(ceiling)


func _build_table() -> void:
	var holder := Node3D.new()
	holder.name = "Table"
	add_child(holder)
	var tool := Kit.begin_field()
	var wood := Color(0.22, 0.1, 0.06)
	Kit.field_box(tool, Vector3(0, 0.76, -1.5), Vector3(6.4, 0.07, 1.1), wood)
	for leg: Vector3 in [Vector3(-3.0, 0.37, -1.95), Vector3(3.0, 0.37, -1.95), Vector3(-3.0, 0.37, -1.05), Vector3(3.0, 0.37, -1.05)]:
		Kit.field_box(tool, leg, Vector3(0.07, 0.74, 0.07), wood)
	Kit.commit_field(holder, "Top", tool, Kit.field(Color.WHITE, 0.05), false)
	Kit.solid(holder, "TableBody", Vector3(6.4, 0.8, 1.1), Vector3(0, 0.4, -1.5))
	var chair := _chair_mesh(Color(0.9, 0.86, 0.78))
	for index in 12:
		var x := -2.75 + float(index) * 0.5
		_place_chair(holder, "Chair%02d" % index, chair, Vector3(x, 0, -2.45), 0.0)
	_place_chair(holder, "TheChair", _chair_mesh(Color(0.95, 0.93, 0.88)), Vector3(0.4, 0, -0.35), PI)


func _place_chair(parent: Node, node_name: String, mesh: Mesh, at: Vector3, yaw: float) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = Kit.field(Color.WHITE, 0.02)
	instance.position = at
	instance.rotation.y = yaw
	parent.add_child(instance)


func _chair_mesh(colour: Color) -> ArrayMesh:
	var tool := Kit.begin_field()
	Kit.field_box(tool, Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42), colour)
	Kit.field_box(tool, Vector3(0, 0.75, -0.2), Vector3(0.42, 0.56, 0.03), colour)
	for leg: Vector3 in [Vector3(-0.19, 0.22, -0.19), Vector3(0.19, 0.22, -0.19), Vector3(-0.19, 0.22, 0.19), Vector3(0.19, 0.22, 0.19)]:
		Kit.field_box(tool, leg, Vector3(0.03, 0.44, 0.03), colour.darkened(0.5))
	return tool.commit()


## The two painted lies: a shadow toward the light, and light from no window.
func _paint_lies() -> void:
	var tool := Kit.begin_field()
	var shadow: Array[Color] = [NEAR_BLACK]
	# From the single chair's feet toward the slot (east), widening as a shadow would away
	# from a light — but on the wrong side.
	Kit.field_quad(tool, Vector3(0.6, 0.006, -0.6), Vector3(0.6, 0.006, -0.15),
		Vector3(4.6, 0.006, 0.5), Vector3(4.4, 0.006, -1.1), shadow)
	var light: Array[Color] = [PAINTED_LIGHT]
	var z := -HALF_Z + 0.03
	var lean_at := func(y: float) -> float: return z + LEAN * y / HEIGHT
	Kit.field_quad(tool, Vector3(-4.2, 0.5, lean_at.call(0.5)), Vector3(-2.2, 0.5, lean_at.call(0.5)),
		Vector3(-1.4, 2.4, lean_at.call(2.4)), Vector3(-3.4, 2.4, lean_at.call(2.4)), light)
	_field("PaintedLies", tool, false, 0.15)
	var bars: Array[Color] = [PRUSSIAN]
	var bar_tool := Kit.begin_field()
	for index in 2:
		var t := 0.33 + float(index) * 0.33
		var bottom := Vector3(-4.2, 0.5, 0).lerp(Vector3(-2.2, 0.5, 0), t)
		var top := Vector3(-3.4, 2.4, 0).lerp(Vector3(-1.4, 2.4, 0), t)
		Kit.field_quad(bar_tool, Vector3(bottom.x - 0.06, 0.5, lean_at.call(0.5) + 0.004),
			Vector3(bottom.x + 0.06, 0.5, lean_at.call(0.5) + 0.004),
			Vector3(top.x + 0.06, 2.4, lean_at.call(2.4) + 0.004),
			Vector3(top.x - 0.06, 2.4, lean_at.call(2.4) + 0.004), bars)
	_field("PaintedWindowBars", bar_tool, false, 0.0)


func _light() -> void:
	spot = SpotLight3D.new()
	spot.name = "SlotLight"
	spot.light_color = Color(1.0, 0.93, 0.78)
	spot.light_energy = 9.0
	spot.spot_range = 22.0
	spot.spot_angle = 32.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = true
	spot.shadow_bias = 0.04
	add_child(spot)
	# Low enough that the beam passes through the slot (y 2.35..3.05 at the wall).
	spot.position = Vector3(HALF_X + 5.0, 4.8, -0.2)
	# look_at() takes a world-space target; the room may be anywhere in the lab.
	spot.look_at(to_global(Vector3(0.4, 0.0, -0.8)), Vector3.UP)
