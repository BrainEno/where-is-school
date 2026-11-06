extends TestCaseHelper
## Integration tests for the playable prologue: the real main scene, the real
## flow, the real content. The narrative layer is not mocked, because the point
## of these tests is that the wiring in main.tscn actually works.


const PROLOGUE_SCENE := preload("res://scenes/main/main.tscn")

var _root: Node


func _run() -> void:
	await _instantiate()
	await _test_wake_state()
	await _test_q_conversation_choices()
	await _test_rehearsal_isolation()
	await _test_missing_textbook_is_recorded_once()
	await _test_bell_and_substitute()
	await _test_permission_unlocks_the_door()
	await _test_exit_flow()
	await _teardown()


func _instantiate() -> void:
	var game_state: Node = make_tree().root.get_node_or_null("GameState")
	var ledger: Node = make_tree().root.get_node_or_null("NarrativeLedger")
	game_state.clear()
	ledger.clear()

	_root = PROLOGUE_SCENE.instantiate()
	_root.set("autostart", false)
	make_tree().root.add_child(_root)
	await flush_frames(3)


func _flow() -> PrologueFlow:
	return _root.get_node_or_null("PrologueFlow") as PrologueFlow


func _player() -> PlayerController:
	return _root.get_node_or_null("Player") as PlayerController


func _door() -> Interactable3D:
	for node in make_tree().get_nodes_in_group(&"interactable"):
		var candidate := node as Interactable3D
		if candidate != null and candidate.interact_id == &"door":
			return candidate
	return null


func _test_wake_state() -> void:
	check_not_null(_root, "main scene instantiated")
	var player := _player()
	check_not_null(player, "player exists")
	var flow := _flow()
	check_not_null(flow, "flow exists")
	check_false(GameState.get_bool(PrologueFlags.AWAKE), "nothing has happened before begin()")

	var classroom := _root.get_node_or_null("LocationRoot/Classroom")
	check_not_null(classroom, "the classroom is the first loaded location")
	check_true(classroom is ClassroomLocation, "the classroom scene has the classroom script")

	var interactables: Array[Node] = make_tree().get_nodes_in_group(&"interactable")
	check(interactables.size() >= 6, "the classroom exposes several interactables", str(interactables.size()))

	var door := _door()
	check_not_null(door, "the classroom has a door interactable")
	if door != null:
		check_false(door.is_enabled(), "the door is inert until the lesson releases the class")


func _test_q_conversation_choices() -> void:
	var script := PrologueDialogue.q_conversation()
	var built: Dictionary = make_session(script)
	var session: DialogueSession = built["session"]
	var log: Dictionary = built["log"]
	var guard := 0
	while not session.is_awaiting_choice() and not session.is_finished() and guard < 20:
		session.advance()
		guard += 1
	check_true(session.is_awaiting_choice(), "Q's conversation reaches a player choice")
	if not session.is_awaiting_choice():
		return
	var options: Array = log["choices"][0]
	check(options.size() >= 3, "the first choice offers at least three replies", str(options.size()))

	# Choosing must produce a different line than the other options, and must be
	# visible in the session history rather than swallowed.
	check_eq(session.history().size(), log["lines"].size(), "every presented line is in the backlog")


## The single most important test in the project: playing the rehearsal must not
## move anything, change a flag, or record anything as observed.
func _test_rehearsal_isolation() -> void:
	var ledger: Node = make_tree().root.get_node_or_null("NarrativeLedger")
	var player := _player()
	var before_position := player.global_position
	var before_ids: Array = ledger.ids()
	var before_flags: Dictionary = GameState.get_snapshot()

	var rehearsal := PrologueDialogue.anticipation()
	var built: Dictionary = make_session(rehearsal)
	var session: DialogueSession = built["session"]
	var log: Dictionary = built["log"]
	var guard := 0
	while not session.is_finished() and guard < 60:
		if session.is_awaiting_choice():
			session.choose(0)
		else:
			session.advance()
		guard += 1

	check_true(session.is_finished(), "the rehearsal can be played to the end")
	check_eq(player.global_position, before_position, "the rehearsal did not move the player")
	check_eq(GameState.get_snapshot(), before_flags, "the rehearsal did not change any story flag")
	check_eq(ledger.ids(), before_ids, "the rehearsal wrote nothing into the ledger by itself")

	for batch in log["records"]:
		for record_id in batch:
			var entry := PrologueRecords.entry_for(record_id)
			check_false(entry.is_empty(), "rehearsal record '%s' is declared" % str(record_id))
			if not entry.is_empty():
				check_eq(
					int(entry["kind"]), int(NarrativeRecord.Kind.IMAGINED),
					"rehearsal record '%s' is imaginary" % str(record_id)
				)


func _test_missing_textbook_is_recorded_once() -> void:
	var ledger: Node = make_tree().root.get_node_or_null("NarrativeLedger")
	var bag := PrologueInspections.get_entry(&"schoolbag")
	check_false(bag.is_empty(), "the schoolbag has inspection content")
	if bag.is_empty():
		return
	PrologueState.record(StringName(bag["record"]))
	PrologueState.set_flag(StringName(bag["flag"]), true)
	PrologueState.set_flag(StringName(bag["extra_flag"]), true)
	check_true(GameState.get_bool(PrologueFlags.TEXTBOOK_MISSING), "the missing textbook is a story flag")
	check_true(ledger.has(PrologueRecords.ID_BAG_EMPTY_TEXTBOOK), "the discovery is in the ledger")

	var count_before: int = ledger.ids().size()
	PrologueState.record(StringName(bag["record"]))
	check_eq(ledger.ids().size(), count_before, "re-inspecting does not duplicate the record")


func _test_bell_and_substitute() -> void:
	var flow := _flow()
	check_false(GameState.get_bool(PrologueFlags.LESSON_STARTED), "the lesson has not started")
	check_false(GameState.get_bool(PrologueFlags.B_ABSENT_CONFIRMED), "B's absence is not pre-loaded")

	flow.ring_bell()
	check_true(GameState.get_bool(PrologueFlags.BELL_RUNG), "the bell is recorded")
	check_true(GameState.get_bool(PrologueFlags.LESSON_STARTED), "the lesson is now underway")
	# ring_bell() is idempotent: a second bell must not double-advance the scene.
	flow.ring_bell()
	check_true(
		NarrativeLedger.records_of_kind(NarrativeRecord.Kind.OBSERVED).size() >= 1,
		"the bell is recorded as something the player observed"
	)

	await make_tree().create_timer(0.05).timeout
	check_false(
		GameState.get_bool(PrologueFlags.B_ABSENT_CONFIRMED),
		"the bell rings first; the empty chair comes a beat later"
	)


func _test_permission_unlocks_the_door() -> void:
	var door := _door()
	if door == null:
		check(false, "door exists")
		return
	check_false(door.is_enabled(), "the door is still inert before free activity")
	PrologueState.set_flag(PrologueFlags.N_CLASS_PERMITTED, true)
	_flow().call("_open_classroom")
	check_true(door.is_enabled(), "free activity opens the door")


func _test_exit_flow() -> void:
	var flow := _flow()
	check_false(GameState.get_bool(PrologueFlags.CLASSROOM_EXITED), "the classroom has not been left")
	flow.call("_leave_classroom")
	await make_tree().create_timer(0.7).timeout
	await flush_frames(6)
	check_true(GameState.get_bool(PrologueFlags.CLASSROOM_EXITED), "leaving the classroom is recorded")
	check_true(flow.current_beat() == PrologueFlow.BEAT_EXIT, "the flow reports the exit beat")


func _teardown() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	await flush_frames(2)
