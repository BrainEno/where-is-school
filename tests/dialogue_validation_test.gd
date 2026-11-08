extends SceneTree
## Proves the dialogue validator actually rejects broken content, and that it says
## where the break is (file + conversation + node id).
##
## Each fixture below is the smallest file that trips one rule. They are written to
## user:// at run time, so the repository never carries deliberately broken content
## that a careless `load_all()` could pick up.

const Harness = preload("res://tests/test_harness.gd")
const BASE_DIR := "user://validation"

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "dialogue_validation_test.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))

	_expect_error("duplicate ids", _duplicate_node_ids(), ["dup", "a1"])
	_expect_error("dangling next", _dangling_next(), ["dangle", "a1", "nowhere"])
	_expect_error("unreachable node", _unreachable_node(), ["lost", "orphan"])
	_expect_error("last node does not end", _unterminated_last_node(), ["open_end", "a2"])
	_expect_error("incomplete choice", _choice_without_next(), ["bad_choice", "b1", "c1"])
	_expect_error("subjective flags", _subjective_flag(), ["imagined", "subjective"])
	_expect_error("literal objective", _literal_objective(), ["objective_text", "text"])
	_expect_error("unknown effect", _unknown_effect(), ["bad_effect", "x1"])
	_expect_error("wrong locale", _wrong_locale(), ["de-DE"])
	# Issue #20: a line parked after a choice hub or a check was treated as reachable
	# because the walk added a sequence edge the runtime never takes. Both must fail.
	_expect_error("orphan after a choice hub", _orphan_after_choice(), ["orphan_after_choice", "orphan"])
	_expect_error("orphan after a check", _orphan_after_check(), ["orphan_after_check", "orphan"])

	# ... and the fix must not turn valid hubs, checks or ordinary chains into errors.
	_expect_valid("a choice hub with ending branches", _valid_choice_hub())
	_expect_valid("a check with two ending branches", _valid_check_branches())
	_expect_valid("an ordinary next chain", _valid_sequence())
	_expect_valid("a choice hub whose branches share a node", _valid_shared_hub())

	_check_locale_parity()
	_check_real_content()

	Harness.finish(self, _failures, "the dialogue validator rejects every broken fixture.")


# --- fixtures ---------------------------------------------------------------


func _graph(conversation_id: String, nodes: Array, extra: Dictionary = {}) -> Dictionary:
	var conversation := {"default_source": "observed", "start": nodes[0]["id"], "nodes": nodes}
	conversation.merge(extra, true)
	return {
		"format_version": 2,
		"locale": "en",
		"chapter": "fixture",
		"conversations": {conversation_id: conversation},
	}


func _duplicate_node_ids() -> Dictionary:
	return _graph("dup", [
		{"id": "a1", "speaker": "q", "text": "Fixture one.", "next": "a2"},
		{"id": "a1", "speaker": "q", "text": "Fixture two.", "next": null},
	])


func _dangling_next() -> Dictionary:
	return _graph("dangle", [
		{"id": "a1", "speaker": "q", "text": "Fixture.", "next": "nowhere"},
	])


func _unreachable_node() -> Dictionary:
	return _graph("lost", [
		{"id": "a1", "speaker": "q", "text": "Fixture.", "next": null},
		{"id": "orphan", "speaker": "q", "text": "Fixture unreachable.", "next": null},
	])


func _unterminated_last_node() -> Dictionary:
	return _graph("open_end", [
		{"id": "a1", "speaker": "q", "text": "Fixture.", "next": "a2"},
		{"id": "a2", "speaker": "q", "text": "Fixture has no exit."},
	])


func _choice_without_next() -> Dictionary:
	return _graph("bad_choice", [
		{"id": "b1", "speaker": "q", "text": "Fixture hub.",
		 "choices": [{"id": "c1", "text": "Fixture choice."}]},
	])


func _subjective_flag() -> Dictionary:
	return _graph("imagined", [
		{"id": "s1", "speaker": "b", "text": "Fixture imagined line.",
		 "effects": [{"type": "set_flag", "flag": "fixture_flag", "value": true}], "next": null},
	], {"subjective": true, "default_source": "imagined"})


func _literal_objective() -> Dictionary:
	return _graph("objective_text", [
		{"id": "t1", "speaker": "q", "text": "Fixture line.",
		 "effects": [{"type": "set_objective", "text": "Fixture literal objective"}], "next": null},
	])


func _unknown_effect() -> Dictionary:
	return _graph("bad_effect", [
		{"id": "x1", "speaker": "q", "text": "Fixture line.",
		 "effects": [{"type": "teleport_player"}], "next": null},
	])


## The fixture from issue #20: the hub's only option goes straight to the end, so the
## node between them can never be shown. The old walk counted it as reachable.
func _orphan_after_choice() -> Dictionary:
	return _graph("orphan_after_choice", [
		{"id": "hub", "speaker": "q", "text": "Fixture hub.",
		 "choices": [{"id": "c1", "text": "Fixture choice.", "next": "end"}]},
		{"id": "orphan", "speaker": "q", "text": "Fixture orphan.", "next": null},
		{"id": "end", "speaker": "q", "text": "Fixture end.", "next": null},
	])


## Same shape after a roll: `success`/`failure` are the only ways on.
func _orphan_after_check() -> Dictionary:
	return _graph("orphan_after_check", [
		{"id": "roll", "speaker": "q", "text": "Fixture roll.",
		 "check": {"ability": "orientation", "difficulty": 8, "kind": "hidden",
				   "success": "ok", "failure": "bad"}},
		{"id": "orphan", "speaker": "q", "text": "Fixture orphan.", "next": null},
		{"id": "ok", "speaker": "q", "text": "Fixture ok.", "next": null},
		{"id": "bad", "speaker": "q", "text": "Fixture bad.", "next": null},
	])


func _valid_choice_hub() -> Dictionary:
	return _graph("valid_choice_hub", [
		{"id": "h1", "speaker": "q", "text": "Fixture hub.",
		 "choices": [
			{"id": "a", "text": "Fixture A", "next": "h2"},
			{"id": "b", "text": "Fixture B", "next": "h3"},
		 ]},
		{"id": "h2", "speaker": "q", "text": "Fixture A end.", "next": null},
		{"id": "h3", "speaker": "q", "text": "Fixture B end.", "next": null},
	])


func _valid_shared_hub() -> Dictionary:
	return _graph("valid_shared_hub", [
		{"id": "s1", "speaker": "q", "text": "Fixture hub.",
		 "choices": [
			{"id": "a", "text": "Fixture A", "next": "s2"},
			{"id": "b", "text": "Fixture B", "next": "s2"},
		 ]},
		{"id": "s2", "speaker": "q", "text": "Fixture shared end.", "next": null},
	])


func _valid_check_branches() -> Dictionary:
	return _graph("valid_check_branches", [
		{"id": "k1", "speaker": "q", "text": "Fixture roll.",
		 "check": {"ability": "orientation", "difficulty": 8, "kind": "visible",
				   "success": "k2", "failure": "k3"}},
		{"id": "k2", "speaker": "q", "text": "Fixture success.", "next": null},
		{"id": "k3", "speaker": "q", "text": "Fixture failure.", "next": null},
	])


func _valid_sequence() -> Dictionary:
	return _graph("valid_sequence", [
		{"id": "n1", "speaker": "q", "text": "Fixture one.", "next": "n2"},
		{"id": "n2", "speaker": "q", "text": "Fixture two.", "next": "n3"},
		{"id": "n3", "speaker": "q", "text": "Fixture three.", "next": null},
	])


func _wrong_locale() -> Dictionary:
	var data := _graph("locale", [
		{"id": "l1", "speaker": "q", "text": "Fixture line.", "next": null},
	])
	data["locale"] = "de-DE"
	return data


# --- checks -----------------------------------------------------------------


func _write(name: String, data: Dictionary) -> String:
	var path := "%s/%s.json" % [BASE_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write fixture %s." % path)
		return ""
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return path


## Loads the fixture through the real parser and requires an error that names the
## file and every fragment of the location the rule is about.
func _expect_error(label: String, data: Dictionary, fragments: Array) -> void:
	var path := _write(label.replace(" ", "_"), data)
	if path.is_empty():
		return
	var graph := DialogueGraph.load_from_file(path)
	if graph.errors.is_empty():
		_failures.append("The validator accepted broken content (%s)." % label)
		return
	var joined := "\n".join(graph.errors)
	for fragment: String in fragments:
		if not joined.contains(fragment):
			_failures.append(
				"The %s error does not mention '%s': %s" % [label, fragment, joined]
			)


## The mirror of `_expect_error`: content that plays must load clean. Without this the
## reachability fix could "pass" by rejecting everything.
func _expect_valid(label: String, data: Dictionary) -> void:
	var path := _write("valid_" + label.replace(" ", "_"), data)
	if path.is_empty():
		return
	var graph := DialogueGraph.load_from_file(path)
	if graph.is_valid():
		return
	_failures.append(
		"The validator rejected valid content (%s): %s" % [label, " | ".join(graph.errors)]
	)


## A translation that drops a node must be reported with the node id, otherwise a
## translator gets a silent hole in the story.
func _check_locale_parity() -> void:
	var reference := DialogueGraph.new()
	reference.source_path = "reference.json"
	reference.locale = "en"
	reference.chapter = "fixture"
	var conversation := DialogueGraph.Conversation.new()
	conversation.conversation_id = &"parity"
	conversation.start_id = &"p1"
	for node_id: StringName in [&"p1", &"p2"]:
		var node := DialogueGraph.DialogueNode.new()
		node.node_id = node_id
		node.speaker_id = &"q"
		node.text = "Fixture %s." % node_id
		conversation.nodes[node_id] = node
		conversation.order.append(node_id)
	reference.conversations[&"parity"] = conversation

	var other := DialogueGraph.new()
	other.source_path = "translation.json"
	other.locale = "zh-CN"
	other.chapter = "fixture"
	var translated := DialogueGraph.Conversation.new()
	translated.conversation_id = &"parity"
	translated.start_id = &"p1"
	var first := DialogueGraph.DialogueNode.new()
	first.node_id = &"p1"
	first.speaker_id = &"q"
	first.text = "Fixture translated."
	translated.nodes[&"p1"] = first
	translated.order.append(&"p1")
	other.conversations[&"parity"] = translated

	var problems := DialogueParity.compare(reference, other)
	if problems.is_empty():
		_failures.append("A translation that drops a node passed the parity check.")
		return
	var joined := "\n".join(problems)
	if not joined.contains("p2"):
		_failures.append("The parity error does not name the dropped node: %s" % joined)


## The content that ships must be valid in both languages.
func _check_real_content() -> void:
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		for message: String in library.errors:
			print("DIAG dialogue: %s" % message)
		return
	var english := library.get_graphs_for("en")
	var chinese := library.get_graphs_for("zh-CN")
	if english.size() != chinese.size():
		_failures.append("The two languages do not have the same chapters.")
	for graph: DialogueGraph in english:
		var translated: DialogueGraph = null
		for candidate: DialogueGraph in chinese:
			if candidate.chapter == graph.chapter:
				translated = candidate
		if translated == null:
			_failures.append("Chapter '%s' has no translation." % graph.chapter)
			continue
		var problems := DialogueParity.compare(graph, translated)
		for problem: String in problems:
			_failures.append(problem)
	var inspections := InspectionLibrary.load_all()
	if not inspections.is_valid():
		_failures.append(inspections.describe_errors())
		for message: String in inspections.errors:
			print("DIAG inspection: %s" % message)
	else:
		# The library compares the two languages per chapter while loading; this
		# only re-checks that the merged id sets are identical.
		if inspections.get_ids_for("en") != inspections.get_ids_for("zh-CN"):
			_failures.append("The inspection ids differ between languages.")
