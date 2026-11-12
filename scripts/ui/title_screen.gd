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
##
## The page is set like the dialogue column (#125): the name in the serif, emboldened and
## tracked, an ember rule in the margin, the entries in the serif with a slanted ember mark
## when selected, and under Continue the room and the time the save was written. Behind it,
## to the right, one distant building cut out of two colour fields on a bare horizon - a
## spare stage (ART_BIBLE, "Outdoor spaces") drawn in `_draw()`, not an illustration.

signal entry_activated(id: StringName)

var _factor := 1.0
var _save_state: StringName = &"none"
var _save_report: Dictionary = {}
var _column: VBoxContainer = null
var _entries_box: VBoxContainer = null
var _title: Label = null
## The line under Continue: where the save stands and when it was written.
var _continue_detail: Label = null
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
	_title = MenuStyle.serif_label(
		_display_name(), MenuStyle.DISPLAY_SIZE, _factor, MenuStyle.PAPER, 0.7, 4
	)
	_title.name = "Title"
	_column.add_child(_title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 40.0)
	_column.add_child(gap)
	_notice = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.WARN)
	_notice.name = "Notice"
	_notice.visible = false
	_column.add_child(_notice)
	_entries_box = VBoxContainer.new()
	_entries_box.name = "Entries"
	_entries_box.add_theme_constant_override(&"separation", 4)
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


## "where-is-school" set as a name: words, not a slug, in capitals for the tracking.
static func _display_name() -> String:
	var game_name := String(ProjectSettings.get_setting("application/config/name", ""))
	return game_name.replace("-", " ").replace("_", " ").strip_edges().to_upper()


func _build_entries() -> void:
	for child in _entries_box.get_children():
		_entries_box.remove_child(child)
		child.queue_free()
	_entries.clear()
	_continue_detail = null
	var ids: Array[StringName] = []
	if _save_state == &"valid":
		ids.append(&"continue")
	ids.append(&"new_game")
	ids.append(&"settings")
	ids.append(&"quit")
	for id: StringName in ids:
		var entry := MenuStyle.page_entry(_entry_text(id), MenuStyle.ENTRY_SIZE, _factor)
		entry.name = String(id)
		entry.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry.pressed.connect(activate.bind(id))
		_entries_box.add_child(entry)
		_entries[id] = entry
		if id == &"continue":
			_add_continue_detail()
	_refresh_texts()


## The save's room and time, indented to the entry text and a step quieter. It is not a
## button, so the focus moves straight from Continue to New game.
func _add_continue_detail() -> void:
	var holder := MarginContainer.new()
	holder.name = "ContinueDetail"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override(&"margin_left", 26)
	holder.add_theme_constant_override(&"margin_bottom", 6)
	_continue_detail = MenuStyle.label("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_continue_detail.name = "Detail"
	holder.add_child(_continue_detail)
	_entries_box.add_child(holder)


func get_continue_detail() -> String:
	return _continue_detail.text if _continue_detail != null else ""


func _entry_text(id: StringName) -> String:
	if id == &"new_game" and _save_state == &"none":
		return L10n.t("menu.start")
	return L10n.t("menu.%s" % id)


func _refresh_texts() -> void:
	for id: Variant in _entries.keys():
		var entry := _entries[id] as Button
		entry.text = _entry_text(StringName(id))
	if _continue_detail != null:
		_continue_detail.text = MenuStyle.save_caption(
			String(_save_report.get("location_id", "")), int(_save_report.get("saved_at_unix", 0))
		)
		(_continue_detail.get_parent() as Control).visible = not _continue_detail.text.is_empty()
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
	var keys := {
		"language": MenuStyle.key(self, &"toggle_language"),
		"confirm": MenuStyle.key(self, &"ui_accept"),
	}
	_hint.text = L10n.t(
		"menu.hint_pad" if MenuStyle.using_gamepad(self) else "menu.hint_keyboard", keys
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
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, view), MenuStyle.INK)
	_draw_stage(view)
	MenuStyle.draw_vignette(self, view, Color(0.0, 0.0, 0.0, 0.5))
	_draw_margin()


## The backdrop: a warm cast from the upper right, a bare horizon, and one distant building
## cut from two colour fields, with a pole and a scrap of flag beside it. Everything sits to
## the right of the column, so nothing crosses the text.
func _draw_stage(view: Vector2) -> void:
	var warm := Color(0.2, 0.11, 0.075, 1.0)
	draw_polygon(
		PackedVector2Array([
			Vector2(view.x * 0.45, 0.0), Vector2(view.x, 0.0), Vector2(view.x, view.y * 0.7),
			Vector2(view.x * 0.45, view.y * 0.7),
		]),
		PackedColorArray([MenuStyle.INK, warm, MenuStyle.INK, MenuStyle.INK])
	)
	var horizon := view.y * 0.62
	draw_rect(Rect2(0.0, horizon, view.x, view.y - horizon), MenuStyle.GROUND)
	var block := Rect2(view.x * 0.64, view.y * 0.33, view.x * 0.2, horizon - view.y * 0.33)
	MenuStyle.draw_rough_slab(self, block.grow(4.0), Color(MenuStyle.OCHRE, 0.2), 7, 9.0)
	MenuStyle.draw_rough_slab(self, block, Color(MenuStyle.BRICK, 0.88), 3, 5.0)
	# Two rows of windows, dark and slightly uneven: a school, not a diagram of one.
	var pane := Vector2(block.size.x * 0.09, block.size.y * 0.13)
	for row in range(2):
		for column in range(4):
			var corner := block.position + Vector2(
				block.size.x * (0.12 + 0.21 * float(column)), block.size.y * (0.22 + 0.32 * float(row))
			)
			draw_rect(Rect2(corner, pane), Color(MenuStyle.INK, 0.62 + 0.04 * float(column % 2)))
	var line := Color(MenuStyle.ACCENT, 0.2)
	draw_line(Vector2(view.x * 0.5, horizon), Vector2(view.x * 0.98, horizon), line, 1.0)
	var pole_x := view.x * 0.89
	draw_line(
		Vector2(pole_x, horizon), Vector2(pole_x, view.y * 0.2), Color(MenuStyle.ACCENT, 0.32), 1.5
	)
	MenuStyle.draw_rough_slab(
		self, Rect2(pole_x + 1.0, view.y * 0.2, view.x * 0.028, view.y * 0.03),
		Color(MenuStyle.EMBER, 0.72), 11, 2.0, false, true
	)
	for stroke in range(3):
		var y := horizon + view.y * (0.06 + 0.07 * float(stroke))
		MenuStyle.draw_dry_brush(
			self, Vector2(view.x * (0.56 + 0.05 * float(stroke)), y), Vector2(view.x * 0.97, y),
			Color(MenuStyle.ACCENT, 0.07), 20 + stroke, 5.0
		)


## The ember rule down the margin of the column, and a short one under the name.
func _draw_margin() -> void:
	if _column == null or _title == null or _entries_box == null:
		return
	var origin := get_global_rect().position
	var title_box := _title.get_global_rect()
	title_box.position -= origin
	var entries_box := _entries_box.get_global_rect()
	entries_box.position -= origin
	var x := _column.position.x - 16.0
	draw_line(
		Vector2(x, title_box.position.y + 6.0), Vector2(x, entries_box.end.y - 4.0),
		Color(MenuStyle.EMBER, 0.85), 2.0
	)
	var under := title_box.end.y + 12.0
	MenuStyle.draw_rough_slab(
		self, Rect2(_column.position.x + 4.0, under, 72.0, 4.0), MenuStyle.EMBER, 5, 2.0
	)


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
	queue_redraw()


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
