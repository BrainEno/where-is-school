class_name DialogueGraph
extends RefCounted
## Parsed, validated dialogue content for one language of one chapter.
##
## Content lives in data/dialogue/<locale>/<chapter>.json. Language files share
## their structure exactly (same conversations, same node ids, same order, same
## effects) and differ only in text; DialogueParity proves that, so a translator
## can never silently drop a line or a branch.
##
## Parsing is strict: every structural problem becomes an entry in `errors` naming
## the file, conversation and node, so a broken conversation fails loudly in CI
## instead of silently ending mid-scene.
##
## Runtime contracts:
## - a node without `next` falls through to the next node in file order;
## - `"next": null` ends the conversation at that node;
## - a node with `choices` never falls through, each choice names its target;
## - `once` choices disappear after they were taken (tracked in GameState);
## - a node whose `conditions` are not met is skipped, as if it were a `next` step.

const FORMAT_VERSION := 2
const EFFECT_TYPES: Array[String] = ["set_flag", "set_objective", "record"]
## Sources that describe what actually happened. A subjective conversation may
## never record these, and never write flags or the objective.
const FACTUAL_SOURCES: Array[String] = ["observed", "reported"]


class DialogueChoice extends RefCounted:
	var choice_id: StringName = &""
	var text: String = ""
	var next_id: StringName = &""
	## flag -> expected value
	var requires: Dictionary = {}
	var all_flags: Array[StringName] = []
	var not_flags: Array[StringName] = []
	var effects: Array = []
	var once: bool = false


class DialogueNode extends RefCounted:
	var node_id: StringName = &""
	var speaker_id: StringName = &""
	var text: String = ""
	## -1 means "inherit the conversation default".
	var source: int = -1
	## Empty means fall through to the next node in file order.
	var next_id: StringName = &""
	var ends_here: bool = false
	var effects: Array = []
	var choices: Array = []
	var tags: PackedStringArray = PackedStringArray()
	var requires: Dictionary = {}
	var all_flags: Array[StringName] = []
	var not_flags: Array[StringName] = []
	## A die roll this node performs before it continues. Empty when the node is an
	## ordinary line. See `_parse_check` for the shape and the runtime for the
	## resolution order.
	var check: Dictionary = {}
	## The two (or more) nodes a check can continue to, in the order
	## success, failure. Used by validation and by the parity checker.
	var check_targets: Array[StringName] = []


class Conversation extends RefCounted:
	var conversation_id: StringName = &""
	var default_source: int = NarrativeEntry.Source.OBSERVED
	## A subjective conversation is a fantasy or expectation: it can never write
	## gameplay flags and can never record observed or reported knowledge.
	var subjective: bool = false
	var start_id: StringName = &""
	var nodes: Dictionary = {}
	var order: Array[StringName] = []


var source_path: String = ""
var locale: String = ""
var chapter: String = ""
var errors: Array[String] = []
var conversations: Dictionary = {}
var speaker_ids: Dictionary = {}


static func load_from_file(path: String) -> DialogueGraph:
	var graph := DialogueGraph.new()
	graph.source_path = path
	graph._parse_file(path)
	return graph


func is_valid() -> bool:
	return errors.is_empty()


func get_conversation(conversation_id: StringName) -> Conversation:
	return conversations.get(conversation_id, null)


func has_conversation(conversation_id: StringName) -> bool:
	return conversations.has(conversation_id)


func get_conversation_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in conversations.keys():
		ids.append(key)
	return ids


# --- Parsing ----------------------------------------------------------------


func _parse_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		errors.append("Dialogue file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append(
			"Dialogue file could not be opened: %s (error %d)" % [path, FileAccess.get_open_error()]
		)
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append(
			"%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		return

	var root: Variant = json.data
	if not (root is Dictionary):
		errors.append("%s: root value must be an object." % path)
		return
	var data: Dictionary = root

	var version := int(data.get("format_version", 0))
	if version != FORMAT_VERSION:
		errors.append(
			"%s: format_version %d is not supported (expected %d)."
			% [path, version, FORMAT_VERSION]
		)
		return

	locale = String(data.get("locale", "")).strip_edges()
	if locale.is_empty():
		errors.append("%s: 'locale' is required (for example \"en\" or \"zh-CN\")." % path)
	chapter = String(data.get("chapter", "")).strip_edges()
	if chapter.is_empty():
		errors.append("%s: 'chapter' is required (for example \"prologue\")." % path)
	if not L10n.is_supported(locale):
		errors.append(
			"%s: locale '%s' is not one of %s." % [path, locale, ", ".join(L10n.LOCALES)]
		)

	var raw_conversations: Variant = data.get("conversations")
	if not (raw_conversations is Dictionary):
		errors.append("%s: 'conversations' must be an object." % path)
		return

	for conversation_key: Variant in raw_conversations:
		var conversation_id := StringName(String(conversation_key))
		var raw_conversation: Variant = raw_conversations[conversation_key]
		if not (raw_conversation is Dictionary):
			errors.append("%s: conversation '%s' must be an object." % [path, conversation_id])
			continue
		if conversations.has(conversation_id):
			errors.append("%s: duplicate conversation id '%s'." % [path, conversation_id])
			continue
		var conversation := _parse_conversation(conversation_id, raw_conversation, path)
		conversations[conversation_id] = conversation
		_validate_conversation(conversation, path)


func _parse_conversation(
	conversation_id: StringName, data: Dictionary, path: String
) -> Conversation:
	var conversation := Conversation.new()
	conversation.conversation_id = conversation_id
	var label := "%s: conversation '%s'" % [path, conversation_id]

	var default_source := String(data.get("default_source", "observed"))
	var source_value := NarrativeEntry.source_from_id(default_source)
	if source_value < 0:
		errors.append("%s has unknown default_source '%s'." % [label, default_source])
		source_value = NarrativeEntry.Source.OBSERVED
	conversation.default_source = source_value
	conversation.subjective = bool(data.get("subjective", false))
	if conversation.subjective and source_value in [
		NarrativeEntry.Source.OBSERVED, NarrativeEntry.Source.REPORTED
	]:
		errors.append(
			"%s is subjective, so default_source '%s' cannot be used: imagination may only "
			% [label, default_source]
			+ "carry imagined or recalled lines."
		)

	var raw_nodes: Variant = data.get("nodes")
	if not (raw_nodes is Array) or (raw_nodes as Array).is_empty():
		errors.append("%s needs a non-empty 'nodes' array." % label)
		return conversation

	for index in (raw_nodes as Array).size():
		var raw_node: Variant = (raw_nodes as Array)[index]
		if not (raw_node is Dictionary):
			errors.append("%s node #%d must be an object." % [label, index])
			continue
		var node := _parse_node(conversation, raw_node as Dictionary, index, path)
		if node == null:
			continue
		if conversation.nodes.has(node.node_id):
			errors.append("%s has duplicate node id '%s'." % [label, node.node_id])
			continue
		conversation.nodes[node.node_id] = node
		conversation.order.append(node.node_id)

	var start_raw: Variant = data.get("start", "")
	conversation.start_id = StringName(String(start_raw))
	return conversation


func _parse_node(
	conversation: Conversation, data: Dictionary, index: int, path: String
) -> DialogueNode:
	var conversation_id := conversation.conversation_id
	var node := DialogueNode.new()
	node.node_id = StringName(String(data.get("id", "")))
	if String(node.node_id).is_empty():
		errors.append("%s: conversation '%s' node #%d is missing 'id'." % [path, conversation_id, index])
		return null

	var context := "%s: %s/%s" % [path, conversation_id, node.node_id]
	node.speaker_id = StringName(String(data.get("speaker", "")))
	if String(node.speaker_id).is_empty():
		errors.append("%s: node needs a 'speaker'." % context)
	else:
		speaker_ids[node.speaker_id] = true

	node.text = String(data.get("text", "")).strip_edges()

	if data.has("source"):
		var source_name := String(data["source"])
		var source_value := NarrativeEntry.source_from_id(source_name)
		if source_value < 0:
			errors.append("%s: unknown source '%s'." % [context, source_name])
			source_value = int(conversation.default_source)
		elif conversation.subjective and source_value in [
			NarrativeEntry.Source.OBSERVED, NarrativeEntry.Source.REPORTED
		]:
			errors.append(
				"%s: a subjective conversation cannot carry a '%s' line; use \"imagined\" or "
				% [context, source_name]
				+ "\"recalled\"."
			)
		node.source = source_value

	if data.has("next"):
		var next_raw: Variant = data["next"]
		if next_raw == null:
			node.ends_here = true
		else:
			node.next_id = StringName(String(next_raw))
			if String(node.next_id).is_empty():
				errors.append("%s: 'next' must be a node id or null." % context)

	node.tags = PackedStringArray()
	if data.has("tags"):
		var tags_raw: Variant = data["tags"]
		if tags_raw is Array:
			for tag: Variant in tags_raw:
				node.tags.append(String(tag))

	_parse_conditions(data.get("conditions", null), context, node.requires, node.all_flags, node.not_flags)
	node.check = _parse_check(data.get("check", null), context, node.check_targets)
	node.effects = _parse_effects(data.get("effects", []), context + " effects")

	var raw_choices: Variant = data.get("choices", [])
	if raw_choices is Array:
		var seen_choice_ids: Dictionary = {}
		for choice_index in (raw_choices as Array).size():
			var raw_choice: Variant = (raw_choices as Array)[choice_index]
			if not (raw_choice is Dictionary):
				errors.append("%s: choice #%d must be an object." % [context, choice_index])
				continue
			var choice := _parse_choice(raw_choice as Dictionary, choice_index, context)
			if choice == null:
				continue
			if seen_choice_ids.has(choice.choice_id):
				errors.append(
					"%s: duplicate choice id '%s'." % [context, choice.choice_id]
				)
				continue
			seen_choice_ids[choice.choice_id] = true
			node.choices.append(choice)
	elif raw_choices != null:
		errors.append("%s: 'choices' must be an array." % context)

	if node.text.is_empty() and node.choices.is_empty():
		errors.append("%s: node has no text and no choices, so nothing can be shown." % context)

	return node


func _parse_choice(data: Dictionary, index: int, context: String) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.choice_id = StringName(String(data.get("id", "")))
	if String(choice.choice_id).is_empty():
		# Ids used to be optional. They are required now: `once` bookkeeping and
		# translation parity both key off them.
		errors.append(
			"%s: choice #%d needs an 'id' (stable, used for 'once' and for translations)."
			% [context, index]
		)
		choice.choice_id = StringName("choice_%d" % index)
	choice.text = String(data.get("text", "")).strip_edges()
	if choice.text.is_empty():
		errors.append("%s: choice '%s' has no text." % [context, choice.choice_id])
	choice.next_id = StringName(String(data.get("next", "")))
	if String(choice.next_id).is_empty():
		errors.append("%s: choice '%s' must name a 'next' node." % [context, choice.choice_id])
	choice.once = bool(data.get("once", false))
	if data.has("requires"):
		var requires_raw: Variant = data["requires"]
		if requires_raw is Dictionary:
			for key: Variant in (requires_raw as Dictionary).keys():
				if String(key).is_empty():
					errors.append("%s: choice '%s' has an empty requires flag." % [context, choice.choice_id])
				choice.requires[StringName(String(key))] = (requires_raw as Dictionary)[key]
		else:
			errors.append("%s: choice '%s' requires must be an object." % [context, choice.choice_id])
	_parse_conditions(
		data.get("conditions", null),
		"%s choice '%s'" % [context, choice.choice_id],
		choice.requires,
		choice.all_flags,
		choice.not_flags
	)
	choice.effects = _parse_effects(
		data.get("effects", []), "%s choice '%s'" % [context, choice.choice_id]
	)
	return choice


## A check node rolls once and continues to one of two nodes:
##
##   "check": {"ability": "orientation", "difficulty": 9, "kind": "visible",
##             "success": "looked_closely", "failure": "looked_badly",
##             "modifiers": [{"flag": "saw_set_square", "value": 1}],
##             "repeatable": false}
##
## - `ability` is the inner voice that carries the attempt; its value is added to
##   the die, so a check without an ability that exists is a content error.
## - `kind` is `visible` (the player sees the die and the result, because they
##   asked for the attempt) or `hidden` (a voice speaks up on its own and only the
##   consequence is shown).
## - `repeatable` is false by default: the recorded outcome is replayed instead of
##   rolled again, so the same attempt cannot be farmed for a better die.
func _parse_check(raw: Variant, context: String, targets: Array[StringName]) -> Dictionary:
	if raw == null:
		return {}
	if not (raw is Dictionary):
		errors.append("%s: 'check' must be an object." % context)
		return {}
	var data: Dictionary = raw
	var check := {}
	check["ability"] = StringName(String(data.get("ability", "")))
	if String(check["ability"]).is_empty():
		errors.append("%s: check needs an 'ability' (an inner-voice id)." % context)
	var difficulty := int(data.get("difficulty", 0))
	if not CheckResolver.is_valid_difficulty(difficulty):
		errors.append(
			"%s: check difficulty %d is outside %d..%d."
			% [context, difficulty, CheckResolver.MIN_DIFFICULTY, CheckResolver.MAX_DIFFICULTY]
		)
	check["difficulty"] = difficulty
	var kind := String(data.get("kind", "visible"))
	if not ["visible", "hidden"].has(kind):
		errors.append("%s: check kind '%s' must be 'visible' or 'hidden'." % [context, kind])
	check["kind"] = kind
	check["success"] = StringName(String(data.get("success", "")))
	check["failure"] = StringName(String(data.get("failure", "")))
	for branch: String in ["success", "failure"]:
		var target: StringName = check[branch]
		if String(target).is_empty():
			errors.append("%s: check needs a '%s' node." % [context, branch])
		else:
			targets.append(target)
	check["repeatable"] = data.get("repeatable", false) == true
	var modifiers: Array = []
	var raw_modifiers: Variant = data.get("modifiers", [])
	if not (raw_modifiers is Array):
		errors.append("%s: check 'modifiers' must be an array." % context)
	else:
		for index in (raw_modifiers as Array).size():
			var entry: Variant = (raw_modifiers as Array)[index]
			if not (entry is Dictionary):
				errors.append("%s: check modifier #%d must be an object." % [context, index])
				continue
			var modifier: Dictionary = entry
			var flag := String(modifier.get("flag", ""))
			if flag.is_empty():
				errors.append("%s: check modifier #%d needs a 'flag'." % [context, index])
				continue
			modifiers.append({"flag": StringName(flag), "value": int(modifier.get("value", 0))})
	check["modifiers"] = modifiers
	for key: Variant in data.keys():
		if String(key) not in [
			"ability", "difficulty", "kind", "success", "failure", "modifiers", "repeatable"
		]:
			errors.append(
				"%s: unknown check field '%s' (use ability, difficulty, kind, success, " % [context, String(key)]
				+ "failure, modifiers or repeatable)."
			)
	return check


## Shared condition syntax for nodes and choices:
##   "conditions": {"all_flags": ["a"], "not_flags": ["b"], "requires": {"c": true}}
func _parse_conditions(
	raw: Variant, context: String, requires: Dictionary,
	all_flags: Array[StringName], not_flags: Array[StringName]
) -> void:
	if raw == null:
		return
	if not (raw is Dictionary):
		errors.append("%s: 'conditions' must be an object." % context)
		return
	var data: Dictionary = raw
	for key: Variant in data.keys():
		if String(key) not in ["all_flags", "not_flags", "requires"]:
			errors.append(
				"%s: unknown condition '%s' (use all_flags, not_flags or requires)." % [context, String(key)]
			)
	for entry: Variant in data.get("all_flags", []):
		all_flags.append(StringName(String(entry)))
	for entry: Variant in data.get("not_flags", []):
		not_flags.append(StringName(String(entry)))
	var raw_requires: Variant = data.get("requires", {})
	if raw_requires is Dictionary:
		for flag: Variant in (raw_requires as Dictionary).keys():
			requires[StringName(String(flag))] = (raw_requires as Dictionary)[flag]
	elif raw_requires != null:
		errors.append("%s: conditions.requires must be an object." % context)


func _parse_effects(raw: Variant, context: String) -> Array:
	var effects: Array = []
	if raw == null:
		return effects
	if not (raw is Array):
		errors.append("%s: effects must be an array." % context)
		return effects
	for effect_index in (raw as Array).size():
		var raw_effect: Variant = (raw as Array)[effect_index]
		var effect_context := "%s effect #%d" % [context, effect_index]
		if not (raw_effect is Dictionary):
			errors.append("%s: must be an object." % effect_context)
			continue
		var effect: Dictionary = raw_effect
		var type_name := String(effect.get("type", ""))
		if not EFFECT_TYPES.has(type_name):
			errors.append("%s: unknown type '%s'." % [effect_context, type_name])
			continue
		match type_name:
			"set_flag":
				if String(effect.get("flag", "")).is_empty():
					errors.append("%s: set_flag needs a 'flag'." % effect_context)
					continue
				if not effect.has("value"):
					errors.append("%s: set_flag needs a 'value'." % effect_context)
					continue
			"set_objective":
				var key := String(effect.get("key", "")).strip_edges()
				if key.is_empty():
					errors.append(
						"%s: set_objective needs a 'key' (a locale key such as "
						% effect_context
						+ "\"objective.check_bag\"), not literal text."
					)
					continue
				if effect.has("text"):
					errors.append(
						"%s: set_objective takes a 'key'; literal 'text' is not translated."
						% effect_context
					)
					continue
				if not key.contains("."):
					errors.append(
						"%s: objective key '%s' does not look like a locale key." % [effect_context, key]
					)
					continue
			"record":
				if String(effect.get("entry_id", "")).is_empty():
					errors.append("%s: record needs an 'entry_id'." % effect_context)
					continue
				var source_name := String(effect.get("source", ""))
				if NarrativeEntry.source_from_id(source_name) < 0:
					errors.append("%s: record has unknown source '%s'." % [effect_context, source_name])
					continue
				if String(effect.get("text", "")).strip_edges().is_empty():
					errors.append("%s: record needs 'text'." % effect_context)
					continue
				if String(effect.get("speaker", "")).is_empty():
					errors.append("%s: record needs a 'speaker'." % effect_context)
					continue
				speaker_ids[StringName(String(effect["speaker"]))] = true
		effects.append(effect)
	return effects


func _validate_conversation(conversation: Conversation, path: String) -> void:
	var label := "%s: conversation '%s'" % [path, conversation.conversation_id]

	if conversation.nodes.is_empty():
		errors.append("%s has no valid nodes." % label)
		return

	if String(conversation.start_id).is_empty():
		conversation.start_id = conversation.order[0]
	elif not conversation.nodes.has(conversation.start_id):
		errors.append("%s start node '%s' does not exist." % [label, conversation.start_id])

	for node_id in conversation.order:
		var node: DialogueNode = conversation.nodes[node_id]
		var node_label := "%s/%s" % [label, node_id]
		if not String(node.next_id).is_empty() and not conversation.nodes.has(node.next_id):
			errors.append("%s: next node '%s' does not exist." % [node_label, node.next_id])
		for choice: DialogueChoice in node.choices:
			if not conversation.nodes.has(choice.next_id):
				errors.append(
					"%s: choice '%s' points at missing node '%s'."
					% [node_label, choice.choice_id, choice.next_id]
				)
		if not node.choices.is_empty() and not String(node.next_id).is_empty():
			errors.append("%s: a node cannot have both choices and 'next'." % node_label)
		if not node.check.is_empty():
			if not node.choices.is_empty():
				errors.append("%s: a check node cannot also offer choices." % node_label)
			if not String(node.next_id).is_empty() or node.ends_here:
				errors.append(
					"%s: a check node continues to success/failure, so it cannot have 'next'."
					% node_label
				)
			for target: StringName in node.check_targets:
				if not conversation.nodes.has(target):
					errors.append(
						"%s: check continues to missing node '%s'." % [node_label, target]
					)
		if node.ends_here and not node.choices.is_empty():
			errors.append("%s: a node with choices must not also end the conversation." % node_label)
		if conversation.subjective:
			_validate_subjective_node(node, node_label)

	_check_last_node_terminates(conversation, label)
	_validate_no_linear_cycle(conversation, label)
	_report_unreachable(conversation, label)


## The last node in file order has no fall-through target, so it must end the
## conversation explicitly instead of dying silently at runtime.
func _check_last_node_terminates(conversation: Conversation, label: String) -> void:
	var last_id: StringName = conversation.order[conversation.order.size() - 1]
	var last: DialogueNode = conversation.nodes[last_id]
	if last.choices.is_empty() and not last.ends_here and String(last.next_id).is_empty():
		errors.append(
			"%s/%s: the last node of a file cannot fall through; add \"next\": null or choices."
			% [label, last_id]
		)


## Statically refuse the effects a subjective conversation is not allowed to
## have. The runtime also refuses them at play time; this makes the mistake
## visible while editing instead of as a warning in a log.
func _validate_subjective_node(node: DialogueNode, node_label: String) -> void:
	for effect: Dictionary in node.effects:
		var type_name := String(effect.get("type", ""))
		if type_name == "set_flag":
			errors.append(
				"%s: subjective conversations cannot set flag '%s'." % [node_label, String(effect.get("flag", ""))]
			)
		elif type_name == "set_objective":
			errors.append("%s: subjective conversations cannot change the objective." % node_label)
		elif type_name == "record" and String(effect.get("source", "")) in FACTUAL_SOURCES:
			errors.append(
				"%s: subjective conversations cannot record '%s' knowledge (entry '%s')."
				% [node_label, String(effect.get("source", "")), String(effect.get("entry_id", ""))]
			)
	# A check records its result in story state (so it cannot be rerolled) and a
	# `once` choice records that it was taken. Both are objective bookkeeping, so
	# neither belongs in a conversation the protagonist is only imagining.
	if not node.check.is_empty():
		errors.append(
			"%s: subjective conversations cannot carry a check; its result would be written to story state."
			% node_label
		)
	for choice: DialogueChoice in node.choices:
		if choice.once:
			errors.append(
				"%s: choice '%s' is marked 'once' inside a subjective conversation; the 'once' bookkeeping is a story flag."
				% [node_label, choice.choice_id]
			)
		for effect: Dictionary in choice.effects:
			var type_name := String(effect.get("type", ""))
			if type_name == "set_flag" or type_name == "set_objective":
				errors.append(
					"%s: choice '%s' belongs to a subjective conversation and cannot change story state."
					% [node_label, choice.choice_id]
				)
			elif type_name == "record" and String(effect.get("source", "")) in FACTUAL_SOURCES:
				errors.append(
					"%s: choice '%s' cannot record '%s' knowledge inside a subjective conversation."
					% [node_label, choice.choice_id, String(effect.get("source", ""))]
				)


## `next` chains must terminate. Loops through choices are allowed (a hub of
## follow-up questions is legitimate); silent loops through `next` are not.
func _validate_no_linear_cycle(conversation: Conversation, label: String) -> void:
	for start_id: StringName in conversation.order:
		var seen: Dictionary = {}
		var current: StringName = start_id
		var steps := 0
		var limit := conversation.order.size() + 1
		while conversation.nodes.has(current) and steps <= limit:
			if seen.has(current):
				var message := "%s: 'next' chain loops through '%s'." % [label, current]
				if not errors.has(message):
					errors.append(message)
				break
			seen[current] = true
			var node: DialogueNode = conversation.nodes[current]
			if node.ends_here or not node.choices.is_empty() or not node.check.is_empty():
				break
			if not String(node.next_id).is_empty():
				current = node.next_id
			else:
				var order_index := conversation.order.find(current)
				if order_index < 0 or order_index + 1 >= conversation.order.size():
					break
				current = conversation.order[order_index + 1]
			steps += 1


## Anything the player can never see is dead content: usually a typo in a `next`.
##
## The walk has to follow the same edges the runtime follows, or it proves nothing
## about the game:
##
## - a node with **choices** continues only through its choices. `DialogueRuntime`
##   blocks `advance()` while an option is on screen, and the content contract says a
##   node with choices never falls through, so the next node in file order is not
##   reachable from it;
## - a node with a **check** continues only to the node it rolled: the runtime answers
##   `_resolve_next_id()` with the branch, never with `next` or the sequence;
## - an ordinary node keeps its `next`, or the next node in file order when it has none.
##
## Adding the sequence edge for all three, as this function used to, made a line parked
## after a choice hub look reachable when no playthrough could ever show it: the
## validator accepted dead content, and the translation of it sank with it (issue #20).
func _report_unreachable(conversation: Conversation, label: String) -> void:
	var reached: Dictionary = {}
	var queue: Array[StringName] = []
	if conversation.nodes.has(conversation.start_id):
		queue.append(conversation.start_id)
	while not queue.is_empty():
		var current: StringName = queue.pop_back()
		if reached.has(current) or not conversation.nodes.has(current):
			continue
		reached[current] = true
		var node: DialogueNode = conversation.nodes[current]
		for choice: DialogueChoice in node.choices:
			queue.append(choice.next_id)
		for target: StringName in node.check_targets:
			queue.append(target)
		# Explicit branches only: a node the player chooses from, or rolls at, has no
		# fall-through edge, because the runtime never walks one from it.
		if not node.choices.is_empty() or not node.check.is_empty():
			continue
		if node.ends_here:
			continue
		if not String(node.next_id).is_empty():
			queue.append(node.next_id)
		else:
			var order_index := conversation.order.find(current)
			if order_index >= 0 and order_index + 1 < conversation.order.size():
				queue.append(conversation.order[order_index + 1])
	for node_id: StringName in conversation.order:
		if not reached.has(node_id):
			errors.append(
				"%s/%s: unreachable node (nothing leads here from start '%s')."
				% [label, node_id, conversation.start_id]
			)


func describe_errors() -> String:
	if errors.is_empty():
		return "Dialogue content %s parsed without errors." % source_path
	return "Dialogue content %s has %d error(s):\n%s" % [
		source_path, errors.size(), "\n".join(errors)
	]
