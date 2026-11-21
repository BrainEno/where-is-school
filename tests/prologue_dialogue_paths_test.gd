extends SceneTree
## Exercise the classroom exchanges through the real opening, interaction dispatcher,
## controller and save file. The fixture starts at the checkpoint after Q's intro;
## opening_flow_test covers the wake and q_wake itself.
##
## The paths follow the author's own version of the prologue (round 5): the set-square
## exchange with its camera looks, the accusation and N's guarded answer, a bag never
## searched, the ruler check after the lesson, and the rear door for a player who said
## they would borrow a book next door - once failed, once taken (skipping class, alone:
## Q does not follow).

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const READ_LOG := "user://prologue_dialogue_paths_read_log.json"
const CHECK_NODE := &"ad_square_check"
const CHECK_KEY := "q_after_dismissal/ad_square_check"
const REAR_CONVERSATION := &"classroom_rear_door_borrow"
const REAR_CHECK := &"rdb_check"
const REAR_KEY := "classroom_rear_door_borrow/rdb_check"

var _checks := Harness.Checker.new()
var _state: Node
var _narrative: Node
var _main: PackedScene
var _world: Node
var _sequence: OpeningSequence
var _dialogue: DialogueController
var _interaction: InteractionController
var _host: LocationHost
var _room: LocationRoot
var _played: Array[StringName] = []
var _lines: Array[StringName] = []
var _rolls: Array[Dictionary] = []
var _inspections: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 170.0, "prologue_dialogue_paths_test.gd")
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
	await _book_talk("zh-CN", true)
	await _book_talk("en", false)
	await _rear_door(false)
	await _rear_door(true)
	await _release()
	Engine.time_scale = 1.0
	Harness.clear_session_state(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(READ_LOG))
	Harness.finish(self, _checks.failures,
		"Bilingual classroom paths: the set-square looks, accusation, silence and N's questions; "
		+ "early and late ruler inspection, both check results, a save with no replay, and the "
		+ "rear door failed and taken.")


func _square_then_bag(locale: String, succeeds: bool) -> void:
	Harness.stage = locale + ": picture B, ruler, ask about it, look again, the lesson, place the sound, reload"
	await _boot(locale, true, true)
	if not await _imagine():
		return
	await _inspect(&"set_square")
	_entry(&"saw_set_square", NarrativeEntry.Source.OBSERVED)
	_entry(&"recall_set_square_placed", NarrativeEntry.Source.RECALLED)
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1") or not _pick(&"square"):
		return
	if not await _menu(&"q_after_bag", &"q_sq_2"):
		return
	if not _pick(&"square_again"):
		return
	# The look is asked for by the option and holds for the line it leads to.
	var square := _room.find_interactable(&"set_square")
	var focus := _sequence.get_camera_focus()
	_checks.expect(await Harness.wait_until(func() -> bool:
		return focus.get_glance() == square, 2.0), "Looking at the set square again did not turn the camera to it.")
	if not await _menu(&"n_class", &"n_8"):
		return
	_checks.expect(focus.get_glance() == null, "The set-square look outlived its conversation.")
	_checks.expect(_flag(StoryFlags.Q_BOOK_TALK_DONE) and not _flag(StoryFlags.TOLD_Q_ABOUT_TEXTBOOK)
		and not _flag(StoryFlags.ACCUSED_Q), "The set-square talk closed the book talk the wrong way.")
	_checks.expect(ConversationRouter.select(&"q", _state.get_snapshot()) == &"q_studying",
		"Q's completed book exchange did not go back to the short studying response.")
	_switch_at_book_choice(locale)
	_checks.expect(_played == [&"expected_b", &"q_after_bag", &"bell_moment", &"n_class"],
		"Search path played the wrong sequence: %s." % str(_played))
	if not _pick(&"textbook") or not await _lesson_ends():
		return
	_checks.expect(_flag(StoryFlags.ASKED_N_ABOUT_TEXTBOOK) and not _lines.has(&"q_n_guarded")
		and _lines.has(&"q_free"), "Asking N about the textbook took the wrong lines.")

	var resolver := _resolver_for(succeeds, &"q_after_dismissal", CHECK_NODE, CHECK_KEY)
	if resolver == null:
		return
	_dialogue.set_check_resolver(resolver)
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_choice(&"place_sound", false)
	if not _pick(&"look_back_at_square") or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_lines.has(&"p_ad_square_memory") and _lines.has(&"q_ad_square_compare"),
		"After the imagined lesson the protagonist did not compare the remembered sound.")
	if not _pick(&"place_sound") or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_rolls.size() == 1 and _rolls[0].get("success") == succeeds
		and _rolls[0].get("kind") == "visible", "The ruler check used the wrong result/presentation.")
	_checks.expect(not _flag(StoryFlags.LEFT_CLASSROOM) and not _flag(StoryFlags.FREE_PERIOD_STAYED)
		and not _flag(StoryFlags.FREE_PERIOD_LEAVING), "An inquiry decided where the player would go.")
	if succeeds:
		_entry(&"recall_square_sound_close", NarrativeEntry.Source.RECALLED)
	else:
		_checks.expect(_lines.has(&"q_ad_square_pause") and not _narrative.has_entry(&"recall_square_sound_close"),
			"A failed placement recorded the sound anyway, or Q did not answer.")
	_choice(&"look_back_at_square", false)
	_choice(&"place_sound", false)
	if not _pick(&"later") or not await _finish():
		return
	_checks.expect(_flag(StoryFlags.FREE_PERIOD_STAYED) and not _flag(StoryFlags.FREE_PERIOD_LEAVING),
		"Deferring did not record the stay.")

	var saved: Dictionary = _sequence.autosave("prologue dialogue paths")
	if not _checks.expect(saved.get("ok", false), "Could not save the completed branch."):
		return
	var check_flag := StoryFlags.check_record_flag(&"q_after_dismissal", CHECK_NODE)
	await _release()
	# Leave the file intact, but prove that nothing comes from the previous world in RAM.
	_state.clear()
	_narrative.clear()
	await _boot(locale, false)
	_checks.expect(_sequence.next_step() == &"" and _flag(StoryFlags.Q_BOOK_TALK_DONE)
		and _flag(StoryFlags.CLASS_DISMISSED) and _state.get_flag(check_flag, null) is Dictionary,
		"Save lost classroom progress or choices.")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(_played == [&"q_after_dismissal"], "Reload replayed part of the lesson: %s." % str(_played))
	_choice(&"look_back_at_square", false)
	_choice(&"place_sound", false)
	if _pick(&"yes"):
		await _finish()
		_checks.expect(_flag(StoryFlags.FREE_PERIOD_LEAVING) and not _flag(StoryFlags.FREE_PERIOD_STAYED)
			and not _flag(StoryFlags.LEFT_CLASSROOM), "Changing your mind should not move the player.")


func _bag_then_square(locale: String) -> void:
	Harness.stage = locale + ": picture B, bag, accuse, ask N about the book, late ruler"
	await _boot(locale, true, true)
	if not await _imagine():
		return
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1"):
		return
	_choice(&"square", false)
	if not _pick(&"accused") or not await _menu(&"n_class", &"n_8"):
		return
	if not _pick(&"textbook") or not await _lesson_ends():
		return
	_checks.expect(_lines.has(&"q_n_guarded") and _flag(StoryFlags.ACCUSED_Q),
		"N's scene lost Q's reaction to the accusation.")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_choice(&"look_back_at_square", false)
	if not _pick(&"no") or not await _finish():
		return
	_checks.expect(_flag(StoryFlags.FREE_PERIOD_STAYED) and not _flag(StoryFlags.FREE_PERIOD_LEAVING)
		and String(_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.stay_classroom"
		and not _narrative.has_entry(&"n_stayed"), "Declining did not keep its stay, or wrote a note.")
	await _inspect(&"set_square")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1") or not _pick(&"look_back_at_square") \
			or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_choice(&"place_sound", true)
	if _pick(&"no"):
		await _finish()


func _no_search(locale: String) -> void:
	Harness.stage = locale + ": wait out the bag step and stay silent in front of N"
	await _boot(locale)
	if not await _menu(&"n_class", &"n_8") or not _pick(&"wait") or not await _lesson_ends():
		return
	_checks.expect(_flag(StoryFlags.BAG_WAIT_EXPIRED) and _flag(StoryFlags.EXPECTATION_SKIPPED)
		and not _flag(StoryFlags.TEXTBOOK_MISSING) and not _flag(StoryFlags.EXPECTATION_PLAYED)
		and not _played.has(&"q_after_bag") and not _played.has(&"expected_b")
		and not _narrative.has_entry(&"bag_missing_textbook"), "Timeout invented a search or memory.")
	_checks.expect(_lines.has(&"p_wait") and _lines.has(&"n_wait_1"), "Silence in front of N took the wrong lines.")
	await _inspect(&"set_square")
	_activate(&"q_talk")
	if not await _menu(&"q_after_dismissal", &"q_ad_1") or not _pick(&"look_back_at_square") \
			or not await _menu(&"q_after_dismissal", &"q_ad_1"):
		return
	_checks.expect(not _lines.has(&"p_ad_square_memory") and not _lines.has(&"q_ad_square_compare"),
		"Without the imagined lesson the protagonist still compared a remembered sound.")
	_choice(&"place_sound", false)
	if _pick(&"silent"):
		await _finish()
		_checks.expect(_flag(StoryFlags.FREE_PERIOD_STAYED)
			and String(_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.stay_classroom",
			"Saying nothing did not keep the player in the room.")


func _book_talk(locale: String, tells: bool) -> void:
	Harness.stage = locale + ": tell Q the book is gone, or question the handwriting"
	await _boot(locale)
	await _inspect(&"schoolbag")
	if not await _menu(&"q_after_bag", &"q_ab_1") or not _pick(&"told" if tells else &"never"):
		return
	if not await _menu(&"n_class", &"n_8"):
		return
	_checks.expect(_flag(StoryFlags.TOLD_Q_ABOUT_TEXTBOOK) == tells and not _flag(StoryFlags.ACCUSED_Q)
		and _flag(StoryFlags.Q_BOOK_TALK_DONE), "The book talk disclosed or accused the wrong way.")
	if _pick(&"where_b") and await _lesson_ends():
		_checks.expect(_flag(StoryFlags.ASKED_N_ABOUT_B) and _lines.has(&"n_where_1"),
			"Asking N about B took the wrong lines.")


## A player who told Q they would borrow a book next door gets one visible check at the
## rear door before the lesson. A failure is the door's line and nothing else; a later
## try is the plain locked door. A success leaves for the corridor and skips the class.
func _rear_door(succeeds: bool) -> void:
	Harness.stage = "rear door, check %s" % ("passed" if succeeds else "failed")
	await _boot("zh-CN")
	_state.set_flag(StoryFlags.BORROW_FROM_NEXT_CLASS, true)
	var resolver := _resolver_for(succeeds, REAR_CONVERSATION, REAR_CHECK, REAR_KEY)
	if resolver == null:
		return
	_dialogue.set_check_resolver(resolver)
	_activate(&"rear_door")
	if not await _drain(func() -> bool:
		return _rolls.size() == 1 and not _dialogue.is_busy() and not _sequence.is_beat_active()):
		return
	# A success may be followed by the corridor's own arrival line; nothing comes before.
	_checks.expect(not _played.is_empty() and _played[0] == REAR_CONVERSATION
		and _played.count(REAR_CONVERSATION) == 1 and _rolls[0].get("success") == succeeds
		and _rolls[0].get("kind") == "visible" and _rolls[0].get("ability") == &"orientation",
		"The rear door did not play its one visible check: %s %s." % [str(_played), str(_rolls)])
	var record: Variant = _state.get_flag(StoryFlags.check_record_flag(REAR_CONVERSATION, REAR_CHECK), null)
	_checks.expect(record is Dictionary, "The rear-door check was not recorded.")
	if not succeeds:
		_checks.expect(_host.get_current() == _room and not _flag(StoryFlags.SKIPPED_CLASS),
			"A failed rear-door check still let the player out.")
		_activate(&"rear_door")
		var inspected := await Harness.wait_until(func() -> bool:
			return _inspections.has(&"classroom_rear_door"), 5.0)
		_checks.expect(inspected and _rolls.size() == 1 and _played == [REAR_CONVERSATION],
			"After a failed attempt the rear door did not go back to its locked line.")
		return
	var in_corridor := func() -> bool:
		var current := _host.get_current()
		return current != null and current.location_id == &"corridor" and not _sequence.is_beat_active()
	var arrived := await Harness.wait_until(in_corridor, 10.0)
	if not _checks.expect(arrived and _flag(StoryFlags.SKIPPED_CLASS), "The rear door did not lead to the corridor."):
		return
	# Give the prologue every chance to carry on: the bag clock, the bell and N must not.
	await create_timer(2.0, true, false, true).timeout
	_checks.expect(_sequence.next_step() == &"" and not _flag(StoryFlags.BELL_RUNG)
		and not _flag(StoryFlags.N_ARRIVED) and not _flag(StoryFlags.CLASS_DISMISSED)
		and not _flag(StoryFlags.BAG_WAIT_EXPIRED)
		and not _played.has(&"bell_moment") and not _played.has(&"n_class"),
		"Skipping class still ran the lesson: %s." % str(_played))
	# The check and the exit are the protagonist's alone: Q stays at his desk (round 7).
	var companion := _world.get_node_or_null(^"Companion") as CompanionController
	_checks.expect(companion != null and not companion.is_joined() and not companion.is_with_player()
		and _state.get_flag(StoryFlags.Q_COMPANION, false) != true,
		"Q followed the protagonist out through the rear door.")


## `imagine`: the player chose to picture B in `q_wake` (round 7), so the imagined lesson
## is the first step the fixture plays.
func _boot(locale: String, fresh: bool = true, imagine: bool = false) -> void:
	await _release()
	if fresh:
		Harness.clear_session_state(self)
		_state.set_flag(StoryFlags.MET_Q, true)
		_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)
		if imagine:
			_state.set_flag(StoryFlags.IMAGINE_B_CHOSEN, true)
	L10n.set_locale(locale)
	_world = _main.instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_world)
	_host = _world.get_node(^"LocationHost") as LocationHost
	_room = _host.get_current()
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_interaction = _world.get_node(^"Player/InteractionController") as InteractionController
	_dialogue.apply_locale(locale)
	_dialogue.set_read_log(ReadLog.new(READ_LOG))
	_played.clear()
	_lines.clear()
	_rolls.clear()
	_inspections.clear()
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _inspections.append(id))
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
	var presented := await Harness.wait_until(func() -> bool:
		return _dialogue.get_mode() == DialogueController.Mode.INSPECTION, 10.0
	)
	if not _checks.expect(presented, "No inspection started for %s." % id):
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


## Plays the imagined lesson the fixture chose, answering B normally at every hub (the
## first option) so it reaches the authored recollection, and waits for its beat to end.
func _imagine() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while not _flag(StoryFlags.EXPECTATION_PLAYED) or _sequence.is_beat_active():
		if Time.get_ticks_msec() >= deadline:
			return _checks.expect(false, "%s: the imagined lesson did not finish (played %s)."
				% [Harness.stage, str(_played)])
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	return _checks.expect(_played == [&"expected_b"]
		and _narrative.has_entry(&"recall_set_square_sound"),
		"%s: the imagined lesson played %s or left no recollection." % [Harness.stage, str(_played)])


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


## N's last lines release the class: the free period is announced and the door opens.
func _lesson_ends() -> bool:
	if not await _finish():
		return false
	_checks.expect(_flag(StoryFlags.CLASS_DISMISSED) and not _flag(StoryFlags.B_ON_STAGE)
		and _room.find_interactable(&"classroom_door").is_open()
		and String(_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.free_period",
		"%s: the lesson did not release the class." % Harness.stage)
	return true


## Advances whatever is on screen until `done` holds; false (and a failure) on timeout.
func _drain(done: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	return _checks.expect(false, "%s: timed out (played %s)." % [Harness.stage, str(_played)])


func _resolver_for(succeeds: bool, conversation_id: StringName, node_id: StringName, key: String) -> CheckResolver:
	var conversation := _dialogue.get_dialogue_library().get_conversation(conversation_id)
	var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
	var ability := _dialogue.get_abilities().get_value(&"orientation")
	for seed_value: int in range(64):
		var resolver := CheckResolver.new(seed_value)
		if (resolver.dice_total_for(key) + ability >= int(node.check["difficulty"])) == succeeds:
			return resolver
	_checks.fail("Could not find a deterministic seed for %s success=%s." % [key, str(succeeds)])
	return null


func _flag(key: StringName) -> bool:
	return _state.get_flag(key, false) == true


func _entry(id: StringName, source: int) -> void:
	var entry: NarrativeEntry = _narrative.get_entry(id)
	_checks.expect(entry != null and entry.source == source,
		"%s: %s is absent or filed under the wrong source." % [Harness.stage, id])
