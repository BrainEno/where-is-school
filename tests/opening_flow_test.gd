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
##
## Input (issue #62). The classroom is driven through the presentation APIs as before,
## and the walkway gate is opened with a real E key press. From the street to the end
## card the run switches to the controller: every line is continued, every choice
## picked (D-pad + A) and every object used with real joypad events pushed through the
## viewport, the left stick walks the player, and the end card's Start again is
## confirmed with the pad (issue #95). Moving between the authored stops still uses
## `teleport()` as the keyboard half does. The summary line reports how many steps the
## controller performed and how many fell back to an API call (a dialogue that was busy
## with nothing on screen), so a run that quietly stopped using the pad is visible.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 4.0
const OVERALL_TIMEOUT_SECONDS := 320.0
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _ui: GameUI = null
var _game_state: Node = null
var _narrative: Node = null
var _started_at_msec: int = 0
var _saw_subjective := false
var _observed_during_expectation := 0
## From the street on, the controller drives the run.
var _pad_mode := false
var _pad_presses := 0
var _pad_activations := 0
var _api_fallbacks := 0
var _settings: Node = null
var _end_card_reached := false


func _initialize() -> void:
	Harness.arm_watchdog(self, 360.0, "opening_flow_test.gd")
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
	_settings = Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if _settings != null:
		# Defaults for every preference, so a file another check left cannot change the run.
		_settings.call("reset_to_defaults")
		_settings.call("set_input_device", &"keyboard")

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
	_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _dialogue == null or _host == null or _player == null or _ui == null \
			or _interaction == null:
		Harness.finish(self, ["Main did not expose its core nodes."], "")
		return

	_dialogue.subjective_changed.connect(_on_subjective_changed)
	Engine.time_scale = TIME_SCALE

	# --- Beat A/B: wake up and let Q start the conversation ----------------
	if await _pump_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.MET_Q, false)),
		45.0, "Q to start talking"
	):
		# met_q is set by the conversation's first line, so the flags below only
		# exist once the director has handed control back.
		await _settle(90.0, "Q's opening conversation to finish")
		if not bool(_game_state.get_flag(StoryFlags.ASKED_Q_IDENTITY, false)):
			_failures.append("The first choice did not produce its story flag.")
		if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.check_bag":
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
			_interaction.request_activation(door)
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
		_interaction.request_activation(bag)
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
		elif _entry_source(&"recall_set_square_sound") != NarrativeEntry.Source.RECALLED:
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
		await _settle(90.0, "the substitute's conversation to finish")
		if not _narrative.has_entry(&"n_covers_for_b"):
			_failures.append("N's account of covering the lesson was not recorded.")
		elif _entry_source(&"n_covers_for_b") != NarrativeEntry.Source.REPORTED:
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
		_interaction.request_activation(door_after)
		if await _pump_until(
			func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "corridor",
			45.0, "the walkway to load"
		):
			if not bool(_game_state.get_flag(StoryFlags.LEFT_CLASSROOM, false)):
				_failures.append("Leaving the classroom did not set its flag.")

	var corridor := _host.get_current()
	if corridor == null or String(corridor.location_id) != "corridor":
		_failures.append("The player did not end up in the walkway.")
	else:
		if corridor.get_interactables().size() < 4:
			_failures.append("The walkway has too few interactables.")
		var gate := corridor.find_interactable(&"school_gate")
		if gate == null:
			_failures.append("The walkway has no exit towards the street.")
		else:
			await _settle(30.0, "the walkway to settle")
			# Stand on the near side of the gate and face it, so the prompt has to be
			# the gate's and not whatever else is inside the interaction radius.
			_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(0.0, 0, 5.0)))
			await physics_frame
			await physics_frame
			await _check_prompt(&"school_gate", "gate prompt")
			# The keyboard's own path: a real E press, not the activation API.
			await _press_key_e(gate)
			if await _pump_until(
				func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "street",
				60.0, "the street to load"
			):
				if not bool(_game_state.get_flag(StoryFlags.LEFT_SCHOOL, false)):
					_failures.append("Walking out of the school did not set its flag.")
				if not await _settle(60.0, "the street arrival line"):
					_failures.append("The street arrival line did not finish.")
				elif not bool(_game_state.get_flag(StoryFlags.STREET_ARRIVED, false)):
					_failures.append("Reaching the street did not play its arrival line.")

	# --- From here on the controller drives the run --------------------------
	_pad_mode = true
	await _check_stick_walk()

	# --- Beat H: an object on the street, read once and then again ---------
	var street := _host.get_current()
	if street == null or String(street.location_id) != "street":
		_failures.append("The street did not stay loaded.")
	else:
		if street.get_interactables().size() < 6:
			_failures.append("The street has too few things to look at.")
		var gutter := street.find_interactable(&"street_gutter")
		if gutter == null:
			_failures.append("The street has no gutter to look at.")
		else:
			_player.teleport(Transform3D(Basis(Vector3.UP, 0.0), Vector3(-8.9, 0, -21.4)))
			await physics_frame
			await physics_frame
			await _check_prompt(&"street_gutter", "gutter prompt")
			await _activate(gutter)
			await process_frame
			var first_text := ""
			if not _dialogue.is_busy():
				_failures.append("Looking at the gutter showed nothing.")
			else:
				first_text = String(_dialogue.get_current_line().get("text", ""))
				if first_text.is_empty():
					_failures.append("The gutter description was empty.")
			await _settle(30.0, "the gutter description")
			if not _narrative.has_entry(&"saw_street_gutter"):
				_failures.append("Looking at the gutter recorded no knowledge entry.")
			if not bool(_game_state.get_flag(StoryFlags.inspection_seen_flag(&"street_gutter"), false)):
				_failures.append("Looking at the gutter did not mark it as seen.")
			await _activate(gutter)
			await process_frame
			if _dialogue.is_busy():
				var repeat_text := String(_dialogue.get_current_line().get("text", ""))
				if repeat_text == first_text:
					_failures.append("Reading the gutter twice showed the same long text again.")
			else:
				_failures.append("Looking at the gutter a second time showed nothing.")
			await _settle(30.0, "the second gutter description")

	# --- Beat I: the residential area and the green animal ----------------
	if street != null:
		var to_residential := street.find_interactable(&"street_to_residential")
		if to_residential == null:
			_failures.append("The street has no way on to the residential area.")
		else:
			_player.teleport(Transform3D(Basis(Vector3.UP, 0.0), Vector3(10.5, 1.6, -35.0)))
			await physics_frame
			await physics_frame
			await _activate(to_residential)
			if await _pump_until(
				func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "residential",
				60.0, "the residential area to load"
			):
				await _settle(60.0, "the residential arrival line")
				if not bool(_game_state.get_flag(StoryFlags.RESIDENTIAL_ARRIVED, false)):
					_failures.append("Reaching the flats did not play its arrival line.")

	var flats := _host.get_current()
	if flats == null or String(flats.location_id) != "residential":
		_failures.append("The residential area did not stay loaded.")
	else:
		var animal := flats.find_interactable(&"green_animal")
		if animal == null:
			_failures.append("The green animal is missing from the courtyard.")
		else:
			_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(-10.0)), Vector3(7.3, 0, 0.1)))
			await physics_frame
			await physics_frame
			await _check_prompt(&"green_animal", "animal prompt")
			await _activate(animal)
			await process_frame
			if not _dialogue.is_busy():
				_failures.append("Looking at the green animal started nothing.")
			else:
				# E during a conversation must not start a second one.
				var conversation_line := String(_dialogue.get_current_line().get("node_id", ""))
				_interaction.request_activation(animal)
				await process_frame
				if String(_dialogue.get_current_line().get("node_id", "")) != conversation_line:
					_failures.append("A key press during a conversation started another one.")
			await _settle(90.0, "the first animal conversation")
			if not bool(_game_state.get_flag(StoryFlags.ANIMAL_SEEN, false)):
				_failures.append("Meeting the animal did not set its flag.")
			if not _narrative.has_entry(&"animal_seen"):
				_failures.append("Meeting the animal recorded no knowledge entry.")
			await _activate(animal)
			await process_frame
			if _dialogue.is_busy():
				if String(_dialogue.get_current_line().get("node_id", "")) != "aa_1":
					_failures.append("Meeting the animal a second time did not use the shorter conversation.")
			else:
				_failures.append("Meeting the animal a second time showed nothing.")
			await _settle(60.0, "the second animal conversation")

		# --- Beat J: the alley and the open yard, to the real end of the slice ---
		# The courtyard's alley exit used to end the slice. It now leads on: alley,
		# estate gate, open yard, and only the gap in the far fence ends it.
		var alley_exit := flats.find_interactable(&"res_alley_end")
		if alley_exit == null:
			_failures.append("The residential area has no way into the alley.")
		else:
			var exit_node := alley_exit as LocationExit
			if exit_node != null and exit_node.is_milestone_end:
				_failures.append("The courtyard still ends the slice at its alley exit.")
			_player.teleport(Transform3D(Basis(Vector3.UP, 0.0), Vector3(6.0, 0, -33.0)))
			await physics_frame
			await physics_frame
			await _activate(alley_exit)
			if await _pump_until(
				func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "alley",
				60.0, "the alley to load"
			):
				await _settle(60.0, "the alley arrival line")
				if not bool(_game_state.get_flag(StoryFlags.ALLEY_ARRIVED, false)):
					_failures.append("Reaching the alley did not play its arrival line.")
				if _ui.end_card.visible:
					_failures.append("The end card appeared in the alley; it belongs at the far fence.")

				var alley := _host.get_current()
				if alley != null:
					var gate := alley.find_interactable(&"alley_to_playground")
					if gate == null:
						_failures.append("The alley has no way on to the yard.")
					else:
						_player.teleport(
							Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(0.0, 0, -20.4))
						)
						await physics_frame
						await physics_frame
						await _activate(gate)
						if await _pump_until(
							func() -> bool:
								return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground",
							60.0, "the yard to load"
						):
							await _settle(60.0, "the yard arrival line")
							if not bool(_game_state.get_flag(StoryFlags.PLAYGROUND_ARRIVED, false)):
								_failures.append("Reaching the yard did not play its arrival line.")
							if _ui.end_card.visible:
								_failures.append("The end card appeared on entering the yard.")
							var yard := _host.get_current()
							if yard != null:
								var ids: Array[StringName] = []
								for interactable: Interactable in yard.get_interactables():
									ids.append(interactable.interact_id)
								for required: StringName in [
									&"pg_hoop_near", &"pg_bench_look", &"pg_frame_look",
									&"pg_shed_door", &"pg_ball_look",
								]:
									if not ids.has(required):
										_failures.append("The yard is missing its anchor '%s'." % required)
								var gap := yard.find_interactable(&"pg_gap_in_fence")
								if gap == null:
									_failures.append("The yard has no far gap to end the slice at.")
								else:
									_player.teleport(
										Transform3D(Basis(Vector3.UP, 0.0), Vector3(-14.0, 0, -16.8))
									)
									await physics_frame
									await physics_frame
									await _activate(gap)
									if await _pump_until(
										func() -> bool: return _ui.end_card.visible,
										30.0, "the end-of-slice card"
									):
										var card_title := _ui.end_card.get_title()
										if card_title.strip_edges().is_empty():
											_failures.append("The end-of-slice card has no title.")
										elif card_title != L10n.t("end.slice.title"):
											_failures.append(
												"The end-of-slice card is not using its locale key."
											)
										_end_card_reached = true

	_dump_state()
	# Last, because it frees the world every reference above points into.
	Engine.time_scale = 1.0
	if _end_card_reached:
		await _check_end_card_restart()
	if is_instance_valid(_main):
		_main.queue_free()
	if current_scene != null:
		var sequence := current_scene.get_node_or_null("OpeningSequence")
		if sequence != null:
			sequence.set("autosave_enabled", false)
		current_scene.queue_free()
	await process_frame
	await process_frame
	Harness.clear_session_state(self)
	print(
		"INPUT pad_presses=%d pad_activations=%d api_fallbacks=%d"
		% [_pad_presses, _pad_activations, _api_fallbacks]
	)
	Harness.finish(
		self, _failures,
		"the slice runs from waking up through the yard to the milestone card at its far fence, "
		+ "the second half on the controller (%d presses, %d uses), and Start again on the "
		% [_pad_presses, _pad_activations]
		+ "card boots a new game with nothing of the old run left."
	)


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


## Waits until no presentation is on screen and the player has control again.
func _settle(timeout_seconds: float, label: String) -> bool:
	return await _pump_until(
		func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		timeout_seconds, label
	)


## Source category of a knowledge entry, or -1 when it was never recorded.
func _entry_source(entry_id: StringName) -> int:
	if _narrative == null or not _narrative.has_entry(entry_id):
		return -1
	return int(_narrative.get_entry(entry_id).source)


func _advance_presentation() -> void:
	var panel := _ui.dialogue_panel
	if _pad_mode and panel.visible and not _ui.backlog.is_open():
		# The controller's path: A continues; a choice is marked with the D-pad (the
		# first option, as the API path picks) and taken with A.
		if panel.has_choices() and panel.get_choice_cursor() < 0:
			_push_pad(JOY_BUTTON_DPAD_DOWN)
		_push_pad(JOY_BUTTON_A)
		return
	if _pad_mode:
		_api_fallbacks += 1
	if _dialogue.has_pending_choices():
		_dialogue.select_choice(0)
	else:
		_dialogue.advance_presentation()


## One real controller button, down and up, through the viewport.
func _push_pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		root.push_input(event)
	_pad_presses += 1


## The keyboard's interact key, for real: E down and up through the viewport.
func _press_key_e(target: Interactable) -> void:
	await _wait_for_target(target)
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.keycode = KEY_E
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _wait_for_target(target: Interactable) -> bool:
	for _index in 30:
		if _interaction.get_current_target() == target:
			return true
		await physics_frame
	return _interaction.get_current_target() == target


## Uses an object the way a controller does: it has to be the target, then A.
func _activate(target: Interactable) -> void:
	if not _pad_mode:
		_interaction.request_activation(target)
		return
	if await _wait_for_target(target):
		_push_pad(JOY_BUTTON_A)
		_pad_activations += 1
		await process_frame
		return
	_failures.append(
		"With a controller, '%s' was not the target where the run stands, so A could not use it (%s)."
		% [target.interact_id, _diagnose_interaction(target.interact_id)]
	)
	_interaction.request_activation(target)


## The left stick walks the player: the click-to-walk alternative for a controller.
func _check_stick_walk() -> void:
	await _settle(30.0, "control before the stick walk")
	var moved := 0.0
	# Forward first; if the spawn faces a wall, back the other way.
	for direction: float in [-1.0, 1.0]:
		moved = await _stick_push(JOY_AXIS_LEFT_Y, direction)
		if moved >= 0.3:
			break
	if moved < 0.3:
		_failures.append("The left stick moved the player %.2f m in 20 physics frames." % moved)
	if _settings != null and not bool(_settings.call("is_using_gamepad")):
		_failures.append("Using the stick did not switch the prompts to the controller.")


## Holds the stick for 20 physics frames and lets go; returns how far the player went.
func _stick_push(axis: JoyAxis, value: float) -> float:
	var before := _player.global_position
	await _stick(axis, value)
	for _index in 20:
		await physics_frame
	var moved := _player.global_position.distance_to(before)
	await _stick(axis, 0.0)
	for _index in 4:
		await physics_frame
	return moved


## The action state (what the player polls) and the event (what the menus and the
## device detection hear) both see the stick.
func _stick(axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = 0
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	root.push_input(motion)


## Start again from the end card, with the pad: cancel first (nothing changes), then
## confirm, and the game that boots has nothing of this run.
func _check_end_card_restart() -> void:
	var card := _ui.end_card
	var save := root.get_node_or_null(^"Save")
	var session := root.get_node_or_null(^"Session")
	for _index in 10:
		await process_frame
	if not card.has_actions():
		_failures.append("The end-of-slice card offers no way to start again.")
		return
	if root.gui_get_focus_owner() != card.get_restart_button():
		_failures.append("Start again does not have the focus on the end card.")
		card.get_restart_button().grab_focus()
	if save == null or not save.has_save():
		_failures.append("The end of the slice left no save to start again from.")
	_push_pad(JOY_BUTTON_A)
	await process_frame
	await process_frame
	if not card.get_confirm().visible:
		_failures.append("Start again did not ask before deleting the save.")
		return
	_push_pad(JOY_BUTTON_B)
	await process_frame
	await process_frame
	if card.get_confirm().visible:
		_failures.append("B did not cancel the start-again question.")
	if save != null and not save.has_save():
		_failures.append("Cancelling Start again deleted the save.")
	if not bool(_game_state.get_flag(StoryFlags.ANIMAL_SEEN, false)):
		_failures.append("Cancelling Start again cleared the story.")
	_push_pad(JOY_BUTTON_A)
	await process_frame
	await process_frame
	_push_pad(JOY_BUTTON_DPAD_RIGHT)
	await process_frame
	if root.gui_get_focus_owner() != card.get_confirm().get_confirm_button():
		_failures.append("The D-pad did not reach the confirm answer.")
		card.get_confirm().get_confirm_button().grab_focus()
	var reports: Array = []
	var on_started := func(report: Dictionary) -> void: reports.append(report)
	if session != null:
		session.connect("new_game_started", on_started)
	_push_pad(JOY_BUTTON_A)
	for _index in 240:
		await process_frame
		if not reports.is_empty() and current_scene != null \
				and current_scene.get_node_or_null("OpeningSequence") != null:
			break
	if session != null:
		session.disconnect("new_game_started", on_started)
	await process_frame
	await process_frame
	if reports.is_empty():
		_failures.append("Confirming Start again did not start a new game.")
		return
	var report: Dictionary = reports[0]
	if not bool(report.get("ok", false)):
		_failures.append("Start again left state behind: %s" % str(report))
	if is_instance_valid(_main):
		_failures.append("Start again did not free the finished world.")
	var fresh := current_scene
	if fresh == null or fresh.get_node_or_null("OpeningSequence") == null:
		_failures.append("Start again did not boot the opening.")
		return
	for flag: StringName in [
		StoryFlags.MET_Q, StoryFlags.LEFT_SCHOOL, StoryFlags.ANIMAL_SEEN,
		StoryFlags.PLAYGROUND_ARRIVED,
	]:
		if bool(_game_state.get_flag(flag, false)):
			_failures.append("Start again kept the story flag '%s'." % flag)
	if _narrative.has_entry(&"animal_seen"):
		_failures.append("Start again kept the knowledge of the animal.")
	var location := String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "classroom"))
	if location != "classroom":
		_failures.append("Start again booted in '%s', not the classroom." % location)
	var sequence := fresh.get_node_or_null("OpeningSequence") as OpeningSequence
	if sequence != null and sequence.next_step() != &"wake":
		_failures.append("Start again did not begin at the wake ('%s')." % sequence.next_step())


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
	if _interaction == null:
		_failures.append("The player has no InteractionController to test.")
		return
	for test_case: Dictionary in cases:
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(test_case["yaw"])),
			test_case["position"]))
		await physics_frame
		await physics_frame
		var target := _interaction.get_current_target()
		var found := String(target.interact_id) if target != null else "<nothing>"
		if target == null or target.interact_id != test_case["expected"]:
			_failures.append(
				"At %s the interaction prompt targeted '%s' instead of '%s'."
				% [test_case["position"], found, test_case["expected"]]
			)


## Compact state line printed once at the end of a run (and used by CI to
## summarise a failure without the full log).
## The prompt the HUD is showing must describe the object the player faces, in the
## current language, and it must come from data rather than from a literal.
func _check_prompt(interact_id: StringName, label: String) -> void:
	# The prompt follows the target found during a physics frame, so give it a
	# couple of seconds instead of assuming it is on screen immediately.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 3000 and _ui.hud.get_prompt_text().strip_edges().is_empty():
		await process_frame
	var scans_before := _interaction.get_scan_count()
	await process_frame
	await process_frame
	var text := _ui.hud.get_prompt_text()
	if text.strip_edges().is_empty():
		_failures.append(
			"No interaction prompt was shown for %s (%s)."
			% [label, _diagnose_interaction(interact_id, scans_before)]
		)
		return
	# The keyboard's prompt names E; the controller's names A.
	var key_label := "A]" if _pad_mode else "E]"
	if not text.contains(key_label):
		_failures.append("The %s prompt does not name the interact key: '%s'." % [label, text])
	var target := _interaction.get_current_target()
	if target == null or target.interact_id != interact_id:
		_failures.append(
			"The %s prompt is showing for '%s' instead of '%s' (%s)."
			% [
				label, "<nothing>" if target == null else target.interact_id, interact_id,
				_diagnose_interaction(interact_id, scans_before),
			]
		)


## Why an interaction prompt is missing: what the controller holds, what the sensor
## overlaps, and where the player is standing.
func _diagnose_interaction(expected: StringName, scans_before: int = -1) -> String:
	var parts := PackedStringArray()
	var target := _interaction.get_current_target()
	parts.append("target=%s" % ("<none>" if target == null else String(target.interact_id)))
	parts.append("expected_in_scene=%s" % str(_host.get_current() != null
		and _host.get_current().find_interactable(expected) != null))
	parts.append("position=%s" % str(_player.global_position))
	parts.append("scans=%d->%d" % [scans_before, _interaction.get_scan_count()])
	parts.append("facing=%s" % str(_player.get_facing_direction()))
	parts.append("control=%s" % str(_player.is_control_enabled()))
	parts.append("busy=%s" % str(_dialogue.is_busy()))
	var expected_node: Interactable = null
	if _host.get_current() != null:
		expected_node = _host.get_current().find_interactable(expected)
	if expected_node != null:
		var offset := expected_node.global_position - _player.global_position
		parts.append("expected_distance=%.2f" % offset.length())
		parts.append("expected_can_interact=%s" % str(expected_node.can_interact()))
		parts.append("expected_los=%s" % str(_interaction._has_line_of_sight(expected_node)))
	var fresh: Interactable = _interaction._find_best_target()
	parts.append("fresh_pick=%s" % ("<none>" if fresh == null else String(fresh.interact_id)))
	parts.append("controller_player=%s" % str(_interaction._player.name if _interaction._player != null else "<null>"))
	parts.append("max_distance=%.2f facing_weight=%.2f" % [
		_interaction.max_distance, _interaction.facing_weight
	])
	var facing := _player.get_facing_direction()
	facing.y = 0.0
	facing = facing.normalized()
	for child in _player.get_children():
		var sensor := child as Area3D
		if sensor == null or not sensor.name.ends_with("InteractionSensor"):
			continue
		var ids := PackedStringArray()
		for area: Area3D in sensor.get_overlapping_areas():
			var interactable := area as Interactable
			if interactable == null:
				ids.append("<freed>")
				continue
			var offset := interactable.global_position - _player.global_position
			offset.y = 0.0
			var distance := offset.length()
			var alignment := facing.dot(offset.normalized()) if distance > 0.001 else 0.0
			var score := distance + _interaction.facing_weight * (1.0 - maxf(alignment, 0.0))
			ids.append("%s d=%.2f a=%.2f s=%.2f los=%s" % [
				interactable.interact_id, distance, alignment, score,
				str(_interaction._has_line_of_sight(interactable)),
			])
		parts.append("candidates=[%s]" % "; ".join(ids))
	return " ".join(parts)


func _dump_state() -> void:
	var raised: Array[String] = []
	for flag: StringName in [
		StoryFlags.MET_Q, StoryFlags.ASKED_Q_IDENTITY, StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG, StoryFlags.N_ARRIVED,
		StoryFlags.CLASS_DISMISSED, StoryFlags.LEFT_CLASSROOM, StoryFlags.LEFT_SCHOOL,
		StoryFlags.STREET_ARRIVED, StoryFlags.RESIDENTIAL_ARRIVED, StoryFlags.ANIMAL_SEEN,
	]:
		if bool(_game_state.get_flag(flag, false)):
			raised.append(String(flag))
	var control := "n/a"
	if _player != null:
		control = str(_player.is_control_enabled())
	print(
		"DIAG busy=%s control=%s mode=%d location=%s flags=%s failures=%d"
		% [
			_dialogue.is_busy(),
			control,
			_dialogue.get_mode(),
			String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "<none>")),
			",".join(raised),
			_failures.size(),
		]
	)
