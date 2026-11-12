class_name SettingsPanel
extends Control
## The settings screen: text size and speed, the three volume dials, interface scale,
## fullscreen and language, and the key/button for every action.
##
## Built in code so the rows, their order and their ids live in one list. Everything can be
## reached without a mouse: ↑/↓ (or the D-pad) move between rows, ←/→ change a choice or a
## dial, Enter/Space/A activates, Esc/B closes. A rebinding button waits for the next key
## (keyboard column) or button/stick direction (controller column); Esc cancels the wait,
## and so does waiting `CAPTURE_SECONDS`.
##
## Every change is applied and saved by the `Settings` autoload the moment it is made: there
## is no "apply" step to forget.

signal closed

const CAPTURE_SECONDS := 6.0
const PANEL_MAX_WIDTH := 980.0
const OUTER_MARGIN := 40.0

var _factor := 1.0
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _rows: VBoxContainer = null
var _status: Label = null
var _title: Label = null
var _back: Button = null
## id -> the focusable control for that row.
var _controls: Dictionary = {}
var _capture_action := StringName()
var _capture_device := StringName()
var _capture_deadline_msec := 0
var _rebuild_queued := false
var _focus_after_rebuild := StringName()


func _init() -> void:
	name = "SettingsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	add_child(MenuStyle.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, int(OUTER_MARGIN))
	add_child(margin)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", MenuStyle.panel_style())
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	_panel.add_child(column)
	_title = MenuStyle.label("", MenuStyle.TITLE_SIZE, 1.0, MenuStyle.PAPER)
	column.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(_rows)
	_status = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, 1.0, MenuStyle.MUTED)
	column.add_child(_status)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_back = MenuStyle.entry_button("", MenuStyle.ENTRY_SIZE, 1.0)
	_back.name = "Back"
	_back.pressed.connect(close)
	footer.add_child(_back)

	var settings := _settings()
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("bindings_changed", _on_bindings_changed)
		settings.connect("input_device_changed", _on_device_changed)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	get_viewport().size_changed.connect(_fit)
	_rebuild()


func open() -> void:
	_cancel_capture()
	_rebuild()
	show()
	_fit()
	focus_row(&"text_size")


func close() -> void:
	if not visible:
		return
	_cancel_capture()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


## The focusable control of a row: `text_size`, `text_speed`, `volume_master`,
## `volume_music`, `volume_sfx`, `ui_scale`, `fullscreen`, `language`,
## `bind_<action>_keyboard`, `bind_<action>_gamepad`, `restore_bindings`, `back`.
func get_row_control(id: StringName) -> Control:
	if id == &"back":
		return _back
	return _controls.get(id) as Control


func get_row_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: Variant in _controls.keys():
		ids.append(StringName(id))
	ids.append(&"back")
	return ids


func focus_row(id: StringName) -> void:
	var control := get_row_control(id)
	if control != null and control.is_inside_tree():
		control.grab_focus()


func get_panel() -> PanelContainer:
	return _panel


func get_scroll() -> ScrollContainer:
	return _scroll


func get_status_text() -> String:
	return _status.text if _status != null else ""


func is_capturing() -> bool:
	return not String(_capture_action).is_empty()


## Starts waiting for a new key (`device` "keyboard") or button (`device` "gamepad").
func start_capture(action: StringName, device: StringName) -> void:
	_capture_action = action
	_capture_device = device
	_capture_deadline_msec = Time.get_ticks_msec() + int(CAPTURE_SECONDS * 1000.0)
	var wait_key := "settings.capture_key" if device == &"keyboard" else "settings.capture_pad"
	_status.text = L10n.t(wait_key, {"action": _action_name(action)})
	var control := get_row_control(_bind_id(action, device)) as Button
	if control != null:
		control.text = "…"


# --- Building --------------------------------------------------------------------


func _rebuild() -> void:
	_rebuild_queued = false
	var focused := _focused_id()
	if String(_focus_after_rebuild).is_empty():
		_focus_after_rebuild = focused
	_factor = UiTextScale.current(self)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_controls.clear()
	_title.text = L10n.t("settings.title")
	_back.text = L10n.t("menu.back")

	_heading("settings.section.text")
	_choice_row(&"text_size", "settings.text_size", _text_size_options(), _current(&"text_size"))
	_choice_row(&"text_speed", "settings.text_speed", _text_speed_options(), _current(&"text_speed"))
	_heading("settings.section.sound")
	for key: StringName in [&"master", &"music", &"sfx"]:
		_volume_row(key)
	_heading("settings.section.display")
	_choice_row(&"ui_scale", "settings.ui_scale", _ui_scale_options(), _current(&"ui_scale"))
	_choice_row(&"fullscreen", "settings.fullscreen", _on_off_options(), _current(&"fullscreen"))
	_choice_row(&"language", "settings.language", _language_options(), _current(&"language"))
	_heading("settings.section.controls")
	_binding_header()
	for action: StringName in _rebindable():
		_binding_row(action)
	var restore := MenuStyle.entry_button(
		L10n.t("settings.restore_bindings"), MenuStyle.BODY_SIZE, _factor
	)
	restore.name = "RestoreBindings"
	restore.pressed.connect(_on_restore_pressed)
	_rows.add_child(restore)
	_controls[&"restore_bindings"] = restore

	UiTextScale.apply(self, _factor)
	_link_focus()
	_refresh_status_hint()
	_fit()
	if visible and not String(_focus_after_rebuild).is_empty():
		var target := _focus_after_rebuild
		call_deferred("focus_row", target)
	_focus_after_rebuild = StringName()


## This screen is a modal over the pause menu or the title, and Godot looks for the nearest
## control in the pressed direction anywhere under the same top-level Control: with the list
## scrolled, ↓ from "Restore defaults" landed on the pause menu behind the screen, and Tab
## from "Back" did too. So every row names its neighbours itself. ↑/↓ walk the list (the
## binding grid keeps its column and steps over the fixed Esc cells), ←/→ stay on the row or
## cross between its two cells, the ends stop, and Tab wraps inside the screen.
func _link_focus() -> void:
	var grid: Array[Array] = []
	for id: StringName in [
		&"text_size", &"text_speed", &"volume_master", &"volume_music", &"volume_sfx",
		&"ui_scale", &"fullscreen", &"language",
	]:
		var single := _focusable(get_row_control(id))
		if single != null:
			grid.append([single, single])
	for action: StringName in _rebindable():
		var keys := _focusable(get_row_control(_bind_id(action, &"keyboard")))
		var pad := _focusable(get_row_control(_bind_id(action, &"gamepad")))
		if keys != null or pad != null:
			grid.append([keys, pad])
	for id: StringName in [&"restore_bindings", &"back"]:
		var single := _focusable(get_row_control(id))
		if single != null:
			grid.append([single, single])
	for row in grid.size():
		var cells: Array = grid[row]
		for column in 2:
			var control := cells[column] as Control
			# A single row is listed in both columns; it is linked once, from the keyboard
			# side, so ↓ into the binding grid lands on the first key cell.
			if control == null or (column == 1 and cells[0] == control):
				continue
			var left := control
			var right := control
			if column == 1 and cells[0] != null:
				left = cells[0] as Control
			if column == 0 and cells[1] != null:
				right = cells[1] as Control
			control.focus_neighbor_left = control.get_path_to(left)
			control.focus_neighbor_right = control.get_path_to(right)
			control.focus_neighbor_top = control.get_path_to(_grid_step(grid, row, column, -1))
			control.focus_neighbor_bottom = control.get_path_to(_grid_step(grid, row, column, 1))
	if grid.is_empty():
		return
	var first := grid[0][0] as Control
	var last := grid[grid.size() - 1][0] as Control
	first.focus_previous = first.get_path_to(last)
	last.focus_next = last.get_path_to(first)


## The next row up (`step` -1) or down (+1) that has a cell in `column`, or the cell itself
## at the end of the list.
func _grid_step(grid: Array[Array], row: int, column: int, step: int) -> Control:
	var at := row + step
	while at >= 0 and at < grid.size():
		var cell := grid[at][column] as Control
		if cell != null:
			return cell
		at += step
	return grid[row][column] as Control


func _focusable(control: Control) -> Control:
	if control == null or control.focus_mode == Control.FOCUS_NONE:
		return null
	return control


func _queue_rebuild(focus: StringName = &"") -> void:
	if not String(focus).is_empty():
		_focus_after_rebuild = focus
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _heading(key: String) -> void:
	var item := MenuStyle.label(L10n.t(key), MenuStyle.HEADING_SIZE, _factor, MenuStyle.ACCENT)
	item.uppercase = false
	_rows.add_child(item)


func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_rows.add_child(row)
	var caption := MenuStyle.paragraph(L10n.t(label_key), MenuStyle.BODY_SIZE, _factor)
	caption.size_flags_stretch_ratio = 1.0
	row.add_child(caption)
	return row


## A choice that cycles: Enter/A moves to the next option, ←/→ move either way.
func _choice_row(id: StringName, label_key: String, options: Array, current: int) -> void:
	var row := _row(label_key)
	var button := MenuStyle.entry_button("", MenuStyle.BODY_SIZE, _factor)
	button.name = String(id)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.0
	button.set_meta(&"options", options)
	button.set_meta(&"index", clampi(current, 0, maxi(options.size() - 1, 0)))
	_show_choice(button)
	button.pressed.connect(_cycle.bind(id, 1))
	button.gui_input.connect(_on_choice_input.bind(id))
	row.add_child(button)
	_controls[id] = button


func _show_choice(button: Button) -> void:
	var options: Array = button.get_meta(&"options", [])
	var index := int(button.get_meta(&"index", 0))
	if options.is_empty():
		button.text = ""
		return
	var option: Dictionary = options[index]
	button.text = "‹  %s  ›" % String(option.get("label", ""))


func _volume_row(key: StringName) -> void:
	var id := StringName("volume_%s" % key)
	var row := _row("settings.volume_%s" % key)
	var holder := HBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override(&"separation", 12)
	row.add_child(holder)
	var slider := HSlider.new()
	slider.name = String(id)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(120.0, 24.0)
	slider.value = float(_volume(key))
	var focus_box := StyleBoxFlat.new()
	focus_box.bg_color = Color(0, 0, 0, 0)
	focus_box.border_width_left = 2
	focus_box.border_color = MenuStyle.ACCENT
	slider.add_theme_stylebox_override(&"focus", focus_box)
	holder.add_child(slider)
	var readout := MenuStyle.label("%d%%" % _volume(key), MenuStyle.BODY_SIZE, _factor)
	readout.custom_minimum_size = Vector2(56.0 * _factor, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(readout)
	slider.value_changed.connect(_on_volume_changed.bind(key, readout))
	_controls[id] = slider


func _binding_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_rows.add_child(row)
	var spacer := MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor)
	row.add_child(spacer)
	for key: String in ["settings.column_keyboard", "settings.column_gamepad"]:
		var head := MenuStyle.label(L10n.t(key), MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
		head.custom_minimum_size = Vector2(_binding_width(), 0.0)
		row.add_child(head)


func _binding_row(action: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_rows.add_child(row)
	row.add_child(MenuStyle.paragraph(_action_name(action), MenuStyle.BODY_SIZE, _factor))
	for device: StringName in [&"keyboard", &"gamepad"]:
		var id := _bind_id(action, device)
		var button := MenuStyle.entry_button(
			_binding_text(action, device), MenuStyle.BODY_SIZE, _factor
		)
		button.name = String(id)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.custom_minimum_size = Vector2(_binding_width(), 0.0)
		var settings := _settings()
		if settings != null and not bool(settings.call("can_rebind", action, device)):
			# Esc stays the keyboard's way back; the cell shows it but is not a control.
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.pressed.connect(start_capture.bind(action, device))
		row.add_child(button)
		_controls[id] = button


func _binding_width() -> float:
	return 150.0 * _factor


func _bind_id(action: StringName, device: StringName) -> StringName:
	return StringName("bind_%s_%s" % [action, device])


func _binding_text(action: StringName, device: StringName) -> String:
	var settings := _settings()
	if settings == null:
		return "—"
	var event: InputEvent = settings.call("primary_event", action, device)
	if event == null:
		return "—"
	return String(settings.call("label_for_event", event))


# --- Options -------------------------------------------------------------------


func _text_size_options() -> Array:
	var out: Array = []
	for value: String in ["standard", "large", "largest"]:
		out.append({"value": value, "label": L10n.t("settings.text_size.%s" % value)})
	return out


func _text_speed_options() -> Array:
	var out: Array = []
	for value: String in ["slow", "normal", "fast", "instant"]:
		out.append({"value": value, "label": L10n.t("settings.text_speed.%s" % value)})
	return out


func _ui_scale_options() -> Array:
	var out: Array = [{"value": "auto", "label": L10n.t("settings.ui_scale.auto")}]
	for value: String in ["100", "125", "150", "200"]:
		out.append({"value": value, "label": "%s%%" % value})
	return out


func _on_off_options() -> Array:
	return [
		{"value": "off", "label": L10n.t("settings.off")},
		{"value": "on", "label": L10n.t("settings.on")},
	]


func _language_options() -> Array:
	var out: Array = []
	for locale: String in L10n.available_locales():
		out.append({"value": locale, "label": L10n.locale_name(locale)})
	return out


func _current(id: StringName) -> int:
	var settings := _settings()
	match id:
		&"text_size":
			return _index_of(_text_size_options(), _setting_string(settings, "get_text_size", "standard"))
		&"text_speed":
			return _index_of(_text_speed_options(), _setting_string(settings, "get_text_speed", "normal"))
		&"ui_scale":
			return _index_of(_ui_scale_options(), _setting_string(settings, "get_ui_scale", "auto"))
		&"fullscreen":
			return 1 if _is_fullscreen() else 0
		&"language":
			return _index_of(_language_options(), L10n.current)
	return 0


func _setting_string(settings: Node, method: String, fallback: String) -> String:
	if settings == null or not settings.has_method(method):
		return fallback
	return String(settings.call(method))


func _index_of(options: Array, value: String) -> int:
	for index in options.size():
		if String((options[index] as Dictionary).get("value", "")) == value:
			return index
	return 0


# --- Changing things -----------------------------------------------------------


func _on_choice_input(event: InputEvent, id: StringName) -> void:
	if event.is_action_pressed(&"ui_left", true):
		accept_event()
		_cycle(id, -1)
	elif event.is_action_pressed(&"ui_right", true):
		accept_event()
		_cycle(id, 1)


## Moves a choice by `step` and applies it.
func cycle(id: StringName, step: int) -> void:
	_cycle(id, step)


func _cycle(id: StringName, step: int) -> void:
	var button := _controls.get(id) as Button
	if button == null:
		return
	var options: Array = button.get_meta(&"options", [])
	if options.is_empty():
		return
	var index := posmod(int(button.get_meta(&"index", 0)) + step, options.size())
	button.set_meta(&"index", index)
	_show_choice(button)
	_apply_choice(id, String((options[index] as Dictionary).get("value", "")))


func _apply_choice(id: StringName, value: String) -> void:
	var settings := _settings()
	match id:
		&"text_size":
			if settings != null:
				settings.call("set_text_size", StringName(value))
		&"text_speed":
			if settings != null:
				settings.call("set_text_speed", StringName(value))
		&"ui_scale":
			if settings != null:
				settings.call("set_ui_scale", StringName(value))
		&"fullscreen":
			var wanted := value == "on"
			if wanted != _is_fullscreen():
				var mode := _display_mode()
				if mode != null:
					mode.call("toggle_fullscreen")
				else:
					# No DisplayMode in this scene: switch the window directly.
					DisplayServer.window_set_mode(
						DisplayServer.WINDOW_MODE_FULLSCREEN if wanted
						else DisplayServer.WINDOW_MODE_WINDOWED
					)
		&"language":
			var loc := get_node_or_null(^"/root/Loc")
			if loc != null:
				loc.call("set_locale", value)
			else:
				L10n.set_locale(value)
				_queue_rebuild(&"language")


func _on_volume_changed(value: float, key: StringName, readout: Label) -> void:
	readout.text = "%d%%" % int(value)
	var settings := _settings()
	if settings != null:
		settings.call("set_volume", key, int(value))


func _on_restore_pressed() -> void:
	var settings := _settings()
	if settings != null:
		settings.call("restore_default_bindings")
	_status.text = L10n.t("settings.restored")


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		_queue_rebuild(&"text_size" if key == &"text_size" else &"")


func _on_bindings_changed() -> void:
	if not is_inside_tree():
		return
	for action: StringName in _rebindable():
		for device: StringName in [&"keyboard", &"gamepad"]:
			var button := _controls.get(_bind_id(action, device)) as Button
			if button != null:
				button.text = _binding_text(action, device)


func _on_device_changed(_device: StringName) -> void:
	_refresh_status_hint()


func _on_locale_changed(_locale: String) -> void:
	_queue_rebuild(&"language" if visible else &"")


func _refresh_status_hint() -> void:
	if _status == null or is_capturing():
		return
	var pad := MenuStyle.using_gamepad(self)
	var keys := {
		"confirm": MenuStyle.key(self, &"ui_accept"),
		"cancel": MenuStyle.key(self, &"ui_cancel"),
	}
	_status.text = L10n.t("settings.hint_pad" if pad else "settings.hint_keyboard", keys)


# --- Capturing a new binding -----------------------------------------------------


func _input(event: InputEvent) -> void:
	if not visible or not is_capturing():
		return
	# While a capture waits, every press belongs to it: none reaches the focused row, the
	# menu behind this screen or the game.
	if event is InputEventKey:
		_capture_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		# A click elsewhere while waiting is not a binding, and not a second capture.
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_capture_pad(event)


func _capture_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
		_cancel_capture()
	elif _capture_device == &"keyboard":
		_finish_capture(key)


func _capture_pad(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	var joy := event as InputEventJoypadButton
	var motion := event as InputEventJoypadMotion
	var decisive := (joy != null and joy.pressed) \
		or (motion != null and absf(motion.axis_value) >= 0.6)
	if not decisive:
		return
	if _capture_device == &"gamepad":
		_finish_capture(event)
		return
	# The controller during a keyboard capture: the player has changed hands, and a pad has
	# no Esc. The wait ends here instead of leaving the pad dead until the timeout.
	_cancel_capture()
	var settings := _settings()
	if settings != null:
		settings.call("set_input_device", &"gamepad")


func _process(_delta: float) -> void:
	if is_capturing() and Time.get_ticks_msec() > _capture_deadline_msec:
		_cancel_capture()
		_status.text = L10n.t("settings.capture_timeout")


func _finish_capture(event: InputEvent) -> void:
	var action := _capture_action
	var device := _capture_device
	_capture_action = StringName()
	_capture_device = StringName()
	var settings := _settings()
	if settings == null:
		return
	var result: Dictionary = settings.call("rebind", action, event)
	if bool(result.get("ok", false)):
		_status.text = L10n.t(
			"settings.rebound",
			{"action": _action_name(action), "key": String(settings.call("label_for_event", event))}
		)
	else:
		var reason := String(result.get("reason", ""))
		if reason == "conflict":
			_status.text = L10n.t(
				"settings.conflict",
				{"action": _action_name(StringName(result.get("conflict", &"")))}
			)
		else:
			_status.text = L10n.t("settings.refused")
	_on_bindings_changed()
	# Keep the hand where it was: the same button keeps the focus.
	call_deferred("focus_row", _bind_id(action, device))


func _cancel_capture() -> void:
	if not is_capturing():
		return
	_capture_action = StringName()
	_capture_device = StringName()
	_on_bindings_changed()
	_refresh_status_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_capturing():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	# The settings screen owns the input while it is up.
	if event is InputEventKey or event is InputEventJoypadButton:
		if not event.is_action_pressed(&"toggle_language") \
				and not event.is_action_pressed(&"toggle_fullscreen"):
			get_viewport().set_input_as_handled()


# --- Layout --------------------------------------------------------------------


func _fit() -> void:
	if _panel == null or _scroll == null:
		return
	var view := get_viewport_rect().size
	var width := minf(view.x - OUTER_MARGIN * 2.0, PANEL_MAX_WIDTH * maxf(_factor, 1.0))
	var height := view.y - OUTER_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(maxf(width, 320.0), maxf(height, 240.0))


# --- Helpers -------------------------------------------------------------------


func _rebindable() -> Array[StringName]:
	var settings := _settings()
	var out: Array[StringName] = []
	if settings == null:
		return out
	for action: Variant in (settings.call("get_rebindable_actions") as Array):
		out.append(StringName(action))
	return out


func _action_name(action: StringName) -> String:
	return L10n.t("settings.action.%s" % action)


func _volume(key: StringName) -> int:
	var settings := _settings()
	return int(settings.call("get_volume", key)) if settings != null else 100


func _focused_id() -> StringName:
	var owner_control: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner_control == null:
		return StringName()
	if owner_control == _back:
		return &"back"
	for id: Variant in _controls.keys():
		if _controls[id] == owner_control:
			return StringName(id)
	return StringName()


func _is_fullscreen() -> bool:
	var mode := _display_mode()
	if mode != null:
		return bool(mode.call("is_window_fullscreen"))
	var window_mode := DisplayServer.window_get_mode()
	return window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _display_mode() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"display_mode")


func _settings() -> Node:
	return get_node_or_null(^"/root/Settings") if is_inside_tree() else null
