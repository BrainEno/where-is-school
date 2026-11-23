class_name PauseSheet
extends Control
## The sheet the pause menu is set on, and the placement of its column.
##
## Two faces, one class. On a desktop the sheet covers the left of the paused world with a
## hand-cut right edge and an ember rule down the column's margin - the title screen's
## look. On a phone it is a card grown around the column instead, so the entries keep
## their room on a wide, short screen rather than a full-height panel with empty space
## above and below. It also stops clicks reaching the world, as the plain backdrop did.
##
## The measuring lives here rather than in `PauseMenu` because it is the only code that
## reads `column_rect` and the only code that knows how much of the safe area the card may
## take. The menu still builds the column; this file places it.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

## The column's rectangle, as the last layout left it. Drawn around on a phone and under
## the ember rule on a desktop.
var column_rect := Rect2()
## The phone face: a card, not the full-height sheet.
var compact := false


func _init() -> void:
	name = "Sheet"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Color(MenuStyle.INK, 0.44 if compact else 0.6))
	if compact:
		if not column_rect.has_area():
			return
		var card := column_rect.grow(20.0)
		MenuStyle.draw_rough_slab(self, card, Color(MenuStyle.SHEET, 0.96), 13, 7.0)
	else:
		var right := minf(column_rect.end.x + 90.0, view.x)
		MenuStyle.draw_rough_slab(
			self, Rect2(0.0, -8.0, right + 10.0, view.y + 16.0),
			Color(MenuStyle.OCHRE, 0.12), 17, 12.0, false, true
		)
		MenuStyle.draw_rough_slab(
			self, Rect2(0.0, -8.0, right, view.y + 16.0), Color(MenuStyle.SHEET, 0.96), 13,
			8.0, false, true
		)
	if column_rect.size.y > 0.0:
		var x := column_rect.position.x - 16.0
		draw_line(
			Vector2(x, column_rect.position.y + 6.0), Vector2(x, column_rect.end.y - 4.0),
			Color(MenuStyle.EMBER, 0.85), 2.0
		)


## The column's left edge and width that the two faces share: 8.5 % of the safe width (at
## most 160) in from the left, and no wider than 560 x the text factor. `null` scroll is the
## desktop face, which has no card to grow and no finger-sized targets to fit.
func place(
	column: VBoxContainer, scroll: ScrollContainer, safe: Rect2, factor: float, foot: float = 24.0
) -> void:
	var view := safe.size
	var left := minf(view.x * 0.085, 160.0)
	var width := minf(view.x - left * 2.0, 560.0 * maxf(factor, 1.0))
	if scroll == null:
		column.custom_minimum_size = Vector2(width, 0.0)
		column.size = Vector2(width, 0.0)
		var needed := column.get_combined_minimum_size().y
		var top := maxf(24.0, minf(view.y * 0.28, view.y - needed - 90.0))
		column.position = safe.position + Vector2(left, top)
		column_rect = Rect2(column.position, Vector2(width, needed))
		queue_redraw()
		return
	left = clampf(view.x * 0.06, 32.0, 92.0)
	width = _touch_width(column, view.x, left, factor)
	_touch_height(column, scroll, safe, left, width, foot)


## The phone column's width. A grid of pairs is used when the longer labels at this text
## size fit; otherwise the entries stack in one column. It never fits by shrinking or
## truncating the text the player chose.
func _touch_width(column: VBoxContainer, view_width: float, left: float, factor: float) -> float:
	var width := minf(view_width * 0.64, 510.0 * factor)
	var grid := column.get_node_or_null(^"SecondaryEntries") as GridContainer
	var pair := Vector2.ZERO
	if grid != null:
		for entry: Control in grid.get_children():
			var column_index := entry.get_index() % 2
			pair[column_index] = maxf(pair[column_index], entry.get_combined_minimum_size().x)
	for path: NodePath in [^"resume", ^"story_editor"]:
		var full_row := column.get_node_or_null(path) as Control
		if full_row != null and full_row.visible:
			width = maxf(width, full_row.get_combined_minimum_size().x)
	width = minf(view_width - left * 2.0, maxf(width, maxf(pair.x, pair.y)))
	if grid != null:
		grid.columns = 2 if pair.x + pair.y + 6.0 <= width else 1
	column.custom_minimum_size = Vector2(width, 0.0)
	return width


## The phone column's height: the entries' own height, but never more than 68 % of the safe
## area, so the card never covers the paused world's edges. The column scrolls inside it.
## `foot` is the room left under the card for the hint line, which the caller hides or
## shows; this file does not read it so the two do not disagree about the same frame.
func _touch_height(
	column: VBoxContainer, scroll: ScrollContainer, safe: Rect2, left: float, width: float,
	foot: float = 24.0
) -> void:
	var needed := column.get_combined_minimum_size().y + 2.0
	var limit := minf(safe.size.y * 0.68, safe.size.y - 24.0 - foot)
	var height := clampf(needed, 1.0, maxf(1.0, limit))
	var top := maxf(24.0, (safe.size.y - height - (foot - 24.0)) * 0.5)
	var bounds := Rect2(safe.position + Vector2(left, top), Vector2(width, height))
	MobileLayout.place_menu_column(column, scroll, bounds)
	column_rect = bounds
	queue_redraw()
