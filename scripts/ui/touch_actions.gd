extends Control
## Two quiet, reachable controls over exploration. Picking a target still belongs to
## InteractionController, and a tap in the world still belongs to PointerNavigator.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

var _pause: Button
var _use: Button
var _menu: PauseMenu
var _interaction: InteractionController
var _player: PlayerController
var _ui: GameUI


func _ready() -> void:
	hide()
	if not MobileLayout.enabled:
		set_process(false)
		return
	_ui = get_parent() as GameUI
	var main := _ui.get_parent()
	_menu = main.get_node_or_null(^"PauseMenu") as PauseMenu
	_player = main.get_node_or_null(^"Player") as PlayerController
	if _menu == null or _player == null:
		set_process(false)
		return
	_interaction = _player.get_node_or_null(^"InteractionController") as InteractionController
	_pause = _button("Pause", _menu.open)
	_use = _button("Use", _use_current)
	_menu.opened.connect(_refresh)
	_menu.closed.connect(_refresh)
	# Some players use a gamepad on a handheld. Do not cover the scene until the next touch.
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect(&"input_device_changed", _refresh.unbind(1))
		settings.connect(&"setting_changed", _on_setting_changed)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect(&"locale_changed", _labels.unbind(1))
	MobileLayout.watch(self, _fit)
	_labels()
	_refresh()


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
	_pause.text = L10n.t("settings.action.pause")
	_use.text = L10n.t("settings.action.interact")
	_fit()


func _process(_delta: float) -> void:
	if _menu != null:
		_refresh()


func _refresh() -> void:
	if _pause == null or _ui == null or not _ui.is_node_ready():
		return
	var blocked := _menu.is_open() or _ui.backlog.is_open() or _ui.end_card.visible or _ui.fade.visible
	visible = not blocked and InputHint.device(self) == InputHint.DEVICE_TOUCH
	_use.visible = visible and not _ui.dialogue_panel.visible and _can_use()


func _can_use() -> bool:
	return _interaction != null and _interaction.is_enabled() and _player.is_control_enabled() \
		and is_instance_valid(_interaction.get_current_target())


func _use_current() -> void:
	if _use.visible and _can_use():
		_interaction.request_activation(_interaction.get_current_target())


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		for button: Button in [_pause, _use]:
			button.add_theme_font_size_override(&"font_size", UiTextScale.scaled(23, UiTextScale.current(self)))
		_fit()


func _fit() -> void:
	if _pause == null:
		return
	var safe := MobileLayout.safe_rect(self).grow(-MobileLayout.EDGE)
	for button: Button in [_pause, _use]:
		MobileLayout.enlarge(button)
		var minimum := button.get_combined_minimum_size()
		button.size = Vector2(maxf(minimum.x + 28.0, 154.0), minimum.y)
		var y := safe.position.y if button == _pause else safe.end.y - button.size.y
		button.position = Vector2(safe.end.x - button.size.x, y)
