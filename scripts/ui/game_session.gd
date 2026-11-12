extends Node
## Autoload `Session`: which screen the game is on, and what "new game" means.
##
## The game boots into the title screen (`TITLE_SCENE`), which asks this node what the save
## file looks like and offers Continue / New Game / Settings accordingly. Continue enters
## `main.tscn`, whose `OpeningSequence` restores the save exactly as before (ADR 0005 §7).
##
## A new game (issue #95) is a fixed order of steps, because each one protects the next:
##
## 1. **The old world stops writing.** Its director's autosave is switched off and the save
##    manager forgets the world it was bound to. Nothing that is still running in the old
##    scene can put a checkpoint back on disk after step 3.
## 2. **The tree is unpaused**, so the old scene can actually be freed (a new game is
##    usually chosen from the pause menu or the end card).
## 3. **The old world is freed** and two frames pass, so its coroutines, timers and signal
##    connections are gone before any state is touched.
## 4. **The save is deleted** with `Save.delete_save()`. The quarantined copy of an
##    unreadable save (`save.broken.json`) is evidence, not progress: it is put back after
##    the call, so a corrupt save is never silently lost (ADR 0005 §6).
## 5. **The session state is cleared**: every story flag (which includes the location and
##    the objective) and every knowledge entry. The dialogue session seed lives on the
##    world's `DialogueController`, which step 3 freed; the next world takes a fresh one.
##    Held inputs are released so nothing from the old run is still "pressed".
## 6. **It is checked**: no save file, no flag, no entry. The report says what was found.
## 7. **The real opening starts**: `main.tscn` is entered with nothing to restore, so the
##    director runs the prologue from the wake.

signal new_game_started(report: Dictionary)

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const MAIN_SCENE := "res://scenes/main/main.tscn"

const SAVE_NONE := &"none"
const SAVE_VALID := &"valid"
const SAVE_BROKEN := &"broken"

## Mirrors `SaveManager.BROKEN_PATH`; read from the node when it is there.
const FALLBACK_BROKEN_PATH := "user://save.broken.json"

var _starting := false


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


## Enters the world; the director resumes the save if there is one.
func continue_game() -> void:
	var tree := get_tree()
	tree.paused = false
	tree.change_scene_to_file(MAIN_SCENE)


func go_to_title() -> void:
	var tree := get_tree()
	tree.paused = false
	tree.change_scene_to_file(TITLE_SCENE)


func quit_game() -> void:
	get_tree().quit()


func is_starting_new_game() -> bool:
	return _starting


## Starts over. `world` is the running game scene (the current scene when omitted); a
## test passes its own instance and `enter_world = false` to inspect the state in between.
## Returns the report described at the top of this file.
func start_new_game(world: Node = null, enter_world: bool = true) -> Dictionary:
	var report := {
		"ok": false,
		"reason": "",
		"steps": PackedStringArray(),
		"had_save": false,
		"kept_quarantine": false,
		"leftover_flags": 0,
		"leftover_entries": 0,
	}
	if _starting:
		report["reason"] = "busy"
		return report
	_starting = true
	var tree := get_tree()
	var target: Node = world
	if target == null:
		target = _find_world()
	var steps: PackedStringArray = report["steps"]

	# 1. Nothing in the old world may write a checkpoint from here on.
	_silence_world(target)
	steps.append("autosave_off")

	# 2-3. Unpause and let the old world go, completely, before touching state.
	tree.paused = false
	if target != null and is_instance_valid(target) and target != self:
		target.queue_free()
		await tree.process_frame
		await tree.process_frame
	steps.append("world_freed")

	# 4. The save, keeping the quarantined copy of an unreadable one.
	var save := _save()
	if save != null:
		report["had_save"] = bool(save.call("has_save"))
		report["kept_quarantine"] = _delete_save_keeping_quarantine(save)
	steps.append("save_deleted")

	# 5. The session itself.
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		game_state.call("clear")
	var narrative := get_node_or_null(^"/root/NarrativeState")
	if narrative != null:
		narrative.call("clear")
	_release_held_inputs()
	steps.append("state_cleared")

	# 6. Prove it.
	var save_left := save != null and bool(save.call("has_save"))
	if game_state != null:
		report["leftover_flags"] = (game_state.call("get_snapshot") as Dictionary).size()
	if narrative != null:
		report["leftover_entries"] = (narrative.call("get_entries") as Array).size()
	report["ok"] = (
		not save_left and int(report["leftover_flags"]) == 0
		and int(report["leftover_entries"]) == 0
	)
	if not bool(report["ok"]):
		report["reason"] = "state_left"
		push_error("Session: the new game left state behind: %s" % str(report))
	steps.append("verified")
	report["steps"] = steps
	_starting = false
	new_game_started.emit(report)

	# 7. The real opening.
	if enter_world:
		tree.change_scene_to_file(MAIN_SCENE)
	return report


## The running game: the current scene, or (when something added it by hand, as the
## headless checks do) the child of the root that carries the opening director.
func _find_world() -> Node:
	var tree := get_tree()
	if tree.current_scene != null:
		return tree.current_scene
	for child in tree.root.get_children():
		if child.get_node_or_null(^"OpeningSequence") != null:
			return child
	return null


func _silence_world(world: Node) -> void:
	if world != null and is_instance_valid(world):
		var director := world.get_node_or_null(^"OpeningSequence")
		if director != null and "autosave_enabled" in director:
			director.set("autosave_enabled", false)
	var save := _save()
	if save != null and save.has_method("unbind_world"):
		save.call("unbind_world")


## `Save.delete_save()` removes the save and its quarantined copy. The copy is what the
## player has left of an unreadable save, so it is read first and written back.
func _delete_save_keeping_quarantine(save: Node) -> bool:
	var broken_path := FALLBACK_BROKEN_PATH
	var script := save.get_script() as Script
	if script != null:
		var constants := script.get_script_constant_map()
		if constants.has("BROKEN_PATH"):
			broken_path = String(constants["BROKEN_PATH"])
	var kept := PackedByteArray()
	var had_copy := FileAccess.file_exists(broken_path)
	if had_copy:
		kept = FileAccess.get_file_as_bytes(broken_path)
	save.call("delete_save")
	if not had_copy:
		return false
	var file := FileAccess.open(broken_path, FileAccess.WRITE)
	if file == null:
		push_error("Session: could not keep the quarantined save at %s." % broken_path)
		return false
	file.store_buffer(kept)
	file.close()
	return true


func _release_held_inputs() -> void:
	for action: StringName in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _save() -> Node:
	return get_node_or_null(^"/root/Save")
