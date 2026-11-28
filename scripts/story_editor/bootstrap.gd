extends Node
## Attaches a local draft editor to a running world. The standalone author build stages
## this as an autoload; a development run of this project installs it through the story
## editor switch (drawer always, live line editor when `Entry.live_editing_allowed()`);
## the iPhone player build installs only the detached editor.

const Overlay := preload("res://scripts/story_editor/author_overlay.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const LiveEditor := preload("res://scripts/story_editor/live_editor.gd")
const Entry := preload("res://scripts/ui/story_editor_entry.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")

var _store: Store
var _overlay: Overlay
var _live: LiveEditor


func _ready() -> void:
	_author_locale()
	get_tree().scene_changed.connect(_attach)
	_attach.call_deferred()


## The staged author app starts in the Simplified Chinese master (#395). Its profile is new
## at boot, so without this the first run opens in the fallback language and the author has to
## press 「切到简中」 before the first line can be edited - the master language of this tool is
## not a preference the author should have to find. The author's own later choice still sticks
## in their own settings file; every fresh profile simply begins where the work is. Only the
## staged app reaches this: `Entry.isolated_author()` is the same gate the pause entry uses,
## so a player's run and the ordinary project's installed editor are not moved.
func _author_locale() -> void:
	if Entry.isolated_author(get_tree().root) != self:
		return
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null and loc.has_method("get_locale") and String(loc.call("get_locale")) != Patch.LOCALE:
		loc.call("set_locale", Patch.LOCALE)


func has_overlay() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion() \
		and _overlay.get_parent() == get_tree().current_scene


func can_open() -> bool:
	if not has_overlay() or is_editing():
		return false
	if is_instance_valid(_live) and _live.controller.is_busy():
		return _live.can_open()
	return _overlay.can_open()


func is_editing() -> bool:
	return has_overlay() and (_overlay.is_editing() or (is_instance_valid(_live) and _live.is_editing()))


func open_editor() -> bool:
	if not can_open():
		return false
	if is_instance_valid(_live) and _live.can_open():
		return _live.open_editor()
	_overlay.open_editor()
	return _overlay.is_editing()


func release_overlay() -> void:
	# The live editor is a sibling under the world, not a child of this node: freeing the
	# bootstrap alone would leave it on the tree after the switch goes off.
	if is_instance_valid(_live) and not _live.is_queued_for_deletion():
		if _live.is_editing():
			_live.close_editor()
		var live_parent := _live.get_parent()
		_live.queue_free()
		if live_parent != null:
			live_parent.remove_child(_live)
		_live = null
	if not is_instance_valid(_overlay) or _overlay.is_queued_for_deletion():
		return
	# Disabling the mode releases the pause even if a final draft write fails.
	_overlay.close_editor(true)
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
	# Live editing of the presented line: the staged author app, and a development run of
	# this project on desktop (#395 follow-up). The drawer stays installed either way - it
	# is what opens when no line is on screen - and `show_launcher` only hides the world
	# button while live can answer for the pause entry.
	var live := Entry.isolated_author(get_tree().root) == self or Entry.live_editing_allowed()
	if _store == null:
		_store = Store.new("", live)
		_store.load_workspace()
	_overlay = Overlay.new()
	_overlay.store = _store
	_overlay.show_launcher = not live
	world.add_child(_overlay)
	if live:
		_live = LiveEditor.new()
		_live.store = _store
		_live.controller = world.get_node(^"DialogueController") as DialogueController
		_live.ui = world.get_node(^"GameUI") as GameUI
		_live.controller.set_author_graph_provider(_store.graph_override)
		world.add_child(_live)
	else:
		_live = null
