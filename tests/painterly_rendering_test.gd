extends SceneTree
## Validates the isolated painterly lab, its separate environment/character materials,
## and its fixed-geometry benchmark. GPU performance numbers are deliberately a Windows
## manual run: headless rendering cannot produce representative frame-time measurements.

const Harness = preload("res://tests/test_harness.gd")

const LAB_SCENE_PATH := "res://scenes/dev/painterly_lab/painterly_lab.tscn"
const ENVIRONMENT_SHADER_PATH := "res://assets/shaders/painterly/environment_surface.gdshader"
const OUTLINE_SHADER_PATH := "res://assets/shaders/painterly/environment_outline.gdshader"
const CHARACTER_SHADER_PATH := "res://assets/shaders/painterly/character_pigment.gdshader"
const BENCHMARK_INSTANCE_COUNT := 144

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 90.0, "painterly_rendering_test.gd")
	call_deferred("_run")


func _run() -> void:
	_check_shader_files()
	var packed := load(LAB_SCENE_PATH) as PackedScene
	if packed == null:
		_failures.append("The independent painterly lab scene could not be loaded.")
		Harness.finish(self, _failures, "")
		return

	var lab := packed.instantiate()
	root.add_child(lab)
	await process_frame
	_check_camera(lab)
	_check_environment_tiers(lab)
	_check_character_treatment(lab)
	_check_benchmark_geometry(lab)
	lab.queue_free()
	await process_frame
	Harness.finish(
		self,
		_failures,
		(
			"the standalone preview has separate environment/character treatments and a fixed "
			+ "144-instance three-tier material benchmark. Windows GPU measurements remain manual."
		)
	)


func _check_shader_files() -> void:
	for path: String in [ENVIRONMENT_SHADER_PATH, OUTLINE_SHADER_PATH, CHARACTER_SHADER_PATH]:
		_expect(ResourceLoader.exists(path), "Missing painterly shader resource: %s" % path)
		_expect(FileAccess.file_exists(path), "Missing painterly shader source: %s" % path)
	_expect(
		ResourceLoader.exists("res://assets/shaders/painterly/environment_fields.tres"),
		"The medium-complexity environment preset is missing."
	)
	_expect(
		ResourceLoader.exists("res://assets/shaders/painterly/environment_inked.tres"),
		"The high-complexity environment preset is missing."
	)
	_expect(
		ResourceLoader.exists("res://assets/shaders/painterly/character_pigment.tres"),
		"The character-specific material preset is missing."
	)


func _check_camera(lab: Node) -> void:
	var camera := lab.get_node_or_null("Camera3D") as Camera3D
	_expect(camera != null, "The lab has no local preview camera.")
	if camera == null:
		return
	_expect(
		camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"The preview camera is not perspective."
	)
	_expect(
		is_equal_approx(camera.fov, 60.0),
		"The preview camera FOV is not the current 60-degree baseline."
	)
	_expect(camera.current, "The lab camera is not current.")


func _check_environment_tiers(lab: Node) -> void:
	var standard_mesh := lab.get_node_or_null("Samples/Standard/BackWall") as MeshInstance3D
	var field_mesh := lab.get_node_or_null("Samples/ColorFields/BackWall") as MeshInstance3D
	var inked_mesh := lab.get_node_or_null("Samples/FieldsMarksContour/BackWall") as MeshInstance3D
	_expect(standard_mesh != null, "The standard environment sample is missing its wall.")
	_expect(field_mesh != null, "The color-field environment sample is missing its wall.")
	_expect(inked_mesh != null, "The marked environment sample is missing its wall.")
	if standard_mesh == null or field_mesh == null or inked_mesh == null:
		return

	var standard_material := standard_mesh.get_active_material(0)
	var field_material := field_mesh.get_active_material(0) as ShaderMaterial
	var inked_material := inked_mesh.get_active_material(0) as ShaderMaterial
	_expect(
		standard_material is StandardMaterial3D,
		"The environment baseline is not a plain StandardMaterial3D."
	)
	_expect(field_material != null, "The color-field tier did not receive a ShaderMaterial.")
	_expect(inked_material != null, "The high-complexity tier did not receive a ShaderMaterial.")
	if field_material == null or inked_material == null:
		return

	_expect(
		field_material.shader.resource_path == ENVIRONMENT_SHADER_PATH,
		"The color-field tier is not using the environment shader."
	)
	_expect(
		inked_material.shader.resource_path == ENVIRONMENT_SHADER_PATH,
		"The marked tier is not using the environment shader."
	)
	_expect(
		int(field_material.get_shader_parameter("style_level")) == 1,
		"The medium environment tier should only enable broad color fields."
	)
	_expect(
		int(inked_material.get_shader_parameter("style_level")) == 2,
		"The high environment tier should enable fields and limited brush marks."
	)
	var standard_base := standard_material as BaseMaterial3D
	if standard_base != null:
		var preserved_color: Color = field_material.get_shader_parameter("base_color")
		_expect(
			preserved_color.is_equal_approx(standard_base.albedo_color),
			"The environment shader did not preserve the source material color."
		)
	var outline := inked_material.next_pass as ShaderMaterial
	_expect(outline != null, "The high environment tier has no geometry-outline pass.")
	if outline != null:
		_expect(
			outline.shader.resource_path == OUTLINE_SHADER_PATH,
			"The high environment tier has the wrong outline shader."
		)
	var floor_mesh := lab.get_node_or_null("Samples/FieldsMarksContour/Floor") as MeshInstance3D
	if floor_mesh != null:
		var floor_material := floor_mesh.get_active_material(0) as ShaderMaterial
		_expect(
			floor_material != null and floor_material.next_pass == null,
			"The floor should keep the broad painterly field but skip the silhouette pass."
		)
	var detail_mesh := (
		lab.get_node_or_null("Samples/FieldsMarksContour/DeskLegFrontLeft") as MeshInstance3D
	)
	if detail_mesh != null:
		var detail_material := detail_mesh.get_active_material(0) as ShaderMaterial
		_expect(
			detail_material != null and detail_material.next_pass == null,
			"Small desk legs should stay quiet rather than receive a heavy contour."
		)


func _check_character_treatment(lab: Node) -> void:
	var authored_root := lab.get_node_or_null("Characters/AuthoredPalette")
	var pigment_root := lab.get_node_or_null("Characters/CharacterPigment")
	_expect(authored_root != null, "The imported authored-palette character is missing.")
	_expect(pigment_root != null, "The separate character shader sample is missing.")
	if authored_root == null or pigment_root == null:
		return

	var authored_mesh := _find_first_mesh(authored_root)
	var pigment_mesh := _find_first_mesh(pigment_root)
	_expect(authored_mesh != null, "The authored character model contains no mesh surface.")
	_expect(pigment_mesh != null, "The pigment character model contains no mesh surface.")
	if authored_mesh == null or pigment_mesh == null:
		return

	var authored_material := authored_mesh.get_active_material(0) as BaseMaterial3D
	var pigment_material := pigment_mesh.get_active_material(0) as ShaderMaterial
	_expect(authored_material != null, "The GLB character has no source color material to compare.")
	_expect(pigment_material != null, "The character-specific ShaderMaterial was not applied.")
	if authored_material == null or pigment_material == null:
		return
	_expect(
		pigment_material.shader.resource_path == CHARACTER_SHADER_PATH,
		"The character uses the environment shader instead of its separate pigment shader."
	)
	_expect(
		pigment_material.next_pass == null,
		"The character shader must not inherit the environment outline."
	)
	var preserved_color: Color = pigment_material.get_shader_parameter("base_color")
	_expect(
		preserved_color.is_equal_approx(authored_material.albedo_color),
		"The character shader did not preserve the imported surface color."
	)


func _check_benchmark_geometry(lab: Node) -> void:
	var batch := lab.get_node_or_null("Benchmark/StressBatch") as MultiMeshInstance3D
	_expect(batch != null, "The material-complexity benchmark batch is missing.")
	if batch == null:
		return
	_expect(batch.multimesh != null, "The benchmark MultiMesh was not constructed.")
	if batch.multimesh == null:
		return
	_expect(
		batch.multimesh.instance_count == BENCHMARK_INSTANCE_COUNT,
		(
			"Expected %d benchmark instances, got %d."
			% [BENCHMARK_INSTANCE_COUNT, batch.multimesh.instance_count]
		)
	)

	var previous_material: Material = null
	for variant in range(3):
		var accepted := bool(lab.call("set_benchmark_variant", variant))
		_expect(accepted, "Benchmark tier %d was rejected." % variant)
		_expect(
			batch.multimesh.instance_count == BENCHMARK_INSTANCE_COUNT,
			"Changing material tier %d changed the fixed benchmark geometry count." % variant
		)
		var material := batch.material_override
		_expect(material != null, "Benchmark tier %d has no material." % variant)
		if material == null:
			continue
		if previous_material != null:
			_expect(
				material != previous_material, "Two benchmark tiers use the same material resource."
			)
		if variant == 0:
			_expect(material is StandardMaterial3D, "Benchmark tier 1 is not standard shading.")
		else:
			var shader_material := material as ShaderMaterial
			_expect(
				shader_material != null,
				"Painterly benchmark tier %d is not a ShaderMaterial." % variant
			)
			if shader_material != null:
				_expect(
					shader_material.shader.resource_path == ENVIRONMENT_SHADER_PATH,
					"Painterly benchmark tier %d uses the wrong shader." % variant
				)
				_expect(
					int(shader_material.get_shader_parameter("style_level")) == variant,
					"Painterly benchmark tier %d has the wrong style level." % variant
				)
				_expect(
					(shader_material.next_pass != null) == (variant == 2),
					"Only the highest benchmark tier should add a contour pass."
				)
		previous_material = material
	_expect(
		not bool(lab.call("set_benchmark_variant", 3)),
		"An invalid fourth benchmark tier was accepted."
	)


func _find_first_mesh(root_node: Node) -> MeshInstance3D:
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				return mesh_instance
		for child: Node in current.get_children():
			pending.push_back(child)
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
