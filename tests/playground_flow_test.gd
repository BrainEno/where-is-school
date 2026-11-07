extends SceneTree
## Physics/navigation integration: starts in the residential courtyard after the
## opening, walks through the actual passage and across both new scenes, visits
## four anchors out of order, and walks back. Movement is simulated input, not
## a human playtest or a screenshot capture.
const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []
var _main: Node
var _sequence: OpeningSequence
var _host: LocationHost
var _player: PlayerController
var _interaction: InteractionController
var _dialogue: DialogueController
var _state: Node
var _narrative: Node
var _loc: Node
var _passive_started: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "playground_flow_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	Harness.clear_session_state(self)
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	_loc.set_locale("en")
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_sequence = _main.get_node("OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_main)
	await process_frame
	await process_frame
	_host = _main.get_node("LocationHost") as LocationHost
	_player = _main.get_node("Player") as PlayerController
	_interaction = _player.get_node("InteractionController") as InteractionController
	_dialogue = _main.get_node("DialogueController") as DialogueController
	_dialogue.conversation_started.connect(func(id: StringName) -> void:
		if String(id).begins_with("inner_"):
			_passive_started.append(id))
	(_main.get_node("GameUI") as GameUI).fade.set_clear()
	_sequence._control_allowed = true
	_sequence._sync_player_locks()
	Engine.time_scale = 3.0

	_state.set_flag(StoryFlags.MET_Q, true)
	_state.set_flag(StoryFlags.ANIMAL_SEEN, true)
	_narrative.record(&"test_animal_observed", NarrativeEntry.Source.OBSERVED, &"protagonist", "A green animal was observed.")
	if not _host.load_location("res://scenes/locations/residential/residential.tscn", &"FromStreet", _player):
		_failures.append("Cannot load residential location.")
	else:
		_state.set_flag(StoryFlags.CURRENT_LOCATION, &"residential")
		# The only setup teleport is on the courtyard side of the building. The
		# formerly solid north block and missing alley floor must be walked through.
		_player.teleport(Transform3D(Basis.IDENTITY, Vector3(6, 0, -14.5)))
		await physics_frame
		await physics_frame
		if await _walk_to(Vector3(6, 0, -31.6), "residential alley"):
			await _use_exit(&"res_alley_end", "estate_passage")

	if _location_id() == "estate_passage":
		if await _walk_to(Vector3(0, 0, -8.0), "estate exit"):
			await _use_exit(&"estate_to_playground", "playground")

	if _location_id() == "playground":
		var location := _host.get_current()
		for id: StringName in [&"pg_track", &"pg_hoop", &"pg_bench", &"pg_notice"]:
			if location.find_interactable(id) == null:
				_failures.append("Playground anchor '%s' is missing." % id)
		# A deliberately non-authored order: notice, track, bench, hoop.
		await _visit(&"pg_notice", Vector3(10, 0, -4.5))
		await _visit(&"pg_track", Vector3(-6, 0, 1.5))
		await _visit(&"pg_bench", Vector3(-10, 0, 0.8))
		await _visit(&"pg_hoop", Vector3(8, 0, 4.4))
		if not bool(_state.get_flag(&"seen:pg_track", false)) or not bool(_state.get_flag(&"seen:pg_hoop", false)):
			_failures.append("Independent playground inspections were not recorded.")
		if _passive_started.is_empty() or not String(_passive_started[0]).begins_with("inner_track_"):
			_failures.append("The eligible track inspection did not play a passive thought.")
		if _narrative.count_for_source(NarrativeEntry.Source.IMAGINED) < 1:
			_failures.append("The passive thought did not record subjective knowledge.")
		await _exercise_active_and_locale()
		if (_main.get_node("GameUI") as GameUI).end_card.visible:
			_failures.append("Exploring automatically ended the slice.")
		if await _walk_to(Vector3(0, 0, 11), "playground return"):
			await _use_exit(&"pg_to_estate", "estate_passage")

	if _location_id() == "estate_passage":
		if await _walk_to(Vector3(0, 0, 8), "estate return"):
			await _use_exit(&"estate_to_residential", "residential")
	if _location_id() != "residential":
		_failures.append("The return route did not reach the residential area.")
	if not bool(_state.get_flag(StoryFlags.MET_Q, false)) or not bool(_state.get_flag(StoryFlags.ANIMAL_SEEN, false)) \
			or not _narrative.has_entry(&"test_animal_observed"):
		_failures.append("Opening or narrative state was lost across location swaps.")
	_release_movement()
	Engine.time_scale = 1.0
	_loc.set_locale("en")
	_main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "simulated walking reached and revisited independent playground anchors and returned.")


func _location_id() -> String:
	return String(_host.get_current().location_id) if _host != null and _host.get_current() != null else ""


func _visit(id: StringName, destination: Vector3) -> void:
	if _location_id() != "playground" or not await _walk_to(destination, String(id)):
		return
	if not await _wait_target(id):
		return
	_interaction.request_activation(_interaction.get_current_target())
	await process_frame
	if not _dialogue.is_busy():
		_failures.append("Anchor '%s' did not open a presentation." % id)
	await _settle()


## Exercise the actual controller and panel, not just the pure dice engine.
func _exercise_active_and_locale() -> void:
	if not await _walk_to(Vector3(-10, 0, 0.8), "bench active check") or not await _wait_target(&"pg_bench"):
		return
	_interaction.request_activation(_interaction.get_current_target())
	await process_frame
	if not _dialogue.has_pending_choices():
		_failures.append("The bench did not offer active ability choices.")
		return
	_dialogue.select_choice(0)
	var result: Dictionary = _state.get_flag(InnerCheckEngine.flag_for(&"bench_pattern"), {})
	var english := String(_dialogue.get_current_line().get("title", ""))
	if result.is_empty() or not english.contains("die") or not english.contains("target"):
		_failures.append("The active check is missing a result, die or target.")
	var knowledge_count: int = _narrative.get_entries().size()
	var backlog: BacklogPanel = (_main.get_node("GameUI") as GameUI).backlog
	var backlog_count := backlog.get_entry_count()
	_loc.set_locale("zh-CN")
	await process_frame
	var chinese := String(_dialogue.get_current_line().get("title", ""))
	if not chinese.contains("骰子") or not chinese.contains("难度"):
		_failures.append("The active result did not switch to Chinese.")
	if _state.get_flag(InnerCheckEngine.flag_for(&"bench_pattern"), {}) != result:
		_failures.append("Changing language changed or rerolled the active check.")
	if _narrative.get_entries().size() != knowledge_count or backlog.get_entry_count() != backlog_count:
		_failures.append("Changing language duplicated a thought or backlog line.")
	_loc.set_locale("en")
	await _settle()


func _use_exit(id: StringName, destination: String) -> void:
	if not await _wait_target(id):
		return
	var exit := _interaction.get_current_target() as LocationExit
	if exit == null or not exit.is_open() or not String(exit.required_flag).is_empty():
		_failures.append("Exit '%s' is missing or unnecessarily locked." % id)
		return
	_interaction.request_activation(exit)
	var started := Time.get_ticks_msec()
	while _location_id() != destination and Time.get_ticks_msec() - started < 15000:
		await process_frame
	if _location_id() != destination:
		_failures.append("Exit '%s' did not load %s." % [id, destination])
	await _settle()


func _wait_target(id: StringName) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 5000:
		var target := _interaction.get_current_target()
		if target != null and target.interact_id == id:
			return true
		await physics_frame
	var actual := _interaction.get_current_target()
	_failures.append("Expected target '%s', got '%s' at %s." % [id,
		"<none>" if actual == null else String(actual.interact_id), _player.global_position])
	return false


## Uses the real camera-relative movement implementation and collision response.
func _walk_to(destination: Vector3, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 18000:
		var delta := destination - _player.global_position
		delta.y = 0.0
		if delta.length() < 0.45:
			_release_movement()
			await physics_frame
			await physics_frame
			return true
		if _player.global_position.y < -1.0:
			_failures.append("Fell through the floor while walking to %s at %s." % [label, _player.global_position])
			_release_movement()
			return false
		var direction := delta.normalized()
		var right := _player.camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var forward := -_player.camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		_set_movement(direction.dot(right), direction.dot(forward))
		await physics_frame
	_release_movement()
	_failures.append("Could not walk to %s; stopped at %s (wanted %s)." % [label, _player.global_position, destination])
	return false


func _set_movement(right: float, forward: float) -> void:
	_release_movement()
	if right > 0.01:
		Input.action_press("move_right", right)
	elif right < -0.01:
		Input.action_press("move_left", -right)
	if forward > 0.01:
		Input.action_press("move_forward", forward)
	elif forward < -0.01:
		Input.action_press("move_back", -forward)


func _release_movement() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)


func _settle() -> void:
	var started := Time.get_ticks_msec()
	var quiet_frames := 0
	while Time.get_ticks_msec() - started < 15000:
		if _dialogue.is_busy():
			quiet_frames = 0
			if _dialogue.has_pending_choices():
				var options := _dialogue.get_runtime().get_current_choices()
				_dialogue.select_choice(options.size() - 1) # Leave; no forced active check.
			else:
				_dialogue.advance_presentation()
		elif _player.is_control_enabled():
			quiet_frames += 1
			if quiet_frames >= 3:
				return
		await process_frame
	_failures.append("A transition or presentation did not release control.")
