class_name MenuStyle
extends RefCounted
## The look the title screen, the pause menu, the settings screen and the confirmation
## share: the same ink, paper and margin mark as the dialogue band, so the menus read as
## part of the same quiet page rather than as a separate product.
##
## Entries are flat text. Hover and keyboard/controller focus draw the same thin rule in the
## margin and a faint wash, so whatever is selected is always visible without a box.

const INK := Color(0.043, 0.051, 0.051, 1.0)
const INK_WASH := Color(0.043, 0.051, 0.051, 0.86)
const PANEL := Color(0.055, 0.065, 0.067, 0.96)
const PAPER := Color(0.898, 0.871, 0.804, 1.0)
const TEXT := Color(0.807, 0.788, 0.741, 0.92)
const MUTED := Color(0.611, 0.6, 0.561, 0.9)
const ACCENT := Color(0.776, 0.733, 0.643, 1.0)
const WARN := Color(0.82, 0.553, 0.349, 1.0)

const TITLE_SIZE := 30
const ENTRY_SIZE := 21
const BODY_SIZE := 18
const HEADING_SIZE := 15
const SMALL_SIZE := 14


static func entry_button(text: String, size: int, factor: float) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_entry(button)
	UiTextScale.set_base(button, size, factor)
	return button


## Flat entry with a margin mark on hover and focus.
static func style_entry(button: Button) -> void:
	var normal := StyleBoxEmpty.new()
	_pad(normal)
	var marked := StyleBoxFlat.new()
	marked.bg_color = Color(0.776, 0.733, 0.643, 0.08)
	marked.border_width_left = 2
	marked.border_color = Color(0.776, 0.733, 0.643, 0.7)
	_pad(marked)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.776, 0.733, 0.643, 0.14)
	pressed.border_width_left = 2
	pressed.border_color = PAPER
	_pad(pressed)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", marked)
	button.add_theme_stylebox_override(&"focus", marked)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", normal)
	button.add_theme_color_override(&"font_color", TEXT)
	button.add_theme_color_override(&"font_hover_color", PAPER)
	button.add_theme_color_override(&"font_focus_color", PAPER)
	button.add_theme_color_override(&"font_pressed_color", PAPER)
	button.add_theme_color_override(&"font_hover_pressed_color", PAPER)
	button.add_theme_color_override(&"font_disabled_color", Color(0.611, 0.6, 0.561, 0.45))
	button.add_theme_constant_override(&"outline_size", 0)


static func _pad(box: StyleBox) -> void:
	box.content_margin_left = 12.0
	box.content_margin_right = 10.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0


static func label(text: String, size: int, factor: float, color: Color = TEXT) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_color_override(&"font_color", color)
	UiTextScale.set_base(item, size, factor)
	return item


## A label that wraps instead of pushing its container wider.
static func paragraph(text: String, size: int, factor: float, color: Color = TEXT) -> Label:
	var item := label(text, size, factor, color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item


static func panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_width_left = 2
	box.border_color = Color(0.776, 0.733, 0.643, 0.35)
	box.content_margin_left = 36.0
	box.content_margin_right = 32.0
	box.content_margin_top = 24.0
	box.content_margin_bottom = 22.0
	return box


static func backdrop(color: Color = INK_WASH) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect


## The key or button that triggers an action, for hint lines: "Esc", "B", "Start".
static func key(node: Node, action: StringName) -> String:
	var settings: Node = node.get_node_or_null(^"/root/Settings") if node.is_inside_tree() else null
	if settings != null and settings.has_method("binding_label"):
		return local_key_name(String(settings.call("binding_label", action, &"")))
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode != KEY_NONE:
			return local_key_name(OS.get_keycode_string(key_event.physical_keycode))
	return String(action)


## The engine names keys in English; the few with a common local name ("空格") use it.
static func local_key_name(label: String) -> String:
	var lookup := "key.%s" % label.to_lower()
	return L10n.t(lookup) if L10n.has_key(lookup) else label


static func using_gamepad(node: Node) -> bool:
	var settings: Node = node.get_node_or_null(^"/root/Settings") if node.is_inside_tree() else null
	return settings != null and settings.has_method("is_using_gamepad") \
		and bool(settings.call("is_using_gamepad"))
