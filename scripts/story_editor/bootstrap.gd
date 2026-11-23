extends Node
## Attaches a local draft editor to a running world. The standalone author build stages
## this as an autoload; the iPhone player build installs it only from the saved opt-in.

const Overlay := preload("res://scripts/story_editor/author_overlay.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")

var _store: Store
var _overlay: Overlay


func _ready() -> void:
	get_tree().scene_changed.connect(_attach)
	_attach.call_deferred()


func has_overlay() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion() \
		and _overlay.get_parent() == get_tree().current_scene


func can_open() -> bool:
	return has_overlay() and _overlay.can_open()


func is_editing() -> bool:
	return has_overlay() and _overlay.is_editing()


func open_editor() -> bool:
	if not can_open():
		return false
	_overlay.open_editor()
	return _overlay.is_editing()


func release_overlay() -> void:
	if not is_instance_valid(_overlay) or _overlay.is_queued_for_deletion():
		return
	_overlay.close_editor()
	_overlay.hide()
	_overlay.queue_free()
	_overlay.get_parent().remove_child(_overlay)
	_overlay = null


func _attach() -> void:
	if not is_inside_tree():
		return
	var world := get_tree().current_scene
	if world == null or not world.has_node(^"DialogueController") or not world.has_node(^"GameUI") \
			or world.has_node(^"AuthorOverlay"):
		return
	if _store == null:
		_store = Store.new()
		_store.load_workspace()
	_overlay = Overlay.new()
	_overlay.store = _store
	world.add_child(_overlay)
