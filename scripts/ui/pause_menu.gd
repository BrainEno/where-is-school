class_name PauseMenu
extends CanvasLayer
## The menu during play: Esc or Start.
##
## Resume / Settings / New game / Title. The world is paused while it is open (the tree is,
## and this layer runs anyway); the settings screen is the same one the title screen opens.
## New game asks first and then hands over to `Session.start_new_game()`, which stops this
## world's autosave before anything is deleted. Title leaves the run where its last
## checkpoint put it, exactly as quitting does.
##
## It never takes Esc from something that is already using it: with the log open, Esc
## closes the log; with a confirmation or the settings up, Esc closes those first.

signal opened
signal closed

const ENTRIES: Array[StringName] = [&"resume", &"settings", &"new_game", &"title"]

var _factor := 1.0
var _root: Control = null
var _column: VBoxContainer = null
var _heading: Label = null
var _hint: Label = null
var _entries: Dictionary = {}
var _settings_panel: SettingsPanel = null
var _confirm: ConfirmPrompt = null
var _was_paused := false


func _ready() -> void:
	name = "PauseMenu"
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_factor = UiTextScale.current(self)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	_root.add_child(MenuStyle.backdrop())
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override(&"separation", 4)
	_root.add_child(_column)
	_heading = MenuStyle.label("", MenuStyle.TITLE_SIZE, _factor, MenuStyle.PAPER)
	_column.add_child(_heading)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	_column.add_child(gap)
	for id: StringName in ENTRIES:
		var entry := MenuStyle.entry_button("", MenuStyle.ENTRY_SIZE, _factor)
		entry.name = String(id)
		entry.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry.pressed.connect(activate.bind(id))
		_column.add_child(entry)
		_entries[id] = entry
	_hint = MenuStyle.label("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_root.add_child(_hint)

	_settings_panel = SettingsPanel.new()
	_root.add_child(_settings_panel)
	_settings_panel.closed.connect(focus_entry.bind(&"settings"))
	_confirm = ConfirmPrompt.new()
	_root.add_child(_confirm)
	_confirm.confirmed.connect(_on_new_game_confirmed)
	_confirm.cancelled.connect(focus_entry.bind(&"new_game"))

	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_device_changed)
		settings.connect("bindings_changed", _refresh_texts)
	_root.get_viewport().size_changed.connect(_fit)
	_refresh_texts()


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	_factor = UiTextScale.current(self)
	UiTextScale.apply(_root, _factor)
	_refresh_texts()
	_root.show()
	_fit()
	focus_entry(&"resume")
	opened.emit()


func close() -> void:
	if not is_open():
		return
	_settings_panel.close()
	_confirm.hide()
	_root.hide()
	get_tree().paused = _was_paused
	closed.emit()


func get_entry(id: StringName) -> Button:
	return _entries.get(id) as Button


func get_settings_panel() -> SettingsPanel:
	return _settings_panel


func get_confirm() -> ConfirmPrompt:
	return _confirm


func focus_entry(id: StringName) -> void:
	var entry := get_entry(id)
	if entry != null and entry.is_visible_in_tree():
		entry.grab_focus()


func activate(id: StringName) -> void:
	match id:
		&"resume":
			close()
		&"settings":
			_settings_panel.open()
		&"new_game":
			_confirm.ask(
				L10n.t("menu.confirm_new_game"),
				L10n.t("menu.confirm_yes"),
				L10n.t("menu.confirm_no")
			)
		&"title":
			var session := get_node_or_null(^"/root/Session")
			_root.hide()
			if session != null:
				session.call("go_to_title")


func _on_new_game_confirmed() -> void:
	_root.hide()
	var session := get_node_or_null(^"/root/Session")
	if session != null:
		# The menu's own world: the session switches its autosave off before anything else.
		session.call("start_new_game", owner if owner != null else get_parent())


func _unhandled_input(event: InputEvent) -> void:
	if is_open():
		if _settings_panel.is_open() or _confirm.visible:
			return
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
			return
		# The world is paused, but autoloads that run anyway must not act through the menu.
		if event is InputEventKey or event is InputEventJoypadButton:
			if not event.is_action_pressed(&"toggle_language") \
					and not event.is_action_pressed(&"toggle_fullscreen"):
				get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"pause"):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _something_else_owns_cancel():
		return
	get_viewport().set_input_as_handled()
	open()


## The log closes on Esc; the session may be swapping worlds.
func _something_else_owns_cancel() -> bool:
	var session := get_node_or_null(^"/root/Session")
	if session != null and bool(session.call("is_starting_new_game")):
		return true
	var ui: Node = get_parent().get_node_or_null(^"GameUI") if get_parent() != null else null
	if ui != null:
		var backlog := ui.get_node_or_null(^"%BacklogPanel") as BacklogPanel
		if backlog != null and backlog.is_open():
			return true
	return false


func _refresh_texts() -> void:
	if _heading == null:
		return
	_heading.text = L10n.t("menu.paused")
	for id: StringName in ENTRIES:
		(_entries[id] as Button).text = L10n.t("menu.%s" % id)
	if MenuStyle.using_gamepad(self):
		_hint.text = L10n.t("menu.pause_hint_pad", {"key": MenuStyle.key(self, &"pause")})
	else:
		_hint.text = L10n.t("menu.pause_hint_keyboard", {"key": MenuStyle.key(self, &"pause")})


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key) and _root != null:
		_factor = UiTextScale.current(self)
		UiTextScale.apply(_column, _factor)
		UiTextScale.apply(_hint, _factor)
		_fit()


func _on_device_changed(_device: StringName) -> void:
	_refresh_texts()


func _fit() -> void:
	if _column == null:
		return
	var view := _root.get_viewport_rect().size
	var left := minf(view.x * 0.085, 160.0)
	var width := minf(view.x - left * 2.0, 560.0 * maxf(_factor, 1.0))
	_column.custom_minimum_size = Vector2(width, 0.0)
	_column.size = Vector2(width, 0.0)
	var needed := _column.get_combined_minimum_size().y
	_column.position = Vector2(left, maxf(24.0, minf(view.y * 0.28, view.y - needed - 90.0)))
	_hint.position = Vector2(left + 12.0, view.y - 48.0 * maxf(_factor, 1.0))
	_hint.size = Vector2(view.x - left * 2.0, 0.0)
