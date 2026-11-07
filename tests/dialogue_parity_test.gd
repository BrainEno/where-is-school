extends SceneTree
## Proves that a translation cannot change the *shape* of a conversation.
##
## The parity checker is the only thing standing between "translated the text" and
## "quietly opened a branch, closed a gate, or reordered a node". Every case below
## writes two small content files to user:// — one English, one "translated" — and
## asserts what the real checker reports. Fixtures live outside the repository so a
## careless content load can never pick them up.

const Harness = preload("res://tests/test_harness.gd")
const BASE_DIR := "user://parity"

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "dialogue_parity_test.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))

	_expect_clean("identical choice gates", {}, {}, {}, {})
	_expect_clean(
		"the same flags written in another order",
		{},
		{"all_flags": ["met_q", "textbook_missing"]},
		{},
		{"all_flags": ["textbook_missing", "met_q"]}
	)
	_expect_problem(
		"a choice that requires a different flag value",
		{}, {"requires": {"textbook_missing": true}},
		{}, {"requires": {"textbook_missing": false}},
		["allow", "requires"]
	)
	_expect_problem(
		"a choice gated on an extra flag",
		{}, {"all_flags": ["met_q"]},
		{}, {"all_flags": ["met_q", "textbook_missing"]},
		["allow", "all_flags"]
	)
	_expect_problem(
		"a choice that lost a blocking flag",
		{}, {"not_flags": ["left_school"]},
		{}, {},
		["allow", "not_flags"]
	)
	_expect_problem(
		"a node gated on a different flag",
		{"not_flags": ["met_q"]}, {},
		{"not_flags": []}, {},
		["start", "not_flags"]
	)

	_check_shipped_content()
	Harness.finish(self, _failures, "the parity checker compares node and choice gates.")


# --- fixtures ---------------------------------------------------------------


## One node with one choice. `node_overrides` are merged into the node, `choice`
## is the condition block of its single choice.
func _fixture(node_overrides: Dictionary, choice: Dictionary) -> Dictionary:
	var node := {
		"id": "start",
		"speaker": "q",
		"text": "A line.",
		"choices": [_choice(choice)],
	}
	node.merge(node_overrides, true)
	return {
		"format_version": 2,
		"locale": "en",
		"chapter": "parity",
		"conversations": {
			"c": {
				"default_source": "observed",
				"start": "start",
				"nodes": [node, {"id": "done", "speaker": "q", "text": "Done.", "next": null}],
			}
		},
	}


func _choice(conditions: Dictionary) -> Dictionary:
	var choice := {"id": "allow", "text": "Allow me.", "next": "done"}
	if not conditions.is_empty():
		choice["conditions"] = conditions
	return choice


func _write(name: String, data: Dictionary, locale: String) -> String:
	var path := "%s/%s_%s.json" % [BASE_DIR, name, locale]
	data["locale"] = locale
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write fixture %s." % path)
		return ""
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return path


func _load_pair(
	name: String, reference: Dictionary, translation: Dictionary
) -> Array[DialogueGraph]:
	var reference_path := _write(name, reference, "en")
	var other_path := _write(name, translation, "zh-CN")
	if reference_path.is_empty() or other_path.is_empty():
		return []
	var reference_graph := DialogueGraph.load_from_file(reference_path)
	var other_graph := DialogueGraph.load_from_file(other_path)
	# Both fixtures must parse, otherwise a "clean" result would only prove that
	# two broken files were compared.
	for graph: DialogueGraph in [reference_graph, other_graph]:
		if not graph.is_valid():
			_failures.append("A parity fixture is not valid content: %s" % graph.describe_errors())
			return []
	return [reference_graph, other_graph]


func _expect_clean(
	label: String,
	reference_node: Dictionary,
	reference_choice: Dictionary,
	other_node: Dictionary,
	other_choice: Dictionary
) -> void:
	var pair := _load_pair(
		label.replace(" ", "_"),
		_fixture(reference_node, reference_choice),
		_fixture(other_node, other_choice)
	)
	if pair.is_empty():
		return
	for problem: String in DialogueParity.compare(pair[0], pair[1]):
		_failures.append("Case '%s' was reported as different: %s" % [label, problem])


func _expect_problem(
	label: String,
	reference_node: Dictionary,
	reference_choice: Dictionary,
	other_node: Dictionary,
	other_choice: Dictionary,
	fragments: Array
) -> void:
	var pair := _load_pair(
		label.replace(" ", "_").replace(",", ""),
		_fixture(reference_node, reference_choice),
		_fixture(other_node, other_choice)
	)
	if pair.is_empty():
		return
	var problems := DialogueParity.compare(pair[0], pair[1])
	if problems.is_empty():
		_failures.append("The parity checker accepted '%s'." % label)
		return
	var joined := "\n".join(problems)
	for fragment: String in fragments:
		if not joined.contains(fragment):
			_failures.append(
				"The '%s' report does not mention '%s': %s" % [label, fragment, joined]
			)


# --- shipped content --------------------------------------------------------


## The real content must pass the same check, so a broken translation is caught in
## the PR that introduces it rather than the first time someone reads it.
func _check_shipped_content() -> void:
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		return
	var english := library.get_graphs_for("en")
	var chinese := library.get_graphs_for("zh-CN")
	for graph: DialogueGraph in english:
		for candidate: DialogueGraph in chinese:
			if candidate.chapter != graph.chapter:
				continue
			for problem: String in DialogueParity.compare(graph, candidate):
				_failures.append(problem)
