extends SceneTree
## Exercise the classroom exchanges through the real opening, interaction dispatcher,
## controller and save file. The fixture starts at the checkpoint after Q's intro;
## opening_flow_test covers the wake and q_wake itself.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const READ_LOG := "user://prologue_dialogue_paths_read_log.json"
const CHECK_NODE := &"ad_square_check"
const CHECK_KEY := "q_after_dismissal/ad_square_check"

var _checks := Harness.Checker.new()
var _state: Node
var _narrative: Node
var _main: PackedScene
var _world: Node
var _sequence: OpeningSequence
var _dialogue: DialogueController
var _interaction: InteractionController
var _room: LocationRoot
var _played: Array[StringName] = []
var _lines: Array[StringName] = []
var _rolls: Array[Dictionary] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "prologue_dialogue_paths_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_main = load(MAIN) as PackedScene
	if _state == null or _narrative == null or autoloads["save"] == null or _main == null:
		Harness.finish(self, ["Could not load main scene and story/save autoloads."], "")
		return
	# Headless starts with a tiny placeholder viewport; use the game's design size.
	root.size = Vector2i(1600, 900)
	Engine.time_scale = 10.0
	for locale: String in ["zh-CN", "en"]:
		await _square_then_bag(locale, locale == "zh-CN")
		await _bag_then_square(locale)
		await _no_search(locale)
	await _book_without_pact("zh-CN", true)
	await _book_without_pact("en", false)
	await _release()
	Engine.time_scale = 1.0
	Harness.clear_session_state(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(READ_LOG))
	Harness.finish(self, _checks.failures,
		"Bilingual classroom paths: book sharing, accusation, testimony, self-answer and silence; "
		+ "early and late ruler inspection, both check results, and a save with no replay.")


func _square_then_bag(locale: String, succeeds: bool) -> void:
	Harness.stage = locale + ": ruler, share the book, answer, place the sound, reload"
	await _boot(locale)
	await _inspect(&"set_square")
	_entry(&"saw_set_square", NarrativeEntry.Source.OBSERVED)
	_entry(&"recall_set_square_placed", NarrativeEntry.Source.RECALLED)
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1") or not _pick(&"square"):
		return
	if not await _menu(&"q_after_bag", &"q_ab_1"):
		return
	_choice(&"square", false)
	if not _pick(&"told") or not await _menu(&"q_after_bag", &"q_told_2") or not _pick(&"share"):
		return
	if not await _menu(&"n_class", &"n_8"):
		return
	_entry(&"q_set_square_use", NarrativeEntry.Source.REPORTED)
	_checks.expect(_flag(StoryFlags.Q_BOOK_PACT), "Sharing did not carry a promise into the lesson.")
	_checks.expect(ConversationRouter.select(&"q", _state.get_snapshot()) == &"q_studying",
		"Q's completed book exchange did not go back to the short studying response.")
	_switch_at_book_choice(locale)
	if not _pick(&"share_with_q"):
		return
	_checks.expect(_played == [&"q_after_bag", &"expected_b", &"bell_moment", &"n_class"],
		"Search path played the wrong sequence: %s." % str(_played))
	if not await _answer_roll(&"answer_self", "answered_self", &"n_roll_answered_self"):
		return
	_entry(&"n_allows_book_sharing", NarrativeEntry.Source.REPORTED)

	var resolver := _resolver_for(succeeds)
	if resolver == null:
		return
	_dialogue.set_check_resolver(resolver)
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_entry(&"q_repeated_absence_rumor", NarrativeEntry.Source.REPORTED)
	_choice(&"place_sound", false)
	if not _pick(&"look_back_at_square") or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_entry(&"q_n_left_square_alone", NarrativeEntry.Source.REPORTED)
	_checks.expect(not _narrative.has_entry(&"q_set_square_after_roll"),
		"Q repeated his account of the ruler's origin.")
	if not _pick(&"place_sound") or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_rolls.size() == 1 and _rolls[0].get("success") == succeeds
		and _rolls[0].get("kind") == "visible", "The ruler check used the wrong result/presentation.")
	_checks.expect(not _flag(StoryFlags.LEFT_CLASSROOM) and not _flag(StoryFlags.FREE_PERIOD_STAYED)
		and not _flag(StoryFlags.FREE_PERIOD_LEAVING), "An inquiry decided where the player would go.")
	var entry := &"recall_square_sound_close" if succeeds else &"q_set_square_pause"
	var source := NarrativeEntry.Source.RECALLED if succeeds else NarrativeEntry.Source.REPORTED
	_entry(entry, source)
	_choice(&"look_back_at_square", false)
	_choice(&"place_sound", false)
	if not _pick(&"later") or not await _finish():
		return

	var saved: Dictionary = _sequence.autosave("prologue dialogue paths")
	if not _checks.expect(saved.get("ok", false), "Could not save the completed branch."):
		return
	var check_flag := StoryFlags.check_record_flag(&"q_after_dismissal", CHECK_NODE)
	await _release()
	# Leave the file intact, but prove that nothing comes from the previous world in RAM.
	_state.clear()
	_narrative.clear()
	await _boot(locale, false)
	_checks.expect(_sequence.next_step() == &"" and _flag(StoryFlags.Q_BOOK_PACT)
		and _flag(StoryFlags.Q_BOOK_TALK_DONE) and _flag(StoryFlags.Q_ROLL_DEBRIEFED)
		and _state.get_flag(StoryFlags.N_ROLL_RESPONSE, "") == "answered_self"
		and _state.get_flag(check_flag, null) is Dictionary, "Save lost classroom progress or choices.")
	_entry(entry, source)
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_played == [&"q_after_dismissal"] and not _lines.has(&"q_ad_present")
		and not _lines.has(&"q_ad_lead"), "Reload replayed the roll call or Q's debrief.")
	_choice(&"look_back_at_square", false)
	_choice(&"place_sound", false)
	if _pick(&"yes"):
		await _finish()
		_checks.expect(_flag(StoryFlags.FREE_PERIOD_LEAVING) and not _flag(StoryFlags.FREE_PERIOD_STAYED)
			and not _flag(StoryFlags.LEFT_CLASSROOM), "Changing your mind should not move the player.")


func _bag_then_square(locale: String) -> void:
	Harness.stage = locale + ": bag first, accuse, ask Q in front of N, late ruler"
	await _boot(locale)
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1"):
		return
	_choice(&"square", false)
	if not _pick(&"accused") or not await _menu(&"n_class", &"n_8"):
		return
	_choice(&"share_with_q", false)
	if not _pick(&"textbook") or not await _answer_roll(&"ask_q", "asked_q", &"n_roll_mark_unconfirmed"):
		return
	_checks.expect(_lines.has(&"q_n_guarded") and _flag(StoryFlags.ACCUSED_Q)
		and not _flag(StoryFlags.Q_BOOK_PACT), "N's scene lost Q's reaction to the accusation.")
	_entry(&"q_answered_at_door", NarrativeEntry.Source.REPORTED)
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_choice(&"look_back_at_square", false)
	_checks.expect(_lines.has(&"q_ad_pressed"), "Q did not respond to being questioned in front of N.")
	if not _pick(&"no") or not await _finish():
		return
	await _inspect(&"set_square")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1") or not _pick(&"look_back_at_square") \
			or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_entry(&"q_set_square_after_roll", NarrativeEntry.Source.REPORTED)
	_choice(&"place_sound", true)
	if _pick(&"no"):
		await _finish()


func _no_search(locale: String) -> void:
	Harness.stage = locale + ": wait out the bag step and leave the roll to N"
	await _boot(locale)
	if not await _menu(&"n_class", &"n_8") or not _pick(&"wait") \
			or not await _answer_roll(&"leave_to_n", "silent", &"n_roll_no_answer"):
		return
	_checks.expect(_flag(StoryFlags.BAG_WAIT_EXPIRED) and _flag(StoryFlags.EXPECTATION_SKIPPED)
		and not _flag(StoryFlags.TEXTBOOK_MISSING) and not _flag(StoryFlags.EXPECTATION_PLAYED)
		and not _played.has(&"q_after_bag") and not _played.has(&"expected_b")
		and not _narrative.has_entry(&"bag_missing_textbook"), "Timeout invented a search or memory.")
	await _inspect(&"set_square")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1") or not _pick(&"look_back_at_square") \
			or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_lines.has(&"q_ad_quiet") and not _lines.has(&"p_ad_square_memory"),
		"Silence and a late inspection produced the wrong Q response.")
	_choice(&"place_sound", false)
	if _pick(&"silent"):
		await _finish()


func _book_without_pact(locale: String, asks_witness: bool) -> void:
	Harness.stage = locale + ": question the witness or decline to discuss the book"
	await _boot(locale)
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1"):
		return
	if asks_witness:
		if not _pick(&"told") or not await _menu(&"q_after_bag", &"q_told_2") or not _pick(&"witness"):
			return
	elif not _pick(&"never"):
		return
	if not await _menu(&"n_class", &"n_8"):
		return
	if asks_witness:
		_entry(&"q_bag_witness_limits", NarrativeEntry.Source.REPORTED)
	else:
		_checks.expect(not _flag(StoryFlags.TOLD_Q_ABOUT_TEXTBOOK) and not _flag(StoryFlags.ACCUSED_Q),
			"Silence disclosed the missing book or accused Q.")
	_choice(&"share_with_q", false)
	if _pick(&"where_b") and await _answer_roll(&"leave_to_n", "silent", &"n_roll_no_answer"):
		_entry(&"n_b_name_crossed_out", NarrativeEntry.Source.REPORTED)


func _boot(locale: String, fresh: bool = true) -> void:
	await _release()
	if fresh:
		Harness.clear_session_state(self)
		_state.set_flag(StoryFlags.MET_Q, true)
		_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)
	L10n.set_locale(locale)
	_world = _main.instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_world)
	_room = (_world.get_node(^"LocationHost") as LocationHost).get_current()
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_interaction = _world.get_node(^"Player/InteractionController") as InteractionController
	_dialogue.apply_locale(locale)
	_dialogue.set_read_log(ReadLog.new(READ_LOG))
	_played.clear()
	_lines.clear()
	_rolls.clear()
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _played.append(id))
	_dialogue.line_presented.connect(func(line: Dictionary) -> void:
		_lines.append(StringName(line.get("node_id", ""))))
	_dialogue.check_resolved.connect(func(result: Dictionary) -> void: _rolls.append(result))
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	await process_frame
	_sequence.start()


func _release() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await process_frame
		await process_frame
	_world = null


func _activate(id: StringName) -> void:
	var target := _room.find_interactable(id) if _room != null else null
	if _checks.expect(target != null and _interaction.is_enabled(), "Cannot use %s in %s." % [id, Harness.stage]):
		_interaction.request_activation(target)


func _inspect(id: StringName) -> void:
	_activate(id)
	if not _checks.expect(_dialogue.get_mode() == DialogueController.Mode.INSPECTION,
		"No inspection started for %s." % id):
		return
	while _dialogue.get_mode() == DialogueController.Mode.INSPECTION:
		_dialogue.advance_presentation()
		await process_frame


func _menu(conversation: StringName, node: StringName) -> bool:
	var deadline := Time.get_ticks_msec() + 22000
	while Time.get_ticks_msec() < deadline:
		if _dialogue.has_pending_choices():
			var runtime := _dialogue.get_runtime()
			return _checks.expect(runtime.get_active_conversation_id() == conversation
				and runtime.get_current_node_id() == node, "%s: wanted %s/%s, got %s/%s." % [
					Harness.stage, conversation, node, runtime.get_active_conversation_id(), runtime.get_current_node_id()])
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	return _checks.expect(false, "%s: timed out waiting for %s/%s (played %s)."
		% [Harness.stage, conversation, node, str(_played)])


func _finish() -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while _dialogue.is_busy() or _sequence.is_beat_active():
		if _dialogue.has_pending_choices() or Time.get_ticks_msec() >= deadline:
			return _checks.expect(false, "%s: last choice did not release the scene." % Harness.stage)
		_dialogue.advance_presentation()
		await process_frame
	return true


func _choice(id: StringName, available: bool) -> void:
	_checks.expect(_dialogue.get_runtime().get_available_choice_ids().has(id) == available,
		"%s: option %s had the wrong visibility." % [Harness.stage, id])


func _pick(id: StringName) -> bool:
	var index := _dialogue.get_runtime().get_available_choice_ids().find(id)
	if not _checks.expect(index >= 0, "%s: missing option %s." % [Harness.stage, id]):
		return false
	_dialogue.select_choice(index)
	return true


func _switch_at_book_choice(locale: String) -> void:
	var runtime := _dialogue.get_runtime()
	var choices := runtime.get_available_choice_ids()
	var line := _dialogue.get_current_line()
	var flags: Dictionary = _state.get_snapshot()
	var other := "en" if locale == "zh-CN" else "zh-CN"
	_checks.expect(_dialogue.apply_locale(other), "Could not switch the lesson to %s." % other)
	_checks.expect(runtime.get_current_node_id() == &"n_8" and runtime.get_available_choice_ids() == choices
		and _dialogue.get_current_line().get("text") != line.get("text") and _state.get_snapshot() == flags,
		"Changing language changed the book choice or story state, not just the text.")
	_checks.expect(_dialogue.apply_locale(locale), "Could not restore %s." % locale)


func _answer_roll(choice_id: StringName, response: String, record_id: StringName) -> bool:
	if not await _menu(&"n_class", &"n_roll_2") or not _pick(choice_id) or not await _finish():
		return false
	_entry(&"n_found_roll_mark", NarrativeEntry.Source.REPORTED)
	_entry(record_id, NarrativeEntry.Source.REPORTED)
	_checks.expect(_state.get_flag(StoryFlags.N_ROLL_RESPONSE, "") == response
		and _flag(StoryFlags.CLASS_DISMISSED) and not _flag(StoryFlags.B_ON_STAGE)
		and _room.find_interactable(&"classroom_door").is_open(),
		"%s: wrong roll response, or the lesson did not release the class." % Harness.stage)
	return true


func _resolver_for(succeeds: bool) -> CheckResolver:
	var conversation := _dialogue.get_dialogue_library().get_conversation(&"q_after_dismissal")
	var node: DialogueGraph.DialogueNode = conversation.nodes[CHECK_NODE]
	var ability := _dialogue.get_abilities().get_value(&"orientation")
	for seed_value: int in range(64):
		var resolver := CheckResolver.new(seed_value)
		if (resolver.dice_total_for(CHECK_KEY) + ability >= int(node.check["difficulty"])) == succeeds:
			return resolver
	_checks.fail("Could not find a deterministic seed for ruler check success=%s." % str(succeeds))
	return null


func _flag(key: StringName) -> bool:
	return _state.get_flag(key, false) == true


func _entry(id: StringName, source: int) -> void:
	var entry: NarrativeEntry = _narrative.get_entry(id)
	_checks.expect(entry != null and entry.source == source,
		"%s: %s is absent or filed under the wrong source." % [Harness.stage, id])
