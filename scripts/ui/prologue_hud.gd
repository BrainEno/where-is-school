extends CanvasLayer
class_name PrologueHUD
## Presentation only: receives dialogue entries and emits player intent.

signal advance_requested
signal choice_requested(index: int)
signal history_visibility_changed(opened: bool)
signal wait_requested
signal resume_requested
signal restart_requested

@onready var location_label: Label = %Location
@onready var objective_label: Label = %Objective
@onready var controls: Label = %Controls
@onready var prompt: PanelContainer = %Prompt
@onready var prompt_text: Label = %PromptText
@onready var dialogue: PanelContainer = %Dialogue
@onready var portrait: Label = %PortraitText
@onready var speaker: Label = %Speaker
@onready var kind_label: Label = %Kind
@onready var body: RichTextLabel = %Body
@onready var choices: HBoxContainer = %Choices
@onready var dialogue_hint: Label = %DialogueHint
@onready var subjective_wash: ColorRect = %SubjectiveWash
@onready var backlog: ColorRect = %Backlog
@onready var backlog_scroll: ScrollContainer = %Scroll
@onready var backlog_entries: VBoxContainer = %Entries
@onready var ending: ColorRect = %Ending
@onready var fade: ColorRect = %Fade
@onready var opening_card: VBoxContainer = %OpeningCard
@onready var history_button: Button = %HistoryButton
@onready var speed_button: Button = %Speed
@onready var resume_button: Button = %Resume

var runner: DialogueRunner
var wait_available: bool = false
var text_size: int = 27
var instant_text: bool = true
var _typing: bool = false
var _typing_progress: float = 0.0
var _selected_choice: int = 0
var _choice_data: Array = []


func _ready() -> void:
	history_button.pressed.connect(toggle_history)
	%CloseHistory.pressed.connect(toggle_history)
	%Smaller.pressed.connect(_change_text_size.bind(-2))
	%Larger.pressed.connect(_change_text_size.bind(2))
	speed_button.pressed.connect(_toggle_speed)
	resume_button.pressed.connect(_on_resume)
	%Restart.pressed.connect(func() -> void: restart_requested.emit())


func bind_dialogue(dialogue_runner: DialogueRunner) -> void:
	runner = dialogue_runner
	runner.conversation_started.connect(_on_conversation_started)
	runner.line_presented.connect(_on_line_presented)
	runner.conversation_finished.connect(_on_conversation_finished)


func set_objective(location: String, objective: String) -> void:
	location_label.text = location.to_upper()
	objective_label.text = objective


func set_prompt(target: Interactable) -> void:
	prompt.visible = is_instance_valid(target) and not dialogue.visible and not backlog.visible and not ending.visible
	if prompt.visible:
		prompt_text.text = "E    " + target.prompt


func set_wait_available(value: bool) -> void:
	wait_available = value
	if value:
		controls.text = "WASD / ARROWS  MOVE     ·     E  INTERACT     ·     SPACE  WAIT FOR CLASS     ·     H  HISTORY"
	else:
		controls.text = "WASD / ARROWS  MOVE     ·     E  INTERACT     ·     H  HISTORY"


func play_wake_fade(duration: float) -> void:
	fade.color.a = 1.0
	opening_card.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(duration * 0.35)
	tween.tween_property(fade, "color:a", 0.0, duration * 0.65)
	tween.parallel().tween_property(opening_card, "modulate:a", 0.0, duration * 0.65)
	tween.tween_callback(func() -> void: opening_card.visible = false)


func fade_to_black(duration: float = 0.25) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade, "color:a", 1.0, duration)
	await tween.finished


func fade_from_black(duration: float = 0.25) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade, "color:a", 0.0, duration)
	await tween.finished


func show_ending() -> void:
	ending.visible = true
	prompt.visible = false
	resume_button.grab_focus()


func toggle_history() -> void:
	if ending.visible:
		return
	backlog.visible = not backlog.visible
	if backlog.visible:
		_rebuild_history()
		prompt.visible = false
		%CloseHistory.grab_focus()
	elif dialogue.visible and not _choice_data.is_empty() and not _typing:
		_focus_choice(_selected_choice)
	history_visibility_changed.emit(backlog.visible)


func _on_resume() -> void:
	ending.visible = false
	resume_requested.emit()


func _on_conversation_started(_id: StringName) -> void:
	dialogue.visible = true
	prompt.visible = false
	controls.visible = false


func _on_line_presented(entry: Dictionary) -> void:
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	_choice_data = entry.get("choices", [])
	_selected_choice = 0
	var entry_kind: String = str(entry["kind"])
	speaker.text = str(entry["speaker"])
	portrait.text = _portrait_for(speaker.text, entry_kind)
	kind_label.text = _kind_description(speaker.text, entry_kind)
	subjective_wash.visible = entry_kind == "imagination"
	body.text = str(entry["text"])
	body.add_theme_font_size_override("normal_font_size", text_size)
	body.scroll_to_line(0)
	_typing = not instant_text
	_typing_progress = 0.0
	body.visible_characters = 0 if _typing else -1
	if not _typing:
		_show_choices_or_hint()
	else:
		dialogue_hint.text = "E / ENTER  SHOW FULL TEXT                         H  HISTORY"


func _process(delta: float) -> void:
	if not _typing or backlog.visible:
		return
	_typing_progress += delta * 45.0
	body.visible_characters = int(_typing_progress)
	if body.visible_characters >= body.get_total_character_count():
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	body.visible_characters = -1
	_show_choices_or_hint()


func _show_choices_or_hint() -> void:
	if _choice_data.is_empty():
		dialogue_hint.text = "E / ENTER  CONTINUE                         H  HISTORY"
		return
	for i: int in range(_choice_data.size()):
		var option: Dictionary = _choice_data[i]
		var button: Button = Button.new()
		button.text = "%d   %s" % [i + 1, option["text"]]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 62)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", maxi(text_size - 6, 18))
		button.add_theme_color_override("font_color", Color("e7e6d9"))
		button.add_theme_color_override("font_hover_color", Color("fff4d9"))
		button.add_theme_stylebox_override("normal", history_button.get_theme_stylebox("normal"))
		button.add_theme_stylebox_override("hover", history_button.get_theme_stylebox("hover"))
		button.add_theme_stylebox_override("focus", history_button.get_theme_stylebox("hover"))
		button.add_theme_stylebox_override("pressed", history_button.get_theme_stylebox("hover"))
		button.pressed.connect(_emit_choice.bind(i))
		button.focus_entered.connect(_on_choice_focused.bind(i))
		choices.add_child(button)
	dialogue_hint.text = "ARROWS  CHOOSE     ·     E / ENTER  SELECT     ·     H  HISTORY"
	if not backlog.visible:
		_focus_choice(_selected_choice)


func _emit_choice(index: int) -> void:
	choice_requested.emit(index)


func _on_choice_focused(index: int) -> void:
	_selected_choice = index


func _focus_choice(index: int) -> void:
	if index >= 0 and index < choices.get_child_count():
		var button: Button = choices.get_child(index) as Button
		if button:
			button.grab_focus()


func _on_conversation_finished(_id: StringName) -> void:
	dialogue.visible = false
	controls.visible = true
	subjective_wash.visible = false
	_typing = false
	_choice_data = []


func _input(event: InputEvent) -> void:
	# Godot's automatic focus navigation can otherwise move focus to the text
	# widget before _unhandled_input sees an arrow. Resolve choices first.
	if event.is_echo() or backlog.visible or ending.visible or not dialogue.visible or _typing or _choice_data.is_empty():
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		var direction: int = -1 if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") else 1
		_selected_choice = posmod(_selected_choice + direction, _choice_data.size())
		_focus_choice(_selected_choice)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("history"):
		toggle_history()
		get_viewport().set_input_as_handled()
		return
	if backlog.visible:
		if event.is_action_pressed("ui_cancel"):
			toggle_history()
		elif event.is_action_pressed("ui_page_up"):
			backlog_scroll.scroll_vertical -= int(backlog_scroll.size.y * 0.8)
		elif event.is_action_pressed("ui_page_down"):
			backlog_scroll.scroll_vertical += int(backlog_scroll.size.y * 0.8)
		get_viewport().set_input_as_handled()
		return
	if ending.visible:
		if event.is_action_pressed("ui_cancel"):
			_on_resume()
			get_viewport().set_input_as_handled()
		return
	if dialogue.visible:
		if event.is_action_pressed("advance"):
			if _typing:
				_finish_typing()
			elif _choice_data.is_empty():
				advance_requested.emit()
			else:
				_emit_choice(_selected_choice)
			get_viewport().set_input_as_handled()
		return
	if wait_available and event.is_action_pressed("wait_for_class"):
		wait_requested.emit()
		get_viewport().set_input_as_handled()


func _rebuild_history() -> void:
	for child: Node in backlog_entries.get_children():
		backlog_entries.remove_child(child)
		child.queue_free()
	if runner == null:
		return
	for entry: Dictionary in runner.history:
		var block: VBoxContainer = VBoxContainer.new()
		block.add_theme_constant_override("separation", 4)
		var heading: Label = Label.new()
		heading.text = "%s   /   %s" % [entry["speaker"], _kind_description(str(entry["speaker"]), str(entry["kind"]))]
		heading.add_theme_font_size_override("font_size", 15)
		heading.add_theme_color_override("font_color", Color("b8b19a"))
		var line: Label = Label.new()
		line.text = str(entry["text"])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", text_size - 3)
		line.add_theme_color_override("font_color", Color("eeeade"))
		block.add_child(heading)
		block.add_child(line)
		backlog_entries.add_child(block)
	await get_tree().process_frame
	backlog_scroll.scroll_vertical = int(backlog_scroll.get_v_scroll_bar().max_value)


func _change_text_size(amount: int) -> void:
	text_size = clampi(text_size + amount, 21, 35)
	body.add_theme_font_size_override("normal_font_size", text_size)
	for child: Node in choices.get_children():
		if child is Button:
			(child as Button).add_theme_font_size_override("font_size", maxi(text_size - 6, 18))
	_rebuild_history()


func _toggle_speed() -> void:
	instant_text = not instant_text
	speed_button.text = "TEXT: INSTANT" if instant_text else "TEXT: SLOW"
	if instant_text and _typing:
		_finish_typing()


func _portrait_for(name: String, kind: String) -> String:
	if kind == "imagination":
		return "…"
	if name == "YOU NOTICE":
		return "·"
	return "YOU" if name == "YOU" else name


func _kind_description(name: String, kind: String) -> String:
	match kind:
		"statement":
			return "CLASSMATE  /  PERSONAL ACCOUNT" if name == "Q" else "SUBSTITUTE  /  PERSONAL ACCOUNT"
		"recollection":
			return "UNCERTAIN RECOLLECTION"
		"imagination":
			return "IMAGINED  /  NOT AN EVENT"
		"observation":
			return "DIRECT OBSERVATION"
		"choice":
			return "YOUR RESPONSE"
		"choice_answer":
			return "YOUR CHOICE"
	return "DIALOGUE"
