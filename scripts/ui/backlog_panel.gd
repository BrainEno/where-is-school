class_name BacklogPanel
extends Control
## Scrollable history of everything the dialogue view has shown.
##
## Long lines need to be reviewable, so the backlog keeps speaker, narrative
## category and the full text. It is presentation state only: it does not read or
## write story flags.

@onready var _list: VBoxContainer = %BacklogList
@onready var _scroll: ScrollContainer = %BacklogScroll
@onready var _empty_label: Label = %BacklogEmpty

## Every line ever shown, kept as data so the list can be rebuilt in another
## language instead of freezing the text the player happened to read first.
var _entries: Array[Dictionary] = []


func _ready() -> void:
	hide()
	_empty_label.visible = true


func add_entry(line: Dictionary) -> void:
	_entries.append(line.duplicate(true))
	_empty_label.visible = false
	_add_rows([line])


## Replaces the newest row (used when the visible line is re-rendered because the
## language changed) so the backlog does not collect a duplicate.
func replace_last(line: Dictionary) -> void:
	if _entries.is_empty():
		add_entry(line)
		return
	_entries[_entries.size() - 1] = line.duplicate(true)
	rebuild()


## Drops every row and re-creates them from the stored data in the current language.
func rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_empty_label.visible = _entries.is_empty()
	_empty_label.text = L10n.t("ui.log_empty")
	_add_rows(_entries)
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func get_entry_count() -> int:
	return _entries.size()


func _add_rows(lines: Array) -> void:
	for line_variant: Variant in lines:
		_add_row(line_variant as Dictionary)


func _add_row(line: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	var speaker := String(line.get("speaker_name", ""))
	var badge_key := String(line.get("badge", ""))
	var badge := L10n.t(badge_key) if not badge_key.is_empty() else ""
	var title := String(line.get("title", ""))
	if not title.is_empty():
		speaker = title
	header.text = "%s  ·  %s" % [speaker, badge]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", line.get("accent_color", Color.WHITE))

	var body := Label.new()
	body.text = String(line.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color(0.776, 0.733, 0.643, 1.0))

	row.add_child(header)
	row.add_child(body)
	_list.add_child(row)


func open() -> void:
	show()
	move_to_front()
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("backlog") or event.is_action_pressed("dialogue_advance") \
			or event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
