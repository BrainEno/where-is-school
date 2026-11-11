extends SceneTree
## Validates the isolated painterly lab, transform/material boundaries, and explicit cleanup.
## GPU performance numbers remain a Windows manual run; CPU headless tests do not measure GPU time.

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
	var packed := (
		ResourceLoader.load(LAB_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		as PackedScene
	)
	if packed == null:
		_failures.append("The independent painterly lab scene could not be loaded.")
		await _finish("")
		return

	var packed_reference := weakref(packed)
	var lab: Node = packed.instantiate()
	if lab == null:
		_failures.append("The independent painterly lab scene could not be instantiated.")
		packed = null
		await _finish("")
		return
	root.add_child(lab)
	packed = null
	await process_frame

	var template_references := _capture_lab_template_references(lab)
	_check_camera(lab)
	_check_environment_tiers(lab)
	_check_character_treatment(lab)
	_check_transform_math(lab)
	await _check_outline_policy(lab)
	var migration_references := _check_material_migration(lab)
	_check_benchmark_geometry(lab)

	var lab_reference := weakref(lab)
	lab.queue_free()
	await process_frame
	await process_frame
	_expect(
		lab_reference.get_ref() == null,
		"The instantiated Painterly Lab scene survived queue_free()."
	)
	lab = null
	RenderingServer.force_sync()
	await process_frame
	_expect(
		packed_reference.get_ref() == null, "The temporary PackedScene reference was not released."
	)
	for resource_reference: WeakRef in migration_references:
		_expect(
			resource_reference.get_ref() == null,
			"A temporary material-migration resource survived cleanup."
		)
	for template_reference: WeakRef in template_references:
		_expect(
			template_reference.get_ref() == null,
			"A lab-owned material template survived freeing the lab instance."
		)
	migration_references.clear()
	template_references.clear()

	await _finish(
		(
			"world-space and normal-transform contracts, rotated/non-uniform/mirrored outline math, "
			+ "albedo/texture/UV migration boundaries, selective contours, explicit resource cleanup, "
			+ "and the fixed 144-instance benchmark. Windows visual/GPU measurements remain manual."
		)
	)


func _capture_lab_template_references(lab: Node) -> Array[WeakRef]:
	var references: Array[WeakRef] = []
	for property_name: String in [
		"_baseline_material",
		"_environment_fields",
		"_environment_inked",
		"_outline_material",
		"_character_pigment",
	]:
		var material := lab.get(property_name) as Resource
		_expect(material != null, "Lab-owned material template is missing: %s" % property_name)
		if material != null:
			references.append(weakref(material))
		material = null
	return references


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

	var environment_source := FileAccess.get_file_as_string(ENVIRONMENT_SHADER_PATH)
	var outline_source := FileAccess.get_file_as_string(OUTLINE_SHADER_PATH)
	var character_source := FileAccess.get_file_as_string(CHARACTER_SHADER_PATH)
	_expect(
		environment_source.contains("MODEL_MATRIX * vec4(VERTEX, 1.0)"),
		"Environment pigment coordinates are no longer derived from world-space position."
	)
	_expect(
		environment_source.contains("MODEL_NORMAL_MATRIX * NORMAL"),
		"Environment brush orientation is missing the model normal transform."
	)
	_expect(
		environment_source.contains("UV * base_uv_scale.xy + base_uv_offset.xy"),
		"Environment albedo sampling no longer applies the source UV1 scale and offset."
	)
	_expect(
		character_source.contains("UV * base_uv_scale.xy + base_uv_offset.xy"),
		"Character albedo sampling no longer applies the source UV1 scale and offset."
	)
	_expect(
		(
			outline_source.contains("MODEL_NORMAL_MATRIX")
			and outline_source.contains("transpose(model_normal_matrix) * world_normal")
		),
		"Outline displacement is not converted from a world-space normal offset."
	)
	_expect(
		not outline_source.contains("NORMAL * (line_width / normal_scale)"),
		"The scale-dependent local-normal outline formula is still present."
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

	_expect(
		bool(lab.call("_should_outline", inked_mesh)),
		"A coarse, sufficiently thick back wall should receive the contour pass."
	)
	for path: String in [
		"Samples/FieldsMarksContour/Floor",
		"Samples/FieldsMarksContour/DoorHandle",
		"Samples/FieldsMarksContour/Book",
		"Samples/FieldsMarksContour/DeskLegFrontLeft",
	]:
		var detail_mesh := lab.get_node_or_null(path) as MeshInstance3D
		_expect(detail_mesh != null, "Expected detail-geometry fixture is missing: %s" % path)
		if detail_mesh != null:
			_expect(
				not bool(lab.call("_should_outline", detail_mesh)),
				"Low-priority geometry should not receive a heavy contour: %s" % path
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


func _check_transform_math(lab: Node) -> void:
	var outline_material := lab.get("_outline_material") as ShaderMaterial
	_expect(outline_material != null, "The lab's outline material template is missing.")
	if outline_material == null:
		return
	var outline_line_width := float(outline_material.get_shader_parameter("line_width"))
	_expect(outline_line_width > 0.0, "The outline material has no positive extrusion width.")
	var rotation := Basis(Vector3(0.4, 0.7, -0.2).normalized(), deg_to_rad(37.0))
	var bases: Array[Basis] = [
		rotation * Basis.from_scale(Vector3(2.4, 0.45, 1.3)),
		rotation * Basis.from_scale(Vector3(-1.7, 0.55, 2.1)),
	]
	_expect(bases[0].determinant() > 0.0, "The positive-scale transform fixture is invalid.")
	_expect(bases[1].determinant() < 0.0, "The mirrored transform fixture is invalid.")

	var local_normals: Array[Vector3] = [
		Vector3.UP,
		Vector3.RIGHT,
		Vector3.FORWARD,
		Vector3(1.0, 2.0, -3.0).normalized(),
	]
	for basis: Basis in bases:
		var normal_matrix := basis.inverse().transposed()
		for local_normal: Vector3 in local_normals:
			var world_normal := (normal_matrix * local_normal).normalized()
			var helper_axis := (
				Vector3.UP if absf(local_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			)
			var tangent_a := local_normal.cross(helper_axis).normalized()
			var tangent_b := local_normal.cross(tangent_a).normalized()
			_expect(
				(
					absf(world_normal.dot(basis * tangent_a)) < 0.0001
					and absf(world_normal.dot(basis * tangent_b)) < 0.0001
				),
				"Inverse-transpose normal is not perpendicular to transformed tangents."
			)

			var local_offset := normal_matrix.transposed() * world_normal * outline_line_width
			var world_offset := basis * local_offset
			_expect(
				world_offset.is_equal_approx(world_normal * outline_line_width),
				"The inverted hull offset is not a constant world-space normal distance."
			)


func _check_outline_policy(lab: Node) -> void:
	var transformed_probe := MeshInstance3D.new()
	transformed_probe.name = "DeskTop"
	transformed_probe.mesh = BoxMesh.new()
	transformed_probe.rotation = Vector3(0.31, -0.42, 0.13)
	transformed_probe.scale = Vector3(-2.2, 0.12, 1.4)
	lab.add_child(transformed_probe)
	await process_frame
	_expect(
		bool(lab.call("_should_outline", transformed_probe)),
		"A rotated, mirrored, non-uniformly scaled thick panel should keep its outline."
	)

	var thin_probe := MeshInstance3D.new()
	thin_probe.name = "DeskTop"
	thin_probe.mesh = BoxMesh.new()
	thin_probe.rotation = Vector3(0.2, 0.4, -0.1)
	thin_probe.scale = Vector3(2.0, 0.015, 1.5)
	lab.add_child(thin_probe)
	await process_frame
	_expect(
		not bool(lab.call("_should_outline", thin_probe)),
		"A plate thinner than two world-space line widths should skip the contour pass."
	)

	var transformed_reference := weakref(transformed_probe)
	var thin_reference := weakref(thin_probe)
	transformed_probe.queue_free()
	thin_probe.queue_free()
	await process_frame
	_expect(transformed_reference.get_ref() == null, "The transformed outline probe was not freed.")
	_expect(thin_reference.get_ref() == null, "The thin outline probe was not freed.")


func _check_material_migration(lab: Node) -> Array[WeakRef]:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.55, 0.82, 1.0))
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = "Painterly material-migration fixture"
	var texture_reference := weakref(texture)

	var environment_shader := ResourceLoader.load(ENVIRONMENT_SHADER_PATH) as Shader
	var character_shader := ResourceLoader.load(CHARACTER_SHADER_PATH) as Shader
	var source := StandardMaterial3D.new()
	source.resource_name = "Painterly source material fixture"
	source.albedo_color = Color(0.18, 0.43, 0.76, 1.0)
	source.albedo_texture = texture
	source.uv1_scale = Vector3(2.25, 0.65, 1.0)
	source.uv1_offset = Vector3(0.17, -0.23, 0.0)

	var environment_destination := ShaderMaterial.new()
	environment_destination.shader = environment_shader
	var character_destination := ShaderMaterial.new()
	character_destination.shader = character_shader
	var source_reference := weakref(source)
	var environment_reference := weakref(environment_destination)
	var character_reference := weakref(character_destination)

	_expect(
		bool(lab.call("_copy_base_material", source, environment_destination)),
		"A supported opaque StandardMaterial3D albedo did not migrate to the environment shader."
	)
	_expect(
		bool(lab.call("_copy_base_material", source, character_destination)),
		"A supported opaque StandardMaterial3D albedo did not migrate to the character shader."
	)
	for destination: ShaderMaterial in [environment_destination, character_destination]:
		var migrated_color: Color = destination.get_shader_parameter("base_color")
		var migrated_texture: Texture2D = destination.get_shader_parameter("base_texture")
		var migrated_scale: Vector3 = destination.get_shader_parameter("base_uv_scale")
		var migrated_offset: Vector3 = destination.get_shader_parameter("base_uv_offset")
		_expect(
			migrated_color.is_equal_approx(source.albedo_color),
			"Source albedo color was not preserved by material migration."
		)
		_expect(
			(
				bool(destination.get_shader_parameter("use_base_texture"))
				and migrated_texture == texture
			),
			"Source albedo texture was not preserved by material migration."
		)
		_expect(
			migrated_scale.is_equal_approx(source.uv1_scale), "Source UV1 scale was not migrated."
		)
		_expect(
			migrated_offset.is_equal_approx(source.uv1_offset),
			"Source UV1 offset was not migrated."
		)
		migrated_texture = null

	var sentinel_color := Color(0.73, 0.21, 0.49, 1.0)
	var unsupported_destination := ShaderMaterial.new()
	unsupported_destination.shader = environment_shader
	unsupported_destination.set_shader_parameter("base_color", sentinel_color)
	unsupported_destination.set_shader_parameter("use_base_texture", false)
	var unsupported_shader_source := ShaderMaterial.new()
	unsupported_shader_source.shader = environment_shader
	unsupported_shader_source.resource_name = "Unsupported shader material fixture"
	var unsupported_source_reference := weakref(unsupported_shader_source)
	_expect(
		not bool(
			lab.call("_copy_base_material", unsupported_shader_source, unsupported_destination)
		),
		"A non-BaseMaterial3D source was silently accepted."
	)
	var unsupported_root := Node3D.new()
	unsupported_root.visible = false
	var unsupported_root_reference := weakref(unsupported_root)
	var unsupported_mesh := MeshInstance3D.new()
	unsupported_mesh.name = "UnsupportedMaterialProbe"
	var unsupported_mesh_reference := weakref(unsupported_mesh)
	unsupported_mesh.mesh = BoxMesh.new()
	unsupported_mesh.material_override = unsupported_shader_source
	unsupported_root.add_child(unsupported_mesh)
	lab.add_child(unsupported_root)
	var environment_template := (
		ResourceLoader.load("res://assets/shaders/painterly/environment_fields.tres")
		as ShaderMaterial
	)
	lab.call("_apply_environment_style", unsupported_root, environment_template, false)
	_expect(
		unsupported_mesh.material_override == unsupported_shader_source,
		"An unsupported source was replaced instead of remaining unchanged in the lab."
	)
	var unchanged_color: Color = unsupported_destination.get_shader_parameter("base_color")
	_expect(
		unchanged_color.is_equal_approx(sentinel_color),
		"Rejecting an unsupported source changed the destination's fallback color."
	)

	var second_surface_source := StandardMaterial3D.new()
	second_surface_source.resource_name = "Second painterly surface fixture"
	second_surface_source.albedo_color = Color(0.84, 0.26, 0.13, 1.0)
	var second_surface_reference := weakref(second_surface_source)
	var multi_surface_mesh := ArrayMesh.new()
	_add_triangle_surface(multi_surface_mesh, source)
	_add_triangle_surface(multi_surface_mesh, second_surface_source)
	var multi_surface_reference := weakref(multi_surface_mesh)
	var multi_surface_root := Node3D.new()
	multi_surface_root.visible = false
	var multi_surface_root_reference := weakref(multi_surface_root)
	var multi_surface_probe := MeshInstance3D.new()
	multi_surface_probe.name = "MultiSurfaceMaterialProbe"
	multi_surface_probe.mesh = multi_surface_mesh
	var multi_surface_probe_reference := weakref(multi_surface_probe)
	multi_surface_root.add_child(multi_surface_probe)
	lab.add_child(multi_surface_root)
	lab.call("_apply_environment_style", multi_surface_root, environment_template, false)
	_expect(
		multi_surface_probe.material_override == null,
		"Per-surface migration unexpectedly replaced a multi-surface mesh override."
	)
	var first_migrated_surface := multi_surface_probe.get_active_material(0) as ShaderMaterial
	var second_migrated_surface := multi_surface_probe.get_active_material(1) as ShaderMaterial
	_expect(first_migrated_surface != null, "The first source surface was not migrated separately.")
	_expect(
		second_migrated_surface != null, "The second source surface was not migrated separately."
	)
	var surface_material_references: Array[WeakRef] = []
	if first_migrated_surface != null and second_migrated_surface != null:
		surface_material_references.append(weakref(first_migrated_surface))
		surface_material_references.append(weakref(second_migrated_surface))
		var first_surface_color: Color = first_migrated_surface.get_shader_parameter("base_color")
		var second_surface_color: Color = second_migrated_surface.get_shader_parameter("base_color")
		_expect(
			first_surface_color.is_equal_approx(source.albedo_color),
			"The first source surface lost its independent color."
		)
		_expect(
			second_surface_color.is_equal_approx(second_surface_source.albedo_color),
			"The second source surface was collapsed to the first surface's color."
		)
		_expect(
			(
				bool(first_migrated_surface.get_shader_parameter("use_base_texture"))
				and not bool(second_migrated_surface.get_shader_parameter("use_base_texture"))
			),
			"Per-surface texture presence was not preserved independently."
		)
	first_migrated_surface = null
	second_migrated_surface = null

	var triplanar_source := StandardMaterial3D.new()
	triplanar_source.resource_name = "Unsupported triplanar fixture"
	triplanar_source.albedo_texture = texture
	triplanar_source.uv1_triplanar = true
	_expect(
		not bool(lab.call("_copy_base_material", triplanar_source, unsupported_destination)),
		"A triplanar source was silently converted to ordinary UV sampling."
	)

	var filtered_source := StandardMaterial3D.new()
	filtered_source.resource_name = "Unsupported texture-filter fixture"
	filtered_source.albedo_texture = texture
	filtered_source.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_expect(
		not bool(lab.call("_copy_base_material", filtered_source, unsupported_destination)),
		"A non-default source texture filter was silently replaced."
	)

	var vertex_color_source := StandardMaterial3D.new()
	vertex_color_source.resource_name = "Unsupported vertex-color fixture"
	vertex_color_source.vertex_color_use_as_albedo = true
	_expect(
		not bool(lab.call("_copy_base_material", vertex_color_source, unsupported_destination)),
		"Vertex-color albedo was silently dropped."
	)

	var transparent_source := StandardMaterial3D.new()
	transparent_source.resource_name = "Unsupported transparent fixture"
	transparent_source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_expect(
		not bool(lab.call("_copy_base_material", transparent_source, unsupported_destination)),
		"Transparent albedo was silently treated as opaque."
	)

	var unsupported_reference := weakref(unsupported_destination)
	source.albedo_texture = null
	triplanar_source.albedo_texture = null
	filtered_source.albedo_texture = null
	environment_destination.set_shader_parameter("base_texture", null)
	character_destination.set_shader_parameter("base_texture", null)
	environment_destination.set_shader_parameter("use_base_texture", false)
	character_destination.set_shader_parameter("use_base_texture", false)
	image = null
	texture = null
	source = null
	environment_destination = null
	character_destination = null
	unsupported_destination = null
	unsupported_shader_source = null
	triplanar_source = null
	filtered_source = null
	vertex_color_source = null
	transparent_source = null
	unsupported_root = null
	unsupported_mesh = null
	second_surface_source = null
	multi_surface_mesh = null
	multi_surface_root = null
	multi_surface_probe = null
	environment_template = null
	environment_shader = null
	character_shader = null

	var references: Array[WeakRef] = [
		texture_reference,
		source_reference,
		environment_reference,
		character_reference,
		unsupported_reference,
		unsupported_source_reference,
		unsupported_root_reference,
		unsupported_mesh_reference,
		second_surface_reference,
		multi_surface_reference,
		multi_surface_root_reference,
		multi_surface_probe_reference,
	]
	references.append_array(surface_material_references)
	return references


func _add_triangle_surface(mesh: ArrayMesh, material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3.ZERO, Vector3.RIGHT, Vector3(0.0, 1.0, 0.0)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0)]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[Vector2.ZERO, Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


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


func _finish(success_message: String) -> void:
	var watchdog := root.get_node_or_null(^"TestWatchdog") as Timer
	if watchdog != null:
		watchdog.stop()
		watchdog.queue_free()
		await process_frame
	Harness.finish(self, _failures, success_message)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
