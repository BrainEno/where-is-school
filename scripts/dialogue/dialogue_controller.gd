class_name DialogueController
extends Node
## Owns the presentation side of conversations and inspections.
##
## Responsibilities:
## - load dialogue/inspection content for every language once and report errors;
## - drive the DialogueRuntime and mirror its events into the DialoguePanel;
## - turn the first read of an inspectable object into one or two lines
##   (observation, then an optional uncertain recollection) and apply the
##   object's state changes;
## - keep the backlog complete;
## - keep what is on screen in the language the player selected, including
##   halfway through a line;
## - remember, across runs, which lines were read and which options were taken
##   (`ReadLog`), and run the two reading modes, auto and skip (`DialoguePlayback`), by
##   calling the same advance path a key press calls.
##
## It does not move the player, load scenes, or decide story progression: the
## sequence director listens to `presentation_active_changed`.

signal presentation_active_changed(active: bool)
signal conversation_started(conversation_id: StringName)
signal conversation_finished(conversation_id: StringName)
signal line_presented(line: Dictionary)
## True while a subjective (imagined) conversation is on screen.
signal subjective_changed(active: bool)
## Emitted when the display language changed, so the HUD can re-apply its prompt.
signal locale_applied(locale: String)
## Emitted once per check, whether it was rolled now or replayed from a record.
signal check_resolved(result: Dictionary)
## Emitted when the first line of an inspection is on screen, so passive inner
## voices can react to *reading* something rather than to standing near it.
signal inspection_presented(inspection_id: StringName)

enum Mode { NONE, CONVERSATION, INSPECTION }

@export var panel_path: NodePath = ^"../GameUI/DialoguePanel"
@export var backlog_path: NodePath = ^"../GameUI/BacklogPanel"
@export var check_overlay_path: NodePath = ^"../GameUI/CheckOverlay"

var _game_state: Node = null
var _narrative_state: Node = null
var _characters: CharacterDirectory = null
var _library: DialogueLibrary = null
var _inspections: InspectionLibrary = null
var _runtime: DialogueRuntime = null
var _panel: DialoguePanel = null
var _backlog: BacklogPanel = null
var _overlay: CheckOverlay = null
var _abilities: InnerAbilities = null
var _resolver: CheckResolver = null

var _mode: Mode = Mode.NONE
var _queue: Array = []
var _subjective: bool = false
## Which inspection line is on screen, so a language switch can rebuild it.
var _active_inspection_id: StringName = &""
var _active_inspection_variant: String = ""
## The line the panel is showing right now, whatever produced it.
var _current_line: Dictionary = {}
## Every event the player has read, identified by content ids rather than by text.
## The backlog renders it; the tests read it to prove a language switch adds nothing.
var _history := DialogueHistory.new()
## True while a language switch is re-emitting the current line. The runtime cannot
## tell a rebind from a new node, so the controller says so explicitly instead of
## guessing from the text.
var _republishing: bool = false
## Lines read and options taken in any run. Shared with the settings screen.
var _read_log: ReadLog = null
## Auto and skip. Off (manual) until the player switches one on.
var _playback := DialoguePlayback.new()
## Whether the line on screen had been read before this showing: what skip goes by.
var _current_was_read := false
## The line on screen, not yet in the read log: {identity, locale, text}. A line is read once
## its whole text has been on screen (or the player moved past it), not when it starts to type.
var _pending_read: Dictionary = {}
## How much of the game's text has been read; built from the loaded content when first asked.
var _reading_progress: ReadingProgress = null
## The options on screen, with their ids, so a pick can be remembered.
var _current_choices: Array = []
## False while the window has lost focus: nothing is passed while nobody is looking.
var _window_focused := true


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

	# Inner voices load first, for two reasons: the character directory resolves every
	# voice's profile from the speaker id the registry declares (so a voice cannot be
	# added here in code), and the dialogue library refuses a check that names a voice
	# nobody implemented.
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		push_error("DialogueController: %s" % _abilities.describe_errors())

	_characters = CharacterDirectory.load_all(_abilities)
	for message in _characters.errors:
		push_error("DialogueController: %s" % message)
	# One resolver for the whole session. Its seed comes from the clock so two
	# playthroughs differ, but within a run every check is fixed by its own key:
	# leaving a scene and coming back cannot reroll anything.
	_resolver = CheckResolver.new(int(Time.get_unix_time_from_system()))

	_library = DialogueLibrary.load_all(_abilities)
	if not _library.is_valid():
		push_error("DialogueController: %s" % _library.describe_errors())

	_inspections = InspectionLibrary.load_all()
	if not _inspections.is_valid():
		push_error("DialogueController: %s" % _inspections.describe_errors())
	_report_content_load()

	_overlay = get_node_or_null(check_overlay_path) as CheckOverlay
	if _overlay == null:
		push_error("DialogueController: check overlay not found at '%s'." % check_overlay_path)

	_runtime = DialogueRuntime.new(_game_state, _narrative_state, _characters, _abilities, _resolver)
	_runtime.line_changed.connect(_on_line_changed)
	_runtime.check_resolved.connect(_on_check_resolved)
	_runtime.choices_changed.connect(_on_choices_changed)
	_runtime.conversation_started.connect(_on_runtime_conversation_started)
	_runtime.conversation_finished.connect(_on_runtime_conversation_finished)

	_panel.advance_requested.connect(_on_advance_requested)
	_panel.choice_selected.connect(_on_choice_selected)
	_panel.backlog_requested.connect(_on_backlog_requested)
	_panel.auto_toggle_requested.connect(_on_auto_toggle_requested)
	_panel.skip_requested.connect(_on_skip_requested)
	if _read_log == null:
		_read_log = ReadLog.shared()
	_playback.mode_changed.connect(_on_playback_mode_changed)
	_connect_playback_settings()
	if _backlog != null:
		_backlog.hide()
		# The backlog rebuilds past lines from their content ids; the controller knows
		# how to turn an id back into a line in the current language.
		_backlog.set_resolver(_render_entry)
	_panel.refresh_static_text()

	# The language switch lives in the Loc autoload; the controller owns the
	# re-render, so it listens directly instead of going through the UI.
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null and loc.has_signal("locale_changed"):
		loc.locale_changed.connect(apply_locale)


func is_busy() -> bool:
	return _mode != Mode.NONE


func get_mode() -> Mode:
	return _mode


## One start-up line for the whole text corpus, in debug builds only: how long loading
## every chapter in every language took, and what it produced. The libraries print their own
## per-chapter breakdown; this is the number that explains a slow start.
func _report_content_load() -> void:
	if not OS.is_debug_build():
		return
	if _library == null or _inspections == null:
		return
	var dialogue_report: Dictionary = _library.get_load_report()
	var inspection_report: Dictionary = _inspections.get_load_report()
	var total := int(dialogue_report.get("total_usec", 0))
	total += int(inspection_report.get("total_usec", 0))
	print(
		(
			"DialogueController: text corpus loaded in %.1f ms "
			+ "(%d dialogue language(s), %d inspection language(s))."
		)
		% [
			total / 1000.0,
			int(dialogue_report.get("locales", {}).size()),
			int(inspection_report.get("locales", {}).size()),
		]
	)


func get_dialogue_library() -> DialogueLibrary:
	return _library


func get_inspection_library() -> InspectionLibrary:
	return _inspections


func get_runtime() -> DialogueRuntime:
	return _runtime


func get_abilities() -> InnerAbilities:
	return _abilities


func get_check_resolver() -> CheckResolver:
	return _resolver


## Replaces the dice core. The session seed is otherwise taken from the clock, so a
## test uses this to force a known outcome instead of re-running until it is lucky.
func set_check_resolver(resolver: CheckResolver) -> void:
	_resolver = resolver if resolver != null else CheckResolver.new()
	if _runtime != null:
		_runtime.set_resolver(_resolver)


## The seed every check in this run is derived from. A save carries it, so a check
## re-entered after a load shows the same faces instead of pretending the dice are
## fresh (ADR 0005 §3). The per-check *result* is already a flag, so both the roll
## and the branch it chose survive.
func get_session_seed() -> int:
	return _resolver.get_session_seed() if _resolver != null else 0


func set_session_seed(seed_value: int) -> void:
	if _resolver == null:
		_resolver = CheckResolver.new(seed_value)
		if _runtime != null:
			_runtime.set_resolver(_resolver)
		return
	_resolver.set_session_seed(seed_value)


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


## The reading modes. Tests switch them through the same intents the panel sends.
func get_playback() -> DialoguePlayback:
	return _playback


func toggle_auto() -> void:
	_on_auto_toggle_requested()


func request_skip() -> void:
	_on_skip_requested()


func get_read_log() -> ReadLog:
	return _read_log


## Uses `log` for what was read, instead of the shared one. For tests that must not touch
## the player's file.
func set_read_log(replacement: ReadLog) -> void:
	_read_log = replacement if replacement != null else ReadLog.shared()


## Whether the line on screen had been read in an earlier showing.
## How much of the game's text has been read, in any run, as `ReadingProgress.measure()`
## gives it for the language on screen. Measured on every call, so it is always current.
func get_reading_progress() -> Dictionary:
	if _reading_progress == null:
		_reading_progress = ReadingProgress.build(_library, _inspections)
	return _reading_progress.measure(_read_log, L10n.current)


func was_current_line_read() -> bool:
	return _current_was_read


## The line the player is currently reading, if any. Used by tests and by the
## language switch to prove the same line is re-rendered.
func get_current_line() -> Dictionary:
	if not _current_line.is_empty():
		return _current_line
	if _mode == Mode.CONVERSATION and _runtime != null:
		return _runtime.get_current_line()
	return {}


## Switches the display language. Safe mid-scene: texts are re-rendered from the
## same node ids and no effect is applied twice.
func apply_locale(locale: String) -> bool:
	if _library == null or _inspections == null:
		return false
	var code := L10n.normalize(locale)
	if not _library.set_locale(code):
		return false
	_inspections.set_locale(code)
	if _abilities != null:
		_abilities.set_locale(code)
	# Everything inside this window is a re-render of the line already on screen. The
	# runtime re-emits it, and the controller must not treat that as a new event: no
	# effect, no record, no flag, no new backlog row.
	_republishing = true
	if _mode == Mode.CONVERSATION and _runtime != null and _runtime.is_active():
		var graph := _library.get_graph(_runtime.get_active_conversation_id())
		_runtime.rebind_graph(graph)
	elif _mode == Mode.INSPECTION and not String(_active_inspection_id).is_empty():
		_refresh_inspection_text()
	_republishing = false
	if _panel != null:
		_panel.refresh_static_text()
	if _backlog != null:
		_backlog.rebuild()
	locale_applied.emit(code)
	return true


## Localized prompt for an interactable: "Look at", "Talk to Q", "Try the door".
## Content data (inspection prompt, locale key) wins over the scene's fallback
## text, so no scene needs editing when a language is added.
func get_interact_prompt(interactable: Interactable) -> String:
	if interactable == null:
		return ""
	var override_key := interactable.get_prompt_override()
	if not override_key.is_empty():
		var resolved := _resolve_key(override_key, interactable)
		if not resolved.is_empty():
			return resolved
	if not String(interactable.inspection_id).is_empty() and _inspections != null:
		var inspection := _inspections.get_inspection(interactable.inspection_id)
		if inspection != null and not inspection.prompt.is_empty():
			return inspection.prompt
	if not interactable.prompt_key.is_empty():
		var resolved := _resolve_key(interactable.prompt_key, interactable)
		if not resolved.is_empty():
			return resolved
	return interactable.get_prompt()


func _resolve_key(key: String, interactable: Interactable) -> String:
	if not L10n.has_key(key):
		return ""
	var args := {}
	if not String(interactable.speaker_id).is_empty():
		args["name"] = _characters.get_display_name(interactable.speaker_id) if _characters != null else String(interactable.speaker_id)
	return L10n.t(key, args)


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

	var already_seen := bool(_game_state.get_flag(StoryFlags.inspection_seen_flag(inspection_id), false))
	_queue.clear()
	var observation := _build_inspection_line(inspection, _observation_text(inspection, already_seen))
	if not already_seen:
		observation["effects"] = inspection.effects
		observation["set_flag"] = StoryFlags.inspection_seen_flag(inspection_id)
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
			recall["badge"] = NarrativeEntry.badge_key_for(NarrativeEntry.Source.RECALLED)
			recall["title"] = _recall_title(inspection)
			recall["variant"] = "recall"
			recall["record"] = {
				"entry_id": inspection.recall_entry_id,
				"source": int(NarrativeEntry.Source.RECALLED),
				"speaker": inspection.speaker_id,
				"text": inspection.recall_text,
			}
			_queue.append(recall)
	observation["variant"] = "repeat" if already_seen else "first"
	_queue.push_front(observation)

	_mode = Mode.INSPECTION
	_set_active(true)
	_present_next_queued_line()
	# Announced only after the text is on screen, so a voice that reacts to reading
	# cannot talk over the line the player is still being shown.
	inspection_presented.emit(inspection_id)
	return true


# --- Internals --------------------------------------------------------------


func _observation_text(inspection: InspectionLibrary.InspectionData, already_seen: bool) -> String:
	if already_seen and not inspection.repeat_text.is_empty():
		return inspection.repeat_text
	return inspection.text


func _recall_title(inspection: InspectionLibrary.InspectionData) -> String:
	return String(inspection.title)


func _build_inspection_line(
	inspection: InspectionLibrary.InspectionData, text: String
) -> Dictionary:
	var speaker_name := "You"
	var accent := Palette.ACCENT
	if _characters != null:
		speaker_name = _characters.get_display_name(inspection.speaker_id)
		accent = _characters.get_accent_color(inspection.speaker_id)
	return {
		"conversation_id": &"",
		"node_id": &"",
		"speaker_id": inspection.speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": _role_text(inspection.speaker_id),
		"accent_color": accent,
		"title": inspection.title,
		"text": text,
		"source": inspection.source,
		"badge": NarrativeEntry.badge_key_for(inspection.source),
		"subjective": false,
		"tags": PackedStringArray(),
		"inspection_id": inspection.inspection_id,
	}


func _role_text(speaker_id: StringName) -> String:
	if String(speaker_id).is_empty():
		return ""
	var key := "role.%s" % String(speaker_id)
	if L10n.has_key(key):
		return L10n.t(key)
	if _characters != null:
		return _characters.get_short_role(speaker_id)
	return ""


func _present_next_queued_line() -> void:
	if _queue.is_empty():
		_close_presentation()
		return
	var line: Dictionary = _queue.pop_front()
	_present_line(line)


func _present_line(line: Dictionary, republished: bool = false) -> void:
	if republished:
		_publish_again(line)
		return
	_current_line = line
	var descriptor := _descriptor(line)
	_history.record(descriptor)
	_apply_line_state(line)
	_remember_line(line, String(descriptor.get("identity", "")))
	_panel.show_line(line)
	_commit_read_if_shown()
	if _backlog != null:
		_backlog.add_entry(descriptor)
	var is_subjective := bool(line.get("subjective", false))
	if is_subjective != _subjective:
		_subjective = is_subjective
		subjective_changed.emit(_subjective)
	line_presented.emit(line)


## Replaces what is on screen with the same event, said in the language that is now
## selected. The backlog row is updated in place when it is the newest one; if the
## identity does not match, the line is genuinely new and is appended, because two
## different events must never collapse into one row.
func _publish_again(line: Dictionary) -> void:
	_current_line = line
	var descriptor := _descriptor(line)
	_history.update_last(descriptor)
	# The same line in the language now selected: remembered in that language too, once it
	# is all on screen, but it is not a new line, so playback's clock and the "read before"
	# answer stay as they were. If the old text was still typing, it was never read whole,
	# so only the new one is waiting to be.
	_pending_read = {
		"identity": String(descriptor.get("identity", "")),
		"locale": L10n.current,
		"text": String(line.get("text", "")),
	}
	_panel.show_line(line, true)
	_commit_read_if_shown()
	if _backlog != null:
		_backlog.replace_last(descriptor)


## Re-renders the line currently on screen after a language change. Only the visible
## text is rebuilt; state stays exactly as it was.
func _refresh_inspection_text() -> void:
	var inspection := _inspections.get_inspection(_active_inspection_id)
	if inspection == null:
		return
	var line := _compose_inspection(inspection, _active_inspection_variant)
	if String(line.get("text", "")).is_empty():
		return
	_present_line(line, true)


## Rebuilds one inspection line from its id and variant, in the current language. Used
## both for the line on screen and for the backlog, so first read, repeat read and
## recollection keep their own text, badge and title after any number of switches.
func _compose_inspection(
	inspection: InspectionLibrary.InspectionData, variant: String
) -> Dictionary:
	var chosen := variant
	if chosen.is_empty():
		chosen = "first"
	var text := inspection.text
	var badge_source := inspection.source
	if chosen == "repeat":
		text = _observation_text(inspection, true)
	elif chosen == "recall":
		text = inspection.recall_text
		badge_source = NarrativeEntry.Source.RECALLED
	var line := _build_inspection_line(inspection, text)
	line["variant"] = chosen
	line["source"] = int(badge_source)
	line["badge"] = NarrativeEntry.badge_key_for(badge_source)
	if chosen == "recall":
		line["title"] = _recall_title(inspection)
	return line


## What the history and the backlog store: the line plus its identity, with everything
## that changes the world removed. A rebuild re-renders text; it can never re-apply an
## effect, re-record knowledge, or flip a flag, because those keys are not kept.
func _descriptor(line: Dictionary) -> Dictionary:
	var entry := line.duplicate(true)
	entry["identity"] = DialogueHistory.identify(line)
	for key in ["effects", "record", "set_flag"]:
		entry.erase(key)
	return entry


## Turns a stored descriptor back into a line in the current language. The backlog
## calls this on a language switch; it reads content and never writes state.
func _render_entry(descriptor: Dictionary) -> Dictionary:
	var conversation_id := StringName(String(descriptor.get("conversation_id", "")))
	var node_id := StringName(String(descriptor.get("node_id", "")))
	if not String(conversation_id).is_empty() and _library != null:
		var graph := _library.get_graph(conversation_id)
		if graph != null:
			var conversation := graph.get_conversation(conversation_id)
			if conversation != null:
				var node: DialogueGraph.DialogueNode = conversation.nodes.get(node_id, null)
				if node != null:
					return DialogueRuntime.compose_line(
						conversation, node, _characters, _abilities
					)
	var inspection_id := StringName(String(descriptor.get("inspection_id", "")))
	if not String(inspection_id).is_empty() and _inspections != null:
		var inspection := _inspections.get_inspection(inspection_id)
		if inspection != null:
			return _compose_inspection(inspection, String(descriptor.get("variant", "first")))
	# Last resort: the text the row was created with, so a row is never blank.
	return descriptor.duplicate(true)


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
	# Remember which inspection line is visible so a language switch can rebuild it.
	if _mode == Mode.INSPECTION:
		_active_inspection_variant = String(line.get("variant", ""))
		_active_inspection_id = StringName(String(line.get("inspection_id", "")))


func _apply_inspection_effect(effect: Dictionary) -> void:
	match String(effect.get("type", "")):
		"set_flag":
			_game_state.set_flag(StringName(String(effect.get("flag", ""))), effect.get("value", true))
		"set_objective":
			_game_state.set_flag(StoryFlags.OBJECTIVE_KEY, String(effect.get("key", "")))
		_:
			push_error("DialogueController: unsupported inspection effect '%s'." % effect.get("type", ""))


func _on_line_changed(line: Dictionary) -> void:
	_present_line(line, _republishing)


# A visible check gets the numbers on screen; a hidden one gets nothing at all, so
# the only thing the player learns is what the voice said about it.
func _on_check_resolved(result: Dictionary) -> void:
	check_resolved.emit(result)
	if String(result.get("kind", "visible")) != "visible":
		return
	if _overlay == null:
		return
	var ability_id := StringName(String(result.get("ability", "")))
	var ability_name := ""
	if _abilities != null and _abilities.has_ability(ability_id):
		ability_name = _abilities.get_ability(ability_id).display_name
	_overlay.present(ability_id, ability_name, result)


func _on_choices_changed(choices: Array) -> void:
	_current_choices = []
	for choice: Variant in choices:
		var entry: Dictionary = (choice as Dictionary).duplicate()
		entry["chosen_before"] = _read_log != null and _read_log.has_chosen(_choice_identity(entry))
		_current_choices.append(entry)
	_panel.set_choices(_current_choices)


func _on_runtime_conversation_started(conversation_id: StringName) -> void:
	conversation_started.emit(conversation_id)


func _on_runtime_conversation_finished(conversation_id: StringName) -> void:
	_close_presentation()
	conversation_finished.emit(conversation_id)


func _close_presentation() -> void:
	_queue.clear()
	_current_choices = []
	# A line taken off screen before it had finished typing was not read.
	_commit_read_if_shown()
	_pending_read = {}
	# A presentation is a natural checkpoint for the read log: one write per conversation,
	# not one per line.
	if _read_log != null:
		_read_log.flush()
	if _overlay != null:
		_overlay.hide_check()
	_mode = Mode.NONE
	_active_inspection_id = &""
	_active_inspection_variant = ""
	_panel.close()
	if _subjective:
		_subjective = false
		subjective_changed.emit(false)
	_set_active(false)


func _set_active(active: bool) -> void:
	presentation_active_changed.emit(active)


func _on_advance_requested() -> void:
	# Moving on is the player saying the line has been read. The panel and auto only ask once
	# the text is all on screen; `advance_presentation()` from code is taken at its word.
	_commit_read()
	if _overlay != null:
		_overlay.hide_check()
	match _mode:
		Mode.CONVERSATION:
			_runtime.advance()
		Mode.INSPECTION:
			_present_next_queued_line()


func _on_choice_selected(index: int) -> void:
	if _mode != Mode.CONVERSATION:
		return
	_commit_read()
	if _read_log != null and index >= 0 and index < _current_choices.size():
		_read_log.mark_chosen(_choice_identity(_current_choices[index]))
	_current_choices = []
	_panel.set_choices([])
	_runtime.choose(index)


func _on_backlog_requested() -> void:
	if _backlog == null:
		return
	if _backlog.is_open():
		_backlog.close()
	else:
		_backlog.open()


# --- Read log and reading modes ----------------------------------------------------


## Takes the line that just appeared and tells playback about it. The "read before" answer
## is taken now, from the log as it was; the line itself goes into the log only once it has
## been shown whole (`_commit_read_if_shown`).
func _remember_line(line: Dictionary, identity: String) -> void:
	var text := String(line.get("text", ""))
	var locale := L10n.current
	_current_was_read = _read_log != null and _read_log.is_read(identity, locale, text)
	_pending_read = {"identity": identity, "locale": locale, "text": text}
	_playback.begin_line(identity, text.length(), _current_was_read, locale)


## Records the waiting line once the panel has finished typing it: at once with instant text,
## otherwise on the frame the last character appears (or the player completes it).
func _commit_read_if_shown() -> void:
	if _pending_read.is_empty() or not is_instance_valid(_panel) or _panel.is_revealing():
		return
	_commit_read()


func _commit_read() -> void:
	if _pending_read.is_empty():
		return
	if _read_log != null:
		_read_log.mark_read(
			String(_pending_read["identity"]), String(_pending_read["locale"]), String(_pending_read["text"])
		)
	_pending_read = {}


func _choice_identity(choice: Dictionary) -> String:
	if _runtime == null:
		return ""
	var line := _runtime.get_current_line()
	return ReadLog.choice_identity(
		_runtime.get_active_conversation_id(),
		StringName(String(line.get("node_id", ""))),
		StringName(String(choice.get("choice_id", "choice_%d" % int(choice.get("index", 0)))))
	)


func _process(delta: float) -> void:
	if _panel == null:
		return
	_commit_read_if_shown()
	if _playback.is_holding_skip() and not Input.is_action_pressed(&"dialogue_skip"):
		_playback.release_skip()
	var view := {
		"presenting": _mode != Mode.NONE and _panel.visible,
		"revealing": _panel.is_revealing(),
		"choices": _panel.has_choices(),
		"blocked": not _window_focused or (_backlog != null and _backlog.is_open()),
		"check": _overlay != null and _overlay.visible,
	}
	match _playback.tick(delta, view):
		DialoguePlayback.COMPLETE:
			_panel.complete_reveal()
		DialoguePlayback.ADVANCE:
			_on_advance_requested()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_window_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_window_focused = true
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			_commit_read_if_shown()
			if _read_log != null:
				_read_log.flush()


func _on_auto_toggle_requested() -> void:
	_playback.toggle_auto()


func _on_skip_requested() -> void:
	_playback.press_skip()


func _on_playback_mode_changed(mode: int, reason: StringName) -> void:
	var notice := ""
	if reason == DialoguePlayback.REASON_UNREAD:
		notice = L10n.t("ui.dialogue_skip_stopped")
	if _panel != null:
		_panel.set_playback_state(mode, notice)


func _connect_playback_settings() -> void:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null:
		return
	if not settings.is_connected("setting_changed", _on_playback_setting_changed):
		settings.connect("setting_changed", _on_playback_setting_changed)
	_on_playback_setting_changed(&"all")


func _on_playback_setting_changed(key: StringName) -> void:
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null:
		return
	if (key == &"all" or key == &"auto_speed") and settings.has_method("get_auto_speed"):
		_playback.set_auto_speed(StringName(settings.call("get_auto_speed")))
	if (key == &"all" or key == &"skip_scope") and settings.has_method("get_skip_scope"):
		_playback.set_skip_scope(StringName(settings.call("get_skip_scope")))
