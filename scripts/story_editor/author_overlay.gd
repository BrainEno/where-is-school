extends CanvasLayer
## Detached drawer and trial; leaves the real controller and its state alone.

const Form := preload("res://scripts/story_editor/author_form.gd")
const Catalog := preload("res://scripts/story_editor/author_catalog.gd")
const Preview := preload("res://scripts/story_editor/branch_preview.gd")
const Exchange := preload("res://scripts/story_editor/author_exchange.gd")
const LauncherTouch := preload("res://scripts/story_editor/launcher_touch.gd")
const KeyboardArea := preload("res://scripts/story_editor/keyboard_area.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const PanelScene := preload("res://scenes/ui/dialogue_panel.tscn")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const EDIT_DELAY := 0.32
const CONFIRM_MSEC := 4_000

var store: Store
var show_launcher := true
var _controller: DialogueController
var _ui: GameUI
var _entry: Button
var _guard: Control
var _panel: DialoguePanel
var _drawer: Form
var _catalog: Catalog
var _preview: Preview
var _exchange: Exchange
var _back: Button
var _timer: Timer
var _last_metrics := Rect2()
var _open := false
var _trial := false
var _original := false
var _clear_until := 0
var _leave_until := 0
var _launcher := LauncherTouch.new()
var _live_tint: Color
var _mode := "text"
var _pending_text := false
var _save_failed := false


func _ready() -> void:
	name = "AuthorOverlay"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controller = get_parent().get_node_or_null(^"DialogueController") as DialogueController
	_ui = get_parent().get_node_or_null(^"GameUI") as GameUI
	_entry = _button("EditStory", "剧情编辑", open_editor)
	_entry.hide()
	_entry.add_theme_font_override("font", Form.make_font(_entry.get_theme_default_font()))
	_guard = Control.new()
	_guard.name = "FrozenWorld"
	_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	_guard.hide()
	add_child(_guard)
	MobileLayout.watch(_entry, _fit)
	_fit()


func _build_editor() -> void:
	_drawer = Form.new()
	_drawer.picked.connect(_picked)
	_drawer.action.connect(_action)
	_drawer.buffer_changed.connect(_dirty)
	add_child(_drawer)
	_catalog = Catalog.new(_drawer)
	_drawer.query_changed.connect(_catalog.search)
	_panel = PanelScene.instantiate() as DialoguePanel
	_panel.name = "AuthorDialoguePreview"
	_panel.instant_reveal = true
	_panel.preview_only = true
	_panel.theme = _drawer.theme
	add_child(_panel)
	# The drawer stays above dialogue buttons; the trial hides the drawer entirely.
	move_child(_panel, _guard.get_index() + 1)
	_preview = Preview.new(_panel)
	_preview.ended.connect(_trial_ended)
	_panel.advance_requested.connect(func() -> void:
		if _trial:
			_preview.advance()
	)
	_panel.choice_selected.connect(func(index: int) -> void:
		if _trial:
			_preview.choose(index)
		elif not _original and _mode == "text":
			var choices: Array = Patch.choices_at(_catalog.selected_node())
			if index < choices.size():
				_picked("field", choices[index]["id"])
	)
	_back = _button("BackToDraft", "返回编辑", _end_trial)
	_back.add_theme_font_override("font", _drawer.theme.default_font)
	_back.hide()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.ignore_time_scale = true
	_timer.timeout.connect(_flush)
	add_child(_timer)
	_exchange = Exchange.new()
	_exchange.exported.connect(_export_finished)
	_exchange.edited.connect(_native_edited)
	_exchange.notice.connect(_status)
	add_child(_exchange)


func _button(id: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(&"normal", MenuStyle.panel_style())
	button.pressed.connect(callback)
	add_child(button)
	return button


## True while the drawer owns the screen. The pause menu and the tests ask before
## closing or re-opening it.
func is_editing() -> bool:
	return _open


## The pause menu's editor entry opens the drawer while the menu's own pause is in effect,
## so the drawer must accept that pause as its own. The menu closes on the same click, and
## `open_editor()` replaces that pause with the editor's.
func can_open() -> bool:
	return is_instance_valid(_ui) and _ui.is_node_ready() and _controller != null \
		and (not get_tree().paused or _pause_owner()) and not _ui.fade.visible \
		and not _ui.end_card.visible and not _ui.backlog.is_open() and not _ui.check_overlay.visible


## True when the only thing pausing the tree is the pause menu this drawer replaces.
func _pause_owner() -> bool:
	var menu := get_parent().get_node_or_null(^"PauseMenu")
	return menu != null and menu.has_method("is_open") and bool(menu.call("is_open"))


func _allowed() -> bool:
	return can_open() and not get_tree().paused


func _process(_delta: float) -> void:
	_entry.visible = show_launcher and not _open and _allowed()
	if _open and is_instance_valid(_drawer):
		var usable := _usable_rect()
		if _last_metrics != usable:
			_fit()


func open_editor() -> void:
	if _open or not _allowed() or store == null:
		return
	if _drawer == null:
		_build_editor()
	_open = true
	_entry.hide()
	get_tree().paused = true
	_guard.show()
	_live_tint = _ui.dialogue_panel.modulate
	_ui.dialogue_panel.modulate.a = 0.0
	_drawer.show()
	_drawer.set_search(false)
	_drawer.set_blocked(not store.blocked.is_empty())
	_select_from_live()
	_fit()


func _select_from_live() -> void:
	_catalog.store = store
	_save_failed = store.has_save_error()
	_original = false
	_catalog.locate_live(_controller)
	var saved := store.buffer
	var saved_mode := String(saved.get("mode", "text"))
	var unfinished := saved_mode != "text" or bool(saved.get("dirty", false))
	var use_live := not unfinished and not _save_failed and not _catalog.live.is_empty()
	_catalog.select_address(_catalog.live if use_live else saved)
	var requested := _catalog.address()
	_catalog.sync()
	var restore := unfinished and requested == _catalog.address()
	match saved_mode:
		"text": restore = restore and not _catalog.selected_node().is_empty()
		"insert": restore = restore and Patch.can_insert(_catalog.selected_node())
		"choice": restore = restore and Patch.can_add_choice(_catalog.selected_node())
		"followup": restore = restore and not _catalog.choice.is_empty()
		_: restore = false
	# Never put a stale structural form's text into a different, writable field.
	_mode = saved_mode if restore else "text"
	_pending_text = restore and _mode == "text"
	_prepare_form(saved if restore else {})
	_render()
	var note := store.recovery_notice()
	if unfinished:
		var form_note := "已恢复未完成的编辑。" if restore else "未恢复原表单：目标已变更。"
		note = form_note if note.is_empty() else note + "\n" + form_note
	_status(note)


func _prepare_form(backing: Dictionary = {}) -> void:
	var value := _catalog.stored_text() if _mode == "text" else ""
	var fields := backing.duplicate()
	fields["replace_placeholder"] = _catalog.choice.is_empty() and store.is_placeholder(_catalog.chapter, _catalog.conversation, _catalog.node)
	_drawer.set_mode(_mode, String(backing.get("text", value)), fields)
	_drawer.set_speakers(_catalog.nodes(), String(backing.get("speaker", _catalog.selected_node().get("speaker", ""))))
	_drawer.round_context.text = "节点：%s" % _catalog.node
	if _mode == "followup":
		_drawer.round_context.text = "选项：%s\n本轮结束后接回原去向。" % Catalog.snippet(_catalog.stored_text())
	_targets(String(backing.get("target", "")))
	_controls()


func _targets(selection: String) -> void:
	_drawer.set_targets(store.choice_targets(_catalog.chapter, _catalog.conversation, _catalog.node) if _mode == "choice" else [], selection)


func _picked(field: String, value: String) -> void:
	if _exchange.is_busy():
		if field == "line":
			_drawer.restore_round_selection()
		else:
			_catalog.sync()
		return
	_clear_until = 0
	_leave_until = 0
	if field in ["speaker", "target", "new_reply", "line"]:
		if field == "line":
			_drawer.select_round_line(value.to_int())
		if field == "new_reply":
			_targets(_drawer.selected("target"))
		_dirty()
		return
	if field == "match":
		_jump_to(_catalog.search_address(value))
	elif _can_navigate():
		_catalog.pick(field, value)
		_refresh_selection()
	else:
		_catalog.sync()


func _jump_to(address: Dictionary) -> void:
	if address.is_empty() or not _can_navigate():
		_catalog.search(_catalog.query)
		return
	_catalog.select_address(address)
	_drawer.set_search(false)
	_refresh_selection()


func _can_navigate() -> bool:
	if _mode != "text":
		_status("请保存新增或取消当前表单，再切换位置。")
		return false
	return _flush()


func _refresh_selection() -> void:
	_catalog.sync()
	_prepare_form()
	_render()
	_save()


func _dirty() -> void:
	if not _open or _trial or not store.blocked.is_empty():
		return
	if _mode == "text" and not _pending_text and _drawer.body.text == _catalog.stored_text():
		return
	_clear_until = 0
	_leave_until = 0
	_pending_text = _mode == "text"
	_drawer.status.text = "正在保存草稿…"
	_controls()
	_timer.start(EDIT_DELAY)


func _flush() -> bool:
	if not _open or _trial or not store.blocked.is_empty():
		return true
	_timer.stop()
	# TextEdit queues text_changed. A selection/close in the same frame must not
	# drop the text even if that notification hasn't reached the debounce yet.
	_pending_text = _mode == "text" and _drawer.body.text != _catalog.stored_text()
	if _pending_text:
		if not store.set_text(_catalog.chapter, _catalog.conversation, _catalog.node, _catalog.choice, _drawer.body.text):
			_save("未应用：" + store.error)
			return false
		_pending_text = false
		_original = false
		_catalog.sync() # Refresh labels without replacing the body or moving its caret.
		_render()
	return _save()


func _save(note: String = "") -> bool:
	store.buffer = _catalog.address().merged({"mode": _mode, "dirty": _pending_text})
	if _pending_text or _mode != "text":
		store.buffer.merge(_drawer.capture_buffer())
	_save_failed = not store.save_editor_state()
	_status("输入仍在编辑器中；可重试保存。" if _save_failed else note)
	return not _save_failed


func _status(note: String = "") -> void:
	if _drawer == null:
		return
	var report := "%d 项修改%s" % [store.change_count(), " · 未导出" if store.is_unexported() else ""]
	if store.placeholder_count() > 0:
		report += " · %d 句占位待补写" % store.placeholder_count()
	if _pending_text:
		report += " · 本次输入未应用"
	if _original and not _preview.has_line():
		report = "原文没有这条草稿新增台词。\n" + report
	if not store.blocked.is_empty():
		report = store.blocked
	var lines := PackedStringArray()
	if _save_failed:
		lines.append(store.save_problem())
	if not note.is_empty():
		lines.append(note)
	lines.append(report)
	_drawer.status.text = "\n".join(lines)
	_controls()


func _controls() -> void:
	var node := _catalog.selected_node()
	_drawer.button("current_line").disabled = _catalog.live.is_empty() or _catalog.live == _catalog.address()
	_drawer.button("cancel").disabled = _mode == "text" and not _pending_text
	_drawer.button("insert").disabled = _mode != "text" or not Patch.can_insert(node)
	_drawer.button("choice").disabled = _mode != "text" or not Patch.can_add_choice(node)
	var first := store.first_followup(_catalog.chapter, _catalog.conversation, _catalog.node, _catalog.choice)
	_drawer.button("followup").disabled = _catalog.choice.is_empty() or not store.blocked.is_empty()
	_drawer.button("followup").text = "添加后续" if first.is_empty() else "追加后续"
	_drawer.button("show_followup").visible = not first.is_empty()
	_drawer.round_placeholder.disabled = _exchange.is_busy()
	_drawer.button("undo").disabled = not store.can_undo() or _mode != "text"
	_drawer.button("clear").disabled = store.change_count() == 0 or _mode != "text"
	_drawer.button("trial").disabled = _mode != "text" or _catalog.conversation.is_empty() or not store.blocked.is_empty()
	_drawer.button("trial_here").disabled = _drawer.button("trial").disabled or not _preview.has_line()
	_drawer.button("original").disabled = not store.blocked.is_empty()
	_drawer.button("export").disabled = not store.has_exportable_changes() or _exchange.is_busy()
	_drawer.button("export").text = "导出已应用" if _mode != "text" or _pending_text else "导出 JSON"


func _action(id: String) -> void:
	if _exchange.is_busy():
		return
	if id != "clear":
		_clear_until = 0
	if id != "close":
		_leave_until = 0
	if id not in ["close", "export", "keyboard"] and not store.blocked.is_empty():
		return
	match id:
		"keyboard": _drawer.hide_keyboard()
		"close": close_editor()
		"current_line": _jump_to(_catalog.live)
		"find":
			if _drawer.toggle_search():
				_catalog.search(_catalog.query)
		"edit_query": _exchange.edit_field("query", _catalog.query, "查找台词或选项")
		"edit_body":
			_exchange.edit_field("body", _drawer.body.text, _drawer.body_caption())
			_controls()
		"edit_reply": _exchange.edit_field("reply", _drawer.reply.text, "编辑新回应")
		"round_add", "round_remove": _drawer.change_round_size(id == "round_add")
		"show_followup":
			var first := store.first_followup(_catalog.chapter, _catalog.conversation, _catalog.node, _catalog.choice)
			if not first.is_empty() and _can_navigate():
				_original = false
				_catalog.pick("node", first)
				_refresh_selection()
		"insert", "choice", "followup":
			if _mode == "text" and (id != "followup" or not _catalog.choice.is_empty()) and _flush():
				_mode = id
				_prepare_form()
				_save("填写后点「保存新增」。")
		"apply": _apply_structure()
		"apply_text": _apply_text()
		"cancel": _return_to_fields()
		"undo":
			if _flush() and store.undo():
				_original = false
				_return_to_fields("已撤销。")
		"clear": _clear_draft()
		"original":
			_original = not _original
			_render()
			_status("原文仅供对照。输入仍保存到草稿。" if _original else "")
		"trial", "trial_here": _start_trial(id == "trial_here")
		"export": _export_draft()


func _clear_draft() -> void:
	if not _can_navigate():
		return
	var now := Time.get_ticks_msec()
	if _clear_until <= now:
		_clear_until = now + CONFIRM_MSEC
		_status("四秒内再点「清空」确认。可撤销，不修改游戏原文。")
	elif store.reset():
		_clear_until = 0
		_original = false
		_return_to_fields("已清空草稿。可以撤销。")


func _export_draft() -> void:
	_flush()
	if store.has_exportable_changes():
		_drawer.hide_keyboard()
		_exchange.export_draft(store.export_json())
		_controls()


## "Save the text": flush the field and say so. The draft is already saved as it types
## (`EDIT_DELAY`); this is the key that puts the keyboard away and tells the player the
## sentence they just wrote is in the draft, which the phone layout has no other place for.
func _apply_text() -> void:
	if _mode != "text":
		return
	_drawer.hide_keyboard()
	if _flush():
		_status("文字已保存到本机草稿。")


func _apply_structure() -> void:
	if _mode == "text":
		return
	var selection := store.apply_structure(_mode, _catalog.chapter, _catalog.conversation, _catalog.node, _catalog.choice, _drawer.capture_buffer())
	if selection.is_empty():
		_save(store.error)
		return
	_original = false
	_catalog.node = selection["node"]
	_catalog.choice = selection["choice"]
	_return_to_fields("新增已保存，可以试走。")


func _return_to_fields(note: String = "") -> void:
	_drawer.hide_keyboard()
	_pending_text = false
	_mode = "text"
	_catalog.sync()
	_prepare_form()
	_render()
	_save(note)


func _render() -> void:
	if not _trial and _open:
		_drawer.set_preview_source(_original)
		_preview.show_node(store.graph_for(_catalog.chapter, _original), _catalog.conversation, _catalog.node)
		_panel.set_process_unhandled_input(false)
		_fit()


func _start_trial(from_here: bool) -> void:
	if not _can_navigate() or (from_here and not _preview.has_line()):
		return
	_drawer.hide_keyboard()
	_drawer.hide()
	_trial = true
	_back.text = "返回编辑"
	_back.show()
	_panel.set_process_unhandled_input(true)
	_fit()
	var flags: Dictionary = get_node(^"/root/GameState").get_snapshot()
	var knowledge: Dictionary = get_node(^"/root/NarrativeState").to_snapshot()
	var first := _catalog.node if from_here else ""
	if not _preview.start(store.graph_for(_catalog.chapter, _original), _catalog.conversation,
			flags, knowledge, _controller.get_session_seed(), first):
		_end_trial()
		_status("无法开始这段试玩。")


func _trial_ended() -> void:
	_back.text = "试走结束 · 返回编辑"
	_fit()


func _end_trial() -> void:
	_trial = false
	_preview.stop()
	_back.hide()
	_drawer.show()
	_render()


func _native_edited(field: String, text: String) -> void:
	if not _open or _trial:
		return
	if field == "query":
		_catalog.search(text)
		return
	var input := _drawer.reply if field == "reply" else _drawer.body
	input.text = text
	_dirty()
	_flush()


func _export_finished(digest: String, note: String) -> void:
	if not digest.is_empty() and store.blocked.is_empty():
		if _pending_text or _mode != "text":
			note += " 未应用的输入没有导出。"
		store.exported_digest = digest
		if _save(note):
			return
	_status(note)


func close_editor(for_removal: bool = false) -> void:
	if not _open or (_exchange.is_busy() and not for_removal):
		return
	_flush() # Invalid/unfinished work remains in the draft journal, not the preview graph.
	if not for_removal and _save_failed and Time.get_ticks_msec() >= _leave_until:
		_leave_until = Time.get_ticks_msec() + CONFIRM_MSEC
		_status("4 秒内再点「回游戏」；退出应用或关闭编辑会丢稿。")
		return
	_leave_until = 0
	_drawer.hide_keyboard()
	_drawer.hide()
	_trial = false
	_back.hide()
	_preview.stop()
	_guard.hide()
	_open = false
	_ui.dialogue_panel.modulate = _live_tint
	get_tree().paused = false


func _usable_rect() -> Rect2:
	return KeyboardArea.usable_rect(_entry, _open)


func _fit() -> void:
	if _entry == null:
		return
	var area := _usable_rect()
	_last_metrics = area
	MobileLayout.enlarge(_entry)
	_entry.reset_size()
	_entry.position = Vector2(area.get_center().x - _entry.size.x / 2.0, area.position.y)
	if _drawer == null or not _open:
		return
	var compact := MobileLayout.enabled and KeyboardArea.height() > 0
	_drawer.set_keyboard_compact(compact)
	_drawer.fit_touch()
	_back.reset_size()
	MobileLayout.enlarge(_back)
	_back.position = area.position
	var fraction := 0.6 if MobileLayout.enabled else 0.38
	var width := minf(area.size.x, maxf(368.0, area.size.x * fraction))
	_drawer.position = Vector2(area.end.x - width, area.position.y)
	_drawer.size = Vector2(width, area.size.y)
	var preview_width := area.size.x - width - 6.0
	var enough_room := preview_width >= 180.0 and area.size.y >= 210.0
	_panel.set_preview_bounds(Rect2() if _trial else Rect2(area.position, Vector2(preview_width, area.size.y)))
	if not _trial:
		_panel.visible = enough_room and _preview.has_line()


func _input(event: InputEvent) -> void:
	if MobileLayout.enabled and _owns_launcher_input(event):
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _trial:
			_end_trial()
		elif KeyboardArea.height() > 0:
			_drawer.hide_keyboard()
		else:
			close_editor()


## True when the launcher owns this event; the rule itself is `LauncherTouch`.
func _owns_launcher_input(event: InputEvent) -> bool:
	return _launcher.handle(event, _entry, open_editor)


func _unhandled_input(_event: InputEvent) -> void:
	if _open:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_launcher.forget()
		_flush()


func _exit_tree() -> void:
	if _preview != null:
		_preview.stop()
	if _open:
		if is_instance_valid(_ui) and is_instance_valid(_ui.dialogue_panel):
			_ui.dialogue_panel.modulate = _live_tint
		get_tree().paused = false
