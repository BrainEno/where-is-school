class_name PaperZone
extends Node3D
## The local paper anomaly round the classroom's back window (the biology-classroom
## experiment's blank paper, migrated as a place rather than a filter).
##
## When the curtain is drawn, the ground round the opening turns into a pencil drawing on
## an answer sheet - the floor, the wall either side of the cut, the curtain, the nearest
## desks - spreading out from the opening over `REVEAL_SECONDS` (the experiment's own
## timing). Everything farther than `radius` keeps its materials. Characters are never
## drawn: `excluded_paths` keeps the room's actors out, and the player and Q's companion
## body are not part of the room at all.
##
## How it is kept local:
##
## * Only meshes whose world box reaches into the zone (a vertical cylinder of `radius`
##   round this node, plus the torn front's margin) get the overlay. Their authored
##   materials are never touched; the overlay is removed again, exactly, when the curtain
##   goes back (`set_drawn(false)`). A mesh that already carries an overlay (the desks'
##   wash and ink, `classroom_desk_ink.gd`) keeps it: it gets a copy of that overlay chain
##   with the paper appended as the last pass (the way `OutlineOverlay._keyed` appends its
##   key), so the shared original is never changed, and gets the original back on release.
## * The overlay (`paper_zone.gdshader`) masks itself by the same world-space distance, so
##   a mesh that reaches only partly into the zone is drawn only where it does, and the
##   edge is continuous across meshes and fixed in the room.
##
## The meshes are collected once per drawing: the room's furniture does not move.

## The experiment's paper reveal (paper_switch.gd REVEAL_SECONDS / LIFT_SECONDS).
const REVEAL_SECONDS := 2.2
const LIFT_SECONDS := 0.9
## Room materials are sorted into these tones (sRGB luma): the darker a surface, the more
## hatching families cover it, as the experiment's filter read off the frame.
const TONES: Array[float] = [0.18, 0.4, 0.62, 0.84]
## The torn front reaches this far past `radius` (paper_zone.gdshader `ragged` * 0.5 plus
## its feather).
const FRONT_MARGIN := 0.35
const BASE_MATERIAL := preload("res://assets/materials/classroom/paper_zone.tres")

## Horizontal radius of the paper, metres from this node.
@export var radius: float = 2.6
## The node whose meshes may be drawn (the location root).
@export var scope_path: NodePath = ^"../.."
## Subtrees of the scope that are never drawn: the people, and the blank sheet in the
## opening, which is already paper.
@export var excluded_paths: Array[NodePath] = [^"Actors", ^"Anomalies/VoidOpening"]

var _scope: Node = null
## MeshInstance3D -> the overlay it had (always null today; restored on release).
var _covered: Dictionary = {}
## Tone index -> the overlay material for that tone.
var _materials: Array[ShaderMaterial] = []
var _reveal: float = 0.0
var _drawn: bool = false
var _tween: Tween = null


func _ready() -> void:
	_scope = get_node_or_null(scope_path)
	if _scope == null:
		push_error("PaperZone: scope_path '%s' did not resolve." % scope_path)
	for tone in TONES:
		var material := BASE_MATERIAL.duplicate() as ShaderMaterial
		material.set_shader_parameter("base_value", tone)
		_materials.append(material)
	_apply_uniforms()


## Draws the room round the opening on paper (or gives it back). `animated` spreads the
## paper out from the opening; otherwise it is there at once (a room loaded as the story
## left it).
func set_drawn(drawn: bool, animated: bool = false) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_drawn = drawn
	if drawn:
		if _scope != null and not _scope.is_node_ready():
			# A room built as the story left it draws its paper from its anomalies' `_ready`,
			# before later siblings are ready - and some of them lay their own overlays then
			# (the desks' ink). Wait for the whole room, so those are kept, not pre-empted.
			if not _scope.ready.is_connected(_cover_if_drawn):
				_scope.ready.connect(_cover_if_drawn, CONNECT_ONE_SHOT)
		else:
			_cover()
	var target := 1.0 if drawn else 0.0
	if not animated or not is_inside_tree():
		_set_reveal(target)
		if not drawn:
			_uncover()
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if drawn else Tween.EASE_IN)
	_tween.tween_method(_set_reveal, _reveal, target, REVEAL_SECONDS if drawn else LIFT_SECONDS)
	if not drawn:
		_tween.tween_callback(_uncover)


func is_drawn() -> bool:
	return _drawn


## 0 = no paper, 1 = the whole zone.
func get_reveal() -> float:
	return _reveal


## The meshes that carry the paper right now.
func get_covered_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for key: Variant in _covered.keys():
		if is_instance_valid(key):
			meshes.append(key as MeshInstance3D)
	return meshes


## The shared overlay materials (one per tone), for tests.
func get_overlay_materials() -> Array[ShaderMaterial]:
	return _materials


## Whether a world box reaches into the zone (the cylinder plus the torn front's margin).
func reaches(box: AABB) -> bool:
	var centre := global_position
	var nearest_x := clampf(centre.x, box.position.x, box.end.x)
	var nearest_z := clampf(centre.z, box.position.z, box.end.z)
	return Vector2(nearest_x - centre.x, nearest_z - centre.z).length() <= radius + FRONT_MARGIN


func _cover() -> void:
	if _scope == null or not _covered.is_empty():
		return
	var excluded: Array[Node] = []
	for path: NodePath in excluded_paths:
		var node := _scope.get_node_or_null(path)
		if node != null:
			excluded.append(node)
	for node in _scope.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _is_excluded(mesh, excluded):
			continue
		if not reaches(mesh.global_transform * mesh.get_aabb()):
			continue
		_covered[mesh] = mesh.material_overlay
		mesh.material_overlay = _with_paper(mesh.material_overlay, _materials[_tone_index(mesh)])


func _cover_if_drawn() -> void:
	if _drawn:
		_cover()


func _uncover() -> void:
	for key: Variant in _covered.keys():
		if is_instance_valid(key):
			var mesh := key as MeshInstance3D
			mesh.material_overlay = _covered[key] as Material
	_covered.clear()


## `authored` (copied, chain and all) with `paper` as its last pass, or `paper` alone.
static func _with_paper(authored: Material, paper: ShaderMaterial) -> Material:
	if authored == null:
		return paper
	var head := authored.duplicate() as Material
	var tail := head
	while tail.next_pass != null:
		tail.next_pass = tail.next_pass.duplicate() as Material
		tail = tail.next_pass
	tail.next_pass = paper
	return head


## Whether `material`'s overlay chain ends in one of this zone's papers.
func carries_paper(material: Material) -> bool:
	while material != null:
		if _materials.has(material):
			return true
		material = material.next_pass
	return false


func _is_excluded(mesh: Node, excluded: Array[Node]) -> bool:
	for node in excluded:
		if node == mesh or node.is_ancestor_of(mesh):
			return true
	return false


## Which tone a mesh reads as: the luma of its material's colour (a painted texture counts
## as a mid tone, which the classroom's plaster and wood are).
func _tone_index(mesh: MeshInstance3D) -> int:
	var value := 0.62
	var material := mesh.get_active_material(0)
	var base := material as BaseMaterial3D
	var shader := material as ShaderMaterial
	if base != null:
		var colour := base.albedo_color
		value = colour.get_luminance() * (0.75 if base.albedo_texture != null else 1.0)
	elif shader != null:
		var parameter: Variant = shader.get_shader_parameter("base_color")
		if parameter is Color:
			var colour: Color = parameter
			value = colour.get_luminance()
	var best := 0
	for index in TONES.size():
		if absf(TONES[index] - value) < absf(TONES[best] - value):
			best = index
	return best


func _set_reveal(value: float) -> void:
	_reveal = clampf(value, 0.0, 1.0)
	_apply_uniforms()


func _apply_uniforms() -> void:
	for material in _materials:
		material.set_shader_parameter("zone_centre", global_position if is_inside_tree() else position)
		material.set_shader_parameter("zone_radius", radius)
		material.set_shader_parameter("reveal", _reveal)
