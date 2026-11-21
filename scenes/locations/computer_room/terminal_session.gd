extends CanvasLayer
## Modal input/scale boundary. The exact desktop drawn here is also the 3D CRT texture.

const Desktop = preload("res://scenes/locations/computer_room/terminal_desktop.gd")
const PIXELS := Vector2(640, 480)

signal closed
signal started

@onready var _root: ColorRect = $Shade
@onready var _bezel: Panel = $Shade/Bezel
@onready var _display: SubViewportContainer = $Shade/Display
@onready var _viewport: SubViewport = $Shade/Display/Pixels
@onready var desktop: Desktop = $Shade/Display/Pixels/Desktop

var _open := false
var _fade: Tween


func _ready() -> void:
	_root.resized.connect(_fit)
	desktop.shutdown_requested.connect(shutdown)
	desktop.boot_finished.connect(func() -> void: started.emit())
	hide()
	set_process_input(false)
	_fit()


func start(first_boot: bool) -> void:
	_open = true
	show()
	set_process_input(true)
	_fit()
	_root.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_interval(0.40) # Let the real tube light the desk before cutting in.
	_fade.tween_property(_root, "modulate:a", 1.0, 0.28)
	desktop.boot(first_boot)


func screen_texture() -> ViewportTexture:
	return _viewport.get_texture()


func is_open() -> bool:
	return _open


func shutdown() -> void:
	if not _open:
		return
	_open = false
	if _fade != null:
		_fade.kill()
	set_process_input(false)
	desktop.stop()
	hide()
	closed.emit()


func _fit() -> void:
	var available := _root.size - Vector2(48, 48)
	var factor := maxf(0.1, minf(available.x / PIXELS.x, available.y / PIXELS.y))
	_display.scale = Vector2.ONE * factor
	_display.position = ((_root.size - PIXELS * factor) * 0.5).round()
	_bezel.position = _display.position - Vector2(12, 12)
	_bezel.size = PIXELS * factor + Vector2(24, 24)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	# Key remapping is still respected for Cancel; don't open the main pause menu behind the CRT.
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			desktop.back()
	elif event.is_action_pressed(&"journal"):
		get_viewport().set_input_as_handled()
	elif desktop.handle_event(event):
		get_viewport().set_input_as_handled()
