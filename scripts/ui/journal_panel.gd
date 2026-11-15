class_name JournalPanel
extends Control
## The notebook: everything the protagonist has come to know this run, and how he knows
## it.
##
## It reads `NarrativeState` - the log of observed, reported, recalled and imagined
## entries the dialogue and inspections record - and never writes to it or to the story
## flags. Each entry is drawn under the place it was learned in, with its kind of
## knowledge as a coloured badge, the person it came from when it came from someone, and
## a short caveat for the kind on show: something seen is not something understood, and
## something heard only proves somebody said it. Above the entries, a route line names the
## places this run has reached (`JournalRoute`, from flags the story already keeps) and the
## objective on screen. That distinction is the game's (see
## `docs/PRODUCT_BRIEF.md`); the notebook is where the player can read it back.
##
## Rows are worded from their identity, not from the stored text: a `JournalCatalog`
## built from the loaded content gives the words for an `entry_id` in the language on
## screen, so a language switch re-words the whole notebook and adds or loses nothing.
## An entry the content no longer knows keeps the words it was recorded with.
##
## "New" is presentation state only. Entries already in the log when the notebook comes
## into being (a Continue) or restored into it later are not news; entries recorded after
## that are, until the notebook has been closed once with them in it. Nothing about it is
## saved: the save format stays what ADR 0005 says it is.
##
## Built in code, set like the settings screen (one face, `MenuStyle.page_theme()`), and
## usable without a mouse: ←/→ move between the kinds, Enter/A picks one, ↑/↓ and Page
## Up/Down scroll the page, and Esc/B, the menu button or the notebook key close it.

signal closed

const PANEL_MAX_WIDTH := 940.0
const OUTER_MARGIN := 40.0
const SCROLL_STEP := 72.0

## The notebook's colours for the four kinds, the same the dialogue panel uses for its
## badges, so a kind looks the same wherever it is named.
const SOURCE_COLORS: Dictionary = {
	NarrativeEntry.Source.OBSERVED: Color(0.776, 0.733, 0.643, 1.0),
	NarrativeEntry.Source.REPORTED: Color(0.561, 0.663, 0.710, 1.0),
	NarrativeEntry.Source.RECALLED: Color(0.604, 0.639, 0.592, 1.0),
	NarrativeEntry.Source.IMAGINED: Color(0.820, 0.553, 0.349, 1.0),
}

var _factor := 1.0
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _route: Label = null
var _objective: Label = null
## "Text read: 37% (120 of 324 lines)", across every run (`ReadingProgress`).
var _progress: Label = null
## Returns `ReadingProgress.measure()`'s dictionary; empty until the world provides one.
var _progress_source: Callable = Callable()
var _filters: HFlowContainer = null
var _caveat: Label = null
var _scroll: ScrollContainer = null
var _rows: VBoxContainer = null
var _empty: Label = null
var _hint: Label = null
var _back: Button = null
## filter (ALL or a source) -> its button.
var _filter_buttons: Dictionary = {}
var _filter: int = JournalPage.ALL
var _catalog: JournalCatalog = null
var _locations: LocationCatalog = null
var _characters: CharacterDirectory = null
## entry_id -> true, for every entry that is not news any more.
var _read: Dictionary = {}
## The page on screen, as `JournalPage.compose()` returned it.
var _page: Dictionary = {}
var _rebuild_queued := false


func _init() -> void:
	name = "JournalPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	theme = MenuStyle.page_theme()
	_factor = UiTextScale.current(self)
	add_child(MenuStyle.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, int(OUTER_MARGIN))
	add_child(margin)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", MenuStyle.sheet_style())
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_panel.add_child(column)

	_title = MenuStyle.serif_label("", MenuStyle.TITLE_SIZE, _factor, MenuStyle.PAPER, 0.6, 3)
	_title.name = "Title"
	column.add_child(_title)
	_subtitle = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_subtitle.name = "Subtitle"
	column.add_child(_subtitle)
	_route = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.ACCENT)
	_route.name = "Route"
	column.add_child(_route)
	_objective = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.PAGE_TEXT)
	_objective.name = "Objective"
	column.add_child(_objective)
	_progress = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_progress.name = "ReadingProgress"
	_progress.visible = false
	column.add_child(_progress)
	column.add_child(MenuStyle.rule(56.0))

	_filters = HFlowContainer.new()
	_filters.name = "Filters"
	_filters.add_theme_constant_override(&"h_separation", 8)
	_filters.add_theme_constant_override(&"v_separation", 6)
	column.add_child(_filters)
	var order: Array[int] = [JournalPage.ALL]
	order.append_array(JournalPage.SOURCES)
	for filter: int in order:
		var button := MenuStyle.entry_button("", MenuStyle.BODY_SIZE, _factor)
		button.name = "Filter_%s" % _filter_slug(filter)
		MenuStyle.style_form_entry(button)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.toggle_mode = true
		button.pressed.connect(set_filter.bind(filter))
		button.gui_input.connect(_on_filter_gui_input)
		_filters.add_child(button)
		_filter_buttons[filter] = button
	_link_filter_focus(order)

	_caveat = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_caveat.name = "Caveat"
	column.add_child(_caveat)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 10)
	_scroll.add_child(_rows)
	_empty = MenuStyle.paragraph("", MenuStyle.BODY_SIZE, _factor, MenuStyle.MUTED)
	_empty.name = "Empty"
	_empty.visible = false
	column.add_child(_empty)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	column.add_child(footer)
	_back = MenuStyle.page_entry("", MenuStyle.BODY_SIZE, _factor)
	_back.name = "Back"
	_back.autowrap_mode = TextServer.AUTOWRAP_OFF
	_back.pressed.connect(close)
	footer.add_child(_back)
	_hint = MenuStyle.paragraph("", MenuStyle.SMALL_SIZE, _factor, MenuStyle.MUTED)
	_hint.name = "Hint"
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_hint)

	var state := _narrative_state()
	if state != null:
		# What the log held before the notebook existed is not news (a Continue).
		mark_all_read()
		state.connect("entry_recorded", _on_entry_recorded)
		state.connect("entries_cleared", _on_entries_cleared)
		state.connect("entries_restored", _on_entries_restored)
	var game_state := _game_state()
	if game_state != null:
		game_state.connect("story_flag_changed", _on_story_flag_changed)
		game_state.connect("story_state_replaced", _on_story_state_replaced)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_device_changed)
		settings.connect("bindings_changed", _refresh_hint)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	get_viewport().size_changed.connect(_fit)
	_rebuild()


# --- Public ---------------------------------------------------------------------------


## The content index rows are worded from. Without one, rows keep their stored words.
func set_catalog(catalog: JournalCatalog) -> void:
	_catalog = catalog
	if visible:
		_queue_rebuild()


func get_catalog() -> JournalCatalog:
	return _catalog


func has_catalog() -> bool:
	return _catalog != null


## The locations the route line is drawn from. Defaults to `data/story/locations.json`.
func set_locations(locations: LocationCatalog) -> void:
	_locations = locations
	if visible:
		_queue_rebuild()


func get_route_text() -> String:
	return _route.text if _route != null and _route.visible else ""


func get_objective_text() -> String:
	return _objective.text if _objective != null and _objective.visible else ""


## Where the reading progress comes from: the dialogue controller's
## `get_reading_progress`, which knows the content and the read log.
func set_progress_source(source: Callable) -> void:
	_progress_source = source
	if visible:
		_queue_rebuild()


func has_progress_source() -> bool:
	return _progress_source.is_valid()


func get_progress_text() -> String:
	return _progress.text if _progress != null and _progress.visible else ""


## Names for "Q said so". Defaults to the shared cached directory.
func set_characters(characters: CharacterDirectory) -> void:
	_characters = characters


func open(filter: int = JournalPage.ALL) -> void:
	_filter = filter if _filter_buttons.has(filter) else JournalPage.ALL
	_factor = UiTextScale.current(self)
	UiTextScale.apply(self, _factor)
	_rebuild()
	show()
	move_to_front()
	_fit()
	focus_filter(_filter)
	_scroll.scroll_vertical = 0
	# Bring the first new entry into view once the rows have a layout.
	_scroll_to_first_new.call_deferred()


## Closes the notebook. Whatever was in it has now been seen.
func close() -> void:
	if not visible:
		return
	mark_all_read()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func get_filter() -> int:
	return _filter


## Narrows the page to one kind of knowledge, or shows all of them (`JournalPage.ALL`).
func set_filter(filter: int) -> void:
	if not _filter_buttons.has(filter):
		return
	_filter = filter
	_rebuild()
	_scroll.scroll_vertical = 0
	if visible:
		focus_filter(filter)


func focus_filter(filter: int) -> void:
	var button := _filter_buttons.get(filter) as Button
	if button != null and button.is_inside_tree() and button.is_visible_in_tree():
		button.grab_focus()


func get_filter_button(filter: int) -> Button:
	return _filter_buttons.get(filter) as Button


func get_back_button() -> Button:
	return _back


func get_scroll() -> ScrollContainer:
	return _scroll


func get_panel() -> PanelContainer:
	return _panel


## The page on screen (see `JournalPage.compose()`), a copy.
func get_page() -> Dictionary:
	return _page.duplicate(true)


func get_row_ids() -> Array[StringName]:
	return JournalPage.row_ids(_page)


func get_row_texts() -> PackedStringArray:
	return JournalPage.row_texts(_page)


## The place headings on screen, as drawn.
func get_section_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	for child in _rows.get_children():
		if child is Label and String(child.name).begins_with("Section"):
			titles.append((child as Label).text)
	return titles


## The drawn header line of every row ("Seen · new"), in drawing order.
func get_row_headers() -> PackedStringArray:
	var headers := PackedStringArray()
	for child in _rows.get_children():
		var header := child.get_node_or_null(^"Text/Header") as Label
		if header != null:
			headers.append(header.text)
	return headers


func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_caveat_text() -> String:
	return _caveat.text if _caveat != null else ""


func get_hint_text() -> String:
	return _hint.text if _hint != null else ""


func get_empty_text() -> String:
	return _empty.text if _empty != null and _empty.visible else ""


## Entries recorded since the notebook last closed with them in it.
func get_unread_count() -> int:
	var state := _narrative_state()
	if state == null:
		return 0
	var count := 0
	for entry: NarrativeEntry in state.call("get_entries"):
		if not _read.has(entry.entry_id):
			count += 1
	return count


func is_new(entry_id: StringName) -> bool:
	var state := _narrative_state()
	return state != null and bool(state.call("has_entry", entry_id)) and not _read.has(entry_id)


func mark_all_read() -> void:
	var state := _narrative_state()
	if state == null:
		return
	for entry: NarrativeEntry in state.call("get_entries"):
		_read[entry.entry_id] = true


# --- Building -------------------------------------------------------------------------


func _rebuild() -> void:
	_rebuild_queued = false
	if _rows == null:
		return
	var state := _narrative_state()
	var entries: Array[NarrativeEntry] = []
	if state != null:
		entries = state.call("get_entries")
	if _characters == null:
		_characters = CharacterDirectory.load_cached()
	_page = JournalPage.compose(entries, _catalog, L10n.current, _filter, _read, _characters)

	_title.text = L10n.t("journal.title")
	_subtitle.text = L10n.t("journal.subtitle")
	_refresh_route()
	_back.text = L10n.t("menu.back")
	var counts: Dictionary = _page.get("counts", {})
	for filter: Variant in _filter_buttons.keys():
		var button := _filter_buttons[filter] as Button
		button.text = L10n.t("journal.filter_count", {
			"label": L10n.t(JournalPage.filter_label_key(int(filter))),
			"count": int(counts.get(int(filter), 0)),
		})
		button.set_pressed_no_signal(int(filter) == _filter)
		if int(filter) != JournalPage.ALL:
			button.add_theme_color_override(&"font_color", _source_color(int(filter)))
	_caveat.text = L10n.t(JournalPage.caveat_key(_filter))
	_caveat.add_theme_color_override(
		&"font_color",
		MenuStyle.MUTED if _filter == JournalPage.ALL else Color(_source_color(_filter), 0.85)
	)

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var first := true
	for section: Variant in _page.get("sections", []):
		_add_section(section as Dictionary, first)
		first = false
	var shown := int(_page.get("shown", 0))
	_empty.visible = shown == 0
	_scroll.visible = shown > 0
	if int(_page.get("total", 0)) == 0:
		_empty.text = L10n.t("journal.empty")
	else:
		_empty.text = L10n.t("journal.empty_filter")
	_refresh_hint()


func _add_section(section: Dictionary, first: bool) -> void:
	if not first:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0.0, 8.0)
		_rows.add_child(gap)
	var heading := MenuStyle.serif_label(
		L10n.t(String(section.get("place_key", JournalCatalog.ELSEWHERE_KEY))),
		MenuStyle.BODY_SIZE, _factor, MenuStyle.EMBER, 0.3, 1
	)
	heading.name = "Section_%d" % _rows.get_child_count()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(heading)
	for row: Variant in section.get("rows", []):
		_add_row(row as Dictionary)


func _add_row(row: Dictionary) -> void:
	var source := int(row.get("source", NarrativeEntry.Source.OBSERVED))
	var color := _source_color(source)
	var line := HBoxContainer.new()
	line.name = "Row_%s" % String(row.get("entry_id", ""))
	line.add_theme_constant_override(&"separation", 12)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.set_meta(&"entry_id", row.get("entry_id", &""))
	line.set_meta(&"is_new", bool(row.get("is_new", false)))
	var mark := ColorRect.new()
	mark.name = "Mark"
	mark.color = Color(color, 0.8)
	mark.custom_minimum_size = Vector2(3.0, 0.0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(mark)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 2)
	line.add_child(text)
	var parts := PackedStringArray([L10n.t(String(row.get("badge_key", "")))])
	var attribution := String(row.get("attribution", ""))
	if not attribution.is_empty():
		parts.append(attribution)
	if bool(row.get("is_new", false)):
		parts.append(L10n.t("journal.new"))
	var header := MenuStyle.paragraph(
		L10n.t("menu.caption_separator").join(parts), MenuStyle.SMALL_SIZE, _factor, color
	)
	header.name = "Header"
	text.add_child(header)
	var body := MenuStyle.paragraph(
		String(row.get("text", "")), MenuStyle.BODY_SIZE, _factor, MenuStyle.PAGE_TEXT
	)
	body.name = "Body"
	text.add_child(body)
	_rows.add_child(line)


func _refresh_route() -> void:
	if _route == null:
		return
	if _locations == null:
		_locations = LocationCatalog.load_all()
	var flags := _game_state()
	var rows := JournalRoute.compose(_locations, flags, _page.get("place_counts", {}))
	_route.text = JournalRoute.describe(rows)
	_route.visible = not _route.text.is_empty()
	var objective := JournalRoute.objective_text(flags)
	_objective.text = L10n.t("journal.objective", {"objective": objective}) \
		if not objective.is_empty() else ""
	_objective.visible = not _objective.text.is_empty()
	_refresh_progress()


func _refresh_progress() -> void:
	if _progress == null:
		return
	var progress: Dictionary = {}
	if _progress_source.is_valid():
		var value: Variant = _progress_source.call()
		if value is Dictionary:
			progress = value
	_progress.text = ReadingProgress.describe(progress)
	_progress.visible = not _progress.text.is_empty()


func _refresh_hint() -> void:
	if _hint == null:
		return
	var pad := MenuStyle.using_gamepad(self)
	_hint.text = L10n.t(
		"journal.hint_pad" if pad else "journal.hint_keyboard",
		{"close": MenuStyle.key(self, &"ui_cancel"), "confirm": MenuStyle.key(self, &"ui_accept")}
	)


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _scroll_to_first_new() -> void:
	if not visible or _rows == null:
		return
	for child in _rows.get_children():
		if child is Control and child.has_meta(&"is_new") and bool(child.get_meta(&"is_new")):
			_scroll.ensure_control_visible(child as Control)
			return


static func _source_color(source: int) -> Color:
	return SOURCE_COLORS.get(source, MenuStyle.PAPER)


static func _filter_slug(filter: int) -> String:
	return "all" if filter == JournalPage.ALL else NarrativeEntry.source_to_id(filter)


# --- Input ----------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"cancel") or _is_journal_key(event):
		if event is InputEventKey and (event as InputEventKey).echo:
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		close()
		return
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up") \
			or event.is_action_pressed(&"ui_page_down") or event.is_action_pressed(&"ui_page_up"):
		get_viewport().set_input_as_handled()
		_scroll_by_event(event)
		return
	# The notebook owns the input while it is up; the language and window keys still work.
	if event is InputEventKey or event is InputEventJoypadButton:
		if not event.is_action_pressed(&"toggle_language") \
				and not event.is_action_pressed(&"toggle_fullscreen"):
			get_viewport().set_input_as_handled()


## ←/→ walk the kinds in order and wrap, whatever the row looks like: at a narrow window
## or the largest text the flow wraps, and the nearest button to the right on screen is
## then not the next kind. ↑/↓ stay put, because they scroll (see below).
func _link_filter_focus(order: Array[int]) -> void:
	var count := order.size()
	for index in count:
		var button: Button = _filter_buttons[order[index]]
		var next: Button = _filter_buttons[order[(index + 1) % count]]
		var previous: Button = _filter_buttons[order[(index - 1 + count) % count]]
		button.focus_neighbor_right = button.get_path_to(next)
		button.focus_neighbor_left = button.get_path_to(previous)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_next = button.focus_neighbor_right
		button.focus_previous = button.focus_neighbor_left


## ↑/↓ on a kind scroll the page instead of leaving the row of kinds: the rows are text,
## not things to focus, so scrolling is the only thing up and down can mean here.
func _on_filter_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up") \
			or event.is_action_pressed(&"ui_page_down") or event.is_action_pressed(&"ui_page_up"):
		accept_event()
		_scroll_by_event(event)


func _scroll_by_event(event: InputEvent) -> void:
	var page := maxf(_scroll.size.y * 0.85, SCROLL_STEP)
	var step := SCROLL_STEP * maxf(_factor, 1.0)
	if event.is_action_pressed(&"ui_down"):
		scroll_by(step)
	elif event.is_action_pressed(&"ui_up"):
		scroll_by(-step)
	elif event.is_action_pressed(&"ui_page_down"):
		scroll_by(page)
	elif event.is_action_pressed(&"ui_page_up"):
		scroll_by(-page)


func scroll_by(pixels: float) -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	var limit := maxf(0.0, bar.max_value - bar.page)
	_scroll.scroll_vertical = int(clampf(float(_scroll.scroll_vertical) + pixels, 0.0, limit))


# --- Signals --------------------------------------------------------------------------


func _on_entry_recorded(_entry: NarrativeEntry) -> void:
	if visible:
		_queue_rebuild()


func _on_entries_cleared() -> void:
	_read.clear()
	_queue_rebuild()


## A restored log is the run picked up again, not news.
func _on_entries_restored(_count: int) -> void:
	mark_all_read()
	_queue_rebuild()


## The location, the objective or an arrival flag can each change the route line.
func _on_story_flag_changed(_flag: StringName, _previous: Variant, _value: Variant) -> void:
	if visible:
		_queue_rebuild()


func _on_story_state_replaced() -> void:
	if visible:
		_queue_rebuild()


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		_factor = UiTextScale.current(self)
		UiTextScale.apply(self, _factor)
		_queue_rebuild()
		_fit.call_deferred()


func _on_device_changed(_device: StringName) -> void:
	_refresh_hint()


func _on_locale_changed(_locale: String) -> void:
	_queue_rebuild()


# --- Layout ---------------------------------------------------------------------------


func _fit() -> void:
	if _panel == null:
		return
	var view := get_viewport_rect().size
	var width := minf(view.x - OUTER_MARGIN * 2.0, PANEL_MAX_WIDTH * maxf(_factor, 1.0))
	var height := view.y - OUTER_MARGIN * 2.0
	_panel.custom_minimum_size = Vector2(maxf(width, 320.0), maxf(height, 240.0))


static func _is_journal_key(event: InputEvent) -> bool:
	return InputMap.has_action(&"journal") and event.is_action_pressed(&"journal")


func _game_state() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(^"/root/GameState")


func _narrative_state() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(^"/root/NarrativeState")
