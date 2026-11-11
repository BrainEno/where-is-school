class_name UiTextScale
extends RefCounted
## The player's text size (Settings > Text size) applied to a piece of interface.
##
## Every scalable control remembers the size it was authored at (a meta entry, set the
## first time it is scaled) and is always recomputed from that base, so switching sizes
## back and forth never compounds rounding. Containers grow around the larger type; no
## layout here shrinks text to make it fit.

const BASE_META := &"ui_base_font_size"


## The multiplier in effect: the `Settings` autoload's, or 1 when there is none (a test
## that never registers it).
static func current(node: Node) -> float:
	if node == null or not node.is_inside_tree():
		return 1.0
	var settings := node.get_node_or_null(^"/root/Settings")
	if settings == null or not settings.has_method("text_scale"):
		return 1.0
	return float(settings.call("text_scale"))


static func scaled(size: int, factor: float) -> int:
	return maxi(1, roundi(float(size) * factor))


## Scales `root` and every Label, Button, LineEdit and RichTextLabel under it.
static func apply(root: Node, factor: float) -> void:
	if root == null:
		return
	_apply_one(root, factor)
	for child in root.get_children():
		apply(child, factor)


## Declares the authored size of a control built in code, then scales it.
static func set_base(control: Control, size: int, factor: float) -> void:
	if control == null:
		return
	control.set_meta(BASE_META, size)
	_apply_one(control, factor)


static func _apply_one(node: Node, factor: float) -> void:
	var control := node as Control
	if control == null:
		return
	var theme_name := StringName()
	if control is RichTextLabel:
		theme_name = &"normal_font_size"
	elif control is Label or control is Button or control is LineEdit:
		theme_name = &"font_size"
	else:
		return
	if not control.has_meta(BASE_META):
		control.set_meta(BASE_META, control.get_theme_font_size(theme_name))
	var base := int(control.get_meta(BASE_META))
	control.add_theme_font_size_override(theme_name, scaled(base, factor))


## True when a `Settings.setting_changed` key means the text size may have moved.
static func is_text_size_key(key: StringName) -> bool:
	return key == &"text_size" or key == &"all"
