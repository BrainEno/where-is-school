class_name DialogueRuntime
extends RefCounted
## Graph walker for authored dialogue.
##
## The runtime knows nothing about UI nodes: it emits presentation events and
## writes story flags / narrative entries through explicit references. That keeps
## DialoguePanel replaceable and lets tests drive conversations headlessly.
##
## Subjective conversations (expectations, fantasies) are constrained here:
## they may never set gameplay flags or objectives, and may never record
## observed or reported knowledge. An imagined confrontation therefore cannot
## become part of the world state by accident.

signal line_changed(line: Dictionary)
signal choices_changed(choices: Array)
signal conversation_started(conversation_id: StringName)
signal conversation_finished(conversation_id: StringName)
signal narrative_entry_recorded(entry: NarrativeEntry)
signal effect_rejected(reason: String)

const MAX_STEPS_PER_CONVERSATION := 512

var _graph: DialogueGraph = null
var _conversation: DialogueGraph.Conversation = null
var _node: DialogueGraph.DialogueNode = null
var _active: bool = false
var _awaiting_choice: bool = false
var _steps: int = 0

var _game_state: Node = null
var _narrative_state: Node = null
var _characters: CharacterDirectory = null
var _checks: InnerCheckEngine = null
## Visible only on the first line after an active choice; re-rendered on locale switch.
var _displayed_check: Dictionary = {}


func _init(
	game_state: Node = null,
	narrative_state: Node = null,
	characters: CharacterDirectory = null,
	rng: Variant = null
) -> void:
	_game_state = game_state if game_state != null else _find_autoload("GameState")
	_narrative_state = narrative_state if narrative_state != null else _find_autoload("NarrativeState")
	_characters = characters if characters != null else CharacterDirectory.load_all()
	_checks = InnerCheckEngine.new(_game_state, rng)
	if _characters != null and not _characters.errors.is_empty():
		for message in _characters.errors:
			push_error("DialogueRuntime: %s" % message)


static func _find_autoload(node_name: String) -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root: Window = (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(NodePath(node_name))


func get_check_engine() -> InnerCheckEngine:
	return _checks


func is_active() -> bool:
	return _active


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func get_active_conversation_id() -> StringName:
	if _conversation == null:
		return &""
	return _conversation.conversation_id


func get_current_node_id() -> StringName:
	if _node == null:
		return &""
	return _node.node_id


func start(graph: DialogueGraph, conversation_id: StringName) -> bool:
	if _active:
		push_error("DialogueRuntime.start: a conversation is already running.")
		return false
	if graph == null:
		push_error("DialogueRuntime.start: no dialogue graph supplied.")
		return false
	var conversation := graph.get_conversation(conversation_id)
	if conversation == null:
		push_error("DialogueRuntime.start: unknown conversation '%s'." % conversation_id)
		return false
	if _game_state == null or _narrative_state == null:
		push_error("DialogueRuntime.start: GameState/NarrativeState autoloads are unavailable.")
		return false

	_graph = graph
	_conversation = conversation
	_active = true
	_steps = 0
	_displayed_check = {}
	conversation_started.emit(conversation_id)
	_enter_node(conversation.start_id)
	return true


## Player asked to continue past the current line. Returns false when a choice
## is pending (the player has to pick) or nothing is running.
func advance() -> bool:
	if not _active or _awaiting_choice or _node == null:
		return false
	_displayed_check = {}
	var next_id := _resolve_next_id(_node)
	if String(next_id).is_empty():
		_finish()
		return true
	_enter_node(next_id)
	return true


func choose(choice_index: int) -> bool:
	if not _active or _node == null:
		return false
	var available := _available_choices(_node)
	if choice_index < 0 or choice_index >= available.size():
		push_error(
			"DialogueRuntime.choose: choice index %d is out of range for node '%s'."
			% [choice_index, _node.node_id]
		)
		return false
	var choice: DialogueGraph.DialogueChoice = available[choice_index]
	var target := choice.next_id
	_displayed_check = {}
	if not choice.check.is_empty():
		var check: Dictionary = choice.check
		var result := _checks.attempt(StringName(check["id"]), StringName(check["ability"]), int(check["difficulty"]), "active")
		if result.is_empty():
			return false
		_displayed_check = result
		target = StringName(check["success"] if bool(result["success"]) else check["failure"])
	if choice.once:
		_set_flag(StoryFlags.choice_flag(_conversation.conversation_id, choice.choice_id), true)
	_apply_effects(choice.effects)
	_awaiting_choice = false
	_enter_node(target)
	return true


func get_current_line() -> Dictionary:
	if _node == null:
		return {}
	return _build_line(_node)


func get_current_choices() -> Array:
	if _node == null or not _awaiting_choice:
		return []
	var presented: Array = []
	var available := _available_choices(_node)
	for index in available.size():
		var choice: DialogueGraph.DialogueChoice = available[index]
		var text := choice.text
		if not choice.check.is_empty():
			var ability := StringName(choice.check["ability"])
			text = L10n.t("check.option", {"ability": InnerAbilities.display_name(ability),
				"rating": InnerAbilities.get_rating(_game_state, ability),
				"difficulty": int(choice.check["difficulty"]), "text": choice.text})
		presented.append({"index": index, "text": text})
	return presented


# --- Internals --------------------------------------------------------------


func _enter_node(node_id: StringName) -> void:
	# A node whose `conditions` are not met is skipped exactly like a `next` step:
	# its effects do not run and nothing is shown. That keeps optional lines
	# ("only if the player already asked about B") free of branching noise.
	var node: DialogueGraph.DialogueNode = null
	while true:
		_steps += 1
		if _steps > MAX_STEPS_PER_CONVERSATION:
			push_error(
				"DialogueRuntime: conversation '%s' exceeded %d steps, stopping. Check for a loop."
				% [_conversation.conversation_id, MAX_STEPS_PER_CONVERSATION]
			)
			_finish()
			return
		node = _conversation.nodes.get(node_id, null)
		if node == null:
			push_error(
				"DialogueRuntime: conversation '%s' has no node '%s'."
				% [_conversation.conversation_id, node_id]
			)
			_finish()
			return
		if _conditions_met(node.requires, node.all_flags, node.not_flags):
			break
		var skipped_target := _resolve_next_id(node)
		if String(skipped_target).is_empty():
			_finish()
			return
		node_id = skipped_target

	_node = node
	_apply_effects(node.effects)

	var available := _available_choices(node)
	_awaiting_choice = not available.is_empty()

	if not node.text.is_empty():
		line_changed.emit(get_current_line())
	if _awaiting_choice:
		choices_changed.emit(get_current_choices())


func _resolve_next_id(node: DialogueGraph.DialogueNode) -> StringName:
	if node.ends_here:
		return &""
	if not String(node.next_id).is_empty():
		return node.next_id
	var order_index := _conversation.order.find(node.node_id)
	if order_index >= 0 and order_index + 1 < _conversation.order.size():
		return _conversation.order[order_index + 1]
	return &""


func _available_choices(node: DialogueGraph.DialogueNode) -> Array:
	var result: Array = []
	for choice: DialogueGraph.DialogueChoice in node.choices:
		if choice.once and _get_flag(
			StoryFlags.choice_flag(_conversation.conversation_id, choice.choice_id), false
		):
			continue
		if not _conditions_met(choice.requires, choice.all_flags, choice.not_flags):
			continue
		result.append(choice)
	return result


func _conditions_met(
	requires: Dictionary, all_flags: Array[StringName], not_flags: Array[StringName]
) -> bool:
	if not _requirements_met(requires):
		return false
	for flag in all_flags:
		if not bool(_get_flag(flag, false)):
			return false
	for flag in not_flags:
		if bool(_get_flag(flag, false)):
			return false
	return true


## Swaps in the same conversation from another language. Only text is re-emitted;
## effects are *not* applied again, so switching language mid-scene can never
## rewrite story state.
func rebind_graph(new_graph: DialogueGraph) -> bool:
	if not _active or _conversation == null or new_graph == null:
		return false
	var conversation := new_graph.get_conversation(_conversation.conversation_id)
	if conversation == null:
		push_error(
			"DialogueRuntime.rebind_graph: '%s' is missing from %s."
			% [_conversation.conversation_id, new_graph.source_path]
		)
		return false
	var current_id: StringName = _node.node_id if _node != null else &""
	_graph = new_graph
	_conversation = conversation
	if String(current_id).is_empty():
		return true
	var node: DialogueGraph.DialogueNode = conversation.nodes.get(current_id, null)
	if node == null:
		push_error(
			"DialogueRuntime.rebind_graph: node '%s' is missing from %s."
			% [current_id, new_graph.source_path]
		)
		return false
	_node = node
	if not node.text.is_empty():
		line_changed.emit(get_current_line())
	if _awaiting_choice:
		choices_changed.emit(get_current_choices())
	return true


func _requirements_met(requires: Dictionary) -> bool:
	for flag: Variant in requires.keys():
		if _get_flag(StringName(String(flag)), null) != requires[flag]:
			return false
	return true


func _build_line(node: DialogueGraph.DialogueNode) -> Dictionary:
	var source_value: int = _conversation.default_source
	if node.source >= 0:
		source_value = node.source
	var speaker_id := node.speaker_id
	var speaker_name := String(speaker_id)
	var speaker_role := ""
	var accent_color := Color.WHITE
	if _characters != null:
		speaker_name = _characters.get_display_name(speaker_id)
		speaker_role = _characters.get_short_role(speaker_id)
		accent_color = _characters.get_accent_color(speaker_id)
	return {
		"conversation_id": _conversation.conversation_id,
		"node_id": node.node_id,
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": speaker_role,
		"accent_color": accent_color,
		"title": _check_title(),
		"text": node.text,
		"source": source_value,
		"badge": NarrativeEntry.badge_key_for(source_value),
		"subjective": _conversation.subjective,
		"tags": node.tags,
	}


## Only active checks supply a visible summary. Passive conversations have no
## numeric title; the same cached result survives a language switch.
func _check_title() -> String:
	if _displayed_check.is_empty() or String(_displayed_check.get("visibility", "")) != "active":
		return ""
	var result := _displayed_check
	var outcome := L10n.t("check.success" if bool(result["success"]) else "check.failure")
	return L10n.t("check.result", {"ability": InnerAbilities.display_name(StringName(result["ability"])),
		"rating": result["rating"], "difficulty": result["difficulty"], "roll": result["roll"],
		"total": result["total"], "outcome": outcome})


func _apply_effects(effects: Array) -> void:
	for effect: Dictionary in effects:
		_apply_effect(effect)


func _apply_effect(effect: Dictionary) -> void:
	var type_name := String(effect.get("type", ""))
	match type_name:
		"set_flag":
			var flag := StringName(String(effect.get("flag", "")))
			if _conversation.subjective:
				_reject(
					"Subjective conversation '%s' tried to set story flag '%s'. Ignored."
					% [_conversation.conversation_id, flag]
				)
				return
			_set_flag(flag, effect.get("value", true))
		"set_objective":
			if _conversation.subjective:
				_reject(
					"Subjective conversation '%s' tried to change the objective. Ignored."
					% _conversation.conversation_id
				)
				return
			_set_flag(StoryFlags.OBJECTIVE_KEY, String(effect.get("key", "")))
		"record":
			_record_narrative(effect)
		_:
			_reject("Unknown dialogue effect '%s'. Ignored." % type_name)


func _record_narrative(effect: Dictionary) -> void:
	var source_name := String(effect.get("source", ""))
	var source_value := NarrativeEntry.source_from_id(source_name)
	if source_value < 0:
		_reject("Record effect has unknown source '%s'. Ignored." % source_name)
		return
	if _conversation.subjective and source_value in [
		NarrativeEntry.Source.OBSERVED, NarrativeEntry.Source.REPORTED
	]:
		_reject(
			"Subjective conversation '%s' tried to record '%s' knowledge. Ignored."
			% [_conversation.conversation_id, source_name]
		)
		return
	var entry_id := StringName(String(effect.get("entry_id", "")))
	if _narrative_state.record(
		entry_id,
		source_value,
		StringName(String(effect.get("speaker", ""))),
		String(effect.get("text", ""))
	):
		narrative_entry_recorded.emit(_narrative_state.get_entry(entry_id))


func _reject(reason: String) -> void:
	push_warning("DialogueRuntime: %s" % reason)
	effect_rejected.emit(reason)


func _finish() -> void:
	var finished_id := _conversation.conversation_id if _conversation else &""
	_active = false
	_awaiting_choice = false
	_node = null
	_conversation = null
	_graph = null
	_displayed_check = {}
	conversation_finished.emit(finished_id)


func _get_flag(flag: StringName, default_value: Variant) -> Variant:
	if _game_state == null:
		return default_value
	return _game_state.get_flag(flag, default_value)


func _set_flag(flag: StringName, value: Variant) -> void:
	if _game_state == null:
		push_error("DialogueRuntime: cannot set flag '%s' without GameState." % flag)
		return
	_game_state.set_flag(flag, value)
