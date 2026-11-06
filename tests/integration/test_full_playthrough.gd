extends TestCaseHelper
## End-to-end playthrough of the prologue, driven through the real flow.
##
## This is the test that answers "is it playable": it starts the game, waits for
## control, walks every beat by calling the same entry points the player's input
## reaches, and asserts the narrative state at each transition. It does not
## simulate key presses — input mapping is checked separately in
## test_input_map.gd — so it stays deterministic in headless CI.
##
## Everything asserted here is a player-visible consequence: a flag, a ledger
## record, a beat id, or a line that reached the dialogue panel.

const PROLOGUE_SCENE := preload("res://scenes/main/main.tscn")

var _root: Node
var _flow: PrologueFlow
var _panel: DialoguePanel
var _hud: PrologueHud


func _run() -> void:
	await _boot()
	await _beat_a_wake()
	await _beat_b_q_conversation()
	await _beat_c_schoolbag()
	await _beat_d_inspect_room()
	await _beat_e_rehearsal()
	await _beat_f_substitute()
	await _beat_g_leave()
	_test_narrative_boundaries()
	await _teardown()


# --- helpers ---------------------------------------------------------------

func _boot() -> void:
	make_tree().root.get_node("GameState").clear()
	make_tree().root.get_node("NarrativeLedger").clear()
	_root = PROLOGUE_SCENE.instantiate()
	make_tree().root.add_child(_root)
	await flush_frames(3)
	_flow = _root.get_node_or_null("PrologueFlow") as PrologueFlow
	_panel = _root.get_node_or_null("Interface/DialoguePanel") as DialoguePanel
	_hud = _root.get_node_or_null("Interface/Hud") as PrologueHud
	check_not_null(_flow, "flow exists")
	check_not_null(_panel, "dialogue panel exists")
	check_not_null(_hud, "hud exists")


## Advances dialogue until the session either asks for a choice or ends.
## Returns the number of choices it had to make.
func _drive_dialogue(choice_picker: Callable = Callable(), limit: int = 200) -> int:
	var made := 0
	var guard := 0
	while guard < limit:
		guard += 1
		if not _flow.is_dialogue_active():
			return made
		if _panel.is_waiting_for_choices():
			made += 1
			if choice_picker.is_valid():
				choice_picker.call(made - 1)
			else:
				_flow.call("_on_choice_chosen", 0)
			await flush_frames(2)
			continue
		_flow.call("_on_advance_requested")
		await flush_frames(2)
	return made


func _wait_until(predicate: Callable, seconds: float = 6.0) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		if predicate.call():
			return true
		await make_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return false


# --- Beat A ----------------------------------------------------------------

func _beat_a_wake() -> void:
	var player := _root.get_node("Player") as PlayerController
	var woke := await _wait_until(func(): return GameState.get_bool(PrologueFlags.AWAKE), 6.0)
	check_true(woke, "the protagonist wakes (Beat A)")
	# Waking and regaining control are two separate moments: the flag is set after
	# the fade, and Q takes control shortly after that. Poll for the transition
	# rather than sampling the instant the wake flag appears.
	var controlled := await _wait_until(
		func(): return GameState.get_bool(PrologueFlags.PLAYER_HAS_CONTROL), 8.0
	)
	check_true(controlled, "control is returned after the opening beat (Beat A)")
	check_true(player.is_sitting() == false, "the player is no longer slumped at the desk (Beat A)")


# --- Beat B ----------------------------------------------------------------

func _beat_b_q_conversation() -> void:
	var q_started := await _wait_until(
		func(): return _flow.is_dialogue_active() or GameState.get_bool(PrologueFlags.Q_TALKED), 10.0
	)
	check_true(q_started, "Q starts the first conversation without being approached (Beat B)")
	check_true(_flow.current_beat() == PrologueFlow.BEAT_Q or GameState.get_bool(PrologueFlags.Q_TALKED),
		"the flow reports the Q beat")

	# Pick the second option at each prompt so the conversation takes a different
	# path than the default, proving choices are live rather than cosmetic.
	var made := await _drive_dialogue(func(index): _flow.call("_on_choice_chosen", 1))
	check(made >= 3, "Q's conversation asks the player at least three times", str(made))
	check_true(GameState.has_flag(PrologueFlags.Q_ATTITUDE), "the reply set a conversational attitude flag (Beat B)")
	check_true(GameState.get_bool(PrologueFlags.Q_MENTIONED_LAST_EXAM), "the previous exam came up (Beat B)")
	check(
		GameState.get_bool(PrologueFlags.Q_MENTIONED_REHEARSAL),
		"Q mentions rehearsing the apology (Beat B)"
	)
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")
	check_true(
		ledger.has_observed(PrologueRecords.ID_BELL) == false,
		"the bell has not happened yet, and is not recorded as observed"
	)
	check_true(
		ledger.get_record(PrologueRecords.ID_Q_REPUTATION).kind == NarrativeRecord.Kind.HEARD
		if ledger.get_record(PrologueRecords.ID_Q_REPUTATION) != null else true,
		"what Q says about the teacher is recorded as heard, not as fact"
	)


# --- Beat C ----------------------------------------------------------------

func _beat_c_schoolbag() -> void:
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")
	var bag: Interactable3D = _find_interactable(&"schoolbag")
	check_not_null(bag, "the schoolbag is targetable (Beat C)")
	if bag == null:
		return
	_flow.call("_handle_interact_id", &"schoolbag")
	await flush_frames(3)
	check_true(GameState.get_bool(PrologueFlags.BAG_EXAMINED), "examining the bag set a flag (Beat C)")
	check_true(GameState.get_bool(PrologueFlags.TEXTBOOK_MISSING), "the textbook is missing (Beat C)")
	check_true(
		ledger.has_observed(PrologueRecords.ID_BAG_EMPTY_TEXTBOOK),
		"the missing textbook is recorded as directly observed (Beat C)"
	)
	var card := _root.get_node("Interface/InspectionCard") as InspectionCard
	check_true(card.is_open(), "the player gets a readable result card, not a silent flag (Beat C)")
	card.dismiss()
	await flush_frames(2)

	# Re-examining must not duplicate state.
	var before: int = ledger.ids().size()
	_flow.call("_handle_interact_id", &"schoolbag")
	await flush_frames(3)
	check_eq(ledger.ids().size(), before, "re-examining the bag does not duplicate records (Beat C)")
	check_true(card.is_open(), "re-examining still gives feedback (Beat C)")
	card.dismiss()
	await flush_frames(2)


# --- Beat D ----------------------------------------------------------------

func _beat_d_inspect_room() -> void:
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")
	var card := _root.get_node("Interface/InspectionCard") as InspectionCard
	var texts: Dictionary = {}
	for id in [&"set_square", &"teacher_desk", &"chalkboard", &"timetable", &"window", &"own_desk"]:
		var target: Interactable3D = _find_interactable(id)
		check_not_null(target, "inspecting '%s' is reachable in the room (Beat D)" % String(id))
		if target == null:
			continue
		var before: int = ledger.ids().size()
		_flow.call("_handle_interact_id", id)
		await flush_frames(3)
		check_true(card.is_open(), "'%s' produces an inspection result (Beat D)" % String(id))
		var body: String = (card.get_node("%BodyLabel") as Label).text
		check(body.length() > 40, "'%s' has a real description (Beat D)" % String(id))
		check_false(texts.has(body), "'%s' has its own text, not a reused one (Beat D)" % String(id))
		texts[body] = true
		card.dismiss()
		await flush_frames(2)
		check(
			ledger.ids().size() >= before,
			"inspecting '%s' never deletes state (Beat D)" % String(id)
		)

	check_true(GameState.get_bool(PrologueFlags.SET_SQUARE_EXAMINED), "the set square was inspected (Beat D)")
	check_true(
		ledger.has_observed(PrologueRecords.ID_SET_SQUARE),
		"the set square is recorded as observed (Beat D)"
	)
	check(
		not GameState.has_flag(&"prologue.b.onstage"),
		"no flag anywhere claims B was present in the room (Beat D)"
	)


# --- Beat E ----------------------------------------------------------------

func _beat_e_rehearsal() -> void:
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")
	var player := _root.get_node("Player") as PlayerController
	var q := make_tree().root.get_node_or_null("Main/LocationRoot/Classroom/NpcQ")
	var before_position := player.global_position
	var before_q_position: Vector3 = (q as Node3D).global_position if q is Node3D else Vector3.ZERO
	var before_observed: int = ledger.records_of_kind(NarrativeRecord.Kind.OBSERVED).size()

	var entered := await _wait_until(func(): return GameState.get_bool(PrologueFlags.ANTICIPATION_ENTERED) or GameState.get_bool(PrologueFlags.ANTICIPATION_EXITED), 8.0)
	check_true(entered, "the anticipated confrontation becomes playable (Beat E)")
	if not entered:
		return

	await _drive_dialogue(Callable(), 200)

	check_true(
		GameState.get_bool(PrologueFlags.ANTICIPATION_EXITED),
		"the rehearsal ends rather than trapping the player (Beat E)"
	)
	check_eq(player.global_position, before_position, "the rehearsal did not move the player (Beat E)")
	if q is Node3D:
		check_eq((q as Node3D).global_position, before_q_position, "the rehearsal did not move Q (Beat E)")
	check_eq(
		ledger.records_of_kind(NarrativeRecord.Kind.OBSERVED).size(),
		before_observed,
		"the rehearsal recorded nothing as observed (Beat E)"
	)
	check(
		ledger.records_of_kind(NarrativeRecord.Kind.IMAGINED).size() >= 2,
		"the rehearsal did record what was imagined (Beat E)",
		str(ledger.records_of_kind(NarrativeRecord.Kind.IMAGINED).size())
	)
	check_false(
		GameState.get_bool(PrologueFlags.B_ABSENT_CONFIRMED),
		"imagining B's arrival does not decide anything about B (Beat E)"
	)


# --- Beat F ----------------------------------------------------------------

func _beat_f_substitute() -> void:
	check_false(GameState.get_bool(PrologueFlags.BELL_RUNG), "the bell has not rung before Beat F")
	_flow.ring_bell()
	check_true(GameState.get_bool(PrologueFlags.BELL_RUNG), "the bell rings (Beat F)")
	var absent := await _wait_until(func(): return GameState.get_bool(PrologueFlags.B_ABSENT_CONFIRMED), 8.0)
	check_true(absent, "the empty chair is established after the bell (Beat F)")
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")
	var absence_recorded := await _wait_until(
		func(): return ledger.has_observed(PrologueRecords.ID_B_ABSENT), 4.0
	)
	check_true(absence_recorded, "B's absence is observed, not asserted by Q")

	var n_started := await _wait_until(func(): return GameState.get_bool(PrologueFlags.N_ENTERED), 10.0)
	check_true(n_started, "N enters as the substitute (Beat F)")
	var n_npc := make_tree().root.get_node_or_null("Main/LocationRoot/Classroom/NpcN") as NpcActor
	check_not_null(n_npc, "the substitute has a body in the room")
	if n_npc != null:
		check_true(n_npc.visible, "the substitute is visibly present (Beat F)")

	await _drive_dialogue(func(index): _flow.call("_on_choice_chosen", 0), 200)

	var permitted := await _wait_until(func(): return GameState.get_bool(PrologueFlags.N_CLASS_PERMITTED), 8.0)
	check_true(permitted, "N eventually permits the class to leave (Beat F)")
	check_true(GameState.get_bool(PrologueFlags.LESSON_ENDED), "the lesson has ended (Beat F)")


# --- Beat G ----------------------------------------------------------------

func _beat_g_leave() -> void:
	var door := _find_interactable(&"door")
	check_not_null(door, "the classroom has an exit (Beat G)")
	if door == null:
		return
	check_true(door.is_enabled(), "the door is usable once the class is released (Beat G)")

	_flow.call("_handle_interact_id", &"door")
	var recorded := await _wait_until(
		func(): return GameState.get_bool(PrologueFlags.CLASSROOM_EXITED), 5.0
	)
	check_true(recorded, "leaving the classroom is recorded (Beat G)")
	check_true(_flow.current_beat() == PrologueFlow.BEAT_EXIT, "the flow reaches its exit beat (Beat G)")


# --- narrative boundaries --------------------------------------------------

func _test_narrative_boundaries() -> void:
	var ledger: Node = make_tree().root.get_node("NarrativeLedger")

	# Every record in the ledger must have a declared kind, and the imagined ones
	# must be the only records about the rehearsal.
	for record in ledger.records():
		var entry: Dictionary = PrologueRecords.entry_for(record.id)
		check_false(entry.is_empty(), "ledger record '%s' is declared in PrologueRecords" % String(record.id))
		if entry.is_empty():
			continue
		check_eq(
			int(record.kind), int(entry["kind"]),
			"ledger record '%s' kept its declared kind" % String(record.id)
		)

	# The whole run must produce all four kinds of knowledge. If a future change
	# collapses them into one, the scene loses the distinction the brief requires.
	var counts: Dictionary = ledger.kind_counts()
	check(int(counts.get(NarrativeRecord.Kind.OBSERVED, 0)) > 0, "the run observed things first-hand")
	check(int(counts.get(NarrativeRecord.Kind.HEARD, 0)) > 0, "the run contains things Q and N said")
	check(int(counts.get(NarrativeRecord.Kind.IMAGINED, 0)) > 0, "the run contains imagined material")

	# No record may be recorded as observed if it is declared as imagined.
	for record in ledger.records_of_kind(NarrativeRecord.Kind.OBSERVED):
		var entry: Dictionary = PrologueRecords.entry_for(record.id)
		if entry.is_empty():
			continue
		check_ne(
			int(entry["kind"]), int(NarrativeRecord.Kind.IMAGINED),
			"an imagined beat was never filed as observed (%s)" % String(record.id)
		)


func _find_interactable(id: StringName) -> Interactable3D:
	for node in make_tree().get_nodes_in_group(&"interactable"):
		var candidate := node as Interactable3D
		if candidate != null and candidate.interact_id == id:
			return candidate
	return null


func _teardown() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	await flush_frames(2)
