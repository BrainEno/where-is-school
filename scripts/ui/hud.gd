class_name GameHud
extends Control
## Non-dialogue HUD: the current objective line, the contextual interaction
## prompt, the language switch hint, and a short "noted" line when something new goes
## into the notebook. Thin views over state the sequence
## director owns; every string it shows is resolved through L10n at draw time so
## a language switch only has to ask for a redraw.

@onready var _objective_label: Label = $ObjectiveLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _language_label: Label = $LanguageLabel

var _objective_tween: Tween = null
var _prompt_tween: Tween = null
## True while the dialogue panel is on screen. The panel carries its own key
## hints at the bottom right, so the HUD's language hint steps aside to keep the
## two from printing on top of each other.
var _dialogue_open: bool = false
## Locale key of the current objective, so it can be re-translated in place.
var _objective_key: String = ""
## The action text of the prompt on screen, so it can be re-drawn with another key name.
var _prompt_action: String = ""
## The contextual prompt arrives and leaves with a short fade. It is the one piece of
## interface that appears while the player is moving the mouse around the world, so a line
## that switches on and off between two frames reads as a glitch in the pointer code; a
## line that arrives reads as the game answering. The fade is short (0.12 s) because the
## prompt is also information the player is waiting for.
const PROMPT_FADE_IN_SECONDS := 0.12
const PROMPT_FADE_OUT_SECONDS := 0.1
## The "noted" line: top right, under where the imagination banner and the objective sit,
## in the colour of the kind of knowledge it names. It says what kind of thing was
## learned and which key opens the notebook - never the entry itself, which the player
## has just read - and goes away by itself.
const NOTED_FADE_SECONDS := 0.25
const NOTED_HOLD_SECONDS := 2.6
const NOTED_FONT_SIZE := 16
const NOTED_TOP := 112.0
const NOTED_RIGHT := 40.0

## The reading-mode line: top right, above the "noted" line. While a conversation is up it
## names the auto and skip keys in a quiet colour; when auto or skip is running it says
## so in the accent colour; when held skip has stopped it says why. Outside dialogue it
## only shows while auto is on, so the player knows the next conversation will play itself.
const READING_FONT_SIZE := 15
const READING_TOP := 76.0
const READING_RIGHT := 40.0
const READING_ACTIVE_COLOR := Color(0.851, 0.396, 0.255, 1.0)
const READING_STOPPED_COLOR := Color(0.82, 0.553, 0.349, 1.0)
const READING_HINT_COLOR := Color(0.611, 0.6, 0.561, 0.85)

var _reading_label: Label = null
var _reading_modes: DialogueAutoplay = null

## The source whose name the "noted" line shows, or -1 while it is not showing.
var _noted_source: int = -1
var _noted_label: Label = null
var _noted_tween: Tween = null


func _ready() -> void:
	_prompt_label.hide()
	_prompt_label.text = ""
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_build_noted_label()
	_build_reading_label()
	refresh_language_text()
	var loc := _loc()
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("input_device_changed", _on_input_changed)
		settings.connect("bindings_changed", _on_input_changed.bind(&""))
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		narrative.connect("entry_recorded", _on_entry_recorded)
		narrative.connect("entries_cleared", clear_noted)
		narrative.connect("entries_restored", _on_entries_restored)
	set_text_scale(UiTextScale.current(self))


## The player's text size, applied to every line the HUD draws.
func set_text_scale(factor: float) -> void:
	UiTextScale.apply(self, factor)


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		set_text_scale(UiTextScale.current(self))
	if key in [&"skip_scope", &"skip_mode", &"all"]:
		refresh_reading_text()


## Another device or binding: the prompt and the language hint name the new key.
func _on_input_changed(_device: StringName) -> void:
	refresh_language_text()
	_refresh_noted_text()
	refresh_reading_text()
	if _prompt_label.visible and not _prompt_action.is_empty():
		_prompt_label.text = "[%s] %s" % [_interact_key_label(), _prompt_action]


func _loc() -> Node:
	return get_node_or_null(^"/root/Loc")


func _on_locale_changed(_locale: String) -> void:
	refresh_language_text()
	set_objective(_objective_key)
	_refresh_noted_text()
	refresh_reading_text()


## Shows the objective by locale key. Empty clears the line.
func set_objective(objective_key: String) -> void:
	_objective_key = objective_key.strip_edges()
	var text := L10n.objective_text(_objective_key)
	_objective_label.text = text
	_objective_label.visible = not text.is_empty()
	if not _objective_label.visible:
		return
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_label.modulate = Color(1, 1, 1, 0.25)
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_label, "modulate", Color(1, 1, 1, 1), 0.5)


func get_objective_key() -> String:
	return _objective_key


## The prompt text is already localized by the dialogue controller.
##
## The text is set synchronously — it is what `get_prompt_text()` reports and what the
## tests and the capture run wait for — and only the fade is asynchronous. Re-showing the
## same text is a no-op: the interaction controller re-resolves its target every physics
## frame, and restarting the fade on every resolve would make the line stutter.
func set_prompt_text(action: String) -> void:
	if action.strip_edges().is_empty():
		clear_prompt()
		return
	_prompt_action = action
	var text := "[%s] %s" % [_interact_key_label(), action]
	if _prompt_label.visible and _prompt_label.text == text:
		return
	_prompt_label.text = text
	_prompt_label.show()
	_kill_prompt_tween()
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_label, "modulate:a", 1.0, PROMPT_FADE_IN_SECONDS)


func get_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


func get_objective_text() -> String:
	return _objective_label.text if _objective_label != null else ""


## Empties the line at once and fades what is left of it out. The text is gone
## immediately, so nothing can read a stale prompt; only the pixels linger for a tenth of
## a second.
func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_action = ""
	_kill_prompt_tween()
	if not _prompt_label.visible:
		return
	if _prompt_label.modulate.a <= 0.001:
		_prompt_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_prompt_label.hide()
		return
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_label, "modulate:a", 0.0, PROMPT_FADE_OUT_SECONDS)
	_prompt_tween.tween_callback(_prompt_label.hide)


func _kill_prompt_tween() -> void:
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_tween = null


func refresh_language_text() -> void:
	if _language_label == null:
		return
	_language_label.text = L10n.t(
		"ui.language_switch",
		{
			"name": L10n.locale_name(L10n.other_locale()),
			"key": MenuStyle.key(self, &"toggle_language"),
		}
	)
	_language_label.visible = not _dialogue_open


## Called by the UI root when the dialogue panel opens or closes.
func set_dialogue_open(open: bool) -> void:
	_dialogue_open = open
	if _language_label != null:
		_language_label.visible = not open
	refresh_reading_text()


## Shared device-aware presentation; no scene-local device branching or binding lookup.
func _interact_key_label() -> String:
	return InputHint.action_key(self, &"interact")


# --- The "noted" line ------------------------------------------------------------------


func _build_noted_label() -> void:
	_noted_label = Label.new()
	_noted_label.name = "NotedLabel"
	_noted_label.anchor_left = 1.0
	_noted_label.anchor_right = 1.0
	_noted_label.offset_left = -NOTED_RIGHT
	_noted_label.offset_right = -NOTED_RIGHT
	_noted_label.offset_top = NOTED_TOP
	_noted_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_noted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_noted_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noted_label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	_noted_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_noted_label.add_theme_constant_override(&"shadow_offset_y", 1)
	UiTextScale.set_base(_noted_label, NOTED_FONT_SIZE, UiTextScale.current(self))
	_noted_label.hide()
	add_child(_noted_label)


## Shows "Noted: SEEN  [N] notebook" for a moment. A second entry while the line is up
## replaces it and restarts the hold, so a run of records reads as one notice.
func show_noted(source: int) -> void:
	if _noted_label == null:
		return
	_noted_source = source
	_refresh_noted_text()
	_noted_label.add_theme_color_override(
		&"font_color", JournalPanel.SOURCE_COLORS.get(source, Color(0.776, 0.733, 0.643, 1.0))
	)
	_kill_noted_tween()
	_noted_label.show()
	_noted_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_noted_tween = create_tween()
	_noted_tween.tween_property(_noted_label, "modulate:a", 1.0, NOTED_FADE_SECONDS)
	_noted_tween.tween_interval(NOTED_HOLD_SECONDS)
	_noted_tween.tween_property(_noted_label, "modulate:a", 0.0, NOTED_FADE_SECONDS)
	_noted_tween.tween_callback(clear_noted)


## Removes the line at once.
func clear_noted() -> void:
	_kill_noted_tween()
	_noted_source = -1
	if _noted_label != null:
		_noted_label.text = ""
		_noted_label.hide()


func get_noted_text() -> String:
	return _noted_label.text if _noted_label != null and _noted_label.visible else ""


func get_noted_label() -> Label:
	return _noted_label


func _refresh_noted_text() -> void:
	if _noted_label == null or _noted_source < 0:
		return
	_noted_label.text = L10n.t("hud.noted", {
		"badge": L10n.t(NarrativeEntry.badge_key_for(_noted_source)),
		"key": InputHint.action_key(self, &"journal"),
	})


func _kill_noted_tween() -> void:
	if _noted_tween != null and _noted_tween.is_valid():
		_noted_tween.kill()
	_noted_tween = null


func _on_entry_recorded(entry: NarrativeEntry) -> void:
	if entry != null:
		show_noted(entry.source)


## A restored log is the run picked up again: nothing was just noted.
func _on_entries_restored(_count: int) -> void:
	clear_noted()


# --- The reading-mode line --------------------------------------------------------------


func _build_reading_label() -> void:
	_reading_label = Label.new()
	_reading_label.name = "ReadingModeLabel"
	_reading_label.anchor_left = 1.0
	_reading_label.anchor_right = 1.0
	_reading_label.offset_left = -READING_RIGHT
	_reading_label.offset_right = -READING_RIGHT
	_reading_label.offset_top = READING_TOP
	_reading_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_reading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reading_label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	_reading_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_reading_label.add_theme_constant_override(&"shadow_offset_y", 1)
	UiTextScale.set_base(_reading_label, READING_FONT_SIZE, UiTextScale.current(self))
	_reading_label.hide()
	add_child(_reading_label)


## The dialogue controller hands over its auto/skip driver once it exists.
func bind_reading_modes(modes: DialogueAutoplay) -> void:
	if _reading_modes != null and is_instance_valid(_reading_modes) \
			and _reading_modes.state_changed.is_connected(refresh_reading_text):
		_reading_modes.state_changed.disconnect(refresh_reading_text)
	_reading_modes = modes
	if _reading_modes != null \
			and not _reading_modes.state_changed.is_connected(refresh_reading_text):
		_reading_modes.state_changed.connect(refresh_reading_text)
	refresh_reading_text()


func get_reading_text() -> String:
	return _reading_label.text if _reading_label != null and _reading_label.visible else ""


func get_reading_label() -> Label:
	return _reading_label


func refresh_reading_text() -> void:
	if _reading_label == null:
		return
	var modes: DialogueAutoplay = null
	if _reading_modes != null and is_instance_valid(_reading_modes):
		modes = _reading_modes
	var mode: StringName = modes.get_mode() if modes != null else DialogueAutoplay.MODE_OFF
	var stopped: StringName = modes.get_stop_reason() if modes != null else &""
	var keys := {
		"auto": InputHint.action_key(self, &"dialogue_auto"),
		"skip": InputHint.action_key(self, &"dialogue_skip"),
	}
	var text := ""
	var color := READING_HINT_COLOR
	if not String(stopped).is_empty() and _dialogue_open:
		text = L10n.t("hud.reading_stopped.%s" % stopped, keys)
		color = READING_STOPPED_COLOR
	elif mode == DialogueAutoplay.MODE_SKIP:
		var everything := modes != null and modes.get_skip_scope() == &"all"
		text = L10n.t("hud.reading_skip_all" if everything else "hud.reading_skip", keys)
		color = READING_ACTIVE_COLOR
	elif mode == DialogueAutoplay.MODE_AUTO:
		text = L10n.t("hud.reading_auto", keys)
		color = READING_ACTIVE_COLOR
	elif _dialogue_open and modes != null:
		# A controller with nothing bound to skip is not told to press a keyboard key.
		var skip_reachable := not MenuStyle.using_gamepad(self) or _has_pad_input(&"dialogue_skip")
		var toggles := modes.get_skip_mode() == DialogueAutoplay.SKIP_TOGGLE
		var hint := "hud.reading_hint_auto"
		if skip_reachable:
			hint = "hud.reading_hint_toggle" if toggles else "hud.reading_hint"
		text = L10n.t(hint, keys)
	_reading_label.text = text
	_reading_label.add_theme_color_override(&"font_color", color)
	_reading_label.visible = not text.is_empty()


func _has_pad_input(action: StringName) -> bool:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null or not settings.has_method("primary_event"):
		return true
	return settings.call("primary_event", action, &"gamepad") != null
