extends Node3D
## Experiment B — the surreal corridor. Forty-four metres of the same corridor.
##
## - **Repetition.** Nineteen doors, every one numbered 2-3. Door slabs and frames are two
##   MultiMeshes, so the repetition costs two draw calls however long the corridor is.
## - **Scale that does not hold.** Each door is 85% the height of the one before it while
##   the corridor itself stays the same size, so the far doors come up to your knee: forced
##   perspective that the walls refuse to share.
## - **A door that is too large.** One doorway on the east side is taller than the wall it
##   is cut into; its frame stands above the corridor. It is also the only real way out.
## - **A window onto somewhere else.** The window in the west wall shows the collage room
##   from above, live — a SubViewport sharing the world, rendered only while you are here.
## - **A staircase to the top of the wall** and no further.
## - **An inexplicable connection.** Walk into the far door and you are at the near end
##   again, facing the same way: an Area3D moves the observer 40 m back.
##
## Local frame: the corridor runs from z 0 to z -44, x -1.3..1.3.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const LENGTH := 44.0
const HALF_WIDTH := 1.3
const WALL_HEIGHT := 3.2
const DOOR_COUNT := 10
const DOOR_SCALE_STEP := 0.85
const FIRST_DOOR_HEIGHT := 2.2
const GIANT_DOOR_Z := -28.0
const GIANT_DOOR_HALF := 1.0
const GIANT_DOOR_HEIGHT := 5.6
const LOOP_TRIGGER_Z := -42.6
## How far the loop carries you back: from the far end to the near end.
const LOOP_OFFSET := Vector3(0, 0, 40.0)
const WINDOW_Z := -14.0
const DADO_HEIGHT := 1.1

const LOWER_WALL := Color(0.36, 0.5, 0.42)
const UPPER_WALL := Color(0.84, 0.8, 0.68)
const FLOOR_A := Color(0.62, 0.52, 0.36)
const FLOOR_B := Color(0.47, 0.44, 0.38)

## Door heights along each wall, near to far. The test reads them.
var west_door_heights: PackedFloat32Array = PackedFloat32Array()
var east_door_heights: PackedFloat32Array = PackedFloat32Array()
var loop_count: int = 0
var loop_trigger: Area3D = null
var elsewhere_view: SubViewport = null
var elsewhere_camera: Camera3D = null
var door_slabs: MultiMeshInstance3D = null
var door_frames: MultiMeshInstance3D = null
var _built: bool = false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	_build_floor()
	_build_walls()
	_build_doors()
	_build_giant_door()
	_build_ceiling_beams()
	_build_staircase()
	_build_far_end()
	_build_window()


func _build_floor() -> void:
	var tool := Kit.begin_field()
	var tiles := int(LENGTH)
	for index in tiles:
		var z0 := -float(index)
		var z1 := -float(index + 1)
		var colour := FLOOR_A if index % 2 == 0 else FLOOR_B
		var colours: Array[Color] = [colour]
		Kit.field_quad(tool, Vector3(-HALF_WIDTH, 0.003, z0), Vector3(HALF_WIDTH, 0.003, z0),
			Vector3(HALF_WIDTH, 0.003, z1), Vector3(-HALF_WIDTH, 0.003, z1), colours)
	Kit.commit_field(self, "Floor", tool, Kit.field(Color.WHITE, 0.05), false)


func _build_walls() -> void:
	var tool := Kit.begin_field()
	var lower: Array[Color] = [LOWER_WALL]
	var upper: Array[Color] = [UPPER_WALL]
	var opening_near := GIANT_DOOR_Z + GIANT_DOOR_HALF
	var opening_far := GIANT_DOOR_Z - GIANT_DOOR_HALF
	# [x of the inner face, sign of the inward normal, list of z spans]
	var faces: Array = [
		[-HALF_WIDTH, 1.0, [Vector2(0.0, -LENGTH)]],
		[HALF_WIDTH, -1.0, [Vector2(0.0, opening_near), Vector2(opening_far, -LENGTH)]],
	]
	for face: Array in faces:
		var x: float = face[0]
		var inward: float = face[1]
		for span: Vector2 in face[2]:
			_wall_band(tool, x, inward, span, 0.0, DADO_HEIGHT, lower)
			_wall_band(tool, x, inward, span, DADO_HEIGHT, WALL_HEIGHT, upper)
			# The outside face, seen from the overview: one dull field.
			var outside: Array[Color] = [UPPER_WALL.darkened(0.35)]
			_wall_band(tool, x - inward * 0.2, -inward, span, 0.0, WALL_HEIGHT, outside)
	Kit.commit_field(self, "Walls", tool, Kit.field(Color.WHITE, 0.06), false)
	# Colliders: the faces above are paint, these are the wall.
	Kit.solid(self, "WestWallBody", Vector3(0.2, WALL_HEIGHT, LENGTH),
		Vector3(-HALF_WIDTH - 0.1, WALL_HEIGHT * 0.5, -LENGTH * 0.5))
	var near_length := -opening_near
	Kit.solid(self, "EastWallNearBody", Vector3(0.2, WALL_HEIGHT, near_length),
		Vector3(HALF_WIDTH + 0.1, WALL_HEIGHT * 0.5, -near_length * 0.5))
	var far_length := LENGTH + opening_far
	Kit.solid(self, "EastWallFarBody", Vector3(0.2, WALL_HEIGHT, far_length),
		Vector3(HALF_WIDTH + 0.1, WALL_HEIGHT * 0.5, opening_far - far_length * 0.5))
	# The near end is open: it is the collage room's north door.


## One horizontal band of a wall face, between heights `y0` and `y1`.
func _wall_band(
	tool: SurfaceTool, x: float, inward: float, span: Vector2, y0: float, y1: float,
	colours: Array[Color]
) -> void:
	var near := span.x
	var far := span.y
	if inward > 0.0:
		Kit.field_quad(tool, Vector3(x, y0, near), Vector3(x, y0, far), Vector3(x, y1, far),
			Vector3(x, y1, near), colours)
	else:
		Kit.field_quad(tool, Vector3(x, y0, far), Vector3(x, y0, near), Vector3(x, y1, near),
			Vector3(x, y1, far), colours)


func _build_doors() -> void:
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(1.0, 1.0, 0.05)
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(1.0, 1.0, 0.03)
	var slabs := MultiMesh.new()
	slabs.transform_format = MultiMesh.TRANSFORM_3D
	slabs.mesh = slab_mesh
	var frames := MultiMesh.new()
	frames.transform_format = MultiMesh.TRANSFORM_3D
	frames.mesh = frame_mesh
	var transforms_slab: Array[Transform3D] = []
	var transforms_frame: Array[Transform3D] = []
	var plates := Node3D.new()
	plates.name = "NumberPlates"
	add_child(plates)
	for side: int in [-1, 1]:
		for index in DOOR_COUNT:
			var z := -2.0 - float(index) * 4.0 - (2.0 if side > 0 else 0.0)
			if side > 0 and absf(z - GIANT_DOOR_Z) < GIANT_DOOR_HALF + 0.9:
				continue
			var height := FIRST_DOOR_HEIGHT * pow(DOOR_SCALE_STEP, float(index))
			var width := height * 0.42
			var x := float(side) * (HALF_WIDTH - 0.03)
			var yaw := -PI * 0.5 * float(side)
			var door_basis := Basis(Vector3.UP, yaw)
			# Scale in the door's own frame (width along the wall), then turn it to the wall.
			var frame_basis := door_basis * Basis.from_scale(Vector3(width + 0.16, height + 0.08, 1.0))
			var slab_basis := door_basis * Basis.from_scale(Vector3(width, height, 1.0))
			transforms_frame.append(Transform3D(frame_basis,
				Vector3(x + float(side) * 0.015, (height + 0.08) * 0.5, z)))
			transforms_slab.append(Transform3D(slab_basis,
				Vector3(x - float(side) * 0.01, height * 0.5, z)))
			if side < 0:
				west_door_heights.append(height)
			else:
				east_door_heights.append(height)
			var plate := Label3D.new()
			plate.name = "Plate%s%d" % ["W" if side < 0 else "E", index]
			plate.text = "2-3"
			plate.font_size = 48
			plate.pixel_size = 0.004 * height / FIRST_DOOR_HEIGHT
			plate.modulate = Color(0.1, 0.1, 0.12)
			plate.outline_size = 0
			plate.position = Vector3(x - float(side) * 0.05, height * 0.82, z)
			plate.rotation.y = yaw
			plates.add_child(plate)
	slabs.instance_count = transforms_slab.size()
	for index in transforms_slab.size():
		slabs.set_instance_transform(index, transforms_slab[index])
	frames.instance_count = transforms_frame.size()
	for index in transforms_frame.size():
		frames.set_instance_transform(index, transforms_frame[index])
	door_slabs = MultiMeshInstance3D.new()
	door_slabs.name = "DoorSlabs"
	door_slabs.multimesh = slabs
	door_slabs.material_override = Kit.flat(Color(0.4, 0.27, 0.2))
	add_child(door_slabs)
	door_frames = MultiMeshInstance3D.new()
	door_frames.name = "DoorFrames"
	door_frames.multimesh = frames
	door_frames.material_override = Kit.flat(Color(0.88, 0.85, 0.76))
	add_child(door_frames)


func _build_giant_door() -> void:
	var holder := Node3D.new()
	holder.name = "GiantDoor"
	add_child(holder)
	var frame := Kit.flat(Color(0.88, 0.85, 0.76))
	var x := HALF_WIDTH + 0.1
	Kit.box(holder, "PostNear", Vector3(0.34, GIANT_DOOR_HEIGHT, 0.3),
		Vector3(x, GIANT_DOOR_HEIGHT * 0.5, GIANT_DOOR_Z + GIANT_DOOR_HALF + 0.15), frame)
	Kit.box(holder, "PostFar", Vector3(0.34, GIANT_DOOR_HEIGHT, 0.3),
		Vector3(x, GIANT_DOOR_HEIGHT * 0.5, GIANT_DOOR_Z - GIANT_DOOR_HALF - 0.15), frame)
	Kit.box(holder, "Header", Vector3(0.34, 0.34, GIANT_DOOR_HALF * 2.0 + 0.6),
		Vector3(x, GIANT_DOOR_HEIGHT + 0.17, GIANT_DOOR_Z), frame)
	# The leaf stands open into the passage beyond, hinged on the far post.
	Kit.box(holder, "Leaf", Vector3(0.08, GIANT_DOOR_HEIGHT - 0.1, GIANT_DOOR_HALF * 2.0),
		Vector3(x + 0.95, (GIANT_DOOR_HEIGHT - 0.1) * 0.5, GIANT_DOOR_Z - GIANT_DOOR_HALF - 0.05),
		Kit.flat(Color(0.4, 0.27, 0.2)), true, -1.75)
	var plate := Label3D.new()
	plate.name = "GiantPlate"
	plate.text = "2-3"
	plate.font_size = 48
	plate.pixel_size = 0.012
	plate.modulate = Color(0.1, 0.1, 0.12)
	plate.outline_size = 0
	# On the header, which stands above the corridor's walls.
	plate.position = Vector3(HALF_WIDTH - 0.08, GIANT_DOOR_HEIGHT + 0.17, GIANT_DOOR_Z)
	plate.rotation.y = -PI * 0.5
	holder.add_child(plate)


func giant_door_height() -> float:
	return GIANT_DOOR_HEIGHT


func wall_height() -> float:
	return WALL_HEIGHT


func _build_ceiling_beams() -> void:
	var beam := BoxMesh.new()
	beam.size = Vector3(HALF_WIDTH * 2.0 + 0.4, 0.18, 0.22)
	var beams := MultiMesh.new()
	beams.transform_format = MultiMesh.TRANSFORM_3D
	beams.mesh = beam
	var count := int(LENGTH / 2.0)
	beams.instance_count = count
	for index in count:
		beams.set_instance_transform(index, Transform3D(Basis.IDENTITY,
			Vector3(0, WALL_HEIGHT + 0.09, -1.0 - float(index) * 2.0)))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CeilingBeams"
	instance.multimesh = beams
	instance.material_override = Kit.flat(Color(0.3, 0.32, 0.3))
	add_child(instance)


func _build_staircase() -> void:
	var holder := Node3D.new()
	holder.name = "StairToNowhere"
	add_child(holder)
	var tool := Kit.begin_field()
	var steps := 10
	for index in steps:
		var top := 0.28 * float(index + 1)
		var z := -18.0 - 0.3 * float(index)
		Kit.field_box(tool, Vector3(0.85, top * 0.5, z), Vector3(0.9, top, 0.3), UPPER_WALL.darkened(0.08 * float(index % 2)))
		Kit.solid(holder, "Step%d" % index, Vector3(0.9, top, 0.3), Vector3(0.85, top * 0.5, z))
	Kit.commit_field(holder, "Steps", tool, Kit.field(Color.WHITE, 0.04), false)


func _build_far_end() -> void:
	var holder := Node3D.new()
	holder.name = "FarEnd"
	add_child(holder)
	var tool := Kit.begin_field()
	var colours: Array[Color] = [UPPER_WALL]
	Kit.field_quad(tool, Vector3(-HALF_WIDTH, 0, -LENGTH), Vector3(HALF_WIDTH, 0, -LENGTH),
		Vector3(HALF_WIDTH, WALL_HEIGHT, -LENGTH), Vector3(-HALF_WIDTH, WALL_HEIGHT, -LENGTH), colours)
	Kit.commit_field(holder, "EndWall", tool, Kit.field(Color.WHITE, 0.05), false)
	Kit.solid(holder, "EndWallBody", Vector3(HALF_WIDTH * 2.0, WALL_HEIGHT, 0.2),
		Vector3(0, WALL_HEIGHT * 0.5, -LENGTH - 0.1))
	# The ordinary door at the end. It does not open; walking into it is enough.
	Kit.box(holder, "EndDoorFrame", Vector3(1.1, 2.24, 0.03), Vector3(0, 1.12, -LENGTH + 0.03),
		Kit.flat(Color(0.88, 0.85, 0.76)), false)
	Kit.box(holder, "EndDoor", Vector3(0.94, 2.14, 0.05), Vector3(0, 1.07, -LENGTH + 0.05),
		Kit.flat(Color(0.4, 0.27, 0.2)), false)
	loop_trigger = Area3D.new()
	loop_trigger.name = "LoopTrigger"
	loop_trigger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, 2.4, 1.6)
	shape.shape = box
	loop_trigger.add_child(shape)
	loop_trigger.position = Vector3(0, 1.2, LOOP_TRIGGER_Z)
	loop_trigger.body_entered.connect(_on_loop_entered)
	holder.add_child(loop_trigger)


func _on_loop_entered(body: Node3D) -> void:
	if not body.has_method("teleport_by"):
		return
	loop_count += 1
	body.call_deferred("teleport_by", LOOP_OFFSET)


func _build_window() -> void:
	elsewhere_view = SubViewport.new()
	elsewhere_view.name = "ElsewhereView"
	elsewhere_view.size = Vector2i(384, 256)
	elsewhere_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	elsewhere_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(elsewhere_view)
	elsewhere_camera = Camera3D.new()
	elsewhere_camera.name = "ElsewhereCamera"
	elsewhere_camera.fov = 58.0
	elsewhere_camera.current = true
	elsewhere_view.add_child(elsewhere_camera)
	var frame := Kit.flat(Color(0.88, 0.85, 0.76))
	var x := -HALF_WIDTH + 0.02
	Kit.box(self, "WindowFrame", Vector3(0.05, 1.3, 1.8), Vector3(x, 1.65, WINDOW_Z), frame, false)
	var material := Kit.textured_paper(elsewhere_view.get_texture(), Vector2(1.6, 1.1), 31.0, 0.0)
	material.set_shader_parameter("flatness", 0.9)
	material.set_shader_parameter("grain", 0.0)
	Kit.sheet(self, "WindowOntoElsewhere", Vector2(1.6, 1.1),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + 0.04, 1.65, WINDOW_Z)), material)


## The window's camera looks down into the collage room from above. Called by the lab
## once the zones are placed, because the shot is in world space.
func aim_window(eye: Vector3, target: Vector3) -> void:
	elsewhere_camera.global_position = eye
	elsewhere_camera.look_at(target, Vector3.FORWARD)


## Render the window live only while someone is in the corridor to see it.
func set_window_live(live: bool) -> void:
	elsewhere_view.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	)
