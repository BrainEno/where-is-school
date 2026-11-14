class_name WindowCurtain
extends Node3D
## The biology classroom's floor-to-ceiling blackout curtain over the back window
## (issue #159), which can really be drawn aside.
##
## The window behind it is a real hole through the wall with nothing beyond, so the cloth
## has to hide all of it: it hangs from a ceiling track to the floor, overlaps the opening
## by `side_overlap` on both sides, and the two panels overlap at the centre. Nothing of
## the opening's edge, the wall or the floor behind it can be seen past a closed curtain.
##
## The cloth is built here, from code, so it can be exactly the size of the room's opening
## and carry deep, heavy folds: each panel is one pleated sheet whose fold depth varies a
## little from fold to fold (from a fixed seed, so every load is the same) and swings out
## slightly toward the hem, the way heavy cloth hangs. There is no ornament - no tiebacks,
## no hem trim, no rings - and the fabric material is matte (`curtain_blackout.tres`).
##
## Opening is driven by one number (`set_open_amount`, 0 = closed, 1 = drawn aside). Each
## panel hangs under a pivot on its outer edge, and opening squeezes the pivot toward that
## edge while deepening the folds - the fabric gathers at the sides the way a curtain on a
## track does. Driving everything from one value keeps the open state exact and testable:
## a curtain loaded open (a save) is in the same pose the animation ends in.
##
## Local space: x runs along the wall, y is up, +z faces the room. The origin is the
## underside of the track at the middle of the curtain; the cloth hangs down from y = 0 to
## y = -drop.
##
## Nothing here collides. The curtain is decoration as far as physics and navigation are
## concerned (`classroom_visual_slice_test.gd` keeps the room's solids a closed list).
##
## The owner's `classroom_window_curtains.glb` (a window-sized, two-colour curtain on
## rings) is no longer used here; it cannot become a floor-to-ceiling blackout without
## stretching its folds out of shape. See docs/MODEL_LIBRARY.md.

## Emitted when an animated opening has finished.
signal opened

const SAMPLES_PER_FOLD := 12
const ROWS := 6
const TRACK_HEIGHT := 0.06
const TRACK_DEPTH := 0.3

## Width of the whole curtain along the wall, metres, closed.
@export var width: float = 3.3
## From the track down to the hem, metres.
@export var drop: float = 3.14
## How far the two panels overlap at the centre, metres.
@export var centre_overlap: float = 0.1
## Folds across one panel.
@export var folds_per_panel: int = 9
## Half the depth of a fold at the top, metres (peak to the panel's mean plane).
@export var fold_depth: float = 0.055
## Extra fold depth at the hem, as a fraction of `fold_depth`.
@export var hem_swing: float = 0.25
## Fraction of a panel's width left once it is drawn aside.
@export var gathered_width: float = 0.235
## How much deeper the gathered folds are than the hanging ones.
@export var gathered_depth: float = 1.8
## Loaded drawn aside or closed (the window that hides something).
@export var start_open: bool = false
## Seconds an animated opening takes.
@export var open_seconds: float = 1.8
@export var fabric_material: Material
@export var track_material: Material
## Seed for the fold-to-fold variation.
@export var fold_seed: int = 159

var _open_amount := 0.0
var _left_pivot: Node3D = null
var _right_pivot: Node3D = null
var _panels: Array[MeshInstance3D] = []
var _track: MeshInstance3D = null
var _tween: Tween = null
var _built := false


func _ready() -> void:
	_build()
	set_open_amount(1.0 if start_open else 0.0)


## True once the curtain is fully drawn aside.
func is_open() -> bool:
	return _open_amount >= 0.999


func get_open_amount() -> float:
	return _open_amount


## Draws the curtain aside. Animated by default; awaiting it waits for the end. Calling it
## on an open curtain does nothing, so a replayed state change cannot jerk it shut and
## open again.
func open(animated: bool = true) -> void:
	_build()
	if is_open():
		return
	if _tween != null and _tween.is_valid():
		await _tween.finished
		return
	if not animated or not is_inside_tree():
		set_open_amount(1.0)
		opened.emit()
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(set_open_amount, _open_amount, 1.0, open_seconds)
	await _tween.finished
	opened.emit()


## Puts both panels where `amount` says (0 closed, 1 drawn aside).
func set_open_amount(amount: float) -> void:
	_build()
	_open_amount = clampf(amount, 0.0, 1.0)
	var squeeze := lerpf(1.0, gathered_width, _open_amount)
	var depth := lerpf(1.0, gathered_depth, _open_amount)
	for pivot in [_left_pivot, _right_pivot]:
		if pivot != null:
			(pivot as Node3D).scale = Vector3(squeeze, 1.0, depth)


## The meshes a player sees as "the curtain" (the two panels): what an interactable
## outlines.
func get_fabric_meshes() -> Array[MeshInstance3D]:
	_build()
	return _panels.duplicate()


## World-space box the drawn fabric covers right now.
func get_fabric_aabb() -> AABB:
	var result := AABB()
	var first := true
	for mesh in get_fabric_meshes():
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Width of one panel, closed (half the curtain plus half the centre overlap).
func panel_width() -> float:
	return width * 0.5 + centre_overlap * 0.5


func _build() -> void:
	if _built:
		return
	_built = true
	var half := width * 0.5
	_track = MeshInstance3D.new()
	_track.name = "Track"
	var track_mesh := BoxMesh.new()
	track_mesh.size = Vector3(width + 0.06, TRACK_HEIGHT, TRACK_DEPTH)
	_track.mesh = track_mesh
	# The track's back face is on the wall: the curtain hangs in front of it, under it.
	_track.position = Vector3(0.0, TRACK_HEIGHT * 0.5, TRACK_DEPTH * 0.5 - 0.18)
	_track.material_override = track_material
	add_child(_track)
	# The left panel hangs a few millimetres behind the right one, so the overlap at the
	# centre never z-fights and never opens a gap.
	_left_pivot = _make_pivot(&"LeftGather", -half, -0.012)
	_right_pivot = _make_pivot(&"RightGather", half, 0.012)
	_panels.append(_make_panel(_left_pivot, &"PanelLeft", 1.0, fold_seed))
	_panels.append(_make_panel(_right_pivot, &"PanelRight", -1.0, fold_seed + 7))


func _make_pivot(pivot_name: StringName, edge_x: float, z_offset: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = Vector3(edge_x, 0.0, z_offset)
	add_child(pivot)
	return pivot


## One pleated sheet from the pivot (x = 0, the outer edge) inward (`inward` = +1 or -1).
func _make_panel(
	pivot: Node3D, panel_name: StringName, inward: float, seed_value: int
) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var folds := maxi(folds_per_panel, 1)
	var amplitudes: Array[float] = []
	for k in folds:
		amplitudes.append(fold_depth * rng.randf_range(0.8, 1.15))
	var w := panel_width()
	var columns := folds * SAMPLES_PER_FOLD
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for r in ROWS + 1:
		var t := float(r) / float(ROWS)
		var y := -drop * t
		var swing := 1.0 + hem_swing * t * t
		for c in columns + 1:
			var u := float(c) / float(columns)
			var phase := u * folds
			var k := mini(int(phase), folds - 1)
			var local_phase := phase - float(k)
			var amp: float = amplitudes[k] * swing
			# One fold: back at both ends, forward in the middle. A raised cosine keeps the
			# turns soft, like cloth, rather than ruled zig-zags.
			var z := amp * -cos(local_phase * TAU)
			var dz_du := amp * sin(local_phase * TAU) * TAU * folds
			var x := inward * u * w
			# Surface p(u, y) = (inward * u * w, y, z(u)); its normal faces +z.
			var tangent := Vector3(inward * w, 0.0, dz_du)
			var n := Vector3(0.0, 1.0, 0.0).cross(tangent).normalized()
			if n.z < 0.0:
				n = -n
			vertices.append(Vector3(x, y, z))
			normals.append(n)
	var stride := columns + 1
	for r in ROWS:
		for c in columns:
			var a := r * stride + c
			var b := a + 1
			var d := a + stride
			var e := d + 1
			# Wound so the room side (+z) is the front face whichever way the panel runs.
			var triangles: Array[int] = [a, b, d, b, e, d] if inward > 0.0 else [a, d, b, b, d, e]
			for index in triangles:
				indices.append(index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var panel := MeshInstance3D.new()
	panel.name = panel_name
	panel.mesh = mesh
	panel.material_override = fabric_material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(panel)
	return panel
