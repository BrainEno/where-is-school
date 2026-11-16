extends Node3D
## The character art review stage (issue #188). Development only: excluded from the export
## (`scenes/dev/*`), loaded by nobody in the game.
##
## Open `character_art_review.tscn` in the editor and run it (F6). The production protagonist
## and Q wrappers stand on a plain floor; every review direction is put on them at run time by
## `review_stage.gd` and taken off again, so nothing on disk changes.
##
##   1-5      C (shipped) / C+A (pose) / D1 stage light / D2 charcoal + pastel / D3 colour planes
##   V        camera: gameplay (the CameraRig's offset and FOV) / dialogue two-shot / faces
##   W        both walk on the spot / stop (the protagonist hesitates after stopping)
##   T        Q steps in to talking distance and the two talk (A's `converse`) / step back
##   L        light: classroom-like / corridor-like / street-like (approximations, see below)
##   H        hide / show the HUD
##
## The HUD shows the frame time, draw calls and primitives the renderer reports for the frame:
## run this on the target machine to measure what each direction costs. The three light
## presets are a rough stand-in for the game's locations so the looks can be compared without
## booting the story; the CI capture (`tests/capture_character_art_review.gd`) photographs
## them in the real locations.

const ReviewStage = preload("res://scenes/dev/character_art_review/review_stage.gd")
const PROTAGONIST := "res://scenes/environment/characters/protagonist.tscn"
const Q := "res://scenes/environment/characters/q.tscn"
const VARIANTS: Array[String] = ["C", "C+A", "D1", "D2", "D3"]
## The game camera: CameraRig's default offset, field of view and target height.
const RIG_OFFSET := Vector3(3.4, 6.4, 3.4)
const RIG_FOV := 60.0
const RIG_TARGET_HEIGHT := 0.9
const APART_Q := Vector3(-1.0, 0.0, 0.7)
const CLOSE_Q := Vector3(-0.68, 0.0, 0.18)
## [name, sun colour, sun energy, sun pitch, sun yaw, ambient colour, ambient energy, fill colour, fill energy]
const LIGHTS := [
	["classroom-like", Color(1.0, 0.93, 0.82), 0.9, -48.0, 35.0, Color(0.55, 0.58, 0.62), 0.55, Color(1.0, 0.95, 0.85), 1.2],
	["corridor-like", Color(0.86, 0.92, 1.0), 0.35, -70.0, -20.0, Color(0.42, 0.46, 0.52), 0.5, Color(0.8, 0.9, 1.0), 2.0],
	["street-like", Color(1.0, 0.86, 0.68), 1.3, -28.0, 120.0, Color(0.5, 0.56, 0.68), 0.7, Color(0.7, 0.75, 0.9), 0.4],
]

var _protagonist: CharacterVisualAnimation
var _q: CharacterVisualAnimation
var _camera: Camera3D
var _sun: DirectionalLight3D
var _fill: OmniLight3D
var _environment: Environment
var _hud: Label
var _variant := 0
var _camera_mode := 0
var _light := 0
var _walking := false
var _talking := false


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_stage()
	_protagonist = (load(PROTAGONIST) as PackedScene).instantiate() as CharacterVisualAnimation
	_q = (load(Q) as PackedScene).instantiate() as CharacterVisualAnimation
	add_child(_protagonist)
	add_child(_q)
	_protagonist.rotation.y = deg_to_rad(35.0)
	_q.position = APART_Q
	_q.rotation.y = deg_to_rad(35.0)
	await get_tree().process_frame
	_apply_variant()
	_apply_light()
	_apply_camera()


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.16, 0.15, 0.15)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	_fill = OmniLight3D.new()
	_fill.position = Vector3(1.6, 2.7, 1.4)
	_fill.omni_range = 7.0
	add_child(_fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.38, 0.33)
	floor_material.roughness = 0.95
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	var back := MeshInstance3D.new()
	var wall := BoxMesh.new()
	wall.size = Vector3(12.0, 3.2, 0.1)
	back.mesh = wall
	back.position = Vector3(0.0, 1.6, -1.6)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.55, 0.56, 0.5)
	back.material_override = wall_material
	add_child(back)
	_camera = Camera3D.new()
	_camera.far = 120.0
	add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_hud.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_variant = int(key.physical_keycode - KEY_1)
			_apply_variant()
		KEY_V:
			_camera_mode = (_camera_mode + 1) % 3
			_apply_camera()
		KEY_W:
			_walking = not _walking
			for animator: CharacterVisualAnimation in [_protagonist, _q]:
				if _walking:
					animator.report_velocity(animator.global_basis.z.normalized() * 1.1)
				else:
					animator.report_velocity(Vector3.ZERO)
		KEY_T:
			_talking = not _talking
			_q.position = CLOSE_Q if _talking else APART_Q
			_q.rotation.y = deg_to_rad(-120.0 if _talking else 35.0)
			_protagonist.rotation.y = deg_to_rad(60.0 if _talking else 35.0)
			_apply_partners()
			_apply_camera()
		KEY_L:
			_light = (_light + 1) % LIGHTS.size()
			_apply_light()
		KEY_H:
			_hud.visible = not _hud.visible


func _apply_variant() -> void:
	var variant := VARIANTS[_variant]
	var direction := "c" if variant.begins_with("C") else variant.to_lower()
	var posed := variant != "C"
	ReviewStage.apply(_protagonist, _q, direction, posed, posed)
	_apply_partners()


func _apply_partners() -> void:
	for pair: Array in [[_protagonist, _q], [_q, _protagonist]]:
		var pose := ReviewStage.get_pose(pair[0])
		if pose != null:
			pose.set("partner", (pair[1] as Node3D) if _talking else null)


func _apply_light() -> void:
	var preset: Array = LIGHTS[_light]
	_sun.light_color = preset[1]
	_sun.light_energy = preset[2]
	_sun.rotation_degrees = Vector3(preset[3], preset[4], 0.0)
	_environment.ambient_light_color = preset[5]
	_environment.ambient_light_energy = preset[6]
	_fill.light_color = preset[7]
	_fill.light_energy = preset[8]


func _apply_camera() -> void:
	var centre := (_protagonist.global_position + _q.global_position) * 0.5
	match _camera_mode:
		0:
			_camera.fov = RIG_FOV
			_camera.global_position = centre + RIG_OFFSET + Vector3.UP * RIG_TARGET_HEIGHT
			_camera.look_at(centre + Vector3.UP * RIG_TARGET_HEIGHT, Vector3.UP)
		1:
			_camera.fov = 40.0
			_camera.global_position = centre + Vector3(0.6, 1.5, 2.4)
			_camera.look_at(centre + Vector3.UP * 1.2, Vector3.UP)
		2:
			_camera.fov = 30.0
			_camera.global_position = centre + Vector3(0.3, 1.55, 1.5)
			_camera.look_at(centre + Vector3.UP * 1.45, Vector3.UP)


func _process(_delta: float) -> void:
	if not _hud.visible:
		return
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var fps := Engine.get_frames_per_second()
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_hud.text = "\n".join([
		"[1-5] %s    [V] camera %s    [W] walk %s    [T] talk %s    [L] %s    [H] hide" % [
			VARIANTS[_variant], ["gameplay", "dialogue", "faces"][_camera_mode],
			"on" if _walking else "off", "on" if _talking else "off", String(LIGHTS[_light][0]),
		],
		"%d fps   process %.2f ms   GPU %.2f ms   %d draw calls   %d primitives" % [fps, frame_ms, gpu_ms, draws, primitives],
		"fps is capped by V-Sync; compare the GPU time between directions instead.",
	])
	if _walking:
		_apply_camera()
