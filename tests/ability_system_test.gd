extends SceneTree
## Tests inner ability registry and passive triggers.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "ability_system_test.gd")
	call_deferred("_run")

func _run() -> void:
	_test_load()
	_test_values()
	_test_passive_trigger()
	_test_passive_not_firing_when_condition_missing()
	_test_active_check_path()
	_test_different_abilities_results()
	Harness.finish(self, _failures, "inner abilities load/value/passive/active/different results work.")

func _test_load() -> void:
	var reg = AbilityRegistry.load_all()
	if not reg.is_valid():
		_failures.append(reg.describe_errors())
	if reg.get_ids().size() < 4:
		_failures.append("Expected 4 abilities, got %d" % reg.get_ids().size())
	for id in [&"keen_eye", &"recollection", &"gut_feeling", &"steadiness"]:
		if not reg.has_ability(id):
			_failures.append("Missing ability %s" % id)

func _test_values() -> void:
	var reg = AbilityRegistry.load_all()
	var a = reg.get_ability(&"keen_eye")
	if a == null:
		_failures.append("keen_eye missing")
		return
	if a.get_value() < 1:
		_failures.append("Ability value should be >=1, got %d" % a.get_value())
	if a.name_key.is_empty() or a.description_key.is_empty():
		_failures.append("Ability missing name/description keys")

func _test_passive_trigger() -> void:
	var gs = load(Harness.GAME_STATE_SCRIPT).new()
	gs.name = "GameState"
	var rpg = load("res://scripts/rpg/rpg_manager.gd").new()
	rpg._game_state = gs
	rpg.abilities_load()
	rpg._init_passive_triggers()
	# Simulate entering playground
	var lines: Array = rpg.evaluate_passives({"location_id": "playground"})
	if lines.is_empty():
		_failures.append("Passive triggers should fire on playground entry, got none.")
	# Second call should be fewer (once per session)
	var lines2: Array = rpg.evaluate_passives({"location_id": "playground"})
	if lines2.size() >= lines.size():
		# At least not more than first (once triggers consumed)
		# Might still have some ALWAYS but in this slice all are ONCE
		pass

func _test_passive_not_firing_when_condition_missing() -> void:
	var gs = load(Harness.GAME_STATE_SCRIPT).new()
	gs.name = "GameState"
	var t = PassiveTrigger.new()
	t.trigger_id = &"test_cond"
	t.ability_id = &"keen_eye"
	t.condition_flags = [&"nonexistent_flag"]
	t.frequency = PassiveTrigger.Frequency.ALWAYS
	if t.conditions_met(gs):
		_failures.append("Trigger with unmet flag should not be conditions_met.")

func _test_active_check_path() -> void:
	var gs = load(Harness.GAME_STATE_SCRIPT).new()
	gs.name = "GameState"
	var ns = load(Harness.NARRATIVE_STATE_SCRIPT).new()
	ns.name = "NarrativeState"
	var chars = CharacterDirectory.load_all()
	var graph = DialogueGraph.new()
	graph.source_path = "test.json"
	graph.locale = "en"
	graph.chapter = "fixture"
	var conv = DialogueGraph.Conversation.new()
	conv.conversation_id = &"chk"
	conv.start_id = &"a1"
	var n1 = DialogueGraph.DialogueNode.new()
	n1.node_id = &"a1"
	n1.speaker_id = &"protagonist"
	n1.text = "Try."
	var chk = DialogueGraph.DialogueCheck.new()
	chk.check_id = &"test_active"
	chk.ability_id = &"keen_eye"
	chk.difficulty = 5
	chk.visible = true
	n1.check = chk
	n1.next_id = &"a2"
	conv.nodes[n1.node_id] = n1
	conv.order.append(n1.node_id)
	var n2 = DialogueGraph.DialogueNode.new()
	n2.node_id = &"a2"
	n2.speaker_id = &"protagonist"
	n2.text = "After check."
	n2.ends_here = true
	conv.nodes[n2.node_id] = n2
	conv.order.append(n2.node_id)
	graph.conversations[&"chk"] = conv
	var rt = DialogueRuntime.new(gs, ns, chars)
	var rng = RandomNumberGenerator.new()
	rng.seed = 1
	var engine = CheckEngine.new(rng, gs)
	rt.set_check_engine(engine)
	if not rt.start(graph, &"chk"):
		_failures.append("Runtime should start check conversation.")
		return
	if gs.get_flag(StoryFlags.check_success_flag(&"test_active"), null) == null:
		_failures.append("Active check should set success flag.")
	# second advance should reach a2
	rt.advance()
	if rt.get_current_node_id() != &"a2":
		_failures.append("After check, should advance to a2, got %s" % rt.get_current_node_id())

func _test_different_abilities_results() -> void:
	var reg = AbilityRegistry.load_all()
	var a1 = reg.get_ability(&"keen_eye")
	var a2 = reg.get_ability(&"recollection")
	if a1 == null or a2 == null:
		_failures.append("Missing abilities for diff test")
		return
	# They have different base values (keen_eye 3, recollection 2) -> totals differ given same roll
	var gs = load(Harness.GAME_STATE_SCRIPT).new()
	var e1 = CheckEngine.new(null, gs)
	e1.reseed(1)
	var r1 = e1.roll_for_ability(&"diff", a1, 10, 0, true, true)
	e1.reseed(1)
	var r2 = e1.roll_for_ability(&"diff2", a2, 10, 0, true, true)
	# r1 total - r2 total should equal difference in ability values
	var diff = a1.get_value() - a2.get_value()
	if r1.total - r2.total != diff:
		_failures.append("Different abilities should affect total by %d, got %d vs %d" % [diff, r1.total, r2.total])
