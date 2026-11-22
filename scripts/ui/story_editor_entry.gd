extends RefCounted
## The pause menu's sixth entry and the editor behind it, in one place.
##
## Settings → Story editor is the only switch; the menu only asks this class what that
## switch means. Keeping the install here means the menu itself names no editor node, the
## install is idempotent (a world builds one pause menu, and every later sync returns the
## same `StoryEditor`), and turning the switch off frees the node - which also unloads any
## draft it held in memory.
##
## `entry_for` is given the menu's own entry factory, so the sixth row cannot drift from
## the other five in size, wrapping or focus behaviour.

const Bootstrap := preload("res://scripts/story_editor/bootstrap.gd")

const STORY_ENTRY := &"story_editor"
const NODE_NAME := "StoryEditor"

## The world's root, where the editor is installed (so it outlives a scene swap).
var _root: Node
## Builds and registers the row; supplied by the menu.
var _make_entry: Callable
## Removes the row from the menu, if it is there.
var _drop_entry: Callable
## Whether the menu currently holds a row for the editor.
var _has_entry: Callable


func _init(
	root: Node, make_entry: Callable, drop_entry: Callable, has_entry: Callable
) -> void:
	_root = root
	_make_entry = make_entry
	_drop_entry = drop_entry
	_has_entry = has_entry


## Makes the world match the switch: installs or frees the editor, and adds or removes the
## row. Safe to call on every change and at startup.
func sync(settings: Node) -> void:
	var wanted := settings != null and settings.has_method("is_story_editor_enabled") \
		and bool(settings.call("is_story_editor_enabled"))
	var existing := installed()
	if wanted and existing == null:
		var editor: Node = Bootstrap.new()
		editor.name = NODE_NAME
		_root.add_child(editor)
	elif not wanted and existing != null:
		existing.queue_free()
	if wanted:
		entry()
	elif bool(_has_entry.call()):
		_drop_entry.call()


## The installed editor, or null when the switch is off (or no world is running).
func installed() -> Node:
	if _root == null or not is_instance_valid(_root):
		return null
	return _root.get_node_or_null(NodePath(NODE_NAME))


## Opens the editor over the running world. The row is only offered while the editor is
## installed, so this is the click: no editor code is decided here.
func open() -> bool:
	var editor := installed()
	if editor == null or not editor.has_method("open_editor"):
		return false
	return bool(editor.call("open_editor"))


## The row, built on demand. A session that never turns the switch on neither shows it nor
## pays for its text; `sync()` removes it again when the switch goes off. Returns the row
## the menu now holds, or null when the menu could not make one.
func entry() -> Button:
	var button: Button = _make_entry.call()
	if button != null:
		button.pressed.connect(open)
	return button
