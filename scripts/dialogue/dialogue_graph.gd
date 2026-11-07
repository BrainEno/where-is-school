class_name DialogueGraph
extends RefCounted
## Parsed, validated dialogue content.
##
## Content lives in data/dialogue/*.json and is loaded here rather than in a
## gameplay script. Parsing is strict: every structural problem becomes an entry
## in `errors` naming the file and node, so a broken conversation fails loudly
## instead of silently ending.
##
## Runtime contracts:
## - a node without `next` falls through to the next node in file order;
## - `"next": null` ends the conversation at that node;
## - a node with `choices` never falls through, each choice names its target;
## - `once` choices disappear after they were taken (tracked in GameState).

const FORMAT_VERSION := 1
const EFFECT_TYPES: Array[String] = ["set_flag", "set_objective", "record"]


class DialogueChoice extends RefCounted:
	var choice_id: StringName = &""
	var text: String = ""
	var next_id: StringName = &""
	var requires: Dictionary = {}
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
			errors.append("Duplicate conversation id '%s' in %s" % [conversation_id, path])
			continue
		var conversation := _parse_conversation(conversation_id, raw_conversation, path)
		conversations[conversation_id] = conversation
		_validate_conversation(conversation, path)


func _parse_conversation(
	conversation_id: StringName, data: Dictionary, path: String
) -> Conversation:
	var conversation := Conversation.new()
	conversation.conversation_id = conversation_id

	var default_source := String(data.get("default_source", "observed"))
	var source_value := NarrativeEntry.source_from_id(default_source)
	if source_value < 0:
		errors.append(
			"%s: conversation '%s' has unknown default_source '%s'."
			% [path, conversation_id, default_source]
		)
		source_value = NarrativeEntry.Source.OBSERVED
	conversation.default_source = source_value
	conversation.subjective = bool(data.get("subjective", false))

	var raw_nodes: Variant = data.get("nodes")
	if not (raw_nodes is Array) or (raw_nodes as Array).is_empty():
		errors.append("%s: conversation '%s' needs a non-empty 'nodes' array." % [path, conversation_id])
		return conversation

	for index in (raw_nodes as Array).size():
		var raw_node: Variant = (raw_nodes as Array)[index]
		if not (raw_node is Dictionary):
			errors.append(
				"%s: conversation '%s' node #%d must be an object." % [path, conversation_id, index]
			)
			continue
		var node := _parse_node(conversation, raw_node as Dictionary, index, path)
		if node == null:
			continue
		if conversation.nodes.has(node.node_id):
			errors.append(
				"%s: conversation '%s' has duplicate node id '%s'."
				% [path, conversation_id, node.node_id]
			)
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
		errors.append(
			"%s: conversation '%s' node #%d is missing 'id'." % [path, conversation_id, index]
		)
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

	node.effects = _parse_effects(data.get("effects", []), context + " effects")

	var raw_choices: Variant = data.get("choices", [])
	if raw_choices is Array:
		for choice_index in (raw_choices as Array).size():
			var raw_choice: Variant = (raw_choices as Array)[choice_index]
			if not (raw_choice is Dictionary):
				errors.append("%s: choice #%d must be an object." % [context, choice_index])
				continue
			var choice := _parse_choice(raw_choice as Dictionary, choice_index, context)
			if choice != null:
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
		# Ids are optional for authoring convenience, but must be stable for the
		# `once` bookkeeping, so derive one from the position when missing.
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
	choice.effects = _parse_effects(
		data.get("effects", []), "%s choice '%s'" % [context, choice.choice_id]
	)
	return choice


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
				if String(effect.get("text", "")).strip_edges().is_empty():
					errors.append("%s: set_objective needs 'text'." % effect_context)
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

	_validate_no_linear_cycle(conversation, label)


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
			if node.ends_here or not node.choices.is_empty():
				break
			if not String(node.next_id).is_empty():
				current = node.next_id
			else:
				var order_index := conversation.order.find(current)
				if order_index < 0 or order_index + 1 >= conversation.order.size():
					break
				current = conversation.order[order_index + 1]
			steps += 1


func describe_errors() -> String:
	if errors.is_empty():
		return "Dialogue content %s parsed without errors." % source_path
	return "Dialogue content %s has %d error(s):\n%s" % [
		source_path, errors.size(), "\n".join(errors)
	]
