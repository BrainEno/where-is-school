extends RefCounted
## "New game" from the pause page, and what the menu does when it does not start.
##
## Starting a run is `Session`'s transaction: it moves the old world aside and loads a new
## one, so a failure before the world is freed leaves the pause menu alive, and a failure
## after it ends on the title screen, which reads the report itself. This class keeps that
## distinction, and the notice the menu shows on the first kind, out of `PauseMenu`.
##
## `NewGameFailureText` still words the reason; the menu still owns the page, the focus and
## the pause the transaction restored.

const FailureText := preload("res://scripts/ui/new_game_failure_text.gd")


## The pause menu itself (its world is the scene to replace) and its root page, hidden
## while the transaction runs, plus its confirmation card, down before the world is freed.
var _menu: Node
var _root: Control
var _confirm: Control
## Puts the menu back on screen with the notice; the menu does that with its own layout.
var _reopen: Callable
## The reason the last attempt did not start, for the menu's notice.
var _report: Dictionary = {}
## The menu's session, remembered so the failure signal can be disconnected from the
## handler it connected, not from a bound callable that is never equal to it.
var _session: Node


func _init(menu: Node, root: Control, confirm: Control, reopen: Callable) -> void:
	_menu = menu
	_root = root
	_confirm = confirm
	_reopen = reopen


## True while an attempt is out; the menu keeps its own pending question empty meanwhile.
func start() -> void:
	_session = _node()
	if _session == null:
		return
	_root.hide()
	# A failure before the world is freed (the save could not be moved aside) leaves this
	# menu alive, and it comes back with the reason. A failure after it ends on the title
	# screen, which reads the report itself; this menu is gone by then, and so is the
	# connection.
	if not _session.is_connected("new_game_failed", _on_failed):
		_session.connect("new_game_failed", _on_failed, CONNECT_ONE_SHOT)
	# The menu's own world: the session switches its autosave off before anything else.
	var immediate: Variant = _session.call("start_new_game", _world())
	if immediate is Dictionary and String((immediate as Dictionary).get("reason", "")) == "busy":
		# Refused before it started, so no signal follows.
		if _session.is_connected("new_game_failed", _on_failed):
			_session.disconnect("new_game_failed", _on_failed)
		_show(immediate as Dictionary)


## The session's own report, after the transaction failed.
func failed(report: Dictionary) -> void:
	if not _root.is_inside_tree():
		return
	var session := _node()
	if session != null and session.has_method("mark_new_game_failure_shown"):
		session.call("mark_new_game_failure_shown")
	_show(report)


## The reason the menu's notice should show, or `{}` after a run started.
func report() -> Dictionary:
	return _report


func _show(report: Dictionary) -> void:
	_report = report.duplicate(true)
	_confirm.hide()
	_reopen.call()


func _on_failed(report: Dictionary) -> void:
	failed(report)


func _node() -> Node:
	if not _root.is_inside_tree():
		return null
	return _root.get_node_or_null(^"/root/Session")


func _world() -> Node:
	return _menu.owner if _menu.owner != null else _menu.get_parent()
