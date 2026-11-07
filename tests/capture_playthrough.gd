extends SceneTree
## Drives the real game in a real window and photographs the flows that matter.
##
## This is not a headless assertion suite: it runs under Xvfb with a real viewport,
## presses real keys through the input system, and saves what the player would see
## to docs/screenshots. Failures are written next to the screenshots (a FAIL_*.png
## of the moment it stopped plus PLAYTHROUGH.log) so a broken build leaves evidence
## instead of a stack trace.
##
## Interaction, dialogue advance, choice selection and the language switch all go
## through simulated key events, exactly as a player would produce them. Walking
## between scenes is shortened with teleports so the capture stays inside the CI
## budget; the movement itself is exercised once, with a held key, and reported in
## the log.

const Harness = preload("res://tests/test_harness.gd")
const SHOT_DIR := "res://docs/screenshots"
const LOG_PATH := "res://docs/screenshots/PLAYTHROUGH.log"

var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _ui: GameUI = null
var _panel: DialoguePanel = null
var _game_state: Node = null
var _narrative: Node = null
var _loc: Node = null

var _log_lines: Array[String] = []
var _failures: Array[String] = []
var _shot_index: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_note("capture started: %s" % Time.get_datetime_string_from_system())

	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	Harness.clear_session_state(self)
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if _loc != null:
		_loc.set_locale("en")

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		await _fail("main.tscn did not load")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_ui = _main.get_node_or_null("GameUI") as GameUI
	if _ui != null:
		_panel = _ui.get_node_or_null("DialoguePanel") as DialoguePanel
	_interaction = _player.get_node_or_null("InteractionController") as InteractionController if _player != null else null
	if _dialogue == null or _host == null or _player == null or _ui == null or _interaction == null:
		await _fail("main scene did not expose its core nodes")
		return
	if root.get_texture() == null or root.get_texture().get_image() == null:
		await _fail("the viewport has no image: this is not a real window")
		return
	_note("viewport: %dx%d, locale=%s" % [
		root.get_texture().get_image().get_width(), root.get_texture().get_image().get_height(),
		L10n.current,
	])

	# 1. The opening line, waiting for the fade instead of guessing at a delay.
	if not await _wait_for_line(60.0):
		await _fail("the opening conversation never showed a line")
		return
	await _wait(0.7)
	await _shot("01_opening_line", "The first line of the opening conversation, in English.")

	# 3. Finish the opening conversation with the keyboard only.
	if not await _drive_until(
		func() -> bool:
			return bool(_game_state.get_flag(StoryFlags.MET_Q, false)) and not _dialogue.is_busy(),
		120.0, "the opening conversation to end"
	):
		await _fail("the opening conversation could not be driven to its end with the keyboard")
		return
	_note("objective after the opening conversation: %s" % _ui.hud.get_objective_key())

	# 2. A held movement key, driven as late as possible: the story beats lock the
	# player, so the walk is measured at the first moment control actually returns.
	if not await _wait_for_free(30.0):
		_failures.append("The player never got control back to walk.")
	else:
		var start_position := _player.global_position
		Input.action_press("move_forward")
		await _wait(0.8)
		Input.action_release("move_forward")
		await _wait(0.2)
		var moved := _player.global_position.distance_to(start_position)
		_note("held move_forward for 0.8 s: player moved %.2f m" % moved)
		if moved < 0.2:
			_failures.append("Holding the forward key did not move the player.")
	await _shot("02_walking", "The player after holding the forward key.")
	await _shot("03_world_after_opening", "The classroom with control returned and the objective set.")

	# 3b. The mouse, with real pointer events: a click on the floor, a click that the
	# keys interrupt, a click on a person, and a click on a prop.
	await _capture_click_navigation()

	# 4. The interaction prompt for the schoolbag, with the key it names.
	await _wait_for_free(60.0)
	_teleport(Vector3(0.55, 0, 1.7), 0.0)
	if not await _wait_for_target(&"schoolbag", 30.0):
		_failures.append("The schoolbag was never offered as an interaction target.")
		await _shot("FAIL_schoolbag_prompt", "No prompt appeared for the schoolbag.")
	await _shot("04_prompt_schoolbag", "The interaction prompt with the key that is bound in the input map.")

	# 5. Press E and photograph the description.
	await _press(KEY_E)
	if not await _wait_for_line(5.0):
		await _fail("pressing E on the schoolbag showed nothing")
		return
	await _wait(0.6)
	await _shot("05_inspection_text", "The schoolbag description, reached by pressing E.")
	await _drive_until(func() -> bool: return not _dialogue.is_busy(), 30.0, "the description to close")

	# 6. Switch the language with L while standing in the world.
	await _press(KEY_L)
	await _wait(0.4)
	_note("locale after pressing L: %s" % L10n.current)
	if L10n.current != "zh-CN":
		_failures.append("Pressing L did not switch the language.")
	await _shot("06_chinese_world", "The same classroom after switching to simplified Chinese at runtime.")
	await _wait_for_free(60.0)
	_teleport(Vector3(0.55, 0, 1.7), 0.0)
	if not await _wait_for_target(&"schoolbag", 30.0):
		_failures.append("The schoolbag was not prompted again after the language switch.")
		await _shot("FAIL_prompt_chinese", "No prompt appeared after the language switch.")
	await _shot("07_prompt_chinese", "The interaction prompt after the switch: the prompt text is translated.")

	# 7. An object read a second time, in Chinese.
	await _press(KEY_E)
	if await _wait_for_line(5.0):
		await _wait(0.6)
		await _shot("08_repeat_read_chinese", "The second read of the same object, in Chinese.")
	await _drive_until(func() -> bool: return not _dialogue.is_busy(), 30.0, "the second read to close")

	# 8. A conversation in Chinese, then back to English.
	var classroom := _host.get_current()
	var q := classroom.find_interactable(&"q_talk") if classroom != null else null
	if q == null:
		_failures.append("Q has no interaction point in the classroom.")
	else:
		await _wait_for_free(60.0)
		_teleport(Vector3(-1.32, 0, 1.75), 0.0)
		if await _wait_for_target(&"q_talk", 30.0):
			await _shot("09_prompt_talk_chinese", "The prompt for a conversation, in Chinese.")
		# The conversation itself is started with the mouse, from out of reach: the
		# character walks over to Q and only then does anything get said. E still works
		# for every object; the prompts photographed elsewhere are its evidence.
		if await _position_near(q, 3.5):
			var q_screen := _screen_position_of(q)
			if _interaction.get_target_at_screen_position(q_screen, false) == q:
				await _click_at_screen(q_screen)
				await _wait(0.35)
				await _shot(
					"09b_click_person_approach",
					"Q clicked from out of reach: the character walks over to them."
				)
				if await _wait_for_line(45.0):
					await _wait(0.6)
					await _shot(
						"10_conversation_chinese",
						"A conversation line in Chinese, started by clicking Q from a distance."
					)
					_note("click-to-talk: the walk and the conversation both came from one click")
				else:
					_failures.append("Clicking Q did not start a conversation on arrival.")
			else:
				_failures.append("Q was not under the cursor for the click-to-talk shot.")
		else:
			_failures.append("Could not stand within sight of Q for the click-to-talk shot.")
		await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the conversation to close")
	await _press(KEY_L)
	await _wait(0.4)
	_note("locale after pressing L again: %s" % L10n.current)
	await _shot("11_back_to_english", "The same scene after switching back to English.")

	# 9. The rest of the story, driven by keys where the player would press them.
	if not await _drive_until(
		func() -> bool: return bool(_game_state.get_flag(StoryFlags.CLASS_DISMISSED, false)) and not _dialogue.is_busy(),
		180.0, "the lesson beats to finish"
	):
		await _fail("the bell and the substitute beats did not finish")
		return

	classroom = _host.get_current()
	var door := classroom.find_interactable(&"classroom_door") if classroom != null else null
	if door == null:
		_failures.append("The classroom door is missing.")
	else:
		_teleport(Vector3(3.2, 0, 2.55), 180.0)
		await _wait_for_target(&"classroom_door", 5.0)
		await _shot("12_door_prompt", "The classroom door is open: its prompt changed with the story.")
		# The transition is made with the mouse if the door is under the cursor; E stays
		# the fallback and the log says which one was used.
		var door_screen := _screen_position_of(door)
		if _interaction.get_target_at_screen_position(door_screen, false) == door:
			await _click_at_screen(door_screen)
			await _wait(0.25)
			await _shot("12b_click_door", "The door clicked with the mouse: the transition starts without a key.")
			_note("left-clicked the classroom door")
		else:
			_note("the door was not under the cursor; pressed E instead")
			await _press(KEY_E)
		if await _wait_for_location("corridor", 40.0):
			await _wait(1.2)
			await _shot("13_corridor", "The walkway outside the classroom.")
	# 9b. The free period as the player now meets it: Q walking along, optional things
	# in the walkway, a real cursor hover, and the yard entered through the end door
	# on foot. Returns with the player back in the walkway.
	await _capture_free_period()

	var corridor := _host.get_current()
	if corridor != null and String(corridor.location_id) == "corridor":
		var gate := corridor.find_interactable(&"school_gate")
		if gate != null:
			await _wait_for_free(60.0)
			_teleport(Vector3(0, 0, 5.4), 0.0)
			await _wait_for_target(&"school_gate", 30.0)
			await _press(KEY_E)
			if await _wait_for_location("street", 40.0):
				await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the street arrival line")
				await _wait(0.8)
				await _shot("14_street", "The street outside the school gate, with the arrival line finished.")

	var street := _host.get_current()
	if street != null and String(street.location_id) == "street":
		var gutter := street.find_interactable(&"street_gutter")
		if gutter != null:
			await _wait_for_free(60.0)
			_teleport(Vector3(-8.9, 0, -21.4), 0.0)
			var prompted := await _wait_for_target(&"street_gutter", 30.0)
			if not prompted:
				_failures.append("The gutter was never offered as an interaction target.")
				await _shot("FAIL_street_prompt", "No prompt appeared for the street object.")
			await _shot("15_street_prompt", "A street object with its prompt.")
			await _press(KEY_E)
			if await _wait_for_line(5.0):
				await _wait(0.6)
				await _shot("16_street_inspection", "The street object's description.")
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 30.0, "the description to close")
		var stairs := street.find_interactable(&"street_to_residential")
		if stairs != null:
			await _wait_for_free(60.0)
			_teleport(Vector3(10.5, 0, -28.6), 0.0)
			if not await _wait_for_target(&"street_to_residential", 30.0):
				_failures.append("The way to the residential area was never offered.")
			await _shot("15b_stair_prompt", "The way up to the residential area.")
			await _press(KEY_E)
			if await _wait_for_location("residential", 40.0):
				await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the residential arrival line")
				await _wait(0.8)
				await _shot("17_residential", "The courtyard behind the school: three blocks and the stair.")

	var stair_location := _host.get_current()
	if stair_location != null and String(stair_location.location_id) == "residential":
		var stair := stair_location.find_interactable(&"res_stair")
		if stair == null:
			_failures.append("The courtyard has no stair to click.")
		else:
			await _wait_for_free(60.0)
			if await _position_near(stair, 1.6):
				await _click_at_screen(_screen_position_of(stair))
				if await _poll(func() -> bool: return _dialogue.has_pending_choices(), 30.0):
					await _shot(
						"17b_mouse_choice_prompt",
						"The stair conversation with its two options, opened by a mouse click."
					)
					if await _click_dialogue_option(1):
						await _wait(0.5)
						await _shot(
							"17c_mouse_choice_taken",
							"The second option taken with the mouse; the panel shows the line it leads to."
						)
						_note("dialogue option 2 selected with a left click")
					else:
						_failures.append("Clicking the second dialogue option did nothing.")
				else:
					_failures.append("Clicking the stair did not offer a choice.")
				await _drive_until(
					func() -> bool: return not _dialogue.is_busy(), 60.0, "the stair conversation"
				)
			else:
				_failures.append("Could not stand next to the stair to click it.")

	var flats := _host.get_current()
	if flats != null and String(flats.location_id) == "residential":
		var animal := flats.find_interactable(&"green_animal")
		if animal == null:
			_failures.append("The green animal is missing from the courtyard.")
		else:
			await _wait_for_free(60.0)
			_teleport(Vector3(7.3, 0, 0.1), -10.0)
			if not await _wait_for_target(&"green_animal", 30.0):
				_failures.append("The green animal was never offered as an interaction target.")
				await _shot("FAIL_animal_prompt", "No prompt appeared for the animal.")
			await _shot("18_animal_prompt", "The green animal, with the prompt to look at it.")
			await _press(KEY_E)
			if await _wait_for_line(5.0):
				await _wait(0.8)
				await _shot("19_animal_conversation", "Meeting the animal: the first line.")
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 90.0, "the animal conversation")
			if _dialogue.is_busy():
				await _shot("FAIL_animal_conversation", "The animal conversation did not finish.")
			var alley_exit := flats.find_interactable(&"res_alley_end")
			if alley_exit == null:
				_failures.append("The courtyard has no way into the alley.")
			else:
				await _wait_for_free(60.0)
				_teleport(Vector3(6.0, 0, -31.6), 0.0)
				if not await _wait_for_target(&"res_alley_end", 30.0):
					_failures.append("The alley was never offered from the courtyard.")
				await _press(KEY_E)
				if await _wait_for_location("alley", 45.0):
					await _drive_until(
						func() -> bool: return not _dialogue.is_busy(), 60.0, "the alley arrival line"
					)
					await _wait(0.8)
					await _shot("20_alley", "The lane behind the flats, with its arrival line finished.")
					await _capture_alley()
					if await _capture_playground():
						await _capture_yard_checks()

	# 10. A final state dump so the log can be read without the screenshots.
	_note("current location: %s" % String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "<none>")))
	_note("locale: %s, objective: %s" % [L10n.current, _ui.hud.get_objective_key()])
	_note("recorded knowledge entries: %d" % int(_narrative.get_entry_ids().size() if _narrative.has_method("get_entry_ids") else -1))
	_note("screenshots written: %d" % _shot_index)

	if _failures.is_empty():
		_note("RESULT: the playthrough reached the end of the built content.")
		print("::notice title=playthrough::reached the end of the built content")
	else:
		for failure: String in _failures:
			_note("FAILURE: %s" % failure)
			# Workflow command: the job log is not always retrievable, but an
			# annotation is, and an annotation is enough to see what broke.
			print("::error title=playthrough::%s" % failure)
		await _shot("FAIL_last_frame", "The last frame before the capture stopped.")
	_write_log()
	quit(0 if _failures.is_empty() else 1)


## The free period, from the walkway to the yard and back.
##
## Everything that can be walked is walked: the corridor-to-yard transition is made
## by holding the forward key at the door, not by teleporting past it, and the
## hover shot moves the real cursor with `Input.warp_mouse` so the highlight ring,
## the prompt and the E key are exercised together.
func _capture_free_period() -> void:
	var companion := _main.get_node_or_null("Companion") as CompanionController
	await _wait_for_free(60.0)
	if companion == null:
		_failures.append("The companion node is missing from the main scene.")
	elif not companion.is_joined():
		_failures.append("Q did not join the player after the classroom was left.")
	else:
		# Facing is set explicitly: a teleport to an identity basis keeps whatever
		# facing the player had, which would make "hold forward" a guess.
		_teleport(Vector3(-0.6, 0, 2.5), 1.0)
		await _wait(0.3)
		var start := _player.global_position
		Input.action_press("move_forward")
		await _wait(1.1)
		Input.action_release("move_forward")
		await _wait(0.6)
		var walked := _player.global_position.distance_to(start)
		var gap := companion.global_position.distance_to(_player.global_position)
		_note("walked %.2f m with Q; Q is %.2f m behind" % [walked, gap])
		if walked < 0.5:
			_failures.append("Holding forward in the walkway did not move the player.")
		if gap > companion.follow_distance + 1.0:
			_failures.append("Q did not keep up in the walkway (%.2f m behind)." % gap)
		await _shot("13a_q_following", "Q walking with the player in the walkway, at a natural distance.")

	# The pointer: stand in front of the cleaning trolley, then move the real cursor
	# onto it and check that the cue, the prompt and the target agree.
	var corridor := _host.get_current()
	if corridor == null:
		_failures.append("The walkway is not loaded during the free-period capture.")
		return
	var trolley := corridor.find_interactable(&"corridor_trolley")
	if trolley != null:
		await _wait_for_free(45.0)
		_teleport(Vector3(0.5, 0, 3.6), 270.0)
		await _wait(0.4)
		await _mouse_to_world(trolley.global_position + Vector3.UP * 0.2)
		var hovered := await _poll(
			func() -> bool:
				var target := _interaction.get_current_target()
				return target != null and target.interact_id == &"corridor_trolley",
			10.0
		)
		if not hovered:
			_failures.append("Moving the real cursor onto the trolley did not target it.")
			await _shot("FAIL_hover_trolley", "The cursor was over the trolley but nothing was targeted.")
		var prompt := _ui.hud.get_prompt_text() if _ui != null and _ui.hud.has_method("get_prompt_text") else ""
		_note("hover prompt: '%s'" % prompt)
		await _shot(
			"13b_hover_trolley",
			"The pointer resting on the cleaning trolley: the cue ring, the prompt, and the object E would use are the same thing."
		)
		await _press(KEY_E)
		if await _wait_for_line(6.0):
			await _wait(0.5)
			await _shot("13c_trolley_line", "Looking at the trolley, with Q's comment because Q is there.")
		await _drive_until(func() -> bool: return not _dialogue.is_busy(), 45.0, "the trolley line")
		# Release the pointer: nothing on screen is under it any more.
		await _mouse_to_world(Vector3(0, 0, 0))
		Input.warp_mouse(Vector2(4.0, 4.0))
		await _wait(0.2)

	# The wall speaker makes a noise of its own, once.
	var speaker := corridor.find_interactable(&"corridor_speaker")
	if speaker != null:
		await _wait_for_free(45.0)
		_teleport(Vector3(0.8, 0, -3.0), 270.0)
		if await _wait_for_target(&"corridor_speaker", 10.0):
			await _press(KEY_E)
			if await _wait_for_line(6.0):
				await _wait(0.5)
				await _shot(
					"13d_corridor_speaker",
					"The wall speaker: a short noise cue of its own, and a line about the class behind the wall."
				)
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 45.0, "the speaker line")

	# Walk to the end door and go through it. This is the transition the slice is
	# about, so it is made on foot rather than by teleporting into the yard.
	var yard_door := corridor.find_interactable(&"to_schoolyard")
	if yard_door == null:
		_failures.append("The walkway has no door to the yard.")
		return
	await _wait_for_free(45.0)
	_teleport(Vector3(0.0, 0, -4.2), 1.0)
	await _wait(0.3)
	# Walk in short pulses and stop as soon as the door is offered. A single long
	# hold overshoots into the end wall, where the door is no longer in front.
	var reached := false
	for _pulse in 8:
		Input.action_press("move_forward")
		await _wait(0.25)
		Input.action_release("move_forward")
		await _wait(0.15)
		if await _wait_for_target(&"to_schoolyard", 1.0):
			reached = true
			break
	if not reached:
		_failures.append("Walking to the end door did not offer it as a target.")
	await _shot("13e_yard_door_prompt", "The end door of the walkway, reached on foot.")
	await _press(KEY_E)
	if not await _wait_for_location("playground", 45.0):
		_failures.append("The walkway's end door did not load the yard.")
		return
	await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the yard arrival line")
	await _wait(0.9)
	await _shot(
		"13f_schoolyard_from_corridor",
		"The yard entered from the school side, with Q arriving beside the player."
	)
	# And back in, so the rest of the walkthrough keeps its original order.
	await _wait_for_free(45.0)
	_teleport(Vector3(-3.0, 0, -18.2), 1.0)
	if await _wait_for_target(&"pg_to_corridor", 12.0):
		await _press(KEY_E)
		if await _wait_for_location("corridor", 45.0):
			await _wait(0.8)
			await _shot("13g_back_in_the_walkway", "Back inside the walkway through the fire door.")


# --- the alley and the yard -------------------------------------------------


## The alley is short on purpose: one look at the notice wall, which is also the
## inspection that lets a passive inner voice speak for the first time.
func _capture_alley() -> void:
	var location := _host.get_current()
	if location == null or String(location.location_id) != "alley":
		_failures.append("The alley did not stay loaded for its screenshots.")
		return
	await _wait_for_free(45.0)
	_teleport(Vector3(2.4, 0, -1.9), 90.0)
	if not await _wait_for_target(&"alley_notice_wall", 30.0):
		_failures.append("The notice wall in the alley was never offered.")
		await _shot("FAIL_alley_prompt", "No prompt appeared for the alley notices.")
		return
	await _shot("21_alley_notices_prompt", "The notice wall in the alley, with its prompt.")
	await _press(KEY_E)
	if await _wait_for_line(6.0):
		await _wait(0.6)
		await _shot("22_alley_notice_line", "Reading the alley notices.")
	await _drive_until(
		func() -> bool: return not _dialogue.is_busy(), 45.0, "the notice description to close"
	)
	# The passive voice reacts to the reading, not to a keypress: wait for it.
	if await _poll(func() -> bool: return _dialogue.is_busy(), 12.0):
		if await _wait_for_line(6.0):
			await _wait(0.5)
			await _shot(
				"23_inner_voice_passive",
				"An inner voice speaking unprompted after the read. The roll behind this line is hidden: only the reaction is shown."
			)
	await _drive_until(
		func() -> bool: return not _dialogue.is_busy(), 45.0, "the inner-voice line"
	)
	await _wait(0.4)


## Walks through the estate gate into the yard. Returns true when the yard is the
## current location, so the caller knows whether the rest is worth attempting.
func _capture_playground() -> bool:
	await _wait_for_free(45.0)
	_teleport(Vector3(0.0, 0, -20.4), 180.0)
	if not await _wait_for_target(&"alley_to_playground", 30.0):
		_failures.append("The estate gate was never offered as a target.")
		return false
	await _shot("24_gate_prompt", "The estate gate at the end of the alley.")
	await _press(KEY_E)
	if not await _wait_for_location("playground", 45.0):
		_failures.append("The estate gate did not load the yard.")
		return false
	await _drive_until(
		func() -> bool: return not _dialogue.is_busy(), 60.0, "the yard arrival line"
	)
	await _wait(0.8)
	_teleport(Vector3(0.0, 0, 14.0), 0.0)
	await _wait(0.5)
	await _shot("25_playground_wide", "The open yard from the gate: court, hoops, bench, climbing frame, shed.")
	return true


## The two things the yard adds beyond a bigger room: a visible check with the
## numbers on screen, and the end card at the far gap instead of the alley mouth.
func _capture_yard_checks() -> void:
	var location := _host.get_current()
	if location == null:
		return
	await _wait_for_free(45.0)
	_teleport(Vector3(-8.0, 0, 9.2), 0.0)
	if await _wait_for_target(&"pg_hoop_near", 30.0):
		await _shot("26_hoop_prompt", "The near hoop, with its prompt.")
		await _press(KEY_E)
		if await _wait_for_line(6.0):
			await _wait(0.6)
			await _shot("27_hoop_inspection", "The hoop's description.")
		await _drive_until(
			func() -> bool: return not _dialogue.is_busy(), 45.0, "the hoop description to close"
		)
	else:
		_failures.append("The hoop was never offered as a target.")

	await _wait_for_free(45.0)
	_teleport(Vector3(-12.4, 0, -4.0), 90.0)
	if not await _wait_for_target(&"pg_shed_door", 30.0):
		_failures.append("The shed door was never offered as a target.")
	else:
		await _shot("28_shed_prompt", "The equipment shed, with its prompt.")
		await _press(KEY_E)
		if await _poll(func() -> bool: return _dialogue.has_pending_choices(), 20.0):
			await _shot(
				"29_shed_choices",
				"The shed's two approaches: the frame (Boundary) or the sheet (The Ledger), or leave it."
			)
			await _press(KEY_1)
			await _wait(0.4)
			if _ui.check_overlay.visible:
				await _shot(
					"30_visible_check",
					"A visible check: the voice, its value, the die, the difficulty, and the outcome."
				)
			else:
				_failures.append("The visible check panel did not appear for the shed attempt.")
			await _drive_until(
				func() -> bool: return not _dialogue.is_busy(), 60.0, "the shed attempt"
			)
			await _shot("31_check_result", "What the attempt left behind on screen.")

	await _wait_for_free(45.0)
	_teleport(Vector3(-14.0, 0, -16.8), 0.0)
	if not await _wait_for_target(&"pg_gap_in_fence", 30.0):
		_failures.append("The gap in the fence at the far end was never offered.")
		return
	await _shot("32_far_gap_prompt", "The gap in the fence at the far end of the yard.")
	await _press(KEY_E)
	if await _wait_for_visible(_ui.end_card, 25.0):
		await _wait(0.6)
		await _shot(
			"33_end_card",
			"The end-of-slice card, now at the far end of the yard instead of the alley mouth."
		)
	else:
		_failures.append("Stepping through the far gap did not show the end card.")


# --- mouse navigation -------------------------------------------------------


## Click-to-move, as a player does it: every step below is a real left click pushed
## through the input system. Nothing here teleports to fake a walk; a teleport is only
## used to reach the *starting* position from which an approach is then clicked.
func _capture_click_navigation() -> void:
	if not await _wait_for_free(45.0):
		_failures.append("The player never got control back for the mouse shots.")
		return
	_note("mouse shots: scripted left clicks pushed through the input system, not a human playtest")
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	var start := _player.global_position
	var destination := ""
	var walking := false
	var settled := false
	var walked := 0.0
	for _attempt in 3:
		var screen := _find_ground_click_screen(4.0, 6.5)
		if screen == Vector2.ZERO:
			break
		start = _player.global_position
		var clicks_before := navigator.get_click_count() if navigator != null else 0
		await _click_at_screen(screen)
		await _wait(0.2)
		walking = _player.is_path_active()
		if not walking and navigator != null and navigator.get_click_count() == clicks_before:
			# The press never arrived as unhandled input: something on screen took it.
			# That is worth saying out loud, and worth another point rather than a
			# failure that blames navigation.
			_note("a scripted click on the floor never reached the world; trying another point")
			continue
		if walking:
			# The route itself, in numbers: this is the evidence that the walk is a
			# navigation route and not a straight line through the furniture.
			var map := _player.navigation_agent.get_navigation_map()
			var path := NavigationServer3D.map_get_path(map, start, _player.get_path_target(), true)
			var length := 0.0
			for index in range(1, path.size()):
				length += Vector2(path[index].x - path[index - 1].x, path[index].z - path[index - 1].z).length()
			_note(
				"clicked route: %d waypoints, %.2f m of path for a %.2f m straight line"
				% [path.size(), length, Vector2(start.x - _player.get_path_target().x, start.z - _player.get_path_target().z).length()]
			)
		await _shot("03a_click_destination", "A left click on the floor: the destination ring and the walk starting.")
		await _wait(0.5)
		await _shot("03b_click_walking", "Mid-walk, after one click on the floor: no keys held.")
		settled = await _poll(func() -> bool: return not _player.is_path_active(), 25.0)
		walked = Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
		_note("floor click: walking=%s arrived=%s walked %.2f metres" % [walking, settled, walked])
		if walking and settled and walked > 1.5:
			destination = "walked"
			break
		if _dialogue.is_busy():
			_note("a story beat interrupted the clicked walk; retrying once")
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the interrupting beat")
			await _wait_for_free(45.0)
			continue
	if destination.is_empty():
		_failures.append(
			"A click on walkable floor did not move the character (%s; walking=%s, arrived=%s, walked %.2f m, at %s)."
			% [
				navigator.get_last_rejection() if navigator != null else "no navigator",
				str(walking), str(settled), walked,
				str(_player.global_position)
			]
		)

	# The keys take over mid-walk.
	var second := _find_ground_click_screen(3.0, 6.0)
	if second != Vector2.ZERO:
		await _click_at_screen(second)
		await _wait(0.25)
		var was_walking := _player.is_path_active()
		Input.action_press("move_forward")
		await _wait(0.4)
		Input.action_release("move_forward")
		await _wait(0.2)
		var stopped := not _player.is_path_active()
		await _shot("03c_wasd_cancels", "Holding a movement key during an automatic walk: the keys take over.")
		_note("walk before WASD=%s, walk after WASD=%s" % [was_walking, stopped])
		if not was_walking or not stopped:
			_failures.append("Holding a movement key did not take over from the automatic walk.")
	else:
		_failures.append("No second floor point was clickable for the interruption shot.")

	# A click on a prop: the inspection, reached by the mouse only.
	var sheet := _host.get_current().find_interactable(&"timetable")
	if sheet == null:
		_failures.append("The timetable sheet is missing from the classroom.")
		return
	await _wait_for_free(60.0)
	if await _position_near(sheet, 1.5):
		var sheet_screen := _screen_position_of(sheet)
		if _interaction.get_target_at_screen_position(sheet_screen, false) == sheet:
			await _click_at_screen(sheet_screen)
			if await _wait_for_line(15.0):
				await _shot("03f_click_inspect", "The timetable sheet opened by a click, with no key pressed.")
				_note("click-to-inspect: the sheet opened from a click")
			else:
				_failures.append("Clicking the timetable sheet opened nothing.")
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the clicked inspection")
		else:
			_failures.append("The timetable sheet was not under the cursor for the click-to-inspect shot.")
	else:
		_failures.append("Could not stand in front of the timetable sheet.")


## A screen position whose click lands on floor 4-6.5 m away, found by asking the same
## question the click will ask.
func _find_ground_click_screen(min_distance: float, max_distance: float) -> Vector2:
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if navigator == null:
		return Vector2.ZERO
	var rect := _player.get_viewport().get_visible_rect().size
	for x_step in 12:
		for y_step in 10:
			# The dialogue panel is anchored to the bottom edge and would swallow a
			# click aimed at the floor behind it, so the scan stays above it.
			var screen := Vector2(
				rect.x * (0.15 + 0.7 * float(x_step) / 11.0),
				rect.y * (0.28 + 0.34 * float(y_step) / 9.0)
			)
			var point: Variant = navigator.get_ground_point_at(screen)
			if point == null:
				continue
			var distance := Vector2(
				point.x - _player.global_position.x, point.z - _player.global_position.z
			).length()
			if distance < min_distance or distance > max_distance:
				continue
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			return screen
	return Vector2.ZERO


## Stands the player near an object, facing it, at a spot the navigation mesh knows.
func _position_near(target: Interactable, distance: float) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	var origin := target.global_position
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var candidate := origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
		if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.5:
			continue
		var to_target := origin - snapped
		var yaw := atan2(-to_target.x, -to_target.z)
		_player.teleport(Transform3D(Basis(Vector3.UP, yaw), Vector3(snapped.x, snapped.y + 0.05, snapped.z)))
		await _wait(0.2)
		if _interaction.get_target_at_screen_position(_screen_position_of(target), false) == target:
			return true
	return false


func _screen_position_of(target: Node3D) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null or target == null:
		return Vector2.ZERO
	return camera.unproject_position(target.global_position)


## A real left click at a screen position: cursor first, then press and release
## through the input system, the same path a player's mouse takes.
func _click_at_screen(screen: Vector2) -> void:
	var rect := _player.get_viewport().get_visible_rect().size
	var position := Vector2(clampf(screen.x, 1.0, rect.x - 1.0), clampf(screen.y, 1.0, rect.y - 1.0))
	Input.warp_mouse(position)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	Input.parse_input_event(press)
	await process_frame
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = position
	release.global_position = position
	Input.parse_input_event(release)
	await process_frame


## Clicks one of the option buttons currently on screen. Returns false when there is
## no such option, or when the click left the options up.
func _click_dialogue_option(index: int) -> bool:
	if _panel == null:
		return false
	var container := _panel.get_node_or_null("Frame/Content/ChoicesContainer")
	if container == null:
		return false
	var buttons: Array[Button] = []
	for child in container.get_children():
		var button := child as Button
		if button != null:
			buttons.append(button)
	if index < 0 or index >= buttons.size():
		return false
	await _click_at_screen(buttons[index].get_global_rect().get_center())
	await _wait(0.3)
	return not _panel.has_choices()


# --- input ------------------------------------------------------------------


## A real key press through the input system, the same path a player's keyboard
## takes: down and up as separate events, one frame apart.
## Moves the real cursor to the screen position of a world point. `Input.warp_mouse`
## moves the OS cursor, so the hover path in the game is the same one a player uses.
func _mouse_to_world(world_position: Vector3) -> void:
	var camera := _player.get_viewport().get_camera_3d() if _player != null else null
	if camera == null:
		return
	var screen := camera.unproject_position(world_position)
	var rect := _player.get_viewport().get_visible_rect().size
	Input.warp_mouse(Vector2(clampf(screen.x, 1.0, rect.x - 1.0), clampf(screen.y, 1.0, rect.y - 1.0)))
	await process_frame


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _teleport(position: Vector3, yaw_degrees: float) -> void:
	_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position))


# --- waiting ----------------------------------------------------------------


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout
	await process_frame


## The director locks the player while a beat plays, and beats can start at any
## time (the bell, the reminder, the arrival line). Nothing is pressed until
## control has actually come back, otherwise the input goes nowhere.
## Waits for a moment with no presentation and with control returned, pressing the
## keys a player would press: story beats can start at any time, and one of them
## will be mid-conversation when the script arrives.
func _wait_for_free(timeout_seconds: float) -> bool:
	return await _drive_until(
		func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		timeout_seconds, "the player to be free"
	)


func _wait_for_line(timeout_seconds: float) -> bool:
	# Wait for the whole line, not the first frame of the reveal: a screenshot
	# taken mid-reveal looks like text that was cut off.
	return await _poll(func() -> bool:
		var line := String(_dialogue.get_current_line().get("text", ""))
		return _dialogue.is_busy() and not line.is_empty() \
			and (_panel == null or not _panel.is_revealing()),
		timeout_seconds)


func _wait_for_target(interact_id: StringName, timeout_seconds: float) -> bool:
	var found := await _poll(func() -> bool:
		var target := _interaction.get_current_target()
		return target != null and target.interact_id == interact_id and not _ui.hud.get_prompt_text().is_empty(),
		timeout_seconds)
	if not found:
		var target := _interaction.get_current_target()
		_note("prompt for '%s' never appeared: target=%s prompt='%s' position=%s busy=%s control=%s" % [
			interact_id,
			"<none>" if target == null else String(target.interact_id),
			_ui.hud.get_prompt_text(),
			str(_player.global_position),
			_dialogue.is_busy(),
			_player.is_control_enabled(),
		])
	return found


func _wait_for_location(location_id: String, timeout_seconds: float) -> bool:
	return await _poll(func() -> bool:
		var current := _host.get_current()
		return current != null and String(current.location_id) == location_id, timeout_seconds)


func _wait_for_visible(node: CanvasItem, timeout_seconds: float) -> bool:
	return await _poll(func() -> bool: return node != null and node.visible, timeout_seconds)


func _poll(predicate: Callable, timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if bool(predicate.call()):
			return true
		await process_frame
	return false


## Presses the key a player would press to get past whatever is on screen, until
## `predicate` is true. Space advances a line; a digit picks a choice.
func _drive_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	var last_key := 0.0
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if bool(predicate.call()):
			return true
		if _dialogue.is_busy() and Time.get_ticks_msec() - last_key > 250:
			last_key = Time.get_ticks_msec()
			if _dialogue.has_pending_choices():
				await _press(KEY_1)
			else:
				await _press(KEY_SPACE)
		else:
			await process_frame
	_failures.append("Timed out while driving %s." % label)
	return false


# --- evidence ---------------------------------------------------------------


func _shot(shot_name: String, caption: String) -> void:
	RenderingServer.force_draw(true)
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	if image == null:
		_failures.append("No image was available for screenshot %s." % shot_name)
		return
	var path := "%s/%s.png" % [SHOT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		_failures.append("Screenshot %s could not be saved (error %d)." % [shot_name, err])
		return
	_shot_index += 1
	_note("screenshot %s: %s (%dx%d)" % [shot_name, caption, image.get_width(), image.get_height()])


func _fail(reason: String) -> void:
	_failures.append(reason)
	await _shot("FAIL_stopped", "The frame where the capture stopped: %s" % reason)
	for failure: String in _failures:
		_note("FAILURE: %s" % failure)
	_write_log()
	quit(1)


func _note(message: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), message]
	_log_lines.append(line)
	print("CAPTURE %s" % line)


func _write_log() -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % LOG_PATH)
		return
	file.store_string("\n".join(_log_lines) + "\n")
	file.close()
	# A Markdown index, so the pull request can show the frames with their captions.
	var markdown := PackedStringArray()
	markdown.append("# Playthrough screenshots")
	markdown.append("")
	markdown.append("Captured by `tests/capture_playthrough.gd` in a real Godot window under")
	markdown.append("Xvfb (`--rendering-driver opengl3`, 1600x900). Interaction, dialogue")
	markdown.append("advance, choice selection and the language switch were produced with")
	markdown.append("simulated key events; walking between scenes was shortened with")
	markdown.append("teleports so the capture fits in CI. Regenerate with the")
	markdown.append("`Playthrough capture` workflow.")
	markdown.append("")
	for line: String in _log_lines:
		if not line.contains("screenshot "):
			continue
		var file_part := line.get_slice("screenshot ", 1)
		var shot_name := file_part.get_slice(":", 0).strip_edges()
		var caption := file_part.get_slice(":", 1).strip_edges()
		caption = caption.substr(0, caption.rfind(" ("))
		markdown.append("## %s" % shot_name)
		markdown.append("")
		markdown.append(caption)
		markdown.append("")
		markdown.append("![%s](%s.png)" % [shot_name, shot_name])
		markdown.append("")
	var markdown_file := FileAccess.open("res://docs/screenshots/PLAYTHROUGH.md", FileAccess.WRITE)
	if markdown_file != null:
		markdown_file.store_string("\n".join(markdown) + "\n")
		markdown_file.close()
