extends SceneTree
## Headless integration test of the whole biology-class slice.
##
## It boots the real main scene with the authored beats enabled and drives the
## presentation APIs the UI itself calls: advance lines, pick choices, activate
## interactables. Every assertion below corresponds to an acceptance criterion
## (wake, Q, missing textbook, inspections, expectation vs. world state, bell,
## substitute, exit, milestone end).
##
## Time is scaled up so the fade and bell pacing do not dominate CI runtime.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 4.0
const OVERALL_TIMEOUT_SECONDS := 240.0

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _ui: GameUI = null
var _game_state: Node = null
var _narrative: Node = null
var _started_at_msec: int = 0
var _saw_subjective := false
var _observed_during_expectation := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "opening_flow_test.gd")
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
	root.add_child(_main)
	await process_frame
	await process_frame

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_ui = _main.get_node_or_null("GameUI") as GameUI
	if _dialogue == null or _host == null or _player == null or _ui == null:
		Harness.finish(self, ["Main did not expose its core nodes."], "")
		return

	_dialogue.subjective_changed.connect(_on_subjective_changed)
	Engine.time_scale = TIME_SCALE

	# --- Beat A/B: wake up and let Q start the conversation ----------------
	if await _pump_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.MET_Q, false)),
		45.0, "Q to start talking"
	):
		if not bool(_game_state.get_flag(StoryFlags.ASKED_Q_IDENTITY, false)):
			_failures.append("The first choice did not produce its story flag.")
		if String(_game_state.get_flag(StoryFlags.OBJECTIVE_TEXT, "")) != \
				"Find your biology textbook. Check your bag.":
			_failures.append("The bag objective was not set after Q's conversation.")
		if not _player.is_control_enabled():
			_failures.append("Control did not return after the opening lines.")

	# --- Interaction targeting: every authored prompt must be reachable ----
	await _check_targeting()

	# --- Beat F (early): the door must stay shut during the lesson ---------
	var classroom := _host.get_current()
	if classroom != null:
		var door := classroom.find_interactable(&"classroom_door")
		if door == null:
			_failures.append("The classroom door interactable is missing.")
		else:
			if door.is_open():
				_failures.append("The classroom door is open before the class is dismissed.")
			door.activate()
			await process_frame
			if not _dialogue.is_busy():
				_failures.append("Trying the locked door did not show its blocked text.")
			await _pump_until(func() -> bool: return not _dialogue.is_busy(), 20.0, "door text")
			if String(_host.get_current().location_id) != "classroom":
				_failures.append("The locked door moved the player out of the classroom.")

	# --- Beat C: search the schoolbag -------------------------------------
	classroom = _host.get_current()
	var bag: Interactable = null
	if classroom != null:
		bag = classroom.find_interactable(&"schoolbag")
	if bag == null:
		_failures.append("The schoolbag interactable is missing.")
	else:
		bag.activate()
		await process_frame
		await _pump_until(
			func() -> bool: return bool(_game_state.get_flag(StoryFlags.TEXTBOOK_MISSING, false)),
			20.0, "the missing textbook flag"
		)
		if not _narrative.has_entry(&"bag_missing_textbook"):
			_failures.append("Searching the bag recorded no observed knowledge entry.")
		elif _narrative.get_entry(&"bag_missing_textbook").source != NarrativeEntry.Source.OBSERVED:
			_failures.append("The bag discovery was not recorded as observed.")

	# --- Beat E: expectation beat must stay subjective ---------------------
	_observed_during_expectation = _narrative.count_for_source(NarrativeEntry.Source.OBSERVED)
	if await _pump_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.EXPECTATION_PLAYED, false)),
		60.0, "the expectation beat"
	):
		if not _saw_subjective:
			_failures.append("The expectation beat never presented itself as subjective.")
		if _narrative.count_for_source(NarrativeEntry.Source.OBSERVED) != \
				_observed_during_expectation:
			_failures.append("The imagined beat added observed knowledge.")
		if not _narrative.has_entry(&"recall_set_square_sound"):
			_failures.append("The half-remembered set square entry was not recorded.")
		if _narrative.get_entry(&"recall_set_square_sound").source != \
				NarrativeEntry.Source.RECALLED:
			_failures.append("The half-remembered set square was not stored as a recollection.")
		if _ui.overlay.visible:
			_failures.append("The imagination overlay is still on screen after the beat.")

	# --- Beat F: bell, no B, substitute N takes the lesson ----------------
	await _pump_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.BELL_RUNG, false)),
		60.0, "the second bell"
	)
	if await _pump_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.CLASS_DISMISSED, false)),
		90.0, "the substitute to dismiss the class"
	):
		if not bool(_game_state.get_flag(StoryFlags.N_ARRIVED, false)):
			_failures.append("The class was dismissed before the substitute arrived.")
		var location := _host.get_current()
		if location != null:
			var actor := location.find_actor(&"n")
			if actor == null or not actor.visible:
				_failures.append("The substitute actor is not visible at the front of the room.")
		if not _narrative.has_entry(&"n_covers_for_b"):
			_failures.append("N's account of covering the lesson was not recorded.")
		if _narrative.get_entry(&"n_covers_for_b").source != NarrativeEntry.Source.REPORTED:
			_failures.append("N's statement was not stored as reported, not observed.")

	# --- Beat G: leave the classroom and reach the milestone end ----------
	classroom = _host.get_current()
	var door_after: Interactable = null
	if classroom != null:
		door_after = classroom.find_interactable(&"classroom_door")
	if door_after == null:
		_failures.append("The classroom door disappeared before the exit beat.")
	elif not door_after.is_open():
		_failures.append("The classroom door stayed locked after the class was dismissed.")
	else:
		door_after.activate()
		if await _pump_until(
			func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "corridor",
			45.0, "the walkway to load"
		):
			if not bool(_game_state.get_flag(StoryFlags.LEFT_CLASSROOM, false)):
				_failures.append("Leaving the classroom did not set its flag.")

	var corridor := _host.get_current()
	if corridor != null and String(corridor.location_id) == "corridor":
		if corridor.get_interactables().size() < 4:
			_failures.append("The walkway has too few interactables.")
		var gate := corridor.find_interactable(&"school_gate")
		if gate == null:
			_failures.append("The walkway has no milestone-exit interactable.")
		else:
			gate.activate()
			await _pump_until(
				func() -> bool: return _ui.end_card.visible, 30.0, "the end-of-slice card"
			)
	else:
		_failures.append("The player did not end up in the walkway.")

	Engine.time_scale = 1.0
	_main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "the classroom slice runs from waking up to the walkway exit.")


func _on_subjective_changed(active: bool) -> void:
	if active:
		_saw_subjective = true


# --- Helpers ----------------------------------------------------------------


## Advances whatever presentation is on screen and waits for `predicate`.
func _pump_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while not bool(predicate.call()):
		if Time.get_ticks_msec() - _started_at_msec > int(OVERALL_TIMEOUT_SECONDS * 1000.0):
			_failures.append("The whole flow exceeded its time budget while waiting for %s." % label)
			return false
		if _dialogue.is_busy():
			_advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			_failures.append("Timed out waiting for %s." % label)
			return false
	return true


func _advance_presentation() -> void:
	if _dialogue.has_pending_choices():
		_dialogue.select_choice(0)
	else:
		_dialogue.advance_presentation()


func _check_targeting() -> void:
	var cases := [
		{"position": Vector3(0.55, 0, 1.7), "yaw": 0.0, "expected": &"schoolbag"},
		{"position": Vector3(-0.6, 0, 1.0), "yaw": 0.0, "expected": &"own_desk"},
		{"position": Vector3(-1.32, 0, 1.75), "yaw": 0.0, "expected": &"q_talk"},
		{"position": Vector3(0.2, 0, -2.3), "yaw": 0.0, "expected": &"blackboard"},
		{"position": Vector3(1.35, 0, -2.05), "yaw": 0.0, "expected": &"set_square"},
		{"position": Vector3(-3.5, 0, -0.2), "yaw": 90.0, "expected": &"window"},
		{"position": Vector3(1.6, 0, 2.6), "yaw": 180.0, "expected": &"timetable"},
		{"position": Vector3(3.2, 0, 2.55), "yaw": 180.0, "expected": &"classroom_door"},
	]
	var interaction := _player.get_node_or_null("InteractionController") as InteractionController
	if interaction == null:
		_failures.append("The player has no InteractionController to test.")
		return
	for test_case: Dictionary in cases:
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(test_case["yaw"])),
			test_case["position"]))
		await physics_frame
		await physics_frame
		var target := interaction.get_current_target()
		var found := String(target.interact_id) if target != null else "<nothing>"
		if target == null or target.interact_id != test_case["expected"]:
			_failures.append(
				"At %s the interaction prompt targeted '%s' instead of '%s'."
				% [test_case["position"], found, test_case["expected"]]
			)
