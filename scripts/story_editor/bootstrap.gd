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
var _releasing := false


func _ready() -> void:
	_author_locale()
	get_tree().scene_changed.connect(_attach)
	print(
		"StoryEditor: bootstrap ready; development_default=%s live_allowed=%s scene=%s"
		% [Entry.development_default(), Entry.live_editing_allowed(), str(get_tree().current_scene)]
	)
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
	if (
		loc != null
		and loc.has_method("get_locale")
		and String(loc.call("get_locale")) != Patch.LOCALE
	):
		loc.call("set_locale", Patch.LOCALE)


func has_overlay() -> bool:
	return (
		is_instance_valid(_overlay)
		and not _overlay.is_queued_for_deletion()
		and _overlay.get_parent() == get_tree().current_scene
	)


func can_open() -> bool:
	if not has_overlay() or is_editing():
		return false
	if is_instance_valid(_live) and _live.controller.is_busy():
		return _live.can_open()
	return _overlay.can_open()


func is_editing() -> bool:
	return (
		has_overlay()
		and (_overlay.is_editing() or (is_instance_valid(_live) and _live.is_editing()))
	)


func open_editor() -> bool:
	if not can_open():
		return false
	if is_instance_valid(_live) and _live.can_open():
		return _live.open_editor()
	_overlay.open_editor()
	return _overlay.is_editing()


## Hands the world back when the editor switch goes off, and answers whether it is back:
## true when the live editor closed (its input saved), the drawer closed, and this node
## may be freed; false when the live editor could not close yet - a file exchange is
## running, or its input would not save. Nothing is released on false: the world stays
## exactly as it is (paused, the input on screen with the problem that stopped the save)
## until `closed` fires and `_finish_release` takes the rest down. Freeing an editing
## live editor here would drop that input and abandon the exchange - the fake success
## this refuses.
func release_overlay() -> bool:
	# The live editor is a sibling under the world, not a child of this node: freeing the
	# bootstrap alone would leave it on the tree after the switch goes off.
	if is_instance_valid(_live) and not _live.is_queued_for_deletion():
		if _live.is_editing() and not _live.begin_release():
			_releasing = true
			return false
		_free_live()
	_releasing = false
	_release_drawer()
	return true


## The switch came back on before a deferred release finished: the author wants the tool,
## so the pending teardown is dropped rather than finishing under them.
func cancel_release() -> void:
	_releasing = false
	if is_instance_valid(_live):
		_live.cancel_release()


func _free_live() -> void:
	# queue_free first, while the node is still in a tree so the SceneTree owns the
	# delete; remove_child then so it is gone from the world in this same call. Both
	# steps run `_exit_tree()` with `get_tree()` still valid, and by now the editor is
	# already closed, so `_exit_tree` is a no-op rather than a second cleanup.
	var live_parent := _live.get_parent()
	_live.queue_free()
	if live_parent != null:
		live_parent.remove_child(_live)
	_live = null


func _release_drawer() -> void:
	if not is_instance_valid(_overlay) or _overlay.is_queued_for_deletion():
		return
	# Disabling the mode releases the pause even if a final draft write fails.
	_overlay.close_editor(true)
	_overlay.hide()
	var overlay_parent := _overlay.get_parent()
	_overlay.queue_free()
	if overlay_parent != null:
		overlay_parent.remove_child(_overlay)
	_overlay = null


func _on_live_closed() -> void:
	if not _releasing:
		return
	# Deferred so the close stack unwinds first; `release_overlay` then finds the live
	# editor closed and takes the drawer and this node down with it.
	_finish_release.call_deferred()


## The deferred half of a refused release: the live editor closed itself - its input
## saved, or the exchange settled and the close went through - so the switch is off and
## everything may go, in the same order `Entry.reconcile` uses.
func _finish_release() -> void:
	if not _releasing or is_queued_for_deletion() or not is_inside_tree():
		return
	if not release_overlay():
		return
	var window := get_tree().root
	queue_free()
	window.remove_child(self)


func _attach() -> void:
	# While a release waits for the live editor to close, a scene change must not
	# install a fresh editor into the new world behind the switch that is already off;
	# the pending release finishes itself from the old editor's `closed`.
	if not is_inside_tree() or _releasing:
		return
	var world := get_tree().current_scene
	if world == null:
		print("StoryEditor: attach deferred; SceneTree has no current scene yet")
		return
	if (
		not world.has_node(^"DialogueController")
		or not world.has_node(^"GameUI")
		or world.has_node(^"AuthorOverlay")
	):
		print(
			"StoryEditor: attach deferred; scene=%s dialogue=%s game_ui=%s author_overlay=%s"
			% [
				world.name,
				world.has_node(^"DialogueController"),
				world.has_node(^"GameUI"),
				world.has_node(^"AuthorOverlay"),
			]
		)
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
		# A release that this editor refuses later finishes through this signal.
		_live.closed.connect(_on_live_closed)
		world.add_child(_live)
		# The install evidence authoring-ci greps for in an ordinary desktop
		# development run: a real window with the gate's real facts, not a seam.
		print("StoryEditor: live line editor attached")
	else:
		_live = null
