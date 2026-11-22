extends Control
## Gameplay controls only. Native finger ownership here leaves unrelated fingers to the
## regular GUI and PointerNavigator. No synthetic InputMap action is held by this layer.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const Joystick := preload("res://scripts/ui/touch_joystick.gd")

var _pause: Button
var _return: Button
var _use: Button
var _stick: Joystick
var _menu: PauseMenu
var _interaction: InteractionController
var _player: PlayerController
var _ui: GameUI
var _controls: Array[Control] = []
# Null values drain old gestures after a modal, rotation or focus loss until finger-up.
var _fingers: Dictionary[int, Control] = {}
var _stick_finger := -1
var _swallow_mouse := false


func _ready() -> void:
	hide()
	if not MobileLayout.enabled:
		set_process(false)
		set_process_input(false)
		return
	_ui = get_parent() as GameUI
	var main := _ui.get_parent()
	_menu = main.get_node_or_null(^"PauseMenu") as PauseMenu
	_player = main.get_node_or_null(^"Player") as PlayerController
	if _menu == null or _player == null:
		set_process(false)
		set_process_input(false)
		return
	_interaction = _player.get_node_or_null(^"InteractionController") as InteractionController
	_stick = Joystick.new()
	_stick.name = "Joystick"
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stick)
	_pause = _button("Pause", _menu.open)
	_return = _button("ReturnToTitle", _menu.request_return_to_title)
	_use = _button("Use", _use_current)
	# Keep the inactive button recognizable even over a bright part of the world.
	var inactive_panel := MenuStyle.panel_style()
	inactive_panel.border_color = MenuStyle.MUTED
	_use.add_theme_stylebox_override(&"disabled", inactive_panel)
	_use.add_theme_color_override(&"font_disabled_color", MenuStyle.MUTED)
	_controls.assign([_return, _pause, _use, _stick])
	_menu.opened.connect(_refresh)
	_menu.closed.connect(_refresh)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect(&"input_device_changed", _on_input_device_changed)
		settings.connect(&"setting_changed", _on_setting_changed)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect(&"locale_changed", _labels.unbind(1))
	MobileLayout.watch(self, _fit)
	_ui.ready.connect(_fit)
	_labels()


func _button(node_name: String, action: Callable) -> Button:
	var button := MenuStyle.entry_button("", 23, UiTextScale.current(self))
	button.name = node_name
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(&"normal", MenuStyle.panel_style())
	button.pressed.connect(action)
	add_child(button)
	return button


func _labels() -> void:
	_pause.text = L10n.t("menu.touch_pause")
	_return.text = L10n.t("menu.return_to_title")
	_use.text = L10n.t("settings.action.interact")
	_fit()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _pause == null or not _ui.is_node_ready() or not _menu.is_node_ready():
		return
	var blocked := get_tree().paused or _menu.is_open() or _ui.backlog.is_open() \
		or _ui.end_card.visible or _ui.fade.visible
	# Handheld HUD visibility follows gameplay, not the last input event. A host,
	# trackpad or controller can change the hints without taking away touch buttons.
	visible = not blocked
	var exploring := visible and not _ui.dialogue_panel.visible and _player.is_control_enabled()
	_stick.visible = exploring
	_use.visible = exploring
	_use.disabled = not exploring or not _can_use()
	_return.visible = visible and _menu.get_entry(&"save_quit").visible
	for id: int in _fingers:
		var control := _fingers[id]
		if control != null and not control.is_visible_in_tree():
			_cancel_finger(id)


func _input(event: InputEvent) -> void:
	_refresh()
	if MobileLayout.is_emulated_mouse(event):
		# Godot sends the first finger's emulated mouse event BEFORE its screen event.
		# Keep swallowing that mouse pair even if a second finger opens a modal, or
		# dragging the stick could click the modal. Leave other emulation (scrolling,
		# reading, title buttons) alone and never toggle the global emulation flag.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_swallow_mouse = _control_at(event.position) != null
			if _swallow_mouse:
				get_viewport().set_input_as_handled()
			if not event.pressed:
				_swallow_mouse = false
		elif _swallow_mouse and event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# This UI is visited before the Player subtree in Main's _input phase. Swallow
	# just the owned fingers so they never enter PointerNavigator's tap recognizer.
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		get_viewport().set_input_as_handled()
		if event.index == _stick_finger:
			_steer(event.position)


func _touch(event: InputEventScreenTouch) -> void:
	var id := event.index
	if event.pressed:
		if _fingers.get(id) != null:
			get_viewport().set_input_as_handled()
			return
		# A platform may reuse an index after suspending without ever sending finger-up.
		_fingers.erase(id)
		var control := _control_at(event.position)
		if control == null:
			return
		get_viewport().set_input_as_handled()
		# Multiple fingers in one hit area do not steal its original owner.
		_fingers[id] = null if _fingers.values().has(control) else control
		if _fingers[id] == _stick:
			_stick_finger = id
			_steer(event.position)
	elif _fingers.has(id):
		get_viewport().set_input_as_handled()
		var button := _fingers[id] as Button
		_cancel_finger(id)
		_fingers.erase(id)
		if not event.canceled and button != null and not button.disabled and _hit(button, event.position):
			button.pressed.emit()


func _control_at(point: Vector2) -> Control:
	for control in _controls:
		if _hit(control, point):
			return control
	return null


static func _hit(control: Control, point: Vector2) -> bool:
	return control.is_visible_in_tree() and Rect2(Vector2.ZERO, control.size).has_point(
		control.get_global_transform_with_canvas().affine_inverse() * point)


func _steer(point: Vector2) -> void:
	var local := _stick.get_global_transform_with_canvas().affine_inverse() * point
	_player.set_touch_move(_stick.steer(local))


func _cancel_finger(id: int) -> void:
	_fingers[id] = null
	if id == _stick_finger:
		_stick_finger = -1
		_stick.center_thumb()
		if is_instance_valid(_player):
			_player.set_touch_move(Vector2.ZERO)


func _cancel_gestures() -> void:
	for id: int in _fingers:
		_cancel_finger(id)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		_cancel_gestures()


func _can_use() -> bool:
	return _interaction != null and _interaction.is_enabled() \
		and is_instance_valid(_interaction.get_current_target())


func _use_current() -> void:
	if _use.is_visible_in_tree() and _player.is_control_enabled() and _can_use():
		_interaction.request_activation(_interaction.get_current_target())


func _on_input_device_changed(device: StringName) -> void:
	# The physical movement vector can take over immediately, but the old thumb
	# must not start moving again when that key/axis is released. Mouse reports
	# need not mean a hardware handoff (for example in a hosted iOS window).
	if _stick_finger >= 0 and device in [InputHint.DEVICE_KEYBOARD, InputHint.DEVICE_GAMEPAD]:
		_cancel_finger(_stick_finger)
	_refresh()


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		for button: Button in [_pause, _return, _use]:
			button.add_theme_font_size_override(&"font_size", UiTextScale.scaled(23, UiTextScale.current(self)))
		_fit()


func _fit() -> void:
	if _pause == null:
		return
	var safe := MobileLayout.safe_rect(self).grow(-MobileLayout.EDGE)
	var hit := MobileLayout.hit_size(self)
	var short := minf(safe.size.x, safe.size.y)
	var diameter := minf(clampf(short * 0.165, hit * 1.9, hit * 2.2), short * 0.42)
	var stick_bounds := Rect2(Vector2(safe.position.x, safe.end.y - diameter), Vector2(diameter, diameter))
	if not Rect2(_stick.position, _stick.size).is_equal_approx(stick_bounds):
		_cancel_gestures()
	_stick.position = stick_bounds.position
	_stick.size = stick_bounds.size
	for button: Button in [_pause, _return, _use]:
		MobileLayout.enlarge(button)
		button.size = button.get_combined_minimum_size() + Vector2(12.0, 0.0)
	_return.position = Vector2(safe.end.x - _return.size.x, safe.position.y)
	_pause.position = _return.position - Vector2(_pause.size.x + MobileLayout.EDGE, 0.0)
	_use.position = safe.end - _use.size
	if _ui.hud != null:
		_ui.hud.set_touch_header_size(Vector2(safe.end.x - _pause.position.x, maxf(_pause.size.y, _return.size.y)))
