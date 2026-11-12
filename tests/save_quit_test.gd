extends SceneTree
## Save and quit, Continue, and a new game that really is one.
##
## The pause menu's **Save and quit** is the player's way out of a run, and the title's
## **Continue** the way back in. This check plays both through the real scenes - the
## `PauseMenu` inside `main.tscn`, the title screen as the current scene - and asserts what
## a player would notice:
##
## 1. **At rest, it saves where the player stands** and goes to the title. The file holds
##    the flags and the exact position; the title then offers Continue with the room and
##    the time under it, and Continue puts the body back where it stood.
## 2. **In the prologue (or a conversation, or a beat) it does not write.** It asks first,
##    names the save the next Continue will load, opens on Cancel, and leaving does not
##    touch the file - not even through the autosave of the world being left.
## 3. **With nothing saved and nothing savable** it says the next game starts over.
## 4. **A write that fails** is reported and asked about; the menu never leaves silently.
## 5. **New game from the title does not bring the old run back.** A leftover of the old
##    run beside the save (a `.staged` copy from an interrupted attempt, a `.bak` from an
##    interrupted swap) used to survive the new game, and the first time the save path was
##    empty again - the new run quit before its first checkpoint - the title "recovered" it
##    and offered to continue the run the player had chosen to end.

const Harness = preload("res://tests/test_harness.gd")

const MAIN_SCENE := "res://scenes/main/main.tscn"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SAVE_PATH := "user://save.json"
const USER_DIR := "user://"
const STANDING := Vector3(1.4, 0.6, -2.2)
const PROLOGUE_FLAGS: Array[StringName] = [
	StoryFlags.MET_Q, StoryFlags.TEXTBOOK_MISSING, StoryFlags.EXPECTATION_PLAYED,
	StoryFlags.BELL_RUNG, StoryFlags.CLASS_DISMISSED,
]


## The real file layer, except that every write fails.
class RefusingIO:
	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> PackedByteArray:
		return FileAccess.get_file_as_bytes(path)

	func write_bytes(_path: String, _data: PackedByteArray) -> int:
		return ERR_FILE_CANT_WRITE

	func rename(from: String, to: String) -> int:
		var dir := DirAccess.open(USER_DIR)
		return dir.rename(from, to) if dir != null else DirAccess.get_open_error()

	func remove(path: String) -> int:
		var dir := DirAccess.open(USER_DIR)
		return dir.remove(path) if dir != null else DirAccess.get_open_error()

	func list() -> PackedStringArray:
		var dir := DirAccess.open(USER_DIR)
		return dir.get_files() if dir != null else PackedStringArray()


var _failures: Array[String] = []
var _game_state: Node = null
var _save: Node = null
var _session: Node = null
var _case := ""


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "save_quit_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_save = autoloads["save"]
	_session = Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if _game_state == null or _save == null or _session == null:
		Harness.finish(self, ["The state, save or session autoloads are unavailable."], "")
		return
	L10n.set_locale("en")
	await _check_save_and_quit_at_rest()
	await _check_quit_in_the_prologue_keeps_the_checkpoint()
	await _check_quit_with_nothing_saved()
	await _check_a_failed_write_is_asked_about()
	await _check_new_game_discards_the_old_runs_leftovers()
	Harness.clear_session_state(self)
	Harness.finish(
		self, _failures,
		"Save and quit saves where the player stands and Continue puts them back; in the "
		+ "prologue, with nothing saved, or when the write fails it asks instead of leaving and "
		+ "the file is untouched; a new game from the title leaves no leftover of the old run "
		+ "for the next boot to recover."
	)


# --- 1. Save and quit at rest, then Continue -----------------------------------------


func _check_save_and_quit_at_rest() -> void:
	_case = "save and quit at rest"
	Harness.stage = _case
	var world := await _open_world(true)
	if world == null:
		return
	var player := world.get_node("Player") as PlayerController
	player.teleport(Transform3D(Basis.IDENTITY, STANDING))
	await _physics_frames(2)
	var standing := player.global_position
	_expect(bool(_session.call("is_at_rest", world)), "%s: the world is not at rest (%s)." % [
		_case, _rest_report(world)
	])
	var menu := world.get_node("PauseMenu") as PauseMenu
	menu.open()
	await _frames(2)
	_expect(
		menu.get_status_text() == L10n.t("menu.no_save_yet"),
		"%s: with no save the status reads '%s'." % [_case, menu.get_status_text()]
	)
	menu.activate(&"save_quit")
	_expect(not menu.get_confirm().visible, "%s: a savable moment asked a question." % _case)
	var title := await _wait_for_title()
	_expect(not paused, "%s: the title opened paused." % _case)
	var read: Dictionary = _save.read_save()
	_expect(bool(read.get("ok", false)), "%s: no readable save was written: %s" % [_case, str(read)])
	if bool(read.get("ok", false)):
		var payload: Dictionary = read["payload"]
		var world_block: Dictionary = payload.get("world", {})
		_expect(
			String(world_block.get("location_id", "")) == "classroom",
			"%s: the save is in '%s'." % [_case, world_block.get("location_id", "")]
		)
		var position: Array = world_block.get("position", [0, 0, 0])
		var saved := Vector3(float(position[0]), float(position[1]), float(position[2]))
		_expect(saved.distance_to(standing) < 0.05, "%s: saved %s, stood at %s." % [
			_case, str(saved), str(standing)
		])
	if title == null:
		return
	_expect(
		title.get_entry_ids().has(&"continue") and title.get_entry_ids()[0] == &"continue",
		"%s: the title does not offer Continue first (%s)." % [_case, str(title.get_entry_ids())]
	)
	_expect(
		title.get_continue_detail().contains(L10n.t("place.classroom")),
		"%s: Continue's line is '%s', without the room." % [_case, title.get_continue_detail()]
	)
	# Continue: the same flags, the same room, the same place to stand.
	_game_state.clear()
	title.activate(&"continue")
	var resumed := await _wait_for_world()
	if resumed == null:
		return
	await _physics_frames(3)
	for flag: StringName in PROLOGUE_FLAGS:
		_expect(bool(_game_state.get_flag(flag, false)), "%s: Continue lost '%s'." % [_case, flag])
	var player_again := resumed.get_node("Player") as PlayerController
	var drift := player_again.global_position.distance_to(standing)
	_expect(drift < 0.25, "%s: Continue put the body %.2f m from where it stood." % [_case, drift])
	await _free_current_scene()


# --- 2. In the prologue: ask, keep the checkpoint -------------------------------------


func _check_quit_in_the_prologue_keeps_the_checkpoint() -> void:
	_case = "save and quit in the prologue"
	Harness.stage = _case
	Harness.clear_session_state(self)
	var written: Dictionary = _save.write_payload({
		"flags": {}, "entries": [], "check_seed": 0,
		"world": {"location_id": "classroom", "spawn": "PlayerStart"},
	})
	_expect(bool(written.get("ok", false)), "%s: the checkpoint fixture was not written." % _case)
	var before := FileAccess.get_file_as_bytes(SAVE_PATH)
	# A world that boots from the checkpoint: no flags, so the prologue is still ahead.
	var world := await _open_world(false)
	if world == null:
		return
	_expect(not bool(_session.call("is_at_rest", world)), "%s: the prologue counts as rest." % _case)
	var menu := world.get_node("PauseMenu") as PauseMenu
	menu.open()
	await _frames(2)
	_expect(
		menu.get_status_text().contains(L10n.t("place.classroom")),
		"%s: the status '%s' does not name the save's room." % [_case, menu.get_status_text()]
	)
	menu.activate(&"save_quit")
	await _frames(2)
	var confirm := menu.get_confirm()
	_expect(confirm.visible, "%s: leaving without a save did not ask first." % _case)
	_expect(
		confirm.get_message().contains(L10n.t("place.classroom")),
		"%s: the question '%s' does not say which save Continue loads." % [_case, confirm.get_message()]
	)
	_expect(focused() == confirm.get_cancel_button(), "%s: the question opened on Quit." % _case)
	confirm.get_cancel_button().pressed.emit()
	await _frames(2)
	_expect(menu.is_open() and current_scene == world, "%s: Cancel left the run." % _case)
	_expect(focused() == menu.get_entry(&"save_quit"), "%s: Cancel lost the focus." % _case)
	menu.activate(&"save_quit")
	await _frames(2)
	confirm.get_confirm_button().pressed.emit()
	await _wait_for_title()
	_expect(
		FileAccess.get_file_as_bytes(SAVE_PATH) == before,
		"%s: quitting without a save changed the save." % _case
	)
	Harness.clear_session_state(self)


# --- 3. Nothing saved, nothing savable ------------------------------------------------


func _check_quit_with_nothing_saved() -> void:
	_case = "save and quit with nothing saved"
	Harness.stage = _case
	var world := await _open_world(false)
	if world == null:
		return
	var menu := world.get_node("PauseMenu") as PauseMenu
	menu.open()
	await _frames(2)
	menu.activate(&"save_quit")
	await _frames(2)
	_expect(
		menu.get_confirm().visible
		and menu.get_confirm().get_message() == L10n.t("menu.confirm_quit_no_save"),
		"%s: the question was '%s'." % [_case, menu.get_confirm().get_message()]
	)
	menu.get_confirm().get_cancel_button().pressed.emit()
	await _frames(2)
	_expect(not _save.has_save(), "%s: cancelling wrote a save." % _case)
	await _free_current_scene()


# --- 4. A write that fails ------------------------------------------------------------


func _check_a_failed_write_is_asked_about() -> void:
	_case = "save and quit whose write fails"
	Harness.stage = _case
	var world := await _open_world(true)
	if world == null:
		return
	var menu := world.get_node("PauseMenu") as PauseMenu
	menu.open()
	await _frames(2)
	_save.set("io", RefusingIO.new())
	menu.activate(&"save_quit")
	await _frames(2)
	_save.set("io", null)
	var prefix := L10n.t("menu.confirm_quit_failed").split("{detail}")[0]
	_expect(
		menu.get_confirm().visible and menu.get_confirm().get_message().begins_with(prefix),
		"%s: a failed write did not ask (question '%s')." % [_case, menu.get_confirm().get_message()]
	)
	_expect(current_scene == world, "%s: a failed write left the run." % _case)
	_expect(not _save.has_save(), "%s: a refused write left a save behind." % _case)
	menu.get_confirm().get_cancel_button().pressed.emit()
	await _frames(2)
	_expect(menu.is_open(), "%s: Cancel closed the menu." % _case)
	menu.close()
	await _free_current_scene()


# --- 5. New game from the title, with leftovers of the old run ---------------------------


func _check_new_game_discards_the_old_runs_leftovers() -> void:
	_case = "new game over the old run's leftovers"
	Harness.stage = _case
	Harness.clear_session_state(self)
	var old_flags := {}
	for flag: StringName in PROLOGUE_FLAGS:
		old_flags[String(flag)] = true
	var payload := {
		"flags": SaveCodec.encode_flags(old_flags), "entries": [], "check_seed": 7,
		"world": {"location_id": "classroom", "spawn": "PlayerStart"},
	}
	var written: Dictionary = _save.write_payload(payload)
	_expect(bool(written.get("ok", false)), "%s: the old run's save was not written." % _case)
	var old_bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	for stray: String in [
		"user://save.json.000000000001-001-0001.staged", "user://save.json.000000000002-001-0002.bak",
	]:
		var file := FileAccess.open(stray, FileAccess.WRITE)
		file.store_buffer(old_bytes)
		file.close()
	var title := await _open_title()
	if title == null:
		return
	_expect(title.get_save_state() == &"valid", "%s: the old save reads as '%s'." % [
		_case, title.get_save_state()
	])
	title.activate(&"new_game")
	await _frames(2)
	_expect(title.get_confirm().visible, "%s: New game did not ask first." % _case)
	title.get_confirm().get_confirm_button().pressed.emit()
	var world := await _wait_for_world()
	if world == null:
		return
	var director := world.get_node("OpeningSequence") as OpeningSequence
	_expect(director.next_step() == &"wake", "%s: the new game resumed at '%s'." % [
		_case, director.next_step()
	])
	_expect(
		not bool(_game_state.get_flag(StoryFlags.MET_Q, false)), "%s: old flags came back." % _case
	)
	_expect(_strays().is_empty(), "%s: %s survived the new game." % [_case, str(_strays())])
	# The new run quits before its first checkpoint: the next boot must not find the old one.
	director.set("autosave_enabled", false)
	world.queue_free()
	await _frames(3)
	if _save.has_save():
		_save.call("delete_save")
	var report: Dictionary = _session.call("inspect_save")
	_expect(
		StringName(report.get("state", &"")) == &"none",
		"%s: the next boot found a save again (%s): the old run came back." % [_case, str(report)]
	)
	Harness.clear_session_state(self)


# --- Helpers --------------------------------------------------------------------------


## `main.tscn` as the current scene, the way Continue and New game leave it. With `rest`
## the prologue is behind the player and they have control; without it the flags are
## whatever the session holds (a fresh run, or the checkpoint it booted from).
func _open_world(rest: bool) -> Node:
	paused = false
	if current_scene != null:
		# The title a previous case left: it must not keep listening for keys underneath.
		current_scene.queue_free()
		await _frames(2)
	if rest:
		Harness.clear_session_state(self)
		for flag: StringName in PROLOGUE_FLAGS:
			_game_state.set_flag(flag, true)
		_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.leave_classroom")
	var packed: PackedScene = load(MAIN_SCENE)
	var world := packed.instantiate()
	world.get_node("OpeningSequence").set("autostart", false)
	root.add_child(world)
	current_scene = world
	await _frames(3)
	var director := world.get_node_or_null("OpeningSequence") as OpeningSequence
	if director == null:
		_failures.append("%s: main.tscn has no OpeningSequence." % _case)
		return null
	if rest:
		director.allow_player_control()
		await _frames(2)
	return world


func _open_title() -> TitleScreen:
	change_scene_to_file(TITLE_SCENE)
	return await _wait_for_title()


func _wait_for_title() -> TitleScreen:
	for _index in 120:
		await process_frame
		if current_scene is TitleScreen:
			await _frames(2)
			return current_scene as TitleScreen
	_failures.append("%s: the title screen never became the current scene." % _case)
	return null


func _wait_for_world() -> Node:
	for _index in 240:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == MAIN_SCENE \
				and current_scene.get_node_or_null("OpeningSequence") != null:
			await _frames(3)
			return current_scene
	_failures.append("%s: the game never entered main.tscn." % _case)
	return null


func _free_current_scene() -> void:
	paused = false
	var scene := current_scene
	if scene != null:
		var director := scene.get_node_or_null("OpeningSequence")
		if director != null:
			director.set("autosave_enabled", false)
		scene.queue_free()
	await _frames(3)
	_save.unbind_world()
	Harness.clear_session_state(self)


func _rest_report(world: Node) -> String:
	var director := world.get_node("OpeningSequence") as OpeningSequence
	var dialogue := world.get_node("DialogueController") as DialogueController
	var player := world.get_node("Player") as PlayerController
	return "next step '%s', beat %s, dialogue %s, control %s" % [
		director.next_step(), str(director.is_beat_active()), str(dialogue.is_busy()),
		str(player.is_control_enabled()),
	]


func _strays() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return found
	for name: String in dir.get_files():
		if name.begins_with("save.json."):
			found.append(name)
	return found


func focused() -> Control:
	return root.gui_get_focus_owner()


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
