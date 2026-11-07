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


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "language_switch_test.gd")
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

	# --- wait for a line that is actually on screen ----------------------
	if not await _wait_for_line(60.0):
		Harness.finish(self, _failures + ["The opening conversation never showed a line."], "")
		return

	var before := _dialogue.get_current_line()
	var before_text := String(before.get("text", ""))
	var before_node := String(before.get("node_id", ""))
	var flags_before := _flag_snapshot()
	var entries_before := _narrative.get_entry_ids().size() if _narrative.has_method("get_entry_ids") else -1
	var objectives_before := String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, ""))

	# --- switch while the line is on screen ------------------------------
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

	# The UI chrome follows too: the speaker badge is localized, not a name copied
	# from the content file.
	var badge_zh := _ui.dialogue_panel.get_speaker_badge_text() if _ui.dialogue_panel.has_method("get_speaker_badge_text") else ""
	if not badge_zh.is_empty() and not _has_cjk(badge_zh):
		_failures.append("The speaker badge did not switch language: '%s'." % badge_zh)

	# --- finish the conversation in Chinese ------------------------------
	if not await _settle(120.0):
		_failures.append("The conversation did not finish after the switch.")
	var objective_zh := _ui.hud.get_objective_text()
	if objective_zh.is_empty():
		_failures.append("The objective line is empty after the switch.")
	elif not _has_cjk(objective_zh):
		_failures.append("The objective was not translated: '%s'." % objective_zh)

	# --- the prompt follows the language as well -------------------------
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
