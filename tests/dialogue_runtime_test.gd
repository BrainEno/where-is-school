extends SceneTree
## Unit tests for the dialogue runtime: graph walking, choices, `once` behaviour,
## and the hard boundary between imagined content and story state.
##
## Fixtures are written to user:// at test time instead of being committed, so no
## narrative text lives in the test folder.

const Harness = preload("res://tests/test_harness.gd")
const FIXTURE_PATH := "user://dialogue_runtime_fixture.json"

const FIXTURE := {
	"format_version": 1,
	"conversations": {
		"fixture_subjective": {
			"default_source": "imagined",
			"subjective": true,
			"start": "s1",
			"nodes": [
				{
					"id": "s1",
					"speaker": "b",
					"text": "Fixture line inside an imagined conversation.",
					"effects": [
						{"type": "set_flag", "flag": "fixture_forbidden_flag", "value": true},
						{"type": "set_objective", "text": "Fixture forbidden objective"},
						{"type": "record", "entry_id": "fixture_observed",
						 "source": "observed", "speaker": "b", "text": "Fixture observed claim."},
						{"type": "record", "entry_id": "fixture_reported",
						 "source": "reported", "speaker": "b", "text": "Fixture reported claim."},
						{"type": "record", "entry_id": "fixture_recalled",
						 "source": "recalled", "speaker": "protagonist", "text": "Fixture memory."},
						{"type": "record", "entry_id": "fixture_imagined",
						 "source": "imagined", "speaker": "b", "text": "Fixture imagined line."}
					]
				}
			]
		},
		"fixture_once": {
			"default_source": "observed",
			"start": "o1",
			"nodes": [
				{
					"id": "o1",
					"speaker": "q",
					"text": "Fixture choice hub.",
					"choices": [
						{"id": "a", "text": "Fixture A", "next": "o2", "once": true},
						{"id": "b", "text": "Fixture B", "next": "o3"}
					]
				},
				{"id": "o2", "speaker": "q", "text": "Fixture repeat.", "next": "o1"},
				{"id": "o3", "speaker": "q", "text": "Fixture end."}
			]
		}
	}
}

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "dialogue_runtime_test.gd")
	call_deferred("_run")


func _run() -> void:
	var game_state: Node = load(Harness.GAME_STATE_SCRIPT).new()
	var narrative: Node = load(Harness.NARRATIVE_STATE_SCRIPT).new()
	var characters := CharacterDirectory.load_all()
	if not characters.errors.is_empty():
		_failures.append("\n".join(characters.errors))

	_test_opening_conversation(game_state, narrative, characters)
	_test_subjective_boundaries(game_state, narrative, characters)
	_test_once_choice(game_state, narrative, characters)

	game_state.free()
	narrative.free()
	Harness.finish(self, _failures, "dialogue runtime walks graphs and enforces source boundaries.")


func _new_runtime(game_state: Node, narrative: Node, characters: CharacterDirectory) -> DialogueRuntime:
	return DialogueRuntime.new(game_state, narrative, characters)


func _test_opening_conversation(
	game_state: Node, narrative: Node, characters: CharacterDirectory
) -> void:
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		return
	var runtime := _new_runtime(game_state, narrative, characters)

	# Dictionaries are shared by reference, so counts survive the lambda capture.
	var counters := {"lines": 0, "choices": 0}
	runtime.line_changed.connect(
		func(_line: Dictionary) -> void: counters["lines"] = int(counters["lines"]) + 1
	)
	runtime.choices_changed.connect(
		func(choices: Array) -> void: counters["choices"] = int(counters["choices"]) + choices.size()
	)

	if not runtime.start(library.get_graph(&"q_wake"), &"q_wake"):
		_failures.append("The opening conversation would not start.")
		return

	var steps := 0
	while runtime.is_active() and steps < 200:
		if runtime.is_awaiting_choice():
			if not runtime.choose(0):
				_failures.append("Choosing option 0 failed on node %s." % runtime.get_current_node_id())
				break
		else:
			runtime.advance()
		steps += 1

	if runtime.is_active():
		_failures.append("The opening conversation did not finish within 200 steps.")
	if int(counters["lines"]) < 10:
		_failures.append(
			"The opening conversation only produced %d lines." % int(counters["lines"])
		)
	if int(counters["choices"]) < 3:
		_failures.append(
			"The opening conversation only offered %d choice options." % int(counters["choices"])
		)

	if not bool(game_state.get_flag(StoryFlags.MET_Q, false)):
		_failures.append("The opening conversation did not set the met_q flag.")
	if not bool(game_state.get_flag(StoryFlags.ASKED_Q_IDENTITY, false)):
		_failures.append("Choosing the first option did not set its story flag.")
	if bool(game_state.get_flag(StoryFlags.STAYED_SILENT, false)):
		_failures.append("An unchosen branch set its flag anyway.")
	if String(game_state.get_flag(StoryFlags.OBJECTIVE_TEXT, "")) != \
			"Find your biology textbook. Check your bag.":
		_failures.append("The conversation did not set the bag objective.")

	var exam_claim: NarrativeEntry = narrative.get_entry(&"q_claims_blank_exam")
	if exam_claim == null:
		_failures.append("Q's exam claim was not recorded.")
	elif exam_claim.source != NarrativeEntry.Source.REPORTED:
		_failures.append("Q's claim was not recorded as reported knowledge.")


func _test_subjective_boundaries(
	game_state: Node, narrative: Node, characters: CharacterDirectory
) -> void:
	_write_fixture()
	var graph := DialogueGraph.load_from_file(FIXTURE_PATH)
	if not graph.is_valid():
		_failures.append(graph.describe_errors())
		return

	var objective_before := String(game_state.get_flag(StoryFlags.OBJECTIVE_TEXT, ""))
	var runtime := _new_runtime(game_state, narrative, characters)
	var rejections: Array[String] = []
	runtime.effect_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	var flags := {"subjective_seen": false}
	runtime.line_changed.connect(
		func(line: Dictionary) -> void:
			if bool(line.get("subjective", false)):
				flags["subjective_seen"] = true
	)

	if not runtime.start(graph, &"fixture_subjective"):
		_failures.append("The subjective fixture conversation would not start.")
		return
	while runtime.is_active():
		runtime.advance()

	if not bool(flags["subjective_seen"]):
		_failures.append("Subjective lines were not flagged as subjective.")
	if bool(game_state.get_flag(&"fixture_forbidden_flag", false)):
		_failures.append("A subjective conversation changed a story flag.")
	if String(game_state.get_flag(StoryFlags.OBJECTIVE_TEXT, "")) != objective_before:
		_failures.append("A subjective conversation changed the objective.")
	if narrative.has_entry(&"fixture_observed"):
		_failures.append("A subjective conversation recorded observed knowledge.")
	if narrative.has_entry(&"fixture_reported"):
		_failures.append("A subjective conversation recorded reported knowledge.")
	if not narrative.has_entry(&"fixture_recalled"):
		_failures.append("A subjective conversation could not record a memory.")
	if not narrative.has_entry(&"fixture_imagined"):
		_failures.append("A subjective conversation could not record imagined content.")
	if rejections.size() != 4:
		_failures.append(
			"Expected 4 rejected subjective effects, got %d." % rejections.size()
		)


func _test_once_choice(
	game_state: Node, narrative: Node, characters: CharacterDirectory
) -> void:
	var graph := DialogueGraph.load_from_file(FIXTURE_PATH)
	if not graph.is_valid():
		_failures.append(graph.describe_errors())
		return
	var runtime := _new_runtime(game_state, narrative, characters)
	if not runtime.start(graph, &"fixture_once"):
		_failures.append("The once-choice fixture would not start.")
		return

	var first_choices := runtime.get_current_choices()
	if first_choices.size() != 2:
		_failures.append("Expected two choices on the first visit, got %d." % first_choices.size())
	runtime.choose(0)
	runtime.advance()
	var second_choices := runtime.get_current_choices()
	if second_choices.size() != 1:
		_failures.append(
			"An 'once' choice should disappear on the second visit, got %d options."
			% second_choices.size()
		)
	if not bool(game_state.get_flag(StoryFlags.choice_flag(&"fixture_once", &"a"), false)):
		_failures.append("Taking a 'once' choice did not record that it was taken.")
	var guard := 0
	while runtime.is_active() and guard < 20:
		if runtime.is_awaiting_choice():
			runtime.choose(0)
		else:
			runtime.advance()
		guard += 1
	if runtime.is_active():
		_failures.append("The once-choice fixture conversation did not finish.")


func _write_fixture() -> void:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write the dialogue fixture to %s." % FIXTURE_PATH)
		return
	file.store_string(JSON.stringify(FIXTURE, "  "))
	file.close()
