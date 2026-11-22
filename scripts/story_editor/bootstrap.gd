extends Node
## The one place the story editor reaches a running game. Both the retail iPhone build and
## the separate author app carry it; the retail one only lets the menus open the editor
## after Settings → Story editor is switched on, and its autoload is installed by the
## menus themselves (so a separate author build can still be started by staging it).

const Overlay := preload("res://scripts/story_editor/author_overlay.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")

var _store: Store
var _overlay: Node


func _ready() -> void:
	get_tree().scene_changed.connect(_attach)
	_attach.call_deferred()


func has_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


## Opens the editor on the current scene. The pause menu's entry calls this; it returns
## false when no world is running or the drawer cannot take the screen right now.
func open_editor() -> bool:
	if _overlay == null or not is_instance_valid(_overlay):
		return false
	var editor := _overlay as Overlay
	if editor == null:
		return false
	if not editor.can_open():
		return false
	editor.open_editor()
	return editor.is_editing()


func _attach() -> void:
	var world := get_tree().current_scene
	if world == null or not world.has_node(^"DialogueController") or not world.has_node(^"GameUI") \
			or world.has_node(^"AuthorOverlay"):
		return
	if _store == null:
		_store = Store.new()
		_store.load_workspace()
	var editor := Overlay.new()
	editor.store = _store
	world.add_child(editor)
	_overlay = editor
