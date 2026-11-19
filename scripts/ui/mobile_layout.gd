extends RefCounted
## Mobile canvas policy. The world can fill the screen; interactive UI lives inside the
## OS safe rectangle after applying the same pixel-to-canvas transform as Godot input.
## A preview seam is available only in the editor binary, never in a shipped build.

const DESIGN_SIZE := Vector2i(960, 720)
const TEXT_MULTIPLIER := 1.3
const TARGET_POINTS := 48.0
const EDGE := 12.0
const TEST_SAFE_AREA := &"mobile_test_safe_area"
const TEST_DENSITY := &"mobile_test_density"

static var preview := OS.has_feature("editor") and "--mobile-preview" in OS.get_cmdline_user_args()
static var enabled := OS.has_feature("mobile") or preview


static func safe_pixels(window: Window) -> Rect2:
	if preview and window.has_meta(TEST_SAFE_AREA):
		return window.get_meta(TEST_SAFE_AREA) as Rect2
	if preview:
		return Rect2(Vector2.ZERO, Vector2(window.size))
	return Rect2(DisplayServer.get_display_safe_area())


static func safe_rect(node: Node) -> Rect2:
	var viewport := node.get_viewport()
	var view := viewport.get_visible_rect()
	if not enabled or not viewport is Window:
		return view
	var window := viewport as Window
	var transform := window.get_final_transform() if preview else window.get_screen_transform()
	return from_pixels(view, safe_pixels(window), transform)


static func from_pixels(view: Rect2, pixels: Rect2, to_screen: Transform2D) -> Rect2:
	if not pixels.has_area() or is_zero_approx(to_screen.determinant()):
		return view
	var safe := view.intersection(to_screen.affine_inverse() * pixels)
	# During foregrounding/rotation the OS can report a rect from the old orientation.
	# Do not collapse a whole menu to a sliver until the next metrics update.
	if safe.size.x < view.size.x * 0.5 or safe.size.y < view.size.y * 0.5:
		return view
	return safe


static func density(window: Window) -> float:
	if preview:
		return maxf(float(window.get_meta(TEST_DENSITY, 1.0)), 1.0)
	if OS.has_feature("ios"):
		return maxf(DisplayServer.screen_get_scale(), 1.0)
	# Android uses density-independent pixels. Fall back to mdpi if a display has no DPI.
	return maxf(float(DisplayServer.screen_get_dpi()) / 160.0, 1.0)


static func hit_size(node: Node) -> float:
	var window := node.get_window()
	if window == null:
		return 88.0
	var zoom := window.get_final_transform().get_scale().abs()
	return ceilf(TARGET_POINTS * density(window) / maxf(minf(zoom.x, zoom.y), 0.01))


static func enlarge(control: Control) -> void:
	# Recompute from the authored minimum after rotating or changing density. Using the
	# previous result as the minimum would make a transient metric permanent.
	const BASE_SIZE := &"mobile_base_minimum"
	if not control.has_meta(BASE_SIZE):
		control.set_meta(BASE_SIZE, control.custom_minimum_size)
	var authored: Vector2 = control.get_meta(BASE_SIZE)
	var side := hit_size(control)
	control.custom_minimum_size = authored.max(Vector2(side, side))


static func watch(node: Node, callback: Callable) -> void:
	node.get_viewport().size_changed.connect(callback)
	if enabled:
		var settings := node.get_node_or_null(^"/root/Settings")
		if settings != null:
			settings.connect(&"mobile_area_changed", callback)


## Keep full-screen backdrops full-screen; only move their content inside this rect.
static func inset(control: Control, margin: float = 0.0) -> void:
	var view := control.get_viewport_rect()
	var safe := safe_rect(control)
	control.offset_left = safe.position.x - view.position.x + margin
	control.offset_top = safe.position.y - view.position.y + margin
	control.offset_right = safe.end.x - view.end.x - margin
	control.offset_bottom = safe.end.y - view.end.y - margin


static func is_emulated_mouse(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION


static func setup_scroll(scroll: ScrollContainer) -> void:
	# Godot's ScrollContainer consumes the emulated mouse drag and sends SCROLL_BEGIN,
	# which cancels a held child Button rather than pushing it at the end of a swipe.
	scroll.scroll_deadzone = roundi(hit_size(scroll) / 5.0)
	var rows := scroll.get_child(0) as Control if scroll.get_child_count() > 0 else null
	if rows != null:
		_pass_through_for_scroll(rows)


static func _pass_through_for_scroll(control: Control) -> void:
	# Sliders must retain their own horizontal gesture. Everything else can bubble to
	# the enclosing scroll while still accepting a normal tap on a button.
	if control is Slider:
		return
	if control.mouse_filter == Control.MOUSE_FILTER_STOP:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in control.get_children():
		if child is Control:
			_pass_through_for_scroll(child as Control)


static func add_menu_column(parent: Control, column: VBoxContainer) -> ScrollContainer:
	if not enabled:
		parent.add_child(column)
		return null
	var scroll := ScrollContainer.new()
	scroll.name = "TouchMenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	scroll.add_child(column)
	return scroll


static func place_menu_column(column: VBoxContainer, scroll: ScrollContainer, bounds: Rect2) -> void:
	if scroll == null:
		column.position = bounds.position
		return
	setup_scroll(scroll)
	scroll.position = bounds.position
	scroll.size = bounds.size
