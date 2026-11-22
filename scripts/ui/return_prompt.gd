extends RefCounted
## The question before leaving a run, and the answer's consequences.
##
## The pause page's "Return to main menu" row and the touch HUD's own button both come
## here; `Session` owns the save write and the scene swap, so nothing in this class writes
## a file. Two rules make the question honest:
##
## - At rest the answer saves the run. In a beat, or after a write failed, the message names
##   the last save instead of promising a new one, and a failed write asks again before
##   leaving without it.
## - Opening the question writes nothing. Only a confirmed answer can.
##
## `PauseMenu` supplies its own confirmation card, page and `close()`, so the card that asks
## is the menu's and the menu is still the thing that leaves.

const MenuStyle := preload("res://scripts/ui/menu_style.gd")

## The pause menu's confirmation card (`ConfirmPrompt`).
var _confirm: Control
## Hides the entry page while the question is up, and back again.
var _page: Control
## Closes the menu around the question (the answer "keep playing").
var _close: Callable
## The menu's own world: the scene the session should save.
var _world: Callable
## What the open question is about: left empty while asking, set to a return kind once the
## player confirms. The menu's other question (`new_game`) sets and reads it around us.
var pending: StringName = &""


func _init(confirm: Control, page: Control, close_menu: Callable, world: Callable) -> void:
	_confirm = confirm
	_page = page
	_close = close_menu
	_world = world


## Asks before returning to the title. False when the question does not apply: another
## card is up, the session is already leaving, or this world has nothing to return from.
func ask(menu_open: bool, open_menu: Callable, block: Control) -> bool:
	if _confirm == null or _confirm.visible:
		return false
	var session := _session()
	if session == null or block == null or not block.visible \
			or bool(session.call("is_changing_scene")):
		return false
	if not menu_open:
		open_menu.call()
	else:
		_page.hide()
	var status: Dictionary = session.call("get_save_status", _world.call())
	_ask(status, bool(status.get("can_save_now", false)))
	return true


## The answer. `true` means "save, then leave"; false leaves the last checkpoint only.
func answer(confirmed: bool) -> void:
	var kind := pending
	pending = StringName()
	if not confirmed:
		if kind == &"return_save" or kind == &"return_checkpoint":
			_close.call()
		return
	if kind == &"return_save" or kind == &"return_checkpoint":
		_return_to_title(kind == &"return_save")


func _ask(status: Dictionary, write: bool, warning: String = "") -> void:
	pending = &"return_save" if write else &"return_checkpoint"
	var message := L10n.t("menu.confirm_return_save")
	if not write:
		var caption := MenuStyle.save_caption(
			String(status.get("location_id", "")), int(status.get("saved_at_unix", 0))
		)
		message = L10n.t("menu.confirm_quit_checkpoint", {"caption": caption}) \
			if status.get("ok", false) else L10n.t("menu.confirm_quit_no_save")
	if not warning.is_empty():
		message = warning + "\n\n" + message
	_confirm.ask(message, L10n.t("menu.return_to_title"), L10n.t("menu.keep_playing"),
		L10n.t("menu.confirm_heading_quit"))


func _return_to_title(write: bool) -> void:
	var session := _session()
	if session == null:
		_close.call()
		return
	var report: Dictionary = session.call("save_and_quit", write, _world.call())
	if report.get("ok", false):
		return # The scene, including the menu, has already left the tree.
	var status: Dictionary = session.call("get_save_status", _world.call())
	match String(report.get("reason", "")):
		"save_failed":
			# A second, explicit answer is required before leaving without a new save.
			_ask(status, false, L10n.t("menu.confirm_quit_failed"))
		"not_at_rest":
			_ask(status, false)
		_:
			_ask(status, write and bool(status.get("can_save_now", false)),
				L10n.t("menu.return_failed"))


func _session() -> Node:
	if not _confirm.is_inside_tree():
		return null
	return _confirm.get_node_or_null(^"/root/Session")
