class_name DialogueBox
extends Control
## Renders a DialogueRunner conversation: speaker, body, choices, backlog.
## Presentation only — story truth lives in GameState via the runner.
## Imagination conversations show a banner and tinted frame; they can
## never be confused with observed events from inside this panel.

signal conversation_closed(conversation_id: StringName)

const SPEAKER_PATHS: Dictionary = {
	&"q": "res://data/characters/q.tres",
	&"n": "res://data/characters/n.tres",
	&"narrator": "res://data/characters/narrator.tres",
	&"inner": "res://data/characters/inner.tres",
	&"imagination": "res://data/characters/imagination.tres",
}
const BASE_SIZES: Dictionary = {
	"speaker": 22,
	"body": 23,
	"choices": 21,
	"portrait": 60,
	"hint": 13,
	"backlog": 18,
}

@onready var _panel: PanelContainer = $Panel
@onready var _imagination_tint: ColorRect = $ImaginationTint
@onready var _imagination_banner: Label = $ImaginationBanner
@onready var _speaker_label: Label = $Panel/MarginContainer/HBox/VBox/SpeakerLabel
@onready var _body_label: RichTextLabel = $Panel/MarginContainer/HBox/VBox/BodyText
@onready var _choices_container: VBoxContainer = $Panel/MarginContainer/HBox/VBox/ChoicesContainer
@onready var _advance_hint: Label = $Panel/MarginContainer/HBox/VBox/AdvanceHint
@onready var _portrait_panel: PanelContainer = $Panel/MarginContainer/HBox/PortraitBox
@onready var _portrait_label: Label = $Panel/MarginContainer/HBox/PortraitBox/PortraitInitial
@onready var _backlog_panel: Control = $BacklogPanel
@onready var _backlog_text: RichTextLabel = $BacklogPanel/PanelContainer/VBox/ScrollContainer/BacklogText
@onready var _audio: AudioStreamPlayer = $AudioStreamPlayer

var runner: DialogueRunner = null
var _conversation_id: StringName = &""
var _typing: bool = false
var _type_progress: float = 0.0
var _full_text: String = ""
var _session_backlog: Array[Dictionary] = []
var _imagination: bool = false
var _speakers: Dictionary = {}
var _portrait_style: StyleBoxFlat


func _ready() -> void:
	_panel.visible = false
	_backlog_panel.visible = false
	_imagination_tint.visible = false
	_imagination_banner.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_style = StyleBoxFlat.new()
	_portrait_style.bg_color = Color(0.4, 0.4, 0.4)
	_portrait_style.corner_radius_top_left = 6
	_portrait_style.corner_radius_top_right = 6
	_portrait_style.corner_radius_bottom_left = 6
	_portrait_style.corner_radius_bottom_right = 6
	_portrait_panel.add_theme_stylebox_override("panel", _portrait_style)
	_load_speakers()
	_audio.stream = SfxBank.ui_blip()


func _load_speakers() -> void:
	for speaker_id in SPEAKER_PATHS:
		var path: String = SPEAKER_PATHS[speaker_id]
		if ResourceLoader.exists(path):
			var def := load(path) as CharacterDef
			if def != null:
				_speakers[speaker_id] = def
				continue
			push_error("DialogueBox: %s is not a CharacterDef" % path)
		else:
			push_error("DialogueBox: missing speaker definition %s" % path)


func start(conversation: DialogueConversation, start_override: StringName = &"") -> bool:
	if conversation == null:
		push_error("DialogueBox.start: null conversation")
		return false
	var state: Node = get_tree().get_root().get_node_or_null("GameState")
	if state == null:
		push_error("DialogueBox.start: /root/GameState not found")
	runner = DialogueRunner.new(state)
	runner.line_shown.connect(_on_line_shown)
	runner.choices_shown.connect(_on_choices_shown)
	runner.conversation_finished.connect(_on_conversation_finished)
	if not runner.start(conversation, start_override):
		_show_error_line("This conversation is broken. (see console)")
		return false
	_conversation_id = conversation.id
	_imagination = conversation.presentation == "imagination"
	_imagination_tint.visible = _imagination
	_imagination_banner.visible = _imagination
	_panel.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _imagination:
		_audio.stream = SfxBank.imagination_swell()
		_audio.play()
	return true


func is_open() -> bool:
	return _panel.visible


func is_backlog_open() -> bool:
	return _backlog_panel.visible


func toggle_backlog() -> void:
	_backlog_panel.visible = not _backlog_panel.visible
	if _backlog_panel.visible:
		_rebuild_backlog()


func close_backlog() -> void:
	_backlog_panel.visible = false


func session_backlog_size() -> int:
	return _session_backlog.size()


func advance_pressed() -> void:
	if not is_open() or runner == null:
		return
	if _typing:
		_complete_typing()
		return
	if not _current_choices_empty():
		return
	runner.advance()


func apply_text_scale(factor: float) -> void:
	_speaker_label.add_theme_font_size_override("font_size", int(round(BASE_SIZES["speaker"] * factor)))
	_body_label.add_theme_font_size_override("font_size", int(round(BASE_SIZES["body"] * factor)))
	for button in _choices_container.get_children():
		if button is Button:
			button.add_theme_font_size_override("font_size", int(round(BASE_SIZES["choices"] * factor)))
	_portrait_label.add_theme_font_size_override("font_size", int(round(BASE_SIZES["portrait"] * factor)))
	_advance_hint.add_theme_font_size_override("font_size", int(round(BASE_SIZES["hint"] * factor)))
	_backlog_text.add_theme_font_size_override("font_size", int(round(BASE_SIZES["backlog"] * factor)))


func _process(delta: float) -> void:
	if _typing:
		_type_progress += _typewriter_cps() * delta
		var shown: int = min(int(_type_progress), _full_text.length())
		_body_label.visible_characters = shown
		if shown >= _full_text.length():
			_complete_typing()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance_pressed()
		accept_event()


func _on_line_shown(entry: DialogueEntry) -> void:
	var def: CharacterDef = _speaker_def(entry.speaker_id)
	_speaker_label.text = def.display_name if def else str(entry.speaker_id)
	_full_text = entry.text
	_body_label.text = _full_text
	_body_label.visible_characters = 0
	_typing = true
	_type_progress = 0.0
	_advance_hint.visible = false
	_clear_choices()
	if def != null:
		_portrait_panel.visible = true
		_portrait_label.text = def.initial()
		_portrait_style.bg_color = def.portrait_color
		_speaker_label.add_theme_color_override("font_color", def.portrait_color.lightened(0.35))
	else:
		_portrait_panel.visible = false
	if def != null and def.kind == "narration":
		_portrait_panel.visible = false
	var backlog_kind: String = def.kind if def != null else "character"
	_session_backlog.append({
		"speaker": def.display_name if def else str(entry.speaker_id),
		"text": entry.text,
		"kind": backlog_kind,
	})
	_audio.stream = SfxBank.ui_blip()
	_audio.play()


func _on_choices_shown(choices: Array) -> void:
	_clear_choices()
	for choice in choices:
		if choice == null:
			continue
		var button := Button.new()
		button.text = String(choice.text)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_make_choice_handler(choice))
		button.add_theme_font_size_override("font_size", int(round(BASE_SIZES["choices"] * _font_scale())))
		button.custom_minimum_size = Vector2(0, 38)
		_choices_container.add_child(button)
	# Buttons stay hidden until the typewriter finishes.
	_set_choices_visible(false)


func _reveal_choices_if_ready() -> void:
	if runner == null:
		return
	var offered := runner.visible_choices()
	if offered.is_empty():
		_set_choices_visible(false)
		return
	_set_choices_visible(true)
	var first_button: Button = null
	for child in _choices_container.get_children():
		if child is Button:
			first_button = child
			break
	if first_button != null:
		first_button.grab_focus()


func _current_choices_empty() -> bool:
	return _choices_container.get_child_count() == 0


func _clear_choices() -> void:
	for child in _choices_container.get_children():
		child.free()


func _set_choices_visible(value: bool) -> void:
	for child in _choices_container.get_children():
		child.visible = value


func _complete_typing() -> void:
	_typing = false
	_type_progress = float(_full_text.length())
	_body_label.visible_characters = _full_text.length()
	_advance_hint.visible = true
	_reveal_choices_if_ready()


func _make_choice_handler(choice: DialogueChoice) -> Callable:
	return func() -> void:
		if runner == null:
			return
		runner.choose(choice)


func _on_conversation_finished(conversation_id: StringName) -> void:
	_panel.visible = false
	_imagination_tint.visible = false
	_imagination_banner.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_choices()
	runner = null
	var closed_id: StringName = _conversation_id if _conversation_id != &"" else conversation_id
	_conversation_id = &""
	conversation_closed.emit(closed_id)


func _rebuild_backlog() -> void:
	var lines: Array[String] = []
	for entry in _session_backlog:
		var speaker: String = String(entry.get("speaker", ""))
		var text: String = String(entry.get("text", ""))
		if speaker.strip_edges().is_empty():
			lines.append(text)
		else:
			lines.append("%s:\n%s" % [speaker, text])
	if lines.is_empty():
		lines.append("Nothing has happened yet.")
	_backlog_text.text = "\n\n".join(lines)


func _speaker_def(speaker_id: StringName) -> CharacterDef:
	if _speakers.has(speaker_id):
		return _speakers[speaker_id]
	return null


func _show_error_line(message: String) -> void:
	_panel.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_speaker_label.text = "!"
	_body_label.text = message
	_body_label.visible_characters = message.length()
	_advance_hint.visible = true
