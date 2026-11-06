extends Control
class_name DialoguePanel
## Presentation layer for [DialogueSession]. Renders lines, choices, and the
## backlog, and reports player intent back through signals.
##
## The panel never reads or writes story state, never instantiates content, and
## never touches the world. It is driven entirely by the flow owner.
##
## Presentation rules worth knowing when editing this file:
## - A line's [member DialogueLine.imagined] flag switches the whole frame to the
##   "rehearsal" treatment (cool, dimmed, a standing caption), so an expectation
##   can never read as a thing that happened in the room.
## - Narration speakers (aside/caption) get no name plate.
## - Text reveals at [member text_speed] characters per second, with skip.

signal line_finished
signal advance_requested
signal choice_chosen(index: int)

const REHEARSAL_CAPTION := "Rehearsal — nothing here is happening in the room"

@export_category("Typography")
@export_range(18, 40, 1) var body_font_size: int = 21
@export_range(14, 26, 1) var speaker_font_size: int = 22
@export_range(20.0, 160.0, 1.0) var text_speed: float = 46.0
@export var auto_reveal_delay: float = 0.05

@onready var frame: PanelContainer = %Frame
@onready var speaker_label: Label = %SpeakerLabel
@onready var speaker_role: Label = %SpeakerRole
@onready var body_label: RichTextLabel = %BodyLabel
@onready var continuation: Label = %Continuation
@onready var choice_list: VBoxContainer = %ChoiceList
@onready var rehearsal_banner: PanelContainer = %RehearsalBanner
@onready var rehearsal_caption: Label = %RehearsalCaption
@onready var imagine_note: Label = %ImagineNote
@onready var portrait: TextureRect = %Portrait
@onready var backlog_layer: PanelContainer = %BacklogLayer
@onready var backlog_log: VBoxContainer = %Log

var _revealing: bool = false
var _reveal_progress: float = 0.0
var _reveal_length: int = 0
var _pending_choices: bool = false
var _last_history: Array = []


func _ready() -> void:
	visible = false
	rehearsal_banner.visible = false
	choice_list.visible = false
	continuation.visible = false
	imagine_note.visible = false
	backlog_layer.visible = false
	body_label.text = ""
	body_label.add_theme_font_size_override("normal_font_size", body_font_size)
	speaker_label.add_theme_font_size_override("font_size", speaker_font_size)


func is_open() -> bool:
	return visible


func set_text_speed(characters_per_second: float) -> void:
	text_speed = maxf(characters_per_second, 10.0)


func set_body_font_size(size: int) -> void:
	body_font_size = clampi(size, 16, 40)
	if body_label != null:
		body_label.add_theme_font_size_override("normal_font_size", body_font_size)


func open() -> void:
	visible = true
	choice_list.visible = false
	_pending_choices = false
	continuation.visible = false


func close() -> void:
	visible = false
	_revealing = false
	choice_list.visible = false
	_pending_choices = false
	rehearsal_banner.visible = false
	imagine_note.visible = false


## Shows one line. When [param imagined] is true the frame switches to the
## rehearsal treatment; when [param narration] is true the name plate is hidden.
func present_line(line: DialogueLine, imagined: bool, history: Array = []) -> void:
	open()
	_last_history = history.duplicate() if not history.is_empty() else _last_history
	var narration: bool = CharacterDirectory.is_narration(line.speaker)
	speaker_label.visible = not narration
	speaker_role.visible = not narration
	if not narration:
		speaker_label.text = CharacterDirectory.display_name(line.speaker)
		speaker_label.add_theme_color_override("font_color", CharacterDirectory.accent(line.speaker))
		var role_text: String = CharacterDirectory.role(line.speaker)
		speaker_role.text = role_text
		speaker_role.visible = not role_text.is_empty()
	else:
		speaker_label.text = ""

	_update_portrait(line.speaker, imagined)

	body_label.text = line.text
	body_label.visible_characters = 0
	_reveal_length = body_label.get_total_character_count()
	_reveal_progress = 0.0
	_revealing = true
	choice_list.visible = false
	_pending_choices = false
	continuation.visible = false
	_set_rehearsal_mode(imagined)


func present_choices(choices: Array) -> void:
	_revealing = false
	body_label.visible_characters = -1
	continuation.visible = false
	for child in choice_list.get_children():
		child.queue_free()
	choice_list.visible = true
	_pending_choices = true
	for index in choices.size():
		var choice: DialogueChoice = choices[index]
		var button := Button.new()
		button.name = "Choice%d" % index
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = ("%d. %s" % [index + 1, choice.text]) if choice.hint.is_empty() else ("%d. %s\n    %s" % [index + 1, choice.text, choice.hint])
		button.pressed.connect(_on_choice_pressed.bind(index))
		choice_list.add_child(button)
	_attach_choice_focus()


func is_waiting_for_choices() -> bool:
	return _pending_choices


func is_revealing() -> bool:
	return _revealing


## Finishes the text reveal instantly. Returns true if there was anything to skip.
func skip_reveal() -> bool:
	if not _revealing:
		return false
	_revealing = false
	body_label.visible_characters = -1
	continuation.visible = not _pending_choices
	line_finished.emit()
	return true


func _process(delta: float) -> void:
	if _revealing:
		_reveal_progress += text_speed * delta
		var shown := int(_reveal_progress)
		body_label.visible_characters = shown
		if shown >= _reveal_length:
			skip_reveal()
	else:
		# Slow, quiet pulse on the continuation mark.
		if continuation.visible:
			continuation.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 420.0))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _pending_choices:
		for index in 4:
			if event.is_action_pressed("interact_choice_%d" % (index + 1)):
				_on_choice_pressed(index)
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("backlog"):
			toggle_backlog()
			get_viewport().set_input_as_handled()
			return
		return
	if event.is_action_pressed("advance") or event.is_action_pressed("interact"):
		if not skip_reveal():
			advance_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("backlog"):
		toggle_backlog()
		get_viewport().set_input_as_handled()


## Opens or closes the transcript overlay. Closing returns focus to the choices.
func toggle_backlog() -> void:
	if backlog_layer.visible:
		backlog_layer.visible = false
		_attach_choice_focus()
		return
	show_backlog(_last_history)


func show_backlog(history: Array) -> void:
	_last_history = history.duplicate()
	for child in backlog_log.get_children():
		child.queue_free()
	if history.is_empty():
		var empty := Label.new()
		empty.text = "Nothing has been said yet."
		empty.theme_type_variation = &"SmallLabel"
		backlog_log.add_child(empty)
	for entry in history:
		backlog_log.add_child(_make_backlog_entry(entry))
	backlog_layer.visible = true
	if not history.is_empty():
		show_backlog(history)
	_scroll_backlog_to_end.call_deferred()


func is_backlog_open() -> bool:
	return backlog_layer.visible


func _scroll_backlog_to_end() -> void:
	var scroll := %BacklogLayer.get_node("Margin/Rows/Scroll") as ScrollContainer
	if scroll == null:
		return
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _make_backlog_entry(entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var name_text: String = String(entry.get("name", ""))
	var imagined: bool = bool(entry.get("imagined", false))
	var header := Label.new()
	header.theme_type_variation = &"SmallLabel"
	if String(entry.get("speaker", "")) == "aside" or name_text.is_empty():
		header.text = "Rehearsal" if imagined else "—"
	else:
		header.text = name_text + ("   (imagined)" if imagined else "")
	header.add_theme_color_override("font_color", Color(0.6, 0.66, 0.7) if imagined else Color(0.66, 0.66, 0.62))
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = String(entry.get("text", ""))
	body.add_theme_color_override("default_color", Color(0.74, 0.79, 0.84) if imagined else Color(0.87, 0.86, 0.82))
	row.add_child(header)
	row.add_child(body)
	return row


func _on_choice_pressed(index: int) -> void:
	if not _pending_choices:
		return
	if index >= choice_list.get_child_count():
		return
	_pending_choices = false
	choice_list.visible = false
	choice_chosen.emit(index)


func _attach_choice_focus() -> void:
	if choice_list.get_child_count() == 0:
		return
	var first := choice_list.get_child(0) as Control
	if first != null:
		first.grab_focus.call_deferred()


func _update_portrait(speaker_id: StringName, imagined: bool) -> void:
	var path: String = CharacterDirectory.portrait_path(speaker_id, imagined)
	if path.is_empty():
		portrait.visible = false
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		push_warning("DialoguePanel: portrait '%s' could not be loaded." % path)
		portrait.visible = false
		return
	portrait.texture = texture
	portrait.visible = true
	portrait.modulate = Color(0.78, 0.84, 0.9) if imagined else Color(1, 1, 1)
	if CharacterDirectory.is_narration(speaker_id):
		portrait.visible = false


func _set_rehearsal_mode(enabled: bool) -> void:
	rehearsal_banner.visible = enabled
	imagine_note.visible = false
	if enabled:
		rehearsal_caption.text = REHEARSAL_CAPTION
		frame.modulate = Color(0.86, 0.9, 0.95, 1.0)
		body_label.modulate = Color(0.8, 0.84, 0.9, 1.0)
	else:
		frame.modulate = Color(1, 1, 1, 1)
		body_label.modulate = Color(1, 1, 1, 1)
