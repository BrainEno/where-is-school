class_name DialogueParity
extends RefCounted
## Compares the same chapter in two languages.
##
## Translation must never change the shape of a conversation: same conversations,
## same node ids in the same order (order matters, because a node without `next`
## falls through to the next one in the file), same choices, same jump targets,
## same effects. Only human-readable text may differ. Every difference is
## reported with the file, conversation and node id.

## Fields that are prose and must differ per language.
const TEXTUAL_NODE_FIELDS: Array[String] = ["text"]
const TEXTUAL_CHOICE_FIELDS: Array[String] = ["text"]


static func compare(reference: DialogueGraph, other: DialogueGraph) -> Array[String]:
	var problems: Array[String] = []
	if reference == null or other == null:
		problems.append("DialogueParity: a missing graph cannot be compared.")
		return problems
	var other_label := "%s (%s)" % [other.source_path, other.locale]

	if reference.chapter != other.chapter:
		problems.append(
			"%s: chapter '%s' does not match '%s' in %s."
			% [other_label, other.chapter, reference.chapter, reference.source_path]
		)

	for conversation_id: StringName in reference.get_conversation_ids():
		if not other.has_conversation(conversation_id):
			problems.append(
				"%s: conversation '%s' is missing (present in %s)."
				% [other_label, conversation_id, reference.source_path]
			)
	for conversation_id: StringName in other.get_conversation_ids():
		if not reference.has_conversation(conversation_id):
			problems.append(
				"%s: conversation '%s' does not exist in the other language."
				% [other_label, conversation_id]
			)

	for conversation_id: StringName in reference.get_conversation_ids():
		if not other.has_conversation(conversation_id):
			continue
		_compare_conversation(
			reference.get_conversation(conversation_id),
			other.get_conversation(conversation_id),
			other_label,
			problems
		)
	return problems


static func _compare_conversation(
	reference: DialogueGraph.Conversation,
	other: DialogueGraph.Conversation,
	other_label: String,
	problems: Array[String]
) -> void:
	var label := "%s: conversation '%s'" % [other_label, reference.conversation_id]
	if String(reference.start_id) != String(other.start_id):
		problems.append(
			"%s: start node is '%s' but should be '%s'." % [label, other.start_id, reference.start_id]
		)
	if reference.subjective != other.subjective:
		problems.append("%s: 'subjective' differs between languages." % label)
	if reference.default_source != other.default_source:
		problems.append("%s: default_source differs between languages." % label)

	if reference.order.size() != other.order.size():
		problems.append(
			"%s: has %d node(s) but the other language has %d."
			% [label, other.order.size(), reference.order.size()]
		)
	for index in min(reference.order.size(), other.order.size()):
		if reference.order[index] != other.order[index]:
			problems.append(
				"%s: node #%d is '%s' but the other language has '%s' (order matters: "
				% [label, index, other.order[index], reference.order[index]]
				+ "nodes without 'next' fall through in file order)."
			)

	for node_id: StringName in reference.order:
		var reference_node: DialogueGraph.DialogueNode = reference.nodes[node_id]
		var other_node: DialogueGraph.DialogueNode = other.nodes.get(node_id, null)
		var node_label := "%s/%s" % [label, node_id]
		if other_node == null:
			problems.append("%s: node is missing in the other language." % node_label)
			continue
		_compare_node(reference_node, other_node, node_label, problems)


static func _compare_node(
	reference: DialogueGraph.DialogueNode,
	other: DialogueGraph.DialogueNode,
	node_label: String,
	problems: Array[String]
) -> void:
	if other.text.strip_edges().is_empty():
		problems.append("%s: missing translation (empty text)." % node_label)
	elif String(reference.text).strip_edges().is_empty() and not other.text.is_empty():
		problems.append("%s: has text that the reference language does not have." % node_label)
	if String(reference.speaker_id) != String(other.speaker_id):
		problems.append(
			"%s: speaker is '%s' but should be '%s'." % [node_label, other.speaker_id, reference.speaker_id]
		)
	if reference.source != other.source:
		problems.append("%s: narrative source tag differs between languages." % node_label)
	if String(reference.next_id) != String(other.next_id) or reference.ends_here != other.ends_here:
		problems.append("%s: jump target differs between languages." % node_label)
	if reference.tags != other.tags:
		problems.append("%s: tags differ between languages." % node_label)

	_compare_effects(reference.effects, other.effects, node_label, problems)
	_compare_conditions(reference, other, node_label, problems)

	if reference.choices.size() != other.choices.size():
		problems.append(
			"%s: has %d choice(s) but should have %d."
			% [node_label, other.choices.size(), reference.choices.size()]
		)
	for index in min(reference.choices.size(), other.choices.size()):
		var reference_choice: DialogueGraph.DialogueChoice = reference.choices[index]
		var other_choice: DialogueGraph.DialogueChoice = other.choices[index]
		var choice_label := "%s choice '%s'" % [node_label, reference_choice.choice_id]
		if reference_choice.choice_id != other_choice.choice_id:
			problems.append(
				"%s: choice #%d has id '%s' but should be '%s'."
				% [node_label, index, other_choice.choice_id, reference_choice.choice_id]
			)
		if other_choice.text.strip_edges().is_empty():
			problems.append("%s: missing translation (empty choice text)." % choice_label)
		if String(reference_choice.next_id) != String(other_choice.next_id):
			problems.append("%s: jump target differs between languages." % choice_label)
		if reference_choice.once != other_choice.once:
			problems.append("%s: 'once' differs between languages." % choice_label)
		if reference_choice.check != other_choice.check:
			problems.append("%s: check definition differs between languages." % choice_label)
		_compare_conditions(reference_choice, other_choice, choice_label, problems)
		_compare_effects(reference_choice.effects, other_choice.effects, choice_label, problems)


static func _compare_conditions(
	reference: Variant,
	other: Variant,
	node_label: String,
	problems: Array[String]
) -> void:
	if reference.requires != other.requires:
		problems.append("%s: conditions.requires differ between languages." % node_label)
	if reference.all_flags != other.all_flags:
		problems.append("%s: conditions.all_flags differ between languages." % node_label)
	if reference.not_flags != other.not_flags:
		problems.append("%s: conditions.not_flags differ between languages." % node_label)


## Effects are behaviour, not prose: flag names, objective keys and entry ids
## must be identical in both languages.
static func _compare_effects(
	reference: Array, other: Array, label: String, problems: Array[String]
) -> void:
	if reference.size() != other.size():
		problems.append(
			"%s: has %d effect(s) but should have %d." % [label, other.size(), reference.size()]
		)
	for index in min(reference.size(), other.size()):
		var reference_effect: Dictionary = reference[index]
		var other_effect: Dictionary = other[index]
		for field: String in ["type", "flag", "value", "key", "entry_id", "source", "speaker"]:
			if not reference_effect.has(field) and not other_effect.has(field):
				continue
			if reference_effect.has(field) != other_effect.has(field) or (
				typeof(reference_effect.get(field)) != typeof(other_effect.get(field))
				 or reference_effect.get(field) != other_effect.get(field)
			):
				problems.append(
					"%s: effect #%d field '%s' is '%s' but should be '%s'."
					% [
						label,
						index,
						field,
						str(other_effect.get(field, "<none>")),
						str(reference_effect.get(field, "<none>")),
					]
				)


## Inspection content parity: same ids, same structure and effects, different prose.
static func compare_inspections(
	reference: InspectionLibrary,
	other: InspectionLibrary,
	reference_locale: String,
	other_locale: String
) -> Array[String]:
	var problems: Array[String] = []
	for inspection_id: StringName in reference.get_ids():
		var reference_data: InspectionLibrary.InspectionData = reference.get_inspection(inspection_id)
		var other_data: InspectionLibrary.InspectionData = other.get_inspection(inspection_id)
		var label := "inspection '%s' (%s)" % [inspection_id, other_locale]
		if other_data == null:
			problems.append("%s: missing in %s." % [label, reference_locale])
			continue
		if other_data.text.strip_edges().is_empty():
			problems.append("%s: missing translation (empty observation text)." % label)
		if reference_data.repeat_text.is_empty() != other_data.repeat_text.is_empty():
			problems.append("%s: repeat text is present in only one language." % label)
		if reference_data.source != other_data.source:
			problems.append("%s: narrative source tag differs between languages." % label)
		if String(reference_data.speaker_id) != String(other_data.speaker_id):
			problems.append("%s: speaker differs between languages." % label)
		if String(reference_data.record_entry_id) != String(other_data.record_entry_id):
			problems.append("%s: record entry id differs between languages." % label)
		if reference_data.record_source != other_data.record_source:
			problems.append("%s: record source differs between languages." % label)
		if String(reference_data.recall_entry_id) != String(other_data.recall_entry_id):
			problems.append("%s: recall entry id differs between languages." % label)
		if reference_data.recall_text.is_empty() != other_data.recall_text.is_empty():
			problems.append("%s: one language has a recollection line and the other does not." % label)
		if reference_data.effects.size() != other_data.effects.size():
			problems.append("%s: effect count differs between languages." % label)
		else:
			_compare_effects(reference_data.effects, other_data.effects, label, problems)
	for inspection_id: StringName in other.get_ids():
		if not reference.has_inspection(inspection_id):
			problems.append(
				"inspection '%s' (%s): does not exist in %s."
				% [inspection_id, other_locale, reference_locale]
			)
	return problems
