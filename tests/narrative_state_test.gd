extends SceneTree
## Headless logic tests for the narrative-state layer.
##
## These test behaviour, not constants: provenance separation, append-only ledger
## semantics, snapshot round-trips, dialogue graph traversal, and content
## validation over the real authored conversation files.

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_provenance_boundaries()
	_test_ledger_behaviour()
	_test_ledger_round_trip()
	_test_dialogue_traversal()
	_test_choice_consequences()
	_test_authored_content_is_valid()
	_test_flags_registry()

	if _failures.is_empty():
		print("narrative_state_test passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("narrative_state_test failed: %d failure(s) of %d checks." % [_failures.size(), _checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


# ---------------------------------------------------------------------------
func _test_provenance_boundaries() -> void:
	_check(NarrativeProvenance.is_objective(NarrativeProvenance.Kind.OBSERVED),
		"observed information must count as objective")
	for kind: int in [
		NarrativeProvenance.Kind.HEARD,
		NarrativeProvenance.Kind.RECOLLECTED,
		NarrativeProvenance.Kind.IMAGINED,
	]:
		_check(not NarrativeProvenance.is_objective(kind),
			"provenance kind %d must not count as objective" % kind)
	_check(NarrativeProvenance.from_id("imagined") == NarrativeProvenance.Kind.IMAGINED,
		"provenance id round-trip failed for 'imagined'")
	_check(NarrativeProvenance.id_of(NarrativeProvenance.Kind.HEARD) == "heard",
		"provenance id round-trip failed for heard")


func _test_ledger_behaviour() -> void:
	var ledger := NarrativeLedger.new()
	var signals: Array[int] = []
	ledger.entry_recorded.connect(func(_entry: NarrativeEntry) -> void: signals.append(1))

	ledger.record(&"a", NarrativeProvenance.Kind.OBSERVED, "看到", "observed", &"test")
	_check(ledger.count() == 1, "recording one entry must produce one entry")
	_check(signals.size() == 1, "recording must emit entry_recorded once")

	# Re-recording the same id must not duplicate or rewrite.
	ledger.record(&"a", NarrativeProvenance.Kind.OBSERVED, "看到", "observed", &"test")
	_check(ledger.count() == 1, "re-recording the same id must not duplicate the entry")
	_check(signals.size() == 1, "re-recording the same id must not emit again")

	ledger.record(&"b", NarrativeProvenance.Kind.IMAGINED, "想像", "imagined", &"test")
	_check(ledger.count() == 2, "a second id must be appended")
	_check(ledger.has_observed(&"a"), "observed entry must be reported as observed")
	_check(not ledger.has_observed(&"b"), "imagined entry must never be reported as observed")

	var imagined: Array[NarrativeEntry] = ledger.entries_of_kind(NarrativeProvenance.Kind.IMAGINED)
	_check(imagined.size() == 1 and imagined[0].id == &"b", "kind filtering failed")

	# Invalid provenance must be rejected, not silently coerced.
	var before: int = ledger.count()
	ledger.record(&"c", 99, "坏", "bad", &"test")
	_check(ledger.count() == before, "an invalid provenance kind must not create an entry")

	ledger.clear()
	_check(ledger.count() == 0, "clear must empty the ledger")


func _test_ledger_round_trip() -> void:
	var ledger := NarrativeLedger.new()
	ledger.record(&"x", NarrativeProvenance.Kind.HEARD, "听说", "heard", &"q_start")
	ledger.record(&"y", NarrativeProvenance.Kind.RECOLLECTED, "记得", "remembered", &"q_exam")
	var snapshot: Array = ledger.to_array()

	var restored := NarrativeLedger.new()
	restored.restore_from_array(snapshot)
	_check(restored.count() == 2, "snapshot round-trip lost entries")
	_check(restored.get_entry(&"x") != null, "snapshot round-trip lost entry x")
	_check(restored.get_entry(&"y").kind == NarrativeProvenance.Kind.RECOLLECTED,
		"snapshot round-trip changed provenance")

	# A new entry after restore must not collide with restored ids.
	restored.record(&"z", NarrativeProvenance.Kind.OBSERVED, "看到", "observed", &"test")
	_check(restored.count() == 3, "appending after restore failed")


func _test_dialogue_traversal() -> void:
	var script := DialogueScript.new(&"synthetic")
	script.define_character(&"speaker_x", "X", "X", Color.WHITE)
	var first := DialogueNode.new(&"one")
	first.say(&"speaker_x", "一", "one")
	first.choose(&"c1", "去二", "to two", &"two")
	first.choose(&"c2", "去三", "to three", &"three")
	var second := DialogueNode.new(&"two")
	second.say(&"speaker_x", "二", "two")
	var third := DialogueNode.new(&"three")
	third.say(&"speaker_x", "三", "three")
	script.add(first)
	script.add(second)
	script.add(third)

	_check(script.validate().is_empty(), "synthetic script should be valid: %s" % [script.validate()])

	var session := DialogueSession.new(script)
	_check(session.start().is_empty(), "session failed to start")
	_check(session.advance() != null, "first line should be available")
	_check(session.awaiting_choice(), "after the only line the node should await a choice")
	_check(session.choices().size() == 2, "two choices should be available")
	_check(session.backlog.size() == 1, "backlog should contain the read line")

	# A dangling continuation must be reported, not silently ignored.
	var broken := DialogueScript.new(&"broken")
	var node := DialogueNode.new(&"only")
	node.say(&"", "文字", "text")
	node.go_to(&"missing")
	broken.add(node)
	_check(not broken.validate().is_empty(), "a dangling continuation must fail validation")


func _test_choice_consequences() -> void:
	# Two choices in the authored Q conversation must lead to different nodes,
	# so this guards against accidental convergence.
	var script := PrologueQConversation.build()
	var start: DialogueNode = script.get_node_by_id(PrologueQConversation.START)
	_check(start != null, "Q conversation has no start node")
	var targets: Dictionary = {}
	for choice: DialogueChoice in start.choices:
		targets[choice.next_id] = true
	_check(start.choices.size() >= 3, "Q's opening must offer at least three choices")
	_check(targets.size() >= 3, "Q's opening choices must lead to distinct nodes")

	var pushback: DialogueChoice = null
	for choice: DialogueChoice in start.choices:
		if choice.id == &"q_choice_pushback":
			pushback = choice
	_check(pushback != null, "expected a pushback choice in Q's opening")
	if pushback != null:
		_check(pushback.flags.has(PrologueFlags.Q_PUSHBACK),
			"the pushback choice must set its story flag")
		_check(not pushback.aside_zh.is_empty(),
			"the pushback choice must give the protagonist a visible reaction")


func _test_authored_content_is_valid() -> void:
	var scripts: Array[DialogueScript] = [
		PrologueQConversation.build(),
		PrologueNConversation.build(),
		PrologueAnticipation.build(),
		StreetObservations.build(),
	]
	for inspection_id: StringName in [
		ClassroomInspections.BAG,
		ClassroomInspections.SET_SQUARE,
		ClassroomInspections.TEACHER_DESK,
		ClassroomInspections.TIMETABLE,
		ClassroomInspections.CHAIR,
		ClassroomInspections.WINDOW,
	]:
		for flags: Dictionary in [{}, {String(PrologueFlags.HEARD_SET_SQUARE): true}]:
			var inspection := ClassroomInspections.script_for(inspection_id, flags)
			_check(inspection != null, "no inspection script for '%s'" % inspection_id)
			if inspection != null:
				scripts.append(inspection)

	for script: DialogueScript in scripts:
		var problems: Array[String] = script.validate()
		if problems.is_empty():
			_checks += 1
		else:
			for problem: String in problems:
				_failures.append(problem)
		_check(script.unreachable_node_ids().is_empty(),
			"%s has unreachable nodes: %s" % [script.id, script.unreachable_node_ids()])
		# Bilingual content: every authored line must carry both languages.
		for node_id: StringName in script.nodes:
			for line: DialogueLine in script.nodes[node_id].lines:
				_check(not line.text_en.strip_edges().is_empty(),
					"%s/%s has a line without English text" % [script.id, node_id])
				_check(not line.text_zh.strip_edges().is_empty(),
					"%s/%s has a line without Chinese text" % [script.id, node_id])


func _test_flags_registry() -> void:
	var flags: Array[StringName] = PrologueFlags.all()
	var seen: Dictionary = {}
	for flag: StringName in flags:
		_check(flag != &"", "PrologueFlags.all() contains an empty identifier")
		_check(not seen.has(flag), "PrologueFlags.all() contains duplicate '%s'" % flag)
		_check(String(flag).begins_with("prologue."), "flag '%s' is missing the prologue. prefix" % flag)
		seen[flag] = true
	_check(flags.size() >= 20, "expected the prologue to declare its full flag set")

	# The subjective sequence must not be able to masquerade as an objective flag.
	# Autoloads do not exist under `--script`, so resolve the flag store explicitly.
	_check(StoryFlags.node() == null or not StoryFlags.has_flag(PrologueFlags.CONFRONTATION_IMAGINED),
		"the imagined-confrontation flag must not be set before the player imagines it")
