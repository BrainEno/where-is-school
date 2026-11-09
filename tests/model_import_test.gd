extends SceneTree
## The imported-model contract, measured on the two samples the repository ships.
##
## `docs/ASSET_PIPELINE.md` is a promise about files that come from outside the
## engine: one metre is one metre, the origin is on the floor between the feet, the
## model faces -Z, nothing carries a stray scale, and the collision that goes with it
## is declared in a wrapper scene the generator cannot overwrite. A promise nobody
## runs is a wish, so this test imports both `.glb` samples and measures them:
##
## 1. each file imports as a scene at all — a model that fails to import is invisible
##    in Godot and there is no error until someone drags it into a room;
## 2. the measured bounding box matches the size the pipeline declares, and the two
##    things the contract is really about (floor at y = 0, centred on x and z) are
##    within a centimetre — this is where a centimetre-vs-metre export dies;
## 3. no node in the imported scene carries a scale other than 1 — the other half of
##    the same export mistake, and the one that survives a size check;
## 4. the wrapper scene supplies exactly one collision shape, on the world layer the
##    navigation bake reads, tall enough to cover the model it wraps;
## 5. the one placed instance in the slice stands on the courtyard floor, on walkable
##    ground, and is still there because the *generator table* asks for it — the
##    wrapper itself lives outside `scenes/locations/`, so regenerating cannot delete
##    it.
##
## What this does not test: how the models look, whether whoever authored the next one
## followed the export settings, or any performance budget (that needs the target
## machine).

const Harness = preload("res://tests/test_harness.gd")

const MODELS := "res://assets/models/sample/"
const CHAIR_WRAPPER := "res://scenes/environment/props/sample_chair.tscn"
const FIGURE_WRAPPER := "res://scenes/environment/characters/sample_figure.tscn"
const RESIDENTIAL := "res://scenes/locations/residential/residential.tscn"
const GENERATOR := "res://tools/build_outdoor_locations.py"
const PIPELINE_DOC := "res://docs/ASSET_PIPELINE.md"
const PROVENANCE_DOC := "res://docs/ASSET_PROVENANCE.md"

## What the shipped samples claim to be, in metres. Changing a sample means changing
## this table and the contract document in the same commit.
const SAMPLES: Array[Dictionary] = [
	{
		"file": "chair.glb",
		"size": Vector3(0.52, 0.92, 0.52),
		"wrapper": CHAIR_WRAPPER,
		"shape": "BoxShape3D",
		"note": "a chair standing on the courtyard floor",
	},
	{
		"file": "figure.glb",
		"size": Vector3(0.60, 1.72, 0.26),
		"wrapper": FIGURE_WRAPPER,
		"shape": "CapsuleShape3D",
		"note": "a person-sized figure, 1.72 m to the crown",
	},
]

## A model is authored to size, so the box it declares has to match it: 2 cm is
## already a modelling error at this scale, not a rounding difference.
const SIZE_TOLERANCE := 0.02
## The origin has to sit on the floor and on the model's own centre line.
const ORIGIN_TOLERANCE := 0.01

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "model_import_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	L10n.load_tables()
	for sample: Dictionary in SAMPLES:
		_check_imported_model(sample)
		_check_wrapper(sample)
	await _check_placement()
	_check_documents()
	Harness.finish(
		self, _failures,
		"both sample models import at the declared size, and the wrappers carry matching collision."
	)


# --- 1-3: the model ----------------------------------------------------------


func _check_imported_model(sample: Dictionary) -> void:
	var path: String = MODELS + String(sample["file"])
	var label := String(sample["file"])
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

	var meshes := _meshes_under(instance)
	if meshes.is_empty():
		_failures.append("%s imported without a mesh, so nothing would be drawn." % label)
		instance.free()
		return

	var bounds := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in meshes:
		var box: AABB = mesh_instance.get_aabb()
		box.position += mesh_instance.position
		bounds = box if first else bounds.merge(box)
		first = false
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			_failures.append("%s has a mesh instance with no surface." % label)
		elif mesh_instance.get_active_material(0) == null:
			_failures.append("%s has a surface with no material, so it would render untextured." % label)

	var expected: Vector3 = sample["size"]
	for axis in 3:
		var measured: float = bounds.size[axis]
		if absf(measured - expected[axis]) > SIZE_TOLERANCE:
			_failures.append(
				"%s measures %.3f m on axis %d, the pipeline declares %.3f m (%s)."
				% [label, measured, axis, expected[axis], String(sample["note"])]
			)
	# The origin: on the floor, and on the model's own centre line.
	if absf(bounds.position.y) > ORIGIN_TOLERANCE:
		_failures.append(
			"%s has its origin %.3f m off the floor; the contract puts it at the feet."
			% [label, bounds.position.y]
		)
	for axis in [0, 2]:
		var centre: float = bounds.position[axis] + bounds.size[axis] * 0.5
		if absf(centre) > ORIGIN_TOLERANCE:
			_failures.append(
				"%s is %.3f m off centre on axis %d; the contract centres the model on its origin."
				% [label, centre, axis]
			)

	# A centimetre-scale export looks correct until it is placed next to a door.
	for node in _descendants(instance):
		var spatial := node as Node3D
		if spatial == null:
			continue
		if not spatial.scale.is_equal_approx(Vector3.ONE):
			_failures.append(
				"%s imports with scale %s on node '%s'; scale belongs in the model, not in the scene."
				% [label, str(spatial.scale), spatial.name]
			)
	instance.free()


# --- 4: the wrapper ----------------------------------------------------------


func _check_wrapper(sample: Dictionary) -> void:
	var path: String = sample["wrapper"]
	var label := String(sample["file"])
	if not ResourceLoader.exists(path):
		_failures.append("The wrapper for %s is missing at %s." % [label, path])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("The wrapper for %s is not a scene." % label)
		return
	var wrapper := packed.instantiate()
	if wrapper == null:
		_failures.append("The wrapper for %s cannot be instantiated." % label)
		return

	var body := wrapper as StaticBody3D
	if body == null:
		_failures.append("The wrapper for %s is not a StaticBody3D." % label)
		wrapper.free()
		return
	if not (body.collision_layer & 1):
		_failures.append(
			"The wrapper for %s is not on the world layer, so the navigation bake would ignore it."
			% label
		)
	if not _wraps_model(wrapper, sample):
		_failures.append("The wrapper for %s does not instance %s." % [label, String(sample["file"])])

	var shapes := _shape_nodes_under(wrapper)
	if shapes.size() != 1:
		_failures.append(
			"The wrapper for %s has %d collision shape(s); one box or capsule per prop."
			% [label, shapes.size()]
		)
		wrapper.free()
		return
	var shape_node: CollisionShape3D = shapes[0]
	var shape_name := "<none>"
	if shape_node.shape != null:
		shape_name = shape_node.shape.get_class()
	if shape_name != String(sample["shape"]):
		_failures.append(
			"The wrapper for %s uses a %s, the pipeline declares a %s."
			% [label, shape_name, String(sample["shape"])]
		)
	# The collision has to cover the model, or the player walks through the top of it.
	var collision := _collision_bounds(shape_node)
	var visual: Vector3 = sample["size"]
	if absf(collision.size.y - visual.y) > SIZE_TOLERANCE:
		_failures.append(
			"The wrapper for %s collides %.3f m tall, the model is %.3f m tall."
			% [label, collision.size.y, visual.y]
		)
	if collision.position.y < -ORIGIN_TOLERANCE:
		_failures.append(
			"The wrapper for %s puts collision %.3f m below the floor." % [label, collision.position.y]
		)
	wrapper.free()


# --- 5: the one placed instance ---------------------------------------------


func _check_placement() -> void:
	var packed := load(RESIDENTIAL) as PackedScene
	if packed == null:
		_failures.append("The residential location could not be loaded.")
		return
	var location := packed.instantiate() as LocationRoot
	if location == null:
		_failures.append("The residential location could not be instantiated as a LocationRoot.")
		return
	root.add_child(location)

	var chair: Node3D = null
	for node in _descendants(location):
		if node.name == &"SampleChair":
			chair = node as Node3D
			break
	if chair == null:
		_failures.append(
			"The generated courtyard no longer places the sample chair; the generator table lost it."
		)
		root.remove_child(location)
		location.free()
		return
	if chair.scene_file_path != CHAIR_WRAPPER:
		_failures.append(
			"The placed chair is '%s', not the wrapper '%s'."
			% [chair.scene_file_path, CHAIR_WRAPPER]
		)
	if absf(chair.position.y) > ORIGIN_TOLERANCE:
		_failures.append("The chair stands %.3f m off the courtyard floor." % chair.position.y)
	if not chair.scale.is_equal_approx(Vector3.ONE):
		_failures.append("The placed chair carries a scale: %s." % str(chair.scale))

	# Walkable ground: the chair carves a hole in the mesh the size of the agent plus its
	# own footprint, so "the chair's centre is on the mesh" is the wrong question. What
	# matters is that it stands on the courtyard's floor and has not cut the space in two.
	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("The courtyard has no Navigation region for the chair to sit on.")
	elif not await _wait_for_bake(nav):
		_failures.append(
			"The courtyard never baked a mesh with the chair in it (%s)." % nav.get_bake_error()
		)
	else:
		var map := nav.get_navigation_map()
		var closest := NavigationServer3D.map_get_closest_point(map, chair.global_position)
		var away := Vector2(
			closest.x - chair.global_position.x, closest.z - chair.global_position.z
		).length()
		if away > 1.0:
			_failures.append(
				"The chair stands %.2f m from the nearest walkable point; it is not on the courtyard's ground."
				% away
			)
		var from_spawn := location.get_spawn(&"FromStreet")
		var to_exit := _find_node(location, &"AlleyEnd")
		if from_spawn != null and to_exit != null:
			var route := NavigationServer3D.map_get_path(
				map,
				NavigationServer3D.map_get_closest_point(map, from_spawn.global_position),
				NavigationServer3D.map_get_closest_point(map, to_exit.global_position),
				true
			)
			if route.size() < 2:
				_failures.append(
					"With the chair placed, the courtyard is cut in two: no route from FromStreet to the alley."
				)
	root.remove_child(location)
	location.free()


# --- the table, not the artefact --------------------------------------------


func _check_documents() -> void:
	var script := _read(GENERATOR)
	if script.is_empty():
		_failures.append("The location generator could not be read.")
	else:
		if not script.contains(CHAIR_WRAPPER):
			_failures.append(
				"The generator does not name %s, so a regeneration would drop the chair." % CHAIR_WRAPPER
			)
		for line: String in script.split("\n"):
			if line.contains("write(") and (
				line.contains("sample_chair") or line.contains("sample_figure")
			):
				_failures.append(
					"The generator writes a model wrapper; wrappers have to live outside scenes/locations."
				)
	var pipeline := _read(PIPELINE_DOC)
	if pipeline.is_empty():
		_failures.append("docs/ASSET_PIPELINE.md is missing: the contract has no home.")
	else:
		for sample: Dictionary in SAMPLES:
			if not pipeline.contains(String(sample["file"])):
				_failures.append(
					"docs/ASSET_PIPELINE.md does not mention %s." % String(sample["file"])
				)
	var provenance := _read(PROVENANCE_DOC)
	for sample: Dictionary in SAMPLES:
		if not provenance.contains(String(sample["file"])):
			_failures.append(
				"docs/ASSET_PROVENANCE.md has no entry for %s." % String(sample["file"])
			)


# --- helpers ----------------------------------------------------------------


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


func _find_node(root_node: Node, wanted: StringName) -> Node3D:
	for node in _descendants(root_node):
		if node.name == wanted:
			return node as Node3D
	return null


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


func _wraps_model(wrapper: Node, sample: Dictionary) -> bool:
	for node in _descendants(wrapper):
		if node.scene_file_path.ends_with(String(sample["file"])):
			return true
	return false


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
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		size = Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	elif shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		size = Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
	else:
		size = shape.get_debug_mesh().get_aabb().size
	return AABB(shape_node.position - size * 0.5, size)


func _wait_for_bake(nav: LocationNavigation) -> bool:
	var budget := 0
	while budget < 120:
		if nav.is_baked():
			return true
		await physics_frame
		budget += 1
	return false
