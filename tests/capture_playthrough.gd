extends SceneTree
## Drives the real game in a real window and photographs the flows that matter.
##
## This is not a headless assertion suite: it runs under Xvfb with a real viewport
## (the CI runner uses the Dummy audio driver, so sound is not being tested),
## presses real keys through the input system, and saves what the player would see
## to a fresh evidence directory. Failures are written next to the screenshots (a FAIL_*.png
## of the moment it stopped plus PLAYTHROUGH.log) so a broken build leaves evidence
## instead of a stack trace.
##
## Interaction, dialogue advance, choice selection and the language switch all go
## through simulated key events, exactly as a player would produce them. Walking
## between scenes is shortened with teleports so the capture stays inside the CI
## budget; the movement itself is exercised once, with a held key, and reported in
## the log.

const Harness = preload("res://tests/test_harness.gd")
## CI sets an isolated absolute directory; local captures use a fresh user:// directory.
var _shot_dir: String = OS.get_environment("CAPTURE_DIR")


func _output_path(filename: String) -> String:
	return _shot_dir.path_join(filename)

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
	if _shot_dir.is_empty():
		var base := "user://playthrough-captures/%d" % int(Time.get_unix_time_from_system())
		_shot_dir = base
		var suffix := 0
		while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_shot_dir)):
			suffix += 1
			_shot_dir = "%s-%d" % [base, suffix]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
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
	if _dialogue == null or _host == null or _player == null or _ui == null or _panel == null or _interaction == null:
		await _fail("main scene did not expose its core nodes and dialogue panel")
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
			await _press(KEY_E)
			if await _wait_for_line(5.0):
				await _wait(0.6)
				await _shot("10_conversation_chinese", "A conversation line in Chinese, opened with E.")
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
		await _press(KEY_E)
		if await _wait_for_location("corridor", 40.0):
			await _wait(1.2)
			await _shot("13_corridor", "The walkway outside the classroom.")
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
			var alley := flats.find_interactable(&"res_alley_end")
			if alley == null:
				_failures.append("The alley exit is missing.")
			elif await _travel(&"res_alley_end", Vector3(6.0, 0, -31.6), 0.0, "estate_passage"):
				await _shot("20_estate_exit", "The open space outside the estate gate.")
				if await _travel(&"estate_to_playground", Vector3(0, 0, -8.0), 0.0, "playground"):
					await _shot("21_playground", "The playground: open space and independent landmarks.")
					await _wait_for_free(30.0)
					_teleport(Vector3(-10, 0, 0.8), 0.0)
					if not await _wait_for_target(&"pg_bench", 30.0):
						_failures.append("The playground bench prompt was not offered.")
					else:
						await _press(KEY_E)
						if await _poll(func() -> bool: return _dialogue.has_pending_choices(), 10.0):
							await _shot("22_active_choices", "An optional ability choice with rating and target.")
							await _press(KEY_1)
							if await _poll(func() -> bool: return not String(_dialogue.get_current_line().get("title", "")).is_empty(), 10.0):
								if await _wait_for_line(20.0):
									_note("active result text fully revealed before capture")
									await _shot("23_active_result", "The visible die, ability, target and fully revealed result.")
								else:
									_failures.append("The active roll result never finished revealing.")
							else:
								_failures.append("The active roll result did not appear.")
						else:
							_failures.append("The ability choices did not appear.")
						await _drive_until(func() -> bool: return not _dialogue.is_busy(), 30.0, "the bench thought")
					await _press(KEY_L)
					await _wait_for_free(30.0)
					_teleport(Vector3(10, 0, -4.5), 0.0)
					if await _wait_for_target(&"pg_notice", 30.0):
						await _press(KEY_E)
						if await _poll(func() -> bool: return _dialogue.has_pending_choices(), 10.0):
							if _panel.get_speaker_text() != L10n.t("speaker.protagonist"):
								_failures.append("The protagonist label did not switch to Chinese.")
							await _shot("24_active_choices_chinese", "The same ability interface in simplified Chinese.")
							await _drive_until(func() -> bool: return not _dialogue.is_busy(), 30.0, "the notice thought")
						else:
							_failures.append("The Chinese ability choices did not appear.")
					else:
						_failures.append("The notice board prompt was not offered.")
					await _press(KEY_L)
					await _wait_for_free(30.0)
					_teleport(Vector3(8, 0, 4.4), 0.0)
					if await _wait_for_target(&"pg_hoop", 30.0):
						await _shot("25_practice_ring", "The practice ring is another independent landmark.")
					else:
						_failures.append("The practice ring prompt was not offered.")
					_teleport(Vector3(12, 0, -10.4), 0.0)
					if not await _wait_for_target(&"pg_finish", 30.0):
						_failures.append("The optional end-of-build prompt was not offered.")
					else:
						await _press(KEY_E)
						if await _wait_for_visible(_ui.end_card, 20.0):
							await _wait(0.6)
							await _shot("20_end_card", "The optional end card, beyond the open playground.")
						else:
							_failures.append("The end-of-build card did not appear.")

	# 10. A final state dump so the log can be read without the screenshots.
	_note("current location: %s" % String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "<none>")))
	_note("locale: %s, objective: %s" % [L10n.current, _ui.hud.get_objective_key()])
	_note("recorded knowledge entries: %d" % int(_narrative.get_entry_ids().size() if _narrative.has_method("get_entry_ids") else -1))
	_note("screenshots written: %d" % _shot_index)

	if _failures.is_empty():
		_note("RESULT: the playthrough reached the end of the built content.")
	else:
		for failure: String in _failures:
			_note("FAILURE: %s" % failure)
		await _shot("FAIL_last_frame", "The last frame before the capture stopped.")
	if not _write_log():
		_failures.append("Could not write the capture log or index.")
	if _failures.is_empty():
		print("CAPTURE_RESULT: PASS")
	else:
		print("CAPTURE_RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)


## Crosses a threshold via the real interaction input. Teleports only shorten
## the walking portion; a missing prompt or failed transition remains a failure.
func _travel(id: StringName, position: Vector3, yaw: float, destination: String) -> bool:
	if not await _wait_for_free(30.0):
		return false
	_teleport(position, yaw)
	if not await _wait_for_target(id, 30.0):
		_failures.append("No prompt for %s." % id)
		return false
	await _press(KEY_E)
	if not await _wait_for_location(destination, 40.0):
		_failures.append("Transition to %s did not finish." % destination)
		return false
	return await _wait_for_free(40.0)


# --- input ------------------------------------------------------------------


## A real key press through the input system, the same path a player's keyboard
## takes: down and up as separate events, one frame apart.
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
	var texture := root.get_texture()
	if texture == null:
		_failures.append("No viewport texture was available for screenshot %s." % shot_name)
		return
	var image: Image = texture.get_image()
	if image == null:
		_failures.append("No image was available for screenshot %s." % shot_name)
		return
	var path := _output_path("%s.png" % shot_name)
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
	print("CAPTURE_RESULT: FAIL")
	quit(1)


func _note(message: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), message]
	_log_lines.append(line)
	print("CAPTURE %s" % line)


func _write_log() -> bool:
	var log_path := _output_path("PLAYTHROUGH.log")
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % log_path)
		return false
	file.store_string("\n".join(_log_lines) + "\n")
	file.close()
	# A Markdown index, so the pull request can show the frames with their captions.
	var markdown := PackedStringArray()
	markdown.append("# Playthrough screenshots")
	markdown.append("")
	markdown.append("Captured by `tests/capture_playthrough.gd` in a real Godot window under")
	markdown.append("Xvfb (`--rendering-driver opengl3`, 1600x900; Dummy audio). Interaction, dialogue")
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
	var markdown_file := FileAccess.open(_output_path("PLAYTHROUGH.md"), FileAccess.WRITE)
	if markdown_file == null:
		return false
	markdown_file.store_string("\n".join(markdown) + "\n")
	markdown_file.close()
	return true
