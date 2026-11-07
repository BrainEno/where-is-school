class_name DialoguePanel
extends Control
## View for dialogue and inspection text. Owns presentation only.
##
## It renders a line, its speaker, the narrative category badge, and any choices;
## it translates input into intents (`advance_requested`, `choice_selected`) and
## leaves story state to the DialogueController. Long text reveals at a readable
## speed, and the first advance press completes the reveal instead of skipping
## the line.

signal advance_requested
signal choice_selected(index: int)
signal backlog_requested

## Characters revealed per second. Raising it also raises the "instant" feel.
@export var characters_per_second: float = 55.0
## Extra characters revealed per frame while holding the advance key.
@export var skip_multiplier: float = 8.0

@onready var _speaker_label: Label = %SpeakerLabel
@onready var _role_label: Label = %RoleLabel
@onready var _badge_label: Label = %SourceBadge
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _choices_container: VBoxContainer = %ChoicesContainer
@onready var _hint_label: Label = %HintLabel
@onready var _frame: PanelContainer = %Frame

const SOURCE_COLORS: Dictionary = {
	NarrativeEntry.Source.OBSERVED: Color(0.776, 0.733, 0.643, 1.0),
	NarrativeEntry.Source.REPORTED: Color(0.561, 0.663, 0.710, 1.0),
	NarrativeEntry.Source.RECALLED: Color(0.604, 0.639, 0.592, 1.0),
	NarrativeEntry.Source.IMAGINED: Color(0.820, 0.553, 0.349, 1.0),
}

const SUBJECTIVE_TINT := Color(0.717, 0.427, 0.286, 1.0)

var _reveal_progress: float = 0.0
var _revealing: bool = false
var _choice_buttons: Array[Button] = []
var _line: Dictionary = {}


func _ready() -> void:
	hide()
	_choices_container.hide()
	_hint_label.hide()
	refresh_static_text()


func show_line(line: Dictionary) -> void:
	_line = line
	show()
	_move_to_front()

	_speaker_label.text = String(line.get("speaker_name", ""))
	var role_text := String(line.get("speaker_role", ""))
	_role_label.text = role_text
	_role_label.visible = not role_text.is_empty()
	_speaker_label.add_theme_color_override("font_color", line.get("accent_color", Color.WHITE))

	# The badge is stored as a locale key by the runtime/controller.
	var badge_key := String(line.get("badge", ""))
	var badge := L10n.t(badge_key) if not badge_key.is_empty() else ""
	_badge_label.text = badge
	_badge_label.visible = not badge.is_empty()
	var source_value := int(line.get("source", NarrativeEntry.Source.OBSERVED))
	var badge_color: Color = SOURCE_COLORS.get(source_value, Color.WHITE)
	_badge_label.add_theme_color_override("font_color", badge_color)
	if line.get("subjective", false):
		badge_color = SUBJECTIVE_TINT
		_badge_label.add_theme_color_override("font_color", badge_color)
		_speaker_label.add_theme_color_override("font_color", SUBJECTIVE_TINT)
	var border_color: Color = badge_color
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.106, 0.118, 0.118, 0.94)
	style.border_color = Color(border_color.r, border_color.g, border_color.b, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_frame.add_theme_stylebox_override("panel", style)

	var title := String(line.get("title", ""))
	_title_label.text = title
	_title_label.visible = not title.is_empty()

	_body_label.text = String(line.get("text", ""))
	_body_label.visible_characters = 0
	_reveal_progress = 0.0
	_revealing = _body_label.text.length() > 0

	set_choices([])
	refresh_static_text()
	_hint_label.show()
	_update_hint_visibility()


func set_choices(choices: Array) -> void:
	for button in _choice_buttons:
		button.queue_free()
	_choice_buttons.clear()
	_choices_container.hide()
	# Reserve space for up to three optional check choices without crowding the
	# fixed-height panel. Restore the normal reading area on non-choice lines.
	if _body_label != null:
		_body_label.custom_minimum_size.y = 52.0 if not choices.is_empty() else 116.0
	if choices.is_empty():
		return

	for index in choices.size():
		var choice: Dictionary = choices[index]
		var button := Button.new()
		button.text = "%d. %s" % [index + 1, String(choice.get("text", ""))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 20)
		button.custom_minimum_size = Vector2(0.0, 40.0)
		button.pressed.connect(_on_choice_button_pressed.bind(index))
		_choices_container.add_child(button)
		_choice_buttons.append(button)
	_choices_container.show()
	if _revealing:
		complete_reveal()
	refresh_static_text()
	_update_hint_visibility()


func close() -> void:
	hide()
	_line = {}
	_revealing = false
	set_choices([])


## Text of the source badge currently shown, for the language switch and tests.
func get_speaker_badge_text() -> String:
	return _badge_label.text if _badge_label != null else ""


func get_speaker_text() -> String:
	return _speaker_label.text if _speaker_label != null else ""


func is_revealing() -> bool:
	return _revealing


func complete_reveal() -> void:
	if not _revealing:
		return
	_body_label.visible_characters = _body_label.text.length()
	_revealing = false


func has_choices() -> bool:
	return not _choice_buttons.is_empty()


## Re-resolves every string the panel owns. Called on language switches and
## whenever a line is shown, so hints and badges never stay in the old language.
func refresh_static_text() -> void:
	if _hint_label == null:
		return
	if has_choices():
		_hint_label.text = L10n.t("ui.dialogue_choose", {"count": _choice_buttons.size()})
	else:
		_hint_label.text = L10n.t("ui.dialogue_continue")
	if not _line.is_empty():
		var badge_key := String(_line.get("badge", ""))
		if not badge_key.is_empty():
			_badge_label.text = L10n.t(badge_key)
		var role_key_source := String(_line.get("speaker_id", ""))
		if not role_key_source.is_empty():
			_role_label.text = L10n.t("role.%s" % role_key_source) \
				if L10n.has_key("role.%s" % role_key_source) else _role_label.text


## Redraws the line that is already on screen, used by a language switch.
func redraw_current_line() -> void:
	if _line.is_empty():
		return
	var line := _line
	line["badge"] = String(line.get("badge", ""))
	show_line(line)


func _process(delta: float) -> void:
	if not _revealing:
		return
	var direction := 1.0
	if Input.is_action_pressed("dialogue_advance"):
		direction = skip_multiplier
	_reveal_progress += characters_per_second * direction * delta
	var total := _body_label.text.length()
	_body_label.visible_characters = mini(int(_reveal_progress), total)
	if _body_label.visible_characters >= total:
		_revealing = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("backlog"):
		get_viewport().set_input_as_handled()
		backlog_requested.emit()
		return

	if has_choices():
		var index := _digit_from_event(event)
		if index >= 0 and index < _choice_buttons.size():
			get_viewport().set_input_as_handled()
			choice_selected.emit(index)
		return

	if event.is_action_pressed("dialogue_advance"):
		get_viewport().set_input_as_handled()
		if _revealing:
			complete_reveal()
			return
		advance_requested.emit()


## Returns a zero-based choice index when the event is a digit key.
func _digit_from_event(event: InputEvent) -> int:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return -1
	var code := key_event.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1)
	return -1


func _on_choice_button_pressed(index: int) -> void:
	choice_selected.emit(index)


func _update_hint_visibility() -> void:
	_hint_label.visible = visible


func _move_to_front() -> void:
	# Keep the dialogue above the HUD without reordering the scene at edit time.
	if get_parent() is Control:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
