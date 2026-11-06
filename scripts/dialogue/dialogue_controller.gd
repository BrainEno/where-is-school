class_name DialogueController
extends Node
## Owns the presentation side of conversations and inspections.
##
## Responsibilities:
## - load dialogue/inspection content once and report load errors;
## - drive the DialogueRuntime and mirror its events into the DialoguePanel;
## - turn the first read of an inspectable object into one or two lines
##   (observation, then an optional uncertain recollection) and apply the
##   object's state changes;
## - keep the backlog complete.
##
## It does not move the player, load scenes, or decide story progression: the
## sequence director listens to `presentation_active_changed`.

signal presentation_active_changed(active: bool)
signal conversation_started(conversation_id: StringName)
signal conversation_finished(conversation_id: StringName)
signal line_presented(line: Dictionary)
## True while a subjective (imagined) conversation is on screen.
signal subjective_changed(active: bool)

enum Mode { NONE, CONVERSATION, INSPECTION }

@export var panel_path: NodePath = ^"../GameUI/DialoguePanel"
@export var backlog_path: NodePath = ^"../GameUI/BacklogPanel"

var _game_state: Node = null
var _narrative_state: Node = null
var _characters: CharacterDirectory = null
var _library: DialogueLibrary = null
var _inspections: InspectionLibrary = null
var _runtime: DialogueRuntime = null
var _panel: DialoguePanel = null
var _backlog: BacklogPanel = null

var _mode: Mode = Mode.NONE
var _queue: Array = []
var _subjective: bool = false


func _ready() -> void:
	_game_state = get_node_or_null(^"/root/GameState")
	if _game_state == null:
		push_error("DialogueController: GameState autoload is missing; story flags cannot be written.")
	_narrative_state = get_node_or_null(^"/root/NarrativeState")
	if _narrative_state == null:
		push_error("DialogueController: NarrativeState autoload is missing; knowledge cannot be recorded.")

	_panel = get_node_or_null(panel_path) as DialoguePanel
	if _panel == null:
		push_error("DialogueController: dialogue panel not found at '%s'." % panel_path)
		return
	_backlog = get_node_or_null(backlog_path) as BacklogPanel
	if _backlog == null:
		push_error("DialogueController: backlog panel not found at '%s'." % backlog_path)

	_characters = CharacterDirectory.load_all()
	for message in _characters.errors:
		push_error("DialogueController: %s" % message)

	_library = DialogueLibrary.load_all()
	if not _library.is_valid():
		push_error("DialogueController: %s" % _library.describe_errors())

	_inspections = InspectionLibrary.load_all()
	if not _inspections.is_valid():
		push_error("DialogueController: %s" % _inspections.describe_errors())

	_runtime = DialogueRuntime.new(_game_state, _narrative_state, _characters)
	_runtime.line_changed.connect(_on_line_changed)
	_runtime.choices_changed.connect(_on_choices_changed)
	_runtime.conversation_started.connect(_on_runtime_conversation_started)
	_runtime.conversation_finished.connect(_on_runtime_conversation_finished)

	_panel.advance_requested.connect(_on_advance_requested)
	_panel.choice_selected.connect(_on_choice_selected)
	_panel.backlog_requested.connect(_on_backlog_requested)
	if _backlog != null:
		_backlog.hide()


func is_busy() -> bool:
	return _mode != Mode.NONE


func get_mode() -> Mode:
	return _mode


func get_dialogue_library() -> DialogueLibrary:
	return _library


func get_inspection_library() -> InspectionLibrary:
	return _inspections


## True while the current presentation is waiting for the player to pick a choice.
func has_pending_choices() -> bool:
	return _mode == Mode.CONVERSATION and _runtime != null and _runtime.is_awaiting_choice()


## True while a subjective (imagined) sequence is on screen.
func is_presenting_subjective() -> bool:
	return _subjective


## Presentation intents, exposed for automated tests and for a future input
## remapping layer. The UI calls the same code paths through signals.
func advance_presentation() -> void:
	_on_advance_requested()


func select_choice(index: int) -> void:
	_on_choice_selected(index)


## Starts an authored conversation. Returns false when content is missing or a
## presentation is already running.
func play_conversation(conversation_id: StringName) -> bool:
	if is_busy():
		push_error("DialogueController: cannot start '%s' while busy." % conversation_id)
		return false
	if _library == null:
		push_error("DialogueController: dialogue library failed to load.")
		return false
	var graph := _library.get_graph(conversation_id)
	if graph == null:
		push_error("DialogueController: unknown conversation '%s'." % conversation_id)
		return false

	_mode = Mode.CONVERSATION
	_set_active(true)
	if not _runtime.start(graph, conversation_id):
		_mode = Mode.NONE
		_set_active(false)
		return false
	return true


## Shows an inspectable object. The first read applies its effects, records its
## knowledge entry, and may add a separate recollection line; later reads show
## only the repeat text and change nothing.
func present_inspection(inspection_id: StringName) -> bool:
	if is_busy():
		return false
	if _inspections == null:
		push_error("DialogueController: inspection library failed to load.")
		return false
	var inspection := _inspections.get_inspection(inspection_id)
	if inspection == null:
		push_error("DialogueController: unknown inspection '%s'." % inspection_id)
		return false

	var seen_flag := StoryFlags.inspection_seen_flag(inspection_id)
	var already_seen := bool(_game_state.get_flag(seen_flag, false))
	var shown_text := inspection.text
	if already_seen and not inspection.repeat_text.is_empty():
		shown_text = inspection.repeat_text

	_queue.clear()
	var observation := _build_inspection_line(inspection, shown_text)
	if not already_seen:
		observation["effects"] = inspection.effects
		observation["set_flag"] = seen_flag
		if not String(inspection.record_entry_id).is_empty():
			observation["record"] = {
				"entry_id": inspection.record_entry_id,
				"source": inspection.record_source,
				"speaker": inspection.speaker_id,
				"text": inspection.record_text,
			}
		if not inspection.recall_text.is_empty():
			var recall := _build_inspection_line(inspection, inspection.recall_text)
			recall["source"] = int(NarrativeEntry.Source.RECALLED)
			recall["badge"] = NarrativeEntry.badge_for(NarrativeEntry.Source.RECALLED)
			recall["title"] = "%s — remembered" % inspection.title
			recall["record"] = {
				"entry_id": inspection.recall_entry_id,
				"source": int(NarrativeEntry.Source.RECALLED),
				"speaker": inspection.speaker_id,
				"text": inspection.recall_text,
			}
			_queue.append(recall)
	_queue.push_front(observation)

	_mode = Mode.INSPECTION
	_set_active(true)
	_present_next_queued_line()
	return true


# --- Internals --------------------------------------------------------------


func _build_inspection_line(inspection: InspectionLibrary.InspectionData, text: String) -> Dictionary:
	var speaker_name := "You"
	var accent := Color(0.776, 0.733, 0.643, 1.0)
	if _characters != null:
		speaker_name = _characters.get_display_name(inspection.speaker_id)
		accent = _characters.get_accent_color(inspection.speaker_id)
	return {
		"conversation_id": &"",
		"node_id": &"",
		"speaker_id": inspection.speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": "",
		"accent_color": accent,
		"title": inspection.title,
		"text": text,
		"source": inspection.source,
		"badge": NarrativeEntry.badge_for(inspection.source),
		"subjective": false,
		"tags": PackedStringArray(),
	}


func _present_next_queued_line() -> void:
	if _queue.is_empty():
		_close_presentation()
		return
	var line: Dictionary = _queue.pop_front()
	_present_line(line)


func _present_line(line: Dictionary) -> void:
	_apply_line_state(line)
	_panel.show_line(line)
	if _backlog != null:
		_backlog.add_entry(line)
	var is_subjective := bool(line.get("subjective", false))
	if is_subjective != _subjective:
		_subjective = is_subjective
		subjective_changed.emit(_subjective)
	line_presented.emit(line)


## Applies the state changes a line carries. Only first reads and conversation
## effects carry any, so repeat visits stay side-effect free.
func _apply_line_state(line: Dictionary) -> void:
	if _game_state == null:
		return
	if line.has("effects"):
		for effect: Dictionary in line.get("effects", []):
			_apply_inspection_effect(effect)
	if line.has("record"):
		var record: Dictionary = line["record"]
		if _narrative_state != null:
			_narrative_state.record(
				StringName(String(record.get("entry_id", ""))),
				int(record.get("source", int(NarrativeEntry.Source.OBSERVED))),
				StringName(String(record.get("speaker", "protagonist"))),
				String(record.get("text", ""))
			)
	if line.has("set_flag"):
		_game_state.set_flag(StringName(String(line["set_flag"])), true)


func _apply_inspection_effect(effect: Dictionary) -> void:
	match String(effect.get("type", "")):
		"set_flag":
			_game_state.set_flag(StringName(String(effect.get("flag", ""))), effect.get("value", true))
		"set_objective":
			_game_state.set_flag(StoryFlags.OBJECTIVE_TEXT, String(effect.get("text", "")))
		_:
			push_error("DialogueController: unsupported inspection effect '%s'." % effect.get("type", ""))


func _on_line_changed(line: Dictionary) -> void:
	_present_line(line)


func _on_choices_changed(choices: Array) -> void:
	_panel.set_choices(choices)


func _on_runtime_conversation_started(conversation_id: StringName) -> void:
	conversation_started.emit(conversation_id)


func _on_runtime_conversation_finished(conversation_id: StringName) -> void:
	_close_presentation()
	conversation_finished.emit(conversation_id)


func _close_presentation() -> void:
	_queue.clear()
	_mode = Mode.NONE
	_panel.close()
	if _subjective:
		_subjective = false
		subjective_changed.emit(false)
	_set_active(false)


func _set_active(active: bool) -> void:
	presentation_active_changed.emit(active)


func _on_advance_requested() -> void:
	match _mode:
		Mode.CONVERSATION:
			_runtime.advance()
		Mode.INSPECTION:
			_present_next_queued_line()


func _on_choice_selected(index: int) -> void:
	if _mode != Mode.CONVERSATION:
		return
	_panel.set_choices([])
	_runtime.choose(index)


func _on_backlog_requested() -> void:
	if _backlog == null:
		return
	if _backlog.is_open():
		_backlog.close()
	else:
		_backlog.open()
