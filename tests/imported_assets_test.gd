extends SceneTree
## The imported production assets (round two): four GLBs that came from outside the
## repository — two Poly Haven CC0 props and the owner's two Blender characters —
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
## 1. the two characters face **+Z**, not the -Z the pipeline asks for, and the wrapper
##    does not hide it (a yaw baked into the wrapper would break the moment the GLB is
##    replaced) — see docs/ASSET_PIPELINE.md §10;
## 2. the stationery is a *display line-up* of nine separate items centred on its own
##    origin, so the wrapper re-origins it to its base;
## 3. no asset carries a non-unit node scale. `q.glb` used to be the one exception
##    (`Q_Collar`, 1 × 0.7 × 0.9, recorded here by name); the rigging re-export baked that
##    scale into the collar's vertices, which is what §1 asks for, so the record is empty
##    and the rule now holds for all four assets. A new scale still fails this test.
##
## What this does not test: how the assets look (that is the preview scene's job) or any
## performance budget.

const Harness = preload("res://tests/test_harness.gd")

const PIPELINE_DOC := "res://docs/ASSET_PIPELINE.md"
const PROVENANCE_DOC := "res://docs/ASSET_PROVENANCE.md"

## A model is authored to size: 2 cm is already a modelling error at this scale.
const SIZE_TOLERANCE := 0.02
## The origin's height, measured on the GLB itself, is what a placement method has to
## know about, so it is pinned tightly.
const BASE_TOLERANCE := 0.005
## Where every wrapper's own origin has to sit: on the object's base.
const WRAPPER_BASE_TOLERANCE := 0.02

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
		"file": "res://assets/models/protagonist/protagonist.glb",
		"wrapper": "res://scenes/environment/characters/protagonist.tscn",
		"size": Vector3(0.5559, 1.7269, 0.3370),
		"meshes": 78,
		"surfaces": 78,
		"model_base": 0.0170,
		"scaled_nodes": {},
		"kind": "character",
		"shape": "",
		"anchor_height": 1.2,
		"note": "the player's own expressionist character, rigid-weighted, no animation",
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
]

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
		"all four imported assets measure at their declared size and ship a wrapper that matches them."
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
	if String(asset["kind"]) == "character":
		_check_facing(label, meshes)

	holder.remove_child(instance)
	instance.free()


## The pipeline forbids a node scale other than 1. Two of the four assets honour it; the
## exception is named here so a *new* one cannot appear unnoticed.
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


## Both characters were authored facing +Z, which is the opposite of the pipeline's
## `-Z forward` rule. The wrapper does not correct it, so the fact is asserted instead:
## the eyes have to be in front, or every placement in the repository is suddenly a
## guess. See docs/ASSET_PIPELINE.md §10.
func _check_facing(label: String, meshes: Array[MeshInstance3D]) -> void:
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
				front = maxf(front, (mesh_instance.global_transform * vertex).z)
	if front == -INF:
		_failures.append("%s has no surface whose material is named for the iris." % label)
	elif front <= 0.0:
		_failures.append(
			"%s no longer faces +Z: its eyes reach z=%.4f. Update the facing note in "
			% [label, front]
			+ "docs/ASSET_PIPELINE.md §10 and every placement that relies on it."
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
		_:
			_check_decoration_wrapper(label, wrapper, shapes)

	# Whatever the kind, the wrapper's own origin sits on the object's base: that is the
	# one promise every consumer relies on.
	var extent := _subtree_aabb(wrapper)
	if extent.size.y > 0.0:
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
## a `.blend` next to the model means the export was copied rather than converted.
func _check_model_directory(asset: Dictionary) -> void:
	var directory := String(asset["file"]).get_base_dir()
	var model_file := String(asset["file"]).get_file()
	var allowed := [model_file, model_file + ".import"]
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
