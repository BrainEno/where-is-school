extends Node
class_name PrologueFlow
## Beat orchestration for the biology-class prologue.
##
## This is the only node that turns authored content into consequences. Dialogue
## content declares flags and records; this node applies them. Interactables
## declare an id; this node decides what the id does. That keeps the ownership
## line from docs/ARCHITECTURE.md in one auditable place:
##
##   content (data/)      → what could happen
##   PrologueFlow         → what does happen, in what order, and what it changes
##   PrologueState        → the only writer of flags and ledger records
##   DialoguePanel / HUD  → presentation only
##
## A rule worth keeping when editing: nothing in a "rehearsal" (Beat E) path may
## call [method _enter_inspection], move an actor, or write an OBSERVED record.
## Rehearsal writes are routed through [method _apply_records] with the session's
## "imagining" state, and the records themselves are declared IMAGINED.

signal beat_changed(beat: StringName)
signal flow_finished

## Beat ids. These are presentation/telemetry labels, not save data.
const BEAT_WAKE := &"wake"
const BEAT_Q := &"q_conversation"
const BEAT_EXPLORE := &"explore"
const BEAT_REHEARSAL := &"rehearsal"
const BEAT_LESSON := &"lesson"
const BEAT_FREE := &"free_activity"
const BEAT_EXIT := &"exit"

@export_category("Ownership")
@export var player: PlayerController
@export var hud: PrologueHud
@export var dialogue_panel: DialoguePanel
@export var inspection_card: InspectionCard
@export var note_book: NoteBook
@export var camera_focus_front: Node3D
@export var camera_focus_hall: Node3D

@export_category("Timing")
@export var wake_hold_seconds: float = 1.35
@export var wake_fade_seconds: float = 1.6
@export var beat_pause_seconds: float = 0.45

var _beat: StringName = BEAT_WAKE
var _session: DialogueSession
var _sensor: InteractionSensor
var _busy: bool = false
var _n_entered: bool = false
var _q_present: bool = true
var _npc_q: NpcActor
var _npc_n: NpcActor
var _lesson_timer: SceneTreeTimer
var _exiting: bool = false
var _awaiting_rehearsal: bool = false


func _ready() -> void:
	# References are injected by PrologueRoot after the whole tree is ready.
	_configure.call_deferred()


func _configure() -> void:
	if player == null or hud == null or dialogue_panel == null:
		push_error("PrologueFlow is missing a required presentation reference.")
		set_process(false)
		return
	_sensor = player.get_node_or_null("InteractionSensor") as InteractionSensor
	if _sensor == null:
		push_error("PrologueFlow: player scene has no InteractionSensor.")
		set_process(false)
		return

	player.interaction_pressed.connect(_on_interaction_pressed)
	dialogue_panel.advance_requested.connect(_on_advance_requested)
	dialogue_panel.choice_chosen.connect(_on_choice_chosen)
	inspection_card.dismissed.connect(_on_inspection_dismissed)
	note_book.closed.connect(_on_notebook_closed)
	hud.notebook_requested.connect(_on_notebook_requested)
	_sensor.target_changed.connect(_on_target_changed)

	_npc_q = get_tree().get_first_node_in_group(&"npc_q") as NpcActor
	_npc_n = get_tree().get_first_node_in_group(&"npc_n") as NpcActor


# --- public state -----------------------------------------------------------

func current_beat() -> StringName:
	return _beat


func is_busy() -> bool:
	return _busy


func is_dialogue_active() -> bool:
	return _session != null and not _session.is_finished()


func q_is_present() -> bool:
	return _q_present


## Starts the prologue. Awaitable, so tests can drive the opening and then take
## control of the session themselves.
func begin() -> void:
	if GameState.get_bool(PrologueFlags.AWAKE):
		_start_from_existing_state()
		return
	_set_beat(BEAT_WAKE)
	player.set_input_enabled(false)
	player.set_sitting(true)
	hud.fade.color.a = 1.0
	hud.fade.visible = true
	AudioCues.set_room_tone(0.7)
	await _wait(wake_hold_seconds)
	PrologueState.set_flag(PrologueFlags.AWAKE, true)
	await hud.fade_to(0.0, wake_fade_seconds)
	player.set_sitting(false)
	player.set_input_enabled(true)
	PrologueState.set_flag(PrologueFlags.PLAYER_HAS_CONTROL, true)
	hud.show_caption("Third period. You are at a desk that is not yours.", 3.0)
	hud.set_objective("Find your biology textbook before the bell.", 8.0)
	await _wait(0.6)
	_start_q_conversation()


func _start_from_existing_state() -> void:
	# Resuming an already-awake session (for example after a hot reload).
	player.set_input_enabled(true)
	player.set_sitting(false)
	hud.fade.color.a = 0.0
	hud.fade.visible = false
	_set_beat(BEAT_EXPLORE)
	if GameState.get_bool(PrologueFlags.LESSON_ENDED):
		_open_classroom()
		_set_beat(BEAT_FREE)
	elif GameState.get_bool(PrologueFlags.LESSON_STARTED):
		_set_beat(BEAT_LESSON)
	elif GameState.get_bool(PrologueFlags.Q_TALKED):
		_maybe_offer_rehearsal()


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


# --- interaction routing ----------------------------------------------------

func _on_target_changed(target: Interactable3D) -> void:
	if _busy or hud == null:
		return
	if target == null:
		hud.hide_prompt()
		return
	hud.show_prompt(target.get_prompt_text(), target.short_label)


func _on_interaction_pressed(target: Interactable3D) -> void:
	if _busy or target == null:
		return
	_handle_interact_id(target.interact_id)


func _handle_interact_id(interact_id: StringName) -> void:
	match interact_id:
		&"schoolbag":
			_inspect(&"schoolbag")
		&"own_desk", &"set_square", &"teacher_desk", &"chalkboard", &"timetable", &"window":
			_inspect(interact_id)
		&"q":
			_talk_to_q()
		&"door":
			_try_door()
		&"threshold_yard":
			_reach_gate()
		_:
			push_warning("PrologueFlow: no handler for interact id '%s'." % String(interact_id))


# --- Beat C/D: inspection ---------------------------------------------------

func _inspect(inspect_id: StringName) -> void:
	var entry: Dictionary = PrologueInspections.get_entry(inspect_id)
	if entry.is_empty():
		push_error("PrologueFlow: no inspection content for '%s'." % String(inspect_id))
		return
	var repeated: bool = false
	var record_id: StringName = StringName(entry.get("record", &""))
	if not String(record_id).is_empty() and PrologueState.has_record(record_id):
		repeated = true

	_set_busy(true)
	hud.hide_prompt()
	AudioCues.play(&"cloth" if inspect_id == &"schoolbag" else &"paper", -6.0)

	var text: String = String(entry["text"])
	if repeated and not String(entry.get("repeat", "")).is_empty():
		text = String(entry["repeat"])
	inspection_card.show_entry(String(entry["title"]), text, repeated)

	# Consequences are applied on first inspection only; repeat inspections are
	# read-only, which is what makes narrative state behave consistently.
	if not repeated:
		if not String(record_id).is_empty():
			PrologueState.record(record_id)
		var flag: StringName = StringName(entry.get("flag", &""))
		if not String(flag).is_empty():
			PrologueState.set_flag(flag, true)
		var extra: StringName = StringName(entry.get("extra_flag", &""))
		if not String(extra).is_empty():
			PrologueState.set_flag(extra, true)
		if inspect_id == &"schoolbag":
			hud.set_objective("You have no textbook. Q is still talking.", 6.0)
			PrologueState.record(PrologueRecords.ID_BAG_EMPTY_TEXTBOOK)


func _on_inspection_dismissed() -> void:
	_set_busy(false)
	_maybe_offer_rehearsal()


# --- Beat B: Q --------------------------------------------------------------

func _start_q_conversation() -> void:
	if not _q_present:
		return
	_set_beat(BEAT_Q)
	_set_busy(true)
	if _npc_q != null and player != null:
		_npc_q.face_point(player.global_position)
		player.look_at_point(_npc_q.global_position)
	_run_script(PrologueDialogue.q_conversation())


func _talk_to_q() -> void:
	if not _q_present:
		return
	_set_busy(true)
	if GameState.get_bool(PrologueFlags.LESSON_STARTED):
		_run_script(PrologueDialogue.q_after_bell())
	elif GameState.get_bool(PrologueFlags.Q_TALKED):
		_run_script(PrologueDialogue.q_repeat())
	else:
		_run_script(PrologueDialogue.q_conversation())


# --- dialogue runtime driving ----------------------------------------------

func _run_script(script: DialogueScript) -> void:
	if _session != null:
		_disconnect_session()
	_session = DialogueSession.new()
	_session.line_presented.connect(_on_line_presented)
	_session.choices_presented.connect(_on_choices_presented)
	_session.flags_requested.connect(_on_flags_requested)
	_session.records_requested.connect(_on_records_requested)
	_session.cue_requested.connect(_on_cue_requested)
	_session.session_finished.connect(_on_session_finished)
	if not _session.start(script, Callable(GameState, "get_flag")):
		push_error("PrologueFlow: dialogue script '%s' failed validation." % String(script.id))
		_set_busy(false)
		_session = null


func _on_line_presented(line: DialogueLine, history: Array) -> void:
	var imagined: bool = line.imagined or _session.is_imagining()
	dialogue_panel.present_line(line, imagined, history)
	if imagined:
		_set_beat(BEAT_REHEARSAL)
		if camera_focus_front != null:
			player.emphasise(camera_focus_front.global_position, 0.45)
		AudioCues.set_room_tone(0.0)
	else:
		AudioCues.set_room_tone(0.7)


func _on_choices_presented(choices: Array) -> void:
	dialogue_panel.present_choices(choices)


func _on_advance_requested() -> void:
	if _session == null or _session.is_finished():
		return
	_session.advance()


func _on_choice_chosen(index: int) -> void:
	if _session == null:
		return
	_session.choose(index)


func _on_flags_requested(flags: Dictionary) -> void:
	for flag_name in flags.keys():
		PrologueState.set_flag(StringName(flag_name), flags[flag_name])
	if flags.has(PrologueFlags.Q_ATTITUDE):
		_refresh_q_demeanour(String(flags[PrologueFlags.Q_ATTITUDE]))


func _on_records_requested(record_ids: Array[StringName]) -> void:
	var imagining: bool = _session != null and _session.is_imagining()
	_apply_records(record_ids, imagining)


## Applies a group of ledger records. When the session is in a rehearsal, a
## non-imagined record would be a content bug: the protagonist cannot *observe*
## anything inside their own head. Refusing loudly is better than quietly
## recording a fake fact.
func _apply_records(record_ids: Array[StringName], imagining: bool) -> void:
	for record_id in record_ids:
		var entry: Dictionary = PrologueRecords.entry_for(record_id)
		if entry.is_empty():
			push_error("PrologueFlow: unknown record id '%s'." % String(record_id))
			continue
		if imagining and entry["kind"] != NarrativeRecord.Kind.IMAGINED:
			push_error(
				"PrologueFlow: record '%s' (%s) was requested during a rehearsal."
				% [String(record_id), NarrativeRecord.kind_label(entry["kind"])]
			)
			continue
		PrologueState.record(record_id)


func _on_cue_requested(cue: StringName) -> void:
	match cue:
		&"enter_anticipation":
			_enter_rehearsal_presentation()
		&"exit_anticipation":
			_exit_rehearsal_presentation()
		&"bell":
			AudioCues.play(&"bell", -4.0)


func _on_session_finished(script_id: StringName) -> void:
	_disconnect_session()
	_session = null
	dialogue_panel.close()
	player.emphasise(player.global_position, 0.0)
	AudioCues.set_room_tone(0.7)

	match script_id:
		&"q_opening":
			_set_beat(BEAT_EXPLORE)
			_set_busy(false)
			hud.set_objective("Check your schoolbag.", 7.0)
			PrologueState.set_flag(PrologueFlags.Q_TALKED, true)
			_maybe_offer_rehearsal()
		&"anticipation":
			_set_busy(false)
			hud.show_caption("You are still in the classroom. Nothing has happened yet.", 3.2)
			_maybe_offer_rehearsal()
		&"n_lesson":
			_set_busy(false)
			_open_classroom()
			_set_beat(BEAT_FREE)
			hud.set_objective("The door is open. The corridor is your decision.", 8.0)
		&"q_parting":
			_set_busy(false)
		_:
			_set_busy(false)


func _disconnect_session() -> void:
	if _session == null:
		return
	if _session.line_presented.is_connected(_on_line_presented):
		_session.line_presented.disconnect(_on_line_presented)
	if _session.choices_presented.is_connected(_on_choices_presented):
		_session.choices_presented.disconnect(_on_choices_presented)
	if _session.flags_requested.is_connected(_on_flags_requested):
		_session.flags_requested.disconnect(_on_flags_requested)
	if _session.records_requested.is_connected(_on_records_requested):
		_session.records_requested.disconnect(_on_records_requested)
	if _session.cue_requested.is_connected(_on_cue_requested):
		_session.cue_requested.disconnect(_on_cue_requested)
	if _session.session_finished.is_connected(_on_session_finished):
		_session.session_finished.disconnect(_on_session_finished)


# --- Beat E: rehearsal ------------------------------------------------------

## Entering the rehearsal is possible once the player knows the textbook is
## missing and has actually talked to Q. It is optional, repeatable at most once
## per state, and it never advances the lesson clock by itself.
func _maybe_offer_rehearsal() -> void:
	if _busy:
		return
	if _session != null and not _session.is_finished():
		return
	if GameState.get_bool(PrologueFlags.ANTICIPATION_ENTERED) and GameState.get_bool(PrologueFlags.ANTICIPATION_EXITED):
		return
	if not GameState.get_bool(PrologueFlags.TEXTBOOK_MISSING):
		return
	if not GameState.get_bool(PrologueFlags.Q_TALKED):
		return
	if GameState.get_bool(PrologueFlags.LESSON_STARTED):
		return
	_awaiting_rehearsal = true
	_set_busy(true)
	await _wait(beat_pause_seconds)
	if not _awaiting_rehearsal:
		return
	_awaiting_rehearsal = false
	_start_rehearsal()


func _start_rehearsal() -> void:
	_set_busy(true)
	_set_beat(BEAT_REHEARSAL)
	_run_script(PrologueDialogue.anticipation())


func _enter_rehearsal_presentation() -> void:
	var room := get_parent().get_node_or_null("Classroom") as ClassroomLocation
	if room != null:
		room.set_rehearsal_lighting(true)
	hud.show_caption("Rehearsal — what you are picturing has not happened.", 4.0)
	AudioCues.play(&"distant", -10.0)


func _exit_rehearsal_presentation() -> void:
	var room := get_parent().get_node_or_null("Classroom") as ClassroomLocation
	if room != null:
		room.set_rehearsal_lighting(false)


# --- Beat F: bell, absence, substitute --------------------------------------

## Called by the lesson clock (or by tests) to move the world to third period.
func ring_bell() -> void:
	if GameState.get_bool(PrologueFlags.BELL_RUNG):
		return
	PrologueState.set_flag(PrologueFlags.BELL_RUNG, true)
	PrologueState.record(PrologueRecords.ID_BELL)
	AudioCues.play(&"bell", -3.0)
	hud.show_caption("The bell. Third period.", 2.6)
	_set_beat(BEAT_LESSON)
	PrologueState.set_flag(PrologueFlags.LESSON_STARTED, true)
	if _session != null:
		return
	_set_busy(true)
	await _wait(2.2)
	_begin_lesson()


func _begin_lesson() -> void:
	# B does not arrive. The evidence is an absence: an empty chair, a class that
	# waits, and the door staying shut a beat too long.
	PrologueState.set_flag(PrologueFlags.B_ABSENT_CONFIRMED, true)
	PrologueState.record(PrologueRecords.ID_B_ABSENT)
	hud.show_caption("Nobody comes in. The chair stays empty.", 3.0)
	await _wait(2.4)
	_npc_n.set_visible_actor(false)
	_set_beat(BEAT_LESSON)
	AudioCues.play(&"door", -4.0)
	await _wait(0.5)
	_npc_n.set_visible_actor(true)
	if camera_focus_front != null:
		player.emphasise(camera_focus_front.global_position, 0.6)
	_n_entered = true
	_run_script(PrologueDialogue.n_lesson())


func _open_classroom() -> void:
	var room := get_parent().get_node_or_null("Classroom") as ClassroomLocation
	if room != null:
		room.set_door_open(true)
	_enable_door(true)


func _enable_door(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := node as Interactable3D
		if interactable != null and interactable.interact_id == &"door":
			interactable.set_enabled(enabled)


# --- Beat G: exit -----------------------------------------------------------

func _try_door() -> void:
	if _exiting:
		return
	if not GameState.get_bool(PrologueFlags.N_CLASS_PERMITTED):
		_inspect(&"door_locked")
		return
	_leave_classroom()


func _leave_classroom() -> void:
	_exiting = true
	_set_busy(true)
	AudioCues.play(&"door", -4.0)
	# State is committed when the player decides to leave, not when the fade ends:
	# a transition that is interrupted mid-fade must not lose the decision.
	PrologueState.set_flag(PrologueFlags.CLASSROOM_EXITED, true)
	_set_beat(BEAT_EXIT)
	await hud.fade_to(1.0, 0.55)
	_set_busy(false)
	flow_finished.emit()
	_exiting = false


func _reach_gate() -> void:
	if GameState.get_bool(PrologueFlags.GATE_REACHED):
		return
	PrologueState.set_flag(PrologueFlags.GATE_REACHED, true)
	PrologueState.record(PrologueRecords.ID_GATE)
	hud.show_caption("The gate is open a hand's width. Nobody is guarding it.", 3.4)
	hud.set_objective("End of this milestone. The street is next.", 0.0)


# --- helpers ----------------------------------------------------------------

func _set_beat(beat: StringName) -> void:
	if _beat == beat:
		return
	_beat = beat
	beat_changed.emit(beat)


func _set_busy(value: bool) -> void:
	_busy = value
	if player != null:
		player.set_input_enabled(not value)
	if hud != null:
		if value:
			hud.hide_prompt()
		else:
			var target: Interactable3D = player.current_target() if player != null else null
			if target != null:
				hud.show_prompt(target.get_prompt_text(), target.short_label)


func _refresh_q_demeanour(attitude: String) -> void:
	if _npc_q == null:
		return
	# Presentation only: posture changes with how the player has been treating Q.
	match attitude:
		"warm":
			_npc_q.rotation_degrees.y = 195.0
		"guarded":
			_npc_q.rotation_degrees.y = 205.0
		_:
			_npc_q.rotation_degrees.y = 200.0


func _on_notebook_requested() -> void:
	if _busy:
		return
	note_book.toggle(NarrativeLedger)


func _on_notebook_closed() -> void:
	pass
