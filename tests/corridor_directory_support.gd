extends RefCounted
## The directory branch of corridor_art, through the real interaction and reading band.

const Harness = preload("res://tests/test_harness.gd")
const TAB := ^"DirectoryTrack/Tab"
const FLAG := StoryFlags.CORRIDOR_DIRECTORY_TAB


static func use_tab(
	corridor: LocationRoot, directory: Interactable, dialogue: DialogueController,
	check: Harness.Checker, interact_input: Callable
) -> Dictionary:
	Harness.stage = "two 01s: defer, mark the glass, defer again, mark the stair"
	var tab := corridor.get_node_or_null(TAB) as Node3D
	if not check.expect(tab != null, "The directory has no physical tab."):
		return {}
	var state := corridor.get_node(^"/root/GameState")
	var journal := corridor.get_node(^"/root/NarrativeState")
	var save := corridor.get_node(^"/root/Save")
	var director := dialogue.get_node(^"../OpeningSequence") as OpeningSequence
	var player := director.get_player()
	var interaction := player.get_node(^"InteractionController") as InteractionController
	# Releasing movement at the doorway does not stop the capsule on the same frame.
	# Measure the staging from rest so ordinary braking is not attributed to the cut-in.
	var settled := await Harness.wait_until(func() -> bool:
		return player.is_on_floor() and not player.is_path_active() \
			and Vector2(player.velocity.x, player.velocity.z).is_zero_approx(), 3.0)
	if not check.expect(settled, "The player did not come to rest beside the directory."):
		return {}
	var initial := player.global_position
	var objective: Variant = state.get_flag(StoryFlags.OBJECTIVE_KEY)
	var unmarked: Dictionary = save.capture()
	check.expect(is_zero_approx(tab.position.x) and not state.has_flag(FLAG),
		"An unmarked directory did not start centered.")
	check.expect(directory.get_prompt_override() == "prompt.corridor_directory_tab",
		"Reading did not expose the tab action.")
	var clue: NarrativeEntry = journal.get_entry(&"saw_double_01")
	check.expect(clue != null and clue.source == NarrativeEntry.Source.OBSERVED,
		"Reading the two signs did not leave an observation in the journal.")

	var expected := ""
	for choice: StringName in [&"leave", &"glass", &"leave", &"stair"]:
		if not check.expect(await Harness.wait_until(func() -> bool:
			return interaction.get_current_target() == directory, 3.0), "The directory prompt did not return."):
			return {}
		var x := tab.position.x
		interact_input.call()
		if not check.expect(await Harness.wait_until(dialogue.has_pending_choices, 4.0),
			"Using the tab did not open the choices."):
			return {}
		var runtime := dialogue.get_runtime()
		var choices := runtime.get_available_choice_ids()
		if not check.expect(runtime.get_active_conversation_id() == &"corridor_directory_tab"
			and choices == [&"glass", &"stair", &"leave"], "The tab offered the wrong choices."):
			return {}
		check.expect(is_equal_approx(tab.position.x, x) and player.camera_rig.get_focus_subject() == directory,
			"The tab moved before a choice, or the cut-in is not following the directory.")
		if choice == &"glass":
			_check_locale_swap(dialogue, check)
		var moved := choice != &"leave"
		if moved:
			expected = String(choice)
		dialogue.select_choice(choices.find(choice))
		check.expect(state.get_flag(FLAG, "") == expected, "The choice did not set the expected mark.")
		check.expect(runtime.get_current_node_id() == StringName("cd_" + String(choice)),
			"The directory did not acknowledge the selected choice.")
		dialogue.advance_presentation()
		if moved:
			check.expect(director.is_beat_active() and not player.is_control_enabled(),
				"The slide was not staged between dialogue and the return of controls.")
		var released := await Harness.wait_until(func() -> bool:
			return not dialogue.is_busy() and not director.is_beat_active() and player.is_control_enabled(), 4.0)
		if not check.expect(released, "The tab left the player locked."):
			return {}
		var stop := -0.62 if expected == "glass" else (0.62 if expected == "stair" else 0.0)
		check.expect(is_equal_approx(tab.position.x, stop), "The tab settled on the wrong side.")
		check.expect(player.camera_rig.get_focus_subject() == null,
			"The directory kept camera focus after '%s'." % choice)
		check.expect(player.global_position.distance_to(initial) < 0.1,
			"The directory moved the settled player after '%s': %s -> %s." % [choice, initial, player.global_position])
		if moved:
			var entry: NarrativeEntry = journal.get_entry(StringName("directory_mark_" + expected))
			check.expect(entry != null and entry.source == NarrativeEntry.Source.OBSERVED,
				"The journal did not remember the physical mark.")
	check.expect(state.get_flag(StoryFlags.OBJECTIVE_KEY) == objective,
		"The optional tab replaced the main objective.")
	return {"marked": _read_checkpoint(save, check), "unmarked": unmarked}


static func _check_locale_swap(dialogue: DialogueController, check: Harness.Checker) -> void:
	var from_locale := L10n.current
	var other_locale := "zh-CN" if from_locale == "en" else "en"
	var text := String(dialogue.get_current_line().get("text", ""))
	var swapped := dialogue.apply_locale(other_locale)
	check.expect(swapped and dialogue.get_runtime().get_current_node_id() == &"cd_choose"
		and dialogue.get_runtime().get_available_choice_ids() == [&"glass", &"stair", &"leave"]
		and String(dialogue.get_current_line().get("text", "")) != text,
		"Switching language changed the directory choice, not just its words.")
	check.expect(dialogue.apply_locale(from_locale), "Could not restore the locale after the directory choice.")


static func _read_checkpoint(save: Node, check: Harness.Checker) -> Dictionary:
	var read: Dictionary = save.read_save()
	if not check.expect(read["ok"] == true, "Marking the directory left no readable checkpoint."):
		return {}
	var payload: Dictionary = read["payload"]
	var flags := SaveCodec.decode_flags(payload.get("flags", {}))
	check.expect(flags["ok"] == true and flags["flags"].get(FLAG) == "stair",
		"The checkpoint did not store the chosen side of the tab.")
	return payload


## Boot the actual scene twice, after the walking cases and their later autosaves.
## The unmarked payload was captured before the first choice, with no tab field.
static func check_resume(
	tree: SceneTree, main_scene: PackedScene, checkpoints: Dictionary, check: Harness.Checker
) -> void:
	var save := tree.root.get_node(^"Save")
	for marked: bool in [true, false]:
		var key := "marked" if marked else "unmarked"
		Harness.stage = "resume the %s directory checkpoint" % key
		var payload: Dictionary = checkpoints[key]
		if not check.expect(not payload.is_empty(), "Missing %s directory checkpoint." % key):
			continue
		Harness.clear_session_state(tree)
		if not check.expect(save.write_payload(payload).get("ok", false), "Could not write the %s checkpoint." % key):
			continue
		var main := main_scene.instantiate()
		var director := main.get_node(^"OpeningSequence") as OpeningSequence
		# Do not replay unrelated prologue beats. _ready still loads the checkpoint.
		director.autostart = false
		tree.root.add_child(main)
		_check_resumed_tab(main, marked, check)
		main.queue_free()
		if not check.expect(await Harness.wait_until(func() -> bool: return not is_instance_valid(main), 5.0),
			"Could not close the resumed world."):
			return
	Harness.clear_session_state(tree)


static func _check_resumed_tab(main: Node, marked: bool, check: Harness.Checker) -> void:
	var host := main.get_node(^"LocationHost") as LocationHost
	var room := host.get_current()
	if not check.expect(room != null and room.location_id == &"corridor", "The save did not resume in the corridor."):
		return
	var tab := room.get_node_or_null(TAB) as Node3D
	check.expect(tab != null and is_equal_approx(tab.position.x, 0.62 if marked else 0.0),
		"The tab did not restore its pose from the save (marked: %s)." % str(marked))
	var state := main.get_node(^"/root/GameState")
	var journal := main.get_node(^"/root/NarrativeState")
	check.expect(state.has_flag(FLAG) == marked and state.get_flag(FLAG, "") == ("stair" if marked else ""),
		"The save did not restore the chosen side or left a mark in an unmarked save.")
	check.expect(journal.has_entry(&"directory_mark_stair") == marked,
		"The journal's stair entry did not match the checkpoint.")
	var director := main.get_node(^"OpeningSequence") as OpeningSequence
	var dialogue := main.get_node(^"DialogueController") as DialogueController
	check.expect(not director.is_beat_active() and not dialogue.is_busy()
		and director.get_player().camera_rig.get_focus_subject() == null,
		"Restoring the pose replayed the directory cut-in.")


static func check_street_echo(dialogue: DialogueController, check: Harness.Checker) -> void:
	Harness.stage = "street wall remembers only the currently marked side"
	var state := dialogue.get_node(^"/root/GameState")
	var snapshot: Dictionary = state.get_snapshot()
	for mark: String in ["", "glass", "stair"]:
		state.set_flag(FLAG, mark)
		if not check.expect(dialogue.play_conversation(&"street_wall"), "The street wall could not be examined."):
			break
		var echoes: Array[StringName] = []
		for step in range(8):
			if not dialogue.is_busy():
				break
			var line := dialogue.get_current_line()
			var node := StringName(line.get("node_id", &""))
			if String(node).begins_with("w_tab_"):
				echoes.append(node)
				check.expect(int(line["source"]) == NarrativeEntry.Source.RECALLED,
					"The street callback was labelled as observed rather than remembered.")
			dialogue.advance_presentation()
		var expected: Array[StringName] = []
		if not mark.is_empty():
			expected.append(StringName("w_tab_" + mark))
		check.expect(echoes == expected and not dialogue.is_busy(),
			"Unexpected street-wall lines for tab position '%s': %s." % [mark, echoes])
	state.replace_snapshot(snapshot)


static func check_return(corridor: LocationRoot, check: Harness.Checker) -> void:
	Harness.stage = "the new corridor instance restores the mark"
	var tab := corridor.get_node_or_null(TAB) as Node3D
	check.expect(tab != null and is_equal_approx(tab.position.x, 0.62),
		"Returning from the street centered the stair-side mark.")
