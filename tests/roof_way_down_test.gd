extends SceneTree
## Getting off the container roof while the resident stands in his doorway, and the yard tap
## (round 8), on the real main scene. The ladder itself, chosen, is covered by
## `classroom_anomaly_test.gd` after both real landings; this test starts on the roof.
##
## 1. **The ladder asks first.** With the resident outside, using the roof ladder offers
##    the ladder, the jump and waiting; waiting leaves the protagonist on the roof.
## 2. **The jump, unheard.** A passed orientation check: the protagonist steps off
##    (`void_step`), lands hard on the yard behind the north door leaf (`roof_impact`), and
##    the dazed look comes back heavier than a landing (`ConcussionView.HEAVY_SECONDS`).
##    The resident searches for 30-60 story seconds, never holds the hidden protagonist in
##    a clear line of sight while he looks, and goes back into his cabin. Then the player
##    has control on the yard floor, the look keeps fading, and the checkpoint is there.
## 3. **The jump, heard.** A failed check: the same fall, then he stops the protagonist
##    (`pg_collector_stop`) and keeps him in view; there is no search.
## 4. **The tap.** Clear-headed it is its inspection. Dazed, it offers water: a mouthful
##    takes a third of the look and can be taken again, a wash clears it, leaving keeps it.

const Harness = preload("res://tests/test_harness.gd")
const RoofEncounter = preload("res://scenes/locations/playground/roof_encounter.gd")
const RoofWayDown = preload("res://scenes/locations/playground/roof_way_down.gd")
const MAIN := "res://scenes/main/main.tscn"
const PLAYGROUND := "res://scenes/locations/playground/playground.tscn"
const JUMP_KEY := "pg_roof_jump/prj_check"
## The protagonist's orientation value the check adds to the dice.
const ORIENTATION := 3
const TIME_SCALE := 4.0
## A glimpse is not being found: he has to hold the protagonist in a clear line of
## sight, in front of him, for this many story seconds.
const FOUND_SECONDS := 1.5

var _check := Harness.Checker.new()
var _state: Node = null
var _world: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _interaction: InteractionController = null
var _view: ConcussionView = null
var _conversations: Array[StringName] = []
var _inspections: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "roof_way_down_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	if _state == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	_world = (load(MAIN) as PackedScene).instantiate()
	var sequence := _world.get_node(^"OpeningSequence") as OpeningSequence
	sequence.autostart = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	await _frames(3)
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_sequence = sequence
	_view = _world.get_node_or_null(^"ConcussionView") as ConcussionView
	_interaction = _player.get_node_or_null(^"InteractionController") as InteractionController
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	if not _check.expect(
		_view != null and _interaction != null, "Main lacks the nodes this test needs."
	):
		Harness.finish(self, _check.failures, "")
		return
	_interaction.mouse_targeting = false
	# Even with autostart off, the classroom entered the tree and queued a bake; let it
	# finish before the room is swapped.
	var nav := _host.get_current().get_node_or_null(^"Navigation") as LocationNavigation
	if nav != null:
		await Harness.wait_until(nav.is_routable, 7.0)
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _conversations.append(id))
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _inspections.append(id))
	_sequence.allow_player_control()
	Engine.time_scale = TIME_SCALE

	Harness.stage = "the ladder asks first"
	await _check_wait()
	Harness.stage = "the jump, unheard"
	await _check_jump(true)
	Harness.stage = "the jump, heard"
	await _check_jump(false)
	Harness.stage = "the tap"
	await _check_tap()

	Engine.time_scale = 1.0
	var save := root.get_node_or_null(^"Save")
	if save != null and save.has_method("forget_all"):
		save.forget_all()
	_world.queue_free()
	await _frames(2)
	Harness.clear_session_state(self)
	Harness.finish(
		self,
		_check.failures,
		(
			"the roof ladder asks while the resident watches; the jump falls again, heavier,"
			+ " and is searched for or stopped; the tap's water relieves and clears the look."
		)
	)


# --- 1. the choice ------------------------------------------------------------------


func _check_wait() -> void:
	if not await _on_roof(false):
		return
	var roof := _player.global_position
	await _activate(&"pg_container_ladder")
	var ids := await _choices("the roof ladder")
	_check.expect(
		ids == [&"ladder", &"jump", &"stay"],
		"The roof ladder offered %s, not the ladder, the jump and waiting." % str(ids)
	)
	if not await _choose(&"stay", "waiting on the roof"):
		return
	await _settle(10.0, "waiting on the roof")
	_check.expect(
		_player.global_position.distance_to(roof) < 0.3 and _player.is_control_enabled(),
		"Waiting did not leave the protagonist on the roof with control."
	)
	_check.expect(_stage().phase == RoofEncounter.Phase.OUTSIDE, "Waiting moved the resident.")


# --- 2./3. the jump -----------------------------------------------------------------


func _check_jump(unheard: bool) -> void:
	if not await _on_roof(true):
		return
	_seed_check(unheard)
	var container := _room().get_node(^"ContainerBody") as Node3D
	var collector := _stage().get_node(^"Collector") as NpcActor
	await _activate(&"pg_container_ladder")
	if not await _choose(&"jump", "jumping off the roof"):
		return
	var clips := {}
	var heaviest := 0
	var search_started := 0
	var search_ended := 0
	var in_sight := 0.0
	var longest_sight := 0.0
	var started := Time.get_ticks_msec()
	var last := started
	while _sequence.is_beat_active() and Time.get_ticks_msec() - started < 60000:
		var now := Time.get_ticks_msec()
		var step := (now - last) / 1000.0 * TIME_SCALE
		last = now
		clips[_player.get_character_animator().get_current_clip()] = true
		heaviest = maxi(heaviest, _seconds())
		var phase := _stage().phase
		if phase == RoofEncounter.Phase.SEARCHING and search_started == 0:
			search_started = Time.get_ticks_msec()
		if phase == RoofEncounter.Phase.INSIDE and search_ended == 0:
			search_ended = Time.get_ticks_msec()
		if phase == RoofEncounter.Phase.SEARCHING and _sees(collector):
			in_sight += step
			longest_sight = maxf(longest_sight, in_sight)
		else:
			in_sight = 0.0
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		await process_frame
	await _settle(10.0, "the end of the jump")
	var label := "unheard" if unheard else "heard"
	_check.expect(
		clips.has("void_step") and clips.has("roof_impact"),
		"The %s jump did not step off and land hard (%s)." % [label, str(clips.keys())]
	)
	_check.expect(
		heaviest >= ConcussionView.HEAVY_SECONDS,
		"The %s jump did not make the look heavier (%d s)." % [label, heaviest]
	)
	var record: Variant = _state.get_flag(
		StoryFlags.check_record_flag(RoofWayDown.JUMP_CONVERSATION, RoofWayDown.JUMP_CHECK), null
	)
	_check.expect(
		record is Dictionary and bool((record as Dictionary).get("success", false)) == unheard,
		"The landing's check did not come out %s: %s." % [label, str(record)]
	)
	var hide := container.to_global(RoofWayDown.HIDE)
	var flat := _player.global_position - hide
	flat.y = 0.0
	_check.expect(
		flat.length() < 0.25 and _player.is_on_floor() and _player.is_control_enabled(),
		(
			"The %s jump left the player at %s with control %s, not behind the leaf at %s."
			% [label, str(_player.global_position), _player.is_control_enabled(), str(hide)]
		)
	)
	_check.expect(
		_view.visible and _view.get_daze() > 0.5,
		"The look was gone after the %s jump (%.2f)." % [label, _view.get_daze()]
	)
	if unheard:
		var story_seconds := (search_ended - search_started) / 1000.0 * TIME_SCALE
		_check.expect(
			(
				search_started > 0
				and search_ended > 0
				and story_seconds >= 30.0
				and story_seconds <= 60.0
			),
			"The search lasted %.1f story seconds, not 30-60." % story_seconds
		)
		_check.expect(
			longest_sight < FOUND_SECONDS,
			(
				"The searching resident held the hidden protagonist in sight for %.1f s."
				% longest_sight
			)
		)
		_check.expect(
			not _conversations.has(RoofWayDown.STOP_CONVERSATION),
			"An unheard jump was still stopped."
		)
		_check.expect(
			_stage().phase == RoofEncounter.Phase.INSIDE, "The resident did not go back inside."
		)
	else:
		_check.expect(search_started == 0, "A heard jump was searched for.")
		_check.expect(
			_conversations.has(RoofWayDown.STOP_CONVERSATION) and collector.is_watching(),
			"A heard jump did not end with him stopping the protagonist."
		)
	_check_checkpoint(_player.global_position)


# --- 4. the tap ---------------------------------------------------------------------


func _check_tap() -> void:
	_state.replace_snapshot(
		{StoryFlags.CURRENT_LOCATION: &"playground", StoryFlags.PLAYGROUND_ARRIVED: true}
	)
	if not _check.expect(
		_host.load_location(PLAYGROUND, &"FromAlley", _player, &"playground"),
		"The yard did not load."
	):
		return
	await _frames(6)
	_player.teleport(Transform3D(Basis(), Vector3(-4.67, 0.0, 14.42)))
	await _frames(4)
	_inspections.clear()
	await _activate(&"pg_tap")
	await _settle(10.0, "the tap, clear-headed")
	_check.expect(
		_inspections.has(&"pg_tap") and not _conversations.has(&"pg_tap_use"),
		"Clear-headed, the tap was not its inspection (%s)." % str(_inspections)
	)

	ConcussionView.begin(_world)
	await Harness.wait_until(func() -> bool: return _view.get_daze() > 0.97, 3.0)
	for sip in 2:
		await _activate(&"pg_tap")
		await _choices("the tap, dazed")
		var before := ConcussionView.daze_for(_seconds())
		if not await _choose(&"drink", "a mouthful at the tap"):
			return
		var after := ConcussionView.daze_for(_seconds())
		_check.expect(
			absf(after - before * 2.0 / 3.0) < 0.04,
			"Mouthful %d took the look %.2f -> %.2f, not a third." % [sip + 1, before, after]
		)
		await _settle(10.0, "the mouthful")
	var kept := _seconds()
	await _activate(&"pg_tap")
	if not await _choose(&"leave", "leaving the tap"):
		return
	await _settle(10.0, "leaving the tap")
	_check.expect(absi(_seconds() - kept) <= 3, "Leaving the tap changed the look.")
	await _activate(&"pg_tap")
	if not await _choose(&"wash", "washing at the tap"):
		return
	_check.expect(_seconds() == 0, "Washing did not clear the look at once.")
	await _settle(10.0, "the wash")
	var gone := await Harness.wait_until(
		func() -> bool: return not _view.visible, ConcussionView.RELIEF_SECONDS + 2.0
	)
	_check.expect(gone, "The look was still drawn after the wash.")


# --- helpers ------------------------------------------------------------------------


## The yard after a landing, the player on the roof by the ladder, the resident at his
## door. `hurt` is the landing's outcome (both offer the choice).
func _on_roof(hurt: bool) -> bool:
	(
		_state
		. replace_snapshot(
			{
				StoryFlags.CURRENT_LOCATION: &"playground",
				StoryFlags.CURTAIN_DRAWN: true,
				StoryFlags.CURTAIN_LANDING_INJURED: hurt,
				StoryFlags.PLAYGROUND_ARRIVED: true,
			}
		)
	)
	_conversations.clear()
	if not _check.expect(
		_host.load_location(PLAYGROUND, RoofEncounter.ROOF_SPAWN, _player, &"playground"),
		"The yard did not load on the roof."
	):
		return false
	await _frames(6)
	var roof := (_room().get_node(^"ContainerBody/Ladder/RoofMark") as Marker3D).global_position
	_player.teleport(Transform3D(Basis(), roof))
	_player.face_toward(Vector3.BACK)
	await _frames(6)
	return _check.expect(
		_stage() != null and _stage().phase == RoofEncounter.Phase.OUTSIDE,
		"The resident was not in his doorway on the roof visit."
	)


func _seed_check(passed: bool) -> void:
	for seed_value in 4000:
		var resolver := CheckResolver.new(seed_value)
		if (resolver.dice_total_for(JUMP_KEY) + ORIENTATION >= 10) == passed:
			_dialogue.set_check_resolver(resolver)
			return
	_check.fail("No seed for the required jump check outcome.")


## A clear line from his eyes to the crouched protagonist, in front of him.
func _sees(collector: NpcActor) -> bool:
	var eye := collector.global_position + Vector3.UP * 1.55
	var body := _player.global_position + Vector3.UP * 0.6
	var ahead := collector.get_facing_direction()
	var toward := body - eye
	toward.y = 0.0
	if ahead.dot(toward.normalized()) < 0.35:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, body, 0xFFFFFFFF, [_player.get_rid()])
	return _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _check_checkpoint(at: Vector3) -> void:
	var save := root.get_node_or_null(^"Save")
	var result: Dictionary = save.read_save()
	var world: Dictionary = (result.get("payload", {}) as Dictionary).get("world", {})
	var saved: Array = world.get("position", [])
	_check.expect(
		(
			bool(result.get("ok", false))
			and saved.size() == 3
			and Vector3(saved[0], saved[1], saved[2]).distance_to(at) < 0.15
		),
		"The jump's checkpoint saved %s, not the landing at %s." % [str(saved), str(at)]
	)


func _activate(id: StringName) -> void:
	var target: Interactable = _room().find_interactable(id)
	if not _check.expect(target != null, "No '%s' interactable." % id):
		return
	_interaction.set_enabled(true)
	_interaction.request_activation(target)
	await process_frame


func _choices(label: String) -> Array[StringName]:
	var started := Time.get_ticks_msec()
	while not _dialogue.has_pending_choices():
		if Time.get_ticks_msec() - started > 15000:
			_check.fail("Timed out waiting for choices at %s." % label)
			return []
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	var ids: Array[StringName] = []
	for id: Variant in _dialogue.get_runtime().get_available_choice_ids():
		ids.append(StringName(String(id)))
	return ids


func _choose(choice_id: StringName, label: String) -> bool:
	var ids := await _choices(label)
	var index := ids.find(choice_id)
	if not _check.expect(index >= 0, "%s offers %s, not '%s'." % [label, str(ids), choice_id]):
		return false
	_dialogue.select_choice(index)
	await process_frame
	return true


func _settle(limit: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy() or _sequence.is_beat_active():
		if Time.get_ticks_msec() - started > int(limit * 1000.0):
			_check.fail("Timed out waiting for %s." % label)
			return false
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		await process_frame
	await _frames(2)
	return true


func _seconds() -> int:
	return int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0))


func _room() -> LocationRoot:
	return _host.get_current()


func _stage() -> RoofEncounter:
	return _room().get_node_or_null(^"RoofEncounter") as RoofEncounter


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
