class_name PrologueFlow
extends Node
## The one place where a conversation becomes a change in the world.
##
## Responsibilities:
## - own the NarrativeLedger and the active DialogueSession;
## - apply a node's/choice's flags and ledger records when they are reached;
## - hand framing instructions to the presentation layer (DialoguePanel, CameraRig,
##   HUD) without letting that layer decide story state;
## - translate specific story events into scene changes (Q speaking, N arriving,
##   the door unlocking).
##
## Non-responsibilities: geometry, prop placement, input mapping, save files.
##
## Every flag write goes through [method _set_flag] so that a test can assert the
## exact order of story-state changes.

signal dialogue_started(script_id: StringName)
signal dialogue_ended(script_id: StringName)
signal ledger_changed
signal prompt_changed(text_zh: String, text_en: String)
signal presentation_mode_changed(mode: int)

enum PresentationMode {
	NORMAL = 0,
	IMAGINED = 1,
}

## Exported so the main scene can wire the flow to concrete nodes by reference
## rather than by deep NodePaths.
@export var player_path: NodePath
@export var dialogue_panel_path: NodePath
@export var hud_path: NodePath
@export var director_path: NodePath

var ledger: NarrativeLedger = NarrativeLedger.new()
var session: DialogueSession = null
var active_script_id: StringName = &""
var presentation_mode: int = PresentationMode.NORMAL

var _player: PlayerController
var _panel: DialoguePanel
var _hud: PrologueHud
var _director: PrologueDirector
var _pending_release: bool = false
## What the sensor last focused, kept so the prompt can be re-rendered in the
## other language without waiting for the player to walk somewhere else.
var _focused: Interactable3D = null


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_panel = get_node_or_null(dialogue_panel_path) as DialoguePanel
	_hud = get_node_or_null(hud_path) as PrologueHud
	_director = get_node_or_null(director_path) as PrologueDirector

	if _player == null:
		push_error("PrologueFlow is missing the player reference (player_path).")
	if _panel == null:
		push_error("PrologueFlow is missing the dialogue panel reference (dialogue_panel_path).")
	if _director == null:
		push_error("PrologueFlow is missing the director reference (director_path).")

	if _panel != null:
		_panel.advance_requested.connect(_on_advance_requested)
		_panel.choice_selected.connect(_on_choice_selected)
		_panel.closed.connect(_on_panel_closed)
	ledger.entry_recorded.connect(_on_ledger_entry_recorded)


# ---------------------------------------------------------------- interaction

## Connected from the interaction sensor's focus_changed signal.
func set_focused_interactable(interactable: Interactable3D) -> void:
	_focused = interactable
	if session != null or _panel == null or _panel.visible:
		return
	if interactable == null:
		_emit_prompt("", "")
		return
	var key_hint: String = _interact_key_label()
	_emit_prompt(
		"%s　%s" % [key_hint, _prompt_for(interactable, true)],
		"%s  %s" % [key_hint, _prompt_for(interactable, false)]
	)


func interact_with(interactable: Interactable3D) -> void:
	if session != null:
		return
	match interactable.kind:
		Interactable3D.Kind.INSPECT:
			_inspect(interactable.interact_id)
		Interactable3D.Kind.TALK:
			_talk(interactable.interact_id)
		Interactable3D.Kind.DOOR:
			_open_door(interactable)
		Interactable3D.Kind.THRESHOLD:
			_reach_threshold(interactable)
		Interactable3D.Kind.SIT:
			_sit(interactable)
		_:
			push_warning("PrologueFlow does not know how to handle interactable '%s'." % interactable.interact_id)


## Re-emits the current interaction prompt (or the current status line) in the
## newly selected language. Called by main when the player switches languages.
func refresh_language() -> void:
	if session == null and _panel != null and not _panel.visible:
		set_focused_interactable(_focused)
	if _hud != null:
		_refresh_presentation()


func _prompt_for(interactable: Interactable3D, zh: bool) -> String:
	var verb: String = interactable.prompt_zh if zh else interactable.prompt_en
	var target: String = interactable.display_name_zh() if zh else interactable.display_name_en()
	var separator: String = "：" if zh else ": "
	return "%s%s%s" % [verb, separator, target]


func _interact_key_label() -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
	for event: InputEvent in events:
		var key := event as InputEventKey
		if key != null:
			return "[%s]" % OS.get_keycode_string(key.physical_keycode)
	return "[E]"


func _emit_prompt(zh: String, en: String) -> void:
	prompt_changed.emit(zh, en)
	if _hud != null:
		_hud.set_prompt(zh, en)


# ------------------------------------------------------------------ inspection

func _inspect(inspection_id: StringName) -> void:
	var script := ClassroomInspections.script_for(inspection_id, StoryFlags.snapshot())
	if script == null:
		push_error("No inspection content exists for '%s'." % inspection_id)
		return
	_begin_dialogue(script, _inspection_flag(inspection_id))


func _inspection_flag(inspection_id: StringName) -> Array:
	match inspection_id:
		ClassroomInspections.BAG:
			return [PrologueFlags.BAG_EXAMINED]
		ClassroomInspections.SET_SQUARE:
			return [PrologueFlags.SQUARE_EXAMINED]
		ClassroomInspections.TEACHER_DESK:
			return [PrologueFlags.TEACHER_DESK_EXAMINED]
		ClassroomInspections.TIMETABLE:
			return [PrologueFlags.TIMETABLE_EXAMINED]
		ClassroomInspections.CHAIR:
			return [PrologueFlags.CHAIR_EXAMINED]
		ClassroomInspections.WINDOW:
			return [PrologueFlags.WINDOW_EXAMINED]
	return []


# -------------------------------------------------------------------- talking

func _talk(interact_id: StringName) -> void:
	match interact_id:
		&"q":
			begin_q_conversation()
		&"n":
			begin_n_conversation()
		_:
			push_warning("PrologueFlow has no conversation for speaker '%s'." % interact_id)


func begin_q_conversation() -> void:
	if session != null:
		return
	if _director != null and _director.current_location_id != &"classroom":
		return
	_begin_dialogue(PrologueQConversation.build(), [])


func begin_n_conversation() -> void:
	if session != null:
		return
	_begin_dialogue(PrologueNConversation.build(), [])


## Second milestone: the residential lane and the ambiguous green animal.
func begin_street_observations() -> void:
	if session != null:
		return
	if StoryFlags.has_flag(PrologueFlags.STREET_RELEASE_NOTED) or _flow_street_seen():
		_show_status(
			"这条巷子我看过了。校门还在那里。",
			"I've already looked down this lane. The gate is still there."
		)
		return
	_begin_dialogue(StreetObservations.build(), [])


func _flow_street_seen() -> bool:
	return ledger.has(&"observed_street")


## Beat E entry point. Called by the anticipation interactable or by the
## classroom's "B has not arrived" beat.
func begin_anticipation() -> void:
	if session != null:
		return
	if StoryFlags.has_flag(PrologueFlags.BELL_RUNG):
		_show_status("钟响过了。现在想这个太晚了。", "The bell already rang. Too late for that now.")
		return
	_begin_dialogue(PrologueAnticipation.build(), [])


# ------------------------------------------------------------------- doors

func _open_door(interactable: Interactable3D) -> void:
	if not interactable.enabled:
		_show_status(
			"上课中。门关着。也不该由我来开。",
			"Class is on. The door is shut, and it isn't mine to open."
		)
		return
	_leave_classroom()


func _reach_threshold(interactable: Interactable3D) -> void:
	match interactable.interact_id:
		&"desk_think":
			begin_anticipation()
		&"corridor_classroom":
			if _director != null:
				_director.load_location(&"classroom")
		&"corridor_exit":
			_set_flag(PrologueFlags.EXIT_SEEN, true)
			if _director != null:
				_director.load_location(&"street")
		&"street_corridor":
			if _director != null:
				_director.load_location(&"corridor")
		&"street_gate":
			_set_flag(PrologueFlags.EXIT_REACHED, true)
			begin_street_observations()
		_:
			push_warning("Unknown threshold '%s'." % interactable.interact_id)


## Beat G: leaving the room proper. Only possible after N releases the class,
## which is expressed by the classroom having unlocked its door.
func _leave_classroom() -> void:
	if _director == null:
		return
	if not StoryFlags.has_flag(PrologueFlags.N_LET_CLASS_GO):
		_show_status(
			"还没下课。门开着走出去太明显。",
			"Class isn't over. Walking out through an open door is too obvious."
		)
		return
	_set_flag(PrologueFlags.LEFT_CLASSROOM, true)
	_set_flag(PrologueFlags.CORRIDOR_ENTERED, true)
	_director.load_location(&"corridor")


func _sit(interactable: Interactable3D) -> void:
	_show_status(
		"我刚才就是从这张椅子醒来的。现在不想再坐回去。",
		"This is the chair I woke up in. I don't want to sit back down in it."
	)


func _show_status(zh: String, en: String) -> void:
	if _hud != null:
		_hud.show_status(zh, en)


# --------------------------------------------------------------- dialogue core

func _begin_dialogue(script: DialogueScript, extra_flags: Array) -> void:
	if script == null:
		push_error("PrologueFlow was asked to begin a null dialogue script.")
		return
	var problems: Array[String] = script.validate()
	if not problems.is_empty():
		for problem: String in problems:
			push_error("Dialogue content error: %s" % problem)
		return

	session = DialogueSession.new(script)
	active_script_id = script.id
	var start_problems: Array[String] = session.start()
	if not start_problems.is_empty():
		for problem: String in start_problems:
			push_error("Dialogue start error: %s" % problem)
		session = null
		return

	for flag: StringName in extra_flags:
		_set_flag(flag, true)

	_player.set_input_enabled(false)
	_panel.open()
	_panel.set_backlog(session.backlog)
	dialogue_started.emit(script.id)
	_enter_current_node()


func _enter_current_node() -> void:
	if session == null or session.node == null:
		return
	var node: DialogueNode = session.node
	for flag: StringName in node.on_enter_flags:
		_set_flag(flag, true)
	for record: Dictionary in node.on_enter_records:
		_record(record)
	_refresh_presentation()
	if session.has_pending_line():
		_show_next_line()
	else:
		_after_node_lines()


func _show_next_line() -> void:
	if session == null:
		return
	var line: DialogueLine = session.advance()
	if line == null:
		_after_node_lines()
		return
	_panel.set_backlog(session.backlog)
	_panel.show_line(
		session.speaker_label_zh(line.speaker),
		session.speaker_label_en(line.speaker),
		line.text_zh,
		line.text_en,
		session.speaker_tint(line.speaker),
		NarrativeProvenance.label_zh(line.kind),
		NarrativeProvenance.label_en(line.kind),
		line.style,
		session.speaker_note_zh(line.speaker),
		session.speaker_note_en(line.speaker)
	)
	var more_lines: bool = session.has_pending_line()
	_panel.set_line_continues(more_lines or not session.node.choices.is_empty())
	# The last line of a node is shown together with its choices, so the player
	# reads the line that the choice answers instead of a blank panel.
	if not more_lines:
		_after_node_lines()


func _after_node_lines() -> void:
	if session == null:
		return
	if session.awaiting_choice():
		var labels: Array[Dictionary] = []
		for choice: DialogueChoice in session.choices():
			labels.append({
				"zh": choice.text_zh,
				"en": choice.text_en,
			})
		_panel.show_choices(labels)
	elif session.awaiting_continue():
		_panel.show_continue_hint()
	else:
		_close_dialogue()


func _on_advance_requested() -> void:
	if session == null:
		return
	if session.has_pending_line():
		_show_next_line()
		return
	if session.awaiting_choice():
		# Advance while a choice is open does nothing; the player must choose.
		return
	if session.node == null:
		_close_dialogue()
		return
	_apply_node_transition()


func _apply_node_transition() -> void:
	var completed_node_id: StringName = session.node.id
	var problems: Array[String] = session.follow_current()
	if not problems.is_empty():
		for problem: String in problems:
			push_error("Dialogue transition error: %s" % problem)
		_close_dialogue()
		return
	if session.finished:
		_close_dialogue()
		return
	_before_entering_node(completed_node_id, session.node.id)
	_enter_current_node()


func _on_choice_selected(index: int) -> void:
	if session == null or not session.awaiting_choice():
		return
	var available: Array[DialogueChoice] = session.choices()
	if index < 0 or index >= available.size():
		push_error("Dialogue panel reported choice index %d out of range." % index)
		return
	var choice: DialogueChoice = available[index]
	for flag: StringName in choice.flags:
		_set_flag(flag, true)
	for record: Dictionary in choice.records:
		_record(record)
	if not choice.aside_zh.is_empty():
		_record({
			"id": &"aside_" + String(choice.id),
			"kind": NarrativeProvenance.id_of(NarrativeProvenance.Kind.RECOLLECTED),
			"zh": choice.aside_zh,
			"en": choice.aside_en,
		})
	var completed_node_id: StringName = session.node.id
	var problems: Array[String] = session.follow(choice)
	if not problems.is_empty():
		for problem: String in problems:
			push_error("Dialogue choice error: %s" % problem)
		_close_dialogue()
		return
	_before_entering_node(completed_node_id, session.node.id)
	_panel.clear_choices()
	_enter_current_node()
	# After the first line of the new node is rendered, so entering the node does
	# not immediately clear the aside that belongs to this choice.
	if not choice.aside_zh.is_empty():
		_panel.append_aside(choice.aside_zh, choice.aside_en)


## Scene-side reactions to narrative transitions. Kept explicit rather than
## generic so the coupling stays readable.
func _before_entering_node(_from: StringName, to: StringName) -> void:
	match to:
		PrologueAnticipation.IMAGINE_START, PrologueAnticipation.IMAGINE_MIDDLE:
			_set_presentation_mode(PresentationMode.IMAGINED)
		PrologueAnticipation.IMAGINE_END, PrologueAnticipation.DECLINED:
			_set_presentation_mode(PresentationMode.NORMAL)


func _close_dialogue() -> void:
	var closing_id: StringName = active_script_id
	_set_presentation_mode(PresentationMode.NORMAL)
	session = null
	active_script_id = &""
	_panel.close()
	dialogue_ended.emit(closing_id)
	_player.set_input_enabled(true)
	_apply_post_dialogue_effects(closing_id)


## The two beats where finishing a conversation changes the room.
func _apply_post_dialogue_effects(closing_id: StringName) -> void:
	if closing_id == &"prologue_anticipation":
		# Beat F: the bell goes while the protagonist is still sitting with the
		# expectation. B does not come; N does.
		_start_bell_beat()
	if closing_id == &"prologue_n":
		_release_class()
	if closing_id == &"prologue_street":
		_show_ending()


func _start_bell_beat() -> void:
	if StoryFlags.has_flag(PrologueFlags.BELL_RUNG):
		return
	if _director == null or not (_director.current_location is Classroom):
		return
	var classroom := _director.current_location as Classroom
	_set_flag(PrologueFlags.BELL_RUNG, true)
	classroom.set_think_available(false)
	_director.ring_bell()
	_await_bell_then_substitute(classroom)


func _await_bell_then_substitute(classroom: Classroom) -> void:
	if _hud != null:
		_hud.show_status("钟响了。", "The bell rings.")
		_hud.flash_bell()
	await get_tree().create_timer(2.4).timeout
	if not is_inside_tree() or classroom == null or not is_instance_valid(classroom):
		return
	if _hud != null:
		_hud.show_status("B 没有来。", "B does not come.")
	_set_flag(PrologueFlags.B_ABSENCE_NOTED, true)
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree() or classroom == null or not is_instance_valid(classroom):
		return
	classroom.bring_in_substitute()
	await get_tree().create_timer(1.3).timeout
	if not is_inside_tree():
		return
	begin_n_conversation()


func _release_class() -> void:
	if not StoryFlags.has_flag(PrologueFlags.N_LET_CLASS_GO):
		push_error("PrologueFlow finished N's conversation without the release flag set.")
		return
	if _director != null and _director.current_location is Classroom:
		(_director.current_location as Classroom).set_released(true)
	if _hud != null:
		_hud.show_status(
			"教室的门现在可以开了。走廊的尽头有楼梯。",
			"The classroom door can be opened now. There are stairs at the end of the corridor."
		)


func _on_panel_closed() -> void:
	if session != null:
		# The panel should never close itself mid-conversation; if it does, end
		# cleanly rather than leaving input disabled.
		session = null
		_player.set_input_enabled(true)


func _set_presentation_mode(mode: int) -> void:
	if presentation_mode == mode:
		return
	presentation_mode = mode
	presentation_mode_changed.emit(mode)
	if _panel != null:
		_panel.set_imagined_mode(mode == PresentationMode.IMAGINED)
	if _hud != null:
		_hud.set_imagined_overlay(mode == PresentationMode.IMAGINED)


# ------------------------------------------------------------ state recording

func _set_flag(flag: StringName, value: Variant) -> void:
	if flag == &"":
		push_error("PrologueFlow received an empty flag id.")
		return
	StoryFlags.set_flag(flag, value)


func _record(record: Dictionary) -> void:
	var kind_id: String = str(record.get("kind", ""))
	var entry_id: StringName = StringName(str(record.get("id", "")))
	if entry_id == &"" or not NarrativeProvenance.has_id(kind_id):
		push_error("PrologueFlow received an invalid ledger record: %s" % record)
		return
	ledger.record(
		entry_id,
		NarrativeProvenance.from_id(kind_id),
		str(record.get("zh", "")),
		str(record.get("en", "")),
		active_script_id
	)


func _on_ledger_entry_recorded(_entry: NarrativeEntry) -> void:
	ledger_changed.emit()
	if _hud != null:
		_hud.set_note_available(ledger.count())


func _refresh_presentation() -> void:
	if _hud != null:
		_hud.set_note_available(ledger.count())


func _show_ending() -> void:
	if _hud != null:
		_hud.show_status(
			"校门。外面是一条普通的巷子，电动车停在楼下。\n"
			+ "第一里程碑到此结束——离开学校不是结束，只是走出去。",
			"The school gate. Outside is an ordinary lane, scooters parked under the arcade.\n"
			+ "First milestone ends here — leaving school isn't an ending, only stepping out."
		)


# ------------------------------------------------------------------- queries

func is_dialogue_active() -> bool:
	return session != null


func has_input_lock() -> bool:
	return session != null
