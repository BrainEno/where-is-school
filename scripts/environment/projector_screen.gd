class_name ProjectorScreen
extends Node3D
## The biology classroom's pull-down projection screen (issue #159): a roller case
## hung on the front wall above the blackboard, and a cream, matte screen that unrolls
## straight down over about half of the board to just above the floor.
##
## Built from primitives in the room's own materials, so the scene file is the editable
## source. The rolling is driven by one number (`set_unroll_amount`, 0 = rolled up in the
## case, 1 = all the way down), the same pattern as `WindowCurtain`: a state loaded
## directly is the exact pose the animation ends in.
##
## Nothing is projected on it. There is no story content for a projection yet, and the
## brief asks for none to be invented: the screen is a surface and a moving part only.
##
## Local space: x runs along the wall, y is up, +z faces the room. The origin is the
## axis of the roller; the screen leaves the case through the slot under it.
##
## Nothing here collides: the screen hangs in front of the board, outside the walkable
## floor, and `classroom_visual_slice_test.gd` keeps the room's solids a closed list.

## Emitted when an animated roll has finished, with the new state.
signal rolled(is_unrolled: bool)

## The case's slot, below the roller axis.
const SLOT_Y := -0.065
## The screen hangs this far in front of the roller axis (toward the room).
const SCREEN_Z := 0.02
const CASE_SIZE := Vector3(0.13, 0.13, 0.13)
const BAR_SIZE := Vector3(0.03, 0.03, 0.03)

## Width of the screen surface, metres.
@export var screen_width: float = 2.3
## From the slot to the bottom bar when fully unrolled, metres.
@export var drop: float = 2.25
## Loaded unrolled or rolled up.
@export var start_unrolled: bool = false
## Seconds an animated roll takes.
@export var roll_seconds: float = 1.6
@export var screen_material: Material
@export var case_material: Material

var _amount := 0.0
var _cloth_pivot: Node3D = null
var _cloth: MeshInstance3D = null
var _bar: Node3D = null
var _tween: Tween = null
var _built := false


func _ready() -> void:
	_build()
	set_unroll_amount(1.0 if start_unrolled else 0.0)


func get_unroll_amount() -> float:
	return _amount


## True once the screen is all the way down.
func is_unrolled() -> bool:
	return _amount >= 0.999


## True while the screen is all the way up in its case.
func is_rolled_up() -> bool:
	return _amount <= 0.001


## Puts the screen and its bottom bar where `amount` says (0 up, 1 down).
func set_unroll_amount(amount: float) -> void:
	_build()
	_amount = clampf(amount, 0.0, 1.0)
	var length := drop * _amount
	if _cloth_pivot != null:
		_cloth_pivot.scale = Vector3(1.0, maxf(length, 0.001), 1.0)
		_cloth_pivot.visible = length > 0.005
	if _bar != null:
		_bar.position = Vector3(0.0, SLOT_Y - length - BAR_SIZE.y * 0.5, SCREEN_Z)


## Unrolls the screen. Animated by default; awaiting it waits for the end.
func unroll(animated: bool = true) -> void:
	await _roll_to(1.0, animated)


## Rolls the screen back up into its case.
func roll_up(animated: bool = true) -> void:
	await _roll_to(0.0, animated)


## Down if it is up (or part way), up if it is down.
func toggle(animated: bool = true) -> void:
	await _roll_to(0.0 if is_unrolled() else 1.0, animated)


## The meshes a player sees as "the screen": the surface, the case and the bar - what
## an interactable outlines.
func get_screen_meshes() -> Array[MeshInstance3D]:
	_build()
	var meshes: Array[MeshInstance3D] = []
	for node in find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	return meshes


## World-space rectangle of the screen surface when fully unrolled (for aiming checks):
## [centre, half extents along the wall and up, the surface normal].
func get_surface_frame() -> Dictionary:
	var centre := to_global(Vector3(0.0, SLOT_Y - drop * 0.5, SCREEN_Z))
	return {
		"centre": centre,
		"right": global_basis.x.normalized() * screen_width * 0.5,
		"up": global_basis.y.normalized() * drop * 0.5,
		"normal": global_basis.z.normalized(),
	}


func _roll_to(target: float, animated: bool) -> void:
	_build()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_equal_approx(_amount, target):
		return
	if not animated or not is_inside_tree():
		set_unroll_amount(target)
		rolled.emit(is_unrolled())
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var seconds := roll_seconds * absf(target - _amount)
	_tween.tween_method(set_unroll_amount, _amount, target, maxf(seconds, 0.05))
	await _tween.finished
	rolled.emit(is_unrolled())


func _build() -> void:
	if _built:
		return
	_built = true
	var case_length := screen_width + 0.16
	var case_size := Vector3(case_length, CASE_SIZE.y, CASE_SIZE.z)
	_add_box(self, &"Case", case_size, Vector3.ZERO, case_material)
	for side in [-1.0, 1.0]:
		var cap_name := &"EndCapLeft" if side < 0.0 else &"EndCapRight"
		_add_box(
			self, cap_name, Vector3(0.03, 0.16, 0.16),
			Vector3(side * (case_length * 0.5 + 0.015), 0.0, 0.0), case_material
		)
		# A wall bracket behind each end cap, back to the wall.
		var bracket_name := &"BracketLeft" if side < 0.0 else &"BracketRight"
		_add_box(
			self, bracket_name, Vector3(0.04, 0.04, 0.2),
			Vector3(side * (case_length * 0.5 - 0.06), 0.02, -0.165), case_material
		)
	_cloth_pivot = Node3D.new()
	_cloth_pivot.name = "ScreenPivot"
	_cloth_pivot.position = Vector3(0.0, SLOT_Y, SCREEN_Z)
	add_child(_cloth_pivot)
	# One metre tall, hanging from the pivot: the pivot's y scale is the unrolled length.
	_cloth = _add_box(
		_cloth_pivot, &"Surface", Vector3(screen_width, 1.0, 0.006), Vector3(0.0, -0.5, 0.0),
		screen_material
	)
	_bar = Node3D.new()
	_bar.name = "BottomBar"
	add_child(_bar)
	var bar_size := Vector3(screen_width + 0.04, BAR_SIZE.y, BAR_SIZE.z)
	_add_box(_bar, &"Bar", bar_size, Vector3.ZERO, case_material)
	_add_box(_bar, &"PullTab", Vector3(0.07, 0.05, 0.012), Vector3(0.0, -0.035, 0.0), case_material)


func _add_box(
	parent: Node3D, node_name: StringName, size: Vector3, at: Vector3, material: Material
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = at
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance
