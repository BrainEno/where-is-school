extends Node3D
## An orbit desk for the maquette, deliberately unrelated to the in-game camera and input map.

# Focus in world units; azimuth and elevation in degrees; distance from focus.
const VIEWS := [
	{ "focus": Vector3(-1.50, 6.05, -0.28), "orbit": Vector3(38, 31, 37.0) },
	{ "focus": Vector3(-1.22, 5.70, -0.95), "orbit": Vector3(193, 45, 35.0) },
	{ "focus": Vector3(-0.68, 4.98, 3.54), "orbit": Vector3(18, 14, 23.5) },
]

var _focus: Vector3
var _orbit: Vector3

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	show_view(0)


func show_view(index: int) -> void:
	var view: Dictionary = VIEWS[index]
	_focus = view["focus"]
	_orbit = view["orbit"]
	_place_camera()


func _place_camera() -> void:
	_orbit.x = wrapf(_orbit.x, -180.0, 180.0)
	_orbit.y = clampf(_orbit.y, 6.0, 82.0)
	_orbit.z = clampf(_orbit.z, 15.0, 66.0)
	var yaw := deg_to_rad(_orbit.x)
	var pitch := deg_to_rad(_orbit.y)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.global_position = _focus + direction * _orbit.z
	_camera.look_at(_focus)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_orbit.x -= event.relative.x * 0.24
		_orbit.y += event.relative.y * 0.24
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: _orbit.z *= 0.90
			MOUSE_BUTTON_WHEEL_DOWN: _orbit.z /= 0.90
			_: return
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1, KEY_R: show_view(0)
			KEY_2: show_view(1)
			KEY_3: show_view(2)
			KEY_LEFT: _orbit.x -= 9.0
			KEY_RIGHT: _orbit.x += 9.0
			KEY_UP: _orbit.y += 5.0
			KEY_DOWN: _orbit.y -= 5.0
			_: return
	else:
		return
	_place_camera()
	get_viewport().set_input_as_handled()
