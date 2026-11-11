extends Node3D
## Standalone material study. It intentionally does not instance the production classroom,
## navigation, player, or CameraRig; the local perspective camera stays at the current 60° FOV.

const BASELINE_MATERIAL_PATH := "res://assets/shaders/painterly/environment_baseline.tres"
const ENVIRONMENT_FIELDS_PATH := "res://assets/shaders/painterly/environment_fields.tres"
const ENVIRONMENT_INKED_PATH := "res://assets/shaders/painterly/environment_inked.tres"
const OUTLINE_MATERIAL_PATH := "res://assets/shaders/painterly/environment_outline.tres"
const CHARACTER_PIGMENT_PATH := "res://assets/shaders/painterly/character_pigment.tres"
const BENCHMARK_INSTANCE_COUNT: int = 144
const BENCHMARK_GRID_WIDTH: int = 12
const BENCHMARK_WARMUP_SECONDS: float = 1.0
const BENCHMARK_SAMPLE_SECONDS: float = 3.0
const BENCHMARK_NAMES: Array[String] = ["Standard", "Color fields", "Marks + contour"]
const OUTLINE_CANDIDATE_NODE_NAMES: Array[String] = [
	"BackWall", "SideWall", "DoorFrame", "DoorPanel", "DeskTop", "PlantPot", "PlantCrown"
]
const OUTLINE_MINIMUM_THICKNESS_RATIO: float = 2.0

var _baseline_material: StandardMaterial3D
var _environment_fields: ShaderMaterial
var _environment_inked: ShaderMaterial
var _outline_material: ShaderMaterial
var _character_pigment: ShaderMaterial

var _benchmark_view: bool = false
var _benchmark_running: bool = false
var _selected_benchmark_variant: int = 0
var _hud_clock: float = 0.0
var _sampling: bool = false
var _sample_frames: int = 0
var _sample_elapsed: float = 0.0
var _sample_process_ms: float = 0.0
var _sample_draw_calls: float = 0.0
var _sample_primitives: float = 0.0
var _restore_window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var _restore_window_size: Vector2i = Vector2i(1600, 900)

@onready var _camera: Camera3D = $Camera3D
@onready var _samples: Node3D = $Samples
@onready var _characters: Node3D = $Characters
@onready var _benchmark: Node3D = $Benchmark
@onready var _stress_batch: MultiMeshInstance3D = $Benchmark/StressBatch
@onready var _stats_label: Label = $HUD/Panel/Stats


func _ready() -> void:
	_restore_window_mode = DisplayServer.window_get_mode()
	_restore_window_size = DisplayServer.window_get_size()
	if not _load_material_templates():
		push_error("Painterly Lab: a required preview material could not be loaded.")
		return
	_apply_environment_style($Samples/ColorFields, _environment_fields, false)
	_apply_environment_style($Samples/FieldsMarksContour, _environment_inked, true)
	_apply_character_style($Characters/CharacterPigment)
	_build_stress_batch()
	set_benchmark_variant(0)
	_camera.look_at(Vector3(1.8, 1.2, 0.0), Vector3.UP)
	_update_hud()


func _load_material_templates() -> bool:
	_baseline_material = load(BASELINE_MATERIAL_PATH) as StandardMaterial3D
	_environment_fields = load(ENVIRONMENT_FIELDS_PATH) as ShaderMaterial
	_environment_inked = load(ENVIRONMENT_INKED_PATH) as ShaderMaterial
	_outline_material = load(OUTLINE_MATERIAL_PATH) as ShaderMaterial
	_character_pigment = load(CHARACTER_PIGMENT_PATH) as ShaderMaterial
	return (
		_baseline_material != null
		and _environment_fields != null
		and _environment_inked != null
		and _outline_material != null
		and _character_pigment != null
	)


func _process(delta: float) -> void:
	if _sampling:
		_sample_frames += 1
		_sample_elapsed += delta
		_sample_process_ms += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		_sample_draw_calls += float(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		)
		_sample_primitives += float(
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		)

	_hud_clock += delta
	if _hud_clock >= 0.25:
		_hud_clock = 0.0
		_update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or _benchmark_running:
		return

	match key_event.keycode:
		KEY_B:
			_set_benchmark_view(not _benchmark_view)
		KEY_F11:
			_toggle_fullscreen()
		KEY_1:
			if _benchmark_view:
				set_benchmark_variant(0)
		KEY_2:
			if _benchmark_view:
				set_benchmark_variant(1)
		KEY_3:
			if _benchmark_view:
				set_benchmark_variant(2)
		KEY_ENTER:
			if _benchmark_view:
				run_benchmark()


func _toggle_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(_restore_window_mode)
		if _restore_window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(_restore_window_size)
		return

	_restore_window_mode = current_mode
	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		_restore_window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Public so the headless test can confirm a fixed mesh/instance count across tiers.
func set_benchmark_variant(variant: int) -> bool:
	if variant < 0 or variant >= BENCHMARK_NAMES.size():
		return false
	_selected_benchmark_variant = variant
	if _stress_batch != null:
		_stress_batch.material_override = _benchmark_material(variant)
	return true


## Runs a warm-up and sample for each material on the same 144-instance MultiMesh.
## The reported frame time is end-to-end; TIME_PROCESS is CPU-side engine process time,
## not a GPU timer. VSync is disabled only during samples and restored afterward.
func run_benchmark() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	_set_benchmark_view(true)
	var previous_vsync_mode := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results: Array[Dictionary] = []

	for variant in range(BENCHMARK_NAMES.size()):
		set_benchmark_variant(variant)
		await get_tree().create_timer(BENCHMARK_WARMUP_SECONDS).timeout
		_sample_frames = 0
		_sample_elapsed = 0.0
		_sample_process_ms = 0.0
		_sample_draw_calls = 0.0
		_sample_primitives = 0.0
		_sampling = true
		await get_tree().create_timer(BENCHMARK_SAMPLE_SECONDS).timeout
		_sampling = false

		var safe_frames := maxi(_sample_frames, 1)
		var average_fps := float(_sample_frames) / maxf(_sample_elapsed, 0.001)
		var window_size := DisplayServer.window_get_size()
		var result := {
			"tier": BENCHMARK_NAMES[variant],
			"window_width": window_size.x,
			"window_height": window_size.y,
			"vsync": "disabled_during_benchmark",
			"instances": BENCHMARK_INSTANCE_COUNT,
			"frames": _sample_frames,
			"average_fps": snappedf(average_fps, 0.01),
			"average_frame_ms": snappedf(1000.0 / maxf(average_fps, 0.001), 0.01),
			"average_process_ms": snappedf(_sample_process_ms / float(safe_frames), 0.01),
			"average_draw_calls": snappedf(_sample_draw_calls / float(safe_frames), 0.01),
			"average_primitives": snappedf(_sample_primitives / float(safe_frames), 0.01),
		}
		results.append(result)
		print("PAINTERLY_BENCHMARK %s" % JSON.stringify(result))

	print("PAINTERLY_BENCHMARK_SUMMARY %s" % JSON.stringify(results))
	DisplayServer.window_set_vsync_mode(previous_vsync_mode)
	_benchmark_running = false
	_update_hud()


func _apply_environment_style(sample: Node3D, template: ShaderMaterial, add_outline: bool) -> void:
	var pending: Array[Node] = [sample]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			pending.push_back(child)
		if not current is MeshInstance3D:
			continue

		var mesh_instance := current as MeshInstance3D
		if mesh_instance.material_override != null:
			var styled_override := _make_environment_material(
				mesh_instance.material_override, mesh_instance, template, add_outline
			)
			if styled_override != null:
				mesh_instance.material_override = styled_override
			continue

		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface_index in range(mesh.get_surface_count()):
			var source_material := mesh_instance.get_active_material(surface_index)
			if source_material == null:
				continue
			var styled_surface := _make_environment_material(
				source_material, mesh_instance, template, add_outline
			)
			if styled_surface != null:
				mesh_instance.set_surface_override_material(surface_index, styled_surface)


func _make_environment_material(
	source: Material, mesh_instance: MeshInstance3D, template: ShaderMaterial, add_outline: bool
) -> ShaderMaterial:
	var styled := template.duplicate() as ShaderMaterial
	if styled == null:
		push_error("Painterly Lab: could not duplicate an environment ShaderMaterial.")
		return null
	if not _copy_base_material(source, styled):
		return null
	styled.next_pass = (
		_outline_material if add_outline and _should_outline(mesh_instance) else null
	)
	return styled


func _should_outline(mesh_instance: MeshInstance3D) -> bool:
	# A positive list is safer than outlining every imported or future detail mesh.
	if String(mesh_instance.name) not in OUTLINE_CANDIDATE_NODE_NAMES:
		return false
	if mesh_instance.mesh == null:
		return false

	# A conservative lower bound on transformed thickness also handles parent-induced shear.
	# Singular/nearly singular transforms cannot produce a stable normal matrix or hull offset.
	var local_size := mesh_instance.mesh.get_aabb().size
	var basis := mesh_instance.global_transform.basis
	if absf(basis.determinant()) < 0.000001:
		return false
	var inverse_basis := basis.inverse()
	var inverse_frobenius := sqrt(
		(
			inverse_basis.x.length_squared()
			+ inverse_basis.y.length_squared()
			+ inverse_basis.z.length_squared()
		)
	)
	var minimum_world_scale := 1.0 / maxf(inverse_frobenius, 0.0001)
	var smallest_local_extent := minf(local_size.x, minf(local_size.y, local_size.z))
	var smallest_extent := smallest_local_extent * minimum_world_scale
	var line_width := float(_outline_material.get_shader_parameter("line_width"))
	var edge_wobble := float(_outline_material.get_shader_parameter("edge_wobble"))
	var maximum_line_width := line_width * (1.0 + edge_wobble)
	return smallest_extent > maximum_line_width * OUTLINE_MINIMUM_THICKNESS_RATIO


func _apply_character_style(character_root: Node) -> void:
	var pending: Array[Node] = [character_root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			pending.push_back(child)
		if not current is MeshInstance3D:
			continue

		var mesh_instance := current as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		if mesh_instance.material_override != null:
			var styled_override := _character_pigment.duplicate() as ShaderMaterial
			if styled_override == null:
				push_error("Painterly Lab: could not duplicate the character ShaderMaterial.")
				continue
			if _copy_base_material(mesh_instance.material_override, styled_override):
				mesh_instance.material_override = styled_override
			continue

		for surface_index in range(mesh.get_surface_count()):
			var source_material := mesh_instance.get_active_material(surface_index)
			if source_material == null:
				continue
			var styled := _character_pigment.duplicate() as ShaderMaterial
			if styled == null:
				push_error("Painterly Lab: could not duplicate the character ShaderMaterial.")
				continue
			if _copy_base_material(source_material, styled):
				mesh_instance.set_surface_override_material(surface_index, styled)


func _copy_base_material(source: Material, destination: ShaderMaterial) -> bool:
	var base := source as BaseMaterial3D
	if base == null:
		return _reject_material_migration(
			source, "only BaseMaterial3D albedo sources are supported"
		)

	var unsupported_reason := _unsupported_base_material_reason(base)
	if not unsupported_reason.is_empty():
		return _reject_material_migration(source, unsupported_reason)

	destination.set_shader_parameter("base_color", base.albedo_color)
	destination.set_shader_parameter("base_uv_scale", base.uv1_scale)
	destination.set_shader_parameter("base_uv_offset", base.uv1_offset)
	var texture := base.albedo_texture
	destination.set_shader_parameter("use_base_texture", texture != null)
	destination.set_shader_parameter("base_texture", texture)
	return true


func _unsupported_base_material_reason(base: BaseMaterial3D) -> String:
	var reason := ""
	if base.uv1_triplanar:
		reason = "UV1 triplanar mapping is not supported by the painterly UV sampler"
	elif base.vertex_color_use_as_albedo:
		reason = "vertex-color albedo is not migrated"
	elif base.detail_enabled:
		reason = "detail albedo is not migrated"
	elif base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		reason = "transparent albedo is not migrated"
	elif base.albedo_texture_msdf:
		reason = "MSDF albedo textures require their own decode path"
	elif base.albedo_texture_force_srgb:
		reason = "forced-sRGB albedo textures require their own conversion path"
	elif base.next_pass != null:
		reason = "source material next_pass is not migrated"
	elif base.albedo_texture != null:
		if base.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			reason = "albedo texture filtering differs from the painterly sampler"
		elif not base.texture_repeat:
			reason = "non-repeating albedo textures differ from the painterly sampler"
	return reason


func _reject_material_migration(source: Material, reason: String) -> bool:
	var source_name := source.resource_name
	if source_name.is_empty():
		source_name = source.get_class()
	push_warning("Painterly Lab: leaving '%s' unchanged; %s." % [source_name, reason])
	return false


func _build_stress_batch() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.58, 0.58, 0.58)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = BENCHMARK_INSTANCE_COUNT

	var half_grid := float(BENCHMARK_GRID_WIDTH - 1) * 0.5
	for index in range(BENCHMARK_INSTANCE_COUNT):
		var column := index % BENCHMARK_GRID_WIDTH
		var row := floori(float(index) / float(BENCHMARK_GRID_WIDTH))
		var position := Vector3(float(column) - half_grid, 0.09, float(row) - half_grid)
		var angle := deg_to_rad(float((column * 23 + row * 17) % 360))
		var basis := Basis(Vector3.UP, angle)
		multimesh.set_instance_transform(index, Transform3D(basis, position))
	_stress_batch.multimesh = multimesh


func _benchmark_material(variant: int) -> Material:
	match variant:
		0:
			return _baseline_material
		1:
			return _environment_fields
		2:
			return _environment_inked
	return _baseline_material


func _set_benchmark_view(enabled: bool) -> void:
	_benchmark_view = enabled
	_samples.visible = not enabled
	_characters.visible = not enabled
	_benchmark.visible = enabled
	if enabled:
		set_benchmark_variant(_selected_benchmark_variant)
	_update_hud()


func _update_hud() -> void:
	if _stats_label == null:
		return
	var window_size := DisplayServer.window_get_size()
	var width := window_size.x
	var height := window_size.y
	var fps := Engine.get_frames_per_second()
	var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var mode_text := "144-instance benchmark: %s" % BENCHMARK_NAMES[_selected_benchmark_variant]
	if not _benchmark_view:
		mode_text = "Three environment lanes + separate character study"
	if _benchmark_running:
		mode_text = "Benchmark running — keep the window focused"
	_stats_label.text = (
		"Painterly Lab — %d x %d  |  perspective FOV 60\n" % [width, height]
		+ "FPS: %d  |  process: %.2f ms  |  draw calls: %d\n" % [fps, process_ms, draw_calls]
		+ "Objects: %d  |  primitives: %d\n" % [objects, primitives]
		+ mode_text
	)
