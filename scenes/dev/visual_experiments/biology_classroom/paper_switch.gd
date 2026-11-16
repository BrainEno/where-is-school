extends Node
## The blank-paper medium: what drawing the curtain does to the picture.
##
## The same machinery as the visual lab's medium switch (`../medium_switch.gd`), copied
## here so the lab stays untouched and this experiment owns its own filter:
##
## 1. while the paper is down, the root viewport stops rendering 3D (`disable_3d`), so the
##    frame is not drawn twice;
## 2. a SubViewport at `RENDER_SCALE` of the window, sharing the World3D, renders through
##    a camera copied from the visitor's every frame;
## 3. a full-screen TextureRect shows it through `blank_paper.gdshader`, spreading from
##    the opening (`set_origin`) over `REVEAL_SECONDS`.
##
## Nothing in the world changes: collisions, the visitor, Q, are all as they were. When the
## paper lifts and the reveal reaches 0, the SubViewport stops updating and the root
## renders 3D again; in colour, nothing here costs anything.

const FILTER_SHADER := preload(
	"res://scenes/dev/visual_experiments/biology_classroom/shaders/blank_paper.gdshader"
)
const RENDER_SCALE: float = 0.6
const REVEAL_SECONDS: float = 2.2
const LIFT_SECONDS: float = 0.9
const CANVAS_LAYER: int = 5

var _observer_camera: Camera3D = null
var _view: SubViewport = null
var _camera: Camera3D = null
var _canvas: CanvasLayer = null
var _picture: TextureRect = null
var _material: ShaderMaterial = null
var _on: bool = false
var _reveal: float = 0.0
var _switches: int = 0
var _root_disable_3d_before: bool = false
var _origin_world: Vector3 = Vector3.ZERO
var _has_origin: bool = false


func _ready() -> void:
	process_priority = 100
	_root_disable_3d_before = get_viewport().disable_3d
	_view = SubViewport.new()
	_view.name = "PaperView"
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.size = Vector2i(64, 64)
	add_child(_view)
	_camera = Camera3D.new()
	_camera.name = "PaperCamera"
	_camera.current = true
	_view.add_child(_camera)
	_canvas = CanvasLayer.new()
	_canvas.name = "PaperCanvas"
	_canvas.layer = CANVAS_LAYER
	_canvas.visible = false
	add_child(_canvas)
	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.texture = _view.get_texture()
	_material = ShaderMaterial.new()
	_material.shader = FILTER_SHADER
	_picture.material = _material
	_canvas.add_child(_picture)


func _exit_tree() -> void:
	# Never leave the window without 3D, even if the scene is closed on paper.
	var viewport := get_viewport()
	if viewport != null:
		viewport.disable_3d = _root_disable_3d_before


func bind(observer_camera: Camera3D) -> void:
	_observer_camera = observer_camera


## Where the paper comes from, in the world (the opening). Projected every frame.
func set_origin(world_point: Vector3) -> void:
	_origin_world = world_point
	_has_origin = true


func is_on() -> bool:
	return _on


func get_reveal() -> float:
	return _reveal


func get_switch_count() -> int:
	return _switches


func get_view() -> SubViewport:
	return _view


func get_canvas() -> CanvasLayer:
	return _canvas


func get_filter_material() -> ShaderMaterial:
	return _material


func get_paper_camera() -> Camera3D:
	return _camera


## Puts the paper down (`enabled`) or lifts it. `instant` skips the spread (captures, tests).
func set_paper(enabled: bool, instant: bool = false) -> void:
	if enabled == _on:
		if instant:
			_reveal = 1.0 if enabled else 0.0
			_apply_reveal()
		return
	_on = enabled
	_switches += 1
	if enabled:
		_resize_view()
		_sync_camera()
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_canvas.visible = true
		get_viewport().disable_3d = true
	if instant:
		_reveal = 1.0 if enabled else 0.0
	_apply_reveal()


func _process(delta: float) -> void:
	var target := 1.0 if _on else 0.0
	if not is_equal_approx(_reveal, target):
		var seconds := REVEAL_SECONDS if _on else LIFT_SECONDS
		_reveal = move_toward(_reveal, target, delta / seconds)
		_apply_reveal()
	if _canvas.visible:
		_resize_view()
		_sync_camera()


func _apply_reveal() -> void:
	_material.set_shader_parameter("reveal", _reveal)
	if not _on and _reveal <= 0.0 and _canvas.visible:
		_canvas.visible = false
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		get_viewport().disable_3d = _root_disable_3d_before


func _sync_camera() -> void:
	if _observer_camera == null or not is_instance_valid(_observer_camera):
		return
	_camera.global_transform = _observer_camera.global_transform
	_camera.fov = _observer_camera.fov
	_camera.near = _observer_camera.near
	_camera.far = _observer_camera.far
	if _has_origin and not _camera.is_position_behind(_origin_world):
		var screen := _camera.unproject_position(_origin_world)
		var size := Vector2(_view.size)
		_material.set_shader_parameter("origin", screen / size)


func _resize_view() -> void:
	var window_size := get_viewport().get_visible_rect().size
	var wanted := Vector2i(
		maxi(64, int(window_size.x * RENDER_SCALE)), maxi(64, int(window_size.y * RENDER_SCALE))
	)
	if _view.size != wanted:
		_view.size = wanted
		_material.set_shader_parameter("texel", Vector2(1.0 / wanted.x, 1.0 / wanted.y))
		_material.set_shader_parameter("screen_aspect", window_size.x / maxf(window_size.y, 1.0))
