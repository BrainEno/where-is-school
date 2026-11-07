extends SceneTree
## Switches the display language in the middle of the real game and proves nothing
## is lost: the line on screen is re-rendered from the same node id, the objective,
## prompt and backlog follow, story flags and knowledge entries are untouched, and
## interaction still works afterwards.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _ui: GameUI = null
var _game_state: Node = null
var _narrative: Node = null
var _loc: Node = null
## Every check the session resolved. A language switch must not add one: a re-render
## is not a new roll.
var _check_events: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 420.0, "language_switch_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	Harness.clear_session_state(self)
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if _loc == null:
		Harness.finish(self, ["The Loc autoload could not be created."], "")
		return
	_loc.set_locale("en")

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
	if _dialogue == null or _host == null or _player == null or _ui == null or _interaction == null:
		Harness.finish(self, ["Main did not expose its core nodes."], "")
		return

	Engine.time_scale = 3.0
	_dialogue.check_resolved.connect(_on_check_resolved)

	# --- wait for a line that is actually on screen ----------------------
	Harness.stage = "waiting for the opening line"
	if not await _wait_for_line(60.0):
		Harness.finish(self, _failures + ["The opening conversation never showed a line."], "")
		return

	var before := _dialogue.get_current_line()
	var before_text := String(before.get("text", ""))
	var before_node := String(before.get("node_id", ""))
	var flags_before := _flag_snapshot()
	var entries_before: int = -1
	if _narrative.has_method("get_entry_ids"):
		entries_before = int(_narrative.get_entry_ids().size())
	var objectives_before := String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, ""))
	# Issue #18 was exactly this: the log grew a row every time the language changed.
	var log_before := _backlog_snapshot()
	var checks_before := _check_events

	# --- switch while the line is on screen ------------------------------
	Harness.stage = "the mid-line language switch"
	checks_before = _check_events
	if not _loc.set_locale("zh-CN"):
		_failures.append("Loc refused to switch to zh-CN.")
	await process_frame
	await process_frame

	var after := _dialogue.get_current_line()
	if String(after.get("node_id", "")) != before_node:
		_failures.append("The language switch moved the conversation to another node.")
	if String(after.get("text", "")) == before_text:
		_failures.append("The line on screen was not re-rendered in the new language.")
	if not _has_cjk(String(after.get("text", ""))):
		_failures.append("The re-rendered line is not Chinese: '%s'." % after.get("text", ""))
	if not _ui.dialogue_panel.visible:
		_failures.append("The dialogue panel closed when the language changed.")
	if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != objectives_before:
		_failures.append("The objective changed value during a language switch.")
	if _flag_snapshot() != flags_before:
		_failures.append("Story flags changed during a language switch.")
	if _narrative.has_method("get_entry_ids") and _narrative.get_entry_ids().size() != entries_before:
		_failures.append("Knowledge entries changed during a language switch.")
	_assert_log_unchanged("Switching language mid-conversation", log_before)
	if _check_events != checks_before:
		_failures.append("A language switch re-ran %d check(s)." % (_check_events - checks_before))
	var speaker_zh := _ui.dialogue_panel.get_speaker_text()
	if speaker_zh.is_empty():
		_failures.append("The panel lost the speaker name during the language switch.")

	# The UI chrome follows too: the speaker badge is localized, not a name copied
	# from the content file.
	var badge_zh := _ui.dialogue_panel.get_speaker_badge_text() if _ui.dialogue_panel.has_method("get_speaker_badge_text") else ""
	if not badge_zh.is_empty() and not _has_cjk(badge_zh):
		_failures.append("The speaker badge did not switch language: '%s'." % badge_zh)

	# --- finish the conversation in Chinese ------------------------------
	Harness.stage = "finishing the conversation in Chinese"
	if not await _settle(120.0):
		_failures.append("The conversation did not finish after the switch.")
	var objective_zh := _ui.hud.get_objective_text()
	if objective_zh.is_empty():
		_failures.append("The objective line is empty after the switch.")
	elif not _has_cjk(objective_zh):
		_failures.append("The objective was not translated: '%s'." % objective_zh)

	# --- the prompt follows the language as well -------------------------
	Harness.stage = "the prompt after the switch"
	var classroom := _host.get_current()
	var bag := classroom.find_interactable(&"schoolbag") if classroom != null else null
	if bag == null:
		_failures.append("The schoolbag interactable is missing.")
	else:
		_player.teleport(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.55, 0, 1.7)))
		await physics_frame
		await physics_frame
		var prompt_zh := _ui.hud.get_prompt_text()
		if prompt_zh.strip_edges().is_empty():
			_failures.append("No prompt was shown after the language switch.")
		elif not _has_cjk(prompt_zh):
			_failures.append("The interaction prompt was not translated: '%s'." % prompt_zh)

		# --- and interaction still works after switching -----------------
		_interaction.request_activation(bag)
		await process_frame
		if not _dialogue.is_busy():
			_failures.append("Interaction stopped working after a language switch.")
		else:
			var inspection_text := String(_dialogue.get_current_line().get("text", ""))
			if not _has_cjk(inspection_text):
				_failures.append("Inspecting after the switch showed English text.")
		await _settle(60.0)

	# --- issue #18: inspection variants keep their identity -------------
	Harness.stage = "the set square first read"
	# The controller queue for an inspection is: the observation, then the separate
	# recollection. Both are recorded, both must survive any number of switches, and
	# neither may be confused with the other.
	if not _dialogue.present_inspection(&"classroom_set_square"):
		_failures.append("The set square inspection could not be presented.")
	else:
		await _settle(25.0)
		print("PROGRESS: first read of the set square is on screen; log=%d" % _ui.backlog.get_entry_count())
		# A passive voice speaking between two snapshots would be a real new event, not
		# a duplicate, and would make the "nothing was added" assertions lie. The section
		# is about the log, so the voices are parked here rather than being muted in the
		# assertions.
		var voice := _main.get_node_or_null("InnerVoiceDirector")
		if voice != null:
			voice.set_process(false)
		var log_first_read := _backlog_snapshot()
		var checks_at_inspection := _check_events
		if not bool(_game_state.get_flag(&"saw_set_square", false)):
			_failures.append("The first read of the set square did not set its flag.")
		var flags_after_first_read := _flag_snapshot()
		var entries_after_first_read: int = _narrative.get_entry_ids().size()
		var identities: PackedStringArray = log_first_read["identities"]
		if not identities.has("inspection:classroom_set_square/first"):
			_failures.append("The first read is not identified as a first read.")
		if not identities.has("inspection:classroom_set_square/recall"):
			_failures.append("The recollection is not identified as a recollection.")
		var recall_index := identities.find("inspection:classroom_set_square/recall")
		if recall_index < 0:
			_failures.append("The recollection is missing from the log.")
		else:
			var recall_text := String((log_first_read["texts"] as PackedStringArray)[recall_index])
			if not _has_cjk(recall_text):
				_failures.append("The recollection was not shown in Chinese: '%s'." % recall_text)

		Harness.stage = "the log round trips"
		# zh -> en -> zh -> en -> zh: the log keeps every row, in order, and ends up
		# with exactly the text it had the first time it was Chinese.
		for round_index in 2:
			if not _loc.set_locale("en"):
				_failures.append("Loc refused to switch to English (round %d)." % round_index)
				break
			await process_frame
			await process_frame
			_assert_log_unchanged("Switching to English (round %d)" % round_index, log_first_read)
			if _count_cjk_texts(_backlog_snapshot()["texts"]) != 0:
				_failures.append("The log kept Chinese text after switching to English.")
			if _check_events != checks_at_inspection:
				_failures.append("A language switch re-ran a check.")
			if not _loc.set_locale("zh-CN"):
				_failures.append("Loc refused to switch to Chinese (round %d)." % round_index)
				break
			await process_frame
			await process_frame
			var again := _backlog_snapshot()
			print("PROGRESS: round %d back in Chinese, log=%d" % [round_index, int(again["count"])])
			_assert_log_unchanged("Switching back to Chinese (round %d)" % round_index, log_first_read)
			if again["texts"] != log_first_read["texts"]:
				_failures.append("The rebuilt log differs from the first Chinese render.")
		if _flag_snapshot() != flags_after_first_read:
			_failures.append("A language switch changed a story flag.")
		if _narrative.get_entry_ids().size() != entries_after_first_read:
			_failures.append("A language switch added or removed a knowledge entry.")
		if _check_events != checks_at_inspection:
			_failures.append("A language switch re-ran a check after the recollection.")

		Harness.stage = "the repeat read"
		# Reading the same object again is a *new* event: same content, different
		# variant, and it must append rather than replace.
		if not _dialogue.present_inspection(&"classroom_set_square"):
			_failures.append("The set square inspection could not be repeated.")
		else:
			await _settle(25.0)
			var log_repeat := _backlog_snapshot()
			if int(log_repeat["count"]) != int(log_first_read["count"]) + 1:
				_failures.append(
					"Reading the set square again did not add exactly one row (%d -> %d)."
					% [int(log_first_read["count"]), int(log_repeat["count"])]
				)
			if not (log_repeat["identities"] as PackedStringArray).has("inspection:classroom_set_square/repeat"):
				_failures.append("The second read is not identified as a repeat read.")
			if _narrative.get_entry_ids().size() != entries_after_first_read:
				_failures.append("A repeat read recorded knowledge again.")
			# ... and it survives a round trip as its own row.
			_loc.set_locale("en")
			await process_frame
			await process_frame
			_loc.set_locale("zh-CN")
			await process_frame
			await process_frame
			_assert_log_unchanged("Switching after a repeat read", log_repeat)
			var repeat_text := String((_backlog_snapshot()["texts"] as PackedStringArray)[int(log_repeat["count"]) - 1])
			if not _has_cjk(repeat_text):
				_failures.append("The repeat read was not re-rendered in Chinese: '%s'." % repeat_text)

	# --- the conversation history is localised too ----------------------
	Harness.stage = "the final language check"
	var conversation_texts: PackedStringArray = _backlog_snapshot()["texts"]
	for index in conversation_texts.size():
		if _has_cjk(String(conversation_texts[index])) and _loc.get_locale() == "en":
			_failures.append("A backlog row stayed Chinese in English: '%s'." % conversation_texts[index])
			break

	# --- and switching back is also safe --------------------------------
	if not _loc.set_locale("en"):
		_failures.append("Loc refused to switch back to English.")
	await process_frame
	await process_frame
	var back_prompt := _ui.hud.get_prompt_text()
	if _has_cjk(back_prompt):
		_failures.append("The prompt stayed Chinese after switching back: '%s'." % back_prompt)
	if _has_cjk(_ui.hud.get_objective_text()):
		_failures.append("The objective stayed Chinese after switching back.")

	Engine.time_scale = 1.0
	_loc.set_locale("en")
	_main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "the game switches language mid-scene without losing state.")


# --- helpers ----------------------------------------------------------------


func _backlog_snapshot() -> Dictionary:
	var backlog := _ui.backlog
	return {
		"count": backlog.get_entry_count(),
		"identities": backlog.get_entry_identities(),
		"texts": backlog.get_entry_texts(),
	}


## The log must keep every row and its order; only the words may change.
func _assert_log_unchanged(label: String, before: Dictionary) -> void:
	var after := _backlog_snapshot()
	if int(after["count"]) != int(before["count"]):
		_failures.append(
			"%s: the backlog holds %d rows instead of %d."
			% [label, int(after["count"]), int(before["count"])]
		)
	if after["identities"] != before["identities"]:
		_failures.append("%s: the backlog changed identity or order." % label)


func _count_cjk_texts(texts: PackedStringArray) -> int:
	var count := 0
	for text in texts:
		if _has_cjk(String(text)):
			count += 1
	return count


func _on_check_resolved(_result: Dictionary) -> void:
	_check_events += 1


func _has_cjk(text: String) -> bool:
	for index in text.length():
		var code := text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false


func _flag_snapshot() -> Dictionary:
	var snapshot := {}
	for flag: StringName in [
		StoryFlags.MET_Q, StoryFlags.ASKED_Q_IDENTITY, StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG, StoryFlags.N_ARRIVED,
		StoryFlags.CLASS_DISMISSED,
	]:
		snapshot[String(flag)] = _game_state.get_flag(flag, null)
	return snapshot


func _wait_for_line(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if _dialogue.is_busy() and not String(_dialogue.get_current_line().get("text", "")).is_empty():
			return true
		await process_frame
	return false


func _settle(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if not _dialogue.is_busy() and _player.is_control_enabled():
			return true
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	return false
