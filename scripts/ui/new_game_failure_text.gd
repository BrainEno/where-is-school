class_name NewGameFailureText
extends RefCounted
## What a menu says when `Session.start_new_game()` did not start a new game.
##
## The report's `detail` is for the log: English, technical, and written for whoever reads
## a bug report. The player gets this instead: one line for what went wrong, one for what
## happened to their save, and that they can try again. Every line is a locale key, so a
## screen that keeps the report (not the text) can render it again when the language
## changes. The title screen, the pause menu and the end card all go through here.

const KEY_PREFIX := "menu.new_game_failed."
## Reasons with a line of their own; anything else reads as `unknown`.
const REASONS: Array[String] = [
	"save_stage_failed", "scene_change_failed", "staged_discard_failed", "state_left", "busy",
]


## The text for `report` in the current language. An empty report gives "".
static func describe(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var reason := String(report.get("reason", ""))
	if reason == "busy":
		# Refused before anything ran: nothing to say about the save.
		return L10n.t(KEY_PREFIX + "busy")
	var lines := PackedStringArray()
	lines.append(L10n.t(KEY_PREFIX + (reason if REASONS.has(reason) else "unknown")))
	var rollback := Array(report.get("rollback", PackedStringArray()))
	if rollback.has("save_restore_failed"):
		var path := String(report.get("recovery_path", ""))
		if path.is_empty():
			path = String(report.get("staged_path", ""))
		lines.append(L10n.t(KEY_PREFIX + "save_lost", {"path": path}))
	elif bool(report.get("had_save", false)) and not rollback.has("state_restore_failed"):
		lines.append(L10n.t(KEY_PREFIX + "kept"))
	lines.append(L10n.t(KEY_PREFIX + "retry"))
	return "\n".join(lines)
