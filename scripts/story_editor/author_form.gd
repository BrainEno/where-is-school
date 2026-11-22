extends PanelContainer
## The author drawer only owns controls. It sends stable selections to its host;
## the scroll list is not the order of nodes/choices in the content file.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
signal picked(field: String, id: String)
signal action(id: String)
signal buffer_changed

var body: TextEdit
var reply: TextEdit
var new_reply: CheckButton
var round_placeholder: CheckButton
var round_context: Label
var status: Label
var _columns: VBoxContainer
var _toolbar: HBoxContainer
var _footer: HBoxContainer
var _structure: HBoxContainer
var _followup_actions: HBoxContainer
var _round_actions: HBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _rows := {}
var _buttons := {}
var _pickers := {}
var _speakers: Array = []
var _round: Array[Dictionary] = []
var _round_index := 0
var _busy := false
var _mode := "text"
var _compact := false
var _blocked := false
var _native_fields := OS.has_feature("ios")


func _ready() -> void:
	name = "AuthorDrawer"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("20222c")
	style.border_color = Color("83725a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	for side in [SIDE_TOP, SIDE_LEFT, SIDE_BOTTOM, SIDE_RIGHT]:
		style.set_content_margin(side, 9.0)
	add_theme_stylebox_override("panel", style)
	var local_theme := Theme.new()
	local_theme.default_font = make_font(get_theme_default_font())
	local_theme.default_font_size = 22 if MobileLayout.enabled else 19
	theme = local_theme

	_columns = VBoxContainer.new()
	_columns.add_theme_constant_override("separation", 5)
	add_child(_columns)
	_toolbar = _row(_columns)
	var title := Label.new()
	title.text = "剧情编辑 · 中文"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(title)
	_button(_toolbar, "keyboard", "收键盘")
	_button(_toolbar, "close", "回游戏")

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 5)
	_scroll.add_child(_content)
	_picker("chapter", "章节")
	_picker("conversation", "会话")
	_picker("node", "节点")
	_picker("field", "文案")
	_followup_actions = _row(_content)
	_button(_followup_actions, "followup", "添加后续")
	_button(_followup_actions, "show_followup", "查看后续")

	_structure = _row(_content)
	_button(_structure, "insert", "插句")
	_button(_structure, "choice", "加选项")
	_button(_structure, "undo", "撤销")
	_button(_structure, "clear", "清空")

	round_context = Label.new()
	round_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(round_context)
	_picker("line", "后续句")
	_round_actions = _row(_content)
	_button(_round_actions, "round_add", "加一句")
	_button(_round_actions, "round_remove", "删除此句")
	round_placeholder = CheckButton.new()
	round_placeholder.text = "本句先占位"
	round_placeholder.toggled.connect(_round_placeholder_changed)
	_content.add_child(round_placeholder)
	_picker("speaker", "说话人")

	if _native_fields:
		_button(_content, "edit_body", "编辑这个字段")
	body = _text_box("DraftText")
	new_reply = CheckButton.new()
	new_reply.text = "添加新回应"
	new_reply.toggled.connect(_on_reply_toggled)
	_content.add_child(new_reply)
	if _native_fields:
		_button(_content, "edit_reply", "编辑新回应")
	reply = _text_box("ReplyText")
	reply.placeholder_text = "输入新回应"
	_picker("target", "接到")
	var form_actions := _row(_content)
	_rows["form_actions"] = form_actions
	_button(form_actions, "apply", "保存新增")
	# A plain-text edit is saved as it types, but on a phone the keyboard covers the footer
	# and the status line: without a key of its own the player cannot say "done" and put
	# the keyboard away. The same button flushes the draft.
	_button(form_actions, "apply_text", "保存文字")
	_button(form_actions, "cancel", "取消／还原字段")

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 3
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_columns.add_child(status)
	_footer = _row(_columns)
	_button(_footer, "original", "看原文")
	_button(_footer, "trial", "试走")
	_button(_footer, "export", "导出 JSON")
	set_mode("text", "")
	fit_touch()
	if MobileLayout.enabled:
		MobileLayout.setup_scroll(_scroll)
		# On the touch preview, a writable TextEdit still owns its selection gestures.
		if not _native_fields:
			body.mouse_filter = Control.MOUSE_FILTER_STOP
			reply.mouse_filter = Control.MOUSE_FILTER_STOP


static func make_font(base: Font) -> Font:
	var font := FontVariation.new()
	font.base_font = base
	var system := SystemFont.new()
	system.font_names = ["PingFang SC", "Microsoft YaHei UI", "Noto Sans CJK SC", "Noto Sans CJK TC"]
	font.fallbacks = [system]
	return font


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	return row


func _button(parent: Control, id: String, caption: String) -> void:
	var button := Button.new()
	button.name = "Action_" + id
	button.text = caption
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: action.emit(id))
	parent.add_child(button)
	_buttons[id] = button


func _picker(id: String, title: String) -> void:
	var row := _row(_content)
	_rows[id] = row
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 70.0
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = "Pick_" + id
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index: int) -> void:
		if not _busy:
			picked.emit(id, String(picker.get_item_metadata(index)))
	)
	row.add_child(picker)
	_pickers[id] = picker


func _text_box(id: String) -> TextEdit:
	var field := TextEdit.new()
	field.name = id
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.scroll_fit_content_height = false
	field.custom_minimum_size.y = 110.0
	field.virtual_keyboard_enabled = not _native_fields
	if _native_fields:
		field.editable = false
		field.focus_mode = Control.FOCUS_NONE
	field.text_changed.connect(func() -> void:
		if not _busy:
			buffer_changed.emit()
	)
	_content.add_child(field)
	return field


static func id_options(ids: Array) -> Array:
	var rows := []
	for id: String in ids:
		rows.append({"id": id, "label": id})
	return rows


func set_speakers(nodes: Array, selection: String) -> void:
	var ids := []
	for node: Dictionary in nodes:
		if node["speaker"] not in ids:
			ids.append(node["speaker"])
	_speakers = id_options(ids)
	replace_options("speaker", _speakers, selection)
	if _mode == "followup":
		_show_round_line()


func set_targets(nodes: Array, selection: String) -> void:
	var entries := [{"id": "", "label": "回应后结束"}] if new_reply.button_pressed else []
	for node: Dictionary in nodes:
		var snippet := String(node.get("text", "")).replace("\n", " ").left(34)
		entries.append({"id": node["id"], "label": "%s · %s" % [node["id"], snippet]})
	replace_options("target", entries, selection)


func replace_options(key: String, entries: Array, selection: String) -> void:
	var picker: OptionButton = _pickers[key]
	var active := 0
	_busy = true
	picker.clear()
	for entry: Dictionary in entries:
		var index := picker.item_count
		picker.add_item(entry["label"])
		picker.set_item_metadata(index, entry["id"])
		if entry["id"] == selection:
			active = index
	if picker.item_count > 0:
		picker.select(active)
	picker.disabled = picker.item_count == 0
	_busy = false


func selected(key: String) -> String:
	var picker: OptionButton = _pickers[key]
	return String(picker.get_selected_metadata()) if picker.selected >= 0 else ""


func button(id: String) -> Button:
	return _buttons[id]


func set_mode(mode: String, text: String, backing: Dictionary = {}) -> void:
	_mode = mode
	_busy = true
	body.text = text
	# A control is reused for different IDs. Undo must never paste a different
	# node's previously selected text into this one.
	body.clear_undo_history()
	body.placeholder_text = "输入选项文案" if mode == "choice" else "输入对白或旁白"
	if bool(backing.get("replace_placeholder", false)):
		body.placeholder_text = "输入正文以替换占位"
	if mode == "followup":
		_restore_round(backing)
		_scroll.scroll_vertical = 0
	new_reply.button_pressed = bool(backing.get("new_reply", false))
	reply.text = String(backing.get("reply", ""))
	reply.clear_undo_history()
	_busy = false
	_apply_visibility()


func capture_buffer() -> Dictionary:
	if _mode == "followup":
		_remember_round_line()
		return {"lines": _round.duplicate(true), "line": _round_index}
	return {"text": body.text, "reply": reply.text, "speaker": selected("speaker"),
		"target": selected("target"), "new_reply": new_reply.button_pressed}


func select_round_line(index: int) -> void:
	if _mode != "followup" or index < 0 or index >= _round.size() or index == _round_index:
		return
	_remember_round_line()
	_round_index = index
	_show_round_line()


func restore_round_selection() -> void:
	(_pickers["line"] as OptionButton).select(_round_index)


func change_round_size(add: bool) -> void:
	if _mode != "followup":
		return
	if add and _round.size() < Patch.MAX_ROUND_LINES:
		_remember_round_line()
		_round.append({"text": "", "speaker": selected("speaker"), "placeholder": false})
		_round_index = _round.size() - 1
	elif not add and _round.size() > 1:
		_round.remove_at(_round_index)
		_round_index = mini(_round_index, _round.size() - 1)
	else:
		return
	_show_round_line()
	buffer_changed.emit()


func _restore_round(backing: Dictionary) -> void:
	_round.clear()
	var lines: Variant = backing.get("lines")
	if lines is Array:
		for row: Variant in lines.slice(0, Patch.MAX_ROUND_LINES):
			if row is Dictionary:
				_round.append({"speaker": String(row.get("speaker", "")), "text": String(row.get("text", "")),
					"placeholder": bool(row.get("placeholder", false))})
	if _round.is_empty():
		_round.append({"text": "", "speaker": "", "placeholder": false})
	_round_index = clampi(int(backing.get("line", 0)), 0, _round.size() - 1)


func _remember_round_line() -> void:
	_round[_round_index] = {"text": body.text, "speaker": selected("speaker"),
		"placeholder": round_placeholder.button_pressed}


func _show_round_line() -> void:
	var entries := []
	for index in _round.size():
		entries.append({"id": str(index), "label": "第 %d / %d 句" % [index + 1, _round.size()]})
	replace_options("line", entries, str(_round_index))
	var row := _round[_round_index]
	var speaker: String = row["speaker"] if not row["speaker"].is_empty() else selected("speaker")
	replace_options("speaker", _speakers, speaker)
	body.text = row["text"]
	body.clear_undo_history()
	round_placeholder.set_pressed_no_signal(row["placeholder"])
	_set_round_prompt()
	_buttons["round_add"].disabled = _round.size() >= Patch.MAX_ROUND_LINES
	_buttons["round_remove"].disabled = _round.size() <= 1


func body_caption() -> String:
	if _mode == "followup":
		return "编辑占位备注" if round_placeholder.button_pressed else "编辑本句对白"
	return "编辑这个字段"


func _set_round_prompt() -> void:
	body.placeholder_text = "占位备注（可留空）" if round_placeholder.button_pressed else "输入这句对白"
	if _native_fields:
		_buttons["edit_body"].text = body_caption()


func _round_placeholder_changed(_on: bool) -> void:
	_set_round_prompt()
	buffer_changed.emit()


func _on_reply_toggled(_on: bool) -> void:
	_apply_visibility()
	if not _busy:
		picked.emit("new_reply", "")


func set_blocked(blocked: bool) -> void:
	_blocked = blocked
	_apply_visibility()


func set_keyboard_compact(enabled: bool) -> void:
	if _compact == enabled:
		return
	_compact = enabled
	_apply_visibility()


func hide_keyboard() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == body or focus == reply:
		focus.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()


func _apply_visibility() -> void:
	var editing := not _compact and not _blocked
	var branching := _mode == "choice"
	var replying := branching and new_reply.button_pressed
	var in_reply := reply.has_focus()
	if _native_fields:
		_buttons["edit_body"].visible = editing
		_buttons["edit_body"].text = body_caption()
		_buttons["edit_reply"].visible = editing and replying
	var composing_round := _mode == "followup"
	for key: String in ["chapter", "conversation", "node"]:
		_rows[key].visible = editing and not composing_round
	_rows["form_actions"].visible = editing
	_rows["field"].visible = editing and _mode == "text"
	var round_visible := editing and composing_round
	_rows["line"].visible = round_visible
	_round_actions.visible = round_visible
	round_context.visible = round_visible
	round_placeholder.visible = round_visible
	_rows["speaker"].visible = editing and (_mode == "insert" or replying or round_visible)
	_rows["target"].visible = editing and branching
	_followup_actions.visible = editing and _mode == "text"
	_structure.visible = editing and _mode == "text"
	_footer.visible = not _compact
	_buttons["keyboard"].visible = _compact
	_buttons["apply"].visible = _mode != "text"
	# One key at a time: "save the new structure" while composing, "save this text" while
	# editing a field, never both.
	_buttons["apply_text"].visible = _mode == "text" and not _compact
	_buttons["apply_text"].disabled = _blocked
	body.visible = not _blocked and (not _compact or not in_reply)
	body.custom_minimum_size.y = 64.0 if _compact else 110.0
	new_reply.visible = editing and branching
	reply.visible = (editing and replying) or (_compact and in_reply)
	reply.custom_minimum_size.y = body.custom_minimum_size.y
	status.visible = not _compact
	if _compact:
		_scroll.set_deferred("scroll_vertical", 0)


func fit_touch() -> void:
	for control: Control in _buttons.values() + _pickers.values() + [new_reply, round_placeholder]:
		if MobileLayout.enabled:
			MobileLayout.enlarge(control)
		else:
			control.custom_minimum_size.y = 33.0
	if MobileLayout.enabled:
		_scroll.scroll_deadzone = roundi(MobileLayout.hit_size(self) / 6.0)
