extends SceneTree
## Unit tests for the DialogueRunner conversation engine (headless).
## Verifies flags, choices, conditional choice gating, start overrides,
## imagination isolation, and finish semantics.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var game_state_script: GDScript = load("res://scripts/autoload/game_state.gd") as GDScript
	var runner_script: GDScript = load("res://scripts/dialogue/dialogue_runner.gd") as GDScript
	var conversation_script: GDScript = load("res://scripts/dialogue/dialogue_conversation.gd") as GDScript
	var entry_script: GDScript = load("res://scripts/dialogue/dialogue_entry.gd") as GDScript

	# ---------- bag_search: effects and backlog ----------
	var state: Node = game_state_script.new()
	var bag: Resource = load("res://data/dialogue/bag_search.tres")
	var bag_runner: RefCounted = runner_script.new(state)
	if not bag_runner.start(bag):
		failures.append("bag_search failed to start")
	_drain(bag_runner, failures)
	if state.get_flag(&"observed.textbook_missing") != true:
		failures.append("bag_search did not set observed.textbook_missing")
	if state.get_flag(&"recollection.exam_paper_blank") != true:
		failures.append("bag_search did not set recollection.exam_paper_blank")
	if bag_runner.backlog.size() != 4:
		failures.append("bag_search backlog expected 4 entries, got %d" % bag_runner.backlog.size())
	state.free()

	# ---------- q_intro: divergent choices ----------
	var state_a: Node = game_state_script.new()
	var q_intro: Resource = load("res://data/dialogue/q_intro.tres")
	var runner_a: RefCounted = runner_script.new(state_a)
	runner_a.start(q_intro)
	_advance_times(runner_a, 3) # q1 -> q4
	var offered: Array = runner_a.visible_choices()
	if offered.size() != 3:
		failures.append("q_intro expected 3 choices at q4, got %d" % offered.size())
	var pretend: Resource = _find_choice(offered, "Of course I remember.")
	if pretend == null:
		failures.append("q_intro 'Of course I remember.' choice not found")
	else:
		runner_a.choose(pretend)
		_drain(runner_a, failures)
	if state_a.get_flag(&"choice.pretend_remembered") != true:
		failures.append("choice.pretend_remembered not set")
	if state_a.has_flag(&"choice.brushed_q_off"):
		failures.append("choice.brushed_q_off should not be set by the pretend branch")
	if state_a.get_flag(&"flow.q_intro_done") != true:
		failures.append("flow.q_intro_done not set by q_intro")
	if state_a.get_flag(&"claim.q.exam_blank") != true:
		failures.append("claim.q.exam_blank not set by q_intro")
	state_a.free()

	var state_b: Node = game_state_script.new()
	var runner_b: RefCounted = runner_script.new(state_b)
	runner_b.start(q_intro)
	_advance_times(runner_b, 3)
	var offered_b: Array = runner_b.visible_choices()
	var brushed: Resource = _find_choice(offered_b, "Not now, Q.")
	if brushed == null:
		failures.append("q_intro 'Not now, Q.' choice not found")
	else:
		runner_b.choose(brushed)
		_drain(runner_b, failures)
	if state_b.get_flag(&"choice.brushed_q_off") != true:
		failures.append("choice.brushed_q_off not set in the dismissive branch")
	if state_b.has_flag(&"choice.pretend_remembered"):
		failures.append("choice.pretend_remembered should not be set by the dismissive branch")
	state_b.free()

	# ---------- imagination isolation: only imagination.* flags ----------
	var state_i: Node = game_state_script.new()
	var applied_flags: Array[String] = []
	var imagination: Resource = load("res://data/dialogue/imagination_b.tres")
	if imagination.presentation != "imagination":
		failures.append("imagination_b must use the 'imagination' presentation")
	var runner_i: RefCounted = runner_script.new(state_i)
	runner_i.effect_applied.connect(func(flag: StringName, _value: Variant) -> void: applied_flags.append(String(flag)))
	runner_i.start(imagination)
	_drain(runner_i, failures)
	for flag in applied_flags:
		if not flag.begins_with("imagination."):
			failures.append("imagination conversation set non-imagination flag '%s'" % flag)
	if state_i.get_flag(&"imagination.b_confrontation_seen") != true:
		failures.append("imagination.b_confrontation_seen not set")
	if state_i.count_flags_with_prefix("observed.") != 0:
		failures.append("imagination conversation leaked observed.* flags")
	state_i.free()

	# ---------- q_free_talk: choice gating on observed.textbook_missing ----------
	var state_g: Node = game_state_script.new()
	var free_talk: Resource = load("res://data/dialogue/q_free_talk.tres")
	var runner_g: RefCounted = runner_script.new(state_g)
	runner_g.start(free_talk) # defaults to ft_start
	runner_g.advance() # ft_start -> ft_choice
	var gated_choices: Array = runner_g.visible_choices()
	if gated_choices.size() != 2:
		failures.append("expected 2 visible choices before textbook discovery, got %d" % gated_choices.size())
	state_g.set_flag(&"observed.textbook_missing", true)
	var ungated_choices: Array = runner_g.visible_choices()
	if ungated_choices.size() != 3:
		failures.append("expected 3 visible choices after textbook discovery, got %d" % ungated_choices.size())
	var imagine: Resource = _find_choice(ungated_choices, "What if B walks in right now?")
	if imagine == null:
		failures.append("imagination choice missing after discovery")
	elif imagine.set_flag != &"flow.want_imagination":
		failures.append("imagination choice should request flow.want_imagination")
	state_g.free()

	# ---------- start_override selects a different branch ----------
	var state_o: Node = game_state_script.new()
	var runner_o: RefCounted = runner_script.new(state_o)
	runner_o.start(free_talk, &"ft_start_pretend")
	if runner_o.current_entry == null or runner_o.current_entry.id != &"ft_start_pretend":
		failures.append("start_override did not select ft_start_pretend")
	state_o.free()

	# ---------- conversation_finished signal fires ----------
	var state_f: Node = game_state_script.new()
	var gate_end: Resource = load("res://data/dialogue/gate_end.tres")
	var finished_id: Array[StringName] = []
	var runner_f: RefCounted = runner_script.new(state_f)
	runner_f.conversation_finished.connect(func(id: StringName) -> void: finished_id.append(id))
	runner_f.start(gate_end)
	_drain(runner_f, failures)
	if finished_id.size() != 1 or finished_id[0] != &"gate_end":
		failures.append("conversation_finished not emitted with gate_end")
	if state_f.get_flag(&"observed.reached_gate") != true:
		failures.append("gate_end did not set observed.reached_gate")
	state_f.free()

	# ---------- invalid conversation is rejected, not faked ----------
	var broken: Resource = conversation_script.new()
	broken.id = &"broken_test"
	broken.start_id = &"missing_entry"
	var broken_entry: DialogueEntry = entry_script.new()
	broken_entry.id = &"orphan"
	broken_entry.speaker_id = &"narrator"
	broken_entry.text = "This is a broken test fixture."
	broken_entry.next_id = &"nowhere"
	var broken_entries: Array[DialogueEntry] = [broken_entry]
	broken.entries = broken_entries
	var state_x: Node = game_state_script.new()
	var runner_x: RefCounted = runner_script.new(state_x)
	if runner_x.start(broken):
		failures.append("invalid conversation started successfully; expected rejection")
	state_x.free()

	if not failures.is_empty():
		for failure in failures:
			push_error("dialogue_runner_test failed: %s" % failure)
		quit(1)
		return
	print("dialogue_runner_test passed")
	quit(0)


func _advance_times(runner: RefCounted, times: int) -> void:
	for i in range(times):
		runner.advance()


func _drain(runner: RefCounted, failures: Array[String]) -> void:
	var guard: int = 0
	while not runner.is_finished() and guard < 64:
		guard += 1
		if not runner.current_entry.choices.is_empty():
			failures.append("conversation '%s' expected a choice at '%s'; test does not pick one" % [runner.conversation.id, runner.current_entry.id])
			return
		runner.advance()
	if guard >= 64:
		failures.append("conversation did not finish within 64 advances")


func _find_choice(choices: Array, text: String) -> Resource:
	for choice in choices:
		if String(choice.text) == text:
			return choice
	return null
