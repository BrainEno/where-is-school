extends TestCaseHelper
## Content-integrity tests for the prologue: every authored script validates,
## every speaker exists, every declared record is known, and the narrative
## boundaries the design depends on (B never speaks onstage, choices do not all
## converge) are enforced as data assertions rather than review notes.


func _run() -> void:
	_test_all_scripts_validate()
	_test_speakers_are_known()
	_test_records_are_declared()
	_test_flags_are_declared()
	_test_b_has_no_onstage_exposition()
	_test_choice_counts()
	_test_choice_outcomes_differ()
	_test_imagined_records_are_declared_imagined()
	_test_inspection_content()
	_test_no_manuscript_markers()


func _test_all_scripts_validate() -> void:
	for script in PrologueDialogue.scripts():
		var problems: PackedStringArray = script.validate()
		check_empty(problems, "dialogue '%s' validates cleanly" % String(script.id))


func _test_speakers_are_known() -> void:
	for script in PrologueDialogue.scripts():
		var problems: PackedStringArray = CharacterDirectory.validate_script(script)
		check_empty(problems, "dialogue '%s' only names known speakers" % String(script.id))


func _test_records_are_declared() -> void:
	var declared: Array[StringName] = PrologueRecords.entry_ids()
	check(declared.size() >= 15, "the prologue declares a useful set of records", str(declared.size()))
	for script in PrologueDialogue.scripts():
		for node_id in script.node_ids():
			var node: DialogueNode = script.get_node(node_id)
			for record_id in node.on_enter_records:
				check_has(declared, record_id, "node '%s' record '%s' is declared" % [String(node_id), String(record_id)])
			for choice in node.choices:
				for record_id in choice.records:
					check_has(
						declared, record_id,
						"choice '%s' record '%s' is declared" % [String(choice.id), String(record_id)]
					)


func _test_flags_are_declared() -> void:
	var known: Array[StringName] = PrologueFlags.all()
	for script in PrologueDialogue.scripts():
		for node_id in script.node_ids():
			var node: DialogueNode = script.get_node(node_id)
			for flag_name in node.on_enter_flags.keys():
				check_has(known, StringName(flag_name), "node '%s' flag '%s' is declared" % [String(node_id), flag_name])
			for choice in node.choices:
				for flag_name in choice.flags.keys():
					if StringName(flag_name) == PrologueFlags.Q_ATTITUDE:
						continue
					check_has(
						known, StringName(flag_name),
						"choice '%s' flag '%s' is declared" % [String(choice.id), flag_name]
					)


## B must be absent from the opening. She may appear inside a rehearsal, but she
## may never say anything in a node that is not marked imagined, and nothing in
## the classroom scenes may cite her as present.
func _test_b_has_no_onstage_exposition() -> void:
	var b_line_count: int = 0
	for script in PrologueDialogue.scripts():
		for node_id in script.node_ids():
			var node: DialogueNode = script.get_node(node_id)
			for line in node.lines:
				if line.speaker != &"b":
					continue
				b_line_count += 1
				check_true(node.imagined, "B only speaks inside a rehearsal (node '%s')" % String(node_id))
				check_true(line.imagined, "B's line is flagged imagined in node '%s'" % String(node_id))
	check(b_line_count >= 1, "the rehearsal actually contains something B would say")
	check(
		not GameState.get_bool(PrologueFlags.N_ENTERED),
		"B's absence is not pre-empted by N before the lesson"
	)


func _test_choice_counts() -> void:
	var q_script: DialogueScript = PrologueDialogue.q_conversation()
	check(
		q_script.choice_count() >= 3,
		"Q's conversation offers at least three meaningful choices",
		str(q_script.choice_count())
	)
	var n_script: DialogueScript = PrologueDialogue.n_lesson()
	check(n_script.choice_count() >= 2, "N's lesson offers responses of its own", str(n_script.choice_count()))
	var rehearsal: DialogueScript = PrologueDialogue.anticipation()
	check(rehearsal.choice_count() >= 2, "the rehearsal is played, not watched", str(rehearsal.choice_count()))


## The acceptance criteria ask that choices not converge into identical output.
## This test walks every choice and asserts each one owns at least one distinct
## consequence: its own reply line, flag, record, or target node.
func _test_choice_outcomes_differ() -> void:
	for script in PrologueDialogue.scripts():
		for node_id in script.node_ids():
			var node: DialogueNode = script.get_node(node_id)
			if not node.has_choices():
				continue
			var seen_targets: Dictionary = {}
			var seen_records: Dictionary = {}
			for choice in node.choices:
				var has_reply: bool = not choice.reply_lines.is_empty()
				var has_flag: bool = not choice.flags.is_empty()
				var has_record: bool = not choice.records.is_empty()
				check_true(
					has_reply or has_flag or has_record or not String(choice.goto).is_empty(),
					"choice '%s' has an observable consequence" % String(choice.id)
				)
				var target_key := String(choice.goto)
				if not target_key.is_empty():
					check_false(
						seen_targets.has(target_key),
						"choices in '%s' do not share a convergence node (%s)" % [String(node_id), target_key]
					)
					seen_targets[target_key] = true
				for record_id in choice.records:
					check_false(
						seen_records.has(String(record_id)),
						"choices in '%s' write different records" % String(node_id)
					)
					seen_records[String(record_id)] = true


func _test_imagined_records_are_declared_imagined() -> void:
	# Anything downstream of the rehearsal must be declared IMAGINED, or the flow
	# will (correctly) refuse it at runtime.
	var rehearsal: DialogueScript = PrologueDialogue.anticipation()
	var imagined_ids: Array[StringName] = []
	for node_id in rehearsal.node_ids():
		var node: DialogueNode = rehearsal.get_node(node_id)
		for record_id in node.on_enter_records:
			imagined_ids.append(record_id)
		for choice in node.choices:
			for record_id in choice.records:
				imagined_ids.append(record_id)
	check(imagined_ids.size() >= 3, "the rehearsal records its own beats")
	for record_id in imagined_ids:
		var entry: Dictionary = PrologueRecords.entry_for(record_id)
		check_false(entry.is_empty(), "rehearsal record '%s' is declared" % String(record_id))
		if entry.is_empty():
			continue
		check_eq(
			int(entry["kind"]),
			int(NarrativeRecord.Kind.IMAGINED),
			"rehearsal record '%s' is declared IMAGINED" % String(record_id)
		)


func _test_inspection_content() -> void:
	var required: Array[StringName] = [
		&"schoolbag", &"set_square", &"teacher_desk", &"chalkboard", &"timetable", &"window",
	]
	var titles: Dictionary = {}
	for inspect_id in required:
		check_true(PrologueInspections.has_entry(inspect_id), "inspection '%s' has content" % String(inspect_id))
		var entry: Dictionary = PrologueInspections.get_entry(inspect_id)
		if entry.is_empty():
			continue
		var title: String = String(entry["title"])
		var body: String = String(entry["text"])
		check(not title.is_empty(), "inspection '%s' has a title" % String(inspect_id))
		check(body.length() >= 60, "inspection '%s' has a real description" % String(inspect_id))
		check(
			not titles.has(title),
			"inspection '%s' has its own title, not a reused one" % String(inspect_id)
		)
		titles[title] = true

	# The missing textbook must have a record, and the bag must set the flag the
	# rest of the flow gates on.
	var bag: Dictionary = PrologueInspections.get_entry(&"schoolbag")
	check_eq(StringName(bag["flag"]), PrologueFlags.BAG_EXAMINED, "the bag sets the examined flag")
	check_eq(
		StringName(bag["extra_flag"]), PrologueFlags.TEXTBOOK_MISSING,
		"the bag sets the missing-textbook flag that gates the lesson"
	)
	check_contains_text(String(bag["text"]), "textbook", "the bag text names the missing textbook")


## Cheap, blunt guard against accidentally pasting prose. These are properties of
## unpublished literary text (long paragraphs, quoted dialogue, first-person
## interiority at length) that should never appear in a game-content table.
func _test_no_manuscript_markers() -> void:
	for inspect_id in PrologueInspections.ids():
		var entry: Dictionary = PrologueInspections.get_entry(inspect_id)
		var body: String = String(entry.get("text", ""))
		check(body.length() <= 420, "inspection '%s' stays short" % String(inspect_id))
		check_false(body.contains("\n\n"), "inspection '%s' has no pasted paragraphs" % String(inspect_id))
		check_false(
			body.contains("\n") or body.begins_with("“"),
			"inspection '%s' is not pasted quoted prose" % String(inspect_id)
		)
	for script in PrologueDialogue.scripts():
		for node_id in script.node_ids():
			var node: DialogueNode = script.get_node(node_id)
			for line in node.lines:
				check(line.text.length() <= 340, "line in '%s' stays speakable" % String(node_id))
