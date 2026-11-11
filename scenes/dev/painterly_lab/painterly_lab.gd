extends Node3D
## Standalone material study. It intentionally does not instance the production classroom,
## navigation, player, or CameraRig; the local perspective camera stays at the current 60° FOV.

const BASELINE_MATERIAL: StandardMaterial3D = preload(
	"res://assets/shaders/painterly/environment_baseline.tres"
)
const ENVIRONMENT_FIELDS: ShaderMaterial = preload(
	"res://assets/shaders/painterly/environment_fields.tres"
)
const ENVIRONMENT_INKED: ShaderMaterial = preload(
	"res://assets/shaders/painterly/environment_inked.tres"
)
const OUTLINE_MATERIAL: ShaderMaterial = preload(
	"res://assets/shaders/painterly/environment_outline.tres"
)
const CHARACTER_PIGMENT: ShaderMaterial = preload(
	"res://assets/shaders/painterly/character_pigment.tres"
)

const BENCHMARK_INSTANCE_COUNT: int = 144
const BENCHMARK_GRID_WIDTH: int = 12
const BENCHMARK_WARMUP_SECONDS: float = 1.0
const BENCHMARK_SAMPLE_SECONDS: float = 3.0
const BENCHMARK_NAMES: Array[String] = ["Standard", "Color fields", "Marks + contour"]

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
	_apply_environment_style($Samples/ColorFields, ENVIRONMENT_FIELDS, false)
	_apply_environment_style($Samples/FieldsMarksContour, ENVIRONMENT_INKED, true)
	_apply_character_style($Characters/CharacterPigment)
	_build_stress_batch()
	set_benchmark_variant(0)
	_camera.look_at(Vector3(1.8, 1.2, 0.0), Vector3.UP)
	_update_hud()


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
		var source_material: Material = mesh_instance.material_override
		if source_material == null:
			source_material = mesh_instance.get_active_material(0)
		if source_material == null:
			continue

		var styled := template.duplicate() as ShaderMaterial
		if styled == null:
			push_error("Painterly Lab: could not duplicate an environment ShaderMaterial.")
			continue
		_copy_base_material(source_material, styled)
		styled.next_pass = (
			OUTLINE_MATERIAL if add_outline and _should_outline(mesh_instance) else null
		)
		mesh_instance.material_override = styled


func _should_outline(mesh_instance: MeshInstance3D) -> bool:
	var node_name := String(mesh_instance.name)
	if node_name in ["Floor", "DoorHandle", "Book"] or node_name.begins_with("DeskLeg"):
		return false
	return true


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
		for surface_index in range(mesh.get_surface_count()):
			var source_material := mesh_instance.get_active_material(surface_index)
			var styled := CHARACTER_PIGMENT.duplicate() as ShaderMaterial
			if styled == null:
				push_error("Painterly Lab: could not duplicate the character ShaderMaterial.")
				continue
			if source_material != null:
				_copy_base_material(source_material, styled)
			mesh_instance.set_surface_override_material(surface_index, styled)


func _copy_base_material(source: Material, destination: ShaderMaterial) -> void:
	var base := source as BaseMaterial3D
	if base == null:
		return
	destination.set_shader_parameter("base_color", base.albedo_color)
	var texture := base.albedo_texture
	destination.set_shader_parameter("use_base_texture", texture != null)
	if texture != null:
		destination.set_shader_parameter("base_texture", texture)


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
			return BASELINE_MATERIAL
		1:
			return ENVIRONMENT_FIELDS
		2:
			return ENVIRONMENT_INKED
	return BASELINE_MATERIAL


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
