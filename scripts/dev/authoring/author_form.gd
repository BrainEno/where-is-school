extends PanelContainer
## The author drawer only owns controls. It sends stable selections to its host;
## the scroll list is not the order of nodes/choices in the content file.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
signal picked(field: String, id: String)
signal action(id: String)
signal buffer_changed

var body: TextEdit
var reply: TextEdit
var new_reply: CheckButton
var status: Label
var _columns: VBoxContainer
var _toolbar: HBoxContainer
var _footer: HBoxContainer
var _structure: HBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _rows := {}
var _buttons := {}
var _pickers := {}
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

	_structure = _row(_content)
	_button(_structure, "insert", "插句")
	_button(_structure, "choice", "加选项")
	_button(_structure, "undo", "撤销")
	_button(_structure, "clear", "清空")

	if _native_fields:
		_button(_content, "edit_body", "编辑这个字段")
	body = _text_box("DraftText")
	new_reply = CheckButton.new()
	new_reply.text = "添加新回应"
	new_reply.toggled.connect(_on_reply_toggled)
	_content.add_child(new_reply)
	_picker("speaker", "说话人")
	if _native_fields:
		_button(_content, "edit_reply", "编辑新回应")
	reply = _text_box("ReplyText")
	reply.placeholder_text = "输入新回应"
	_picker("target", "接到")
	var form_actions := _row(_content)
	_rows["form_actions"] = form_actions
	_button(form_actions, "apply", "保存新增")
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
	new_reply.button_pressed = bool(backing.get("new_reply", false))
	reply.text = String(backing.get("reply", ""))
	reply.clear_undo_history()
	_busy = false
	_apply_visibility()


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
		_buttons["edit_reply"].visible = editing and replying
	for key: String in ["chapter", "conversation", "node", "form_actions"]:
		_rows[key].visible = editing
	_rows["field"].visible = editing and _mode == "text"
	_rows["speaker"].visible = editing and (_mode == "insert" or replying)
	_rows["target"].visible = editing and branching
	_structure.visible = editing
	_footer.visible = not _compact
	_buttons["keyboard"].visible = _compact
	_buttons["apply"].visible = _mode != "text"
	body.visible = not _blocked and (not _compact or not in_reply)
	body.custom_minimum_size.y = 64.0 if _compact else 110.0
	new_reply.visible = editing and branching
	reply.visible = (editing and replying) or (_compact and in_reply)
	reply.custom_minimum_size.y = body.custom_minimum_size.y
	status.visible = not _compact
	if _compact:
		_scroll.set_deferred("scroll_vertical", 0)


func fit_touch() -> void:
	for control: Control in _buttons.values() + _pickers.values() + [new_reply]:
		if MobileLayout.enabled:
			MobileLayout.enlarge(control)
		else:
			control.custom_minimum_size.y = 33.0
	if MobileLayout.enabled:
		_scroll.scroll_deadzone = roundi(MobileLayout.hit_size(self) / 6.0)
