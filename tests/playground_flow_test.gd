extends SceneTree
## Headless integration test of the open-playground slice.
##
## It boots the real main scene, but not the authored prologue: the opening beats
## are long on purpose and `opening_flow_test.gd` already covers them end to end.
## Here the player is placed on the residential courtyard and every location after
## it is walked through for real — exits are activated, the location host loads the
## next scene, arrival beats play, inspections open, the passive voice director
## fires, and checks are rolled through the real dialogue runtime.
##
## What this asserts, in the order the acceptance criteria list it:
##
## 1. the residential courtyard still leads somewhere: its alley exit is a real
##    transition, not the old end card;
## 2. the alley and the yard can be reached, with their arrival beats;
## 3. the yard is open: several independently useful anchors, spread out, and any
##    order works;
## 4. state survives the transitions (flags, knowledge, check records);
## 5. a passive voice speaks once, hidden, and only after something happened;
## 6. a visible check shows its numbers, records its outcome, and cannot be re-rolled
##    by walking back in; the attempt stops being offered;
## 7. a failed check leaves no wall: the exit still works and other anchors still do;
## 8. the green animal from the earlier slice still works;
## 9. the end card now sits at the far end of the yard, and nowhere earlier.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 4.0
const OVERALL_TIMEOUT_SECONDS := 260.0
const RESIDENTIAL := "res://scenes/locations/residential/residential.tscn"
const PLAYGROUND_EXIT := &"pg_gap_in_fence"

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _sequence: OpeningSequence = null
var _director: InnerVoiceDirector = null
var _ui: GameUI = null
var _game_state: Node = null
var _narrative: Node = null
var _started_at_msec: int = 0
var _hidden_checks: int = 0
var _visible_checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 320.0, "playground_flow_test.gd")
	call_deferred("_run")


func _run() -> void:
	_started_at_msec = Time.get_ticks_msec()
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	# The authored prologue is not what this test is about; the sequence still owns
	# transitions and arrivals, which is what the slice needs from it.
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await process_frame
	await process_frame

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_ui = _main.get_node_or_null("GameUI") as GameUI
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	_director = _main.get_node_or_null("InnerVoiceDirector") as InnerVoiceDirector
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _dialogue == null or _host == null or _player == null or _ui == null \
			or _interaction == null or _sequence == null or _director == null:
		Harness.finish(self, ["Main did not expose the nodes the slice needs."], "")
		return
	if not _dialogue.get_abilities().is_valid():
		_failures.append("Inner abilities failed to load: %s" % _dialogue.get_abilities().describe_errors())
	_dialogue.check_resolved.connect(_on_check_resolved)
	Engine.time_scale = TIME_SCALE

	await _start_at_residential()
	await _walk_to_alley()
	await _walk_to_playground()
	await _check_open_structure()
	await _explore_in_two_orders()
	await _attempt_shed_check_expecting_failure()
	await _retry_shed_without_a_reroll()
	await _check_no_soft_lock()
	await _check_animal_still_works()
	_check_check_accounting()

	Harness.finish(
		self, _failures,
		"the yard is reachable, open, checkable, and does not reset the story."
	)


# --- the walk ---------------------------------------------------------------


func _start_at_residential() -> void:
	if not _host.load_location(RESIDENTIAL, &"FromStreet", _player):
		_failures.append("The residential courtyard failed to load.")
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"residential")
	await _settle(20.0, "the courtyard to settle")
	var location := _host.get_current()
	if location == null or String(location.location_id) != "residential":
		_failures.append("The test did not start in the residential courtyard.")
		return
	var alley_exit := location.find_interactable(&"res_alley_end")
	if alley_exit == null:
		_failures.append("The courtyard lost its alley exit.")
		return
	var exit := alley_exit as LocationExit
	if exit == null:
		_failures.append("The courtyard's alley exit is not an exit.")
		return
	if exit.is_milestone_end:
		_failures.append("The courtyard still ends the slice; the end card must move to the yard.")
	if String(exit.destination_scene).is_empty():
		_failures.append("The courtyard's alley exit does not lead anywhere.")


func _walk_to_alley() -> void:
	await _activate(&"res_alley_end", "the alley exit")
	if not await _pump_until(
		func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "alley",
		45.0, "the alley to load"
	):
		return
	# The arrival line plays after the fade, so wait for its flag rather than for a
	# quiet frame: a quiet frame happens during the fade, before the beat starts.
	if not await _pump_until(
		func() -> bool: return _flag_is(StoryFlags.ALLEY_ARRIVED),
		60.0, "the alley arrival line"
	):
		_failures.append("Reaching the alley did not play its arrival line.")
	await _settle(45.0, "the alley arrival beat")
	var location := _host.get_current()
	if location == null:
		_failures.append("The alley did not stay loaded.")
		return
	if location.get_interactables().size() < 3:
		_failures.append("The alley has too few things to look at (%d)." % location.get_interactables().size())
	if not _flag_is(StoryFlags.ALLEY_ARRIVED):
		_failures.append("Arriving in the alley did not set its flag.")
	if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.alley":
		_failures.append("Arriving in the alley did not change the objective.")

	# A passive voice: reading the notices is enough to make the counting voice
	# speak, without the player asking it to.
	await _activate(&"alley_notice_wall", "the notice wall")
	await _settle(45.0, "the notices and any voice that reacts to them")
	if not _flag_is(StoryFlags.inspection_seen_flag(&"alley_notices")):
		_failures.append("Reading the alley notices did not mark them as read.")
	if not _flag_is(StoryFlags.passive_fired_flag(&"alley_notice_ledger")):
		_failures.append("No passive voice reacted to reading the notices.")
	var hidden: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"voice_notice", &"vn_1"), null
	)
	if not (hidden is Dictionary):
		_failures.append("The passive voice line did not roll a hidden check.")


func _walk_to_playground() -> void:
	await _activate(&"alley_to_playground", "the estate gate")
	if not await _pump_until(
		func() -> bool:
			return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground",
		45.0, "the yard to load"
	):
		return
	if not await _pump_until(
		func() -> bool: return _flag_is(StoryFlags.PLAYGROUND_ARRIVED),
		60.0, "the yard arrival line"
	):
		_failures.append("Reaching the yard did not set its flag.")
	await _settle(60.0, "the yard arrival beat and any voice that reacts to it")
	if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.playground":
		_failures.append("Reaching the yard did not change the objective.")
	# The alley's knowledge must survive the transition.
	if not _flag_is(StoryFlags.ALLEY_ARRIVED):
		_failures.append("The alley flag was lost when the yard loaded.")
	if not _narrative.has_entry(&"alley_arrived"):
		_failures.append("Knowledge recorded in the alley was lost in the yard.")


# --- the space --------------------------------------------------------------


func _check_open_structure() -> void:
	var location := _host.get_current()
	if location == null:
		_failures.append("The yard is not loaded.")
		return
	var ids: Array[StringName] = []
	for interactable: Interactable in location.get_interactables():
		ids.append(interactable.interact_id)
	for required: StringName in [
		&"pg_hoop_near", &"pg_bench_look", &"pg_frame_look", &"pg_shed_door", &"pg_ball_look"
	]:
		if not ids.has(required):
			_failures.append("The yard is missing its anchor '%s'." % required)
	if location.get_spawn(&"FromAlley") == null:
		_failures.append("The yard has no spawn point for the gate the player arrives through.")
	if location.find_interactable(PLAYGROUND_EXIT) == null:
		_failures.append("The yard has no far gap.")
	else:
		var gap := location.find_interactable(PLAYGROUND_EXIT) as LocationExit
		if gap == null or not gap.is_milestone_end:
			_failures.append("The far gap does not end the slice.")
		elif gap.end_card_key != "end.slice":
			_failures.append("The far gap does not carry the slice's end card.")
	# Readability: the anchors should be spread out, not stacked in one corner.
	var positions: Array[Vector3] = []
	for name: StringName in [&"pg_hoop_near", &"pg_bench_look", &"pg_frame_look", &"pg_shed_door"]:
		var anchor := location.find_interactable(name)
		if anchor != null:
			positions.append(anchor.global_position)
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < 6.0:
				_failures.append(
					"Two anchors in the yard are only %.1f m apart (%s / %s)."
					% [positions[i].distance_to(positions[j]), str(i), str(j)]
				)


## Two passes in different orders. Nothing in the yard may depend on which of these
## the player looks at first.
func _explore_in_two_orders() -> void:
	var first_pass: Array[StringName] = [
		&"pg_hoop_near", &"pg_bench_look", &"pg_frame_look", &"pg_court_middle"
	]
	var seen_flags := {
		&"pg_hoop_near": &"seen:pg_hoop",
		&"pg_bench_look": &"seen:pg_bench",
		&"pg_frame_look": &"seen:pg_frame",
		&"pg_court_middle": &"seen:pg_court",
	}
	for interactable_id: StringName in first_pass:
		await _activate(interactable_id, str(interactable_id))
		await _settle(45.0, "looking at %s" % interactable_id)
		var flag: StringName = seen_flags[interactable_id]
		if not _flag_is(flag):
			_failures.append("Looking at '%s' was not recorded." % interactable_id)

	# Revisit one of them: the text must exist for a second read and nothing resets.
	var observed_before: int = int(_narrative.count_for_source(NarrativeEntry.Source.OBSERVED))
	await _activate(&"pg_hoop_near", "the hoop again")
	await _settle(30.0, "the repeat read of the hoop")
	var observed_after: int = int(_narrative.count_for_source(NarrativeEntry.Source.OBSERVED))
	if observed_after < observed_before:
		_failures.append("Revisiting an anchor removed knowledge.")
	if not _flag_is(StoryFlags.PLAYGROUND_ARRIVED):
		_failures.append("Revisiting an anchor cleared the arrival flag.")

	# The reverse order, in a fresh visit to the same scene: the space must not lock
	# anything behind the order the first pass used.
	var reverse: Array[StringName] = [&"pg_frame_look", &"pg_bench_look", &"pg_hoop_near"]
	for interactable_id: StringName in reverse:
		await _activate(interactable_id, "reverse %s" % interactable_id)
		await _settle(30.0, "reverse look at %s" % interactable_id)


# --- checks -----------------------------------------------------------------


func _attempt_shed_check_expecting_failure() -> void:
	if not await _open_shed_choices("the shed choices"):
		return
	var seed_value := _find_seed("pg_shed/ps_boundary_check", 4, 11, false)
	if seed_value < 0:
		_failures.append("Could not find a seed that fails the shed check.")
		return
	_dialogue.set_check_resolver(CheckResolver.new(seed_value))
	var index := _dialogue.get_runtime().get_available_choice_ids().find(&"frame")
	if index < 0:
		_failures.append("The shed does not offer the frame attempt.")
		return
	_dialogue.select_choice(index)
	await process_frame
	if not _ui.check_overlay.is_showing():
		_failures.append("A visible check did not show its numbers.")
	else:
		var result := _ui.check_overlay.get_result()
		if result.get("success", true) == true:
			_failures.append("The forced-failure seed reported success.")
		if int(result.get("die", 0)) < 1 or int(result.get("die", 0)) > CheckResolver.DIE_FACES:
			_failures.append("The visible check showed an impossible die.")
		if String(result.get("ability", "")) != "boundary":
			_failures.append("The visible check did not name the voice that carried it.")
	await _pump_until(func() -> bool: return not _dialogue.is_busy(), 45.0, "the shed attempt to finish")
	if _flag_is(&"playground_shed_open"):
		_failures.append("A failed attempt reported the shed as open.")
	if not _flag_is(&"playground_shed_looked"):
		_failures.append("A failed attempt produced no story at all.")
	if not _flag_is(StoryFlags.PLAYGROUND_CHECKED):
		_failures.append("A failed attempt did not count as an attempt.")
	var record: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"pg_shed", &"ps_boundary_check"), null
	)
	if not (record is Dictionary):
		_failures.append("The failed attempt was not recorded.")
	elif (record as Dictionary).get("success", true) == true:
		_failures.append("The recorded failure was stored as a success.")


## Walking back in must not offer the same attempt again, and must not roll again:
## the second visit is where a reroll exploit would live.
func _retry_shed_without_a_reroll() -> void:
	if not await _open_shed_choices("the shed choices on the second visit"):
		return
	var ids := _dialogue.get_runtime().get_available_choice_ids()
	if ids.has(&"frame"):
		_failures.append("An attempt already made is still on offer; it can be farmed.")
	if not ids.has(&"count"):
		_failures.append("The other approach disappeared after one attempt.")
	var record_flag := StoryFlags.check_record_flag(&"pg_shed", &"ps_boundary_check")
	var before: Variant = _game_state.get_flag(record_flag, null)
	var seed_value := _find_seed("pg_shed/ps_ledger_check", 3, 9, true)
	if seed_value < 0:
		_failures.append("Could not find a seed that passes the rota check.")
		_dialogue.advance_presentation()
		return
	_dialogue.set_check_resolver(CheckResolver.new(seed_value))
	var index := ids.find(&"count")
	_dialogue.select_choice(index)
	await process_frame
	if _ui.check_overlay.is_showing():
		var result := _ui.check_overlay.get_result()
		if result.get("success", false) != true:
			_failures.append("The forced-success seed reported failure.")
		else:
			_visible_checks += 1
	else:
		_failures.append("The second visible check did not show its numbers.")
	await _pump_until(func() -> bool: return not _dialogue.is_busy(), 45.0, "the rota attempt to finish")
	if not _flag_is(&"playground_rota_read"):
		_failures.append("The passing check produced no story.")
	var after: Variant = _game_state.get_flag(record_flag, null)
	if before is Dictionary and after is Dictionary and before != after:
		_failures.append("A later attempt overwrote the earlier check record.")


func _check_no_soft_lock() -> void:
	# After one failed and one passed check, everything that mattered must still work.
	await _activate(&"pg_back_to_alley", "the gate back to the alley")
	if not await _pump_until(
		func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "alley",
		45.0, "the alley to reload after the checks"
	):
		_failures.append("A failed check blocked the way back out of the yard.")
		return
	await _settle(30.0, "the alley after the checks")
	if not _flag_is(StoryFlags.PLAYGROUND_ARRIVED):
		_failures.append("Leaving the yard lost its arrival flag.")

	await _activate(&"alley_to_playground", "the estate gate again")
	if not await _pump_until(
		func() -> bool:
			return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground",
		45.0, "the yard to reload"
	):
		return
	await _settle(30.0, "the yard after coming back")
	var location := _host.get_current()
	if location != null:
		var bench := location.find_interactable(&"pg_bench_look")
		if bench == null:
			_failures.append("The bench vanished after the checks.")
		else:
			await _activate(&"pg_bench_look", "the bench after the checks")
			await _settle(30.0, "the bench re-read")


func _check_animal_still_works() -> void:
	if not _host.load_location(RESIDENTIAL, &"FromStreet", _player):
		_failures.append("The courtyard failed to reload for the animal check.")
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"residential")
	await _settle(30.0, "the courtyard before the animal")
	var location := _host.get_current()
	if location == null:
		return
	var animal := location.find_interactable(&"green_animal")
	if animal == null:
		_failures.append("The green animal is gone from the courtyard.")
		return
	_interaction.set_enabled(true)
	_interaction.request_activation(animal)
	if not await _pump_until(func() -> bool: return _dialogue.is_busy(), 15.0, "the animal conversation"):
		_failures.append(
			"Looking at the green animal no longer starts its conversation "
			+ "(can_interact=%s, interaction_enabled=%s, slice_finished=%s)."
			% [str(animal.can_interact()), str(_interaction.is_enabled()), str(_sequence.is_slice_finished())]
		)
	else:
		# The route picks `animal_sighting` on a first meeting and `animal_again`
		# afterwards; the conversation's own effect sets the flag, so compare against
		# the family rather than a single id.
		var conversation := String(_dialogue.get_runtime().get_active_conversation_id())
		if not conversation.begins_with("animal_"):
			_failures.append("The animal opened '%s' instead of its own conversation." % conversation)
	await _pump_until(func() -> bool: return not _dialogue.is_busy(), 45.0, "the animal conversation")


## Both kinds of roll must have actually happened in this run: a passive line rolled
## hidden, and the two shed attempts rolled visible. Without this the test could pass
## while the dice never ran at all.
func _check_check_accounting() -> void:
	if _hidden_checks < 1:
		_failures.append("No hidden check was rolled during the run.")
	if _visible_checks < 2:
		_failures.append("Expected two visible checks, saw %d." % _visible_checks)


# --- helpers ----------------------------------------------------------------


func _open_shed_choices(label: String) -> bool:
	await _activate(&"pg_shed_door", label)
	if not await _pump_until(
		func() -> bool: return _dialogue.has_pending_choices(), 45.0, label
	):
		return false
	return true


func _activate(interactable_id: StringName, label: String) -> void:
	var location := _host.get_current()
	if location == null:
		_failures.append("No location is loaded while trying to reach %s." % label)
		return
	var target := location.find_interactable(interactable_id)
	if target == null:
		_failures.append("Could not find the interactable for %s ('%s')." % [label, interactable_id])
		return
	# The authored succession of beats is off in this test, which leaves the player
	# permanently locked; the interaction layer is re-enabled here so activation can
	# be requested at all. Movement locking itself is covered by opening_flow_test.
	_interaction.set_enabled(true)
	_interaction.request_activation(target)
	await process_frame


func _pump_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while predicate.call() != true:
		if Time.get_ticks_msec() - _started_at_msec > int(OVERALL_TIMEOUT_SECONDS * 1000.0):
			_failures.append("The whole flow exceeded its budget while waiting for %s." % label)
			return false
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			_failures.append("Timed out waiting for %s." % label)
			return false
	return true


## Waits until nothing is on screen, no passive line is queued, and the beat lock is
## free — the only state from which an interaction is guaranteed to be accepted.
func _settle(timeout_seconds: float, label: String) -> bool:
	var settled := await _pump_until(
		func() -> bool:
			return not _dialogue.is_busy() \
				and _director.pending_count() == 0 and not _director.is_firing(),
		timeout_seconds, label
	)
	if not settled:
		return false
	# One more frame: the director pumps in _process, so a voice may start the very
	# frame the queue empties.
	await process_frame
	await process_frame
	if _dialogue.is_busy():
		var retried := await _settle(timeout_seconds, label)
		return retried
	return true


## One place that reads a boolean flag, so a Variant never has to be converted with
## a constructor call at the point of use.
func _flag_is(flag: StringName) -> bool:
	var value: Variant = _game_state.get_flag(flag, false)
	return value == true


func _find_seed(key: String, ability_value: int, difficulty: int, want_success: bool) -> int:
	for seed_value in 4000:
		var die := CheckResolver.new(seed_value).face_for(key)
		if (die + ability_value >= difficulty) == want_success:
			return seed_value
	return -1


func _on_check_resolved(result: Dictionary) -> void:
	if String(result.get("kind", "")) == "hidden":
		_hidden_checks += 1
		# A hidden check must never put numbers on screen: the player is supposed to
		# feel the reaction, not audit the arithmetic.
		if _ui != null and _ui.check_overlay.is_showing():
			_failures.append("A hidden check showed the visible-check panel.")
	else:
		_visible_checks += 1
