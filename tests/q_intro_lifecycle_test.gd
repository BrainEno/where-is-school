extends Node
## #160 integration checks, invoked by the registered opening_resume test.
## No new test workflow or production seam: real Q beat, interaction dispatcher,
## dialogue controller, Session's save refusal, disk checkpoint and world teardown.
## The wake/seat composition is owned by #121/#159; the Q beat must preserve any
## seated pose those owners give it, rather than issuing its own get-up command.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SAVE_PATH := "user://save.json"

var failures: Array[String] = []
var _state: Node
var _narrative: Node
var _save: Node
var _session: Node
var _world: Node
var _sequence: OpeningSequence
var _dialogue: DialogueController
var _player: PlayerController
var _interaction: InteractionController
var _room: LocationRoot
var _played: Array[StringName] = []
var _lines: Array[StringName] = []


func run() -> void:
	_state = get_node(^"/root/GameState")
	_narrative = get_node(^"/root/NarrativeState")
	_save = get_node(^"/root/Save")
	_session = Harness.ensure_autoload(get_tree(), "Session", "res://scripts/ui/game_session.gd")
	Harness.clear_session_state(get_tree())
	await _interrupted_checkpoint()
	await _completed_checkpoint()
	await _authored_landing_and_seat()
	await _release_world()
	Harness.clear_session_state(get_tree())
	print("::notice title=Q intro lifecycle::interrupted and completed disk checkpoints, "
		+ "repeat interactions in both locales, and an authored Q landing/held seat checked; "
		+ "%d problem(s)." % failures.size())


func _boot() -> bool:
	_world = (load(MAIN) as PackedScene).instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	get_tree().root.add_child(_world)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_player = _world.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_room = (_world.get_node(^"LocationHost") as LocationHost).get_current()
	var voices := _world.get_node_or_null(^"InnerVoiceDirector")
	if voices != null:
		voices.set_process(false)
	_played.clear()
	_lines.clear()
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _played.append(id))
	_dialogue.line_presented.connect(func(line: Dictionary) -> void: _lines.append(line["node_id"]))
	_sequence.allow_player_control()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	await _frames(3)
	_expect(_room != null, "Q fixture did not enter the classroom.")
	return _room != null


## MET_Q is written by the first line, but a player cannot persist that half-read
## state: the pause-menu save route must refuse and keep the last checkpoint's
## bytes. Destroying the world mid-line then proves the next boot has not skipped Q.
func _interrupted_checkpoint() -> void:
	Harness.stage = "Q: interrupted introduction keeps the previous checkpoint"
	if not await _boot():
		return
	var written: Dictionary = _sequence.autosave("wake")
	_expect(written.get("ok", false), "The pre-Q checkpoint was not written.")
	var before := FileAccess.get_file_as_bytes(SAVE_PATH)
	var actor := _room.find_actor(&"q")
	if actor == null:
		_expect(false, "The Q actor is missing.")
		return
	var initial := actor.global_position
	_sequence._beat_q_wake()
	_expect(not _player.is_control_enabled() and not _interaction.is_enabled(),
		"Q's approach did not acquire the beat lock before the first line.")
	_interaction.request_activation(_room.find_interactable(&"q_talk"))
	_expect(_played.is_empty(), "An early interaction bypassed Q's locked approach.")
	if not await _wait_for_q():
		return
	_expect(bool(_state.get_flag(StoryFlags.MET_Q, false)), "Q's first line no longer sets MET_Q.")
	_check_arrival(actor, initial)
	_expect(not _player.is_control_enabled() and not _interaction.is_enabled(),
		"The Q conversation failed to hold the existing control/interaction lock.")
	var refused: Dictionary = await _session.save_and_quit(true, _world)
	_expect(not bool(refused.get("ok", true)) and refused.get("reason") == "not_at_rest",
		"Save and quit accepted a half-read Q intro: %s." % str(refused))
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == before,
		"Refusing a mid-intro save changed the checkpoint bytes.")
	_interaction.request_activation(_room.find_interactable(&"q_talk"))
	await _frames(2)
	_expect(_played == [&"q_wake"], "An interaction interrupted/duplicated the locked Q intro.")
	# Re-rendering a first line in another locale is not another meeting/event.
	var old_node := _dialogue.get_runtime().get_current_node_id()
	_dialogue.apply_locale("en")
	_dialogue.apply_locale("zh-CN")
	_expect(_dialogue.get_runtime().get_current_node_id() == old_node,
		"Switching locale moved the Q intro to a different node.")
	await _release_world()
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == before,
		"Tearing down an interrupted conversation overwrote its checkpoint.")
	if not await _boot():
		return
	_expect(not bool(_state.get_flag(StoryFlags.MET_Q, false)),
		"The interrupted first-line meeting leaked into the restored checkpoint.")
	_expect(_sequence.next_step() == &"wake", "The pre-Q checkpoint skipped the pending intro.")
	_sequence._beat_q_wake()
	if await _wait_for_q():
		await _finish_lines()
	_expect(_played == [&"q_wake"], "Restoring the interrupted checkpoint skipped or duplicated Q.")


## This is the real q_wake boundary checkpoint, not just a synthetic MET_Q map.
## Old saves already carry MET_Q; keeping its meaning and using it in routing needs
## no renamed flag or new save version. Both locales go through the real dispatcher.
func _completed_checkpoint() -> void:
	Harness.stage = "Q: completed introduction restores into the short studying reply"
	if _world == null or _dialogue.is_busy():
		_expect(false, "The introduction did not finish before the completed checkpoint check.")
		return
	_expect(_player.is_control_enabled() and _interaction.is_enabled() and not _sequence.is_beat_active(),
		"Q's ending did not release the beat and restore control.")
	_expect(not bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false))
		and not bool(_state.get_flag(StoryFlags.LEFT_CLASSROOM, false)),
		"Q's ending advanced to dismissal or departure.")
	await _repeat_in_both_locales()
	var written: Dictionary = _sequence.autosave("q_wake")
	_expect(written.get("ok", false), "The completed Q checkpoint was not written.")
	await _release_world()
	if not await _boot():
		return
	_expect(_sequence.next_step() == &"bag", "Restoring the Q boundary wants to replay the introduction.")
	_expect(ConversationRouter.select(&"q", _state.get_snapshot()) == &"q_studying",
		"The completed/legacy MET_Q save still routes to the long introduction.")
	await _repeat_in_both_locales()
	_played.clear()
	await _sequence._beat_q_wake()
	_expect(_played.is_empty(), "Re-entering a completed Q beat replayed the introduction.")
	await _story_priority()
	await _release_world()
	Harness.clear_session_state(get_tree())


func _story_priority() -> void:
	_state.set_flag(StoryFlags.TEXTBOOK_MISSING, true)
	for want: StringName in [&"q_after_bag", &"q_after_dismissal"]:
		if want == &"q_after_dismissal":
			_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
		_played.clear()
		_interaction.request_activation(_room.find_interactable(&"q_talk"))
		await _frames(1)
		_expect(_dialogue.is_busy() and _dialogue.get_runtime().get_active_conversation_id() == want,
			"The studying reply overrode the later story route '%s'." % want)
		await _finish_lines()
		_expect(_played == [want], "The later Q story started an unexpected conversation.")


func _repeat_in_both_locales() -> void:
	for locale: String in ["zh-CN", "en"]:
		_dialogue.apply_locale(locale)
		_played.clear()
		_lines.clear()
		var flags: Dictionary = _state.get_snapshot()
		var entries: int = _narrative.get_entries().size()
		_interaction.request_activation(_room.find_interactable(&"q_talk"))
		await _frames(1)
		_expect(_dialogue.is_busy() and _dialogue.get_runtime().get_active_conversation_id() == &"q_studying",
			"%s: re-interacting with Q did not enter q_studying." % locale)
		await _finish_lines()
		_expect(_played == [&"q_studying"] and _lines.size() >= 1 and _lines.size() <= 2,
			"%s: repeat interaction replayed the long greeting (%s / %d lines)."
			% [locale, str(_played), _lines.size()])
		_expect(_state.get_snapshot() == flags and _narrative.get_entries().size() == entries,
			"%s: the studying reply rewrote progress, choices, objectives or knowledge." % locale)


## The optional landing belongs to the classroom author (#159). Alter only this
## runtime fixture: the product must use the supplied point, face the protagonist,
## carry QTalk with Q, and leave the protagonist's seated pose alone throughout.
func _authored_landing_and_seat() -> void:
	Harness.stage = "Q: authored landing and held seated pose"
	if not await _boot():
		return
	var marker := Marker3D.new()
	marker.name = "QOpeningTalk"
	_room.add_child(marker)
	# Intentionally distinct from the default 1.25 m fallback: ignoring the
	# authored marker must fail this check, not accidentally land on the same point.
	marker.global_position = _player.global_position + _player.get_facing_direction()
	var actor := _room.find_actor(&"q")
	if actor == null:
		_expect(false, "The marker fixture has no Q actor.")
		return
	var initial := actor.global_position
	_player.set_wake_pose(1.0)
	var tilt := _player.visual.rotation.x
	_sequence._beat_q_wake()
	if await _wait_for_q():
		_check_arrival(actor, initial)
		_expect(actor.global_position.distance_to(marker.global_position) < 0.15,
			"The Q intro ignored the classroom's QOpeningTalk landing.")
		_expect(bool(_player.get("_wake_seated")) and is_equal_approx(_player.visual.rotation.x, tilt),
			"Approaching Q made the protagonist stand up or changed the wake pose.")
		await _finish_lines()
		_expect(bool(_player.get("_wake_seated")) and is_equal_approx(_player.visual.rotation.x, tilt),
			"Q's closing line made the protagonist stand up or changed the wake pose.")
		_expect(_player.is_control_enabled(), "The held-seat Q beat did not return control.")
	await _release_world()


func _check_arrival(actor: NpcActor, initial: Vector3) -> void:
	var toward := _player.global_position - actor.global_position
	toward.y = 0.0
	_expect(actor.global_position.distance_to(initial) > 0.25,
		"Q began talking without approaching from the authored initial position.")
	_expect(toward.length() >= 0.85 and toward.length() <= 1.65,
		"Q is not at a close, non-overlapping talking distance (%.2f m)." % toward.length())
	_expect((-actor.global_basis.z).dot(toward.normalized()) > 0.98,
		"Q is not facing the protagonist when the first line begins.")
	var talk := _room.find_interactable(&"q_talk")
	if talk == null:
		_expect(false, "The QTalk interaction is missing.")
	else:
		var gap := talk.global_position - actor.global_position
		_expect(Vector2(gap.x, gap.z).length() < 0.1,
			"Q moved but left the interaction hotspot at the old position.")


func _wait_for_q() -> bool:
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until:
		if _dialogue.is_busy() and _dialogue.get_runtime().get_active_conversation_id() == &"q_wake":
			return true
		await get_tree().process_frame
	_expect(false, "Q never approached and started the introduction within 20 seconds.")
	return false


func _finish_lines() -> void:
	var until := Time.get_ticks_msec() + 20000
	while (_dialogue.is_busy() or _sequence.is_beat_active()) and Time.get_ticks_msec() < until:
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		await get_tree().process_frame
	_expect(not _dialogue.is_busy() and not _sequence.is_beat_active(), "Q's conversation did not finish.")


func _release_world() -> void:
	_save.unbind_world()
	if is_instance_valid(_world):
		_world.queue_free()
	await _frames(3)
	_world = null
	_state.clear()
	_narrative.clear()


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
