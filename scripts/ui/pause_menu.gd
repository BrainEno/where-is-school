class_name PauseMenu
extends CanvasLayer
## The menu during play: Esc or Start.
##
## Resume / Notebook / Settings / New game / Return to main menu. The world is paused
## while this layer is open; settings is the same screen the title uses. Scene and save
## transactions belong to Session.
##
## Both the pause entry and the touch HUD ask before returning to the title. At rest the
## answer saves the current run. In a beat, or after a write fails, the question instead
## names the last save (if any). Keeping playing closes the entire pause and resumes the
## same world and conversation.
##
## The look is the title screen's: a dark sheet with a hand-cut edge down the left of the
## paused world, an ember rule in its margin, the heading and entries in the serif, and the
## last save's room and time under the heading.
##
## It never takes Esc from something that is already using it: with the log open, Esc
## closes the log; with a confirmation, the settings or the notebook up, Esc closes those
## first.
##
## The notebook (`JournalPanel`) opens from its entry here or, during play, straight from
## the notebook key: then the menu is only its frame - the world pauses behind it, and
## closing the notebook goes back to the game rather than to this list. The entry says how
## many entries are new since the notebook was last read.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

signal opened
signal closed

# The notebook sits right under Resume, the thing most often opened from here; Settings
# follows it (Down, Down, Enter from Resume) and the way out comes last.
const ENTRIES: Array[StringName] = [&"resume", &"journal", &"settings", &"new_game", &"save_quit"]


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
			self, Rect2(0.0, -8.0, right, view.y + 16.0), Color(MenuStyle.SHEET, 0.96), 13,
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
var _page: Control = null
var _column: VBoxContainer = null
var _touch_scroll: ScrollContainer
var _heading: Label = null
## The last save, under the heading: "Last saved: Corridor · 14:03".
var _status: Label = null
## Why Save and quit did not save, when it could not.
var _notice: Label = null
var _sheet: Sheet = null
var _hint: Label = null
var _entries: Dictionary = {}
var _settings_panel: SettingsPanel = null
var _journal: JournalPanel = null
## True while the menu is open only as the notebook's frame (the notebook key during
## play): closing the notebook then closes the menu too.
var _journal_only := false
var _closing := false
var _confirm: ConfirmPrompt = null
var _was_paused := false
var _previous_focus: Control = null
## What the open question is about: `new_game`, `return_save` or `return_checkpoint`.
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
	_page = Control.new()
	_page.name = "PausePage"
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet = Sheet.new()
	_page.add_child(_sheet)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override(&"separation", 4)
	_touch_scroll = MobileLayout.add_menu_column(_page, _column)
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
	_page.add_child(_hint)

	_settings_panel = SettingsPanel.new()
	_root.add_child(_settings_panel)
	_settings_panel.closed.connect(focus_entry.bind(&"settings"))
	_journal = JournalPanel.new()
	_root.add_child(_journal)
	_journal.closed.connect(_on_journal_closed)
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
	MobileLayout.watch(_root, _fit)
	if MobileLayout.enabled:
		get_window().go_back_requested.connect(_on_mobile_back)
	_refresh_texts()


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	_open(true)
	focus_entry(&"resume")


func _open(show_page: bool) -> void:
	_was_paused = get_tree().paused
	_previous_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	_factor = UiTextScale.current(self)
	UiTextScale.apply(_root, _factor)
	_notice.hide()
	_failure = {}
	_refresh_texts()
	_page.visible = show_page
	_root.show()
	_fit()
	opened.emit()


func close() -> void:
	if not is_open() or _closing:
		return
	_closing = true
	_settings_panel.close()
	_journal.close()
	_journal_only = false
	_pending = &""
	_confirm.hide()
	_root.hide()
	_closing = false
	get_tree().paused = _was_paused
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


## Opens the notebook. `from_play` is the notebook key during play: the menu opens as the
## notebook's frame only, and closing the notebook returns to the game.
func open_journal(from_play: bool = false) -> void:
	if not is_open():
		open()
		_journal_only = from_play
	_ensure_journal_catalog()
	_journal.open()


func get_journal_panel() -> JournalPanel:
	return _journal


## The notebook words its rows from the content the world's dialogue controller has
## already loaded; built once, the first time it is wanted. Its reading progress comes from
## the same controller, which holds the read log.
func _ensure_journal_catalog() -> void:
	var world := _world()
	var dialogue := world.get_node_or_null(^"DialogueController") if world != null else null
	if dialogue != null and dialogue.has_method("get_reading_progress") \
			and not _journal.has_progress_source():
		_journal.set_progress_source(Callable(dialogue, "get_reading_progress"))
	if _journal.has_catalog():
		return
	if dialogue == null or not dialogue.has_method("get_dialogue_library"):
		return
	var library := dialogue.call("get_dialogue_library") as DialogueLibrary
	var inspections := dialogue.call("get_inspection_library") as InspectionLibrary
	if library == null and inspections == null:
		return
	var catalog := JournalCatalog.build(library, inspections)
	for problem: String in catalog.problems():
		push_warning("JournalCatalog: %s" % problem)
	_journal.set_catalog(catalog)


func _on_journal_closed() -> void:
	if _closing:
		return
	if _journal_only:
		close()
		return
	_refresh_texts()
	focus_entry(&"journal")


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
		&"save_quit", &"title":
			request_return_to_title()
		&"settings":
			_settings_panel.open()
		&"journal":
			open_journal()
		&"new_game":
			_pending = &"new_game"
			_confirm.ask(
				L10n.t("menu.confirm_new_game"),
				L10n.t("menu.confirm_yes"),
				L10n.t("menu.confirm_no"),
				L10n.t("menu.confirm_heading_new_game")
			)


## The menu's own world: the scene this layer belongs to.
func _world() -> Node:
	return owner if owner != null else get_parent()


## The same question from the pause page and the mobile shortcut. No write on opening.
func request_return_to_title() -> void:
	if _confirm == null or _confirm.visible or _settings_panel.is_open() or _journal.is_open():
		return
	var session := get_node_or_null(^"/root/Session")
	if session == null or not get_entry(&"save_quit").visible or session.call("is_changing_scene"):
		return
	if not is_open():
		_open(false)
	else:
		_page.hide()
	var status: Dictionary = session.call("get_save_status", _world())
	_ask_return(status, bool(status.get("can_save_now", false)))


func _ask_return(status: Dictionary, write: bool, warning: String = "") -> void:
	_pending = &"return_save" if write else &"return_checkpoint"
	var message := L10n.t("menu.confirm_return_save")
	if not write:
		message = L10n.t("menu.confirm_quit_checkpoint", {"caption": _caption(status)}) \
			if status.get("ok", false) else L10n.t("menu.confirm_quit_no_save")
	if not warning.is_empty():
		message = warning + "\n\n" + message
	_confirm.ask(message, L10n.t("menu.return_to_title"), L10n.t("menu.keep_playing"),
		L10n.t("menu.confirm_heading_quit"))


func _return_to_title(write: bool) -> void:
	var session := get_node_or_null(^"/root/Session")
	if session == null:
		close()
		return
	var report: Dictionary = session.call("save_and_quit", write, _world())
	if report.get("ok", false):
		return # The scene, including this layer, has already left the tree.
	var status: Dictionary = session.call("get_save_status", _world())
	match String(report.get("reason", "")):
		"save_failed":
			# A second, explicit answer is required before leaving without a new save.
			_ask_return(status, false, L10n.t("menu.confirm_quit_failed"))
		"not_at_rest":
			_ask_return(status, false)
		_:
			_ask_return(status, write and bool(status.get("can_save_now", false)),
				L10n.t("menu.return_failed"))


func _on_confirmed() -> void:
	var pending := _pending
	_pending = &""
	match pending:
		&"return_save", &"return_checkpoint":
			_return_to_title(pending == &"return_save")
		&"new_game":
			_on_new_game_confirmed()


func _on_cancelled() -> void:
	var pending := _pending
	_pending = &""
	if pending == &"return_save" or pending == &"return_checkpoint":
		close()
	elif pending == &"new_game":
		focus_entry(&"new_game")


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


func _on_mobile_back() -> void:
	if is_open():
		if _confirm.visible:
			_confirm.cancel()
		elif _settings_panel.is_open():
			_settings_panel.close()
		elif _journal.is_open():
			_journal.close()
		else:
			close()
	else:
		var ui := get_parent().get_node_or_null(^"GameUI") as GameUI
		if ui != null and ui.end_card.visible:
			ui.end_card.get_confirm().cancel()
		elif ui != null and ui.backlog.is_open():
			ui.backlog.close()
		elif not _something_else_owns_cancel():
			open()


func _unhandled_input(event: InputEvent) -> void:
	if is_open():
		if _settings_panel.is_open() or _confirm.visible or _journal.is_open():
			return
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
			return
		if InputMap.has_action(&"journal") and event.is_action_pressed(&"journal"):
			get_viewport().set_input_as_handled()
			open_journal()
			return
		# The world is paused, but autoloads that run anyway must not act through the menu.
		if event is InputEventKey or event is InputEventJoypadButton:
			if not event.is_action_pressed(&"toggle_language") \
					and not event.is_action_pressed(&"toggle_fullscreen"):
				get_viewport().set_input_as_handled()
		return
	var wants_journal := InputMap.has_action(&"journal") and event.is_action_pressed(&"journal")
	if not event.is_action_pressed(&"pause") and not wants_journal:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _something_else_owns_cancel():
		return
	get_viewport().set_input_as_handled()
	if wants_journal:
		open_journal(true)
	else:
		open()


## The log closes on Esc; the session may be swapping worlds.
func _something_else_owns_cancel() -> bool:
	var session := get_node_or_null(^"/root/Session")
	if session != null and bool(session.call("is_changing_scene")):
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
		(_entries[id] as Button).text = L10n.t("menu.return_to_title" if id == &"save_quit" else "menu.%s" % id)
	var unread := _journal.get_unread_count() if _journal != null else 0
	if unread > 0:
		(_entries[&"journal"] as Button).text = L10n.t("menu.journal_unread", {"count": unread})
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
	if MobileLayout.enabled:
		_fit()


func _fit() -> void:
	if _column == null:
		return
	var safe := MobileLayout.safe_rect(_root)
	var view := safe.size
	if MobileLayout.enabled:
		_hint.visible = MenuStyle.using_gamepad(self)
		for entry: Button in _entries.values():
			MobileLayout.enlarge(entry)
	var left := minf(view.x * 0.085, 160.0)
	var width := minf(view.x - left * 2.0, 560.0 * maxf(_factor, 1.0))
	_column.custom_minimum_size = Vector2(width, 0.0)
	_column.size = Vector2(width, 0.0)
	var needed := _column.get_combined_minimum_size().y
	var foot_room := 90.0 if _hint.visible else MobileLayout.EDGE
	var top := maxf(12.0 if MobileLayout.enabled else 24.0, minf(view.y * 0.28, view.y - needed - foot_room))
	var bounds := Rect2(safe.position + Vector2(left, top), Vector2(width, minf(needed + 2.0, view.y - top - foot_room)))
	MobileLayout.place_menu_column(_column, _touch_scroll, bounds)
	_hint.position = safe.position + Vector2(left + 12.0, view.y - 48.0 * maxf(_factor, 1.0))
	_hint.size = Vector2(view.x - left * 2.0, 0.0)
	if _sheet != null:
		_sheet.column_rect = Rect2(bounds.position, Vector2(width, needed)) if _touch_scroll == null else bounds
		_sheet.queue_redraw()
