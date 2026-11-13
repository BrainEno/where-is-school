extends SceneTree
## Content validation for the opening slice.
##
## Proves the authored data is internally consistent (targets, speakers, effects)
## and that the opening actually contains the interaction density the brief asks
## for, so a later content edit cannot quietly remove the choices.

const Harness = preload("res://tests/test_harness.gd")
const OPENING_CONVERSATION := &"q_wake"

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "dialogue_content_test.gd")
	call_deferred("_run")


func _run() -> void:
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		for message: String in library.errors:
			print("DIAG dialogue: %s" % message)
	_inspect_conversations(library)

	var inspections := InspectionLibrary.load_all()
	if not inspections.is_valid():
		_failures.append(inspections.describe_errors())
		for message: String in inspections.errors:
			print("DIAG inspection: %s" % message)
	_check_inspections(inspections)

	Harness.finish(self, _failures, "dialogue and inspection content are consistent.")


func _inspect_conversations(library: DialogueLibrary) -> void:
	# The registry is what tells the directory which profiles are inner voices, so a
	# speaker id like `voice_orientation` is found by declaration rather than by a list.
	var abilities := InnerAbilities.load_all()
	if not abilities.is_valid():
		_failures.append(abilities.describe_errors())
	var characters := CharacterDirectory.load_all(abilities)
	if not characters.errors.is_empty():
		_failures.append("\n".join(characters.errors))

	for speaker_id in library.get_referenced_speaker_ids():
		if not characters.has_character(speaker_id):
			_failures.append("Speaker '%s' has no CharacterProfile." % speaker_id)

	if not library.has_conversation(OPENING_CONVERSATION):
		_failures.append("Missing opening conversation '%s'." % OPENING_CONVERSATION)
		return

	var total_choices := 0
	var branch_targets: Dictionary = {}
	for conversation_id in library.get_conversation_ids():
		var conversation := library.get_conversation(conversation_id)
		if conversation == null:
			_failures.append("Conversation '%s' could not be read." % conversation_id)
			continue
		if conversation.nodes.is_empty():
			_failures.append("Conversation '%s' has no nodes." % conversation_id)
		for node_id in conversation.order:
			var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
			total_choices += node.choices.size()
			for choice: DialogueGraph.DialogueChoice in node.choices:
				if choice.text.strip_edges().is_empty():
					_failures.append(
						"%s/%s has an empty choice." % [conversation_id, node_id]
					)
				if not conversation.nodes.has(choice.next_id):
					_failures.append(
						"%s/%s choice target '%s' is missing."
						% [conversation_id, node_id, choice.next_id]
					)
				branch_targets[choice.next_id] = true

	if total_choices < 3:
		_failures.append(
			"The opening needs at least three meaningful choices, found %d." % total_choices
		)

	# Choices must not all funnel into the same node on the same conversation.
	var opening := library.get_conversation(OPENING_CONVERSATION)
	var opening_targets: Dictionary = {}
	for node_id in opening.order:
		var node: DialogueGraph.DialogueNode = opening.nodes[node_id]
		for choice: DialogueGraph.DialogueChoice in node.choices:
			opening_targets[choice.next_id] = true
	if opening_targets.size() < 3:
		_failures.append(
			"The opening conversation's choices lead to %d distinct nodes; expected at least 3."
			% opening_targets.size()
		)

	# The expectation conversation must be marked subjective.
	if not library.has_conversation(&"expected_b"):
		_failures.append("Missing the subjective expectation conversation.")
	else:
		var expected := library.get_conversation(&"expected_b")
		if not expected.subjective:
			_failures.append("'expected_b' must be marked subjective.")
		if expected.default_source != NarrativeEntry.Source.IMAGINED:
			_failures.append("'expected_b' must default to the 'imagined' source.")

	# Each inspected narrative id must be unique across the content.
	_check_unique_narrative_ids(library)
	_check_free_period_gate(library)


func _check_unique_narrative_ids(library: DialogueLibrary) -> void:
	var seen: Dictionary = {}
	for conversation_id in library.get_conversation_ids():
		var conversation := library.get_conversation(conversation_id)
		for node_id in conversation.order:
			var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
			for effect: Dictionary in node.effects:
				_register_entry(seen, effect, "%s/%s" % [conversation_id, node_id])
			for choice: DialogueGraph.DialogueChoice in node.choices:
				for effect: Dictionary in choice.effects:
					_register_entry(seen, effect, "%s/%s" % [conversation_id, node_id])


func _register_entry(seen: Dictionary, effect: Dictionary, context: String) -> void:
	if String(effect.get("type", "")) != "record":
		return
	var entry_id := String(effect.get("entry_id", ""))
	if entry_id.is_empty():
		_failures.append("%s has a record effect without an entry id." % context)
		return
	if seen.has(entry_id):
		_failures.append(
			"Narrative entry '%s' is recorded twice (%s and %s)." % [entry_id, seen[entry_id], context]
		)
		return
	seen[entry_id] = context


func _check_inspections(inspections: InspectionLibrary) -> void:
	if inspections.get_ids().is_empty():
		_failures.append("No inspection content was loaded.")
		return
	for inspection_id in inspections.get_ids():
		var inspection := inspections.get_inspection(inspection_id)
		if inspection.text.strip_edges().is_empty():
			_failures.append("Inspection '%s' has no text." % inspection_id)
		if inspection.prompt.strip_edges().is_empty():
			_failures.append("Inspection '%s' has no prompt." % inspection_id)
		if not String(inspection.recall_text).is_empty() and \
				String(inspection.recall_entry_id).is_empty():
			_failures.append("Inspection '%s' has recall text but no recall entry id." % inspection_id)
		for effect: Dictionary in inspection.effects:
			match String(effect.get("type", "")):
				"set_flag":
					if String(effect.get("flag", "")).is_empty():
						_failures.append("Inspection '%s' has a set_flag without a flag." % inspection_id)
				"set_objective":
					var key := String(effect.get("key", ""))
					if key.is_empty():
						_failures.append("Inspection '%s' has an empty objective key." % inspection_id)
					elif not L10n.has_key(key):
						_failures.append(
							"Inspection '%s' uses objective key '%s' that no locale defines."
							% [inspection_id, key]
						)
				_:
					_failures.append(
						"Inspection '%s' uses unsupported effect '%s'."
						% [inspection_id, effect.get("type", "")]
					)

	var classroom_inspections := 0
	for inspection_id in inspections.get_ids():
		if String(inspection_id).begins_with("classroom_"):
			classroom_inspections += 1
	if classroom_inspections < 4:
		_failures.append(
			"The classroom needs at least four inspectable texts, found %d." % classroom_inspections
		)

	if not inspections.has_inspection(&"classroom_door_blocked"):
		_failures.append("The blocked-door text is missing.")
	if not inspections.has_inspection(&"classroom_schoolbag"):
		_failures.append("The schoolbag text is missing.")


func _check_free_period_gate(library: DialogueLibrary) -> void:
	if not library.has_conversation(&"n_class") or not library.has_conversation(&"q_after_dismissal"):
		_failures.append("The substitute lesson or Q's free-period invitation is missing.")
		return
	var before_dismissal := ConversationRouter.select(
		&"q", {StoryFlags.TEXTBOOK_MISSING: true}
	)
	if before_dismissal == &"q_after_dismissal":
		_failures.append("Q's free-period invitation is available before N dismisses the class.")
	var after_dismissal := ConversationRouter.select(
		&"q", {StoryFlags.CLASS_DISMISSED: true}
	)
	if after_dismissal != &"q_after_dismissal":
		_failures.append("Q's free-period invitation is not routed after class dismissal.")
	var invitation := library.get_conversation(&"q_after_dismissal")
	var choice_hub_found := false
	for node_id in invitation.order:
		var node: DialogueGraph.DialogueNode = invitation.nodes[node_id]
		if node_id == &"q_ad_1":
			choice_hub_found = node.choices.size() >= 4
	if not choice_hub_found:
		_failures.append("Q's invitation needs accept, defer, decline and silent choices.")
