extends CanvasLayer
## Attached only in the staged author project. Pauses the existing world, draws a
## detached DialoguePanel over it, and leaves the real controller and its state alone.

const Form := preload("res://scripts/story_editor/author_form.gd")
const Preview := preload("res://scripts/story_editor/branch_preview.gd")
const Exchange := preload("res://scripts/story_editor/author_exchange.gd")
const LauncherTouch := preload("res://scripts/story_editor/launcher_touch.gd")
const KeyboardArea := preload("res://scripts/story_editor/keyboard_area.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const PanelScene := preload("res://scenes/ui/dialogue_panel.tscn")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const EDIT_DELAY := 0.32

var store: Store
var _controller: DialogueController
var _ui: GameUI
var _entry: Button
var _guard: Control
var _panel: DialoguePanel
var _drawer: Form
var _preview: Preview
var _exchange: Exchange
var _back: Button
var _timer: Timer
var _last_metrics := Rect2()
var _open := false
var _trial := false
var _original := false
var _clear_armed := false
var _launcher := LauncherTouch.new()
var _live_tint: Color
var _chapter := ""
var _conversation := ""
var _node := ""
var _choice := ""
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
			var choices: Array = Patch.choices_at(_selected_node())
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
	_entry.visible = not _open and _allowed()
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
	_drawer.set_blocked(not store.blocked.is_empty())
	_select_from_live()
	_fit()


func _select_from_live() -> void:
	var live: Dictionary = _controller.get_current_line()
	var saved := store.buffer
	var unfinished: bool = saved.get("mode", "text") != "text" or bool(saved.get("dirty", false))
	if unfinished or _controller.get_mode() != DialogueController.Mode.CONVERSATION:
		_chapter = String(saved.get("chapter", _chapter))
		_conversation = String(saved.get("conversation", _conversation))
		_node = String(saved.get("node", _node))
		_choice = String(saved.get("choice", ""))
	else:
		_conversation = String(live.get("conversation_id", ""))
		_chapter = store.chapter_for(_conversation)
		_node = String(live.get("node_id", ""))
		_choice = ""
	if store.chapter_ids().is_empty():
		_status(store.blocked)
		return
	_catalog()
	var matches: bool = unfinished and saved.get("chapter") == _chapter \
		and saved.get("conversation") == _conversation and saved.get("node") == _node and saved.get("choice", "") == _choice
	var restored := String(saved.get("mode", "text")) if matches else "text"
	if restored == "insert" and not Patch.can_insert(_selected_node()) \
			or restored == "choice" and not Patch.can_add_choice(_selected_node()) \
			or restored == "followup" and _choice.is_empty():
		restored = "text"
	_mode = restored if restored in ["text", "insert", "choice", "followup"] else "text"
	_pending_text = matches and _mode == "text" and bool(saved.get("dirty", false))
	_prepare_form(saved if matches else {})
	_render()
	_status("已恢复未完成的编辑。" if matches else "")


func _choice_options() -> Array:
	var entries := [{"id": "", "label": "正文"}]
	for choice: Dictionary in Patch.choices_at(_selected_node()):
		entries.append({"id": choice["id"], "label": "选项 · " + _snippet(choice["text"])})
	return entries


func _catalog() -> void:
	var chapters := store.chapter_ids()
	if _chapter not in chapters:
		_chapter = chapters[0]
	var conversations := store.conversation_ids(_chapter)
	if _conversation not in conversations:
		_conversation = conversations[0] if not conversations.is_empty() else ""
	var rows := _nodes()
	if not rows.is_empty() and _selected_node().is_empty():
		_node = rows[0]["id"]
	if not _choice.is_empty() and Patch.find_record(Patch.choices_at(_selected_node()), _choice).is_empty():
		_choice = ""
	_drawer.replace_options("chapter", Form.id_options(chapters), _chapter)
	_drawer.replace_options("conversation", Form.id_options(conversations), _conversation)
	var options := []
	for node: Dictionary in rows:
		var label := "%s · %s" % [node["speaker"], _snippet(node.get("text", ""))]
		options.append({"id": node["id"], "label": label if not label.ends_with(" · ") else node["id"]})
	_drawer.replace_options("node", options, _node)
	_drawer.replace_options("field", _choice_options(), _choice)


func _nodes() -> Array:
	return store.nodes_for(_chapter, _conversation)


func _selected_node() -> Dictionary:
	return Patch.find_record(_nodes(), _node)


func _stored_value() -> String:
	return store.editable_text(_chapter, _conversation, _node, _choice)


func _snippet(text: String) -> String:
	return text.replace("\n", " ").left(34)


func _prepare_form(backing: Dictionary = {}) -> void:
	var value := _stored_value() if _mode == "text" else ""
	var fields := backing.duplicate()
	fields["replace_placeholder"] = _choice.is_empty() and store.is_placeholder(_chapter, _conversation, _node)
	_drawer.set_mode(_mode, String(backing.get("text", value)), fields)
	_drawer.set_speakers(_nodes(), String(backing.get("speaker", _selected_node().get("speaker", ""))))
	_drawer.round_context.text = "选项：%s\n逐句填写；本轮结束后接回原去向。" % _snippet(_stored_value())
	_targets(String(backing.get("target", "")))
	_controls()


func _targets(selection: String) -> void:
	_drawer.set_targets(store.choice_targets(_chapter, _conversation, _node) if _mode == "choice" else [], selection)


func _picked(field: String, value: String) -> void:
	if _exchange.is_busy():
		if field == "line":
			_drawer.restore_round_selection()
		else:
			_catalog()
		return
	_clear_armed = false
	if field in ["speaker", "target", "new_reply", "line"]:
		if field == "line":
			_drawer.select_round_line(value.to_int())
		if field == "new_reply":
			_targets(_drawer.selected("target"))
		_dirty()
		return
	if _mode != "text" or not _flush():
		_catalog()
		_status("先保存或取消当前编辑，再切换位置。")
		return
	match field:
		"chapter":
			_chapter = value
			_conversation = ""
			_node = ""
			_choice = ""
		"conversation":
			_conversation = value
			_node = ""
			_choice = ""
		"node":
			_node = value
			_choice = ""
		"field": _choice = value
	_catalog()
	_prepare_form()
	_render()
	_save()


func _dirty() -> void:
	if not _open or _trial or not store.blocked.is_empty():
		return
	_clear_armed = false
	_pending_text = _mode == "text"
	_drawer.status.text = "正在保存草稿…"
	_timer.start(EDIT_DELAY)


func _flush() -> bool:
	if not _open or _trial or not store.blocked.is_empty():
		return true
	_timer.stop()
	# TextEdit queues text_changed. A selection/close in the same frame must not
	# drop the text even if that notification hasn't reached the debounce yet.
	_pending_text = _mode == "text" and _drawer.body.text != _stored_value()
	if _pending_text:
		var was_placeholder := _choice.is_empty() and store.is_placeholder(_chapter, _conversation, _node)
		if not store.set_text(_chapter, _conversation, _node, _choice, _drawer.body.text):
			_save(store.error + "（未应用；已保留输入）")
			return false
		_pending_text = false
		if was_placeholder:
			_catalog() # Refresh the resolved node label, but keep the editor's caret.
		_render()
	return _save()


func _save(note: String = "") -> bool:
	store.buffer = {"chapter": _chapter, "conversation": _conversation, "node": _node,
		"choice": _choice, "mode": _mode, "dirty": _pending_text}
	if _pending_text or _mode != "text":
		store.buffer.merge(_drawer.capture_buffer())
	_save_failed = not store.save_editor_state()
	_status("无法保存到本机；请缩短输入或检查可用空间。" if _save_failed else note)
	return not _save_failed


func _status(note: String = "") -> void:
	if _drawer == null:
		return
	var report := "%d 项修改%s" % [store.change_count(), " · 未导出" if store.is_unexported() else ""]
	if store.placeholder_count() > 0:
		report += " · %d 句占位待补写" % store.placeholder_count()
	if not store.blocked.is_empty():
		report = store.blocked
	_drawer.status.text = report if note.is_empty() else "%s\n%s" % [note, report]
	_controls()


func _controls() -> void:
	var node := _selected_node()
	_drawer.button("insert").disabled = _mode != "text" or not Patch.can_insert(node)
	_drawer.button("choice").disabled = _mode != "text" or not Patch.can_add_choice(node)
	var first := store.first_followup(_chapter, _conversation, _node, _choice)
	_drawer.button("followup").disabled = _choice.is_empty() or not store.blocked.is_empty()
	_drawer.button("followup").text = "添加后续" if first.is_empty() else "追加后续"
	_drawer.button("show_followup").visible = not first.is_empty()
	_drawer.round_placeholder.disabled = _exchange.is_busy()
	_drawer.button("undo").disabled = not store.can_undo() or _mode != "text"
	_drawer.button("clear").disabled = store.change_count() == 0 or _mode != "text"
	_drawer.button("trial").disabled = _conversation.is_empty() or not store.blocked.is_empty()
	_drawer.button("original").disabled = not store.blocked.is_empty()
	_drawer.button("export").disabled = not store.has_exportable_changes() or _exchange.is_busy()


func _action(id: String) -> void:
	if _exchange.is_busy():
		return
	if id != "clear":
		_clear_armed = false
	if id not in ["close", "export", "keyboard"] and not store.blocked.is_empty():
		return
	match id:
		"keyboard": _drawer.hide_keyboard()
		"close": close_editor()
		"edit_body":
			_exchange.edit_field("body", _drawer.body.text, _drawer.body_caption())
			_controls()
		"edit_reply": _exchange.edit_field("reply", _drawer.reply.text, "编辑新回应")
		"round_add", "round_remove": _drawer.change_round_size(id == "round_add")
		"show_followup":
			var first := store.first_followup(_chapter, _conversation, _node, _choice)
			if not first.is_empty() and _mode == "text" and _flush():
				_show_draft()
				_picked("node", first)
		"insert", "choice", "followup":
			if _mode == "text" and (id != "followup" or not _choice.is_empty()) and _flush():
				_mode = id
				_prepare_form()
				_save("填写后点「保存新增」。")
		"apply": _apply_structure()
		"apply_text": _apply_text()
		"cancel": _return_to_fields()
		"undo":
			if _flush() and store.undo():
				_return_to_fields("已撤销。")
		"clear":
			if not _clear_armed:
				_clear_armed = true
				_status("再点一次「清空」将清空当前草稿；不会修改游戏原文。")
			elif store.reset():
				_clear_armed = false
				_return_to_fields("草稿已清空。")
		"original":
			_original = not _original
			_drawer.button("original").text = "看草稿" if _original else "看原文"
			_render()
			_status("当前预览是游戏原文。" if _original else "当前预览是本机草稿。")
		"trial": _start_trial()
		"export":
			if not store.blocked.is_empty() or (_mode == "text" and _flush()):
				_drawer.hide_keyboard()
				_exchange.export_draft(store.export_json())
				_controls()
			else:
				_status("请先保存新增，或取消未完成的修改。")


## "Save the text": flush the field and say so. The draft is already saved as it types
## (`EDIT_DELAY`); this is the key that puts the keyboard away and tells the player the
## sentence they just wrote is in the draft, which the phone layout has no other place for.
func _apply_text() -> void:
	if _mode != "text":
		return
	_drawer.hide_keyboard()
	if _exchange.is_busy() or store.blocked != "":
		return
	_flush()
	if _save_failed:
		return
	_status("文字已保存到草稿；「导出 JSON」把整份草稿给到「文件」。")


func _apply_structure() -> void:
	if _mode == "text":
		return
	var selection := store.apply_structure(_mode, _chapter, _conversation, _node, _choice, _drawer.capture_buffer())
	if selection.is_empty():
		_save(store.error)
		return
	var new_round := _mode == "followup"
	if new_round:
		_show_draft()
	_node = selection["node"]
	_choice = selection["choice"]
	_return_to_fields("后续已保存，可以查看或试走。" if new_round else "结构已通过校验，可以试走。")


func _show_draft() -> void:
	_original = false
	_drawer.button("original").text = "看原文"


func _return_to_fields(note: String = "") -> void:
	_drawer.hide_keyboard()
	_pending_text = false
	_mode = "text"
	_catalog()
	_prepare_form()
	_render()
	_save(note)


func _render() -> void:
	if not _trial and _open:
		_preview.show_node(store.graph_for(_chapter, _original), _conversation, _node)
		_panel.set_process_unhandled_input(false)
		_fit()


func _start_trial() -> void:
	if _mode != "text" or not _flush():
		_status("请先完成编辑，再试走。")
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
	if not _preview.start(store.graph_for(_chapter, _original), _conversation, flags, knowledge, _controller.get_session_seed()):
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
	var input := _drawer.reply if field == "reply" else _drawer.body
	input.text = text
	_dirty()
	_flush()


func _export_finished(digest: String, note: String) -> void:
	if not digest.is_empty() and store.blocked.is_empty():
		store.exported_digest = digest
		_save(note)
	else:
		_status(note)


func close_editor() -> void:
	if not _open or _exchange.is_busy():
		return
	_flush() # Invalid/unfinished work remains in the draft journal, not the preview graph.
	if _save_failed:
		return
	_drawer.hide_keyboard()
	_drawer.hide()
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
		get_tree().paused = false
