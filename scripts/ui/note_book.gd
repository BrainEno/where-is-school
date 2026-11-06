extends Control
class_name NoteBook
## The in-game notes page: a read-only view of the NarrativeLedger, grouped by
## how the player came to know each thing.
##
## The four groups are not a stylistic choice. They are the feature: the player
## can always check whether something was seen, said, half-remembered, or only
## imagined. The notebook reads the ledger and writes nothing.

signal closed

@onready var columns: HBoxContainer = %Columns
@onready var header: Label = %Header
@onready var footer: Label = %Footer
@onready var empty_label: Label = %EmptyLabel

var _open: bool = false


func _ready() -> void:
	visible = false
	footer.text = "N or Esc to close"


func is_open() -> bool:
	return _open


func open(ledger: Node) -> void:
	_open = true
	visible = true
	_refresh(ledger)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func toggle(ledger: Node) -> void:
	if _open:
		close()
	else:
		open(ledger)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("notebook") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh(ledger: Node) -> void:
	for child in columns.get_children():
		child.queue_free()

	var groups := [
		{"kind": NarrativeRecord.Kind.OBSERVED, "title": "Seen", "note": "You were there for this."},
		{"kind": NarrativeRecord.Kind.HEARD, "title": "Heard", "note": "Someone said it. That is not the same as it being true."},
		{"kind": NarrativeRecord.Kind.RECALLED, "title": "Remembered", "note": "Yours, and not reliable."},
		{"kind": NarrativeRecord.Kind.IMAGINED, "title": "Imagined", "note": "Rehearsed, not observed. Did not happen."},
	]

	var total := 0
	for group in groups:
		var entries: Array = ledger.records_of_kind(group["kind"])
		total += entries.size()
		columns.add_child(_make_column(String(group["title"]), String(group["note"]), entries, group["kind"]))

	header.text = "Notes — %d entries" % total
	empty_label.visible = total == 0


func _make_column(title: String, note: String, entries: Array, kind: NarrativeRecord.Kind) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)

	var heading := Label.new()
	heading.text = "%s  (%d)" % [title, entries.size()]
	heading.theme_type_variation = &"HeadingLabel"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", _kind_color(kind))
	column.add_child(heading)

	var rule := Label.new()
	rule.text = note
	rule.theme_type_variation = &"SmallLabel"
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	column.add_child(scroll)

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "—"
		empty.theme_type_variation = &"SmallLabel"
		list.add_child(empty)
	else:
		for record in entries:
			list.add_child(_make_entry(record, kind))
	return column


func _make_entry(record: NarrativeRecord, kind: NarrativeRecord.Kind) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = record.title
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", _kind_color(kind))
	entry.add_child(title)
	if not record.body.is_empty():
		var body := Label.new()
		body.text = record.body
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.theme_type_variation = &"SmallLabel"
		entry.add_child(body)
	return entry


func _kind_color(kind: NarrativeRecord.Kind) -> Color:
	match kind:
		NarrativeRecord.Kind.OBSERVED:
			return Color(0.8, 0.83, 0.78)
		NarrativeRecord.Kind.HEARD:
			return Color(0.9, 0.76, 0.55)
		NarrativeRecord.Kind.RECALLED:
			return Color(0.72, 0.75, 0.8)
		NarrativeRecord.Kind.IMAGINED:
			return Color(0.62, 0.72, 0.8)
	return Color(0.8, 0.8, 0.8)
