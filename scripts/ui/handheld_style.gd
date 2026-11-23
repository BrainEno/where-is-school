extends RefCounted
## Shared phone controls: ink panels stay legible on a bright scene, and a warm rim
## distinguishes the main action without making every button look equally urgent.
## Sizing and finger ownership still belong to MobileLayout and TouchActions.

const REST_STYLE := &"handheld_rest_style"
const HELD := &"handheld_held"
const GLYPHS := {
	&"pause": '<path d="M9 5v14m6-14v14"/>',
	&"title": '<path d="M3 11 12 4l9 7M5 10v10h14V10m-9 10v-6h4v6"/>',
	&"use": '<path d="M8 4H4v4m12-4h4v4M4 16v4h4m12-4v4h-4m-4-11 3 3-3 3-3-3z"/>',
	&"resume": '<path d="m9 5 10 7-10 7z"/>',
}

static var _icons: Dictionary = {}


static func apply(button: Button, primary: bool = false, glyph: StringName = &"") -> void:
	var ink := MenuStyle.PANEL
	var paper := MenuStyle.PAPER
	var umber := MenuStyle.OCHRE
	var stroke := Color(MenuStyle.EMBER, 0.94) if primary else Color(paper, 0.3)
	var fill := Color(ink.lerp(umber, 0.23 if primary else 0.06), 0.96)
	var rest := _box(fill, stroke)
	button.set_meta(REST_STYLE, rest)
	button.add_theme_stylebox_override(&"normal", rest)
	button.add_theme_stylebox_override(&"hover", _box(Color(fill.lerp(umber, 0.12), 0.98), Color(paper, 0.66)))
	button.add_theme_stylebox_override(&"pressed", _box(Color(ink.lerp(umber, 0.45), 1.0), paper))
	button.add_theme_stylebox_override(&"disabled", _box(Color(ink, 0.86), Color(MenuStyle.MUTED, 0.42)))
	var focus := _box(fill, paper)
	focus.draw_center = false
	focus.shadow_size = 0
	button.add_theme_stylebox_override(&"focus", focus)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, paper)
	button.add_theme_color_override(&"font_disabled_color", MenuStyle.MUTED)
	if glyph != &"":
		button.icon = _icon(glyph)
		button.add_theme_constant_override(&"icon_max_width", 25)
		button.add_theme_constant_override(&"h_separation", 9)
		button.add_theme_color_override(&"icon_disabled_color", MenuStyle.MUTED)


## The native HUD recognizer consumes screen touches before Godot's Button sees them.
## Mirror its accepted press for visual feedback, without emitting or holding an action.
static func set_held(button: Button, value: bool) -> void:
	if not button.has_meta(REST_STYLE) or bool(button.get_meta(HELD, false)) == value:
		return
	button.set_meta(HELD, value)
	var style := button.get_theme_stylebox(&"pressed") if value else button.get_meta(REST_STYLE) as StyleBox
	button.add_theme_stylebox_override(&"normal", style)


static func _box(fill: Color, outline: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_corner_radius_all(14)
	box.set_border_width_all(2)
	box.set_content_margin(SIDE_LEFT, 15.0)
	box.set_content_margin(SIDE_RIGHT, 15.0)
	box.set_content_margin(SIDE_TOP, 7.0)
	box.set_content_margin(SIDE_BOTTOM, 7.0)
	box.shadow_color = Color(MenuStyle.INK, 0.28)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0.0, 2.0)
	return box


static func _icon(glyph: StringName) -> Texture2D:
	if _icons.has(glyph):
		return _icons[glyph] as Texture2D
	if not GLYPHS.has(glyph):
		return null
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="60" height="60" viewBox="0 0 24 24" '
		+ 'fill="none" stroke="#%s" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">%s</svg>') \
		% [MenuStyle.PAPER.to_html(false), GLYPHS[glyph]]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	var icon := ImageTexture.create_from_image(image)
	_icons[glyph] = icon
	return icon
