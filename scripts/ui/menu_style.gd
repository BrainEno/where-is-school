class_name MenuStyle
extends RefCounted
## The look the title screen, the pause menu, the settings screen and the confirmation
## share: the same ink, paper and margin mark as the dialogue band, so the menus read as
## part of the same quiet page rather than as a separate product.
##
## Entries are flat text. Hover and keyboard/controller focus draw the same thin rule in the
## margin and a faint wash, so whatever is selected is always visible without a box.
##
## The title screen, the pause menu and the questions they ask are set a step further, the
## way the dialogue column is (#125): the serif (Noto Serif SC, the dialogue panel's face,
## with the project Sans behind it for anything its subset does not carry), one warm accent
## ("ember") for what is selected, and colour fields with hand-cut edges instead of boxes
## (ART_BIBLE, "UI restraint"). `page_entry()` is that entry; the settings screen keeps the
## plain one because its rows are a form, not a page.

const INK := Color(0.043, 0.051, 0.051, 1.0)
const INK_WASH := Color(0.043, 0.051, 0.051, 0.86)
const PANEL := Color(0.055, 0.065, 0.067, 0.96)
const PAPER := Color(0.898, 0.871, 0.804, 1.0)
const TEXT := Color(0.807, 0.788, 0.741, 0.92)
const MUTED := Color(0.611, 0.6, 0.561, 0.9)
const ACCENT := Color(0.776, 0.733, 0.643, 1.0)
const WARN := Color(0.82, 0.553, 0.349, 1.0)
## The one warm accent of the title and pause menus: the selected entry, the margin rule.
const EMBER := Color(0.851, 0.396, 0.255, 1.0)
## Entry text on a page, and the brighter, warmer white it turns when selected.
const PAGE_TEXT := Color(0.86, 0.835, 0.776, 0.94)
const PAGE_LIT := Color(1.0, 0.925, 0.851, 1.0)
## The colour fields behind the title: brick, ochre, and the dark of the ground.
const BRICK := Color(0.4, 0.192, 0.133, 1.0)
const OCHRE := Color(0.62, 0.471, 0.29, 1.0)
const GROUND := Color(0.027, 0.033, 0.033, 1.0)

const SERIF_PATH := "res://assets/fonts/NotoSerifSC-Regular.otf"

const TITLE_SIZE := 30
const ENTRY_SIZE := 21
const BODY_SIZE := 18
const HEADING_SIZE := 15
const SMALL_SIZE := 14
## The name of the game on the title screen.
const DISPLAY_SIZE := 52

## FontVariations of the serif, one per (weight, tracking), shared by every menu.
static var _serif_cache: Dictionary = {}


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


## An entry on the title screen, the pause menu or a question: serif, and when hovered or
## focused a slanted ember wash with a ruled left edge, like a brush mark in the margin.
static func page_entry(text: String, size: int, factor: float) -> Button:
	var button := entry_button(text, size, factor)
	style_page_entry(button)
	var font := serif()
	if font != null:
		button.add_theme_font_override(&"font", font)
	return button


static func style_page_entry(button: Button) -> void:
	var normal := StyleBoxEmpty.new()
	_page_pad(normal)
	var marked := StyleBoxFlat.new()
	marked.bg_color = Color(EMBER, 0.16)
	marked.skew = Vector2(0.3, 0.0)
	marked.border_width_left = 3
	marked.border_color = EMBER
	marked.anti_aliasing = true
	_page_pad(marked)
	var pressed := marked.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(EMBER, 0.3)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", marked)
	button.add_theme_stylebox_override(&"focus", marked)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", normal)
	button.add_theme_color_override(&"font_color", PAGE_TEXT)
	button.add_theme_color_override(&"font_hover_color", PAGE_LIT)
	button.add_theme_color_override(&"font_focus_color", PAGE_LIT)
	button.add_theme_color_override(&"font_pressed_color", PAGE_LIT)
	button.add_theme_color_override(&"font_hover_pressed_color", PAGE_LIT)
	button.add_theme_color_override(&"font_disabled_color", Color(0.611, 0.6, 0.561, 0.4))
	button.add_theme_constant_override(&"outline_size", 0)


static func _page_pad(box: StyleBox) -> void:
	box.content_margin_left = 26.0
	box.content_margin_right = 18.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 7.0


## The serif, emboldened and tracked as asked, with the project Sans as its fallback so a
## character the serif subset does not carry is drawn instead of becoming a box. Null when
## the font cannot be loaded (a control then simply keeps the theme's Sans).
static func serif(embolden: float = 0.0, tracking: int = 0) -> Font:
	var key := "%.2f/%d" % [embolden, tracking]
	if _serif_cache.has(key):
		return _serif_cache[key] as Font
	if not ResourceLoader.exists(SERIF_PATH):
		return null
	var base := load(SERIF_PATH) as Font
	if base == null:
		return null
	var font := FontVariation.new()
	font.base_font = base
	font.variation_embolden = embolden
	font.spacing_glyph = tracking
	var sans := _project_font()
	if sans != null and sans != base:
		var fallbacks: Array[Font] = [sans]
		font.fallbacks = fallbacks
	_serif_cache[key] = font
	return font


static func _project_font() -> Font:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font


## A label in the serif.
static func serif_label(text: String, size: int, factor: float, color: Color = PAPER,
		embolden: float = 0.0, tracking: int = 0) -> Label:
	var item := label(text, size, factor, color)
	var font := serif(embolden, tracking)
	if font != null:
		item.add_theme_font_override(&"font", font)
	return item


## The question box over a page: dark, with the ember rule down its left edge.
static func prompt_panel_style() -> StyleBoxFlat:
	var box := panel_style()
	box.bg_color = Color(0.047, 0.055, 0.057, 0.98)
	box.border_width_left = 3
	box.border_color = EMBER
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	box.shadow_size = 18
	return box


## "教室 · 11月12日 14:03": where the save stands and when it was written, local time.
## Either half is left out when the file does not say.
static func save_caption(location_id: String, saved_at_unix: int) -> String:
	var parts := PackedStringArray()
	if not location_id.is_empty():
		var key := "place.%s" % location_id
		parts.append(L10n.t(key) if L10n.has_key(key) else location_id)
	if saved_at_unix > 0:
		var bias := int(Time.get_time_zone_from_system().get("bias", 0))
		var when := Time.get_datetime_dict_from_unix_time(saved_at_unix + bias * 60)
		parts.append(L10n.t("menu.save_time", {
			"year": str(when["year"]),
			"month": str(when["month"]),
			"day": str(when["day"]),
			"hour": "%02d" % int(when["hour"]),
			"minute": "%02d" % int(when["minute"]),
		}))
	return L10n.t("menu.caption_separator").join(parts)


# --- Hand-cut colour fields --------------------------------------------------
#
# Deterministic: the same seed gives the same edge every frame and every run, so a redraw
# never shimmers and a screenshot is reproducible.


## A filled rectangle whose left and right edges are cut by hand: each side wanders by up to
## `jitter` pixels.
static func draw_rough_slab(canvas: CanvasItem, rect: Rect2, color: Color, seed_value: int,
		jitter: float = 8.0, rough_left: bool = true, rough_right: bool = true) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var steps := clampi(int(rect.size.y / 22.0), 4, 48)
	var points := PackedVector2Array()
	for index in range(steps + 1):
		var y := rect.position.y + rect.size.y * float(index) / float(steps)
		var dx: float = (_noise(seed_value, index) - 0.5) * 2.0 * jitter if rough_right else 0.0
		points.append(Vector2(rect.end.x + dx, y))
	for index in range(steps, -1, -1):
		var y := rect.position.y + rect.size.y * float(index) / float(steps)
		var dx: float = (_noise(seed_value + 101, index) - 0.5) * 2.0 * jitter if rough_left else 0.0
		points.append(Vector2(rect.position.x + dx, y))
	canvas.draw_colored_polygon(points, color)


## A dry-brush stroke: a few thin, uneven, overlapping lines instead of one hard one.
static func draw_dry_brush(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color,
		seed_value: int, width: float = 6.0) -> void:
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var hairs := 6
	for index in range(hairs):
		var offset := (float(index) / float(hairs - 1) - 0.5) * width
		var head := _noise(seed_value, index * 3) * 0.12
		var tail := _noise(seed_value, index * 3 + 1) * 0.18
		var alpha := 0.35 + 0.65 * _noise(seed_value, index * 3 + 2)
		var a := from.lerp(to, head) + normal * offset
		var b := from.lerp(to, 1.0 - tail) + normal * offset
		canvas.draw_line(a, b, Color(color, color.a * alpha), 1.0, true)


## Darkens the edges of `size` towards `color`; `depth` is the band's share of the short side.
static func draw_vignette(canvas: CanvasItem, size: Vector2, color: Color,
		depth: float = 0.22) -> void:
	var band := minf(size.x, size.y) * depth
	var clear := Color(color, 0.0)
	var outer := [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	var inner := [
		Vector2(band, band), Vector2(size.x - band, band), size - Vector2(band, band),
		Vector2(band, size.y - band),
	]
	for side in range(4):
		var next := (side + 1) % 4
		canvas.draw_polygon(
			PackedVector2Array([outer[side], outer[next], inner[next], inner[side]]),
			PackedColorArray([color, color, clear, clear])
		)


static func _noise(seed_value: int, index: int) -> float:
	var value := sin(float(index) * 12.9898 + float(seed_value) * 78.233) * 43758.5453
	return value - floorf(value)


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
	return InputHint.action_key(node, action)


## Kept as a compatibility helper for controls that already hold a label.
static func local_key_name(label: String) -> String:
	return InputHint.local_key_name(label)


static func using_gamepad(node: Node) -> bool:
	return InputHint.is_gamepad(node)
