extends Node
## End-to-end failure transaction checks, run by classroom_anomaly_test.gd so the
## existing Godot CI job exercises the disk round trips without changing its workflow.
##
## This is intentionally a Node helper rather than a second SceneTree test: it replaces
## only the staged handler's returned destination in memory. The real curtain handler,
## OpeningSequence beat, LocationFlow, LocationHost, SaveManager and main scene still run.

const Harness = preload("res://tests/test_harness.gd")
const MAIN_SCENE := "res://scenes/main/main.tscn"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const PLAYGROUND := "res://scenes/locations/playground/playground.tscn"
const MISSING_SCENE := "res://scenes/locations/playground/__missing_test_fixture__.tscn"

var failures: Array[String] = []
var _main: Node
var _host: LocationHost
var _player: PlayerController
var _interaction: InteractionController
var _dialogue: DialogueController
var _sequence: OpeningSequence
var _director: InnerVoiceDirector
var _game_state: Node
var _narrative: Node
var _save: Node
var _conversations: Array[StringName] = []
var _saved_failure_position := Vector3.ZERO
var _saved_failure_facing := Vector3.ZERO
var _old_time_scale := 1.0


func run(previous_main: Node) -> void:
	_old_time_scale = Engine.time_scale
	Engine.time_scale = 5.0
	var autoloads := Harness.ensure_state_autoloads(get_tree())
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_save = autoloads["save"]
	if _game_state == null or _narrative == null or _save == null:
		_expect(false, "Recovery test could not access the state and save autoloads.")
		Engine.time_scale = _old_time_scale
		return

	_save.unbind_world()
	if is_instance_valid(previous_main):
		previous_main.queue_free()
		await _frames(3)
	_game_state.clear()
	_narrative.clear()
	_save.forget_all()
	for flag: StringName in [
		StoryFlags.MET_Q,
		StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED,
		StoryFlags.BELL_RUNG,
		StoryFlags.CLASS_DISMISSED,
	]:
		_game_state.set_flag(flag, true)

	if not await _boot_main():
		await _finish()
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	_expect(
		_host.get_current_path() == CLASSROOM, "Recovery fixture did not start in the classroom."
	)
	_expect(
		_sequence != null and _interaction != null, "Recovery fixture is missing runtime nodes."
	)
	if _sequence == null or _interaction == null:
		await _finish()
		return
	# This first failure starts with the actual bilingual curtain conversation and its draw
	# choice. The other two continue the pending transaction, one with the legacy stale
	# drawn+pending pair, so the retry path is exercised through real player activation.
	await _attempt_failure("missing_scene", true)
	await _attempt_failure("missing_spawn", false)
	_game_state.set_flag(StoryFlags.CURTAIN_DRAWN, true)
	(_anomalies() as ClassroomAnomalies)._apply_story_state()
	_expect(
		(
			ConversationRouter.select(&"classroom_curtain", _game_state.get_snapshot())
			== &"classroom_curtain"
		),
		"A pending curtain fall does not take precedence over the legacy drawn flag."
	)
	await _attempt_failure("location_host_reject", false)

	# A failed transition is a legal checkpoint, not a half-written flight. Store the real
	# state, destroy the world, and require a fresh main scene to recover it from user://.
	Harness.stage = "save failed curtain transaction"
	var failed_save: Dictionary = _sequence.autosave("curtain fall refused")
	_expect(
		failed_save.get("ok", false) == true,
		"Failure state was not saved to disk: %s" % str(failed_save)
	)
	var disk_read: Dictionary = _save.read_save()
	_expect(
		disk_read.get("ok", false) == true,
		"Failure checkpoint did not read back: %s" % str(disk_read)
	)
	_expect(
		(
			_game_state.get_flag(StoryFlags.CURTAIN_FALL_PENDING, false) == true
			and _game_state.get_flag(StoryFlags.CURTAIN_DRAWN, false) == false
		),
		"The on-disk failure checkpoint does not preserve pending without drawn success."
	)
	await _release_main(true)

	Harness.stage = "reload failed curtain transaction"
	if not await _boot_main():
		await _finish()
		return
	_expect(
		_host.get_current_path() == CLASSROOM,
		"The failure save did not restore the source classroom."
	)
	_expect(
		String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "classroom",
		"The failure save restored CURRENT_LOCATION to somewhere other than the classroom."
	)
	_expect(
		(
			_player.global_position.distance_to(_saved_failure_position) < 0.05
			and _player.get_facing_direction().distance_to(_saved_failure_facing) < 0.02
		),
		"The failure disk round trip did not restore the original player position and facing."
	)
	_expect(
		(
			_player.visual != null
			and absf(_player.visual.rotation_degrees.x) < 0.5
			and _player.camera_rig != null
			and absf(_player.camera_rig.get_roll()) < 0.5
			and _player.camera_rig.get_frame_weight() < 0.01
			and _player.is_control_enabled()
			and _interaction.is_enabled()
			and not _sequence.is_beat_active()
		),
		"The failure disk reload did not restore the upright, unlocked view and interaction."
	)
	_expect(
		(
			_game_state.get_flag(StoryFlags.CURTAIN_FALL_PENDING, false) == true
			and _game_state.get_flag(StoryFlags.CURTAIN_DRAWN, false) == false
		),
		"The disk reload lost the pending retry or restored a false drawn success."
	)
	_expect(
		(
			_narrative.has_entry(&"drew_back_curtain")
			and _narrative.has_entry(&"saw_void_window")
			and not _narrative.has_entry(&"fell_into_playground")
		),
		"The failure save restored incorrect curtain/fall narrative records."
	)
	var restored_curtain := _curtain_interactable()
	_expect(
		(
			restored_curtain != null
			and restored_curtain.get_prompt_override() == ClassroomAnomalies.CURTAIN_RETRY_PROMPT
		),
		"The reloaded pending curtain does not offer its retry prompt."
	)
	var restored_anomalies := _anomalies() as ClassroomAnomalies
	_expect(
		(
			restored_anomalies != null
			and not restored_anomalies.is_void_open()
			and not _curtain().is_open()
		),
		"The reloaded failed transaction does not match its rolled-back flags visually."
	)

	# The exact same pending choice now succeeds through the unmodified production handler.
	_conversations.clear()
	await _activate_curtain()
	await _settle("retrying the saved curtain fall")
	_expect(
		(
			String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground"
			and _host.get_current_path() == PLAYGROUND
		),
		"The saved failed fall could not be retried into the playground."
	)
	_expect(
		(
			_game_state.get_flag(StoryFlags.CURTAIN_FALL_PENDING, true) == false
			and _game_state.get_flag(StoryFlags.CURTAIN_DRAWN, false) == true
			and _game_state.get_flag(StoryFlags.PLAYGROUND_ARRIVED, false) == true
		),
		"The successful retry did not atomically consume pending and commit arrival flags."
	)
	_expect(
		_narrative.has_entry(&"fell_into_playground"),
		"The successful retry did not record its landing."
	)
	_expect(
		(
			_count_conversation(&"classroom_curtain_void") == 0
			and _count_conversation(&"classroom_fall_landing") == 1
			and _count_conversation(&"playground_arrival") == 0
		),
		(
			"The retry repeated the fall/landing dialogue or played the wrong ordinary arrival: %s"
			% str(_conversations)
		)
	)
	var landed_room := _host.get_current()
	var landed_marker := (
		landed_room.find_child("FromSchool", true, false) as Node3D if landed_room != null else null
	)
	_expect(landed_marker != null, "The retry destination has no FromSchool spawn marker.")
	if landed_marker != null:
		var landing_offset := _player.global_position - landed_marker.global_position
		landing_offset.y = 0.0
		_expect(
			landing_offset.length() < 1.5, "The retry did not use the FromSchool landing point."
		)

	# The success checkpoint must also survive a true world teardown/reload, and loading it
	# must not replay either the fall's landing line or the playground's ordinary arrival.
	Harness.stage = "save successful curtain transaction"
	var success_read: Dictionary = _save.read_save()
	_expect(
		success_read.get("ok", false) == true, "The successful landing checkpoint is unreadable."
	)
	await _release_main(false)
	Harness.stage = "reload successful curtain transaction"
	if not await _boot_main():
		await _finish()
		return
	_conversations.clear()
	await _frames(30)
	_expect(
		(
			String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground"
			and _host.get_current_path() == PLAYGROUND
		),
		"The successful landing save did not restore the playground."
	)
	_expect(
		(
			_game_state.get_flag(StoryFlags.CURTAIN_FALL_PENDING, true) == false
			and _game_state.get_flag(StoryFlags.CURTAIN_DRAWN, false) == true
			and _game_state.get_flag(StoryFlags.PLAYGROUND_ARRIVED, false) == true
		),
		"The successful landing flags did not survive the second disk round trip."
	)
	_expect(
		(
			_count_conversation(&"classroom_curtain_void") == 0
			and _count_conversation(&"classroom_fall_landing") == 0
			and _count_conversation(&"playground_arrival") == 0
		),
		"Loading a successful landing replayed fall/arrival dialogue: %s" % str(_conversations)
	)

	await _finish()


func _boot_main() -> bool:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_expect(false, "main.tscn could not be loaded for recovery testing.")
		return false
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	get_tree().root.add_child(_main)
	await _frames(4)
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_interaction = (
		_player.get_node_or_null("InteractionController") as InteractionController
		if _player != null
		else null
	)
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = sequence_node as OpeningSequence
	_director = _main.get_node_or_null("InnerVoiceDirector") as InnerVoiceDirector
	if (
		_host == null
		or _player == null
		or _interaction == null
		or _dialogue == null
		or _sequence == null
	):
		_expect(false, "main.tscn did not expose the nodes required by recovery testing.")
		return false
	_dialogue.conversation_started.connect(_on_conversation_started)
	return true


func _attempt_failure(kind: String, make_draw_choice: bool) -> void:
	Harness.stage = "injected curtain failure: %s" % kind
	var anomalies := _anomalies() as ClassroomAnomalies
	var staged := _curtain_interactable()
	if anomalies == null or staged == null:
		_expect(false, "The classroom curtain handler is unavailable for %s." % kind)
		return
	staged.stage_handler = Callable(self, "_stage_curtain_with_failure").bind(anomalies, kind)
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	_player.face_toward(Vector3.RIGHT)
	var original_position := _player.global_position
	var original_facing := _player.get_facing_direction()
	_saved_failure_position = original_position
	_saved_failure_facing = original_facing
	_player.set_camera_roll(4.0)
	if _player.camera_rig != null:
		await _player.camera_rig.frame_point(Vector3(30.0, 0.0, 30.0), 0.0)
	var original_room := _host.get_current()

	await _activate_curtain()
	if make_draw_choice:
		await _choose_draw()
	await _settle("the %s curtain failure" % kind)

	_expect(_host.get_current() == original_room, "%s failure replaced the classroom." % kind)
	_expect(_host.get_current_path() == CLASSROOM, "%s failure changed the current scene." % kind)
	_expect(
		_player.global_position.distance_to(original_position) < 0.05,
		"%s failure moved the player away from their original classroom position." % kind
	)
	_expect(
		_player.get_facing_direction().distance_to(original_facing) < 0.02,
		"%s failure did not restore the player's facing." % kind
	)
	_expect(
		(
			_player.visual != null
			and absf(_player.visual.rotation_degrees.x) < 0.5
			and _player.visual.position.is_equal_approx(Vector3(0.0, 0.9, 0.0))
		),
		"%s failure left the player in a falling or tilted pose." % kind
	)
	_expect(
		(
			_player.camera_rig != null
			and absf(_player.camera_rig.get_roll()) < 0.5
			and _player.camera_rig.get_frame_weight() < 0.01
		),
		"%s failure did not restore camera roll and player framing." % kind
	)
	_expect(
		(
			_player.is_control_enabled()
			and _interaction.is_enabled()
			and not _sequence.is_beat_active()
		),
		"%s failure left the player locked or the staged beat active." % kind
	)
	_expect(
		(
			String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "classroom"
			and _game_state.get_flag(StoryFlags.CURTAIN_FALL_PENDING, false) == true
			and _game_state.get_flag(StoryFlags.CURTAIN_DRAWN, false) == false
			and _game_state.get_flag(StoryFlags.PLAYGROUND_ARRIVED, false) == false
		),
		"%s failure did not preserve only the pending source-room state." % kind
	)
	_expect(
		(
			not _narrative.has_entry(&"fell_into_playground")
			and _count_conversation(&"classroom_fall_landing") == 0
		),
		"%s failure was incorrectly recorded or announced as a successful landing." % kind
	)
	var curtain := _curtain_interactable()
	_expect(
		(
			curtain != null
			and curtain.get_prompt_override() == ClassroomAnomalies.CURTAIN_RETRY_PROMPT
		),
		"%s failure did not leave the curtain's retry prompt available." % kind
	)
	_expect(
		(_anomalies() as ClassroomAnomalies).is_void_open() == false and not _curtain().is_open(),
		"%s failure did not restore the ordinary window and closed curtain." % kind
	)
	if make_draw_choice:
		_expect(
			_narrative.has_entry(&"drew_back_curtain") and _narrative.has_entry(&"saw_void_window"),
			"The real draw/void actions were not preserved as observed after %s." % kind
		)


func _stage_curtain_with_failure(
	director: Node, anomalies: ClassroomAnomalies, kind: String
) -> Dictionary:
	var request: Dictionary = await anomalies._stage_curtain(director)
	var transition: Dictionary = request.get("transition", {}).duplicate(true)
	if transition.is_empty():
		_expect(false, "The real curtain handler returned no transition for %s." % kind)
		return request
	match kind:
		"missing_scene":
			transition["scene"] = MISSING_SCENE
		"missing_spawn":
			transition["spawn"] = &"__MissingTestSpawn__"
		"location_host_reject":
			transition["id"] = &"not_the_playground"
		_:
			_expect(false, "Unknown curtain failure injection '%s'." % kind)
	request["transition"] = transition
	return request


func _activate_curtain() -> void:
	var curtain := _curtain_interactable()
	if curtain == null:
		_expect(false, "No curtain interactable in the current classroom.")
		return
	_interaction.set_enabled(true)
	_interaction.request_activation(curtain)
	await get_tree().process_frame


func _choose_draw() -> void:
	var started := Time.get_ticks_msec()
	while not _dialogue.has_pending_choices():
		if Time.get_ticks_msec() - started > 30000:
			_expect(false, "The real curtain conversation never offered its draw choice.")
			return
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await get_tree().process_frame
	var choices := _dialogue.get_runtime().get_available_choice_ids()
	var index := choices.find(&"draw")
	if index < 0:
		_expect(false, "The real curtain conversation offered %s instead of draw." % str(choices))
		return
	_dialogue.select_choice(index)
	await get_tree().process_frame


func _settle(label: String) -> void:
	var started := Time.get_ticks_msec()
	while (
		_dialogue.is_busy()
		or _sequence.is_beat_active()
		or (_director != null and (_director.pending_count() > 0 or _director.is_firing()))
	):
		if Time.get_ticks_msec() - started > 60000:
			_expect(false, "Timed out waiting for %s." % label)
			return
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await get_tree().process_frame
	await _frames(3)


func _release_main(preserve_save: bool) -> void:
	_save.unbind_world()
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
	_main = null
	if not preserve_save:
		_game_state.clear()
		_narrative.clear()


func _finish() -> void:
	if is_instance_valid(_main):
		if _save != null:
			_save.unbind_world()
		_main.queue_free()
		await _frames(3)
		_main = null
	if _save != null:
		_save.forget_all()
	if _game_state != null:
		_game_state.clear()
	if _narrative != null:
		_narrative.clear()
	Engine.time_scale = _old_time_scale


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _anomalies() -> Node:
	var room := _host.get_current() if _host != null else null
	return room.get_node_or_null(^"Anomalies") if room != null else null


func _curtain() -> WindowCurtain:
	var room := _host.get_current() if _host != null else null
	return (
		room.get_node_or_null(^"Anomalies/BackCurtain") as WindowCurtain if room != null else null
	)


func _curtain_interactable() -> StagedInteractable:
	var room := _host.get_current() if _host != null else null
	return room.find_interactable(&"curtain") as StagedInteractable if room != null else null


func _count_conversation(id: StringName) -> int:
	var count := 0
	for played in _conversations:
		if played == id:
			count += 1
	return count


func _on_conversation_started(id: StringName) -> void:
	_conversations.append(id)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
