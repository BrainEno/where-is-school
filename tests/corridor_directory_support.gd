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


## Boot the actual scene for each checkpoint after the walking cases. The unmarked
## payload was captured before the first choice, with neither the tab nor wall flag.
static func check_resume(
	tree: SceneTree, main_scene: PackedScene, checkpoints: Dictionary, check: Harness.Checker
) -> void:
	var save := tree.root.get_node(^"Save")
	for key: String in ["marked", "unmarked", "wall"]:
		Harness.stage = "resume the %s checkpoint" % key
		var payload: Dictionary = checkpoints.get(key, {})
		if not check.expect(not payload.is_empty(), "Missing %s checkpoint." % key):
			continue
		Harness.clear_session_state(tree)
		if not check.expect(save.write_payload(payload).get("ok", false), "Could not write the %s checkpoint." % key):
			continue
		var main := main_scene.instantiate()
		var director := main.get_node(^"OpeningSequence") as OpeningSequence
		# Do not replay unrelated prologue beats. _ready still loads the checkpoint.
		director.autostart = false
		tree.root.add_child(main)
		if key == "wall":
			_check_resumed_wall(main, check)
		else:
			_check_resumed_tab(main, key == "marked", check)
		if not check.expect(await close_world(main), "Could not close the resumed %s world." % key):
			return
	Harness.clear_session_state(tree)


static func close_world(main: Node) -> bool:
	# The wait must not capture the Node whose destruction it is waiting for.
	var reference: WeakRef = weakref(main)
	main.queue_free()
	return await Harness.wait_until(func() -> bool: return reference.get_ref() == null, 5.0)


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
	check.expect(not state.has_flag(StoryFlags.STREET_WALL_SEEN),
		"A checkpoint from before examining the wall restored a visit.")
	var director := main.get_node(^"OpeningSequence") as OpeningSequence
	var dialogue := main.get_node(^"DialogueController") as DialogueController
	check.expect(not director.is_beat_active() and not dialogue.is_busy()
		and director.get_player().camera_rig.get_focus_subject() == null,
		"Restoring the pose replayed the directory cut-in.")


static func check_street_echo(main: Node, check: Harness.Checker) -> Dictionary:
	Harness.stage = "street wall first look and marked or unmarked revisits"
	var state := main.get_node(^"/root/GameState")
	var journal := main.get_node(^"/root/NarrativeState")
	check.expect(not state.has_flag(StoryFlags.STREET_WALL_SEEN) and not journal.has_entry(&"street_camera"),
		"Arriving in the street counted as examining the wall.")
	check.expect(state.get_flag(FLAG) == "stair", "The walk outside lost the selected mark.")
	var objective: Variant = state.get_flag(StoryFlags.OBJECTIVE_KEY)
	_look_at_wall(main, check, [&"w_1", &"w_2", &"w_3", &"w_tab_stair"])
	check.expect(state.get_flag(StoryFlags.STREET_WALL_SEEN, false) == true,
		"The first observation did not set the wall-visit flag.")
	var camera: NarrativeEntry = journal.get_entry(&"street_camera")
	check.expect(camera != null and camera.source == NarrativeEntry.Source.OBSERVED,
		"The first look did not record the camera as an observation.")
	check.expect(state.get_flag(StoryFlags.OBJECTIVE_KEY) == objective,
		"The optional look replaced the main objective.")
	for mark: String in ["", "glass", "stair"]:
		state.set_flag(FLAG, mark)
		_check_wall_revisit(main, check, mark)
	# Use the same checkpoint writer as the game, after the interaction has ended.
	var director := main.get_node(^"OpeningSequence") as OpeningSequence
	if not check.expect(director.autosave("wall revisit").get("ok", false), "Could not save the wall visit."):
		return {}
	return _read_checkpoint(main.get_node(^"/root/Save"), check)


static func _check_resumed_wall(main: Node, check: Harness.Checker) -> void:
	var state := main.get_node(^"/root/GameState")
	var journal := main.get_node(^"/root/NarrativeState")
	var camera: NarrativeEntry = journal.get_entry(&"street_camera")
	check.expect(state.get_flag(StoryFlags.STREET_WALL_SEEN, false) == true
		and state.get_flag(FLAG) == "stair" and camera != null and camera.source == NarrativeEntry.Source.OBSERVED,
		"Resuming the street did not restore the visit, tab, and observation together.")
	_check_wall_revisit(main, check, "stair")


static func _check_wall_revisit(main: Node, check: Harness.Checker, mark: String) -> void:
	var state := main.get_node(^"/root/GameState")
	var journal := main.get_node(^"/root/NarrativeState")
	var flags: Dictionary = state.get_snapshot()
	var knowledge: Dictionary = journal.to_snapshot()
	var expected: Array[StringName] = [&"w_3"]
	if not mark.is_empty():
		expected.append(StringName("w_tab_" + mark))
	_look_at_wall(main, check, expected)
	check.expect(state.get_snapshot() == flags and journal.to_snapshot() == knowledge,
		"The wall revisit for '%s' changed flags or knowledge." % mark)


static func _look_at_wall(main: Node, check: Harness.Checker, expected: Array[StringName]) -> void:
	var host := main.get_node(^"LocationHost") as LocationHost
	var room := host.get_current()
	if not check.expect(room != null and room.location_id == &"street", "The street was not loaded for a wall look."):
		return
	var wall := room.find_interactable(&"street_school_wall")
	if not check.expect(wall != null, "The street has no school-wall interaction."):
		return
	var interaction := main.get_node(^"Player/InteractionController") as InteractionController
	var dialogue := main.get_node(^"DialogueController") as DialogueController
	interaction.request_activation(wall)
	var nodes: Array[StringName] = []
	for step in range(8):
		if not dialogue.is_busy():
			break
		var line := dialogue.get_current_line()
		var node := StringName(line.get("node_id", &""))
		nodes.append(node)
		var source := NarrativeEntry.Source.RECALLED if String(node).begins_with("w_tab_") else NarrativeEntry.Source.OBSERVED
		check.expect(int(line.get("source", -1)) == source, "Wall node '%s' showed the wrong source." % node)
		dialogue.advance_presentation()
	var director := main.get_node(^"OpeningSequence") as OpeningSequence
	check.expect(nodes == expected and not dialogue.is_busy(),
		"Expected wall nodes %s, got %s." % [expected, nodes])
	check.expect(not director.is_beat_active() and director.get_player().is_control_enabled(),
		"The wall look did not give the player control back.")


static func check_return(corridor: LocationRoot, check: Harness.Checker) -> void:
	Harness.stage = "the new corridor instance restores the mark and retains the wall observation"
	var tab := corridor.get_node_or_null(TAB) as Node3D
	check.expect(tab != null and is_equal_approx(tab.position.x, 0.62),
		"Returning from the street centered the stair-side mark.")
	check.expect(corridor.get_node(^"/root/GameState").get_flag(StoryFlags.STREET_WALL_SEEN, false) == true
		and corridor.get_node(^"/root/NarrativeState").has_entry(&"street_camera"),
		"Returning to the corridor forgot the wall visit or its observation.")
