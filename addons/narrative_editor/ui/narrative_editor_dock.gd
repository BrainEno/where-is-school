@tool
extends Control
## Editor-only: the narrative editor dock.
##
## Bilingual editing of what the game says, inside the editor, without the five-step ritual
## of finding a chapter file, finding a node and making the same edit twice. The layout is
## three columns: what exists on the left, the two languages in the middle, and the
## structure of whatever is selected on the right.
##
## The split with `core/narrative_store.gd` is deliberate. This file only builds Controls
## and asks the store questions; it does not open a file, does not know a JSON address and
## cannot write anything the store has not offered as an editable field. That is what lets
## the store be tested headlessly against a `user://` copy of the content while the dock
## itself needs a running editor — or, for the capture in CI, a window.
##
## Everything the author reads here is Chinese; the code comments stay English like the
## rest of the repository.

const Store := preload("res://addons/narrative_editor/core/narrative_store.gd")
const APP_THEME := "res://assets/ui/app_theme.tres"

const KIND_ENTRIES: Array[Dictionary] = [
	{"kind": "dialogue", "label": "剧情对话"},
	{"kind": "inspections", "label": "场景检视"},
	{"kind": "abilities", "label": "内心声音文案"},
]
const LIST_TITLES: Dictionary = {
	"dialogue": "对话",
	"inspections": "可检视的东西",
	"abilities": "内心声音",
}
const FIELD_HEIGHT := 108

var store: Store = null

var _kind: String = "dialogue"
var _chapter: String = ""
var _ids: Array[String] = []
var _nodes: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _selected_id: String = ""
var _selected_node: int = -1
var _model_state: Dictionary = {}
var _pending_action: Callable = Callable()
var _pending_focus: String = ""
var _updating: bool = false

var _kind_picker: OptionButton = null
var _chapter_label: Label = null
var _chapter_picker: OptionButton = null
var _search_box: LineEdit = null
var _reload_button: Button = null
var _save_button: Button = null
var _discard_button: Button = null
var _validate_button: Button = null
var _dirty_label: Label = null
var _file_label: Label = null
var _list_title: Label = null
var _id_list: ItemList = null
var _node_title: Label = null
var _node_list: ItemList = null
var _editor_scroll: ScrollContainer = null
var _editor_box: VBoxContainer = null
var _structure_box: TextEdit = null
var _guard_panel: PanelContainer = null
var _guard_label: Label = null
var _status_label: Label = null
var _status_text: TextEdit = null


func _ready() -> void:
	if store == null:
		store = Store.new()
	name = "NarrativeEditor"
	custom_minimum_size = Vector2(760, 480)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var app_theme: Variant = load(APP_THEME)
	if app_theme is Theme:
		# The tool lives inside this project, so it wears this project's interface font.
		# That is also what makes the Chinese labels legible in an editor whose own
		# default font has no CJK coverage.
		theme = app_theme
	_build_ui()
	_open_kind(_kind)


# --- construction -----------------------------------------------------------


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_toolbar())
	root.add_child(_build_status_strip())
	root.add_child(_build_guard_banner())
	var columns := HSplitContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_build_list_column())
	columns.add_child(_build_editor_column())
	columns.add_child(_build_structure_column())
	root.add_child(_build_message_area())


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "Toolbar"
	var kind_label := Label.new()
	kind_label.text = "内容"
	bar.add_child(kind_label)
	_kind_picker = OptionButton.new()
	for entry: Dictionary in KIND_ENTRIES:
		_kind_picker.add_item(String(entry["label"]))
	_kind_picker.item_selected.connect(_on_kind_picked)
	bar.add_child(_kind_picker)

	_chapter_label = Label.new()
	_chapter_label.text = "章节"
	bar.add_child(_chapter_label)
	_chapter_picker = OptionButton.new()
	_chapter_picker.custom_minimum_size = Vector2(140, 0)
	_chapter_picker.item_selected.connect(_on_chapter_picked)
	bar.add_child(_chapter_picker)

	_reload_button = Button.new()
	_reload_button.text = "重新载入"
	_reload_button.tooltip_text = "重新读取磁盘上的文件；有未保存的修改时会先问一次"
	_reload_button.pressed.connect(_on_reload_pressed)
	bar.add_child(_reload_button)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索节点 ID、说话者或中英文文本"
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.custom_minimum_size = Vector2(220, 0)
	_search_box.text_changed.connect(_on_search_changed)
	bar.add_child(_search_box)

	_validate_button = Button.new()
	_validate_button.text = "校验"
	_validate_button.tooltip_text = "按保存的规则检查一遍，不写入任何文件"
	_validate_button.pressed.connect(_on_validate_pressed)
	bar.add_child(_validate_button)

	_save_button = Button.new()
	_save_button.text = "保存"
	_save_button.tooltip_text = "写入英文和简体中文两个文件"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save_pressed)
	bar.add_child(_save_button)

	_discard_button = Button.new()
	_discard_button.text = "放弃修改"
	_discard_button.disabled = true
	_discard_button.pressed.connect(_on_discard_pressed)
	bar.add_child(_discard_button)
	return bar


func _build_status_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.name = "StatusStrip"
	_dirty_label = Label.new()
	_dirty_label.text = "没有未保存的修改"
	strip.add_child(_dirty_label)
	_file_label = Label.new()
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_file_label.add_theme_font_size_override("font_size", 14)
	strip.add_child(_file_label)
	return strip


func _build_guard_banner() -> Control:
	_guard_panel = PanelContainer.new()
	_guard_panel.name = "UnsavedChanges"
	_guard_panel.visible = false
	var row := HBoxContainer.new()
	_guard_label = Label.new()
	_guard_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_guard_label)
	var save_first := Button.new()
	save_first.text = "保存并继续"
	save_first.pressed.connect(_on_guard_save)
	row.add_child(save_first)
	var discard_first := Button.new()
	discard_first.text = "放弃修改并继续"
	discard_first.pressed.connect(_on_guard_discard)
	row.add_child(discard_first)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_on_guard_cancel)
	row.add_child(cancel)
	_guard_panel.add_child(row)
	return _guard_panel


func _build_list_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "Lists"
	column.custom_minimum_size = Vector2(300, 0)
	_list_title = Label.new()
	_list_title.text = "对话"
	column.add_child(_list_title)
	_id_list = ItemList.new()
	_id_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_id_list.custom_minimum_size = Vector2(0, 180)
	_id_list.item_selected.connect(_on_id_picked)
	column.add_child(_id_list)
	_node_title = Label.new()
	_node_title.text = "节点"
	column.add_child(_node_title)
	_node_list = ItemList.new()
	_node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_list.custom_minimum_size = Vector2(0, 180)
	_node_list.item_selected.connect(_on_node_picked)
	column.add_child(_node_list)
	return column


func _build_editor_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "Editor"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_scroll = ScrollContainer.new()
	_editor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_editor_scroll)
	_editor_box = VBoxContainer.new()
	_editor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_scroll.add_child(_editor_box)
	return column


func _build_structure_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "Structure"
	column.custom_minimum_size = Vector2(320, 0)
	var title := Label.new()
	title.text = "结构（只读）"
	column.add_child(title)
	_structure_box = TextEdit.new()
	_structure_box.editable = false
	_structure_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_structure_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_structure_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_structure_box)
	return column


func _build_message_area() -> Control:
	var column := VBoxContainer.new()
	column.name = "Messages"
	_status_label = Label.new()
	_status_label.text = ""
	column.add_child(_status_label)
	_status_text = TextEdit.new()
	_status_text.editable = false
	_status_text.custom_minimum_size = Vector2(0, 92)
	_status_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_status_text)
	return column


# --- switching units --------------------------------------------------------


func _open_kind(unit_kind: String) -> void:
	_kind = unit_kind
	_sync_kind_picker()
	var chapters := store.available_chapters(unit_kind)
	var is_ability := unit_kind == "abilities"
	_chapter_label.visible = not is_ability
	_chapter_picker.visible = not is_ability
	_fill_chapter_picker(chapters)
	var chapter: String = chapters[0] if not chapters.is_empty() else ""
	_open_unit(unit_kind, chapter)


func _sync_kind_picker() -> void:
	for index in KIND_ENTRIES.size():
		if String(KIND_ENTRIES[index]["kind"]) == _kind:
			_updating = true
			_kind_picker.select(index)
			_updating = false
			return


func _fill_chapter_picker(chapters: Array[String]) -> void:
	_updating = true
	_chapter_picker.clear()
	for chapter: String in chapters:
		_chapter_picker.add_item(chapter)
	_updating = false


func _open_unit(unit_kind: String, unit_chapter: String) -> void:
	_kind = unit_kind
	_chapter = unit_chapter
	_ids.clear()
	_nodes.clear()
	_hits.clear()
	_selected_id = ""
	_selected_node = -1
	var ok := store.open(unit_kind, unit_chapter)
	_list_title.text = String(LIST_TITLES.get(unit_kind, "内容"))
	_node_title.visible = unit_kind == "dialogue"
	_node_list.visible = unit_kind == "dialogue"
	if not ok:
		_id_list.clear()
		_node_list.clear()
		_clear_editor()
		_structure_box.text = ""
		_show_errors("打开失败：")
		return
	_ids = store.list_ids()
	_fill_id_list()
	_file_label.text = " · ".join(PackedStringArray(store.file_paths()))
	_report_warnings()
	if _ids.is_empty():
		_clear_editor()
		_set_status("这个内容类型下没有任何条目。", false)
	else:
		_id_list.select(0)
		_choose_id(_ids[0])
	_refresh_dirty()


func _fill_id_list() -> void:
	_updating = true
	_id_list.clear()
	if not _hits.is_empty():
		for hit: Dictionary in _hits:
			var locales: Array = hit.get("locales", [])
			# ItemList rows are single-line, so the snippet is joined with a separator
			# rather than a newline that would render as a missing glyph.
			_id_list.add_item(
				"%s · %s · %s"
				% [
					",".join(PackedStringArray(locales)),
					String(hit.get("label", "")),
					String(hit.get("snippet", "")),
				]
			)
	else:
		for id: String in _ids:
			_id_list.add_item(id)
	_updating = false


func _fill_node_list() -> void:
	_updating = true
	_node_list.clear()
	for entry: Dictionary in _nodes:
		_node_list.add_item(String(entry["label"]))
	_updating = false


# --- selections -------------------------------------------------------------


func _on_kind_picked(index: int) -> void:
	if _updating or index < 0 or index >= KIND_ENTRIES.size():
		return
	var unit_kind := String(KIND_ENTRIES[index]["kind"])
	if unit_kind == _kind:
		return
	_with_guard(func() -> void: _open_kind(unit_kind))


func _on_chapter_picked(index: int) -> void:
	if _updating:
		return
	var chapters := store.available_chapters(_kind)
	if index < 0 or index >= chapters.size():
		return
	var chapter := chapters[index]
	if chapter == _chapter:
		return
	_with_guard(func() -> void: _open_unit(_kind, chapter))


func _on_id_picked(index: int) -> void:
	if _updating or index < 0:
		return
	if not _hits.is_empty():
		var hit_index := index
		_with_guard(func() -> void: _jump_to_hit(hit_index))
		return
	if index >= _ids.size():
		return
	var id := _ids[index]
	_with_guard(func() -> void: _choose_id(id))


func _on_node_picked(index: int) -> void:
	if _updating or index < 0 or index >= _nodes.size():
		return
	if index == _selected_node:
		return
	_with_guard(func() -> void: _choose_node(index))


func _choose_id(id: String) -> void:
	_selected_id = id
	_selected_node = -1
	match _kind:
		"dialogue":
			_nodes = store.node_entries(id)
			_fill_node_list()
			if _nodes.is_empty():
				_clear_editor()
				_set_status("%s 里没有节点。" % id, false)
				return
			_choose_node(0)
		"inspections":
			_show_model(store.inspection_model(id))
		_:
			_show_model(store.ability_model(id))
	_refresh_dirty()


func _choose_node(index: int) -> void:
	if index < 0 or index >= _nodes.size():
		return
	_selected_node = index
	_updating = true
	_node_list.select(index)
	_updating = false
	_show_model(store.node_model(_selected_id, index))


func _hit_owner_id(hit: Dictionary) -> String:
	match _kind:
		"dialogue":
			return String(hit.get("conversation", ""))
		"inspections":
			return String(hit.get("inspection_id", ""))
		_:
			return String(hit.get("ability_id", ""))


func _jump_to_hit(index: int) -> void:
	if index < 0 or index >= _hits.size():
		return
	var hit: Dictionary = _hits[index]
	_updating = true
	_search_box.text = ""
	_updating = false
	_hits.clear()
	_fill_id_list()
	var id := _hit_owner_id(hit)
	var id_index := _ids.find(id)
	if id_index < 0:
		_set_status("这一条已经不在文件里了。", false)
		return
	_updating = true
	_id_list.select(id_index)
	_updating = false
	_pending_focus = String(hit.get("field_id", ""))
	if _kind == "dialogue":
		_selected_id = id
		_nodes = store.node_entries(id)
		_fill_node_list()
		_choose_node(int(hit.get("node_index", 0)))
		return
	_choose_id(id)


# --- the editor pane --------------------------------------------------------


func _clear_editor() -> void:
	_model_state = {}
	for child in _editor_box.get_children():
		_editor_box.remove_child(child)
		child.queue_free()


func _show_model(model: Dictionary) -> void:
	_clear_editor()
	_model_state = model
	_structure_box.text = String(model.get("structure_text", ""))
	var heading := Label.new()
	heading.text = String(model.get("title", ""))
	heading.add_theme_font_size_override("font_size", 20)
	_editor_box.add_child(heading)
	for row: Dictionary in model.get("header", []):
		_editor_box.add_child(_build_readonly_row(String(row["label"]), String(row["value"])))
	var fields: Array = model.get("fields", [])
	if fields.is_empty():
		var none := Label.new()
		none.text = "这一条没有可以编辑的文本。"
		_editor_box.add_child(none)
		_pending_focus = ""
		return
	for field: Dictionary in fields:
		_editor_box.add_child(_build_field_block(field))
	_pending_focus = ""


func _build_readonly_row(label_text: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(104, 0)
	row.add_child(label)
	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value_label)
	return row


func _build_field_block(field: Dictionary) -> Control:
	var block := VBoxContainer.new()
	var caption := Label.new()
	caption.text = String(field.get("label", ""))
	block.add_child(caption)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var values: Dictionary = field.get("values", {})
	var focus_taken := false
	for locale: String in store.locales:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size = Vector2(220, 0)
		var language := Label.new()
		language.text = "English" if locale == store.reference_locale else "简体中文"
		language.add_theme_font_size_override("font_size", 14)
		column.add_child(language)
		var edit := TextEdit.new()
		edit.text = String(values.get(locale, ""))
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size = Vector2(0, FIELD_HEIGHT)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(_on_field_changed.bind(field, locale, edit))
		column.add_child(edit)
		if not focus_taken and String(field.get("field_id", "")) == _pending_focus:
			edit.grab_focus()
			focus_taken = true
		row.add_child(column)
	block.add_child(row)
	return block


func _on_field_changed(field: Dictionary, locale: String, edit: TextEdit) -> void:
	if _updating:
		return
	if not store.set_field(field, locale, edit.text):
		_show_errors("这一处没有写进去：")
		return
	var values: Dictionary = field.get("values", {})
	values[locale] = edit.text
	_refresh_dirty()


# --- saving and status ------------------------------------------------------


func _on_save_pressed() -> void:
	_save_now()


func _save_now() -> bool:
	if not store.is_dirty():
		_set_status("没有需要保存的修改。", false)
		return true
	if not store.save():
		_show_errors("保存失败，磁盘上的文件没有改动：")
		_refresh_dirty()
		return false
	_set_status("已保存：%s" % "、".join(PackedStringArray(store.file_paths())), true)
	_refresh_dirty()
	_refresh_current()
	return true


func _on_validate_pressed() -> void:
	if not store.is_dirty():
		_set_status("没有未保存的修改，没有可校验的内容。", false)
		_status_text.text = ""
		return
	if store.validate():
		_set_status("校验通过：现在保存不会改变结构。", true)
		_status_text.text = ""
		return
	_show_errors("校验没有通过：")


func _on_discard_pressed() -> void:
	if not store.is_dirty():
		return
	store.discard_edits()
	_set_status("已放弃未保存的修改。", false)
	_refresh_dirty()
	_refresh_current()


func _on_reload_pressed() -> void:
	_with_guard(
		func() -> void:
			if not store.reload():
				_show_errors("重新读取失败：")
				return
			_ids = store.list_ids()
			_hits.clear()
			_fill_id_list()
			_refresh_dirty()
			_refresh_current()
			_set_status("已重新读取磁盘上的内容。", false)
	)


func _refresh_current() -> void:
	if _selected_id.is_empty():
		return
	if _kind == "dialogue":
		_nodes = store.node_entries(_selected_id)
		_fill_node_list()
		if _selected_node >= 0:
			_choose_node(_selected_node)
		return
	if _kind == "inspections":
		_show_model(store.inspection_model(_selected_id))
	else:
		_show_model(store.ability_model(_selected_id))


func _refresh_dirty() -> void:
	var dirty := store.is_dirty()
	_save_button.disabled = not dirty
	_discard_button.disabled = not dirty
	if not dirty:
		_dirty_label.text = "没有未保存的修改"
		return
	_dirty_label.text = (
		"有 %d 处未保存的修改：%s"
		% [store.edit_count(), "；".join(PackedStringArray(store.dirty_summary()))]
	)


func _set_status(message: String, success: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color", Color(0.45, 0.85, 0.5) if success else Color(0.95, 0.75, 0.45)
	)
	if success:
		_status_text.text = ""


func _show_errors(headline: String) -> void:
	_status_label.text = headline
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_status_text.text = store.describe_errors()


func _report_warnings() -> void:
	if store.warnings.is_empty():
		return
	_status_label.text = "内容有一处需要注意的地方（不影响编辑）"
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	_status_text.text = "\n".join(PackedStringArray(store.warnings))


# --- unsaved-change guard ---------------------------------------------------


func _with_guard(action: Callable) -> void:
	if not store.is_dirty():
		action.call()
		return
	_pending_action = action
	_guard_label.text = "有 %d 处未保存的修改，切换之前先决定怎么处理。" % store.edit_count()
	_guard_panel.visible = true
	# The selection the author just clicked is undone: the guard decides first, and the
	# action then runs against the selection that is still open.
	_updating = true
	if _hits.is_empty():
		var current := _ids.find(_selected_id)
		if current >= 0:
			_id_list.select(current)
	if _selected_node >= 0 and _selected_node < _nodes.size():
		_node_list.select(_selected_node)
	var chapter_index := store.available_chapters(_kind).find(_chapter)
	if chapter_index >= 0:
		_chapter_picker.select(chapter_index)
	_updating = false


func _on_guard_save() -> void:
	if not _save_now():
		return
	_run_pending()


func _on_guard_discard() -> void:
	store.discard_edits()
	_refresh_dirty()
	_run_pending()


func _on_guard_cancel() -> void:
	_pending_action = Callable()
	_guard_panel.visible = false
	_refresh_dirty()


func _run_pending() -> void:
	_guard_panel.visible = false
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


# --- search -----------------------------------------------------------------


func _on_search_changed(query: String) -> void:
	if _updating:
		return
	if query.strip_edges().is_empty():
		_hits.clear()
		_fill_id_list()
		_set_status("", false)
		_status_text.text = ""
		return
	_with_guard(
		func() -> void:
			_hits = store.search(query)
			for hit: Dictionary in _hits:
				hit["label"] = _hit_label(hit)
			_fill_id_list()
			_set_status("找到 %d 处。" % _hits.size(), false)
	)


func _hit_label(hit: Dictionary) -> String:
	match _kind:
		"dialogue":
			return "%s / %s / %s" % [
				String(hit.get("conversation", "")),
				String(hit.get("node_id", "")),
				String(hit.get("field_id", "")),
			]
		"inspections":
			return "%s / %s" % [
				String(hit.get("inspection_id", "")),
				String(hit.get("field_id", "")),
			]
		_:
			return "%s / %s" % [String(hit.get("ability_id", "")), String(hit.get("field_id", ""))]


# --- programmatic interface -------------------------------------------------


## Switches the panel to a content type, as if the author had picked it in the toolbar.
## Public because the capture run has to photograph three panels without a mouse, and
## because a future test may want to drive the dock the same way a person does.
func show_kind(unit_kind: String, unit_chapter: String = "") -> void:
	_kind = unit_kind
	_sync_kind_picker()
	var chapters := store.available_chapters(unit_kind)
	var chapter: String = unit_chapter
	if chapter.is_empty() and not chapters.is_empty():
		chapter = chapters[0]
	_fill_chapter_picker(chapters)
	_open_unit(unit_kind, chapter)
	var index := chapters.find(chapter)
	if index >= 0:
		_updating = true
		_chapter_picker.select(index)
		_updating = false


## Selects an entry by id: a conversation (and one of its nodes) for dialogue, an
## inspection id, or an ability id.
func show_entry(id: String, node_index: int = 0) -> void:
	var index := _ids.find(id)
	if index < 0:
		return
	_updating = true
	_id_list.select(index)
	_updating = false
	_hits.clear()
	_fill_id_list()
	_choose_id(id)
	if _kind == "dialogue" and node_index > 0:
		_choose_node(node_index)


## Puts text in the search box, as if it had been typed.
func search_for(query: String) -> void:
	_search_box.text = query
	_on_search_changed(query)


## Rebuilds the panel from the store: the status strip and the editor in front of the
## author. Used after a programmatic change.
func refresh() -> void:
	_refresh_dirty()
	_refresh_current()
