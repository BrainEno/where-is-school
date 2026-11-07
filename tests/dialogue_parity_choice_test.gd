extends SceneTree
## Tests the fix for dialogue_parity.gd: choice-level conditions must be compared.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "dialogue_parity_choice_test.gd")
	call_deferred("_run")

func _run() -> void:
	_test_requires_mismatch()
	_test_all_flags_mismatch()
	_test_not_flags_mismatch()
	_test_consistent_pass()
	_test_check_mismatch()
	Harness.finish(self, _failures, "choice parity correctly distinguishes requires/all_flags/not_flags/checks.")

func _base_graph() -> DialogueGraph:
	var g := DialogueGraph.new()
	g.source_path = "reference.json"
	g.locale = "en"
	g.chapter = "fixture"
	var conv := DialogueGraph.Conversation.new()
	conv.conversation_id = &"par"
	conv.start_id = &"n1"
	var n1 := DialogueGraph.DialogueNode.new()
	n1.node_id = &"n1"
	n1.speaker_id = &"q"
	n1.text = "Fixt."
	var c1 := DialogueGraph.DialogueChoice.new()
	c1.choice_id = &"c1"
	c1.text = "Choice one"
	c1.next_id = &"n2"
	c1.requires = {&"met_q": true}
	c1.all_flags = [&"a"]
	c1.not_flags = [&"b"]
	n1.choices.append(c1)
	conv.nodes[n1.node_id] = n1
	conv.order.append(n1.node_id)
	var n2 := DialogueGraph.DialogueNode.new()
	n2.node_id = &"n2"
	n2.speaker_id = &"q"
	n2.text = "End."
	n2.ends_here = true
	conv.nodes[n2.node_id] = n2
	conv.order.append(n2.node_id)
	g.conversations[&"par"] = conv
	return g

func _other_with_choice_mod(mod: Callable) -> DialogueGraph:
	var g := _base_graph()
	g.source_path = "translation.json"
	g.locale = "zh-CN"
	var conv: DialogueGraph.Conversation = g.conversations[&"par"]
	var node: DialogueGraph.DialogueNode = conv.nodes[&"n1"]
	var choice: DialogueGraph.DialogueChoice = node.choices[0]
	mod.call(choice)
	return g

func _test_requires_mismatch() -> void:
	var ref := _base_graph()
	var other := _other_with_choice_mod(func(c: DialogueGraph.DialogueChoice): c.requires = {&"met_q": false})
	var problems := DialogueParity.compare(ref, other)
	var found := false
	for p in problems:
		if String(p).contains("requires"):
			found = true
	if not found:
		_failures.append("Choice requires mismatch should be reported but parity passed: %s" % str(problems))

func _test_all_flags_mismatch() -> void:
	var ref := _base_graph()
	var other := _other_with_choice_mod(func(c: DialogueGraph.DialogueChoice): c.all_flags = [&"x"])
	var problems := DialogueParity.compare(ref, other)
	var found := false
	for p in problems:
		if String(p).contains("condition flags") or String(p).contains("all_flags"):
			found = true
	if not found:
		_failures.append("Choice all_flags mismatch should be reported: %s" % str(problems))

func _test_not_flags_mismatch() -> void:
	var ref := _base_graph()
	var other := _other_with_choice_mod(func(c: DialogueGraph.DialogueChoice): c.not_flags = [])
	var problems := DialogueParity.compare(ref, other)
	var found := false
	for p in problems:
		if String(p).contains("condition flags") or String(p).contains("not_flags"):
			found = true
	if not found:
		_failures.append("Choice not_flags mismatch should be reported: %s" % str(problems))

func _test_consistent_pass() -> void:
	var ref := _base_graph()
	var other := _base_graph()
	other.source_path = "translation.json"
	other.locale = "zh-CN"
	var problems := DialogueParity.compare(ref, other)
	if not problems.is_empty():
		_failures.append("Identical choice conditions should pass parity but got: %s" % str(problems))

func _test_check_mismatch() -> void:
	var ref := _base_graph()
	var conv: DialogueGraph.Conversation = ref.conversations[&"par"]
	var n1: DialogueGraph.DialogueNode = conv.nodes[&"n1"]
	var chk := DialogueGraph.DialogueCheck.new()
	chk.check_id = &"my_check"
	chk.ability_id = &"keen_eye"
	chk.difficulty = 12
	chk.visible = true
	n1.check = chk
	var other := _base_graph()
	other.source_path = "translation.json"
	other.locale = "zh-CN"
	# other has no check -> should report
	var problems := DialogueParity.compare(ref, other)
	var found := false
	for p in problems:
		if String(p).contains("dice check") or String(p).contains("check"):
			found = true
	if not found:
		_failures.append("Missing check in one language should be reported: %s" % str(problems))
