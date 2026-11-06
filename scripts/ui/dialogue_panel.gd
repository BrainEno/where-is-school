class_name DialoguePanel
extends Control
## Presentation for conversations: speaker identity, body text, choices,
## backlog/history, and the visual separation of an imagined sequence.
##
## Content is authored in Chinese and English, but only ONE of them is ever on
## screen. `Language` decides which, and `apply_language()` re-renders the line
## that is currently open instead of leaving a mixed page behind.
##
## This node renders what it is told and reports player intent through signals. It
## never inspects GameState, never reads dialogue data, and never changes flags.

signal advance_requested
signal choice_selected(index: int)
signal closed

@export var text_reveal_chars_per_second: float = 45.0
@export var skip_reveal_on_advance: bool = true

@onready var speaker_label: Label = %SpeakerLabel
@onready var speaker_note_label: Label = %SpeakerNoteLabel
@onready var provenance_label: Label = %ProvenanceLabel
@onready var body_label: RichTextLabel = %BodyLabel
## Kept in the scene so older saved layouts do not break, but never shown: the
## panel displays one language at a time, not two stacked.
@onready var english_label: RichTextLabel = %EnglishLabel
@onready var choice_list: VBoxContainer = %ChoiceList
@onready var continue_hint: Label = %ContinueHint
@onready var aside_label: Label = %AsideLabel
@onready var backlog_panel: PanelContainer = %BacklogPanel
@onready var backlog_text: RichTextLabel = %BacklogText
@onready var imagined_border: Panel = %ImaginedBorder
@onready var imagined_caption: Label = %ImaginedCaption
@onready var advance_button: Button = %AdvanceButton
@onready var body_column: VBoxContainer = %BodyColumn

var _reveal_progress: float = 0.0
var _revealing: bool = false
var _full_text: String = ""
var _choice_buttons: Array[Button] = []
var _choice_data: Array[Dictionary] = []
var _backlog: Array[Dictionary] = []

## The current line, kept as an explicit pair so a language switch re-renders it
## without the panel needing to reach back into dialogue state.
var _current_speaker_zh: String = ""
var _current_speaker_en: String = ""
var _current_note_zh: String = ""
var _current_note_en: String = ""
var _current_text_zh: String = ""
var _current_text_en: String = ""
var _current_provenance_zh: String = ""
var _current_provenance_en: String = ""
var _current_style: StringName = &""
var _current_tint: Color = Color.WHITE
var _current_aside_zh: String = ""
var _current_aside_en: String = ""
var _imagined_mode: bool = false
var _backlog_open: bool = false


func _ready() -> void:
	visible = false
	english_label.visible = false
	choice_list.visible = false
	aside_label.visible = false
	backlog_panel.visible = false
	imagined_border.visible = false
	imagined_caption.visible = false
	advance_button.pressed.connect(_on_advance_pressed)
	set_process(false)


func open() -> void:
	visible = true
	_backlog_open = false
	backlog_panel.visible = false
	aside_label.visible = false
	_current_aside_zh = ""
	_current_aside_en = ""
	choice_list.visible = false
	_clear_choices()


func close() -> void:
	visible = false
	_clear_choices()
	_choice_buttons.clear()
	choice_list.visible = false
	backlog_panel.visible = false
	_backlog_open = false
	body_label.text = ""
	english_label.text = ""
	_choice_data.clear()
	_backlog.clear()
	_current_aside_zh = ""
	_current_aside_en = ""
	_imagined_mode = false
	modulate = Color(1, 1, 1, 1)
	speaker_label.text = ""
	speaker_note_label.text = ""
	provenance_label.text = ""
	aside_label.text = ""
	advance_button.visible = false
	continue_hint.visible = false
	set_process(false)
	closed.emit()


func show_line(
	speaker_zh: String,
	speaker_en: String,
	text_zh: String,
	text_en: String,
	tint: Color,
	provenance_zh: String,
	provenance_en: String,
	style: StringName,
	note_zh: String = "",
	note_en: String = ""
) -> void:
	# A new line clears the previous aside. PrologueFlow appends the new aside
	# *after* this call, so the aside stays on screen for exactly the line it
	# belongs to instead of flashing for one frame.
	_current_speaker_zh = speaker_zh
	_current_speaker_en = speaker_en
	_current_note_zh = note_zh
	_current_note_en = note_en
	_current_text_zh = text_zh
	_current_text_en = text_en
	_current_provenance_zh = provenance_zh
	_current_provenance_en = provenance_en
	_current_style = style
	_current_tint = tint
	_render_current_line(true)


## Renders whatever line is current in the selected language.
## `restart_reveal` is false when re-rendering after a language switch, because
## the player has already read that line and should not watch it type again.
func _render_current_line(restart_reveal: bool) -> void:
	var is_stage: bool = _current_style == &"stage" or _current_style == &"interior"
	speaker_label.text = _current_speaker_zh if not _current_speaker_zh.is_empty() \
		else _narrator(_current_style)
	# The name itself is never translated (Q is Q), so only the note below it and
	# a narrator label follow the language.
	speaker_note_label.text = Language.pick(_current_note_zh, _current_note_en)
	speaker_note_label.visible = not speaker_note_label.text.strip_edges().is_empty()
	speaker_label.add_theme_color_override("font_color", _current_tint)
	provenance_label.text = Language.pick(_current_provenance_zh, _current_provenance_en)

	var italic_open: String = "[i]" if is_stage else ""
	var italic_close: String = "[/i]" if is_stage else ""
	_full_text = "%s%s%s" % [
		italic_open,
		Language.pick(_current_text_zh, _current_text_en),
		italic_close,
	]
	body_label.text = _full_text
	if restart_reveal:
		_reveal_progress = 0.0
		_revealing = text_reveal_chars_per_second > 0.0
		body_label.visible_ratio = 0.0 if _revealing else 1.0
		set_process(_revealing)
	else:
		_revealing = false
		set_process(false)
		body_label.visible_ratio = 1.0
	set_process(_revealing)
	advance_button.visible = true
	advance_button.text = Language.kb("E", "继续", "continue")
	continue_hint.visible = false
	aside_label.visible = false
	aside_label.visible = false


## Public UI actions. Buttons and keyboard shortcuts call these, and so do the
## integration tests, so a test exercises the same path a player's input does.
func press_advance() -> void:
	_on_advance_pressed()


func select_choice(index: int) -> void:
	_on_choice_pressed(index)


func has_open_choices() -> bool:
	return choice_list.visible and not _choice_buttons.is_empty()


func choice_count() -> int:
	return _choice_buttons.size()


func set_line_continues(_continues: bool) -> void:
	continue_hint.visible = false


func show_choices(choices: Array[Dictionary]) -> void:
	_clear_choices()
	choice_list.visible = true
	continue_hint.visible = false
	_choice_data = choices.duplicate(true)
	_rebuild_choice_buttons()
	if not _choice_buttons.is_empty():
		_choice_buttons[0].grab_focus()


func _rebuild_choice_buttons() -> void:
	_clear_choices()
	for index: int in _choice_data.size():
		var data: Dictionary = _choice_data[index]
		var button := Button.new()
		button.name = "Choice%d" % index
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%d. %s" % [index + 1, Language.pick(str(data.get("zh", "")), str(data.get("en", "")))]
		button.pressed.connect(_on_choice_pressed.bind(index))
		choice_list.add_child(button)
		_choice_buttons.append(button)


func clear_choices() -> void:
	_clear_choices()
	choice_list.visible = false


func append_aside(text_zh: String, text_en: String) -> void:
	_current_aside_zh = text_zh
	_current_aside_en = text_en
	aside_label.text = Language.pick(text_zh, text_en)
	aside_label.visible = true


func show_continue_hint() -> void:
	continue_hint.visible = true
	continue_hint.text = Language.kb("E", "继续", "continue")
	advance_button.visible = true


func set_backlog(backlog: Array[Dictionary]) -> void:
	_backlog = backlog.duplicate(true)
	_render_backlog()


func _render_backlog() -> void:
	var separator: String = "：" if Language.is_zh() else ": "
	var indent: String = "　　" if Language.is_zh() else "    "
	var lines: PackedStringArray = PackedStringArray()
	for item: Dictionary in _backlog:
		var speaker: String = str(item.get("speaker_zh", ""))
		var text: String = Language.pick(str(item.get("text_zh", "")), str(item.get("text_en", "")))
		if speaker.is_empty():
			lines.append(indent + text)
		else:
			lines.append("%s%s%s" % [speaker, separator, text])
		lines.append("")
	backlog_text.text = "\n".join(lines)


func set_imagined_mode(enabled: bool) -> void:
	imagined_border.visible = enabled
	imagined_caption.visible = enabled
	imagined_caption.text = "（想象 / imagined）\n这不是发生过的事。 / This did not happen."
	if enabled:
		extra_ui_desaturate()


func extra_ui_desaturate() -> void:
	# A restrained treatment: the panel dims and cools, nothing in the world moves.
	modulate = Color(0.82, 0.86, 0.9, 1.0)


func _process(delta: float) -> void:
	if not _revealing:
		return
	_reveal_progress += delta * text_reveal_chars_per_second
	var total: float = maxf(float(body_label.get_total_character_count()), 1.0)
	body_label.visible_ratio = clampf(_reveal_progress / total, 0.0, 1.0)
	if body_label.visible_ratio >= 1.0:
		_finish_reveal()


func _finish_reveal() -> void:
	_revealing = false
	set_process(false)
	body_label.visible_ratio = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("backlog"):
		_toggle_backlog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _backlog_open:
			_toggle_backlog()
		elif _revealing and skip_reveal_on_advance:
			_finish_reveal()
		elif not choice_list.visible:
			advance_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not choice_list.visible:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := event as InputEventKey
		var number: int = int(key.unicode) - int(KEY_1) + 1
		if number >= 1 and number <= _choice_buttons.size():
			_on_choice_pressed(number - 1)
			get_viewport().set_input_as_handled()


func _toggle_backlog() -> void:
	_backlog_open = not _backlog_open
	backlog_panel.visible = _backlog_open


func _on_advance_pressed() -> void:
	if _revealing:
		_finish_reveal()
		return
	if not choice_list.visible:
		advance_requested.emit()


func _on_choice_pressed(index: int) -> void:
	if index < 0 or index >= _choice_buttons.size():
		return
	choice_selected.emit(index)


func _clear_choices() -> void:
	for button: Button in _choice_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_choice_buttons.clear()


func _narrator(style: StringName) -> String:
	if style == &"interior":
		return Language.pick("我", "me")
	return "——"


## Called when the player switches language while a line is on screen. The line
## is re-rendered, not restarted, and an open backlog follows along.
func apply_language() -> void:
	if not visible:
		return
	_render_current_line(false)
	if not _choice_data.is_empty() and choice_list.visible:
		var open_choices: bool = choice_list.visible
		_rebuild_choice_buttons()
		choice_list.visible = open_choices
	if not _current_aside_zh.is_empty():
		aside_label.text = Language.pick(_current_aside_zh, _current_aside_en)
	if _imagined_mode:
		set_imagined_mode(true)
	advance_button.text = Language.kb("E", "继续", "continue")
	_render_backlog()
