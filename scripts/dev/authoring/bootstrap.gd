extends Node
## The staging tool adds this autoload only to the author project. Neither the
## ordinary project nor any shared gameplay scene has a dependency on this folder.

const Overlay := preload("res://scripts/dev/authoring/author_overlay.gd")
const Store := preload("res://scripts/dev/authoring/draft_store.gd")

var _store: Store


func _ready() -> void:
	get_tree().scene_changed.connect(_attach)
	_attach.call_deferred()


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
