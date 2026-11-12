class_name TitleScreen
extends Control
## The first screen: the name of the game and a short list.
##
## - a readable save: **Continue**, **New game**, **Settings**, **Quit**;
## - no save: **Start**, **Settings**, **Quit**;
## - a save that cannot be read: the reason and where its copy was kept, then **New game**,
##   **Settings**, **Quit**. There is no Continue, and the file is not touched until the
##   player confirms a new game (ADR 0005 §6).
##
## Starting over when there is something to lose always asks first; the question opens on
## "Cancel". The list is a column of plain text on the same ink as the reading band, set to
## the left the way the band is: a page, not a storefront.

signal entry_activated(id: StringName)

var _factor := 1.0
var _save_state: StringName = &"none"
var _save_report: Dictionary = {}
var _column: VBoxContainer = null
var _entries_box: VBoxContainer = null
var _title: Label = null
var _notice: Label = null
var _hint: Label = null
var _entries: Dictionary = {}
var _settings_panel: SettingsPanel = null
var _confirm: ConfirmPrompt = null
var _starting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_factor = UiTextScale.current(self)
	queue_redraw()
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override(&"separation", 10)
	add_child(_column)
	var game_name := String(ProjectSettings.get_setting("application/config/name", ""))
	_title = MenuStyle.label(game_name, MenuStyle.TITLE_SIZE + 14, _factor, MenuStyle.PAPER)
	_title.name = "Title"
	_column.add_child(_title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 18.0)
	_column.add_child(gap)
	_notice = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.WARN)
	_notice.name = "Notice"
	_notice.visible = false
	_column.add_child(_notice)
	_entries_box = VBoxContainer.new()
	_entries_box.name = "Entries"
	_entries_box.add_theme_constant_override(&"separation", 2)
	_column.add_child(_entries_box)
	_hint = MenuStyle.label("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_hint.name = "Hint"
	add_child(_hint)

	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.closed.connect(_on_settings_closed)
	_confirm = ConfirmPrompt.new()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_new_game_confirmed)
	_confirm.cancelled.connect(_on_new_game_cancelled)

	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_device_changed)
		settings.connect("bindings_changed", _refresh_hint)
	get_viewport().size_changed.connect(_refit)

	refresh_save_state()
	_refit()


## Reads the save again and rebuilds the list. The first entry takes the focus.
func refresh_save_state() -> void:
	var session := get_node_or_null(^"/root/Session")
	if session != null and session.has_method("inspect_save"):
		_save_report = session.call("inspect_save")
	else:
		_save_report = {"state": &"none"}
	_save_state = StringName(_save_report.get("state", &"none"))
	_build_entries()
	focus_entry(get_entry_ids()[0])


func get_save_state() -> StringName:
	return _save_state


## Entry ids in the order they are shown: `continue`, `new_game`, `settings`, `quit`.
func get_entry_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child in _entries_box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			ids.append(StringName(child.name))
	return ids


func get_entry(id: StringName) -> Button:
	return _entries.get(id) as Button


func get_settings_panel() -> SettingsPanel:
	return _settings_panel


func get_confirm() -> ConfirmPrompt:
	return _confirm


func get_notice_text() -> String:
	return _notice.text if _notice != null and _notice.visible else ""


func get_column() -> VBoxContainer:
	return _column


func focus_entry(id: StringName) -> void:
	var entry := get_entry(id)
	if entry != null and entry.is_inside_tree():
		entry.grab_focus()


## The same thing a click, Enter or A on the entry does.
func activate(id: StringName) -> void:
	entry_activated.emit(id)
	match id:
		&"continue":
			var session := get_node_or_null(^"/root/Session")
			if session != null:
				session.call("continue_game")
		&"new_game":
			if _save_state == &"none":
				_start_new_game()
			else:
				_ask_new_game()
		&"settings":
			_settings_panel.open()
		&"quit":
			var session := get_node_or_null(^"/root/Session")
			if session != null:
				session.call("quit_game")
			else:
				get_tree().quit()


func _build_entries() -> void:
	for child in _entries_box.get_children():
		_entries_box.remove_child(child)
		child.queue_free()
	_entries.clear()
	var ids: Array[StringName] = []
	if _save_state == &"valid":
		ids.append(&"continue")
	ids.append(&"new_game")
	ids.append(&"settings")
	ids.append(&"quit")
	for id: StringName in ids:
		var entry := MenuStyle.entry_button(_entry_text(id), MenuStyle.ENTRY_SIZE, _factor)
		entry.name = String(id)
		entry.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry.pressed.connect(activate.bind(id))
		_entries_box.add_child(entry)
		_entries[id] = entry
	_refresh_texts()


func _entry_text(id: StringName) -> String:
	if id == &"new_game" and _save_state == &"none":
		return L10n.t("menu.start")
	return L10n.t("menu.%s" % id)


func _refresh_texts() -> void:
	for id: Variant in _entries.keys():
		var entry := _entries[id] as Button
		entry.text = _entry_text(StringName(id))
	if _save_state == &"broken":
		var lines := PackedStringArray([L10n.t("menu.save_unreadable")])
		var detail := String(_save_report.get("detail", ""))
		if not detail.is_empty():
			lines.append(detail)
		var copy := String(_save_report.get("quarantined_to", ""))
		if not copy.is_empty():
			lines.append(L10n.t("save.error.quarantined", {"path": copy}))
		_notice.text = "\n".join(lines)
		_notice.visible = true
	else:
		_notice.text = ""
		_notice.visible = false
	_refresh_hint()


func _refresh_hint() -> void:
	if _hint == null:
		return
	if MenuStyle.using_gamepad(self):
		_hint.text = L10n.t("menu.hint_pad", {"language": MenuStyle.key(self, &"toggle_language")})
	else:
		_hint.text = L10n.t(
			"menu.hint_keyboard", {"language": MenuStyle.key(self, &"toggle_language")}
		)


func _ask_new_game() -> void:
	var key := "menu.confirm_new_game_broken" if _save_state == &"broken" else "menu.confirm_new_game"
	_confirm.ask(L10n.t(key), L10n.t("menu.confirm_yes"), L10n.t("menu.confirm_no"))


func _on_new_game_confirmed() -> void:
	_start_new_game()


func _on_new_game_cancelled() -> void:
	focus_entry(&"new_game")


func _start_new_game() -> void:
	if _starting:
		return
	_starting = true
	for entry: Button in _entries.values():
		entry.disabled = true
	var session := get_node_or_null(^"/root/Session")
	if session == null:
		var error := get_tree().change_scene_to_file("res://scenes/main/main.tscn")
		if error != OK:
			_show_start_error("Could not open the game scene (error %d)." % error)
		return
	# Session owns the whole new game, including the hand-off to the opening (step 8 of
	# its transaction in game_session.gd): the old save stays staged until the opening is
	# really on screen, and only then is it discarded and are writes released. Entering
	# the opening from here, after Session had already committed, skipped that step and
	# left a failed hand-off with nothing to roll back to.
	#
	# No world is passed: on the title screen Session finds none (the title is not a
	# world), so nothing here is freed by the transaction, and a failure stays on this
	# screen (Session's rollback keeps the title as the current scene). The success path
	# frees this screen with the scene change, so the call is not awaited: the outcome
	# arrives as `new_game_failed`, the same way the pause menu and the end card hear it.
	if not session.is_connected("new_game_failed", _on_new_game_failed):
		session.connect("new_game_failed", _on_new_game_failed, CONNECT_ONE_SHOT)
	var immediate: Variant = session.call("start_new_game")
	if immediate is Dictionary and String((immediate as Dictionary).get("reason", "")) == "busy":
		# Refused before it started, so no signal follows.
		if session.is_connected("new_game_failed", _on_new_game_failed):
			session.disconnect("new_game_failed", _on_new_game_failed)
		_show_start_error(String((immediate as Dictionary).get("detail", "")))


func _on_new_game_failed(report: Dictionary) -> void:
	if not is_inside_tree():
		return
	_show_start_error(String(report.get("detail", report.get("reason", "Unknown error."))))


func _show_start_error(detail: String) -> void:
	_starting = false
	for entry: Button in _entries.values():
		entry.disabled = false
	_notice.text = detail if not detail.is_empty() else "The new game could not be started. Please try again."
	_notice.visible = true
	_refit()
	focus_entry(&"new_game")


func _draw() -> void:
	# A spare, stage-like horizon: a single ground plane and one distant structure,
	# deliberately quiet behind the text rather than an illustrated scene.
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, view), MenuStyle.INK)
	var horizon_y := view.y * 0.59
	var line := Color(MenuStyle.ACCENT, 0.14)
	draw_line(Vector2(view.x * 0.59, horizon_y), Vector2(view.x * 0.96, horizon_y), line, 1.0)
	draw_line(Vector2(view.x * 0.79, horizon_y), Vector2(view.x * 0.79, horizon_y - view.y * 0.13), Color(MenuStyle.ACCENT, 0.17), 1.0)
	draw_line(Vector2(view.x * 0.76, horizon_y - view.y * 0.13), Vector2(view.x * 0.82, horizon_y - view.y * 0.13), Color(MenuStyle.ACCENT, 0.17), 1.0)
	draw_line(Vector2(view.x * 0.07, view.y * 0.20), Vector2(view.x * 0.11, view.y * 0.20), Color(MenuStyle.ACCENT, 0.52), 1.0)
	draw_line(Vector2(view.x * 0.07, view.y * 0.20), Vector2(view.x * 0.07, view.y * 0.24), Color(MenuStyle.ACCENT, 0.52), 1.0)


func _on_settings_closed() -> void:
	focus_entry(&"settings")


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()
	_refit()


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		_factor = UiTextScale.current(self)
		UiTextScale.apply(_column, _factor)
		UiTextScale.apply(_hint, _factor)
		_refit()


func _on_device_changed(_device: StringName) -> void:
	_refresh_hint()


func _fit() -> void:
	if _column == null:
		return
	var view := get_viewport_rect().size
	var factor := maxf(_factor, 1.0)
	# The reading band's left margin; the column a little above the middle, lifted when a
	# notice and the largest text size need the room, never into the hint line.
	var left := minf(view.x * 0.085, 160.0)
	var width := minf(view.x - left * 2.0, 720.0 * factor)
	_column.custom_minimum_size = Vector2(width, 0.0)
	_column.size = Vector2(width, 0.0)
	var needed := _column.get_combined_minimum_size().y
	var hint_room := 64.0 * factor
	var top := minf(view.y * 0.28, view.y - hint_room - needed - 12.0)
	_column.position = Vector2(left, maxf(top, 24.0))
	_hint.position = Vector2(left + 12.0, view.y - 48.0 * factor)
	_hint.size = Vector2(view.x - left * 2.0, 0.0)


## Wrapped text knows its height only after a layout pass, so the fit runs once more.
func _refit() -> void:
	_fit()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree():
		_fit()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_panel.is_open() or _confirm.visible:
		return
	# A focus that was lost to a click on the background comes back on the next key.
	if get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down") \
				or event.is_action_pressed(&"ui_accept"):
			get_viewport().set_input_as_handled()
			focus_entry(get_entry_ids()[0])
