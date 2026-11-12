extends Node
## Autoload `Session`: which screen the game is on, and what "new game" means.
##
## The game boots into the title screen (`TITLE_SCENE`), which asks this node what the save
## file looks like and offers Continue / New Game / Settings accordingly. Continue enters
## `main.tscn`, whose `OpeningSequence` restores the save exactly as before (ADR 0005 §7).
##
## **A new game is a transaction, not a sequence of deletions.** The steps below run in this
## order because each one protects the next, and the boundary is the last of them:
##
## 1. **Writes stop.** `Save.suspend_writes(true)`, the old director's autosave switched off
##    and the save manager's world unbound. Nothing still running in the old scene can put a
##    checkpoint back on disk while the rest happens — not because it was asked politely, but
##    because `SaveManager` refuses the write.
## 2. **The tree is unpaused**, so the old scene can be released (a new game is usually
##    chosen from the pause menu or the end card).
## 3. **The session is copied to memory** (flags and knowledge). It is the second way back,
##    for the case where the file is fine but the hand-off to the new scene is not.
## 4. **The old save is *staged*, not deleted** — moved to a unique file and verified byte
##    for byte. From here on the save path is empty, which is what a new run means, and the
##    previous run is still on disk under a name this node remembers.
## 5. **The old world is freed** and two frames pass.
## 6. **The session state is cleared**: every story flag (which includes the location and the
##    objective) and every knowledge entry. Held inputs are released.
## 7. **It is verified**: no save at the save path, no flag, no entry — and the quarantined
##    copy of an unreadable save, if there was one, is still exactly the bytes it was.
## 8. **The opening is entered**, and the hand-off is checked: `change_scene_to_file()`'s
##    return code *and* whether the current scene actually changed.
## 9. **Commit**: the staged copy is discarded, verified gone, and writes are released.
##
## **If anything fails before 9, nothing is half-done.** Steps 1-3 are reversible, so a
## failure at 4 puts the world and its autosave back and returns the player to the run they
## were in. A failure after 5 restores the session from the memory copy *and* puts the staged
## save back, and takes the player to the title screen rather than to a freed scene — the
## safe UI, with their progress on disk and Continue offered. Either way the report says what
## failed, why, where the save is and what was restored, and the session emits
## `new_game_failed` with that report, which is what a menu renders.
##
## The old save is therefore never deleted to make room for the new run: it is moved aside,
## proved, and either put back or discarded. `SaveManager` makes the same promise one level
## down for ordinary writes (see the header of `save_manager.gd`).

## Emitted once a new game has actually started: everything cleared, the opening entered.
signal new_game_started(report: Dictionary)
## Emitted when a new game could not be started. The report is the same dictionary
## `start_new_game()` returns, so a menu can show `reason`, `detail`, `save_path` and
## `recovery_path` without parsing prose.
signal new_game_failed(report: Dictionary)

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"

const SAVE_NONE := &"none"
const SAVE_VALID := &"valid"
const SAVE_BROKEN := &"broken"

## Mirrors `SaveManager`'s paths; read from the node when it is there, so the two cannot
## drift apart without this file noticing.
const FALLBACK_SAVE_PATH := "user://save.json"
const FALLBACK_BROKEN_PATH := "user://save.broken.json"

## The scene a new game enters. A variable rather than a constant so a test can point it at
## a path that cannot be loaded and exercise the failure path for real; the game never sets
## it to anything but `MAIN_SCENE`.
var world_scene := MAIN_SCENE

var _starting := false
var _last_report: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## What the save file looks like, without applying anything: `{state, detail,
## quarantined_to}` where `state` is `SAVE_NONE`, `SAVE_VALID` or `SAVE_BROKEN`. Reading an
## unreadable file copies it to `save.broken.json`, exactly as the boot path always did.
func inspect_save() -> Dictionary:
	var report := {"state": SAVE_NONE, "detail": "", "quarantined_to": ""}
	var save := _save()
	if save == null or not save.has_method("has_save") or not bool(save.call("has_save")):
		return report
	var read: Dictionary = save.call("read_save")
	if read.get("ok", false) == true:
		report["state"] = SAVE_VALID
		return report
	report["state"] = SAVE_BROKEN
	report["detail"] = String(read.get("detail", ""))
	report["quarantined_to"] = String(read.get("quarantined_to", ""))
	return report


## Enters the world; the director resumes the save if there is one. Returns
## `{ok, error, scene}` — a caller that shows an error needs to know the scene never came.
func continue_game() -> Dictionary:
	var tree := get_tree()
	tree.paused = false
	var error := tree.change_scene_to_file(MAIN_SCENE)
	if error != OK:
		push_error("Session: could not enter %s (error %d)." % [MAIN_SCENE, error])
	return {"ok": error == OK, "error": error, "scene": MAIN_SCENE}


func go_to_title() -> Dictionary:
	return _go_to(TITLE_SCENE, "the title screen")


func quit_game() -> void:
	get_tree().quit()


func is_starting_new_game() -> bool:
	return _starting


## The report of the last `start_new_game()`, successful or not. The menu reads this when
## it prefers to ask later rather than listen to a signal.
func get_last_new_game_report() -> Dictionary:
	return _last_report.duplicate(true)


## Starts over. `world` is the running game scene (the current scene when omitted); a test
## passes its own instance and `enter_world = false` to inspect the state in between.
## Returns the report described at the top of this file.
func start_new_game(world: Node = null, enter_world: bool = true) -> Dictionary:
	if _starting:
		# A second click while the first transaction is between two awaits. It must not
		# run any of the steps again: the save may already be staged.
		var busy := _blank_report()
		busy["reason"] = "busy"
		busy["detail"] = "a new game is already being started"
		push_warning("Session: a new game is already running; the second request was ignored.")
		return busy

	_starting = true
	var report := _blank_report()
	var steps: PackedStringArray = report["steps"]
	var tree := get_tree()
	var save := _save()
	var target: Node = world if world != null else _find_world()
	report["world_scene"] = world_scene
	report["save_path"] = _save_constant(save, "SAVE_PATH", FALLBACK_SAVE_PATH)
	report["broken_path"] = _save_constant(save, "BROKEN_PATH", FALLBACK_BROKEN_PATH)

	report["had_world"] = target != null and is_instance_valid(target) and target != self

	# 1. Nothing that is still alive may write a checkpoint from here on.
	_silence_world(target)
	if save != null and save.has_method("suspend_writes"):
		save.call("suspend_writes", true)
	steps.append("writes_suspended")
	steps.append("autosave_off")

	# 2. Unpause, so the old scene can actually be freed.
	tree.paused = false
	steps.append("unpaused")

	# 3. The second way back: what the session looked like before any of this.
	var snapshot := _snapshot_session()

	# 4. The old save moves aside and is proved. This is the first step that changes what a
	#    new boot would do, so everything before it has to be undoable — and is.
	report["had_save"] = save != null and bool(save.call("has_save"))
	if bool(report["had_save"]):
		var staged: Dictionary = save.call("stage_save")
		report["staged_path"] = String(staged.get("staged_path", ""))
		if not bool(staged.get("ok", false)):
			return _abort(
				report, steps, save, target, snapshot, "save_stage_failed",
				String(staged.get("detail", "")), "the old save and the running session are "
				+ "unchanged"
			)
		steps.append("save_staged")
	else:
		steps.append("no_save")

	# The quarantined copy of an unreadable save is evidence, not progress: it is neither
	# deleted nor rewritten here, and step 7 proves it is still the same bytes.
	var quarantine_before := _read_quarantine(save)

	# 5. The old world goes, and two frames pass so its timers, coroutines and signals are
	#    gone before the state is touched.
	if target != null and is_instance_valid(target) and target != self:
		target.queue_free()
		await tree.process_frame
		await tree.process_frame
	steps.append("world_freed")

	# 6. The session itself.
	_clear_session()
	steps.append("state_cleared")

	# 7. Prove it, rather than assume it.
	var leftover := _leftovers(save, quarantine_before)
	report["save_left"] = leftover["save"]
	report["leftover_flags"] = leftover["flags"]
	report["leftover_entries"] = leftover["entries"]
	report["kept_quarantine"] = leftover["quarantine_kept"]
	report["quarantine_lost"] = leftover["quarantine_lost"]
	steps.append("verified")
	if bool(leftover["save"]) or int(leftover["flags"]) > 0 or int(leftover["entries"]) > 0:
		report["detail"] = (
			"the new game left %d flag(s), %d knowledge entr(y/ies) and %s save file behind"
			% [int(leftover["flags"]), int(leftover["entries"]),
				"a" if bool(leftover["save"]) else "no"]
		)
		return _abort(
			report, steps, save, null, snapshot, "state_left", String(report["detail"]),
			"the staged save and the session were put back"
		)
	if bool(leftover["quarantine_lost"]):
		# Nothing here removed it, so this means something outside the transaction did. The
		# new game is still the right thing to do — the run is already gone — but it must not
		# be reported as a clean one.
		push_error(
			"Session: the quarantined copy at %s changed or disappeared during the new game."
			% String(report["broken_path"])
		)

	# 8. Enter the opening. Writes stay suspended through the hand-off: the new world's
	#    `_ready` asks `has_save()`, and a recovery pass at that moment would put the staged
	#    copy back and resume the run that is being replaced.
	if enter_world:
		var previous := tree.current_scene
		var error := tree.change_scene_to_file(world_scene)
		await tree.process_frame
		await tree.process_frame
		var entered := tree.current_scene != null and tree.current_scene != previous
		report["scene_error"] = error
		report["scene"] = world_scene
		if error != OK or not entered:
			report["detail"] = (
				"could not enter %s (error %d); the current scene did not change"
				% [world_scene, error]
			)
			return _abort(
				report, steps, save, null, snapshot, "scene_change_failed", String(report["detail"]),
				"the save and the session were put back and the title screen was entered"
			)
		steps.append("scene_entered")

	# 9. Commit. The staged copy goes before writes are released, because releasing them
	#    while it is still on disk would let the very next `has_save()` recover it.
	var discarded: Dictionary = {}
	var staged_path := String(report["staged_path"])
	if save != null and save.has_method("discard_staged") and not staged_path.is_empty():
		discarded = save.call("discard_staged", staged_path)
	report["staged_removed"] = bool(discarded.get("removed", false))
	if not bool(discarded.get("ok", true)):
		push_error("Session: the staged save could not be discarded: %s"
			% String(discarded.get("detail", "")))
		report["leftovers"] = [staged_path]
	steps.append("staged_discarded")

	if save != null and save.has_method("suspend_writes"):
		save.call("suspend_writes", false)
	steps.append("writes_released")
	steps.append("committed")
	return _conclude(report, steps)


## Puts everything back and ends the transaction with a failure report.
##
## `world` is the world that is still alive (a failure before it was freed), or null when it
## is already gone — in which case the player is taken to the title screen, which is the one
## screen that is always safe to be on.
func _abort(report: Dictionary, steps: PackedStringArray, save: Node, world: Node,
		snapshot: Dictionary, reason: String, detail: String, recovery: String) -> Dictionary:
	var tree := get_tree()
	var rollback: PackedStringArray = []

	# The session first: it is the part the player can still have back.
	if not _restore_session(snapshot):
		push_error("Session: the session could not be put back after '%s'." % reason)
		rollback.append("state_restore_failed")
	else:
		rollback.append("state_restored")

	# Then the file: a staged copy is put back where the game reads it, and proved.
	var staged_path := String(report.get("staged_path", ""))
	if save != null and not staged_path.is_empty():
		var restored: Dictionary = save.call("restore_staged", staged_path)
		report["recovery_path"] = String(restored.get("path", ""))
		if bool(restored.get("ok", false)):
			rollback.append("save_restored")
		else:
			report["recovery_path"] = staged_path
			rollback.append("save_restore_failed")
			push_error("Session: the staged save could not be put back: %s"
				% String(restored.get("detail", "")))

	# Then the world, if it is still there to switch back on.
	if world != null and is_instance_valid(world):
		_restore_world(world)
		rollback.append("world_restored")

	if save != null and save.has_method("suspend_writes"):
		save.call("suspend_writes", false)
	rollback.append("writes_released")

	# Somewhere safe to be: the old world if it survived, otherwise the title screen.
	if world != null and is_instance_valid(world) and tree.current_scene == world:
		rollback.append("stayed_in_world")
	else:
		var target := TITLE_SCENE
		var error := _go_to(target, "the title screen")
		report["scene_error"] = error
		rollback.append("title_entered" if error == OK else "title_failed")

	report["rollback"] = rollback
	report["reason"] = reason
	report["detail"] = "%s (%s)" % [detail, recovery]
	return _conclude(report, steps)


## Ends the transaction: the report is final, the flag is cleared on every path, and the
## signal that matches the outcome is emitted.
func _conclude(report: Dictionary, steps: PackedStringArray) -> Dictionary:
	report["steps"] = steps
	report["ok"] = String(report["reason"]).is_empty()
	_starting = false
	_last_report = report.duplicate(true)
	if bool(report["ok"]):
		new_game_started.emit(report.duplicate(true))
	else:
		push_error("Session: the new game did not start: %s" % str(report))
		new_game_failed.emit(report.duplicate(true))
	return report


func _blank_report() -> Dictionary:
	return {
		"ok": false,
		"reason": "",
		"detail": "",
		"steps": PackedStringArray(),
		"rollback": PackedStringArray(),
		"had_save": false,
		"had_world": false,
		"staged_path": "",
		"staged_removed": false,
		"save_path": FALLBACK_SAVE_PATH,
		"broken_path": FALLBACK_BROKEN_PATH,
		"recovery_path": "",
		"leftovers": [],
		"scene": "",
		"scene_error": 0,
		"world_scene": world_scene,
		"save_left": false,
		"leftover_flags": 0,
		"leftover_entries": 0,
		"kept_quarantine": false,
		"quarantine_lost": false,
	}


## The running game: the current scene when it is a world, or (when something added it by
## hand, as the headless checks do) the child of the root that carries the opening director.
##
## The title screen is deliberately not a "world": a new game started from it must not
## silence, bind or free anything, because there is no session to protect yet.
func _find_world() -> Node:
	var tree := get_tree()
	if tree.current_scene != null and _is_world(tree.current_scene):
		return tree.current_scene
	for child in tree.root.get_children():
		if _is_world(child):
			return child
	return null


func _is_world(node: Node) -> bool:
	return node != null and node.get_node_or_null(^"OpeningSequence") != null


func _silence_world(world: Node) -> void:
	if world != null and is_instance_valid(world):
		var director := world.get_node_or_null(^"OpeningSequence")
		if director != null and "autosave_enabled" in director:
			director.set("autosave_enabled", false)
	var save := _save()
	if save != null and save.has_method("unbind_world"):
		save.call("unbind_world")


## The undo of `_silence_world`, for a transaction that had to stop early.
func _restore_world(world: Node) -> void:
	if world == null or not is_instance_valid(world):
		return
	var director := world.get_node_or_null(^"OpeningSequence")
	if director != null and "autosave_enabled" in director:
		director.set("autosave_enabled", true)
	var save := _save()
	if save != null and save.has_method("bind_world"):
		save.call("bind_world", world)


func _snapshot_session() -> Dictionary:
	var snapshot := {"flags": {}, "entries": []}
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		snapshot["flags"] = (game_state.call("get_snapshot") as Dictionary).duplicate(true)
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		var serialized: Dictionary = narrative.call("to_snapshot")
		snapshot["entries"] = (serialized.get("entries", []) as Array).duplicate(true)
	return snapshot


func _restore_session(snapshot: Dictionary) -> bool:
	var restored := true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		game_state.call("replace_snapshot", (snapshot.get("flags", {}) as Dictionary).duplicate(true))
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		var result: Dictionary = narrative.call(
			"restore_snapshot", {"entries": (snapshot.get("entries", []) as Array).duplicate(true)}
		)
		restored = result.get("ok", false) == true
	return restored


func _clear_session() -> void:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		game_state.call("clear")
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		narrative.call("clear")
	_release_held_inputs()


func _leftovers(save: Node, quarantine_before: PackedByteArray) -> Dictionary:
	var found := {"save": false, "flags": 0, "entries": 0,
		"quarantine_kept": false, "quarantine_lost": false}
	if save != null and save.has_method("has_save"):
		# `has_save()` also recovers a save left behind by an interrupted write, which is
		# exactly what must not happen in the middle of this transaction — but writes are
		# still suspended here, and that is what stops it.
		found["save"] = bool(save.call("has_save"))
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		found["flags"] = (game_state.call("get_snapshot") as Dictionary).size()
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		found["entries"] = (narrative.call("get_entries") as Array).size()

	var after := _read_quarantine(save)
	found["quarantine_kept"] = not after.is_empty()
	if quarantine_before.is_empty():
		found["quarantine_lost"] = false
	else:
		found["quarantine_lost"] = after != quarantine_before
		found["quarantine_kept"] = not found["quarantine_lost"]
	return found


func _read_quarantine(save: Node) -> PackedByteArray:
	var path := _save_constant(save, "BROKEN_PATH", FALLBACK_BROKEN_PATH)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## A constant from the save node's own script, so the paths here cannot drift from the ones
## the writer uses without this file noticing.
func _save_constant(save: Node, name: String, fallback: String) -> String:
	if save == null:
		return fallback
	var script := save.get_script() as Script
	if script == null:
		return fallback
	var constants := script.get_script_constant_map()
	if constants.has(name):
		return String(constants[name])
	return fallback


func _release_held_inputs() -> void:
	for action: StringName in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _go_to(scene: String, what: String) -> int:
	var error := get_tree().change_scene_to_file(scene)
	if error != OK:
		push_error("Session: could not enter %s (error %d)." % [what, error])
	return error


func _save() -> Node:
	return get_node_or_null(^"/root/Save")
