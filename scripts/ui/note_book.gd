class_name NoteBook
extends Control
## The protagonist's note page: everything recorded so far, grouped by provenance.
##
## The grouping is the point of this screen. "What I saw" is separated from "what
## I was told", "what I half-remember", and "what I only imagined", so the player
## can tell the difference between a fact and a rehearsal.

signal close_requested

@onready var close_button: Button = %CloseButton
@onready var empty_label: Label = %EmptyLabel

var _ledger: NarrativeLedger = null


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_request_close)


func bind_ledger(ledger: NarrativeLedger) -> void:
	_ledger = ledger


func open_notebook() -> void:
	visible = true
	refresh()


func close_notebook() -> void:
	visible = false


func refresh() -> void:
	var content_root: Node = %ContentRoot
	for child: Node in content_root.get_children():
		child.queue_free()

	if _ledger == null or _ledger.count() == 0:
		empty_label.visible = true
		return
	empty_label.visible = false

	var groups: Array = [
		{"kind": NarrativeProvenance.Kind.OBSERVED, "zh": "看到 / 亲手确认", "en": "Observed"},
		{"kind": NarrativeProvenance.Kind.HEARD, "zh": "听到的说法", "en": "Heard"},
		{"kind": NarrativeProvenance.Kind.RECOLLECTED, "zh": "记得的（不确定）", "en": "Remembered (uncertain)"},
		{"kind": NarrativeProvenance.Kind.IMAGINED, "zh": "想象的（没有发生）", "en": "Imagined (did not happen)"},
	]

	for group: Dictionary in groups:
		var entries: Array[NarrativeEntry] = _ledger.entries_of_kind(group["kind"])
		var box := VBoxContainer.new()
		box.name = "Group_%s" % group["en"].replace(" ", "_")
		box.add_theme_constant_override("separation", 10)

		var heading := Label.new()
		heading.text = Language.pick(group["zh"], group["en"])
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", _group_color(group["kind"]))
		box.add_child(heading)

		if entries.is_empty():
			var none := Label.new()
			none.text = Language.pick("（还没有）", "(nothing yet)")
			none.add_theme_color_override("font_color", Color(0.62, 0.63, 0.62))
			box.add_child(none)
		for entry: NarrativeEntry in entries:
			var line := RichTextLabel.new()
			line.fit_content = true
			line.scroll_active = false
			line.custom_minimum_size = Vector2(0, 0)
			line.bbcode_enabled = true
			line.text = Language.pick(entry.text_zh, entry.text_en)
			box.add_child(line)
		content_root.add_child(box)


func _group_color(kind: int) -> Color:
	match kind:
		NarrativeProvenance.Kind.OBSERVED:
			return Color(0.80, 0.82, 0.76)
		NarrativeProvenance.Kind.HEARD:
			return Color(0.86, 0.74, 0.52)
		NarrativeProvenance.Kind.RECOLLECTED:
			return Color(0.66, 0.72, 0.80)
		NarrativeProvenance.Kind.IMAGINED:
			return Color(0.72, 0.64, 0.72)
	return Color(0.8, 0.8, 0.8)


func _request_close() -> void:
	close_requested.emit()


func apply_language() -> void:
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("note_book") or event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
