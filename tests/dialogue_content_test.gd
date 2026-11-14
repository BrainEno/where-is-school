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
	_check_q_studying(library, characters)


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


## #160: the meeting flag means Q has spoken, not that every later interaction is
## another wake-up. Exhaust every existing combination of the three choice hubs in
## both locales, through the real runtime, so no branch can lose the shared ending or
## its own consequences while the first/last lines are edited.
func _check_q_studying(library: DialogueLibrary, characters: CharacterDirectory) -> void:
	var routes := [
		{"flags": {}, "want": &"q_wake"},
		{"flags": {StoryFlags.MET_Q: false}, "want": &"q_wake"},
		{"flags": {StoryFlags.MET_Q: true}, "want": &"q_studying"},
		{"flags": {StoryFlags.TEXTBOOK_MISSING: true}, "want": &"q_after_bag"},
		{"flags": {StoryFlags.MET_Q: true, StoryFlags.TEXTBOOK_MISSING: true}, "want": &"q_after_bag"},
		{"flags": {StoryFlags.MET_Q: true, StoryFlags.CLASS_DISMISSED: true}, "want": &"q_after_dismissal"},
		{"flags": {StoryFlags.TEXTBOOK_MISSING: true, StoryFlags.CLASS_DISMISSED: true}, "want": &"q_after_dismissal"},
		{"flags": {StoryFlags.BAG_WAIT_EXPIRED: true, StoryFlags.MET_Q: true}, "want": &"q_studying"},
	]
	for case: Dictionary in routes:
		var got := ConversationRouter.select(&"q", case["flags"])
		if got != case["want"]:
			_failures.append("Q route %s selected '%s', wanted '%s'." % [case["flags"], got, case["want"]])

	for locale: String in L10n.LOCALES:
		library.set_locale(locale)
		var opening := library.get_conversation(OPENING_CONVERSATION)
		var first: DialogueGraph.DialogueNode = opening.nodes[&"q_1"]
		var ending: DialogueGraph.DialogueNode = opening.nodes[&"q_end_2"]
		if (locale == "zh-CN" and not first.text.contains("睡得")) \
				or (locale == "en" and not first.text.to_lower().contains("nap")):
			_failures.append("%s: Q's first line is not the familiar teasing greeting (#160)." % locale)
		if (locale == "zh-CN" and not ending.text.contains("知识点")) \
				or (locale == "en" and not ending.text.to_lower().contains("biology")):
			_failures.append("%s: Q does not end by returning to biology revision." % locale)
		var busy := library.get_conversation(&"q_studying")
		if busy == null:
			_failures.append("%s: the independent q_studying response is missing." % locale)
		else:
			if busy.order.is_empty() or busy.order.size() > 2:
				_failures.append("%s: q_studying is not a short response." % locale)
			for node: DialogueGraph.DialogueNode in busy.nodes.values():
				if node.speaker_id != &"q" or not node.choices.is_empty() or not node.effects.is_empty():
					_failures.append("%s: q_studying changes state or is not Q's short reply." % locale)
				if node.text.contains("醒") or node.text.to_lower().contains("wake"):
					_failures.append("%s: q_studying repeats the wake-up greeting." % locale)
		for identity in 3:
			for exam in 3:
				for topic in 3:
					_check_q_branch(library, characters, locale, [identity, exam, topic])
	library.set_locale(L10n.DEFAULT_LOCALE)


func _check_q_branch(
	library: DialogueLibrary, characters: CharacterDirectory, locale: String, picks: Array
) -> void:
	var state: Node = load(Harness.GAME_STATE_SCRIPT).new()
	var narrative: Node = load(Harness.NARRATIVE_STATE_SCRIPT).new()
	var runtime := DialogueRuntime.new(state, narrative, characters)
	var seen: Array[StringName] = []
	runtime.line_changed.connect(func(line: Dictionary) -> void: seen.append(line["node_id"]))
	var label := "%s Q choices %s" % [locale, str(picks)]
	if not runtime.start(library.get_graph(OPENING_CONVERSATION), OPENING_CONVERSATION):
		_failures.append("%s could not start." % label)
	else:
		var hubs := 0
		var steps := 0
		while runtime.is_active() and steps < 100:
			if runtime.is_awaiting_choice():
				var expected := [
					[&"who", &"day", &"silent"], [&"blank", &"absent", &"none"],
					[&"ask", &"silent", &"search"],
				]
				if hubs >= picks.size() or runtime.get_available_choice_ids() != expected[hubs]:
					_failures.append("%s: choice hub %d lost its original options." % [label, hubs])
					break
				runtime.choose(int(picks[hubs]))
				hubs += 1
			else:
				runtime.advance()
			steps += 1
		if runtime.is_active() or hubs != 3 or seen.is_empty() or seen[-1] != &"q_end_2":
			_failures.append("%s did not reach the shared closing node (hubs=%d, steps=%d)." % [label, hubs, steps])
		if not bool(state.get_flag(StoryFlags.MET_Q, false)) \
				or not bool(state.get_flag(StoryFlags.ASKED_Q_IDENTITY, false)):
			_failures.append("%s lost the meeting/identity flags." % label)
		for flag: StringName in [StoryFlags.ASKED_Q_DATE, StoryFlags.STAYED_SILENT, StoryFlags.DENIED_EXAM_MEMORY]:
			var want := (flag == StoryFlags.ASKED_Q_DATE and picks[0] == 1) \
				or (flag == StoryFlags.STAYED_SILENT and picks[0] == 2) \
				or (flag == StoryFlags.DENIED_EXAM_MEMORY and picks[1] == 2)
			if bool(state.get_flag(flag, false)) != want:
				_failures.append("%s: consequence '%s' does not match the chosen branch." % [label, flag])
		if String(state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.check_bag":
			_failures.append("%s lost the schoolbag objective." % label)
		var entry: NarrativeEntry = narrative.get_entry(&"q_claims_blank_exam")
		if entry == null or entry.source != NarrativeEntry.Source.REPORTED:
			_failures.append("%s lost Q's uncertain exam account or made it fact." % label)
	state.free()
	narrative.free()
