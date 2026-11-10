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
## Why the last `_find_ground_click_screen` calls found nothing. Filled whether or not
## they succeed; a failure that says "no second floor point was clickable" without
## saying which of the four ways it was rejected is a failure nobody can act on.
var _ground_search_log: Array[String] = []
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

	# The four imported models, in this room. Taken here, at the first moment the player
	# has control and before anything else moves them.
	await _capture_imported_models()

	# The three candidate marks for a floor click, photographed from one fixed viewpoint.
	# The comparison is part of the evidence: this round chose between them, and the frames
	# are the only way to look at that choice afterwards.
	await _capture_cue_candidates()

	# 3b. The mouse, with real pointer events: a click on the floor, a click that the
	# keys interrupt, a click on a person, and a click on a prop.
	await _capture_click_navigation()

	# 4. The interaction prompt for the schoolbag, with the key it names.
	await _wait_for_free(60.0)
	# Stand where the schoolbag is actually offered, rather than at a coordinate that
	# happened to face it when this was written: the room has been rebuilt since, and a
	# hardcoded spot turns a moved prop into "the schoolbag was never offered".
	var bag: Interactable = null
	if _host.get_current() != null:
		bag = _host.get_current().find_interactable(&"schoolbag")
	if bag == null:
		await _fail("The schoolbag is missing from the classroom.")
		return
	if not await _position_near(bag, 1.4):
		_failures.append("Could not stand in front of the schoolbag.")
		await _shot("FAIL_schoolbag_position", "No spot next to the schoolbag offered it as a target.")
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
	await _position_near(bag, 1.4)
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
	_note("recorded knowledge entries: %d" % _knowledge_count())
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


# --- the ground mark: candidate comparison ----------------------------------


## Half of this is the shipped mark (candidate A); B and C are composed here, out of the same
## pen, so that all three are real geometry drawn by the real material on the real floor. A
## candidate that only exists in this file cannot leak into the game.
func _candidate_mesh(design: String) -> ArrayMesh:
	match design:
		"tick":
			return WorldCue.destination_mark_mesh()
		"brackets":
			var bracket := SurfaceTool.new()
			bracket.begin(Mesh.PRIMITIVE_TRIANGLES)
			bracket.set_normal(Vector3.UP)
			bracket.append_from(WorldCue.arc_mesh(0.085, 25.0, 70.0, 0.02, 0.3), 0, Transform3D())
			bracket.append_from(WorldCue.arc_mesh(0.085, 205.0, 70.0, 0.02, 0.3), 0, Transform3D())
			bracket.append_from(
				WorldCue.stroke_mesh(Vector2(-0.009, 0.0), Vector2(0.009, 0.0), 0.016), 0, Transform3D()
			)
			return bracket.commit()
		_:
			var commas := SurfaceTool.new()
			commas.begin(Mesh.PRIMITIVE_TRIANGLES)
			commas.set_normal(Vector3.UP)
			var strokes: Array = [[4.0, 0.050], [121.0, 0.062], [247.0, 0.044]]
			for stroke: Array in strokes:
				var angle := deg_to_rad(float(stroke[0]))
				var reach := float(stroke[1])
				var direction := Vector2(cos(angle), sin(angle))
				commas.append_from(
					WorldCue.stroke_mesh(
						direction * 0.022, direction * (0.022 + reach), 0.02, 0.55
					),
					0,
					Transform3D()
				)
			commas.append_from(
				WorldCue.stroke_mesh(Vector2(-0.006, 0.0), Vector2(0.006, 0.0), 0.015), 0, Transform3D()
			)
			return commas.commit()


## Puts one candidate mark on the floor at `point`, laid on the real surface normal. Returns
## the holder so the caller can free it again.
func _place_candidate(design: String, point: Vector3, normal: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Candidate_%s" % design
	var parent: Node = _host.get_current()
	if parent == null:
		parent = _main
	parent.add_child(holder)
	holder.global_transform = Transform3D(
		WorldCue.ground_basis(normal), point + normal.normalized() * 0.02
	)
	var mark := MeshInstance3D.new()
	mark.mesh = _candidate_mesh(design)
	mark.material_override = WorldCue.material_for(WorldCue.ROLE_DESTINATION)
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.transparency = 0.0
	holder.add_child(mark)
	return holder


## The four imported models, in the room the player is standing in.
##
## The classroom's six student desks, the stationery on the player's own desk, the
## player's own model and Q. These are frames of the running game — the same window, the
## same light, the same baked navigation as every other frame in this run — from a camera
## the capture places for the purpose, because the player's own camera is nailed to the
## player's shoulder and a desk is 0.9 m tall. The camera is removed and the player's
## camera made current again before anything else happens, so no other frame in this run
## is affected.
##
## What is *not* done here: the models are not staged. Nothing is moved, spawned or
## hidden for these frames; if the classroom does not contain them, the shot shows an
## empty classroom and the log says so.
func _capture_imported_models() -> void:
	var classroom := _host.get_current()
	if classroom == null:
		_failures.append("The classroom was not loaded, so the imported models could not be photographed.")
		return

	# The scene the frames are supposed to show, checked before it is photographed: a
	# missing model is a defect in the build, not a bad camera angle.
	var furniture := classroom.get_node_or_null(^"Furniture")
	var desk_names: Array[String] = ["DeskA1", "DeskA2", "DeskA3", "DeskB1", "DeskB2", "DeskB3"]
	var with_models := 0
	if furniture != null:
		for desk_name: String in desk_names:
			var desk := furniture.get_node_or_null(NodePath(desk_name)) as Node3D
			if desk != null and desk.get_node_or_null(^"Desk") != null:
				with_models += 1
	_note("classroom desks with the imported model: %d of %d" % [with_models, desk_names.size()])
	if with_models != desk_names.size():
		_failures.append(
			"Only %d of the classroom's %d desks have the school desk model."
			% [with_models, desk_names.size()]
		)
	var stationery := classroom.get_node_or_null(^"Furniture/DeskB2/Stationery") as Node3D
	if stationery == null:
		_failures.append("The player's own desk carries no stationery.")
	else:
		var extent := _subtree_aabb(stationery)
		_note(
			"stationery on DeskB2: base y = %.3f m, %.3f x %.3f x %.3f m"
			% [extent.position.y, extent.size.x, extent.size.y, extent.size.z]
		)

	var player_camera := _player.get_node_or_null(^"Camera3D") as Camera3D
	var player_point := _player.global_position

	# 1. The room from the back, over both rows: six desks, six chairs.
	await _shot_from_camera(
		Vector3(0.0, 2.7, 3.25), Vector3(0.0, 0.5, -0.85),
		"03h_classroom_desks",
		"The classroom from the back: six student desks with the imported model and their "
		+ "chairs, at the positions the room has always had."
	)

	# 2. The player's own desk, close enough to see what is on it.
	# From the front of the room looking back over the desk, so a player standing behind
	# the desk cannot be between the camera and what it is photographing.
	await _shot_from_camera(
		Vector3(-0.55, 1.55, -1.15), Vector3(0.0, 0.95, 0.15),
		"03i_own_desk_stationery",
		"The player's own desk (DeskB2) from the sitting side: the stationery set on the top."
	)

	# 3. The player's own model, from the front, head to feet.
	var facing := _player.get_facing_direction()
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3(0.0, 0.0, 1.0)
	facing = facing.normalized()
	await _shot_from_camera(
		player_point + facing * 2.4 + Vector3(0.0, 1.32, 0.0),
		player_point + Vector3(0.0, 1.1, 0.0),
		"03j_protagonist",
		"The player's authored protagonist, standing on the classroom floor, head to feet, "
		+ "under the nameplate the game shows.",
		_player.get_node_or_null(^"Nameplate") as Node3D
	)

	# 4. Q, from the side Q is looking at, in the same room.
	var q_actor := classroom.get_node_or_null(^"Actors/Q") as Node3D
	if q_actor == null:
		_failures.append("The classroom's Q is missing, so Q could not be photographed.")
	else:
		var q_forward := -q_actor.global_basis.z
		q_forward.y = 0.0
		if q_forward.length() > 0.01:
			q_forward = q_forward.normalized()
		await _shot_from_camera(
			q_actor.global_position + q_forward * 2.5 + Vector3(0.0, 1.28, 0.0),
			q_actor.global_position + Vector3(0.0, 1.1, 0.0),
			"03k_q_in_the_classroom",
			"Q in the classroom, wearing the authored model, from the side Q faces, under the "
			+ "nameplate the game shows.",
			q_actor.get_node_or_null(^"Nameplate") as Node3D
		)

	if player_camera != null:
		player_camera.current = true
	await _wait(0.2)


## The world-space box around everything a node draws, for the logging above.
func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
		var mesh_instance := current as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## One frame from a camera placed for it, then the camera is gone again.
func _shot_from_camera(
	eye: Vector3,
	look_at_point: Vector3,
	shot_name: String,
	caption: String,
	plate: Node3D = null
) -> void:
	var camera := Camera3D.new()
	camera.name = "CaptureCamera"
	camera.fov = 55.0
	camera.far = 120.0
	_main.add_child(camera)
	camera.global_position = eye
	camera.look_at(look_at_point, Vector3.UP)
	camera.current = true
	await process_frame
	# A character shot is framed for the character and the nameplate the game draws over
	# it; the first run of these two put the character in the middle of the frame and cut
	# the nameplate off the top. Whether the plate fits is measurable, so it is measured.
	if plate != null:
		var view := camera.get_viewport().get_visible_rect().size
		if camera.is_position_behind(plate.global_position):
			_failures.append("The nameplate in %s is behind the camera." % shot_name)
		else:
			var screen := camera.unproject_position(plate.global_position)
			var margin := view.y * 0.10
			_note("nameplate in %s: screen %s of %s" % [shot_name, str(screen), str(view)])
			if (
				screen.x < view.x * 0.04
				or screen.x > view.x * 0.96
				or screen.y < margin
				or screen.y > view.y - margin
			):
				_failures.append(
					"the nameplate in %s is at screen %s of %s, closer to the edge than the "
					% [shot_name, str(screen), str(view)]
					+ "character it belongs to, so the frame does not show it"
				)
	await _shot(shot_name, caption)
	camera.queue_free()
	await process_frame


## The three candidates, at the same point from the same camera, then all three together.
##
## "Small" is the whole point of the redesign, so the run measures the ink each candidate
## actually puts on the floor: the frames are grabbed with and without the mark and the
## changed pixels inside the mark's own area are counted. A candidate that turns out
## invisible at gameplay distance would show up here as a number, not as an opinion.
func _capture_cue_candidates() -> void:
	if not await _wait_for_free(45.0):
		_note("the candidate frames could not be taken: the player never got control back")
		return
	_teleport(Vector3(0.55, 0.0, 1.7), 0.0)
	await _wait(0.4)
	var ahead := -_player.global_transform.basis.z
	var centre := _player.global_position + ahead * 2.4
	var floor_hit := _floor_at(centre)
	var point: Vector3 = floor_hit["point"]
	var normal: Vector3 = floor_hit["normal"]
	_note("cue candidates: mark at %s on normal %s" % [str(point), str(normal)])

	var screen := _screen_position_of_point(point)
	var designs: Array[String] = ["tick", "brackets", "commas"]
	var inked := {}
	for design: String in designs:
		await _shot_free_frame()
		var before: Image = await _grab_image()
		var holder := _place_candidate(design, point, normal)
		await _wait(0.3)
		var after: Image = await _grab_image()
		inked[design] = _ink_pixels(before, after, screen, 90)
		await _shot(
			"cue_candidate_%s" % design,
			"Candidate %s: the floor-click mark, from the player's own camera at 2.4 m."
			% design
		)
		holder.queue_free()
		await process_frame
	_note("cue candidates: ink on screen (px within 90 px of the mark) = %s" % str(inked))

	for index in designs.size():
		var offset := ahead * (1.8 + 0.6 * float(index))
		var hit := _floor_at(_player.global_position + offset)
		_place_candidate(designs[index], hit["point"], hit["normal"])
	await _wait(0.3)
	await _shot(
		"cue_candidates_abc",
		"The three candidates side by side on the same floor, from one camera: A tick, "
		+ "B brackets, C commas. The shipped one is A."
	)
	var current := _host.get_current()
	if current != null:
		for child in current.get_children():
			if String(child.name).begins_with("Candidate_"):
				child.queue_free()
	await process_frame


## Hides every cue this run may have left on the floor, so a "before" frame is clean.
func _shot_free_frame() -> void:
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if navigator != null:
		navigator.cancel()
	await _wait(0.2)


## The floor under a world point: position and normal, from one downward ray against the
## world layer. Falls back to y = 0 when nothing is hit, which is the classroom floor.
func _floor_at(point: Vector3) -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	if space != null:
		var from := Vector3(point.x, point.y + 3.0, point.z)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return {
				"point": hit.get("position", point),
				"normal": hit.get("normal", Vector3.UP),
			}
	return {"point": Vector3(point.x, 0.0, point.z), "normal": Vector3.UP}


func _screen_position_of_point(world: Vector3) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world)


func _grab_image() -> Image:
	RenderingServer.force_draw(true)
	await process_frame
	await process_frame
	return root.get_texture().get_image()


## How many pixels changed between two frames inside a square around `centre`. A mark that
## draws nothing changes nothing; a mark that is a ring changes thousands.
func _ink_pixels(before: Image, after: Image, centre: Vector2, half_box: int) -> int:
	if before == null or after == null:
		return -1
	var left := maxi(int(centre.x) - half_box, 0)
	var right := mini(int(centre.x) + half_box, mini(before.get_width(), after.get_width()) - 1)
	var top := maxi(int(centre.y) - half_box, 0)
	var bottom := mini(int(centre.y) + half_box, mini(before.get_height(), after.get_height()) - 1)
	var changed := 0
	for y in range(top, bottom):
		for x in range(left, right):
			var was: Color = before.get_pixel(x, y)
			var now: Color = after.get_pixel(x, y)
			var delta: float = maxf(
				maxf(absf(was.r - now.r), absf(was.g - now.g)), absf(was.b - now.b)
			)
			if delta > 0.04:
				changed += 1
	return changed


# --- mouse navigation -------------------------------------------------------


## Click-to-move, as a player does it: every step below is a real left click pushed
## through the input system. Nothing here teleports to fake a walk; a teleport is only
## used to reach the *starting* position from which an approach is then clicked.
func _capture_click_navigation() -> void:
	if not await _wait_for_free(45.0):
		_failures.append("The player never got control back for the mouse shots.")
		return
	await _unstick()
	_note("mouse shots: scripted left clicks pushed through the input system, not a human playtest")
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	# Which way an automatic walk ends: a finish or a cancel. A walk that stops without
	# travelling has to say which of the two ended it.
	var endings := [0, 0]
	_player.path_finished.connect(func() -> void: endings[0] += 1)
	_player.path_cancelled.connect(func() -> void: endings[1] += 1)
	var start := _player.global_position
	var destination := ""
	var walking := false
	var settled := false
	var walked := 0.0
	var after_click := "not sampled"
	var clicked := false
	for _attempt in 3:
		# Each attempt first asks whether the player can move at all. A capsule wedged
		# between two desks makes `move_and_slide()` find nowhere to go, the walk watchdog
		# cancels three times, and the retry that follows used to click the same floor from
		# the same wedge and report "the click did not move the character".
		await _unstick()
		# A camera looking at the player only shows so much floor: widen the window
		# before giving up, so "no point to click" is not reported as "the click did
		# not move the character".
		var screen := _find_ground_click_screen(4.0, 6.5)
		if screen == Vector2.ZERO:
			screen = _find_ground_click_screen(3.0, 8.0)
		if screen == Vector2.ZERO:
			break
		clicked = true
		start = _player.global_position
		var clicks_before := navigator.get_click_count() if navigator != null else 0
		await _click_at_screen(screen)
		await _wait(0.2)
		walking = _player.is_path_active()
		after_click = "control=%s, legs=%d, index=%d, dialogue=%s, pending=%s, target=%s" % [
			str(_player.is_control_enabled()),
			_player.get_path_legs().size(),
			_player.get_path_index(),
			str(_dialogue.is_busy()),
			str(navigator.get_pending_target()) if navigator != null else "no navigator",
			str(_player.get_path_target()),
		]
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
		if walking and settled and walked < 0.2:
			# Accepted, then cancelled without moving: a wedge, not a navigation refusal.
			# Step clear of it and try again from somewhere the route can actually leave.
			_note("the clicked walk was cancelled without travelling; stepping the player clear")
			await _unstick(true)
		if _dialogue.is_busy():
			_note("a story beat interrupted the clicked walk; retrying once")
			await _drive_until(func() -> bool: return not _dialogue.is_busy(), 60.0, "the interrupting beat")
			await _wait_for_free(45.0)
			continue
	if destination.is_empty() and not clicked:
		_failures.append(
			"No walkable floor between 3 and 8 metres of the player could be found to click (at %s)."
			% str(_player.global_position)
		)
	elif destination.is_empty():
		_failures.append(
			"A click on walkable floor did not move the character (%s; walking=%s, arrived=%s, walked %.2f m, at %s, started at %s; %s; ended %d finish, %d cancel)."
			% [
				navigator.get_last_rejection() if navigator != null else "no navigator",
				str(walking), str(settled), walked,
				str(_player.global_position), str(start), after_click,
				endings[0], endings[1]
			]
		)

	# The keys take over mid-walk.
	_ground_search_log.clear()
	var second := _find_ground_click_screen(3.0, 6.0)
	if second == Vector2.ZERO:
		second = _find_ground_click_screen(2.0, 5.0)
	if second == Vector2.ZERO:
		second = _find_ground_click_screen(4.0, 8.0)
	if second == Vector2.ZERO:
		# The first walk ends wherever the click sent it, and one of those places is a
		# corner of the room. From there the camera has two walls in frame and a 0.4 m
		# strip of floor, so no distance band can contain a click point - measured, not
		# guessed: 123 of 144 screen points had no ground under them and the nearest floor
		# was 0.4 m away. That is a fact about where the player stood, not about the keys
		# taking over a walk, so the shot stands somewhere the room is in frame, says so,
		# and gives the same three bands one more go. The assertion below is unchanged.
		_note(
			"the interruption shot had no floor in view from %s; stepping into the open"
			% str(_player.global_position)
		)
		_teleport(Vector3(0.4, 0.0, 2.6), 0.0)
		await _wait(0.5)
		await _unstick()
		_ground_search_log.clear()
		second = _find_ground_click_screen(3.0, 6.0)
		if second == Vector2.ZERO:
			second = _find_ground_click_screen(2.0, 5.0)
		if second == Vector2.ZERO:
			second = _find_ground_click_screen(4.0, 8.0)
	if second != Vector2.ZERO:
		# The same two retries the first walk gets, for the same two reasons: a click can
		# be swallowed by something on screen before the navigator sees it, and a click
		# the navigator refuses starts no walk. Neither is "the keys did not take over",
		# so neither should be reported as it.
		var was_walking := false
		var clicks_seen := 0
		for _attempt in 2:
			var clicks_before := navigator.get_click_count() if navigator != null else 0
			await _click_at_screen(second)
			# A click becomes a route on the controller's own cadence, and the route can
			# start a third of a second after the press. Waiting a fixed 0.25 s measured
			# that delay instead of the thing the shot is about: the key has to take over
			# from a walk that is *already running*, so wait for it to run.
			was_walking = await _poll(
				func() -> bool: return _player.is_path_active(), 2.0
			)
			clicks_seen = (navigator.get_click_count() if navigator != null else 0) - clicks_before
			if was_walking:
				break
			_note("the interruption click started no walk; %d click(s) were accepted" % clicks_seen)
			if clicks_seen <= 0:
				_note("the interruption click never reached the world; trying another point")
				second = _find_ground_click_screen(3.0, 6.0)
				if second == Vector2.ZERO:
					second = _find_ground_click_screen(2.0, 5.0)
				if second == Vector2.ZERO:
					second = _find_ground_click_screen(4.0, 8.0)
				if second == Vector2.ZERO:
					break
				continue
			# The navigator saw the click and accepted no walk: another point would be a
			# different question, so this is the moment to stop asking it.
			break
		Input.action_press("move_forward")
		await _wait(0.4)
		Input.action_release("move_forward")
		await _wait(0.2)
		var stopped := not _player.is_path_active()
		await _shot("03c_wasd_cancels", "Holding a movement key during an automatic walk: the keys take over.")
		_note("walk before WASD=%s, walk after WASD=%s" % [was_walking, stopped])
		if not was_walking or not stopped:
			_failures.append(
				"Holding a movement key did not take over from the automatic walk "
				+ "(walk before=%s, walk after=%s, clicks accepted=%d, %s, control=%s, "
				% [
					was_walking, stopped, clicks_seen,
					navigator.get_last_rejection() if navigator != null else "no navigator",
					str(_player.is_control_enabled()),
				]
				+ "dialogue=%s, player at %s)."
				% [str(_dialogue.is_busy()), str(_player.global_position)]
			)
	else:
		# The three bands and their numbers travel with the failure: "nothing was
		# clickable" is four different problems depending on which test rejected what.
		_failures.append(
			"No second floor point was clickable for the interruption shot (%s)."
			% ("; ".join(_ground_search_log) if not _ground_search_log.is_empty() else "no search ran")
		)

	# A click on a prop: the inspection, reached by the mouse only.
	var sheet := _host.get_current().find_interactable(&"timetable")
	if sheet == null:
		_failures.append("The timetable sheet is missing from the classroom.")
		return
	await _wait_for_free(60.0)
	if await _position_near(sheet, 1.5):
		# The cue itself, with the real cursor resting on the object. This is the picture
		# of what this round changed: without it the pull request would be describing a
		# cue it cannot show. The cursor is placed by asking the controller which pixel
		# resolves to the sheet, rather than by projecting its origin and hoping.
		var sheet_screen: Vector2 = await _cursor_onto(sheet)
		if sheet_screen != Vector2.ZERO and await _wait_for_target(sheet.interact_id, 6.0):
			# Long enough for the fade to finish and for the ring to have turned: a frame
			# taken in the first sixteenth of a second shows the cue at its dimmest.
			await _wait(0.45)
			await _shot(
				"03d_hover_cue",
				"The hover cue on the timetable sheet: a dashed ring on the floor, a wider halo, "
				+ "and a shard floating above the object."
			)
			var cue := sheet.get_cue()
			if cue != null:
				_note(
					"hover cue: revealed=%s opacity=%.2f parts=%s"
					% [str(cue.is_revealed()), cue.get_opacity(), str(cue.get_parts().keys())]
				)
			else:
				_note("hover cue: the object is highlighted but carries no cue")
		else:
			_note("the hover cue shot found no target under the cursor; the frame is missing")
		if sheet_screen != Vector2.ZERO:
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

	await _capture_refused_click(sheet)
	# The cue is heard as well as seen, and a frame cannot show that. The counts are the
	# only evidence a real run can carry for the sounds: three clicks through the real input
	# system, so at least one accepted and one refused cue should have spoken.
	var audio := root.get_node_or_null("CueAudio")
	if audio != null and audio.has_method("get_counts"):
		_note("cue audio after the mouse shots: %s" % str(audio.get_counts()))
	else:
		_note("cue audio: no CueAudio autoload in this run; the cues were silent")


## A click the world refuses: the cue has to say "no" somewhere the player is looking, and
## it has to look different from the cue that says "walk there". The click is aimed at the
## wall the player is facing, at chest height, which is exactly where a player aims when
## they expect a door to open.
func _capture_refused_click(near: Interactable) -> void:
	await _wait_for_free(30.0)
	if near == null or not await _position_near(near, 1.2):
		_note("the refused-click shot found nowhere to stand; the frame is missing")
		return
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	var camera := _player.get_viewport().get_camera_3d()
	if navigator == null or camera == null:
		_note("the refused-click shot found no navigator or camera; the frame is missing")
		return
	var facing := -_player.global_transform.basis.z
	var aim := _player.global_position + facing * 1.6 + Vector3.UP * 1.2
	var screen := camera.unproject_position(aim)
	await _click_at_screen(screen)
	if navigator.was_last_click_accepted():
		_note("the refused-click shot hit walkable ground instead of a wall; the frame is missing")
		return
	await _wait(0.12)
	await _shot(
		"03g_refused_click",
		"A click on a wall: the cue collapses inward in the refusal colour and fades, and no walk starts."
	)
	_note(
		"refused click: role=%s, rejection=%s"
		% [navigator.get_cue_role(), navigator.get_last_rejection()]
	)


## A screen position whose click lands on floor 4-6.5 m away, found by asking the same
## question the click will ask.
func _find_ground_click_screen(min_distance: float, max_distance: float) -> Vector2:
	var navigator := _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if navigator == null:
		_ground_search_log.append("%.0f-%.0f m: no PointerNavigator" % [min_distance, max_distance])
		return Vector2.ZERO
	var rect := _player.get_viewport().get_visible_rect().size
	var no_ground := 0
	var out_of_range := 0
	var on_a_target := 0
	var unreachable := 0
	var nearest := INF
	for x_step in 12:
		for y_step in 12:
			# The dialogue panel is anchored to the bottom edge and would swallow a click
			# aimed at the floor behind it, so the scan stays above it — but not far above:
			# a narrow band tuned for one camera pitch left "no floor to click" behind
			# whenever the camera settled a little differently, which turned into two
			# different failures blaming navigation.
			var screen := Vector2(
				rect.x * (0.12 + 0.76 * float(x_step) / 11.0),
				rect.y * (0.24 + 0.42 * float(y_step) / 11.0)
			)
			var point: Variant = navigator.get_ground_point_at(screen)
			if point == null:
				no_ground += 1
				continue
			var distance := Vector2(
				point.x - _player.global_position.x, point.z - _player.global_position.z
			).length()
			nearest = minf(nearest, distance)
			if distance < min_distance or distance > max_distance:
				out_of_range += 1
				continue
			if _interaction.get_target_at_screen_position(screen, false) != null:
				on_a_target += 1
				continue
			if not _reaches(point):
				unreachable += 1
				continue
			return screen
	# Nothing in this band. The counts, the closest floor the scan did see, and where the
	# player stood: enough to tell a camera looking at a wall from a floor the navigation
	# map refuses to reach.
	_ground_search_log.append(
		"%.0f-%.0f m: %d points, %d with no ground under them, %d out of range, "
		% [min_distance, max_distance, 12 * 12, no_ground, out_of_range]
		+ "%d on a target, %d unreachable, nearest %.1f m, player at %s"
		% [on_a_target, unreachable, nearest, str(_player.global_position)]
	)
	return Vector2.ZERO


## Makes sure the body can move before a walk is judged by whether it moved.
##
## The capture reaches a starting position by teleporting, and a teleport can drop the
## capsule inside a desk: the navigation map still answers with a route, the walk starts,
## `move_and_slide()` finds nowhere to go, and the stall watchdog cancels it three times
## in a row. That is a capture position problem, not a navigation one, so it is found
## and fixed here — and said out loud rather than silently corrected.
## `force` skips the "can it move at all" question. It is used after a walk that was
## accepted and then cancelled three times without travelling: `test_move()` says the capsule
## can move (it slides along a desk), while `move_and_slide()` along the route finds nowhere
## to go, so the unforced check returns early and the player stays wedged.
func _unstick(force: bool = false) -> void:
	var probe := 0.5
	var directions := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	if not force:
		for direction in directions:
			if not _player.test_move(_player.global_transform, direction * probe):
				return
	_note("the player could not move in any direction from %s; stepping it clear" % str(_player.global_position))
	for radius in [0.6, 1.0, 1.6, 2.2]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := _player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if not _reaches(candidate):
				continue
			var clear := true
			for direction in directions:
				var placed := Transform3D(_player.global_transform.basis, candidate)
				if _player.test_move(placed, direction * probe):
					clear = false
					break
			if clear:
				_player.global_position = candidate
				_player.velocity = Vector3.ZERO
				# This script *is* the main loop (`extends SceneTree`): `physics_frame` is a
				# signal on `self`, and `get_tree()` does not exist here. Calling it was a
				# parse error, so the whole capture script failed to load and every capture
				# run since wrote nothing at all.
				await physics_frame
				await physics_frame
				_note("stepped the player to %s to start the mouse shots" % str(candidate))
				return
	_note("no clear spot within 2.2 m; the mouse shots start where the player stands")


## Whether the navigation map can actually take the player to this point.
##
## Without this a click can land on ground the map cannot reach: the navigator builds a
## short route to the nearest point it can reach, the character takes two steps and the
## capture reads that as a walk. Reachability is part of what a clickable floor point
## means, so it is checked before the click rather than after.
func _reaches(point: Vector3) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	if not map.is_valid():
		return false
	var route := NavigationServer3D.map_get_path(map, _player.global_position, point, true)
	if route.is_empty():
		return false
	return route[route.size() - 1].distance_to(point) <= 0.75


## Puts the real cursor on a target, and returns the screen position that resolves to it.
##
## `_screen_position_of()` projects the object's *origin*, which for a prop authored at the
## middle of its mesh can land a few pixels outside its own collision box — and the cursor
## ray then hits the wall behind it. Instead of guessing a pixel, the same question the click
## will ask is asked of a small ring of pixels around the projection, with a short poll
## because the controller resolves targets on its own cadence.
func _cursor_onto(target: Interactable) -> Vector2:
	if target == null:
		return Vector2.ZERO
	var centre := _screen_position_of(target)
	if centre == Vector2.ZERO:
		return Vector2.ZERO
	var rect := _player.get_viewport().get_visible_rect().size
	var offsets := [
		Vector2.ZERO, Vector2(0, -16), Vector2(0, 16), Vector2(-16, 0), Vector2(16, 0),
		Vector2(0, -32), Vector2(0, 32), Vector2(-32, 0), Vector2(32, 0),
	]
	for offset: Vector2 in offsets:
		var screen := Vector2(
			clampf(centre.x + offset.x, 1.0, rect.x - 1.0),
			clampf(centre.y + offset.y, 1.0, rect.y - 1.0)
		)
		Input.warp_mouse(screen)
		await process_frame
		if await _poll(
			func() -> bool:
				return _interaction.get_target_at_screen_position(screen, false) == target,
			0.25
		):
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
		# The camera trails the body and the visibility ray is cast from wherever it has got
		# to, so a teleport needs a frame or two before the object is under the cursor. One
		# check after a fixed sleep made this the flakiest step in the capture: give it half
		# a second instead of one frame, and only then move on to the next angle.
		if await _poll(
			func() -> bool:
				return _interaction.get_target_at_screen_position(
					_screen_position_of(target), false
				) == target,
			0.5
		):
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


## `NarrativeState` exposes `get_entries()`; there is no `get_entry_ids()`, so the older
## line here always reported -1.
func _knowledge_count() -> int:
	if _narrative == null or not _narrative.has_method("get_entries"):
		return -1
	return (_narrative.get_entries() as Array).size()


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
