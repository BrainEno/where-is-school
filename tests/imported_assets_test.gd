extends SceneTree
## The imported production assets (round two): six GLBs that came from outside the
## repository — two Poly Haven CC0 props and the owner's four Blender characters (the
## protagonist, the former protagonist who now sits in the classroom as a student, Q and the
## substitute teacher N) —
## measured in the engine, not in a file listing.
##
##   godot --headless --path . --script res://tests/imported_assets_test.gd
##
## `tests/model_import_test.gd` measures the two *sample* models against the pipeline
## contract and pins the one placement in the slice. This test does the same job for the
## assets a cloud agent is meant to build scenes from, with one difference: it records
## where each asset genuinely deviates from that contract instead of pretending it does
## not. Three deviations exist and each is pinned here so a re-export that silently
## changes it fails:
##
## 1. the protagonist and Q face **+Z**, not the -Z the pipeline asks for (N is the one
##    character that faces -Z), and the wrapper does not hide it (a yaw baked into the
##    wrapper would break the moment the GLB is replaced) — see docs/ASSET_PIPELINE.md §10;
## 2. the stationery is a *display line-up* of nine separate items centred on its own
##    origin, so the wrapper re-origins it to its base;
## 3. no asset carries a non-unit node scale. `q.glb` used to be the one exception
##    (`Q_Collar`, 1 × 0.7 × 0.9, recorded here by name); the rigging re-export baked that
##    scale into the collar's vertices, which is what §1 asks for, so the record is empty
##    and the rule now holds for all six assets. A new scale still fails this test.
##
## The player's twelve named flat-colour materials must import with real, distinct albedo colours;
## this does not judge silhouette, deformation quality, or a performance budget.

const Harness = preload("res://tests/test_harness.gd")
## The painted looks and motion profiles the protagonist's and Q's wrappers carry
## (docs/CHARACTER_ART.md), by asset name. N and the classroom student have neither.
const CHARACTER_LOOKS := {
	"protagonist": {
		"look": "res://assets/characters/protagonist/protagonist_look.tres",
		"motion": "res://assets/characters/protagonist/protagonist_motion.tres",
	},
	"q": {
		"look": "res://assets/characters/q/q_look.tres",
		"motion": "res://assets/characters/q/q_motion.tres",
	},
}
const PAINT_SHADER_PATH := "res://assets/shaders/characters/character_paint.gdshader"
const PIGMENT_SHADER_PATH := "res://assets/shaders/painterly/character_pigment.gdshader"

const PIPELINE_DOC := "res://docs/ASSET_PIPELINE.md"
const PROVENANCE_DOC := "res://docs/ASSET_PROVENANCE.md"

## A model is authored to size: 2 cm is already a modelling error at this scale.
const SIZE_TOLERANCE := 0.02
## The origin's height, measured on the GLB itself, is what a placement method has to
## know about, so it is pinned tightly.
const BASE_TOLERANCE := 0.005
## Where every wrapper's own origin has to sit: on the object's base.
const WRAPPER_BASE_TOLERANCE := 0.02

## Every named surface on the production protagonist must carry an authored base colour.
const PROTAGONIST_MATERIAL_NAMES := [
	"protagonist_mat_skinbody",
	"protagonist_mat_trousers",
	"protagonist_mat_shirt",
	"protagonist_mat_button",
	"protagonist_mat_sclera",
	"protagonist_mat_iris",
	"protagonist_mat_pupil",
	"protagonist_mat_shoes",
	"protagonist_mat_hair",
	"protagonist_mat_skin",
	"protagonist_mat_mouthinner",
	"protagonist_mat_jacket",
]

const ASSETS: Array[Dictionary] = [
	{
		"name": "school_desk",
		"file": "res://assets/models/school_desk/school_desk.glb",
		"wrapper": "res://scenes/environment/props/school_desk.tscn",
		"size": Vector3(0.7118, 0.8826, 0.5460),
		"meshes": 1,
		"surfaces": 1,
		"model_base": 0.0,
		"scaled_nodes": {},
		"kind": "prop",
		"shape": "BoxShape3D",
		"note": "a one-seat school desk with a storage box and a wood top",
	},
	{
		"name": "stationery_supplies",
		"file": "res://assets/models/stationery_supplies/stationery_supplies.glb",
		"wrapper": "res://scenes/environment/props/stationery_supplies.tscn",
		"size": Vector3(0.3019, 0.1643, 0.0837),
		"meshes": 9,
		"surfaces": 9,
		"model_base": -0.0737,
		"scaled_nodes": {},
		"kind": "decoration",
		"shape": "",
		"note": "a display line-up of nine pens, pencils, an eraser and a cup",
	},
	{
		"name": "protagonist",
		"file": "res://assets/models/protagonist/Protagonist_Character.glb",
		"wrapper": "res://scenes/environment/characters/protagonist.tscn",
		# 1.05 m wide because the arms rest in an A-pose (~35° out from the body).
		"size": Vector3(1.0457, 1.7669, 0.3236),
		"meshes": 9,
		"surfaces": 15,
		"model_base": 0.0,
		"scaled_nodes": {},
		"kind": "character",
		"shape": "",
		"anchor_height": 1.2,
		"note": "the player's protagonist (PR #118): 60-joint skin, A-pose arms, five embedded "
			+ "clips the game does not play",
	},
	{
		"name": "former protagonist",
		"file": "res://assets/models/protagonist/protagonist.glb",
		"wrapper": "res://scenes/environment/characters/classroom_student.tscn",
		"size": Vector3(0.5559, 1.7269, 0.3370),
		"meshes": 78,
		"surfaces": 78,
		"model_base": 0.0170,
		"scaled_nodes": {},
		"kind": "seated_character",
		"shape": "",
		# The wrapper lowers the model so that, in `sit_idle`, the soles meet the floor the
		# wrapper stands on: its origin is the floor under the seat, not the standing base.
		"seated_drop": -0.347,
		"note": "the first protagonist model, now a seated classroom student; rigid-weighted, "
			+ "no embedded animation",
	},
	{
		"name": "q",
		"file": "res://assets/models/q/q.glb",
		"wrapper": "res://scenes/environment/characters/q.tscn",
		# 1.6466 and not 1.6618: the rig bake dropped the ~9° authored tilt on Q's head and
		# hair nodes instead of applying it to the vertices, which lowers the crown by 1.5 cm
		# and leaves the rest of the silhouette where it was. See the note below.
		"size": Vector3(0.7255, 1.6466, 0.6069),
		"meshes": 7,
		"surfaces": 15,
		"model_base": 0.0,
		# Baked into the vertices by the rigging pass; the collar occupies the same world box
		# as before, so the baked scale is not a size change anywhere but in the file.
		"scaled_nodes": {},
		"kind": "character",
		"shape": "",
		"anchor_height": 1.2,
		"note": "the classmate Q, flat-colour materials, no textures; rigged, and its head/hair "
			+ "node tilt was dropped by the rig bake (crown 1.5 cm lower than the unrigged file)",
	},
	{
		"name": "teacher n",
		"file": "res://assets/models/teacher-n/teacher-n.glb",
		"wrapper": "res://scenes/environment/characters/teacher_n.tscn",
		# 0.62 m wide with the arms resting slightly out from the body; 1.654 m sole to crown.
		"size": Vector3(0.6244, 1.6539, 0.3262),
		"meshes": 18,
		"surfaces": 28,
		"model_base": 0.0,
		"scaled_nodes": {},
		"kind": "character",
		"shape": "",
		"anchor_height": 1.2,
		# The only character exported the way docs/ASSET_PIPELINE.md §1 asks.
		"faces": "-Z",
		"note": "substitute teacher N, built by tools/prepare_teacher_n.py from the owner's "
			+ "export: 16-joint skin, 17 flat-colour materials, no textures, four embedded loops",
	},
]

## N's materials after `tools/prepare_teacher_n.py`: the names the owner gave them, and the
## roughness the script sets on the six it tunes (see `ROUGHNESS` there). The other eleven keep
## the owner's value, so only these are pinned; every one of the seventeen has to arrive.
const TEACHER_N_MATERIAL_NAMES := [
	"m_st_blouse", "m_st_button", "m_st_skin", "m_st_cardigan", "m_st_sclera", "m_st_iris",
	"m_st_pupil", "m_st_brow", "m_st_hair", "m_st_hairlight", "m_st_mouthinner", "m_st_lip",
	"m_st_teeth", "m_st_lash", "m_st_shoes", "m_st_sole", "m_st_trousers",
]
const TEACHER_N_ROUGHNESS := {
	"m_st_skin": 0.8, "m_st_hair": 0.75, "m_st_hairlight": 0.72, "m_st_brow": 0.85,
	"m_st_lash": 0.85, "m_st_shoes": 0.6,
}

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "imported_assets_test.gd")
	call_deferred("_run")


func _run() -> void:
	var holder := Node3D.new()
	holder.name = "ImportedAssetsHolder"
	root.add_child(holder)

	for asset: Dictionary in ASSETS:
		Harness.stage = String(asset["name"])
		await _check_model(asset, holder)
		_check_wrapper(asset, holder)

	root.remove_child(holder)
	holder.free()

	Harness.stage = "documents"
	_check_documents()
	Harness.finish(
		self, _failures,
		"all six imported assets measure at their declared size and ship a wrapper that matches them."
	)


# --- the model ---------------------------------------------------------------


func _check_model(asset: Dictionary, holder: Node3D) -> void:
	var label := String(asset["name"])
	var path := String(asset["file"])
	if not ResourceLoader.exists(path):
		_failures.append("%s does not exist at %s." % [label, path])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("%s did not import as a scene." % label)
		return
	var instance := packed.instantiate()
	if instance == null:
		_failures.append("%s imported as a scene that cannot be instantiated." % label)
		return
	holder.add_child(instance)
	await process_frame
	await process_frame

	var meshes := _meshes_under(instance)
	if meshes.size() != int(asset["meshes"]):
		_failures.append(
			"%s has %d mesh instance(s); the asset is recorded as %d."
			% [label, meshes.size(), int(asset["meshes"])]
		)

	var surfaces := 0
	var extent := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in meshes:
		var box: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		extent = box if first else extent.merge(box)
		first = false
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			_failures.append("%s has a mesh instance with no surface." % label)
			continue
		surfaces += mesh_instance.mesh.get_surface_count()
		for index in mesh_instance.mesh.get_surface_count():
			if mesh_instance.get_active_material(index) == null:
				_failures.append(
					"%s has a surface with no material, so it would render untextured." % label
				)
	if surfaces != int(asset["surfaces"]):
		_failures.append(
			"%s has %d material surface(s); the asset is recorded as %d."
			% [label, surfaces, int(asset["surfaces"])]
		)

	if label == "protagonist":
		_check_protagonist_palette(meshes)
	if label == "teacher n":
		_check_teacher_n_materials(meshes)

	var expected: Vector3 = asset["size"]
	for axis in 3:
		var measured: float = extent.size[axis]
		if absf(measured - expected[axis]) > SIZE_TOLERANCE:
			_failures.append(
				"%s measures %.4f m on axis %d, the asset is recorded at %.4f m (%s)."
				% [label, measured, axis, expected[axis], String(asset["note"])]
			)

	var base: float = extent.position.y
	var expected_base := float(asset["model_base"])
	if absf(base - expected_base) > BASE_TOLERANCE:
		_failures.append(
			"%s has its origin %.4f m above its lowest point, recorded as %.4f m; "
			% [label, base, expected_base]
			+ "a re-export changed where the model meets the floor."
		)

	_check_scaled_nodes(label, instance, asset)
	if String(asset["kind"]).ends_with("character"):
		_check_facing(label, meshes, String(asset.get("faces", "+Z")))

	holder.remove_child(instance)
	instance.free()


## The pipeline forbids a node scale other than 1. Every asset honours it now; an exception
## would be named in its `scaled_nodes` so a *new* one cannot appear unnoticed.
func _check_scaled_nodes(label: String, instance: Node, asset: Dictionary) -> void:
	var expected: Dictionary = asset["scaled_nodes"]
	var found: Dictionary = {}
	for node in _descendants(instance):
		var spatial := node as Node3D
		if spatial == null:
			continue
		if not spatial.scale.is_equal_approx(Vector3.ONE):
			found[String(spatial.name)] = spatial.scale
	if found.size() != expected.size():
		_failures.append(
			"%s imports with %d scaled node(s) %s; the asset records %d."
			% [label, found.size(), str(found.keys()), expected.size()]
		)
		return
	for name in expected:
		if not found.has(name):
			_failures.append("%s no longer carries the recorded node scale on '%s'." % [label, name])
		elif not (found[name] as Vector3).is_equal_approx(expected[name]):
			_failures.append(
				"%s node '%s' carries scale %s; recorded as %s."
				% [label, name, str(found[name]), str(expected[name])]
			)
			return


## The protagonist and Q were authored facing +Z, which is the opposite of the pipeline's
## `-Z forward` rule; N follows the rule. No wrapper corrects either, so the fact is asserted
## instead: the eyes have to be in front, or every placement in the repository is suddenly a
## guess. See docs/ASSET_PIPELINE.md §10. `faces` is "+Z" or "-Z".
func _check_facing(label: String, meshes: Array[MeshInstance3D], faces: String) -> void:
	var toward := -1.0 if faces == "-Z" else 1.0
	var front := -INF
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(index)
			if material == null or not material.resource_name.to_lower().contains("iris"):
				continue
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				front = maxf(front, toward * (mesh_instance.global_transform * vertex).z)
	if front == -INF:
		_failures.append("%s has no surface whose material is named for the iris." % label)
	elif front <= 0.0:
		_failures.append(
			"%s no longer faces %s: its eyes reach z=%.4f. Update the facing note in "
			% [label, faces, toward * front]
			+ "docs/ASSET_PIPELINE.md §10 and every placement that relies on it."
		)


## Catch the exact regression: named materials without PBR base colours import as white.
func _check_protagonist_palette(meshes: Array[MeshInstance3D]) -> void:
	var found: Dictionary = {}
	var distinct_colours: Array[Color] = []
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index)
			if material == null:
				continue
			var material_name := material.resource_name.to_lower()
			if not material_name.begins_with("protagonist_mat_"):
				continue
			found[material_name] = true
			var standard := material as StandardMaterial3D
			if standard == null:
				_failures.append(
					"Protagonist material '%s' did not import as a StandardMaterial3D."
					% material_name
				)
				continue
			var albedo := standard.albedo_color
			if albedo.is_equal_approx(Color.WHITE):
				_failures.append(
					"Protagonist material '%s' has the default white albedo; its GLB baseColorFactor is missing."
					% material_name
				)
			var duplicate := false
			for previous: Color in distinct_colours:
				if albedo.is_equal_approx(previous):
					duplicate = true
					break
			if not duplicate:
				distinct_colours.append(albedo)

	for expected_name: String in PROTAGONIST_MATERIAL_NAMES:
		if not found.has(expected_name):
			_failures.append(
				"The protagonist no longer imports the expected material '%s'." % expected_name
			)
	if distinct_colours.size() < 8:
		_failures.append(
			"The protagonist imports only %d distinct material colours; its art-directed palette is missing."
			% distinct_colours.size()
		)


## N's seventeen materials stay seventeen: named as the owner named them, flat colour (no
## texture), not metallic, with the roughness the preparation script gives the six it tunes.
## Merging them, or a re-export that lost the base colours, fails here.
func _check_teacher_n_materials(meshes: Array[MeshInstance3D]) -> void:
	var found: Dictionary = {}
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index)
			if material == null:
				continue
			var material_name := material.resource_name.to_lower()
			found[material_name] = true
			var standard := material as StandardMaterial3D
			if standard == null:
				_failures.append("N's material '%s' did not import as a StandardMaterial3D." % material_name)
				continue
			if standard.albedo_color.is_equal_approx(Color.WHITE):
				_failures.append("N's material '%s' imported white; its base colour is missing." % material_name)
			if standard.albedo_texture != null:
				_failures.append("N's material '%s' has a texture; the model is flat colour." % material_name)
			if standard.metallic > 0.001:
				_failures.append("N's material '%s' is metallic (%.2f)." % [material_name, standard.metallic])
			if TEACHER_N_ROUGHNESS.has(material_name):
				var expected := float(TEACHER_N_ROUGHNESS[material_name])
				if absf(standard.roughness - expected) > 0.01:
					_failures.append(
						"N's material '%s' has roughness %.2f; tools/prepare_teacher_n.py sets %.2f."
						% [material_name, standard.roughness, expected]
					)
	for expected_name: String in TEACHER_N_MATERIAL_NAMES:
		if not found.has(expected_name):
			_failures.append("N no longer imports the material '%s'." % expected_name)
	if found.size() != TEACHER_N_MATERIAL_NAMES.size():
		_failures.append(
			"N imports %d material(s) %s; the model has %d."
			% [found.size(), str(found.keys()), TEACHER_N_MATERIAL_NAMES.size()]
		)


# --- the wrapper -------------------------------------------------------------


func _check_wrapper(asset: Dictionary, holder: Node3D) -> void:
	var label := String(asset["name"])
	var path := String(asset["wrapper"])
	if not ResourceLoader.exists(path):
		_failures.append("The wrapper for %s is missing at %s." % [label, path])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("The wrapper for %s is not a scene." % label)
		return
	var wrapper := packed.instantiate() as Node3D
	if wrapper == null:
		_failures.append("The wrapper for %s cannot be instantiated as a Node3D." % label)
		return
	holder.add_child(wrapper)
	await process_frame
	await process_frame

	var instanced := false
	for node in _descendants(wrapper):
		if node.scene_file_path == String(asset["file"]):
			instanced = true
			break
	if not instanced:
		_failures.append("The wrapper for %s does not instance %s." % [label, String(asset["file"])])

	var shapes := _shape_nodes_under(wrapper)
	var kind := String(asset["kind"])
	match kind:
		"prop":
			_check_prop_wrapper(label, wrapper, shapes, asset)
		"character":
			_check_character_wrapper(label, wrapper, shapes, asset)
		"seated_character":
			_check_seated_wrapper(label, wrapper, shapes, asset)
		_:
			_check_decoration_wrapper(label, wrapper, shapes)

	# Whatever the kind, the wrapper's own origin sits on the object's base: that is the
	# one promise every consumer relies on. A seated character's base is the floor under
	# its chair, which `_check_seated_wrapper()` measures instead.
	var extent := _subtree_aabb(wrapper)
	if extent.size.y > 0.0 and kind != "seated_character":
		var base := extent.position.y - wrapper.global_position.y
		if absf(base) > WRAPPER_BASE_TOLERANCE:
			_failures.append(
				"The wrapper for %s puts the object's base at y=%.4f; the wrapper origin "
				% [label, base]
				+ "has to sit on the base so it can be dropped on a surface."
			)

	holder.remove_child(wrapper)
	wrapper.free()


func _check_prop_wrapper(
	label: String, wrapper: Node3D, shapes: Array[CollisionShape3D], asset: Dictionary
) -> void:
	var body := wrapper as StaticBody3D
	if body == null:
		_failures.append("The wrapper for %s is not a StaticBody3D." % label)
		return
	if not (body.collision_layer & 1):
		_failures.append(
			"The wrapper for %s is not on the world layer, so the navigation bake would ignore it."
			% label
		)
	if shapes.size() != 1:
		_failures.append(
			"The wrapper for %s has %d collision shape(s); one box per prop." % [label, shapes.size()]
		)
		return
	var shape_node := shapes[0]
	if shape_node.shape == null:
		_failures.append("The wrapper for %s has an empty collision shape." % label)
		return
	if shape_node.shape.get_class() != String(asset["shape"]):
		_failures.append(
			"The wrapper for %s uses a %s, the asset records a %s."
			% [label, shape_node.shape.get_class(), String(asset["shape"])]
		)
	var collision := _collision_bounds(shape_node)
	var visual: Vector3 = asset["size"]
	if absf(collision.size.y - visual.y) > SIZE_TOLERANCE:
		_failures.append(
			"The wrapper for %s collides %.4f m tall, the model is %.4f m tall."
			% [label, collision.size.y, visual.y]
		)
	for axis in [0, 2]:
		if absf(collision.size[axis] - visual[axis]) > SIZE_TOLERANCE:
			_failures.append(
				"The wrapper for %s collides %.4f m on axis %d, the model is %.4f m."
				% [label, collision.size[axis], axis, visual[axis]]
			)
	if collision.position.y < -WRAPPER_BASE_TOLERANCE:
		_failures.append(
			"The wrapper for %s puts collision %.4f m below the floor." % [label, collision.position.y]
		)


## A character wrapper is a visual, not a body: the asset reports no collision, and the
## controller that drives the character (CharacterBody3D, an NPC actor) owns its capsule.
## What the wrapper *does* supply is the interaction anchor, so nobody has to re-derive
## chest height for each character.
func _check_character_wrapper(
	label: String, wrapper: Node3D, shapes: Array[CollisionShape3D], asset: Dictionary
) -> void:
	if wrapper is StaticBody3D or wrapper is CharacterBody3D:
		_failures.append(
			"The wrapper for %s is a physics body; the character asset has no collision and "
			% label
			+ "the driving controller owns the capsule."
		)
	if not shapes.is_empty():
		_failures.append(
			"The wrapper for %s carries %d collision shape(s); a character visual must not."
			% [label, shapes.size()]
		)
	var anchor := wrapper.get_node_or_null(^"InteractionAnchor") as Marker3D
	if anchor == null:
		_failures.append("The wrapper for %s has no InteractionAnchor." % label)
	else:
		var expected := float(asset["anchor_height"])
		if absf(anchor.position.y - expected) > SIZE_TOLERANCE:
			_failures.append(
				"The interaction anchor for %s sits at y=%.4f, recorded at %.4f."
				% [label, anchor.position.y, expected]
			)
		if anchor.position.y > float((asset["size"] as Vector3).y):
			_failures.append(
				"The interaction anchor for %s is above the character's head." % label
			)
	if CHARACTER_LOOKS.has(label):
		_check_character_look(label, wrapper, asset)


## The protagonist's and Q's painted look: the wrapper carries its motion profile and a
## `Look` applier, and the applier repaints every surface of the GLB — none left in its
## smooth PBR material — with the painted shader, without touching what the model *is*:
## the same meshes, surfaces, vertex counts, skins and skeleton. The other two treatments
## (the GLB's own materials, the pigment shader) are reachable and reversible, because the
## character art capture photographs all three.
func _check_character_look(label: String, wrapper: Node3D, asset: Dictionary) -> void:
	var paths: Dictionary = CHARACTER_LOOKS[label]
	var animator := wrapper as CharacterVisualAnimation
	if animator == null:
		_failures.append("The wrapper for %s is not driven by CharacterVisualAnimation." % label)
	elif animator.motion_profile == null or animator.motion_profile.resource_path != String(paths["motion"]):
		_failures.append("The wrapper for %s does not carry its motion profile %s." % [label, String(paths["motion"])])
	var applier := wrapper.get_node_or_null(^"Look") as CharacterLookApplier
	if applier == null:
		_failures.append("The wrapper for %s has no Look applier." % label)
		return
	if applier.look == null or applier.look.resource_path != String(paths["look"]):
		_failures.append("The Look applier for %s does not use %s." % [label, String(paths["look"])])
		return
	var model := applier.get_model()
	if model == null or model.scene_file_path != String(asset["file"]):
		_failures.append("The Look applier for %s is not pointed at the GLB instance." % label)
		return
	var report := applier.get_report()
	var expected_surfaces := int(asset["surfaces"])
	if String(report.get("treatment", "")) != "PAINTED":
		_failures.append("%s starts in the %s treatment, not PAINTED." % [label, String(report.get("treatment", "?"))])
	if int(report.get("surfaces", 0)) != expected_surfaces or int(report.get("replaced", 0)) != expected_surfaces:
		_failures.append(
			"%s's look replaced %d of %d surfaces (the GLB has %d); kept %s."
			% [label, int(report.get("replaced", 0)), int(report.get("surfaces", 0)), expected_surfaces, str(report.get("kept", []))]
		)
	var meshes := _meshes_under(model)
	var outlined := 0
	for mesh_instance: MeshInstance3D in meshes:
		for index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_surface_override_material(index) as ShaderMaterial
			if material == null or material.shader == null or material.shader.resource_path != PAINT_SHADER_PATH:
				_failures.append(
					"%s's %s surface %d is not painted with %s." % [label, mesh_instance.name, index, PAINT_SHADER_PATH]
				)
				continue
			if material.next_pass != null:
				outlined += 1
	if outlined == 0 or outlined == expected_surfaces:
		_failures.append(
			"%s has %d of %d surfaces outlined; the ink line belongs on the outer forms only, not the eyes and mouth."
			% [label, outlined, expected_surfaces]
		)
	# The mesh a surface is drawn from may be the rest-coordinate rebuild; it is the same
	# geometry, skinned the same way.
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var bone_count := (skeletons[0] as Skeleton3D).get_bone_count() if not skeletons.is_empty() else -1
	var original_meshes := {}
	applier.apply_treatment(CharacterLookApplier.Treatment.ORIGINAL)
	for mesh_instance: MeshInstance3D in meshes:
		original_meshes[mesh_instance] = mesh_instance.mesh
		for index in mesh_instance.mesh.get_surface_count():
			if mesh_instance.get_surface_override_material(index) != null:
				_failures.append("%s's ORIGINAL treatment left an override on %s." % [label, mesh_instance.name])
			var authored := mesh_instance.get_active_material(index) as StandardMaterial3D
			if authored == null:
				_failures.append("%s's ORIGINAL treatment does not show the GLB's own material on %s." % [label, mesh_instance.name])
	applier.apply_treatment(CharacterLookApplier.Treatment.PIGMENT)
	for mesh_instance: MeshInstance3D in meshes:
		for index in mesh_instance.mesh.get_surface_count():
			var pigment := mesh_instance.get_surface_override_material(index) as ShaderMaterial
			if pigment == null or pigment.shader == null or pigment.shader.resource_path != PIGMENT_SHADER_PATH:
				_failures.append("%s's PIGMENT treatment did not use %s on %s." % [label, PIGMENT_SHADER_PATH, mesh_instance.name])
	var painted := applier.apply_treatment(CharacterLookApplier.Treatment.PAINTED)
	if int(painted.get("replaced", 0)) != expected_surfaces:
		_failures.append("%s did not come back to PAINTED on every surface." % label)
	var rebuilt := 0
	for mesh_instance: MeshInstance3D in meshes:
		var source: Mesh = original_meshes[mesh_instance]
		var mesh := mesh_instance.mesh
		if mesh != source:
			rebuilt += 1
			if mesh.get_surface_count() != source.get_surface_count():
				_failures.append("%s's rebuilt %s has %d surfaces, the GLB %d." % [label, mesh_instance.name, mesh.get_surface_count(), source.get_surface_count()])
				continue
			for index in source.get_surface_count():
				var before: Array = source.surface_get_arrays(index)
				var after: Array = mesh.surface_get_arrays(index)
				for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
					if before[slot] != after[slot]:
						_failures.append(
							"%s's rebuilt %s surface %d changed array %d; only CUSTOM0 may be added."
							% [label, mesh_instance.name, index, slot]
						)
				var custom: Variant = after[Mesh.ARRAY_CUSTOM0]
				var vertices: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
				if not (custom is PackedFloat32Array) or (custom as PackedFloat32Array).size() != vertices.size() * 4:
					_failures.append("%s's rebuilt %s surface %d carries no rest coordinates." % [label, mesh_instance.name, index])
		if mesh.get_aabb().size.distance_to(source.get_aabb().size) > 0.001:
			_failures.append("%s's %s changed size when it was painted." % [label, mesh_instance.name])
	if rebuilt == 0:
		_failures.append("%s's look rebuilt no mesh with rest-pose paint coordinates." % label)
	var after_bones := (skeletons[0] as Skeleton3D).get_bone_count() if not skeletons.is_empty() else -1
	if after_bones != bone_count or bone_count <= 0:
		_failures.append("%s's skeleton has %d bones after painting, %d before." % [label, after_bones, bone_count])
	if label == "protagonist":
		var expression: Dictionary = painted.get("expression", {})
		if expression.is_empty():
			_failures.append("The protagonist's painted look set no resting expression on the head's blend shapes.")


## A seated character is scenery that happens to be a person: the classroom student. It has
## no collision (like every character visual), no interaction anchor (nothing interacts with
## it), and its model hangs at the recorded seated drop so the clip it opens in, `sit_idle`,
## puts its soles on the floor the wrapper stands on.
func _check_seated_wrapper(
	label: String, wrapper: Node3D, shapes: Array[CollisionShape3D], asset: Dictionary
) -> void:
	if wrapper is PhysicsBody3D or not shapes.is_empty():
		_failures.append("The wrapper for %s collides; a seated student must not." % label)
	if wrapper.get_node_or_null(^"InteractionAnchor") != null:
		_failures.append("The wrapper for %s has an InteractionAnchor; nothing interacts with it." % label)
	var animator := wrapper as CharacterVisualAnimation
	if animator == null or not animator.start_seated:
		_failures.append("The wrapper for %s does not open seated." % label)
	var model := wrapper.get_node_or_null(^"Model") as Node3D
	if model == null:
		_failures.append("The wrapper for %s has no Model." % label)
	elif absf(model.position.y - float(asset["seated_drop"])) > BASE_TOLERANCE:
		_failures.append(
			"The wrapper for %s hangs its model at y=%.4f, recorded seated drop %.4f."
			% [label, model.position.y, float(asset["seated_drop"])]
		)


## Desk dressing does not collide on purpose: it sits on furniture that already does, and
## a 0.16 m prop with its own collider would carve a hole in the baked navigation mesh.
func _check_decoration_wrapper(
	label: String, wrapper: Node3D, shapes: Array[CollisionShape3D]
) -> void:
	if wrapper is StaticBody3D or wrapper is CharacterBody3D:
		_failures.append(
			"The wrapper for %s is a physics body, but the asset is decoration." % label
		)
	if not shapes.is_empty():
		_failures.append(
			"The wrapper for %s carries %d collision shape(s); decoration is placed on "
			% [label, shapes.size()]
			+ "furniture that already collides."
		)


# --- documents and the tree --------------------------------------------------


func _check_documents() -> void:
	var pipeline := _read(PIPELINE_DOC)
	var provenance := _read(PROVENANCE_DOC)
	if pipeline.is_empty():
		_failures.append("docs/ASSET_PIPELINE.md is missing: the contract has no home.")
	if provenance.is_empty():
		_failures.append("docs/ASSET_PROVENANCE.md is missing: the ledger has no home.")
	for asset: Dictionary in ASSETS:
		var model_relative := String(asset["file"]).trim_prefix("res://")
		var wrapper_relative := String(asset["wrapper"]).trim_prefix("res://")
		if not pipeline.contains(model_relative):
			_failures.append(
				"docs/ASSET_PIPELINE.md does not mention %s." % model_relative
			)
		if not provenance.contains(model_relative):
			_failures.append(
				"docs/ASSET_PROVENANCE.md has no entry for %s." % model_relative
			)
		if not provenance.contains(wrapper_relative):
			_failures.append(
				"docs/ASSET_PROVENANCE.md does not mention the wrapper %s." % wrapper_relative
			)
		_check_model_directory(asset)


## A runtime model is one `.glb` and nothing else. A stray `.bin`, a `textures/` folder or
## a `.blend` next to the model means the export was copied rather than converted. Two
## recorded models may share a directory (`protagonist/` holds the protagonist and the
## former protagonist); each one still brings only its `.glb` and `.import`.
func _check_model_directory(asset: Dictionary) -> void:
	var directory := String(asset["file"]).get_base_dir()
	var allowed: Array[String] = []
	for other: Dictionary in ASSETS:
		if String(other["file"]).get_base_dir() == directory:
			allowed.append(String(other["file"]).get_file())
			allowed.append(String(other["file"]).get_file() + ".import")
	var dir := DirAccess.open(directory)
	if dir == null:
		_failures.append("Cannot list %s." % directory)
		return
	for entry in dir.get_files():
		if not allowed.has(entry):
			_failures.append(
				"%s holds '%s'; a runtime model directory carries only the .glb and its .import."
				% [directory, entry]
			)


# --- helpers -----------------------------------------------------------------


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _descendants(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root_node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


func _meshes_under(root_node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in _descendants(root_node):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			found.append(mesh_instance)
	return found


func _shape_nodes_under(root_node: Node) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for node in _descendants(root_node):
		var shape_node := node as CollisionShape3D
		if shape_node != null:
			found.append(shape_node)
	return found


func _subtree_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## The box a collision shape covers, in the wrapper's own space, whatever shape it is.
func _collision_bounds(shape_node: CollisionShape3D) -> AABB:
	var shape := shape_node.shape
	if shape == null:
		return AABB()
	var size := Vector3.ZERO
	if shape is BoxShape3D:
		size = (shape as BoxShape3D).size
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		size = Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
	else:
		size = shape.get_debug_mesh().get_aabb().size
	return AABB(shape_node.position - size * 0.5, size)
