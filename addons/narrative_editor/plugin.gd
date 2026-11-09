@tool
extends EditorPlugin
## Editor-only entry point for the narrative editor.
##
## The plugin does one thing: it puts the dock in the bottom panel. All of the work lives
## in `core/` (content) and `ui/` (layout), so this file is the only place that touches
## editor APIs — which is also what keeps the rest of the addon loadable outside the
## editor, for the headless tests and for the screenshot the capture run takes.
##
## Nothing here runs in a player build: `addons/` is excluded from the export preset, the
## project has no autoload pointing at it, and no runtime script preloads it.

const Dock := preload("res://addons/narrative_editor/ui/narrative_editor_dock.gd")
const DOCK_TITLE := "剧情编辑"
const DOCK_NAME := "NarrativeEditorDock"

var _dock: Control = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = DOCK_NAME
	add_control_to_bottom_panel(_dock, DOCK_TITLE)
	# The author enabled this plugin in order to use it, so the panel is shown once instead
	# of waiting behind the bottom panel's selector. Closing it hides it; the selector
	# brings it back. A headless editor (CI's import pass) has no panel to show.
	if DisplayServer.get_name() != "headless":
		call_deferred("_reveal_dock")


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_bottom_panel(_dock)
	_dock.queue_free()
	_dock = null


func _reveal_dock() -> void:
	if _dock != null and is_instance_valid(_dock):
		make_bottom_panel_item_visible(_dock)
