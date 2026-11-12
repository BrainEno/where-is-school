class_name CharacterLookApplier
extends Node
## Puts a `CharacterLook` on the model next to it: painted materials per surface, the ink
## line on the parts that carry one, the face's resting expression, and a blink.
##
## Sits in the character wrapper (`protagonist.tscn`, `q.tscn`) beside `Model`. It changes
## what the surfaces are drawn with and nothing else: no node is added, moved or renamed,
## the skeleton, skin and bone names are the GLB's, and the animation driver on the wrapper
## root never sees the difference. N and the classroom student have no applier.
##
## Three treatments, so the treatment can be compared in the running game (the character art
## capture photographs all three; the game always uses `PAINTED`):
##   PAINTED   the look's own materials (option C in docs/CHARACTER_ART.md);
##   PIGMENT   `assets/shaders/painterly/character_pigment.gdshader`, one instance per GLB
##             material carrying that material's colour (option B);
##   ORIGINAL  the GLB's materials, untouched (option A).
##
## **Rest-pose paint coordinates.** Neither GLB has UVs, so the painted shader places its
## pigment blocks by position. A skinned vertex's position moves with the bone it follows,
## so blocks placed by it would slide through a swinging trouser leg. For PAINTED, each mesh
## without blend shapes is rebuilt once with its own bind-pose position copied into
## `CUSTOM0` (w = 2 marks it); the shader reads that, and the blocks stay on the cloth. The
## vertices, indices, normals, bone indices and weights are the GLB's, unchanged and in the
## same order; the rebuilt mesh is cached per source mesh and shared by every instance.
## Meshes with blend shapes (the protagonist's head) keep their own mesh and the shader
## falls back to the object-space position — the head only nods a few degrees.

enum Treatment { PAINTED, PIGMENT, ORIGINAL }

const PIGMENT_SHADER := preload("res://assets/shaders/painterly/character_pigment.gdshader")
## Marks a CUSTOM0 that carries a rest position (`character_paint.gdshader` tests w > 1.5).
const REST_MARK := 2.0

## Source mesh instance id → its rebuilt twin with rest coordinates (or null: not rebuildable).
static var _rest_meshes: Dictionary = {}

@export var look: CharacterLook = null
@export var treatment: Treatment = Treatment.PAINTED
## The GLB instance this applies to.
@export var model_path: NodePath = ^"../Model"
## Rebuild meshes with rest-pose paint coordinates (see above). Off draws the same
## materials with object-space coordinates, for comparison.
@export var rest_paint_coordinates: bool = true
## Blink while the PAINTED treatment is on.
@export var blinking: bool = true

var _model: Node3D = null
## MeshInstance3D → its GLB mesh, so ORIGINAL and PIGMENT can put it back.
var _source_meshes: Dictionary = {}
var _pigment_materials: Dictionary = {}
var _report: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _blink_wait := 0.0
var _blink_time := -1.0


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	if _model == null:
		push_error("CharacterLookApplier on '%s': no model at %s." % [get_parent().name, model_path])
		return
	for mesh_instance in _meshes():
		_source_meshes[mesh_instance] = mesh_instance.mesh
	# Deterministic per character, so two captures of the same scene blink alike.
	_rng.seed = hash(look.label if look != null else String(get_parent().name))
	_blink_wait = _next_blink_wait()
	apply_treatment(treatment)


func _process(delta: float) -> void:
	if treatment != Treatment.PAINTED or look == null or not blinking or look.blink_shapes.is_empty():
		return
	if _blink_time >= 0.0:
		_blink_time += delta
		var duration := maxf(look.blink_duration, 0.02)
		var closed := 1.0 - absf(_blink_time / duration * 2.0 - 1.0)
		if _blink_time >= duration:
			_blink_time = -1.0
			closed = 0.0
			_blink_wait = _next_blink_wait()
		_set_blink(clampf(closed, 0.0, 1.0))
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_time = 0.0


## Switches the model to `which` and returns the report (see `get_report()`).
func apply_treatment(which: Treatment) -> Dictionary:
	treatment = which
	_blink_time = -1.0
	var report := {
		"treatment": Treatment.keys()[which],
		"look": look.label if look != null else "",
		"surfaces": 0,
		"replaced": 0,
		"kept": [],
		"outlined": [],
		"rebuilt_meshes": [],
		"expression": {},
	}
	if _model == null:
		report["error"] = "no model"
		_report = report
		return report
	for mesh_instance in _meshes():
		var source: Mesh = _source_meshes.get(mesh_instance, mesh_instance.mesh)
		var mesh := source
		if which == Treatment.PAINTED and rest_paint_coordinates:
			var rebuilt := rest_coordinate_mesh(source as ArrayMesh)
			if rebuilt != null:
				mesh = rebuilt
				(report["rebuilt_meshes"] as Array).append(String(mesh_instance.name))
		if mesh_instance.mesh != mesh:
			mesh_instance.mesh = mesh
		for surface in mesh.get_surface_count():
			report["surfaces"] = int(report["surfaces"]) + 1
			var authored := source.surface_get_material(surface)
			var authored_name := authored.resource_name if authored != null else ""
			var replacement: Material = null
			match which:
				Treatment.PAINTED:
					if look != null:
						replacement = look.material_for(String(mesh_instance.name), authored_name)
				Treatment.PIGMENT:
					replacement = _pigment_for(authored)
			mesh_instance.set_surface_override_material(surface, replacement)
			if replacement != null:
				report["replaced"] = int(report["replaced"]) + 1
				if replacement.next_pass != null:
					(report["outlined"] as Array).append(
						"%s/%s" % [String(mesh_instance.name), authored_name]
					)
			else:
				(report["kept"] as Array).append("%s/%s" % [String(mesh_instance.name), authored_name])
		(report["expression"] as Dictionary).merge(_apply_expression(mesh_instance, which == Treatment.PAINTED))
	_report = report
	return report


## What the last `apply_treatment()` did: the treatment, how many surfaces it saw and replaced,
## the ones it kept (`mesh/material`), the outlined ones, the meshes rebuilt with rest
## coordinates and the blend shapes it set.
func get_report() -> Dictionary:
	return _report


func get_model() -> Node3D:
	return _model


## `source` rebuilt with each vertex's bind-pose position in CUSTOM0 (xyz, w = `REST_MARK`),
## or null when it cannot be (no mesh, or blend shapes, which this does not carry over).
## Everything else is the source's own data, surface by surface, in the same order.
static func rest_coordinate_mesh(source: ArrayMesh) -> ArrayMesh:
	if source == null:
		return null
	var key := source.get_instance_id()
	if _rest_meshes.has(key):
		return _rest_meshes[key] as ArrayMesh
	if source.get_blend_shape_count() > 0:
		_rest_meshes[key] = null
		return null
	var rebuilt := ArrayMesh.new()
	rebuilt.resource_name = source.resource_name
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rest := PackedFloat32Array()
		rest.resize(vertices.size() * 4)
		for index in vertices.size():
			var vertex := vertices[index]
			rest[index * 4] = vertex.x
			rest[index * 4 + 1] = vertex.y
			rest[index * 4 + 2] = vertex.z
			rest[index * 4 + 3] = REST_MARK
		arrays[Mesh.ARRAY_CUSTOM0] = rest
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if int(source.surface_get_format(surface)) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
		rebuilt.surface_set_material(surface, source.surface_get_material(surface))
		rebuilt.surface_set_name(surface, source.surface_get_name(surface))
	rebuilt.custom_aabb = source.custom_aabb
	_rest_meshes[key] = rebuilt
	return rebuilt


func _meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if _model == null:
		return found
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			found.append(mesh_instance)
	return found


func _pigment_for(authored: Material) -> Material:
	if authored == null:
		return null
	if _pigment_materials.has(authored):
		return _pigment_materials[authored] as Material
	var material := ShaderMaterial.new()
	material.shader = PIGMENT_SHADER
	material.resource_name = "%s (pigment)" % authored.resource_name
	var colour := Color(0.55, 0.46, 0.39)
	var standard := authored as BaseMaterial3D
	if standard != null:
		colour = standard.albedo_color
	material.set_shader_parameter("base_color", colour)
	_pigment_materials[authored] = material
	return material


func _apply_expression(mesh_instance: MeshInstance3D, painted: bool) -> Dictionary:
	var applied := {}
	var mesh := mesh_instance.mesh
	if mesh == null or mesh.get_blend_shape_count() == 0:
		return applied
	for index in mesh.get_blend_shape_count():
		var shape := String(mesh.get_blend_shape_name(index))
		var weight := 0.0
		if painted and look != null:
			weight = float(look.expression.get(shape, 0.0))
		mesh_instance.set_blend_shape_value(index, weight)
		if weight != 0.0:
			applied[shape] = weight
	return applied


func _set_blink(closed: float) -> void:
	for mesh_instance in _meshes():
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for shape: String in look.blink_shapes:
			var index := mesh_instance.find_blend_shape_by_name(StringName(shape))
			if index < 0:
				continue
			var resting := float(look.expression.get(shape, 0.0))
			mesh_instance.set_blend_shape_value(index, lerpf(resting, 1.0, closed))


func _next_blink_wait() -> float:
	if look == null:
		return 4.0
	return _rng.randf_range(look.blink_interval.x, maxf(look.blink_interval.y, look.blink_interval.x))
