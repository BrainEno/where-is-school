extends Node3D
## Experiment D — the medium switch. A plain 3D classroom, a doorway, and a stage beyond it.
##
## The classroom is the most conventional 3D in the lab: the game's own desk and chair
## models, a plaster wall, a lit floor. On its south wall hangs a "painting" that is a live
## view of the stage next door (a second SubViewport, banded like a cheap print).
##
## Through the east doorway is a stage built of theatre flats: a back flat painted with a
## corridor in one-point perspective, four wings painted with vanishing points that do not
## agree with it or with each other, plywood backs and braces you can walk round to see,
## Q (the game's model) standing in front of the painting under a real spotlight,
## and a paper chair with a real collider. Every flat, wing and brace is solid: the stage is
## paint to the eye and furniture to the body.
##
## Crossing the threshold (the `PaintedSide` Area3D) is the switch itself: the lab's
## MediumSwitch stops drawing 3D to the screen and paints the camera's view instead. This
## node only reports the crossing; see `medium_switch.gd`.
##
## Local frame: classroom x -5..5, z -6..6; stage x 5..19, z -7..7; passage from the staff
## room at x -10.8.

signal threshold_changed(on_painted_side: bool)

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const ROOM_HALF_X := 5.0
const ROOM_HALF_Z := 6.0
const ROOM_HEIGHT := 3.4
const WEST_DOOR_HALF := 0.6
const EAST_DOOR_HALF := 1.0
const DOOR_HEIGHT := 2.5
const PASSAGE_START := -10.8
const STAGE_END := 19.0
const STAGE_HALF_Z := 7.0
const BACK_FLAT_X := 18.4
const BACK_FLAT_SIZE := Vector2(12.0, 6.0)

const REAL_DESK := "res://assets/models/classroom/classroom_student_desk.glb"
const REAL_CHAIR := "res://assets/models/classroom/classroom_student_chair.glb"
## You walk in as the protagonist, so the figure on the stage is someone else: Q.
const STAGE_ACTOR := "res://scenes/environment/characters/q.tscn"
const PLASTER := "res://assets/materials/laboratory/textures/wall_plaster.png"
const CONCRETE := "res://assets/materials/laboratory/textures/floor_concrete.png"
const BOARD := "res://assets/materials/classroom/textures/board_front.png"

const PLYWOOD := Color(0.62, 0.48, 0.32)
const VELVET := Color(0.05, 0.04, 0.05)

var painted_side: Area3D = null
var stage_window: SubViewport = null
var stage_window_camera: Camera3D = null
var flats: Array[Node3D] = []
var actor: Node3D = null
var stage_spot: SpotLight3D = null
var _built: bool = false
var _inside: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	_build_passage()
	_build_classroom()
	_build_stage_floor()
	_build_curtains()
	_build_flats()
	_place_actor()
	_build_stage_window()
	_build_trigger()


func is_on_painted_side() -> bool:
	return _inside


# --- The ordinary room ------------------------------------------------------------------


func _build_passage() -> void:
	var material := Kit.flat(Color(0.32, 0.3, 0.28))
	var length := -ROOM_HALF_X - PASSAGE_START
	var centre_x := PASSAGE_START + length * 0.5
	Kit.box(self, "PassageNorth", Vector3(length, 2.8, 0.2), Vector3(centre_x, 1.4, -WEST_DOOR_HALF - 0.1), material)
	Kit.box(self, "PassageSouth", Vector3(length, 2.8, 0.2), Vector3(centre_x, 1.4, WEST_DOOR_HALF + 0.1), material)
	Kit.box(self, "PassageFloor", Vector3(length, 0.02, WEST_DOOR_HALF * 2.0), Vector3(centre_x, 0.0, 0),
		Kit.flat(Color(0.2, 0.19, 0.18)), false)


func _plaster() -> StandardMaterial3D:
	var material := Kit.flat(Color(0.86, 0.84, 0.78))
	var texture := load(PLASTER) as Texture2D
	if texture != null:
		material.albedo_texture = texture
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return material


func _build_classroom() -> void:
	var holder := Node3D.new()
	holder.name = "Classroom"
	add_child(holder)
	var wall := _plaster()
	var h := ROOM_HEIGHT
	var t := 0.2
	var x := ROOM_HALF_X
	var z := ROOM_HALF_Z
	Kit.box(holder, "NorthWall", Vector3(x * 2.0, h, t), Vector3(0, h * 0.5, -z), wall)
	Kit.box(holder, "SouthWall", Vector3(x * 2.0, h, t), Vector3(0, h * 0.5, z), wall)
	for side: Array in [[-x, WEST_DOOR_HALF, "West"], [x, EAST_DOOR_HALF, "East"]]:
		var wall_x: float = side[0]
		var door_half: float = side[1]
		var label: String = side[2]
		var length := z - door_half
		Kit.box(holder, label + "WallNorth", Vector3(t, h, length),
			Vector3(wall_x, h * 0.5, -door_half - length * 0.5), wall)
		Kit.box(holder, label + "WallSouth", Vector3(t, h, length),
			Vector3(wall_x, h * 0.5, door_half + length * 0.5), wall)
		Kit.box(holder, label + "Lintel", Vector3(t, h - DOOR_HEIGHT, door_half * 2.0),
			Vector3(wall_x, DOOR_HEIGHT + (h - DOOR_HEIGHT) * 0.5, 0), wall)
	var floor_material := Kit.flat(Color(0.62, 0.6, 0.56))
	var concrete := load(CONCRETE) as Texture2D
	if concrete != null:
		floor_material.albedo_texture = concrete
		floor_material.uv1_triplanar = true
		floor_material.uv1_scale = Vector3(0.25, 0.25, 0.25)
	Kit.box(holder, "Floor", Vector3(x * 2.0, 0.02, z * 2.0), Vector3(0, 0.0, 0), floor_material, false)
	var board := Kit.flat(Color(1, 1, 1))
	var board_texture := load(BOARD) as Texture2D
	if board_texture != null:
		board.albedo_texture = board_texture
	Kit.box(holder, "Blackboard", Vector3(4.4, 1.2, 0.04), Vector3(0, 1.65, -z + 0.13), board, false)
	for row in 3:
		for column in 2:
			var spot := Vector3(-2.6 + float(column) * 2.6, 0, -2.6 + float(row) * 2.0)
			_real_model(holder, REAL_DESK, "Desk%d%d" % [row, column], spot)
			_real_model(holder, REAL_CHAIR, "Chair%d%d" % [row, column], spot + Vector3(0, 0, 0.62))
			Kit.solid(holder, "DeskBody%d%d" % [row, column], Vector3(1.0, 0.8, 0.6), spot + Vector3(0, 0.4, 0))


func _real_model(parent: Node, path: String, node_name: String, at: Vector3) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Visual lab: %s is missing." % path)
		return
	var model := packed.instantiate() as Node3D
	model.name = node_name
	model.position = at
	parent.add_child(model)


# --- The stage --------------------------------------------------------------------------


func _build_stage_floor() -> void:
	var tool := Kit.begin_field()
	var start := ROOM_HALF_X + 0.1
	for plank in 14:
		var z0 := -STAGE_HALF_Z + float(plank)
		var colour := Color(0.17, 0.13, 0.11) if plank % 2 == 0 else Color(0.2, 0.15, 0.12)
		var colours: Array[Color] = [colour]
		Kit.field_quad(tool, Vector3(start, 0.004, z0 + 1.0), Vector3(STAGE_END, 0.004, z0 + 1.0),
			Vector3(STAGE_END, 0.004, z0), Vector3(start, 0.004, z0), colours)
	Kit.commit_field(self, "StageBoards", tool, Kit.field(Color.WHITE, 0.15), false)
	# A floor-cloth painted with tiles in the back flat's perspective, lying where the
	# real floor would have to be for the painting to be true.
	var cloth := Kit.paper(Kit.PERSPECTIVE, Color(0.72, 0.56, 0.32), Color(0.3, 0.22, 0.16),
		Vector2(9.0, 8.0), 17.0)
	cloth.set_shader_parameter("vanishing_point", Vector2(0.5, -0.9))
	cloth.set_shader_parameter("tear_depth", 0.0)
	cloth.set_shader_parameter("flatness", 0.25)
	Kit.sheet(self, "FloorCloth", Vector2(9.0, 8.0),
		Transform3D(Kit.floor_basis(-PI * 0.5), Vector3(13.5, 0.008, 0)), cloth)


func _build_curtains() -> void:
	var tool := Kit.begin_field()
	var start := ROOM_HALF_X + 0.1
	var folds := 18
	for side: float in [-1.0, 1.0]:
		var z := side * STAGE_HALF_Z
		for fold in folds:
			var x0 := start + (STAGE_END - start) * float(fold) / float(folds)
			var x1 := start + (STAGE_END - start) * float(fold + 1) / float(folds)
			var shade := VELVET.lightened(0.06 if fold % 2 == 0 else 0.0)
			var colours: Array[Color] = [shade]
			if side < 0.0:
				Kit.field_quad(tool, Vector3(x0, 0, z), Vector3(x1, 0, z), Vector3(x1, 6.0, z), Vector3(x0, 6.0, z), colours)
			else:
				Kit.field_quad(tool, Vector3(x1, 0, z), Vector3(x0, 0, z), Vector3(x0, 6.0, z), Vector3(x1, 6.0, z), colours)
	Kit.commit_field(self, "Curtains", tool, Kit.field(Color.WHITE, 0.02), false)
	var length := STAGE_END - start
	Kit.solid(self, "CurtainNorthBody", Vector3(length, 6.0, 0.2), Vector3(start + length * 0.5, 3.0, -STAGE_HALF_Z - 0.1))
	Kit.solid(self, "CurtainSouthBody", Vector3(length, 6.0, 0.2), Vector3(start + length * 0.5, 3.0, STAGE_HALF_Z + 0.1))


## A theatre flat: a thin plywood board, its painted face, and two braces behind it.
## `position_at` is the centre of the bottom edge; the face looks along the flat's local +Z.
func _flat(
	node_name: String, size: Vector2, position_at: Vector3, yaw: float, material: Material
) -> Node3D:
	var flat_root := Node3D.new()
	flat_root.name = node_name
	flat_root.position = position_at
	flat_root.rotation.y = yaw
	add_child(flat_root)
	var depth := 0.08
	Kit.box(flat_root, "Board", Vector3(size.x, size.y, depth),
		Vector3(0, size.y * 0.5, -depth * 0.5 - 0.005), Kit.flat(PLYWOOD))
	var face := Kit.sheet(flat_root, "PaintedFace", size,
		Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0.0)), material)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var brace_material := Kit.flat(PLYWOOD.darkened(0.25))
	for side: float in [-0.3, 0.3]:
		var brace_length := size.y * 0.8
		var brace := Kit.box(flat_root, "Brace%s" % ("L" if side < 0.0 else "R"),
			Vector3(0.06, brace_length, 0.1),
			Vector3(side * size.x, brace_length * 0.42, -0.9), brace_material, false)
		brace.rotation.x = -0.55
		Kit.box(flat_root, "Weight%s" % ("L" if side < 0.0 else "R"), Vector3(0.3, 0.16, 0.4),
			Vector3(side * size.x, 0.08, -1.6), Kit.flat(Color(0.12, 0.12, 0.13)), false)
	flats.append(flat_root)
	return flat_root


func _build_flats() -> void:
	var back := Kit.backdrop(Vector2(0.5, 0.48), BACK_FLAT_SIZE.x / BACK_FLAT_SIZE.y, 1.0)
	# The back flat faces -X, toward the doorway.
	_flat("BackFlat", BACK_FLAT_SIZE, Vector3(BACK_FLAT_X, 0, 0), -PI * 0.5, back)
	# The wings disagree: each paints its own vanishing point.
	var wings: Array = [
		["WingNorthNear", Vector3(9.0, 0, -5.4), -PI * 0.5 + 0.55, Vector2(0.9, 0.42)],
		["WingSouthNear", Vector3(9.0, 0, 5.4), -PI * 0.5 - 0.55, Vector2(0.1, 0.56)],
		["WingNorthFar", Vector3(13.5, 0, -4.8), -PI * 0.5 + 0.35, Vector2(1.2, 0.3)],
		["WingSouthFar", Vector3(13.5, 0, 4.8), -PI * 0.5 - 0.35, Vector2(-0.2, 0.62)],
	]
	for index in wings.size():
		var entry: Array = wings[index]
		var material := Kit.backdrop(entry[3], 2.4 / 4.6, 3.0 + float(index))
		material.set_shader_parameter("far_half", Vector2(0.12, 0.08))
		_flat(String(entry[0]), Vector2(2.4, 4.6), entry[1], float(entry[2]), material)


func _place_actor() -> void:
	var packed := load(STAGE_ACTOR) as PackedScene
	if packed != null:
		actor = packed.instantiate() as Node3D
		actor.name = "Actor"
		actor.position = Vector3(16.6, 0, 0.9)
		# The model looks down +Z; turn it to face the doorway (-X).
		actor.rotation.y = -PI * 0.5
		add_child(actor)
		Kit.solid(self, "ActorBody", Vector3(0.5, 1.7, 0.5), Vector3(16.6, 0.85, 0.9))
	else:
		push_warning("Visual lab: the stage actor scene is missing; the stage is empty.")
	# A paper chair with a real collider, set on the floor-cloth like a prop.
	var chair := Sprite3D.new()
	chair.name = "PaperChair"
	chair.texture = Kit.chair_texture(77, Color(0.75, 0.22, 0.16))
	chair.pixel_size = 0.95 / float(chair.texture.get_height())
	chair.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	chair.double_sided = true
	chair.position = Vector3(14.6, 0.475, -1.4)
	chair.rotation.y = -PI * 0.5 + 0.3
	add_child(chair)
	Kit.solid(self, "PaperChairBody", Vector3(0.06, 0.9, 0.7), Vector3(14.6, 0.45, -1.4), -PI * 0.5 + 0.3)
	stage_spot = SpotLight3D.new()
	stage_spot.name = "FollowSpot"
	stage_spot.light_color = Color(1.0, 0.92, 0.76)
	stage_spot.light_energy = 7.0
	stage_spot.spot_range = 24.0
	stage_spot.spot_angle = 24.0
	stage_spot.shadow_enabled = true
	add_child(stage_spot)
	# Both points are in the zone's frame; look_at_from_position() wants world space.
	stage_spot.look_at_from_position(
		to_global(Vector3(8.0, 5.6, 3.2)), to_global(Vector3(17.0, 1.2, 0.4)), Vector3.UP
	)


## A picture on the classroom's south wall that is a live view of the stage.
func _build_stage_window() -> void:
	stage_window = SubViewport.new()
	stage_window.name = "StageWindow"
	stage_window.size = Vector2i(320, 200)
	stage_window.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(stage_window)
	stage_window_camera = Camera3D.new()
	stage_window_camera.name = "StageWindowCamera"
	stage_window_camera.fov = 50.0
	stage_window_camera.current = true
	stage_window.add_child(stage_window_camera)
	var material := Kit.textured_paper(stage_window.get_texture(), Vector2(1.6, 1.0), 9.0, 0.0)
	material.set_shader_parameter("posterize_levels", 5.0)
	material.set_shader_parameter("flatness", 0.8)
	Kit.box(self, "PictureFrame", Vector3(1.84, 1.24, 0.05), Vector3(-1.0, 1.75, ROOM_HALF_Z - 0.13),
		Kit.flat(Color(0.3, 0.22, 0.14)), false)
	Kit.sheet(self, "PictureOfTheStage", Vector2(1.6, 1.0),
		Transform3D(Basis(Vector3.UP, PI), Vector3(-1.0, 1.75, ROOM_HALF_Z - 0.16)), material)


## Called by the lab once the zone is placed (the shot is in world space).
func aim_stage_window() -> void:
	stage_window_camera.global_position = to_global(Vector3(9.5, 1.7, 3.6))
	stage_window_camera.look_at(to_global(Vector3(17.0, 1.4, -0.5)), Vector3.UP)


func set_stage_window_live(live: bool) -> void:
	stage_window.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	)


func _build_trigger() -> void:
	painted_side = Area3D.new()
	painted_side.name = "PaintedSide"
	painted_side.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var start := ROOM_HALF_X + 0.3
	box.size = Vector3(STAGE_END - start, 3.0, STAGE_HALF_Z * 2.0)
	shape.shape = box
	painted_side.add_child(shape)
	painted_side.position = Vector3(start + (STAGE_END - start) * 0.5, 1.5, 0)
	painted_side.body_entered.connect(_on_body_entered)
	painted_side.body_exited.connect(_on_body_exited)
	add_child(painted_side)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("teleport_by") or _inside:
		return
	_inside = true
	threshold_changed.emit(true)


func _on_body_exited(body: Node3D) -> void:
	if not body.has_method("teleport_by") or not _inside:
		return
	_inside = false
	threshold_changed.emit(false)
