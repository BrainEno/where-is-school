extends Node
## The real medium switch (experiment D).
##
## In 3D mode nothing here costs anything: the SubViewport is not updated and the canvas is
## hidden. In painted mode:
##
## 1. the root viewport stops rendering 3D (`Viewport.disable_3d`), so the frame is not
##    drawn twice;
## 2. a SubViewport at `RENDER_SCALE` of the window, sharing the same World3D, renders the
##    observer's view through its own camera, copied from the observer's every frame;
## 3. a full-screen TextureRect shows that texture through `painting_filter.gdshader` —
##    stroke smear, banded values, ink edges, a crooked paper mount — torn in from the left
##    over `REVEAL_SECONDS`.
##
## The observer, its collisions and the world are untouched: the stage stays solid while it
## looks painted, which is the experiment. Every renderer can do all three steps; nothing
## reads the screen texture or the depth buffer.

const FILTER_SHADER := preload("res://scenes/dev/visual_experiments/shaders/painting_filter.gdshader")
const RENDER_SCALE: float = 0.5
const REVEAL_SECONDS: float = 0.7
const CANVAS_LAYER: int = 5

var _observer_camera: Camera3D = null
var _view: SubViewport = null
var _camera: Camera3D = null
var _canvas: CanvasLayer = null
var _painting: TextureRect = null
var _material: ShaderMaterial = null
var _painted: bool = false
var _reveal: float = 0.0
var _switches: int = 0
var _root_disable_3d_before: bool = false


func _ready() -> void:
	process_priority = 100
	_root_disable_3d_before = get_viewport().disable_3d
	_view = SubViewport.new()
	_view.name = "PaintedView"
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.size = Vector2i(64, 64)
	add_child(_view)
	_camera = Camera3D.new()
	_camera.name = "PaintedCamera"
	_camera.current = true
	_view.add_child(_camera)
	_canvas = CanvasLayer.new()
	_canvas.name = "PaintedCanvas"
	_canvas.layer = CANVAS_LAYER
	_canvas.visible = false
	add_child(_canvas)
	_painting = TextureRect.new()
	_painting.name = "Painting"
	_painting.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_painting.stretch_mode = TextureRect.STRETCH_SCALE
	_painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painting.texture = _view.get_texture()
	_material = ShaderMaterial.new()
	_material.shader = FILTER_SHADER
	_painting.material = _material
	_canvas.add_child(_painting)


func _exit_tree() -> void:
	# Never leave the window without 3D: the lab may be closed while painted.
	var viewport := get_viewport()
	if viewport != null:
		viewport.disable_3d = _root_disable_3d_before


func bind(observer_camera: Camera3D) -> void:
	_observer_camera = observer_camera


func is_painted() -> bool:
	return _painted


func get_reveal() -> float:
	return _reveal


func get_switch_count() -> int:
	return _switches


func get_view() -> SubViewport:
	return _view


func get_painted_camera() -> Camera3D:
	return _camera


func get_canvas() -> CanvasLayer:
	return _canvas


func get_filter_material() -> ShaderMaterial:
	return _material


## Switches the medium. `instant` skips the tear (captures and tests).
func set_painted(enabled: bool, instant: bool = false) -> void:
	if enabled == _painted:
		if instant:
			_reveal = 1.0 if enabled else 0.0
			_apply_reveal()
		return
	_painted = enabled
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
	var target := 1.0 if _painted else 0.0
	if not is_equal_approx(_reveal, target):
		_reveal = move_toward(_reveal, target, delta / REVEAL_SECONDS)
		_apply_reveal()
	if _canvas.visible:
		_resize_view()
		_sync_camera()


func _apply_reveal() -> void:
	_material.set_shader_parameter("reveal", _reveal)
	if not _painted and _reveal <= 0.0 and _canvas.visible:
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


func _resize_view() -> void:
	var window_size := get_viewport().get_visible_rect().size
	var wanted := Vector2i(
		maxi(64, int(window_size.x * RENDER_SCALE)), maxi(64, int(window_size.y * RENDER_SCALE))
	)
	if _view.size != wanted:
		_view.size = wanted
		_material.set_shader_parameter("texel", Vector2(1.0 / wanted.x, 1.0 / wanted.y))
		_material.set_shader_parameter("screen_aspect", window_size.x / maxf(window_size.y, 1.0))
