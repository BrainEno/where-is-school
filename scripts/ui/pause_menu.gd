class_name PauseMenu
extends CanvasLayer
## The menu during play: Esc or Start.
##
## Resume / Save and quit / Settings / New game. The world is paused while it is open (the
## tree is, and this layer runs anyway); the settings screen is the same one the title
## screen opens. New game asks first and then hands over to `Session.start_new_game()`,
## which stops this world's autosave before anything is deleted.
##
## **Save and quit** saves the run where it stands and goes to the title, where Continue
## picks it up again. It saves only where a save can describe everything (ADR 0005 §4:
## after the prologue, no conversation open, no beat running - `Session.is_at_rest()`).
## Anywhere else, or when the write fails, it does not pretend: it asks whether to leave
## anyway, says which save the next Continue will load, and the safe answer has the focus.
##
## The look is the title screen's: a dark sheet with a hand-cut edge down the left of the
## paused world, an ember rule in its margin, the heading and entries in the serif, and the
## last save's room and time under the heading.
##
## It never takes Esc from something that is already using it: with the log open, Esc
## closes the log; with a confirmation or the settings up, Esc closes those first.

signal opened
signal closed

# Settings stays second (Down, Enter reaches it from Resume) and the way out comes last.
const ENTRIES: Array[StringName] = [&"resume", &"settings", &"new_game", &"save_quit"]


## The paused world behind a wash, and the sheet the menu is set on: dark, its right edge
## cut by hand, an ember rule down the column's margin. It also stops clicks reaching the
## world, as the plain backdrop did.
class Sheet:
	extends Control

	var column_rect := Rect2()

	func _init() -> void:
		name = "Sheet"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var view := size
		draw_rect(Rect2(Vector2.ZERO, view), Color(MenuStyle.INK, 0.6))
		var right := minf(column_rect.end.x + 90.0, view.x)
		MenuStyle.draw_rough_slab(
			self, Rect2(0.0, -8.0, right + 10.0, view.y + 16.0),
			Color(MenuStyle.OCHRE, 0.12), 17, 12.0, false, true
		)
		MenuStyle.draw_rough_slab(
			self, Rect2(0.0, -8.0, right, view.y + 16.0), Color(0.04, 0.047, 0.048, 0.96), 13,
			8.0, false, true
		)
		if column_rect.size.y > 0.0:
			var x := column_rect.position.x - 16.0
			draw_line(
				Vector2(x, column_rect.position.y + 6.0), Vector2(x, column_rect.end.y - 4.0),
				Color(MenuStyle.EMBER, 0.85), 2.0
			)

var _factor := 1.0
var _root: Control = null
var _column: VBoxContainer = null
var _heading: Label = null
## The last save, under the heading: "Last saved: Corridor · 14:03".
var _status: Label = null
## Why Save and quit did not save, when it could not.
var _notice: Label = null
var _sheet: Sheet = null
var _hint: Label = null
var _entries: Dictionary = {}
var _settings_panel: SettingsPanel = null
var _confirm: ConfirmPrompt = null
var _was_paused := false
## What the open question is about: `new_game` or `quit_unsaved`.
var _pending: StringName = &""
## The new game that did not start, while the notice shows it. Kept as the report so a
## language switch renders it again (`NewGameFailureText`).
var _failure: Dictionary = {}


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
	# One face on the sheet: the status, the notice and the hint in the serif too.
	_root.theme = MenuStyle.page_theme()
	add_child(_root)
	_sheet = Sheet.new()
	_root.add_child(_sheet)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override(&"separation", 4)
	_root.add_child(_column)
	_heading = MenuStyle.serif_label("", MenuStyle.TITLE_SIZE, _factor, MenuStyle.PAPER, 0.6, 3)
	_heading.name = "Heading"
	_column.add_child(_heading)
	_status = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_status.name = "Status"
	_column.add_child(_status)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 22.0)
	_column.add_child(gap)
	for id: StringName in ENTRIES:
		var entry := MenuStyle.page_entry("", MenuStyle.ENTRY_SIZE, _factor)
		entry.name = String(id)
		entry.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry.pressed.connect(activate.bind(id))
		_column.add_child(entry)
		_entries[id] = entry
	_notice = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.WARN)
	_notice.name = "Notice"
	_notice.visible = false
	_column.add_child(_notice)
	_hint = MenuStyle.label("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_root.add_child(_hint)

	_settings_panel = SettingsPanel.new()
	_root.add_child(_settings_panel)
	_settings_panel.closed.connect(focus_entry.bind(&"settings"))
	_confirm = ConfirmPrompt.new()
	_root.add_child(_confirm)
	_confirm.confirmed.connect(_on_confirmed)
	_confirm.cancelled.connect(_on_cancelled)

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
	_notice.visible = false
	_failure = {}
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


## The line under the heading, for the tests: the last save, or that there is none.
func get_status_text() -> String:
	return _status.text if _status != null else ""


func get_notice_text() -> String:
	return _notice.text if _notice != null and _notice.visible else ""


func focus_entry(id: StringName) -> void:
	var entry := get_entry(id)
	if entry != null and entry.is_visible_in_tree():
		entry.grab_focus()


func activate(id: StringName) -> void:
	match id:
		&"resume":
			close()
		&"save_quit":
			_save_and_quit()
		&"settings":
			_settings_panel.open()
		&"new_game":
			_pending = &"new_game"
			_confirm.ask(
				L10n.t("menu.confirm_new_game"),
				L10n.t("menu.confirm_yes"),
				L10n.t("menu.confirm_no"),
				L10n.t("menu.confirm_heading_new_game")
			)
		&"title":
			# Kept for callers from before Save and quit: the same thing without the save.
			_quit_without_saving()


## The menu's own world: the scene this layer belongs to.
func _world() -> Node:
	return owner if owner != null else get_parent()


## Saves and leaves when the world is at rest; otherwise says why it cannot and asks.
func _save_and_quit() -> void:
	var session := get_node_or_null(^"/root/Session")
	if session == null:
		return
	var status: Dictionary = session.call("get_save_status", _world())
	if bool(status.get("can_save_now", false)):
		var report: Dictionary = session.call("save_and_quit", true, _world())
		if bool(report.get("ok", false)):
			_root.hide()
			return
		if String(report.get("reason", "")) == "save_failed":
			_ask_quit_unsaved(L10n.t("menu.confirm_quit_failed", {
				"detail": String(report.get("detail", "")),
			}), L10n.t("menu.confirm_heading_save_failed"))
			return
		_show_notice(String(report.get("detail", report.get("reason", ""))))
		return
	var caption := _caption(status)
	if bool(status.get("ok", false)):
		_ask_quit_unsaved(L10n.t("menu.confirm_quit_checkpoint", {"caption": caption}))
	else:
		_ask_quit_unsaved(L10n.t("menu.confirm_quit_no_save"))


func _ask_quit_unsaved(message: String, heading: String = "") -> void:
	_pending = &"quit_unsaved"
	if heading.is_empty():
		heading = L10n.t("menu.confirm_heading_quit")
	_confirm.ask(message, L10n.t("menu.confirm_quit_yes"), L10n.t("menu.confirm_no"), heading)


func _quit_without_saving() -> void:
	var session := get_node_or_null(^"/root/Session")
	if session == null:
		return
	var report: Dictionary = session.call("save_and_quit", false, _world())
	if bool(report.get("ok", false)):
		_root.hide()
	else:
		_show_notice(String(report.get("detail", report.get("reason", ""))))


func _show_notice(text: String) -> void:
	_failure = {}
	_notice.text = text
	_notice.visible = not text.is_empty()
	_fit()


func _on_confirmed() -> void:
	var pending := _pending
	_pending = &""
	match pending:
		&"quit_unsaved":
			_quit_without_saving()
		_:
			_on_new_game_confirmed()


func _on_cancelled() -> void:
	var pending := _pending
	_pending = &""
	focus_entry(&"save_quit" if pending == &"quit_unsaved" else &"new_game")


func _on_new_game_confirmed() -> void:
	var session := get_node_or_null(^"/root/Session")
	if session == null:
		return
	_root.hide()
	# A failure before the world is freed (the save could not be moved aside) leaves this
	# menu alive, and it comes back with the reason. A failure after it ends on the title
	# screen, which reads the report itself; this menu is gone by then, and so is the
	# connection.
	if not session.is_connected("new_game_failed", _on_new_game_failed):
		session.connect("new_game_failed", _on_new_game_failed, CONNECT_ONE_SHOT)
	# The menu's own world: the session switches its autosave off before anything else.
	var immediate: Variant = session.call("start_new_game", _world())
	if immediate is Dictionary and String((immediate as Dictionary).get("reason", "")) == "busy":
		# Refused before it started, so no signal follows.
		if session.is_connected("new_game_failed", _on_new_game_failed):
			session.disconnect("new_game_failed", _on_new_game_failed)
		_reopen_with_failure(immediate as Dictionary)


func _on_new_game_failed(report: Dictionary) -> void:
	if not is_inside_tree():
		return
	var session := get_node_or_null(^"/root/Session")
	if session != null and session.has_method("mark_new_game_failure_shown"):
		session.call("mark_new_game_failure_shown")
	_reopen_with_failure(report)


## Back on screen after a new game that did not start, with the reason and the focus on
## New game: Enter tries again, Resume or Esc goes back to the run that is still there.
## The transaction unpaused the tree to free the world; it did not, so the pause comes back.
func _reopen_with_failure(report: Dictionary) -> void:
	_pending = &""
	_confirm.hide()
	get_tree().paused = true
	_failure = report.duplicate(true)
	_refresh_texts()
	_root.show()
	_notice.text = NewGameFailureText.describe(_failure)
	_notice.visible = true
	_fit()
	focus_entry(&"new_game")


## "Corridor · 11/12 14:03" from a status or peek, or "" when the file says nothing.
static func _caption(status: Dictionary) -> String:
	return MenuStyle.save_caption(
		String(status.get("location_id", "")), int(status.get("saved_at_unix", 0))
	)


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
	_status.text = _status_text()
	if not _failure.is_empty():
		_notice.text = NewGameFailureText.describe(_failure)
	for id: StringName in ENTRIES:
		(_entries[id] as Button).text = L10n.t("menu.%s" % id)
	var keys := {
		"key": MenuStyle.key(self, &"pause"),
		"cancel": MenuStyle.key(self, &"ui_cancel"),
	}
	_hint.text = L10n.t(
		"menu.pause_hint_pad" if MenuStyle.using_gamepad(self) else "menu.pause_hint_keyboard",
		keys
	)


## The last save as the session sees it, without touching the file.
func _status_text() -> String:
	var session: Node = get_node_or_null(^"/root/Session") if is_inside_tree() else null
	if session == null or not session.has_method("get_save_status"):
		return ""
	var status: Dictionary = session.call("get_save_status", _world())
	if not bool(status.get("ok", false)):
		return L10n.t("menu.no_save_yet")
	var caption := _caption(status)
	return L10n.t("menu.last_save", {"caption": caption}) if not caption.is_empty() else ""


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()
	_fit()


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
	if _sheet != null:
		_sheet.column_rect = Rect2(_column.position, Vector2(width, needed))
		_sheet.queue_redraw()
