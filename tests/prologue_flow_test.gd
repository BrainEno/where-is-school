extends SceneTree
## End-to-end test of the playable prologue, driven through the same entry points
## the player's input uses (DialoguePanel.press_advance / select_choice, and
## PrologueFlow.infer_with on the real Interactable3D nodes).
##
## This is the test that answers "can you actually play it": it walks Beat A to
## Beat G, checks the story flags each beat is supposed to set, and checks that the
## imagined confrontation never leaks into objective state.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const WAIT_STEP := 0.15

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node
var _flow: PrologueFlow
var _director: PrologueDirector
var _panel: DialoguePanel


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _start_game()

	await _beat_a_wake()
	await _beat_b_q_conversation()
	await _beat_c_d_and_e()
	await _beat_f_substitute()
	await _beat_g_leave()

	if _failures.is_empty():
		print("prologue_flow_test passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("prologue_flow_test failed: %d failure(s) of %d checks." % [_failures.size(), _checks])
		quit(1)


# ---------------------------------------------------------------------------
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _flag(flag: StringName) -> Variant:
	var state: Node = root.get_node_or_null("GameState")
	_check(state != null, "GameState autoload is missing")
	if state == null:
		return null
	return state.call("get_flag", flag)


func _has_flag(flag: StringName) -> bool:
	var value: Variant = _flag(flag)
	if value == null:
		return false
	return value == true


func _start_game() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene failed to load")
	if packed == null:
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_flow = _main.get_node("Flow") as PrologueFlow
	_director = _main.get_node("Director") as PrologueDirector
	_panel = _main.get_node("DialoguePanel") as DialoguePanel
	await process_frame
	await process_frame


func _find_interactable(interact_id: StringName) -> Interactable3D:
	if _director == null or _director.current_location == null:
		return null
	var stack: Array[Node] = [_director.current_location]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var interactable := node as Interactable3D
		if interactable != null and interactable.interact_id == interact_id:
			return interactable
		for child: Node in node.get_children():
			stack.append(child)
	return null


## Uses an interactable exactly as the player would: through PrologueFlow.
func _use(interact_id: StringName) -> Interactable3D:
	var target: Interactable3D = _find_interactable(interact_id)
	if target == null:
		_check(false, "could not find interactable '%s' in the current location" % interact_id)
		return null
	_flow.interact_with(target)
	return target


func _read_through_dialogue(max_steps: int = 200) -> int:
	var steps: int = 0
	while _flow.is_dialogue_active() and steps < max_steps:
		steps += 1
		if _panel.has_open_choices():
			return steps
		_panel.press_advance()
		await process_frame
	return steps


func _choose_by_id(choice_id: StringName) -> bool:
	if not _panel.has_open_choices():
		_check(false, "expected open choices when choosing '%s'" % choice_id)
		return false
	var choices: Array[DialogueChoice] = _flow.session.choices()
	for index: int in choices.size():
		if choices[index].id == choice_id:
			_panel.select_choice(index)
			await process_frame
			return true
	_check(false, "choice '%s' was not offered (offered: %s)" % [choice_id, _choice_ids(choices)])
	return false


func _choice_ids(choices: Array[DialogueChoice]) -> String:
	var ids: PackedStringArray = PackedStringArray()
	for choice: DialogueChoice in choices:
		ids.append(String(choice.id))
	return ", ".join(ids)


# --- Beat A ----------------------------------------------------------------
func _beat_a_wake() -> void:
	_check(_director != null, "director is missing")
	if _director == null:
		return
	_check(_director.current_location_id == &"classroom", "the game must start in the classroom")
	_check(not _has_flag(PrologueFlags.CONTROL_RETURNED), "control must not be available before the wake beat")
	var player: PlayerController = _main.get_node("Player") as PlayerController
	_check(player != null and not player.input_enabled, "player input must be locked during the wake beat")

	# Wait out the staged wake beat instead of skipping it.
	var waited: float = 0.0
	while not _has_flag(PrologueFlags.CONTROL_RETURNED) and waited < 10.0:
		await create_timer(WAIT_STEP).timeout
		waited += WAIT_STEP
	_check(_has_flag(PrologueFlags.AWAKENED), "waking up must set the awakened flag")
	_check(_has_flag(PrologueFlags.CONTROL_RETURNED), "the wake beat must return control")
	_check(player.input_enabled, "input must be enabled once the wake beat ends")

	# The player must be standing where the classroom says they sat down.
	var desk_spawn: Node3D = _director.current_location.get_node_or_null("SpawnPoints/Desk") as Node3D
	_check(desk_spawn != null, "the classroom has no desk spawn marker")
	if desk_spawn != null:
		_check(player.global_position.distance_to(desk_spawn.global_position) < 0.5,
			"the player should start at the desk spawn, not at the origin")


# --- Beat B ----------------------------------------------------------------
func _beat_b_q_conversation() -> void:
	# Q initiates on his own: no interaction with him is required.
	var waited: float = 0.0
	while not _flow.is_dialogue_active() and waited < 10.0:
		await create_timer(WAIT_STEP).timeout
		waited += WAIT_STEP
	_check(_flow.is_dialogue_active(), "Q must start talking without being prompted")
	if not _flow.is_dialogue_active():
		return
	_check(_flow.active_script_id == &"prologue_q", "the opening conversation should be Q's")

	await _read_through_dialogue()
	_check(_panel.has_open_choices(), "Q's opening must offer choices")
	_check(_panel.choice_count() >= 3, "Q's opening must offer at least three choices")

	# Take the pushback line and verify an observable consequence.
	var pushed := await _choose_by_id(&"q_choice_pushback")
	_check(pushed, "expected to be able to push back on Q")
	_check(_has_flag(PrologueFlags.Q_PUSHBACK), "pushing back on Q must set its story flag")
	_check(not _has_flag(PrologueFlags.Q_ALLOWED_SMALLTALK),
		"pushing back must not also record the opposite choice")

	await _read_through_dialogue()
	await _choose_by_id(&"q_pushback_back_off")
	await _read_through_dialogue()
	var doubted := await _choose_by_id(&"q_exam_doubt")
	_check(doubted, "expected to be able to doubt Q's account of the exam")
	_check(_has_flag(PrologueFlags.DOUBTED_EXAM_ACCOUNT), "doubting the exam account must set a flag")

	await _read_through_dialogue()
	await _choose_by_id(&"q_teacher_square")
	await _read_through_dialogue()
	await _read_through_dialogue()

	_check(not _flow.is_dialogue_active(), "Q's conversation must end and return control")
	_check(_has_flag(PrologueFlags.Q_INTRO_SEEN), "finishing Q's opening must set its flag")
	_check(_has_flag(PrologueFlags.HEARD_SET_SQUARE), "the teacher branch must record the set square claim")

	# Provenance: Q's claims are heard, and the exam paper is not objective fact.
	var ledger: NarrativeLedger = _flow.ledger
	_check(ledger.has(&"heard_exam_pending"), "Q's exam claim should be in the ledger")
	if ledger.has(&"heard_exam_pending"):
		_check(ledger.get_entry(&"heard_exam_pending").kind == NarrativeProvenance.Kind.HEARD,
			"Q's exam claim must be recorded as heard, never observed")
	_check(not ledger.has_observed(&"heard_exam_pending"),
		"Q's exam claim must not count as objective knowledge")


# --- Beat C, D, E ----------------------------------------------------------
func _beat_c_d_and_e() -> void:
	# Beat C: the schoolbag, and the missing textbook.
	await _use(&"bag")
	_check(_flow.is_dialogue_active(), "examining the bag must open an inspection")
	await _read_through_dialogue()
	await _choose_by_id(&"bag_tell_q")
	await _read_through_dialogue()
	_check(not _flow.is_dialogue_active(), "the bag inspection must end")
	_check(_has_flag(PrologueFlags.BAG_EXAMINED), "examining the bag must set its flag")
	_check(_has_flag(PrologueFlags.TEXTBOOK_MISSING), "the missing textbook must be recorded")
	_check(_has_flag(PrologueFlags.BAG_OFFERED_TO_Q), "telling Q must set its flag")
	var ledger: NarrativeLedger = _flow.ledger
	_check(ledger.has_observed(&"observed_textbook_missing"),
		"the missing textbook is something the player observed and must be objective")

	# Re-inspecting must not duplicate or contradict the record.
	var before: int = ledger.count()
	await _use(&"bag")
	await _read_through_dialogue()
	await _choose_by_id(&"bag_stay_quiet")
	await _read_through_dialogue()
	_check(ledger.count() >= before, "a revisit must keep the earlier discovery")
	_check(_has_flag(PrologueFlags.BAG_EXAMINED), "a revisit must not clear the first discovery")

	# Beat D: at least three distinct inspectables with distinct text.
	var inspected_ids: Array[StringName] = [&"bag", &"set_square", &"teacher_desk", &"timetable", &"window"]
	var seen_entries: Dictionary = {}
	for inspection_id: StringName in inspected_ids:
		var first_node_text: String = ""
		await _use(inspection_id)
		_check(_flow.is_dialogue_active(), "inspecting '%s' must produce content" % inspection_id)
		if _flow.is_dialogue_active():
			first_node_text = _flow.session.node.lines[0].text_zh if not _flow.session.node.lines.is_empty() else ""
		await _read_through_dialogue()
		if _panel.has_open_choices():
			await _choose_by_id(_flow.session.choices()[0].id)
			await _read_through_dialogue()
		_check(not first_node_text.is_empty(), "inspection '%s' produced no text" % inspection_id)
		_check(not seen_entries.has(first_node_text),
			"inspection '%s' repeats another object's description" % inspection_id)
		seen_entries[first_node_text] = true
	_check(seen_entries.size() >= 5, "expected at least five distinct inspection texts")
	_check(_has_flag(PrologueFlags.SQUARE_EXAMINED), "inspecting the set square must set its flag")

	# Beat E: the anticipation, including the subjective sequence.
	await _use(&"desk_think")
	_check(_flow.is_dialogue_active(), "the think prompt must open the anticipation beat")
	await _read_through_dialogue()
	await _choose_by_id(&"anticipation_rehearse")
	await _read_through_dialogue()
	_check(_flow.presentation_mode == PrologueFlow.PresentationMode.IMAGINED,
		"the imagined sequence must switch presentation mode")
	_check(not _panel.modulate.is_equal_approx(Color.WHITE),
		"the imagined sequence must look different from the playable world")

	# Physical state must not change while imagining.
	var player: PlayerController = _main.get_node("Player") as PlayerController
	var position_before: Vector3 = player.global_position
	var location_before: StringName = _director.current_location_id
	_check(not _has_flag(PrologueFlags.IMAGINATION_PLAYED),
		"the imagined sequence must not finish before the player reads it")
	await _read_through_dialogue()
	await _choose_by_id(&"imagine_answer_plain")
	await _read_through_dialogue()
	_check(player.global_position.distance_to(position_before) < 0.001,
		"imagining must not move the player")
	_check(_director.current_location_id == location_before, "imagining must not change location")
	_check(_flow.presentation_mode == PrologueFlow.PresentationMode.NORMAL,
		"the imagined sequence must hand presentation back")

	# Keep reading until the anticipation beat closes.
	var guard: int = 0
	while _flow.is_dialogue_active() and guard < 20:
		guard += 1
		if _panel.has_open_choices():
			await _choose_by_id(_flow.session.choices()[0].id)
		else:
			_panel.press_advance()
		await process_frame

	var ledger_after: NarrativeLedger = _flow.ledger
	_check(ledger_after.has(&"imagined_confrontation"),
		"the imagined confrontation should be recorded")
	if ledger_after.has(&"imagined_confrontation"):
		_check(ledger_after.get_entry(&"imagined_confrontation").kind == NarrativeProvenance.Kind.IMAGINED,
			"the imagined confrontation must be stored as imagined")
	_check(not ledger_after.has_observed(&"imagined_confrontation"),
		"the imagined confrontation must never count as objective knowledge")


# --- Beat F ----------------------------------------------------------------
func _beat_f_substitute() -> void:
	# The bell, B's absence, and N's arrival run on a timer after the anticipation.
	var waited: float = 0.0
	while not _has_flag(PrologueFlags.N_ARRIVED) and waited < 20.0:
		await create_timer(WAIT_STEP).timeout
		waited += WAIT_STEP
	_check(_has_flag(PrologueFlags.BELL_RUNG), "the bell must ring (or already have rung)")
	_check(_has_flag(PrologueFlags.B_ABSENCE_NOTED), "B's absence must be established")
	_check(_has_flag(PrologueFlags.N_ARRIVED), "N must arrive as the substitute")

	waited = 0.0
	while not _flow.is_dialogue_active() and waited < 10.0:
		await create_timer(WAIT_STEP).timeout
		waited += WAIT_STEP
	_check(_flow.is_dialogue_active(), "N's conversation must start on arrival")
	if not _flow.is_dialogue_active():
		return
	_check(_flow.active_script_id == &"prologue_n", "the substitute conversation should be N's")

	# The door must still be shut while the lesson is nominally on.
	var door: Interactable3D = _find_interactable(&"classroom_door")
	_check(door != null and not door.enabled, "the classroom door must be closed before release")

	await _read_through_dialogue()
	await _choose_by_id(&"n_open_ask_b")
	await _read_through_dialogue()
	await _choose_by_id(&"n_ask_insist")
	await _read_through_dialogue()
	await _choose_by_id(&"n_class_skeptic")
	await _read_through_dialogue()
	_check(_has_flag(PrologueFlags.N_READ_SKEPTICAL), "the tone choice with N must set its flag")
	await _choose_by_id(&"n_release_go")
	await _read_through_dialogue()

	# Read to the end of N's conversation.
	var guard: int = 0
	while _flow.is_dialogue_active() and guard < 30:
		guard += 1
		if _panel.has_open_choices():
			await _choose_by_id(_flow.session.choices()[0].id)
		else:
			_panel.press_advance()
		await process_frame

	_check(_has_flag(PrologueFlags.N_LET_CLASS_GO), "N must release the class at the end")
	_check(_has_flag(PrologueFlags.LEFT_CLASSROOM), "the class must be marked as over")


# --- Beat G ----------------------------------------------------------------
func _beat_g_leave() -> void:
	var door: Interactable3D = _find_interactable(&"classroom_door")
	if door == null:
		_check(false, "classroom door is missing after the release")
		return
	_check(door.enabled, "the door must be usable once the class is released")

	await _use(&"classroom_door")
	await process_frame
	await process_frame
	_check(_director.current_location_id == &"corridor", "using the door must load the corridor")

	if _director.current_location_id != &"corridor":
		return
	var player: PlayerController = _main.get_node("Player") as PlayerController
	_check(player.global_position.x < 0.0, "the player should arrive at the corridor entrance")

	# Walk the corridor to the exit threshold.
	await _use(&"corridor_exit")
	await process_frame
	await process_frame
	_check(_has_flag(PrologueFlags.EXIT_SEEN), "reaching the end of the corridor must set the exit flag")
	_check(_director.current_location_id == &"street", "the exit must lead to the street threshold")

	if _director.current_location_id != &"street":
		return
	# The street beat, including the green-animal observation.
	await _use(&"street_gate")
	_check(_has_flag(PrologueFlags.EXIT_REACHED), "standing at the gate must set the end flag")
	_check(_flow.is_dialogue_active(), "standing at the gate must open the street observation")

	await _read_through_dialogue()
	await _choose_by_id(&"street_look_back")
	await _read_through_dialogue()
	await _choose_by_id(&"street_look_closer")
	await _read_through_dialogue()
	_check(_panel.has_open_choices(), "the animal must offer a choice about what it was")
	await _choose_by_id(&"animal_look_again")
	await _read_through_dialogue()
	await _choose_by_id(&"again_doubt_eyes")
	await _read_through_dialogue()

	var street_ledger: NarrativeLedger = _flow.ledger
	_check(street_ledger.has(&"observed_green_animal"),
		"seeing the animal must be recorded as something observed")
	if street_ledger.has(&"observed_green_animal"):
		var entry: NarrativeEntry = street_ledger.get_entry(&"observed_green_animal")
		_check(entry.kind == NarrativeProvenance.Kind.OBSERVED,
			"the sighting is an observation, not a conclusion")
		_check(entry.text_zh.find("没有看清楚") != -1,
			"the sighting record must stay unresolved about what the animal was")
	_check(_has_flag(PrologueFlags.ANIMAL_GLIMPSED), "the glimpse must set its flag")
	_check(_has_flag(PrologueFlags.ANIMAL_NOT_FOUND_AGAIN), "looking again must record the failure")
	_check(_has_flag(PrologueFlags.DOUBTED_ANIMAL), "doubting your own eyes must set a flag")
	_check(_flow.ledger.has(&"doubted_green_animal"), "the doubt must be recorded as recollection, not fact")
	if _flow.ledger.has(&"doubted_green_animal"):
		_check(_flow.ledger.get_entry(&"doubted_green_animal").kind == NarrativeProvenance.Kind.RECOLLECTED,
			"self-doubt is recollection, never observation")

	var guard2: int = 0
	while _flow.is_dialogue_active() and guard2 < 20:
		guard2 += 1
		if _panel.has_open_choices():
			await _choose_by_id(_flow.session.choices()[0].id)
		else:
			_panel.press_advance()
		await process_frame
	_check(not _flow.is_dialogue_active(), "the milestone ends after the street observation")

	# The player must not be trapped: the way back is still navigable.
	var back: Interactable3D = _find_interactable(&"street_corridor")
	_check(back != null, "the street must offer a way back inside")
