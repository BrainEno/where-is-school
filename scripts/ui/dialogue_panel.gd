class_name DialoguePanel
extends Control
## View for dialogue and inspection text. Owns presentation only.
##
## The panel is a **reading surface at the edge of the world**, not a chat window:
##
## - it is a band in the lower left, never full width, so the room stays the main
##   picture; a soft ink wash fades its top edge into the scene instead of drawing a
##   heavy box around it;
## - the speaker's name is the anchor, the role is quieter, and the sentence is the
##   largest thing on screen;
## - the narrative source (seen / heard / remembered / imagined) is a hairline and a
##   small tracked label, not a badge that competes with the prose;
## - choices sit on their own lines below a rule, left-aligned, with a margin mark on
##   hover — text to read and pick, not a column of buttons.
##
## It still translates input into intents (`advance_requested`, `choice_selected`)
## and leaves story state to the DialogueController.
##
## The band is also the surface that continues the line. A left click inside the box
## advances (or finishes a line that is still typing); a left click anywhere else does
## nothing while the panel is up. The old rule was the opposite — every unhandled click
## anywhere on screen counted as "continue", while the box itself, covered by its frame
## panel, swallowed the click and did nothing.
##
## Layout is measured, not guessed. The band width, the text column and the height are
## computed from the viewport and from the text the panel is actually holding, so the
## same scene reads correctly at 1280x720, 1600x900 and 1920x1080, and a long line
## scrolls inside the body instead of growing past the screen. Nothing shrinks the type
## to make text fit: the type sizes are fixed and the panel adapts around them.
##
## A speaker *may* have an approved 2D portrait (`CharacterProfile.portrait`). Most do
## not, and then nothing here changes: no column is reserved, the band sits where it
## always sat and every rect is the same. When one exists it is part of the same
## picture rather than a card pinned to the box: it stands on the bottom edge of the
## screen, enters from the side the profile names, is drawn behind the band, and the
## band moves away from it only as far as the text needs. It never covers the name,
## the sentence, the options or the hint, and it never takes a click. A portrait that
## cannot be used (missing file, not a texture, no pixels, absurd proportions) is
## reported by `get_portrait_report()` and a warning, and the line is shown as if the
## speaker had none.

signal advance_requested
signal choice_selected(index: int)
signal backlog_requested

## Characters revealed per second. Raising it also raises the "instant" feel.
@export var characters_per_second: float = 55.0
## Extra characters revealed per frame while holding the advance key.
@export var skip_multiplier: float = 8.0
## Show every line whole, without the typewriter (Settings > Text speed > Instant).
## Separate from `characters_per_second`, where 0 means "paused" to the tests.
@export var instant_reveal: bool = false

@export_category("Band")
## Fraction of the viewport width the reading band may use at most.
@export_range(0.3, 0.8, 0.01) var band_width_ratio: float = 0.6
@export var band_min_width: float = 620.0
@export var band_max_width: float = 1040.0
## Distance from the left edge, as a fraction of the viewport width, capped below.
@export_range(0.0, 0.2, 0.005) var side_margin_ratio: float = 0.055
@export var side_margin_max: float = 92.0
@export var bottom_margin: float = 38.0
@export var min_height: float = 176.0
## Fraction of the viewport height the band may grow to before the body scrolls.
@export_range(0.35, 0.85, 0.01) var max_height_ratio: float = 0.62

@export_category("Type")
@export var speaker_size: int = 26
@export var role_size: int = 13
@export var badge_size: int = 12
@export var title_size: int = 16
@export var body_size: int = 22
@export var choice_size: int = 20
@export var hint_size: int = 12

@export_category("Portrait")
## Largest share of the viewport width an optional portrait may take. A portrait that
## would be wider is scaled down as a whole, never cropped into a box.
@export_range(0.1, 0.4, 0.01) var portrait_max_width_ratio: float = 0.28
## How far the band's own padding may slide over the inner edge of the portrait, so
## the two read as one composition. Kept below the frame's content margins (36 px on
## the left, 32 px on the right) so the text itself never reaches the figure.
@export_range(0.0, 30.0, 1.0) var portrait_overlap: float = 24.0
## Narrowest a portrait may be drawn. With less room than this the portrait is left
## out (status "no_room") instead of being shown as a sliver.
@export var portrait_min_width: float = 48.0

@onready var _speaker_label: Label = %SpeakerLabel
@onready var _role_label: Label = %RoleLabel
@onready var _badge_label: Label = %SourceBadge
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _choices_container: VBoxContainer = %ChoicesContainer
@onready var _hint_label: Label = %HintLabel
@onready var _frame: PanelContainer = %Frame
@onready var _source_rule: ColorRect = %SourceRule
@onready var _choice_rule: ColorRect = %ChoiceRule
@onready var _wash: TextureRect = %Wash
@onready var _portrait: TextureRect = %Portrait

const SOURCE_COLORS: Dictionary = {
	NarrativeEntry.Source.OBSERVED: Color(0.776, 0.733, 0.643, 1.0),
	NarrativeEntry.Source.REPORTED: Color(0.561, 0.663, 0.710, 1.0),
	NarrativeEntry.Source.RECALLED: Color(0.604, 0.639, 0.592, 1.0),
	NarrativeEntry.Source.IMAGINED: Color(0.820, 0.553, 0.349, 1.0),
}

const SUBJECTIVE_TINT := Color(0.717, 0.427, 0.286, 1.0)
const PAPER := Color(0.898, 0.871, 0.804, 1.0)
const MUTED := Color(0.611, 0.6, 0.561, 1.0)
const INK := Color(0.055, 0.065, 0.067, 0.78)

var _reveal_progress: float = 0.0
var _revealing: bool = false
var _choice_buttons: Array[Button] = []
var _line: Dictionary = {}
var _accent: Color = PAPER
var _style_normal: StyleBoxEmpty = StyleBoxEmpty.new()
var _style_hover: StyleBoxFlat = StyleBoxFlat.new()
var _style_pressed: StyleBoxFlat = StyleBoxFlat.new()
## Two-pass layout: the first frame sets the width the text will really wrap at, the
## next one measures what that produced. Measuring in the same frame as the resize is
## how a panel ends up sized for the text it had a moment ago.
var _layout_dirty: bool = false
var _layout_stage: int = 0
## The portrait for the line on screen, already resolved and cropped, or null.
var _portrait_texture: Texture2D = null
var _portrait_profile: CharacterProfile = null
## What the last resolve and layout pass decided, for `get_portrait_report()`.
var _portrait_status: String = "none"
var _portrait_message: String = ""
var _portrait_speaker: String = ""
var _portrait_side: String = ""
var _portrait_source_size: Vector2 = Vector2.ZERO
## Each distinct problem is warned about once per panel, not once per line.
var _portrait_warned: Dictionary = {}
## The type sizes as authored, before the player's text size multiplies them.
var _base_type: Dictionary = {}
var _text_scale: float = 1.0
## The option a controller or the arrow keys point at, or -1. The buttons themselves keep
## FOCUS_NONE: the highlight is drawn here so a click and a digit still work unchanged.
var _choice_cursor: int = -1
var _stick_frame: int = -1


func _ready() -> void:
	hide()
	_choices_container.hide()
	_hint_label.hide()
	_remember_base_type()
	_apply_type()
	_connect_settings()
	refresh_static_text()
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	_build_choice_styles()
	_choices_container.add_theme_constant_override("separation", 2)
	_make_band_clickable()
	_queue_fit()


## Everything in the band except the option buttons is transparent to the mouse, and
## the band itself takes the click.
##
## Without this the frame, the containers and the body label each stopped the event on
## their own, so the one part of the screen a reader is looking at was the one part that
## ignored a click. Doing it in one pass also means a node added to the scene later
## cannot quietly eat the click again.
func _make_band_clickable() -> void:
	for child in get_children():
		_set_transparent_to_mouse(child)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _set_transparent_to_mouse(node: Node) -> void:
	var control := node as Control
	if control != null and not (control is Button):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_transparent_to_mouse(child)


## Type is set here rather than only in the scene so the panel has one source of truth
## for its scale, and tests can read the sizes that are really in use.
func _apply_type() -> void:
	_speaker_label.add_theme_font_size_override("font_size", speaker_size)
	_speaker_label.add_theme_font_override("font", _tracked_font(_speaker_label, 3))
	# A name that would push the role and the source label out of the band is trimmed
	# with an ellipsis instead. The name is the anchor, not a reason to break the frame.
	_speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_label.add_theme_font_size_override("font_size", role_size)
	_badge_label.add_theme_font_size_override("font_size", badge_size)
	_badge_label.add_theme_font_override("font", _tracked_font(_badge_label, 2))
	_title_label.add_theme_font_size_override("font_size", title_size)
	_hint_label.add_theme_font_size_override("font_size", hint_size)
	_body_label.add_theme_font_size_override("normal_font_size", body_size)


func _remember_base_type() -> void:
	if not _base_type.is_empty():
		return
	_base_type = {
		"speaker": speaker_size, "role": role_size, "badge": badge_size,
		"title": title_size, "body": body_size, "choice": choice_size, "hint": hint_size,
	}


## The player's text size. Every type size is the authored one times `factor`; the band
## then re-measures around the larger text (it scrolls the body rather than shrink it).
func set_text_scale(factor: float) -> void:
	_remember_base_type()
	_text_scale = maxf(factor, 0.5)
	speaker_size = UiTextScale.scaled(int(_base_type["speaker"]), _text_scale)
	role_size = UiTextScale.scaled(int(_base_type["role"]), _text_scale)
	badge_size = UiTextScale.scaled(int(_base_type["badge"]), _text_scale)
	title_size = UiTextScale.scaled(int(_base_type["title"]), _text_scale)
	body_size = UiTextScale.scaled(int(_base_type["body"]), _text_scale)
	choice_size = UiTextScale.scaled(int(_base_type["choice"]), _text_scale)
	hint_size = UiTextScale.scaled(int(_base_type["hint"]), _text_scale)
	# Before _ready the labels do not exist yet; _ready applies the sizes itself.
	if _speaker_label == null:
		return
	_apply_type()
	for button in _choice_buttons:
		if is_instance_valid(button):
			button.add_theme_font_size_override("font_size", choice_size)
			button.custom_minimum_size = Vector2(0.0, _choice_min_height())
	_queue_fit()


func get_text_scale() -> float:
	return _text_scale


## Characters per second from Settings; 0 there means "instant".
func set_reveal_speed(cps: float) -> void:
	instant_reveal = cps <= 0.0
	if not instant_reveal:
		characters_per_second = cps
	if instant_reveal and _revealing:
		complete_reveal()


func _connect_settings() -> void:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null:
		return
	if not settings.is_connected("setting_changed", _on_setting_changed):
		settings.connect("setting_changed", _on_setting_changed)
		settings.connect("bindings_changed", refresh_static_text)
		settings.connect("input_device_changed", _on_input_device_changed)
	_on_setting_changed(&"all")


func _on_setting_changed(key: StringName) -> void:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null:
		return
	if key == &"all" or key == &"text_size":
		set_text_scale(float(settings.call("text_scale")))
	if key == &"all" or key == &"text_speed":
		set_reveal_speed(float(settings.call("reveal_characters_per_second")))


func _on_input_device_changed(_device: StringName) -> void:
	if has_choices() and _choice_cursor < 0 and MenuStyle.using_gamepad(self):
		_set_choice_cursor(0)
	refresh_static_text()


func _choice_min_height() -> float:
	return roundf(32.0 * maxf(_text_scale, 1.0))


## A `FontVariation` of the project font with extra letter spacing. The project ships
## one font; this widens it for the two short labels (name, source) instead of adding a
## second typeface.
func _tracked_font(source: Label, amount: int) -> Font:
	var base := source.get_theme_font("font")
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = amount
	return variation


func show_line(line: Dictionary, keep_state: bool = false) -> void:
	var was_complete := not _revealing
	_line = line
	show()
	_move_to_front()

	_speaker_label.text = _speaker_text(line)
	_speaker_label.add_theme_color_override("font_color", _speaker_color(line))
	var role_text := _role_text(line)
	_role_label.text = role_text
	_role_label.visible = not role_text.is_empty()

	# The badge is stored as a locale key by the runtime/controller; the panel owns the
	# translation so a language switch only has to call refresh_static_text().
	var badge := _badge_text(line)
	_badge_label.text = badge
	_badge_label.visible = not badge.is_empty()

	_accent = _accent_for(line)
	_apply_accent(_accent)
	_resolve_portrait(line)

	var title := String(line.get("title", ""))
	_title_label.text = title
	_title_label.visible = not title.is_empty()

	_body_label.text = String(line.get("text", ""))
	set_choices([])
	if keep_state and was_complete:
		_body_label.visible_characters = -1
		_reveal_progress = float(_body_label.text.length())
		_revealing = false
	elif instant_reveal:
		_body_label.visible_characters = -1
		_reveal_progress = float(_body_label.text.length())
		_revealing = false
	else:
		_body_label.visible_characters = 0
		_reveal_progress = 0.0
		_revealing = _body_label.text.length() > 0

	refresh_static_text()
	_hint_label.show()
	_update_hint_visibility()
	_queue_fit()


func set_choices(choices: Array) -> void:
	for button in _choice_buttons:
		if is_instance_valid(button):
			_choices_container.remove_child(button)
			button.queue_free()
	_choice_buttons.clear()
	_choice_cursor = -1
	_choices_container.hide()
	_choice_rule.visible = false
	if choices.is_empty():
		_queue_fit()
		return

	for index in choices.size():
		var choice: Dictionary = choices[index]
		var button := Button.new()
		button.name = "Choice%d" % (index + 1)
		button.text = "%d.  %s" % [index + 1, String(choice.get("text", ""))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_font_size_override("font_size", choice_size)
		button.add_theme_constant_override("outline_size", 0)
		button.custom_minimum_size = Vector2(0.0, _choice_min_height())
		_apply_choice_colors(button)
		button.add_theme_stylebox_override("normal", _style_normal)
		button.add_theme_stylebox_override("hover", _style_hover)
		button.add_theme_stylebox_override("pressed", _style_pressed)
		button.add_theme_stylebox_override("hover_pressed", _style_pressed)
		button.add_theme_stylebox_override("focus", _style_normal)
		button.add_theme_stylebox_override("disabled", _style_normal)
		button.pressed.connect(_on_choice_button_pressed.bind(index))
		_choices_container.add_child(button)
		_choice_buttons.append(button)
	_choices_container.show()
	_choice_rule.visible = true
	if MenuStyle.using_gamepad(self):
		_set_choice_cursor(0)
	if _revealing:
		complete_reveal()
	refresh_static_text()
	_update_hint_visibility()
	_queue_fit()


func close() -> void:
	hide()
	_line = {}
	_revealing = false
	set_choices([])
	_clear_portrait()


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


## The option buttons, in order. Read by the tests that click them for real.
func get_choice_buttons() -> Array[Button]:
	return _choice_buttons.duplicate()


## The option a controller or the arrow keys point at, or -1 when none is marked.
func get_choice_cursor() -> int:
	return _choice_cursor


func _set_choice_cursor(index: int) -> void:
	if _choice_buttons.is_empty():
		_choice_cursor = -1
		return
	_choice_cursor = clampi(index, 0, _choice_buttons.size() - 1)
	for i in _choice_buttons.size():
		var button := _choice_buttons[i]
		if not is_instance_valid(button):
			continue
		var marked := i == _choice_cursor
		button.add_theme_stylebox_override("normal", _style_hover if marked else _style_normal)
		var color := PAPER if marked else Color(0.807, 0.788, 0.741, 0.86)
		button.add_theme_color_override("font_color", color)


func _move_choice_cursor(step: int) -> void:
	if _choice_cursor < 0:
		_set_choice_cursor(0 if step > 0 else _choice_buttons.size() - 1)
	else:
		_set_choice_cursor(posmod(_choice_cursor + step, _choice_buttons.size()))


func get_body_label() -> RichTextLabel:
	return _body_label


func get_body_text() -> String:
	return _body_label.text if _body_label != null else ""


func is_body_scrolling() -> bool:
	return _body_label != null and _body_label.scroll_active


## Re-resolves every string the panel owns. Called on language switches and
## whenever a line is shown, so hints and badges never stay in the old language.
func refresh_static_text() -> void:
	if _hint_label == null:
		return
	_hint_label.text = _hint_text()
	if _line.is_empty():
		return
	_badge_label.text = _badge_text(_line)
	_role_label.text = _role_text(_line)
	_speaker_label.text = _speaker_text(_line)
	_choice_rule.visible = has_choices()
	_queue_fit()


## The hint names the keys or buttons actually bound, for the device in use.
func _hint_text() -> String:
	var keys := {
		"log": MenuStyle.key(self, &"backlog"),
		"language": MenuStyle.key(self, &"toggle_language"),
		"advance": MenuStyle.key(self, &"dialogue_advance"),
		"count": _choice_buttons.size(),
	}
	var pad := MenuStyle.using_gamepad(self)
	if has_choices():
		return L10n.t("ui.dialogue_choose_pad" if pad else "ui.dialogue_choose", keys)
	return L10n.t("ui.dialogue_continue_pad" if pad else "ui.dialogue_continue", keys)


## Redraws the line that is already on screen, used by a language switch. The reveal
## state is kept: a line that was already readable stays readable instead of typing
## itself out again in the new language.
func redraw_current_line() -> void:
	if _line.is_empty():
		return
	show_line(_line, true)


func _process(delta: float) -> void:
	if _layout_dirty and visible:
		_settle_layout()
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


## A click on the band. The option buttons take their own clicks before this runs, so
## what arrives here is a click on the reading surface: it continues the line, finishes
## one that is still typing, or does nothing while a choice is open.
func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	# Swallowed either way: reading must never walk the character or use whatever
	# stands behind the band.
	accept_event()
	if has_choices():
		return
	_request_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("backlog"):
		get_viewport().set_input_as_handled()
		backlog_requested.emit()
		return

	# A left click that reaches this point landed outside the band. With the panel up it
	# is consumed and dropped: it is not an advance, and it is not a walk either.
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			get_viewport().set_input_as_handled()
		return

	if has_choices():
		var index := _digit_from_event(event)
		if index >= 0 and index < _choice_buttons.size():
			get_viewport().set_input_as_handled()
			choice_selected.emit(index)
		elif _is_pressed(event, [&"ui_up", &"move_forward"]):
			get_viewport().set_input_as_handled()
			_move_choice_cursor(-1)
		elif _is_pressed(event, [&"ui_down", &"move_back"]):
			get_viewport().set_input_as_handled()
			_move_choice_cursor(1)
		elif _choice_cursor >= 0 and _is_pressed(event, [&"dialogue_advance", &"ui_accept"]):
			get_viewport().set_input_as_handled()
			choice_selected.emit(_choice_cursor)
		return

	if event.is_action_pressed("dialogue_advance"):
		get_viewport().set_input_as_handled()
		_request_advance()


## A fresh press of any of `actions` (a held stick or key does not repeat a move).
func _is_pressed(event: InputEvent, actions: Array) -> bool:
	if event is InputEventKey and (event as InputEventKey).echo:
		return false
	for action: StringName in actions:
		if not InputMap.has_action(action) or not event.is_action_pressed(action):
			continue
		if event is InputEventJoypadMotion:
			# A stick sends a stream of events past the deadzone; only the one that crosses
			# it counts, and only once per frame.
			var frame := Engine.get_process_frames()
			if not Input.is_action_just_pressed(action) or frame == _stick_frame:
				return false
			_stick_frame = frame
		return true
	return false


## One definition of "continue": finish the line if it is still typing, otherwise ask
## for the next one. The click and the key both go through it so they cannot drift.
func _request_advance() -> void:
	if _revealing:
		complete_reveal()
		return
	advance_requested.emit()


func _on_choice_button_pressed(index: int) -> void:
	choice_selected.emit(index)


func _on_viewport_resized() -> void:
	_queue_fit()


func _queue_fit() -> void:
	_layout_stage = 0
	_layout_dirty = true


# --- Layout -----------------------------------------------------------------


func _settle_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	var left := minf(viewport_size.x * side_margin_ratio, side_margin_max)
	var width := clampf(viewport_size.x * band_width_ratio, band_min_width, band_max_width)
	width = minf(width, viewport_size.x - left * 2.0)
	var max_height := viewport_size.y * max_height_ratio
	# Without a portrait the plan is empty and `left` / `width` are exactly what they
	# were before portraits existed.
	var portrait_plan := _plan_portrait(viewport_size, left, width)
	if not portrait_plan.is_empty():
		left = float(portrait_plan["band_left"])
		width = float(portrait_plan["band_width"])

	if _layout_stage == 0:
		# Give the frame the width the text will really wrap at, and the tallest height
		# it is allowed. What the content measures under those two constraints is what
		# the band should be.
		offset_left = left
		offset_right = left + width
		offset_bottom = -bottom_margin
		offset_top = -bottom_margin - max_height
		_body_label.fit_content = true
		_body_label.scroll_active = false
		_body_label.custom_minimum_size = Vector2(0.0, 0.0)
		_place_portrait(portrait_plan)
		_layout_stage = 1
		_layout_dirty = true
		return

	var needed: float = _frame.get_combined_minimum_size().y
	var scrolling := needed > max_height + 0.5
	var height := max_height if scrolling else clampf(needed, min_height, max_height)
	offset_top = -bottom_margin - height
	if scrolling:
		# The body keeps the room that is left and scrolls; nothing is cut off and no
		# type size is reduced to force the paragraph in.
		_body_label.fit_content = false
		_body_label.scroll_active = true
	_body_label.custom_minimum_size = Vector2(0.0, 0.0)
	_place_portrait(portrait_plan)
	_layout_stage = 0
	_layout_dirty = false


## Everything the layout produced, for the tests and for a screenshot caption.
func get_layout_report() -> Dictionary:
	var rect := get_global_rect()
	var body_rect := _body_label.get_global_rect()
	return {
		"viewport": get_viewport_rect().size,
		"panel_rect": rect,
		"body_rect": body_rect,
		"body_content_height": _body_label.get_content_height(),
		"body_scrolling": _body_label.scroll_active,
		"body_font_size": _body_label.get_theme_font_size("normal_font_size"),
		"speaker_font_size": _speaker_label.get_theme_font_size("font_size"),
		"choice_count": _choice_buttons.size(),
		"choice_font_size": choice_size,
		"covers_width": rect.size.x / maxf(get_viewport_rect().size.x, 1.0),
		"covers_height": rect.size.y / maxf(get_viewport_rect().size.y, 1.0),
	}


## What the portrait layer is doing for the line on screen, for tests and for anyone
## wondering why a portrait did not appear.
##
## - `status`: "none" (the speaker has no portrait), "ok", "no_room", or a failure
##   code from `CharacterProfile.resolve_portrait()`;
## - `message`: why, when the status is not "none" or "ok";
## - `visible` / `rect`: whether it is drawn and where, in viewport coordinates;
## - `side`: "left", "right" or "" when nothing is drawn;
## - `mouse_filter`: always `MOUSE_FILTER_IGNORE` - the portrait never takes a click.
func get_portrait_report() -> Dictionary:
	var shown := _portrait != null and _portrait.visible and visible
	return {
		"status": _portrait_status,
		"message": _portrait_message,
		"speaker_id": _portrait_speaker,
		"visible": shown,
		"rect": _portrait.get_global_rect() if shown else Rect2(),
		"side": _portrait_side if shown else "",
		"source_size": _portrait_source_size,
		"mouse_filter": _portrait.mouse_filter if _portrait != null else -1,
	}


# --- Portrait ---------------------------------------------------------------


## Finds and resolves the portrait for a line. The profile normally comes from the
## character directory by `speaker_id`; a line may carry its own `portrait_profile`
## (a CharacterProfile) instead, which is how a test or a future scene-specific
## portrait supplies one without touching the shipped profiles.
func _resolve_portrait(line: Dictionary) -> void:
	_portrait_texture = null
	_portrait_profile = null
	_portrait_status = "none"
	_portrait_message = ""
	_portrait_side = ""
	_portrait_source_size = Vector2.ZERO
	_portrait_speaker = String(line.get("speaker_id", ""))
	_portrait.texture = null
	_portrait.visible = false

	var profile := _portrait_profile_for(line)
	if profile == null:
		return
	var resolved := profile.resolve_portrait()
	_portrait_status = String(resolved.get("status", "none"))
	_portrait_message = String(resolved.get("message", ""))
	_portrait_source_size = resolved.get("source_size", Vector2.ZERO)
	if _portrait_status == "ok":
		_portrait_texture = resolved.get("texture", null)
		_portrait_profile = profile
		_portrait.texture = _portrait_texture
		_portrait_side = (
			"right" if profile.portrait_side == CharacterProfile.PortraitSide.RIGHT else "left"
		)
	elif _portrait_status != "none":
		_warn_portrait(_portrait_message)


func _portrait_profile_for(line: Dictionary) -> CharacterProfile:
	var injected: Variant = line.get("portrait_profile", null)
	if injected is CharacterProfile:
		return injected as CharacterProfile
	var speaker_id := StringName(String(line.get("speaker_id", "")))
	if speaker_id == &"":
		return null
	return CharacterDirectory.load_cached().get_profile(speaker_id)


## Where the portrait goes and where that leaves the band, or {} for no portrait.
##
## The band keeps its own width whenever the screen has room for both; otherwise it
## gives up width down to `band_min_width`, and past that the portrait is scaled down
## instead. The type is never touched.
func _plan_portrait(viewport_size: Vector2, left: float, width: float) -> Dictionary:
	if _portrait_texture == null or _portrait_profile == null:
		return {}
	var texture_size := _portrait_texture.get_size()
	if texture_size.x < 1.0 or texture_size.y < 1.0:
		return {}
	var aspect := texture_size.x / texture_size.y
	var height := viewport_size.y * _portrait_profile.get_portrait_height_ratio()
	var portrait_width := height * aspect
	# The band may narrow to `band_min_width` (or stay narrower if it already is) and
	# keeps its outer margin on the far side: whatever is left is the portrait's.
	var keep_width := minf(width, band_min_width)
	var max_width := minf(
		viewport_size.x * portrait_max_width_ratio,
		viewport_size.x - left - keep_width + portrait_overlap
	)
	if portrait_width > max_width:
		height *= max_width / portrait_width
		portrait_width = max_width
	if portrait_width < portrait_min_width:
		if _portrait_status != "no_room":
			_portrait_status = "no_room"
			_portrait_message = (
				"Character '%s': only %.0f px of the %.0f px screen are left for the portrait; it is not shown."
				% [String(_portrait_profile.character_id), maxf(portrait_width, 0.0), viewport_size.x]
			)
			_warn_portrait(_portrait_message)
		return {}
	if _portrait_status == "no_room":
		_portrait_status = "ok"
		_portrait_message = ""

	var band_left := left
	var band_width := width
	var rect := Rect2()
	if _portrait_profile.portrait_side == CharacterProfile.PortraitSide.RIGHT:
		rect = Rect2(
			viewport_size.x - portrait_width, viewport_size.y - height, portrait_width, height
		)
		band_width = minf(width, rect.position.x + portrait_overlap - band_left)
	else:
		rect = Rect2(0.0, viewport_size.y - height, portrait_width, height)
		band_left = maxf(left, rect.end.x - portrait_overlap)
		band_width = minf(width, viewport_size.x - left - band_left)
	return {"rect": rect, "band_left": band_left, "band_width": band_width}


## Puts the portrait where the plan says, in viewport coordinates. The node is a child
## of the band (so it is drawn behind the wash and the frame), which means its position
## is relative to wherever the band has just been moved to.
func _place_portrait(plan: Dictionary) -> void:
	if plan.is_empty():
		_portrait.visible = false
		return
	var rect: Rect2 = plan["rect"]
	var to_local := get_global_transform().affine_inverse()
	_portrait.position = to_local * rect.position
	_portrait.size = rect.size
	_portrait.visible = true


func _clear_portrait() -> void:
	_portrait_texture = null
	_portrait_profile = null
	_portrait_status = "none"
	_portrait_message = ""
	_portrait_side = ""
	_portrait_speaker = ""
	_portrait_source_size = Vector2.ZERO
	if _portrait != null:
		_portrait.texture = null
		_portrait.visible = false


func _warn_portrait(message: String) -> void:
	if message.is_empty() or _portrait_warned.has(message):
		return
	_portrait_warned[message] = true
	push_warning("DialoguePanel portrait: %s" % message)


# --- Text -------------------------------------------------------------------


## Names come from the character profile but are displayed from the locale table when
## it has one, so the same speaker reads the same way on screen and in the backlog.
func _speaker_text(line: Dictionary) -> String:
	var speaker_id := String(line.get("speaker_id", ""))
	if not speaker_id.is_empty() and L10n.has_key("name.%s" % speaker_id):
		return L10n.t("name.%s" % speaker_id)
	return String(line.get("speaker_name", ""))


func _role_text(line: Dictionary) -> String:
	var speaker_id := String(line.get("speaker_id", ""))
	if speaker_id.is_empty():
		return String(line.get("speaker_role", ""))
	if L10n.has_key("role.%s" % speaker_id):
		return L10n.t("role.%s" % speaker_id)
	return String(line.get("speaker_role", ""))


func _badge_text(line: Dictionary) -> String:
	var badge_key := String(line.get("badge", ""))
	if badge_key.is_empty():
		return ""
	return L10n.t(badge_key)


func _speaker_color(line: Dictionary) -> Color:
	if line.get("subjective", false):
		return SUBJECTIVE_TINT
	return line.get("accent_color", PAPER)


func _accent_for(line: Dictionary) -> Color:
	if line.get("subjective", false):
		return SUBJECTIVE_TINT
	var source_value := int(line.get("source", NarrativeEntry.Source.OBSERVED))
	return SOURCE_COLORS.get(source_value, PAPER)


## The source is drawn twice, both times quietly: a hairline along the top edge and a
## small tracked label. Neither is allowed to out-shout the sentence.
func _apply_accent(accent: Color) -> void:
	_source_rule.color = Color(accent.r, accent.g, accent.b, 0.55)
	_badge_label.add_theme_color_override(
		"font_color", Color(accent.r, accent.g, accent.b, 0.66)
	)
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.content_margin_left = 36.0
	style.content_margin_top = 16.0
	style.content_margin_right = 32.0
	style.content_margin_bottom = 14.0
	_frame.add_theme_stylebox_override("panel", style)
	_wash.modulate = Color(1.0, 1.0, 1.0, 0.9)


func _apply_choice_colors(button: Button) -> void:
	button.add_theme_color_override("font_color", Color(0.807, 0.788, 0.741, 0.86))
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_focus_color", PAPER)


## Option styling lives in one place so every rebuilt list looks the same after a
## language switch: flat by default, a margin mark and a lifted line on hover. The
## shapes are built once and shared by every option.
func _build_choice_styles() -> void:
	_style_normal.content_margin_left = 10.0
	_style_normal.content_margin_right = 6.0
	_style_normal.content_margin_top = 4.0
	_style_normal.content_margin_bottom = 4.0
	_style_hover.bg_color = Color(0.776, 0.733, 0.643, 0.07)
	_style_hover.border_width_left = 2
	_style_hover.border_color = Color(0.776, 0.733, 0.643, 0.55)
	_style_hover.content_margin_left = 10.0
	_style_hover.content_margin_right = 6.0
	_style_hover.content_margin_top = 4.0
	_style_hover.content_margin_bottom = 4.0
	_style_pressed.bg_color = Color(0.776, 0.733, 0.643, 0.12)
	_style_pressed.border_width_left = 2
	_style_pressed.border_color = Color(0.898, 0.871, 0.804, 0.8)
	_style_pressed.content_margin_left = 10.0
	_style_pressed.content_margin_right = 6.0
	_style_pressed.content_margin_top = 4.0
	_style_pressed.content_margin_bottom = 4.0


## Returns a zero-based choice index when the event is a digit key.
func _digit_from_event(event: InputEvent) -> int:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return -1
	var code := key_event.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1)
	return -1


func _update_hint_visibility() -> void:
	_hint_label.visible = visible


func _move_to_front() -> void:
	# Keep the dialogue above the HUD without reordering the scene at edit time.
	if get_parent() is Control:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
