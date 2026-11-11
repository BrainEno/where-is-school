class_name BacklogPanel
extends Control
## Scrollable history of everything the dialogue view has shown.
##
## The backlog keeps presentation state only: it never reads or writes story flags.
## What it stores, though, is deliberately not screen text. Each row keeps the
## **descriptor** of the event that produced it — its identity, the conversation or
## inspection it came from, the speaker and the narrative source — and the rows
## themselves are re-created from those descriptors.
##
## That is what makes the log survive a language switch (issue #18): the entries keep
## their identities and their order, and only their rendered text changes. Nothing is
## compared by text, so two different events that happen to say the same words stay
## two rows, and a first read, a repeat read and a recollection stay three.

@onready var _list: VBoxContainer = %BacklogList
@onready var _scroll: ScrollContainer = %BacklogScroll
@onready var _empty_label: Label = %BacklogEmpty

## Descriptors, in the order the player read them.
var _entries: Array[Dictionary] = []
## What each descriptor looks like in the current language.
var _rendered: Array[Dictionary] = []
## Supplied by the controller: (descriptor) -> display dictionary in the current
## locale. Without it the panel can only re-localise the labels it owns.
var _resolver: Callable = Callable()
var _text_scale: float = 1.0


func _ready() -> void:
	hide()
	_empty_label.visible = true
	_empty_label.text = L10n.t("ui.log_empty")
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_input_changed)
		settings.connect("bindings_changed", _on_input_changed.bind(&""))
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	_refresh_footer()
	set_text_scale(UiTextScale.current(self))


## The player's text size, for the title, the footer and every row.
func set_text_scale(factor: float) -> void:
	_text_scale = factor
	UiTextScale.apply(self, factor)


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		set_text_scale(UiTextScale.current(self))


func _on_input_changed(_device: StringName) -> void:
	_refresh_footer()


func _on_locale_changed(_locale: String) -> void:
	_refresh_footer()
	_empty_label.text = L10n.t("ui.log_empty")


## The title and footer come from the locale tables (they were fixed English in the
## scene); the footer names the key or button that closes the log on the device in use.
func _refresh_footer() -> void:
	var title := get_node_or_null(^"Margin/Layout/Title") as Label
	if title != null:
		title.text = L10n.t("ui.log_title")
	var footer := get_node_or_null(^"Margin/Layout/Footer") as Label
	if footer != null:
		footer.text = L10n.t("ui.log_hint", {"key": MenuStyle.key(self, &"backlog")})


## The controller hands over the re-render function once, in _ready.
func set_resolver(resolver: Callable) -> void:
	_resolver = resolver


## Appends a line. A line whose identity matches the newest entry is the same event
## being republished (a language switch), so it replaces that row instead of adding a
## duplicate — the identity decides, never the text.
func add_entry(line: Dictionary) -> void:
	var entry := line.duplicate(true)
	entry["identity"] = DialogueHistory.identify(entry)
	if not _entries.is_empty() \
			and DialogueHistory.identify(_entries[_entries.size() - 1]) == String(entry["identity"]):
		_entries[_entries.size() - 1] = entry
		_rendered[_rendered.size() - 1] = line.duplicate(true)
		_rebuild_rows()
		return
	_entries.append(entry)
	_rendered.append(line.duplicate(true))
	_empty_label.visible = false
	_add_rows([line])


## Replaces the newest row when it belongs to the same event, and reports whether it
## did. Used when the line on screen is re-rendered because the language changed.
func replace_last(line: Dictionary) -> bool:
	var entry := line.duplicate(true)
	entry["identity"] = DialogueHistory.identify(entry)
	if _entries.is_empty():
		add_entry(line)
		return true
	if DialogueHistory.identify(_entries[_entries.size() - 1]) != String(entry["identity"]):
		# A different event: appending is the only thing that keeps both.
		add_entry(line)
		return false
	_entries[_entries.size() - 1] = entry
	_rendered[_rendered.size() - 1] = line.duplicate(true)
	_rebuild_rows()
	return true


## Drops every row and re-creates them from the stored descriptors in the current
## language. Order and identity are untouched.
func rebuild() -> void:
	var rebuilt: Array[Dictionary] = []
	for entry in _entries:
		rebuilt.append(_display(entry))
	_rendered = rebuilt
	_rebuild_rows()
	await _scroll_to_end()


## Re-resolves one row in place, for a line that is still on screen (no rebuild of the
## whole list, no scroll jump for the player reading further up).
func refresh_last() -> void:
	if _entries.is_empty():
		return
	_rendered[_rendered.size() - 1] = _display(_entries[_entries.size() - 1])
	var rows := _list.get_children()
	if rows.is_empty():
		return
	var row: Node = rows[rows.size() - 1]
	_fill_row(row, _rendered[_rendered.size() - 1])


func get_entry_count() -> int:
	return _entries.size()


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## Identities in reading order. The tests use these to prove that a language switch
## changed no entry and added none.
func get_entry_identities() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in _entries:
		ids.append(DialogueHistory.identify(entry))
	return ids


func get_entry_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for row in _rendered:
		texts.append(String(row.get("text", "")))
	return texts


func open() -> void:
	show()
	move_to_front()
	await get_tree().process_frame
	await _scroll_to_end()


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


func _display(entry: Dictionary) -> Dictionary:
	if _resolver.is_valid():
		var resolved: Variant = _resolver.call(entry)
		if resolved is Dictionary and not (resolved as Dictionary).is_empty():
			return (resolved as Dictionary).duplicate(true)
	return entry.duplicate(true)


func _rebuild_rows() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_empty_label.visible = _rendered.is_empty()
	_empty_label.text = L10n.t("ui.log_empty")
	_add_rows(_rendered)


func _add_rows(lines: Array) -> void:
	for line_variant: Variant in lines:
		var line: Dictionary = line_variant
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		# A row is a header (speaker and source) over the text. The labels were lost in
		# the descriptor rewrite, which left every row empty; they are made here again.
		var header := Label.new()
		header.name = "Header"
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiTextScale.set_base(header, 16, _text_scale)
		var body := Label.new()
		body.name = "Body"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", Color(0.776, 0.733, 0.643, 1.0))
		UiTextScale.set_base(body, 20, _text_scale)
		row.add_child(header)
		row.add_child(body)
		_list.add_child(row)
		_fill_row(row, line)


func _fill_row(row: Node, line: Dictionary) -> void:
	var header: Label = null
	var body: Label = null
	for child in row.get_children():
		if child is Label and header == null:
			header = child
		elif child is Label:
			body = child
	if header == null or body == null:
		return

	var speaker := String(line.get("speaker_name", ""))
	var badge_key := String(line.get("badge", ""))
	var badge := L10n.t(badge_key) if not badge_key.is_empty() else ""
	var title := String(line.get("title", ""))
	if not title.is_empty():
		speaker = title
	header.text = "%s  ·  %s" % [speaker, badge] if not badge.is_empty() else speaker
	header.add_theme_color_override("font_color", line.get("accent_color", Color.WHITE))
	body.text = String(line.get("text", ""))


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if _scroll == null:
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
