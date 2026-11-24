extends PanelContainer
## One option's next round. Rows here are un-applied input, never pieces of the live graph.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

signal changed
signal native_requested(editor: TextEdit, caption: String)
signal apply_requested
signal keep_requested
signal discard_requested

var _context: Label
var _scroll: ScrollContainer
var _lines: VBoxContainer
var _choices: VBoxContainer
var _add_line: Button
var _add_choice: Button
var _speakers: PackedStringArray
var _targets: Dictionary
var _default_speaker: String
var _return_to: String


func _ready() -> void:
	name = "NextRound"
	var style := MenuStyle.panel_style()
	style.set_content_margin_all(12.0)
	add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_context = Label.new()
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context.max_lines_visible = 3
	column.add_child(_context)
	var actions := HFlowContainer.new()
	column.add_child(actions)
	_add_line = _button(actions, "AddLine", "加一句", _add_row.bind(false, {}))
	_add_choice = _button(actions, "AddChoice", "加选项", _add_row.bind(true, {}))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	_lines = _group(rows, "新对白 · 最后一句显示新选项", "Lines")
	_choices = _group(rows, "新选项 · 至少一个接回原去向", "Choices")
	var footer := HFlowContainer.new()
	column.add_child(footer)
	_button(footer, "ApplyRound", "应用并接入", func() -> void: apply_requested.emit())
	_button(footer, "KeepRound", "保留输入", func() -> void: keep_requested.emit())
	_button(footer, "DiscardRound", "放弃", func() -> void: discard_requested.emit())


func prepare(caption: String, speakers: PackedStringArray, speaker: String, destinations: Dictionary,
		return_to: String, values: Dictionary) -> void:
	_context.text = "接在「%s」之后" % caption
	_speakers = speakers
	_default_speaker = speaker
	_return_to = return_to
	_targets = {return_to: "接回原去向 · " + return_to}
	for id: String in destinations:
		if id != return_to:
			_targets[id] = destinations[id]
	for group in [_lines, _choices]:
		for child: Node in group.get_children():
			group.remove_child(child)
			child.queue_free()
	for row: Variant in _saved_rows(values.get("lines"), Patch.MAX_ROUND_LINES, [{}]):
		_add_row(false, row if row is Dictionary else {})
	for row: Variant in _saved_rows(values.get("choices"), Patch.MAX_ROUND_CHOICES, [{}, {}]):
		_add_row(true, row if row is Dictionary else {})
	_scroll.set_deferred("scroll_vertical", 0)


func _saved_rows(value: Variant, limit: int, defaults: Array) -> Array:
	return value.slice(0, limit) if value is Array and not value.is_empty() else defaults


func capture() -> Dictionary:
	return {"lines": _capture_group(_lines, "speaker"), "choices": _capture_group(_choices, "next")}


func _capture_group(group: VBoxContainer, field: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Node in group.get_children():
		var picker := row.get_node(^"Row/Target") as OptionButton
		var edit := row.get_node(^"Text") as TextEdit
		out.append({field: picker.get_selected_metadata(), "text": edit.text})
	return out


func _add_row(choice: bool, values: Dictionary) -> void:
	var group := _choices if choice else _lines
	if group.get_child_count() >= (Patch.MAX_ROUND_CHOICES if choice else Patch.MAX_ROUND_LINES):
		return
	var row := VBoxContainer.new()
	row.name = "Field"
	group.add_child(row, true)
	var bar := HBoxContainer.new()
	bar.name = "Row"
	row.add_child(bar)
	var ordinal := Label.new()
	ordinal.name = "Ordinal"
	bar.add_child(ordinal)
	var picker := OptionButton.new()
	picker.name = "Target"
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(picker)
	if MobileLayout.enabled:
		MobileLayout.enlarge(picker)
	var items := _targets if choice else _speaker_items()
	var key := "next" if choice else "speaker"
	var selected := String(values.get(key, _return_to if choice else _default_speaker))
	if not items.has(selected):
		items = items.duplicate()
		items[selected] = "已失效 · " + selected
	for id: String in items:
		picker.add_item(items[id])
		picker.set_item_metadata(picker.item_count - 1, id)
		if id == selected:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(_index: int) -> void: changed.emit())
	var edit := TextEdit.new()
	edit.name = "Text"
	edit.custom_minimum_size.y = 66 if choice else 90
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.placeholder_text = "新选项文案" if choice else "新对白正文"
	edit.text = String(values.get("text", ""))
	edit.text_changed.connect(func() -> void: changed.emit())
	row.add_child(edit)
	if OS.has_feature("ios"):
		edit.editable = false
		_button(bar, "Input", "输入", func() -> void: native_requested.emit(edit, edit.placeholder_text))
	_button(bar, "Remove", "移除", _remove_row.bind(group, row))
	if MobileLayout.enabled:
		MobileLayout.setup_scroll(_scroll)
	_number_rows()
	changed.emit()


func _remove_row(group: VBoxContainer, row: VBoxContainer) -> void:
	if group.get_child_count() <= 1:
		return
	group.remove_child(row)
	row.queue_free()
	_number_rows()
	changed.emit()


func _number_rows() -> void:
	for group in [_lines, _choices]:
		for row: Node in group.get_children():
			var number := row.get_node(^"Row/Ordinal") as Label
			number.text = str(row.get_index() + 1) + "."
			(row.get_node(^"Row/Remove") as Button).disabled = group.get_child_count() <= 1
	_add_line.disabled = _lines.get_child_count() >= Patch.MAX_ROUND_LINES
	_add_choice.disabled = _choices.get_child_count() >= Patch.MAX_ROUND_CHOICES


func _speaker_items() -> Dictionary:
	var items := {}
	for speaker: String in _speakers:
		items[speaker] = speaker
	return items


func _group(parent: VBoxContainer, title: String, group_name: String) -> VBoxContainer:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var group := VBoxContainer.new()
	group.name = group_name
	group.add_theme_constant_override(&"separation", 8)
	parent.add_child(group)
	return group


func _button(parent: Container, label: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = label
	button.text = text
	button.custom_minimum_size.y = 32.0
	button.pressed.connect(action)
	parent.add_child(button)
	if MobileLayout.enabled:
		MobileLayout.enlarge(button)
	return button
