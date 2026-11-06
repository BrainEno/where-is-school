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


func _ready() -> void:
	hide()
	_empty_label.visible = true


func add_entry(line: Dictionary) -> void:
	_empty_label.visible = false
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	var speaker := String(line.get("speaker_name", ""))
	var badge := String(line.get("badge", ""))
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
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


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
