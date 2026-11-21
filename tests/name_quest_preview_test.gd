extends SceneTree
## Runs the excluded scene with the real director, room swaps, presentation and files.
## Use a disposable Godot profile (see the preview README).

const Harness := preload("res://tests/test_harness.gd")
const PREVIEW := preload("res://scenes/dev/name_quest/name_quest.tscn")
const ENTRY := preload("res://scripts/dev/name_quest/preview.gd")
const QUEST := preload("res://scripts/dev/name_quest/opening.gd")
const LIVE_SAVE := SaveFileStore.SAVE_PATH
const LIVE_READ_LOG := ReadLog.DEFAULT_PATH
const LIVE_MARKER := &"name_quest_fixture_live_save"
const REVEAL := "\u5c24\u5947\u5965\uff08J\u00f3zio\uff09"

var _check := Harness.Checker.new()
var _state: Node
var _knowledge: Node
var _save: Node
var _preview: Node
var _main: Node
var _host: LocationHost
var _player: PlayerController
var _interaction: InteractionController
var _dialogue: DialogueController
var _panel: DialoguePanel
var _q: CompanionController
var _live_bytes: PackedByteArray
var _live_log := "production read-log fixture".to_utf8_buffer()
var _rolls := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 140.0, "name_quest_preview_test.gd")
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Engine.time_scale = 2.0
	if not _check.expect(not FileAccess.file_exists(LIVE_SAVE)
			and not FileAccess.file_exists(SaveFileStore.BROKEN_PATH)
			and not FileAccess.file_exists(LIVE_READ_LOG)
			and not DirAccess.dir_exists_absolute(ENTRY.SAVE_DIR)
			and SaveFileStore.new().stray_paths().is_empty(),
			"Use an empty, disposable Godot user directory for this test."):
		Harness.finish(self, _check.failures, "")
		return
	var state := Harness.ensure_state_autoloads(self)
	_state = state["game_state"]
	_knowledge = state["narrative_state"]
	_save = state["save"]
	_state.set_flag(LIVE_MARKER, true)
	var report: Dictionary = _save.save_game()
	_check.expect(report.get("ok", false), "Could not seed the live save sentinel.")
	_live_bytes = FileAccess.get_file_as_bytes(LIVE_SAVE)
	_check.expect(SaveFileStore.FileIO.new().write_bytes(LIVE_READ_LOG, _live_log) == OK,
		"Could not seed the read log sentinel.")

	for index in QUEST.RESPONSES.size():
		if not await _branch(index):
			break
		await _unmount()
		_clear_preview_files()
	await _unmount()
	_check.expect(not _live_bytes.is_empty() and _live_bytes == FileAccess.get_file_as_bytes(LIVE_SAVE)
		and _live_log == FileAccess.get_file_as_bytes(LIVE_READ_LOG)
		and not FileAccess.file_exists(SaveFileStore.BROKEN_PATH),
		"Preview touched the live save/read log or exposed it to recovery.")
	_check.expect(_save.io == null and not _save.writes_suspended(), "Preview left Save rebound.")
	_check.expect(_rolls == 0, "The archive lookup rolled a dice check.")
	_clear_preview_files()
	_save.forget_all()
	DirAccess.remove_absolute(LIVE_READ_LOG)
	Harness.finish(self, _check.failures,
		"Name quest: keyboard/mouse/pad responses, Q and solo archive routes, retries and isolated Continue.")


func _branch(index: int) -> bool:
	var reply := ["a", "b", "c"][index] as String
	Harness.stage = "dismissal, then response %s at the door" % reply
	if not await _mount():
		return false
	var door := _target(&"classroom_door") as LocationExit
	if not _check.expect(door != null and not door.is_open() and not _q.is_joined()
			and not _state.get_flag(LIVE_MARKER, false), "Preview read the live run or skipped the real dismissal."):
		return false
	# Drain the authored dialogue through the controller; never advance a preview card here.
	if not _check.expect(await Harness.wait_until(func() -> bool:
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		return _state.get_flag(StoryFlags.CLASS_DISMISSED, false) and _player.is_control_enabled(), 14.0),
		"N's authored dismissal did not finish."):
		return false
	var pause := _main.get_node(^"PauseMenu") as PauseMenu
	pause.open()
	_check.expect(not pause.get_entry(&"new_game").is_visible_in_tree()
		and not pause.get_entry(&"save_quit").is_visible_in_tree()
		and not pause.get_entry(&"settings").is_visible_in_tree(), "Preview exposes live session commands.")
	pause.close()

	if not await _settled(&"classroom"):
		return false
	var landing := _host.get_current().get_spawn(&"FromCorridor").global_position
	if not await _walk_to(landing, 18.0) or not await _use_in_reach(door):
		return false
	if not _check.expect(await _card(&"ask_title") and _room() == &"classroom"
			and not _player.is_control_enabled() and not _q.is_joined()
			and not _state.has_flag(QUEST.RESPONSE), "The name question did not hold the player inside the classroom."):
		return false
	_check.expect(_choice_count() == 3 and _body().is_empty(), "N's card must have exactly three choices and no line.")
	await _respond(index)
	if not await _settled(&"corridor"):
		return false
	_check.expect(_state.get_flag(QUEST.RESPONSE) == reply and _q.is_joined()
		and not _state.get_flag(StoryFlags.SKIPPED_CLASS, false)
		and not _knowledge.has_entry(QUEST.VERIFIED), "Response gave the wrong state, invented an answer or skipped the class.")
	for item: Interactable in _host.get_current().get_interactables():
		var outside := item as LocationExit
		if outside != null and outside.destination_id not in [&"classroom", &"archive"]:
			_check.expect(not outside.can_interact(), "Preview exposed an exit to %s." % outside.destination_id)
	if index == 1:
		return true
	if index == 2:
		return await _without_q(reply)

	Harness.stage = "return through the classroom without asking twice"
	_interaction.request_activation(_target(&"back_to_classroom"))
	if not await _settled(&"classroom"):
		return false
	_interaction.request_activation(_target(&"classroom_door"))
	if not await _settled(&"corridor"):
		return false
	_check.expect(not _panel.visible and _state.get_flag(QUEST.RESPONSE) == reply,
		"Returning to the classroom asked for a new response.")

	Harness.stage = "Q lead and independent announcement-board observation"
	# Q is solid, and the return door owns the prompt at its own threshold.
	# Step out beside him in the middle of the hall before turning to talk.
	if not await _walk_to(Vector3(0.45, 0, -5.1), 6.0) \
			or not await _walk_to(Vector3(0.45, 0, -3.0), 6.0):
		return false
	var q_target := _q.get_node_or_null(^"AskAboutTheRegister") as Interactable
	if not _check.expect(q_target != null and q_target.can_interact(), "The joined Q offers no follow-up."):
		return false
	if not await _use_in_reach(q_target) or not await _card(&"q_title"):
		return false
	_check.expect(not _knowledge.has_entry(QUEST.Q_CLUE), "An unasked follow-up already entered the log.")
	_pick(0)
	if not await _card(&"q_report"):
		return false
	_pick(0)
	var q_entry: NarrativeEntry = _knowledge.get_entry(QUEST.Q_CLUE)
	_check.expect(q_entry != null and q_entry.source == NarrativeEntry.Source.REPORTED
		and not q_target.can_interact(), "Q's clue is not a one-time report.")
	if not await _read_board():
		return false
	var board_entry: NarrativeEntry = _knowledge.get_entry(QUEST.BOARD_CLUE)
	_check.expect(board_entry != null and board_entry.source == NarrativeEntry.Source.OBSERVED
		and q_entry != null and board_entry.text == q_entry.text, "The board cannot corroborate the class/seat report.")
	return await _archive(reply, true)


func _respond(index: int) -> void:
	match index:
		0:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_1
			_tap(key)
		1:
			var button := _panel.get_choice_buttons()[1]
			if not _check.expect(await Harness.wait_until(func() -> bool:
				return button.get_global_rect().size.x > 32.0, 3.0), "Response B did not lay out its button."):
				return
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = button.get_global_rect().get_center()
			mouse.global_position = mouse.position
			_tap(mouse)
		2:
			var pad := InputEventJoypadButton.new()
			pad.button_index = JOY_BUTTON_DPAD_DOWN
			for _press in 3:
				if _panel.get_choice_cursor() == 2:
					break
				_tap(pad)
			_check.expect(_panel.get_choice_cursor() == 2, "The controller could not select response C.")
			pad.button_index = JOY_BUTTON_A
			_tap(pad)


func _tap(event: InputEvent) -> void:
	for pressed: bool in [true, false]:
		event.set(&"pressed", pressed)
		root.push_input(event)


func _archive(reply: String, with_q: bool) -> bool:
	Harness.stage = "real route downstairs, archive retries and proof gates (Q: %s)" % with_q
	if not await _walk_to_archive() or not await _use_in_reach(_target(&"to_archive")) \
			or not await _settled(&"archive"):
		return false
	if not with_q:
		# The normal arrival rule joins Q after dismissal. Detach him for
		# this fixture too, without giving the absence a canonical reason.
		_q.leave()
	var q_target := _q.get_node(^"AskAboutTheRegister") as Interactable
	_check.expect(_q.is_with_player() == with_q and not q_target.can_interact(),
		"Wrong presence for Q in the archive (expected present: %s), or corridor follow-up exposed." % with_q)
	_check.expect(not _state.get_flag(&"annex.archive.aligned", false), "Preview wrote a production threshold result.")
	_interaction.request_activation(_target(QUEST.ORIGINALS))
	if not await _card(&"original_title"):
		return false
	_check.expect(_choice_count() == 1 and not _knowledge.has_entry(QUEST.VERIFIED),
		"Unindexed originals offer an answer.")
	_pick(0)
	if not await _walk_to(Vector3(1.10, 0, -0.33), 10.0) \
			or not await _use_in_reach(_target(&"archive_detail")):
		return false
	if not await _card(&"class_title", true):
		return false
	var ledger: NarrativeEntry = _knowledge.get_entry(&"saw_archive_register")
	_check.expect(ledger != null and ledger.source == NarrativeEntry.Source.OBSERVED,
		"The lookup did not use the existing misfiled index inspection.")
	_pick(0)
	_check.expect(not _state.has_flag(QUEST.CLASS_INDEXED) and _choice_count() == 4,
		"A wrong class tab advanced or locked the task.")
	_pick(1)
	if not await _card(&"align_title"):
		return false
	_pick(2)
	_check.expect(not _state.has_flag(QUEST.REFERENCE) and _choice_count() == 4,
		"Disjoint pin holes accepted the copy.")
	_pick(3)

	Harness.stage = "resume between class lookup and alignment"
	await _unmount()
	if not await _mount() or not await _settled(&"archive"):
		return false
	_check.expect(_state.get_flag(QUEST.RESPONSE) == reply and _state.get_flag(QUEST.CLASS_INDEXED, false)
		and not _state.has_flag(QUEST.REFERENCE) and _knowledge.has_entry(QUEST.Q_CLUE) == with_q
		and _knowledge.has_entry(QUEST.BOARD_CLUE) and _q.is_joined() == with_q,
		"Continue changed the evidence or whether Q was following (expected present: %s)." % with_q)
	if not await _use_in_reach(_target(&"archive_detail")) or not await _card(&"align_title"):
		return false
	_pick(1)
	_pick(2)
	_check.expect(_state.get_flag(QUEST.REFERENCE) == "G4" and _choice_count() == 1,
		"Alignment did not derive the matching file reference.")
	_pick(0)

	Harness.stage = "walk to the original, reject decoys and reveal once (Q: %s)" % with_q
	var original := _target(QUEST.ORIGINALS)
	if not await _walk_to(Vector3(3.45, 0.0, -1.24), 10.0) or not await _use_in_reach(original) \
			or not await _card(&"original_title"):
		return false
	for decoy in [0, 1, 2]:
		_pick(decoy)
		_check.expect(not _knowledge.has_entry(QUEST.VERIFIED) and _choice_count() == 5 and REVEAL not in _body(),
			"A decoy revealed the name or blocked retry.")
	_pick(3)
	if not await _card(&"reveal_title", false, true):
		return false
	var found: NarrativeEntry = _knowledge.get_entry(QUEST.VERIFIED)
	_check.expect(_body() == REVEAL and found != null and found.source == NarrativeEntry.Source.OBSERVED,
		"The matched original does not display the selected name as an observation.")
	var font := (_panel.get_node(^"%BodyLabel") as RichTextLabel).get_theme_font(&"normal_font")
	_check.expect(font.has_char(REVEAL.unicode_at(2)), "The reveal font is missing its preview-only glyph.")
	_pick(0)
	await _unmount()
	if not await _mount() or not await _settled(&"archive"):
		return false
	_check.expect(not _panel.visible and _knowledge.has_entry(QUEST.VERIFIED),
		"The finished quest did not restore at rest.")
	if not await _use_in_reach(_target(QUEST.ORIGINALS)) or not await _card(&"reveal_title", false, true):
		return false
	_check.expect(_body() == REVEAL, "Could not re-read the verified original.")
	_pick(0)
	return true


func _without_q(reply: String) -> bool:
	Harness.stage = "no Q: the observed board can supply the lead on its own"
	var q_target := _q.get_node(^"AskAboutTheRegister") as Interactable
	_q.leave()
	_interaction.request_activation(q_target)
	_check.expect(not q_target.can_interact() and not _panel.visible and not _knowledge.has_entry(QUEST.Q_CLUE),
		"A non-following Q could still be questioned.")
	if not await _read_board():
		return false
	var board_entry: NarrativeEntry = _knowledge.get_entry(QUEST.BOARD_CLUE)
	_check.expect(board_entry != null and board_entry.source == NarrativeEntry.Source.OBSERVED
		and not _knowledge.has_entry(QUEST.Q_CLUE), "The solo lead required or fabricated a Q report.")
	return await _archive(reply, false)


func _read_board() -> bool:
	if not await _walk_to(Vector3(-0.58, 0, -2.05), 8.0) \
			or not await _use_in_reach(_target(&"noticeboard")) or not await _card(&"board_title", true):
		return false
	_pick(0)
	return true


func _walk_to_archive() -> bool:
	var hall := _host.get_current()
	var hub := hall.get_node(^"TeachingBlock/RearStair/Junction") as Node3D
	var turn := hall.get_node(^"TeachingBlock/RearStair/DownLanding") as Node3D
	# Walk the same staircase stances as corridor_art_test, not one click
	# across two storeys. Keep the physics clock at normal speed on the ramps.
	return await _walk_to(hub.global_position, 8.0) \
		and await _walk_to(turn.global_position, 8.0) \
		and await _walk_to(Vector3(-11.4, -3.4, 12.6), 10.0) \
		and await _walk_to(hall.get_spawn(&"FromArchive").global_position, 6.0)


func _mount() -> bool:
	_preview = PREVIEW.instantiate()
	root.add_child(_preview)
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _preview.has_node(^"Main/Companion/AskAboutTheRegister"), 12.0), "Preview failed to boot."):
		return false
	_main = _preview.get_node(^"Main")
	_host = _main.get_node(^"LocationHost") as LocationHost
	_player = _main.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_interaction.mouse_targeting = false
	_q = _main.get_node(^"Companion") as CompanionController
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_dialogue.check_resolved.connect(func(_result: Dictionary) -> void: _rolls += 1)
	_panel = (_main.get_node(^"GameUI") as GameUI).dialogue_panel
	return true


func _unmount() -> void:
	if not is_instance_valid(_preview):
		return
	AudioRelease.stop_all(_preview.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(_preview.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	_preview.queue_free()
	await Harness.wait_until(func() -> bool: return not is_instance_valid(_preview), 5.0)
	_state.clear()
	_knowledge.clear()


func _clear_preview_files() -> void:
	for name: String in DirAccess.get_files_at(ENTRY.SAVE_DIR):
		DirAccess.remove_absolute(ENTRY.SAVE_DIR.path_join(name))
	DirAccess.remove_absolute(ENTRY.SAVE_DIR)


func _room() -> StringName:
	var location := _host.get_current()
	return location.location_id if location != null else &""


func _target(id: StringName) -> Interactable:
	return _host.get_current().find_interactable(id)


func _settled(room: StringName) -> bool:
	return _check.expect(await Harness.wait_until(func() -> bool:
		return _room() == room and _player.is_control_enabled() and _player.is_on_floor() \
			and (_host.get_current().get_node(^"Navigation") as LocationNavigation).is_routable(), 14.0),
		"Did not settle in '%s' (%s)." % [room, Harness.stage])


func _walk_to(feet: Vector3, limit: float) -> bool:
	var scale := Engine.time_scale
	Engine.time_scale = 1.0
	var start := _player.global_position
	var accepted := _player.request_path_to(feet)
	var route := _player.get_path_legs()
	var stopped := accepted and await Harness.wait_until(func() -> bool:
		return not _player.is_path_active() and _player.is_on_floor(), limit)
	Engine.time_scale = scale
	return _check.expect(stopped and _player.global_position.distance_to(feet) < 0.65,
		"Walk from %s to %s stopped at %s; accepted=%s; path=%s (%s)." % [
			start, feet, _player.global_position, accepted, route, Harness.stage,
		])


func _use_in_reach(target: Interactable) -> bool:
	if not _check.expect(target != null and target.can_interact() and _interaction.is_in_reach(target)
			and _interaction.has_line_of_sight(target), "Could not reach %s from %s (%s)." % [
				target.interact_id if target != null else "missing target", _player.global_position, Harness.stage,
			]):
		return false
	_player.face_toward(target.global_position - _player.global_position)
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _interaction.get_current_target() == target, 3.0),
		"No keyboard prompt for %s from %s; got %s (%s)." % [
			target.interact_id, _player.global_position, _interaction.get_current_target(), Harness.stage,
		]):
		return false
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
	return true


func _card(key: StringName, drain_inspection: bool = false, reveal_ok: bool = false) -> bool:
	var director := _main.get_node(^"OpeningSequence") as QUEST
	var title := String(director.cards[String(key)])
	var visible := await Harness.wait_until(func() -> bool:
		if drain_inspection and _dialogue.get_mode() == DialogueController.Mode.INSPECTION:
			_dialogue.advance_presentation()
		return _panel.is_visible_in_tree() and _panel.has_choices() \
			and (_panel.get_node(^"%TitleLabel") as Label).text == title, 4.0)
	return _check.expect(visible and (reveal_ok or REVEAL not in _body()),
		"Card '%s' missing or revealed the name too early (%s)." % [key, Harness.stage])


func _pick(index: int) -> void:
	# Fire the real panel button (backed by choice_selected), not the quest's handler.
	var buttons := _panel.get_node(^"%ChoicesContainer")
	if _check.expect(index < buttons.get_child_count(), "Choice %d is missing (%s)." % [index, Harness.stage]):
		(buttons.get_child(index) as Button).pressed.emit()


func _choice_count() -> int:
	return _panel.get_node(^"%ChoicesContainer").get_child_count()


func _body() -> String:
	return (_panel.get_node(^"%BodyLabel") as RichTextLabel).text
