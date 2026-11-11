extends SceneTree
## Save a session, throw the world away, and build it again from the file.
##
## This is the end-to-end half of #60's acceptance: a real `main.tscn` is played into a
## known state, `autosave()` writes it, the scene is freed, the state nodes are wiped,
## and a second `main.tscn` is instantiated. If the second one comes back in the right
## room, on the right marker, at the right spot, with the flags, knowledge and dice
## seed of the first, then "quit and come back" works - which is the only thing a
## player will ever test.
##
## The last section is the other half: a file nobody can read must not silently reset
## the run, so the game is expected to refuse it, keep a copy, say so on screen, and
## start a new game.

const Harness = preload("res://tests/test_harness.gd")
const MAIN_SCENE := "res://scenes/main/main.tscn"
const SAVE_PATH := "user://save.json"
const BROKEN_PATH := "user://save.broken.json"

var _failures: Array[String] = []

var _game_state: Node = null
var _narrative: Node = null
var _save: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "save_roundtrip_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_save = autoloads["save"]
	if _game_state == null or _narrative == null or _save == null:
		Harness.finish(self, ["The state or save autoload could not be created."], "")
		return
	Harness.clear_session_state(self)

	await _check_round_trip()
	await _check_refusal_at_boot()

	Harness.finish(
		self,
		_failures,
		"a saved run comes back whole, and a broken save is refused out loud."
	)


# --- The round trip ---------------------------------------------------------


func _check_round_trip() -> void:
	Harness.stage = "the first run"
	var main := await _enter_main()
	if main == null:
		return
	var sequence := main.get_node_or_null("OpeningSequence")
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var player := main.get_node_or_null("Player") as PlayerController
	var dialogue := main.get_node_or_null("DialogueController")
	if sequence == null or host == null or player == null or dialogue == null:
		_failures.append("main.tscn is missing a node the save system needs.")
		main.free()
		return
	if host.get_current() == null:
		_failures.append("The classroom did not load, so there is nothing to save.")
		main.free()
		return

	# A session in a known state: the prologue behind it, knowledge recorded, a seed
	# chosen, and a body somewhere that is not the spawn marker.
	for flag in [
		StoryFlags.MET_Q,
		StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED,
		StoryFlags.BELL_RUNG,
		StoryFlags.CLASS_DISMISSED,
	]:
		_game_state.set_flag(flag, true)
	_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.leave_classroom")
	_narrative.record(
		&"seen_board", NarrativeEntry.Source.OBSERVED, &"protagonist", "The board, read."
	)
	_narrative.record(
		&"claim_b_strict", NarrativeEntry.Source.REPORTED, &"q", "Q says B is strict."
	)
	dialogue.set_session_seed(31337)
	var standing := Transform3D(Basis.IDENTITY, Vector3(1.4, 0.6, -2.2))
	player.teleport(standing)
	await _physics_frames(2)
	var saved_position := player.global_position
	var saved_location := host.get_current().location_id
	var saved_spawn := host.get_current_spawn()

	Harness.stage = "writing the file"
	var written: Dictionary = sequence.call("autosave", "test")
	_expect(written.get("ok", false) == true, "autosave() did not write a file: %s" % str(written))
	_expect(_save.has_save(), "autosave() reported success but there is no save file.")
	var read: Dictionary = _save.read_save()
	_expect(read["ok"] == true, "The file just written does not read back: %s" % str(read))
	_expect(int(read.get("version", 0)) == SaveCodec.VERSION, "The file's version is wrong.")

	# Tear the world down. The state nodes are wiped by hand, not through the harness:
	# `clear_session_state()` deletes the save file too, and that is the thing under test.
	main.queue_free()
	await _frames(3)
	_game_state.clear()
	_narrative.clear()
	_expect(
		not is_instance_valid(dialogue),
		"The scene was freed but its dialogue controller is still alive."
	)
	dialogue = null

	Harness.stage = "the second run"
	var again := await _enter_main()
	if again == null:
		return
	var sequence_again := again.get_node_or_null("OpeningSequence")
	var host_again := again.get_node_or_null("LocationHost") as LocationHost
	var player_again := again.get_node_or_null("Player") as PlayerController
	var dialogue_again := again.get_node_or_null("DialogueController")

	_expect(
		_game_state.get_flag(StoryFlags.MET_Q, false) == true,
		"The prologue flags did not come back."
	)
	_expect(
		_game_state.get_flag(StoryFlags.CLASS_DISMISSED, false) == true,
		"The last prologue step's flag did not come back."
	)
	_expect(
		String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.leave_classroom",
		"The objective line did not come back."
	)
	_expect(
		String(sequence_again.next_step()).is_empty(),
		"The director wants to replay '%s' after a finished prologue."
		% String(sequence_again.next_step())
	)
	_expect(
		_narrative.get_entries().size() == 2,
		"Expected 2 knowledge entries after the restore, found %d."
		% _narrative.get_entries().size()
	)
	_expect(
		_narrative.get_entry(&"claim_b_strict") != null
		and _narrative.get_entry(&"claim_b_strict").source == NarrativeEntry.Source.REPORTED,
		"A reported claim came back as something else."
	)
	_expect(
		dialogue_again != null and dialogue_again.get_session_seed() == 31337,
		"The dice seed did not come back, so checks would reroll after a load."
	)
	if host_again == null or player_again == null:
		_failures.append("The restored scene has no LocationHost or Player.")
		again.free()
		return
	var restored_location := host_again.get_current()
	_expect(restored_location != null, "The restored scene has no current location.")
	if restored_location != null:
		_expect(
			restored_location.location_id == saved_location,
			"Restored into '%s', was in '%s'."
			% [String(restored_location.location_id), String(saved_location)]
		)
	_expect(
		host_again.get_current_spawn() == saved_spawn,
		"Restored spawn '%s', saved '%s'."
		% [String(host_again.get_current_spawn()), String(saved_spawn)]
	)
	await _physics_frames(2)
	var drift := player_again.global_position.distance_to(saved_position)
	_expect(
		drift < 0.25,
		"The body came back %.2f m from where it stood (saved %s, restored %s)."
		% [drift, str(saved_position), str(player_again.global_position)]
	)

	# Saving again from the restored session must produce a file that still reads.
	Harness.stage = "saving the restored session"
	var rewritten: Dictionary = sequence_again.call("autosave", "after_restore")
	_expect(rewritten.get("ok", false) == true, "The restored session could not be saved again.")

	again.queue_free()
	await _frames(3)


# --- A file nobody can read -------------------------------------------------


func _check_refusal_at_boot() -> void:
	Harness.stage = "a broken save at boot"
	_game_state.clear()
	_narrative.clear()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write a broken save fixture.")
		return
	file.store_string("{\"format\": \"where-is-school/save\", \"version\": 1, \"payload\": ")
	file.close()

	var main := await _enter_main()
	if main == null:
		return
	var sequence := main.get_node_or_null("OpeningSequence")
	var result: Dictionary = _save.get_last_result()
	_expect(result.get("ok", true) != true, "A truncated save was loaded without complaint.")
	_expect(
		not String(result.get("detail", "")).is_empty(),
		"The refusal does not say anything actionable."
	)
	_expect(
		FileAccess.file_exists(BROKEN_PATH),
		"The unreadable save was not copied aside before the new run started."
	)
	_expect(
		_game_state.get_flag(StoryFlags.MET_Q, false) == false,
		"A broken save left half a session behind."
	)
	_expect(
		sequence != null and not String(sequence.next_step()).is_empty(),
		"After a refused save the director should start the prologue from its first step."
	)

	# The player is told, on the card this build already has.
	await _frames(2)
	var ui := main.get_node_or_null("GameUI")
	var card: EndCard = ui.get_node("EndCard") if ui != null and ui.has_node("EndCard") else null
	if card != null:
		_expect(card.visible, "The save problem was not shown on screen.")
		_expect(
			not card.get_title().is_empty(),
			"The card reporting the save problem has no title."
		)
	else:
		_failures.append("main.tscn has no EndCard to report a save problem on.")

	main.queue_free()
	await _frames(3)


# --- Helpers ----------------------------------------------------------------


func _enter_main() -> Node:
	Harness.stage = "loading main.tscn"
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return null
	var main := packed.instantiate()
	var sequence := main.get_node_or_null("OpeningSequence")
	if sequence != null:
		# The beats are not what this test is about: the save system must work with the
		# director holding still.
		sequence.set("autostart", false)
	root.add_child(main)
	await _frames(3)
	return main


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
