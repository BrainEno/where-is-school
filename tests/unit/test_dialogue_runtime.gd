extends TestCaseHelper
## Dialogue runtime behaviour: branching, non-convergent replies, conditions, and
## the error paths that stop bad content from half-playing.


func _run() -> void:
	_test_straight_line()
	_test_branching_replies_differ()
	_test_choice_effects_are_emitted()
	_test_conditional_choices()
	_test_invalid_script_is_refused()
	_test_imagined_node_flag()


func _test_straight_line() -> void:
	var script := DialogueScript.create(&"t_linear")
	script.add(
		DialogueNode.create(&"a")
		.with_speaker_line(&"q", "First.")
		.with_next(&"b")
	)
	script.add(
		DialogueNode.create(&"b")
		.with_speaker_line(&"q", "Second.")
	)
	script.start_id = &"a"
	check_empty(script.validate(), "a linear script validates")

	var built: Dictionary = make_session(script)
	var session: DialogueSession = built["session"]
	var log: Dictionary = built["log"]
	check_eq(log["lines"].size(), 1, "one line presented on start")
	session.advance()
	check_eq(log["lines"].size(), 2, "advance moves to the next node")
	check_eq(log["lines"][1].text, "Second.", "the second node's line was presented")
	session.advance()
	check_true(session.is_finished(), "advance past the last node finishes the session")
	check_eq(log["finished"].size(), 1, "session_finished fired once")


func _test_branching_replies_differ() -> void:
	var script := DialogueScript.create(&"t_branch")
	var pushback := DialogueChoice.make(&"push", "“I don't remember you.”", &"b_push")
	pushback.with_reply(DialogueLine.create(&"protagonist", "I don't remember you."))
	var agree := DialogueChoice.make(&"agree", "“Morning.”", &"b_agree")
	agree.with_reply(DialogueLine.create(&"protagonist", "Morning."))
	script.add(
		DialogueNode.create(&"a")
		.with_aside("He is already talking.")
		.with_choice(pushback)
		.with_choice(agree)
	)
	script.add(DialogueNode.create(&"b_push").with_speaker_line(&"q", "That's a joke, right?"))
	script.add(DialogueNode.create(&"b_agree").with_speaker_line(&"q", "Morning. Right. Good morning."))
	script.start_id = &"a"
	check_empty(script.validate(), "the branching script validates")

	var first: Dictionary = make_session(script)
	var s1: DialogueSession = first["session"]
	s1.advance()
	var log1: Dictionary = first["log"]
	check_eq(log1["choices"].size(), 1, "choices are presented once")
	check_eq((log1["choices"][0] as Array).size(), 2, "both replies are offered")
	s1.choose_by_id(&"push")
	check_eq(log1["lines"].size(), 3, "the reply line is presented before the next node")
	check_eq(log1["lines"][1].text, "I don't remember you.", "the chosen reply was spoken")

	var second: Dictionary = make_session(script)
	var s2: DialogueSession = second["session"]
	s2.advance()
	s2.choose_by_id(&"agree")
	var log2: Dictionary = second["log"]
	check_ne(
		(log2["lines"] as Array)[-1].text,
		(log1["lines"] as Array)[-1].text,
		"different replies reach different output"
	)
	check_contains_text((log2["lines"] as Array)[-1].text, "Good morning", "warm reply has its own text")


func _test_choice_effects_are_emitted() -> void:
	var script := DialogueScript.create(&"t_effects")
	var choice := DialogueChoice.make(&"admit", "“I left it blank.”", &"end")
	choice.with_flag(&"test.flag", true)
	choice.with_record(&"test.record")
	script.add(DialogueNode.create(&"a").with_aside("He waits for an answer.").with_choice(choice))
	script.add(DialogueNode.create(&"end").with_speaker_line(&"q", "Mm."))
	script.start_id = &"a"

	var built: Dictionary = make_session(script)
	var session: DialogueSession = built["session"]
	var log: Dictionary = built["log"]
	session.advance()
	session.choose_by_id(&"admit")
	check_eq(log["flags"].size(), 1, "the choice emitted one flag batch")
	check_eq(log["flags"][0].get(&"test.flag"), true, "the flag carries the authored value")
	check_eq(log["records"].size(), 1, "the choice emitted one record batch")
	check_has(log["records"][0], &"test.record", "the record id was emitted")


func _test_conditional_choices() -> void:
	var game_state: Node = make_tree().root.get_node_or_null("GameState")
	if game_state == null:
		check(false, "GameState autoload is present")
		return
	game_state.clear()
	game_state.set_flag(&"test.gate", true)

	var script := DialogueScript.create(&"t_conditional")
	var gated := DialogueChoice.make(&"gated", "“I know about the cupboard.”", &"end")
	gated.with_requirement(&"test.gate", true)
	script.add(
		DialogueNode.create(&"a")
		.with_speaker_line(&"q", "Anything else?")
		.with_choice(DialogueChoice.make(&"plain", "“No.”", &"end"))
		.with_choice(gated)
	)
	script.add(DialogueNode.create(&"end").with_speaker_line(&"q", "Right."))
	script.start_id = &"a"

	var built: Dictionary = make_session(script)
	var session: DialogueSession = built["session"]
	var log: Dictionary = built["log"]
	session.advance()
	check_eq((log["choices"][0] as Array).size(), 2, "gated choice appears when the flag is set")

	game_state.set_flag(&"test.gate", false)
	var built2: Dictionary = make_session(script)
	var session2: DialogueSession = built2["session"]
	var log2: Dictionary = built2["log"]
	session2.advance()
	check_eq((log2["choices"][0] as Array).size(), 1, "gated choice is hidden when the flag is unset")
	game_state.clear()


func _test_invalid_script_is_refused() -> void:
	var script := DialogueScript.create(&"t_broken")
	script.add(
		DialogueNode.create(&"a")
		.with_speaker_line(&"q", "Go on then.")
		.with_next(&"missing_node")
	)
	script.start_id = &"a"
	check_ne(script.validate().size(), 0, "a dangling jump is reported")

	var session := DialogueSession.new()
	var started: bool = session.start(script)
	check_false(started, "invalid content refuses to start instead of half-playing")


func _test_imagined_node_flag() -> void:
	var script := DialogueScript.create(&"t_imagined")
	script.add(
		DialogueNode.create(&"a")
		.with_imagined()
		.with_imagined_by(&"b", "Textbook out.")
	)
	script.start_id = &"a"
	var built: Dictionary = make_session(script)
	var session: DialogueSession = built["session"]
	check_true(session.is_imagining(), "the session reports it is inside a rehearsal")
	check_true(session.current_line_is_imagined(), "the current line is marked imagined")
	var log: Dictionary = built["log"]
	check_true((log["lines"][0] as DialogueLine).imagined, "the line itself is flagged imagined")
	check_eq((log["lines"][0] as DialogueLine).note, "imagined", "the line carries a visual note")
