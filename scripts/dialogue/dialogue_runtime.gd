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
## Emitted when a check node is entered, after its line is shown. `visible` checks
## are presented with the numbers; `hidden` ones only change which line comes next.
signal check_resolved(result: Dictionary)

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
var _abilities: InnerAbilities = null
var _resolver: CheckResolver = null
## The node a check continues to, worked out when the check node was entered.
var _pending_branch: StringName = &""
var _last_check: Dictionary = {}


func _init(
	game_state: Node = null,
	narrative_state: Node = null,
	characters: CharacterDirectory = null,
	abilities: InnerAbilities = null,
	resolver: CheckResolver = null
) -> void:
	_game_state = game_state if game_state != null else _find_autoload("GameState")
	_narrative_state = narrative_state if narrative_state != null else _find_autoload("NarrativeState")
	_characters = characters if characters != null else CharacterDirectory.load_all()
	if _characters != null and not _characters.errors.is_empty():
		for message in _characters.errors:
			push_error("DialogueRuntime: %s" % message)
	_abilities = abilities
	_resolver = resolver if resolver != null else CheckResolver.new()


static func _find_autoload(node_name: String) -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root: Window = (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(NodePath(node_name))


func is_active() -> bool:
	return _active


## The most recent check this runtime resolved. Tests use it to assert the die,
## the branch and that a second visit replayed the recorded outcome.
func get_last_check() -> Dictionary:
	return _last_check


## Late wiring, so a controller can hand in the registries after construction.
func set_abilities(abilities: InnerAbilities) -> void:
	_abilities = abilities


func set_resolver(resolver: CheckResolver) -> void:
	_resolver = resolver if resolver != null else CheckResolver.new()


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func get_active_conversation_id() -> StringName:
	if _conversation == null:
		return &""
	return _conversation.conversation_id


## Ids of the choices the player can pick right now, in display order. Used by the
## tests to prove that an attempt already made stops being offered.
func get_available_choice_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _node == null or not _awaiting_choice:
		return ids
	for choice: DialogueGraph.DialogueChoice in _available_choices(_node):
		ids.append(choice.choice_id)
	return ids


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
	conversation_started.emit(conversation_id)
	_enter_node(conversation.start_id)
	return true


## Player asked to continue past the current line. Returns false when a choice
## is pending (the player has to pick) or nothing is running.
func advance() -> bool:
	if not _active or _awaiting_choice or _node == null:
		return false
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
	if choice.once:
		if _is_subjective():
			# Static validation already refuses this. If content slips through, the
			# line still plays but the bookkeeping never reaches GameState.
			_reject("a 'once' choice in a subjective conversation cannot write a story flag")
		else:
			_set_flag(StoryFlags.choice_flag(_conversation.conversation_id, choice.choice_id), true)
	_apply_effects(choice.effects)
	_awaiting_choice = false
	_enter_node(choice.next_id)
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
		presented.append({"index": index, "text": choice.text})
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
	_pending_branch = &""
	_apply_effects(node.effects)
	if not node.check.is_empty():
		_resolve_check(node)

	var available := _available_choices(node)
	_awaiting_choice = not available.is_empty()

	if not node.text.is_empty():
		line_changed.emit(get_current_line())
	if _awaiting_choice:
		choices_changed.emit(get_current_choices())


func _resolve_next_id(node: DialogueGraph.DialogueNode) -> StringName:
	if not node.check.is_empty():
		return _pending_branch
	if node.ends_here:
		return &""
	if not String(node.next_id).is_empty():
		return node.next_id
	var order_index := _conversation.order.find(node.node_id)
	if order_index >= 0 and order_index + 1 < _conversation.order.size():
		return _conversation.order[order_index + 1]
	return &""


## Rolls (or replays) the check a node carries and remembers which branch it
## continues to. The line is already on screen when this runs, so a visible check
## can be presented next to the attempt instead of before it.
func _resolve_check(node: DialogueGraph.DialogueNode) -> void:
	var conversation_id := _conversation.conversation_id
	if _is_subjective():
		# Defence in depth: validation refuses the content, and the runtime refuses
		# to roll or record anything if it arrives anyway. The failure branch is
		# taken so the scene still moves on instead of stalling.
		_reject("a check in a subjective conversation was not rolled or recorded")
		_last_check = {}
		_pending_branch = node.check.get("failure", &"")
		return
	var key := "%s/%s" % [conversation_id, node.node_id]
	var record_flag := StoryFlags.check_record_flag(conversation_id, node.node_id)
	var repeatable: bool = node.check.get("repeatable", false) == true
	var recorded: Variant = _get_flag(record_flag, null)
	var result: Dictionary = {}
	if not repeatable and recorded is Dictionary:
		# The die already fell here. Replaying the record is what makes walking away
		# and coming back useless as a reroll strategy.
		result = CheckResolver.reuse(recorded as Dictionary)
	else:
		var ability_id: StringName = node.check.get("ability", &"")
		var ability_value := 0
		if _abilities != null:
			ability_value = _abilities.get_value(ability_id)
		var modifier := CheckResolver.modifier_for(
			node.check.get("modifiers", []), Callable(self, "_get_flag")
		)
		result = _resolver.roll(
			ability_id, ability_value, int(node.check.get("difficulty", 0)), modifier, key
		)
		if not repeatable:
			_set_flag(record_flag, result)
	result["kind"] = String(node.check.get("kind", "visible"))
	_last_check = result
	_pending_branch = (
		node.check.get("success", &"")
		if bool(result.get("success", false))
		else node.check.get("failure", &"")
	)
	check_resolved.emit(result)


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
		if not _flag_is_set(flag):
			return false
	for flag in not_flags:
		if _flag_is_set(flag):
			return false
	return true


## Whether a story flag counts as set.
##
## This cannot be `bool(value)`: a check records its whole result in a flag, so a
## flag legitimately holds a Dictionary, and GDScript's bool constructor does not
## accept one. That was a real crash the first time a choice was gated on
## `not_flags: ["check:…"]`, i.e. the exact pattern used to stop an attempt being
## offered twice.
func _flag_is_set(flag: StringName) -> bool:
	var value: Variant = _get_flag(flag, null)
	if value == null:
		return false
	if value is bool:
		return value
	if value is int:
		return int(value) != 0
	if value is float:
		return not is_zero_approx(float(value))
	if value is String:
		return not (value as String).is_empty()
	if value is Array:
		return not (value as Array).is_empty()
	# A Dictionary (a check record) or any other stored value counts as set.
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
	return compose_line(_conversation, node, _characters, _abilities)


## Builds the presentation dictionary for one node of one conversation.
##
## Static and free of runtime state on purpose: the backlog rebuilds past lines from
## their content ids after a language switch, and it has to produce exactly what the
## live runtime produced, including the translated speaker name and the inner-voice
## override. Two implementations would drift apart at the first content edit.
static func compose_line(
	conversation: DialogueGraph.DialogueConversation,
	node: DialogueGraph.DialogueNode,
	characters: CharacterDirectory,
	abilities: InnerAbilities
) -> Dictionary:
	var source_value: int = conversation.default_source
	if node.source >= 0:
		source_value = node.source
	var speaker_id := node.speaker_id
	var speaker_name := String(speaker_id)
	var speaker_role := ""
	var accent_color := Color.WHITE
	if characters != null:
		speaker_name = characters.get_localized_name(speaker_id)
		speaker_role = characters.get_short_role(speaker_id)
		accent_color = characters.get_accent_color(speaker_id)
	elif L10n.has_key("name.%s" % String(speaker_id)):
		speaker_name = L10n.t("name.%s" % String(speaker_id))
	# Inner voices are not people: their name is the translated ability name, not
	# a fixed string in a character resource.
	if abilities != null:
		var voice_name := abilities.get_name_for_speaker(speaker_id)
		if not voice_name.is_empty():
			speaker_name = voice_name
	return {
		"conversation_id": conversation.conversation_id,
		"node_id": node.node_id,
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": speaker_role,
		"accent_color": accent_color,
		"title": "",
		"text": node.text,
		"source": source_value,
		"badge": NarrativeEntry.badge_key_for(source_value),
		"subjective": conversation.subjective,
		"tags": node.tags,
	}


## True while the running conversation is one the protagonist is only imagining.
## Every write path checks it: the graph validator refuses such content at load
## time, and these guards make sure a hand-edited file that slips through still
## cannot touch GameState.
func _is_subjective() -> bool:
	return _conversation != null and _conversation.subjective


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
	_pending_branch = &""
	_conversation = null
	_graph = null
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
