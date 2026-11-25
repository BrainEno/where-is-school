class_name CharacterLookApplier
extends Node
## Puts a `CharacterLook` on the model next to it: painted materials per surface, the ink
## line on the parts that carry one, the face's resting expression, a directed face state
## (`set_face_state()`, from `CharacterLook.face_states`), and a blink.
##
## **One writer.** Every morph weight on a shipped character is written here (the
## classroom Q's textbook pose excepted - it owns `Smile`/`Mouth_Open`, which no face
## state names). The layers compose in `_composed_weight()`: resting expression under,
## directed state in the middle, blink on top, so a blink and a state can never erase
## each other. Nothing outside this file should call `set_blend_shape_value()` on a
## character mesh.
##
## Sits in the character wrapper (`protagonist.tscn`, `q.tscn`, `teacher_n.tscn`, and the
## seated `classroom_student.tscn`) beside `Model`. It changes what the surfaces are drawn
## with and nothing else: no node is added, moved or renamed, the skeleton, skin and bone
## names are the GLB's, and the animation driver on the wrapper root never sees the
## difference.
##
## Three treatments, so the treatment can be compared in the running game (the character art
## capture photographs all three; the game always uses `PAINTED`):
##   PAINTED   the look's own materials (option C in docs/CHARACTER_ART.md);
##   PIGMENT   `assets/shaders/painterly/character_pigment.gdshader`, one instance per GLB
##             material carrying that material's colour (option B);
##   ORIGINAL  the GLB's materials, untouched (option A).
##
## **Rest-pose paint coordinates.** No GLB ships UVs for its paint, so the painted shader
## places its pigment blocks by position. A skinned vertex's position moves with the bone it
## follows, so blocks placed by it would slide through a swinging trouser leg. For PAINTED, each
## mesh without blend shapes is rebuilt once with its own bind-pose position copied into
## `CUSTOM0` (w = 2 marks it); the shader reads that, and the blocks stay on the cloth. The
## vertices, indices, normals, bone indices and weights are the GLB's, unchanged and in the same
## order; the rebuilt mesh is cached per source mesh and shared by every instance. Meshes with
## blend shapes (the protagonist's head) keep their own mesh and the shader falls back to the
## object-space position — the head only nods a few degrees.
##
## **Local detail maps.** The one exception is the protagonist's V2 head, which carries its own
## UV atlas beside its triangles (`tools/head_v2.py`). A look may name a `CharacterDetailMaps` per
## material; the applier sets it on that surface — and only on a surface that really has UVs — so
## the head's colour and relief come from maps while the rest of the game's characters, which
## have no UVs, draw exactly as before. `detail_maps_enabled` is the switch the A/B is taken on.

enum Treatment { PAINTED, PIGMENT, ORIGINAL }

const PIGMENT_SHADER := preload("res://assets/shaders/painterly/character_pigment.gdshader")
## Marks a CUSTOM0 that carries a rest position (`character_paint.gdshader` tests w > 1.5).
const REST_MARK := 2.0

## Source mesh instance id → its rebuilt twin with rest coordinates.
static var _rest_meshes: Dictionary = {}

@export var look: CharacterLook = null
@export var treatment: Treatment = Treatment.PAINTED
## The GLB instance this applies to.
@export var model_path: NodePath = ^"../Model"
## Rebuild meshes with rest-pose paint coordinates (see above). Off draws the same
## materials with object-space coordinates, for comparison.
@export var rest_paint_coordinates: bool = true
## Opt in when fine detail is baked on a face with both skinning and expression
## targets. Existing looks retain their original blend-shaped meshes by default.
@export var rest_paint_blend_shapes: bool = false
## Draw a look's local detail maps (`CharacterLook.detail_maps`) on the surfaces that carry
## UVs. Off draws the same materials without them — the same geometry, the same flat colour —
## which is the A/B the V2 head's maps are judged with.
@export var detail_maps_enabled: bool = true
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
## The blink channel's current value (0 open, 1 shut), composed *under* nothing - the
## blink is the top layer of `_composed_weight()`.
var _blink_closed := 0.0
## The directed face state currently requested (`""` while settling out), the blend
## shapes it sets, and how far the blend has travelled toward it (0 none, 1 held).
var _state_name: StringName = &""
var _state_target: Dictionary = {}
var _state_weight := 0.0
var _state_blend := 0.3
## A state arrived since the last frame (its target must be written even if the blend
## weight has not moved).
var _state_dirty := false


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
	if treatment != Treatment.PAINTED or look == null:
		return
	# The directed face layer eases toward its state (or back to rest when clearing).
	# It writes only while the blend is moving or a new state just arrived: a held state
	# or a settled face costs nothing per frame, the same bargain the blink already makes.
	var wanted := 1.0 if not _state_name.is_empty() else 0.0
	if _state_dirty or not is_equal_approx(_state_weight, wanted):
		if _state_blend <= 0.0:
			_state_weight = wanted
		else:
			_state_weight = move_toward(_state_weight, wanted, delta / _state_blend)
		if _state_weight <= 0.0 and wanted == 0.0:
			_state_weight = 0.0
		# Write with the target still in place: at weight 0 the composition is rest,
		# so the meshes are left exactly at rest, and only then is the target dropped.
		# Clearing it before the write would strand the meshes at the last value they
		# were given.
		_write_state_shapes()
		_state_dirty = false
		if _state_weight <= 0.0 and wanted == 0.0:
			_state_target = {}
	if not blinking or look.blink_shapes.is_empty():
		return
	if _blink_time >= 0.0:
		_blink_step(delta)
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_time = 0.0


## One step of an open blink: updates the blink channel and writes the composed value
## of every blink shape (rest, then the face state, then the lid on top).
func _blink_step(delta: float) -> void:
	_blink_time += delta
	var duration := maxf(look.blink_duration, 0.02)
	var closed := 1.0 - absf(_blink_time / duration * 2.0 - 1.0)
	if _blink_time >= duration:
		_blink_time = -1.0
		closed = 0.0
		_blink_wait = _next_blink_wait()
	_set_blink(clampf(closed, 0.0, 1.0))


## Switches the model to `which` and returns the report (see `get_report()`).
##
## A treatment switch is also a settle: the directed face state returns to rest and the
## blink channel to open, so a rebind (a capture changing looks, a fresh session) can
## never inherit a half-applied face from before it.
func apply_treatment(which: Treatment) -> Dictionary:
	treatment = which
	_blink_time = -1.0
	_blink_closed = 0.0
	_state_name = &""
	_state_target = {}
	_state_weight = 0.0
	_state_dirty = false
	var report := {
		"treatment": Treatment.keys()[which],
		"look": look.label if look != null else "",
		"surfaces": 0,
		"replaced": 0,
		"kept": [],
		"outlined": [],
		"rebuilt_meshes": [],
		"detail_maps": [],
		"detail_maps_skipped": [],
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
			var rebuilt := rest_coordinate_mesh(source as ArrayMesh, rest_paint_blend_shapes)
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
			if which == Treatment.PAINTED and look != null and detail_maps_enabled:
				var maps := look.detail_maps_for(String(mesh_instance.name), authored_name)
				if maps != null and maps.has_any():
					replacement = _with_detail_maps(replacement, maps, mesh, surface,
						String(mesh_instance.name), report)
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
## or null if there is no mesh or the caller has not opted in to copying morph targets.
## Surface materials, skin attributes and shape names/data retain their original order.
static func rest_coordinate_mesh(source: ArrayMesh, include_shapes := false) -> ArrayMesh:
	if source == null or (source.get_blend_shape_count() > 0 and not include_shapes):
		return null
	var key := source.get_instance_id()
	if _rest_meshes.has(key):
		return _rest_meshes[key] as ArrayMesh
	var rebuilt := ArrayMesh.new()
	rebuilt.resource_name = source.resource_name
	rebuilt.blend_shape_mode = source.blend_shape_mode
	for shape in source.get_blend_shape_count():
		rebuilt.add_blend_shape(source.get_blend_shape_name(shape))
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
		var morphs: Array[Array] = []
		if include_shapes:
			morphs = source.surface_get_blend_shape_arrays(surface)
		rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, morphs, {}, flags)
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


## `replacement` with `maps` set on it, on a copy so the look's own material is untouched, or
## null if this surface cannot carry them. A surface is only given maps when it really has UVs:
## without them every fragment would sample the same texel, which is how a hand sharing the
## head's skin material would turn into one flat colour. The name of a surface that was skipped
## goes in the report, so a look that asks for maps on a part without UVs is visible.
static func _with_detail_maps(replacement: Material, maps: CharacterDetailMaps,
		mesh: Mesh, surface: int, label: String, report: Dictionary) -> Material:
	var key := "%s/%d" % [label, surface]
	if replacement == null:
		(report["detail_maps_skipped"] as Array).append(key)
		return null
	var arrays := mesh.surface_get_arrays(surface)
	# A surface without UVs leaves the slot null rather than absent, so the slot's
	# contents -- not the array's size -- decide whether this surface can carry maps.
	var uvs := PackedVector2Array()
	if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		(report["detail_maps_skipped"] as Array).append(key)
		return null
	var painted := replacement.duplicate() as ShaderMaterial
	if painted == null:
		(report["detail_maps_skipped"] as Array).append(key)
		return null
	if maps.albedo != null:
		painted.set_shader_parameter("has_detail_albedo", true)
		painted.set_shader_parameter("detail_albedo", maps.albedo)
		painted.set_shader_parameter("detail_albedo_mix", maps.albedo_mix)
	if maps.normal != null:
		painted.set_shader_parameter("has_detail_normal", true)
		painted.set_shader_parameter("detail_normal", maps.normal)
		painted.set_shader_parameter("detail_normal_strength", maps.normal_strength)
	(report["detail_maps"] as Array).append(key)
	return painted


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
			weight = _composed_weight(shape)
		mesh_instance.set_blend_shape_value(index, weight)
		if weight != 0.0:
			applied[shape] = weight
	return applied


## Holds `state` (a key of `CharacterLook.face_states`) as this face's directed layer,
## blending from wherever the face currently is over `blend_seconds`. Returns false when
## the look has no such state: N and the seated student honestly have no face states of
## their own instead of borrowing another character's.
func set_face_state(state: StringName, blend_seconds := 0.3) -> bool:
	if look == null:
		return false
	var shapes: Variant = look.face_states.get(String(state))
	if not (shapes is Dictionary) or (shapes as Dictionary).is_empty():
		return false
	_state_name = state
	_state_target = (shapes as Dictionary).duplicate()
	_state_blend = maxf(blend_seconds, 0.0)
	_state_dirty = true
	if _state_blend <= 0.0:
		_state_weight = 1.0
		if treatment == Treatment.PAINTED:
			_write_state_shapes()
			_state_dirty = false
	return true


## Lets the face settle back to its resting expression over `blend_seconds`: the
## "expression settles" half of a conversation ending, a look being released, or a
## load dropping the session that asked for the state.
func clear_face_state(blend_seconds := 0.3) -> void:
	if _state_name.is_empty() and _state_weight <= 0.0:
		return
	_state_name = &""
	_state_blend = maxf(blend_seconds, 0.0)
	if _state_blend > 0.0 and treatment == Treatment.PAINTED:
		# The target stays until the blend arrives, so the fade is out of the state the
		# face was actually holding.
		_state_dirty = true
		return
	_state_weight = 0.0
	_state_dirty = false
	# Write at weight 0 with the target still in place (composition = rest), then
	# drop it: the meshes end exactly at rest instead of at the state's last value.
	if treatment == Treatment.PAINTED:
		_write_state_shapes()
	_state_target = {}


## The directed state currently requested (empty while the face is settling out).
func get_face_state() -> StringName:
	return _state_name


## How far the face has blended into the requested state: 0 is rest, 1 is held.
func get_face_state_weight() -> float:
	return _state_weight


## Every blend shape's weight as this applier composes it - resting expression, moved
## toward the active state, blink lid on top. The mesh is written from the same
## function, so tests compare against what is actually drawn.
func get_composed_face() -> Dictionary:
	var composed := {}
	if look == null:
		return composed
	for mesh_instance in _meshes():
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for index in mesh.get_blend_shape_count():
			var shape := String(mesh.get_blend_shape_name(index))
			composed[shape] = _composed_weight(shape)
	return composed


## The weight one shape should currently hold. The whole priority order of the face in
## one function: the resting expression, moved toward the active state's target for the
## shapes the state names, with the blink lid on top of that. Nothing else writes morphs
## on a shipped character (`q_textbook_pose` excepted - it owns `Smile`/`Mouth_Open`,
## which no state here names).
func _composed_weight(shape: String) -> float:
	var weight := float(look.expression.get(shape, 0.0))
	if _state_weight > 0.0 and _state_target.has(shape):
		weight = lerpf(weight, float(_state_target[shape]), _state_weight)
	if look.blink_shapes.has(shape):
		weight = lerpf(weight, 1.0, _blink_closed)
	return weight


## Writes the composed weight of every shape the active state names, on every mesh that
## has it.
func _write_state_shapes() -> void:
	if look == null or _state_target.is_empty():
		return
	for mesh_instance in _meshes():
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for shape: String in _state_target:
			var index := mesh_instance.find_blend_shape_by_name(StringName(shape))
			if index < 0:
				continue
			mesh_instance.set_blend_shape_value(index, _composed_weight(shape))


## Moves the blink channel to `closed` and writes the composed value of each blink
## shape. The blink never looks at the state to decide its own value and the state
## never writes a blink shape, so the two cannot overwrite each other - they meet only
## in `_composed_weight()`.
func _set_blink(closed: float) -> void:
	_blink_closed = closed
	if look == null:
		return
	for mesh_instance in _meshes():
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for shape: String in look.blink_shapes:
			var index := mesh_instance.find_blend_shape_by_name(StringName(shape))
			if index < 0:
				continue
			mesh_instance.set_blend_shape_value(index, _composed_weight(shape))


func _next_blink_wait() -> float:
	if look == null:
		return 4.0
	return _rng.randf_range(look.blink_interval.x, maxf(look.blink_interval.y, look.blink_interval.x))
