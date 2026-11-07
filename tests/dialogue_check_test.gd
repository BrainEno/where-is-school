extends SceneTree
## Proves that dice live inside the dialogue system and nowhere else.
##
## What this covers:
##
## - **Parsing.** A check block is read into the node, and malformed ones are
##   rejected instead of silently behaving like a plain line. Content errors are
##   cheaper to find here than in a playtest.
## - **Resolution.** A check node rolls once, continues to `success` or `failure`,
##   and reports the whole result (die, total, difficulty, kind) as data.
## - **Visible vs hidden.** Both use the same core; the only difference the runtime
##   reports is `kind`, which is what the panel keys off.
## - **No rerolling.** Re-entering the same check replays the recorded outcome,
##   even with a different seed, and marks it `reused`.
## - **Failure is not a wall.** The failure branch is an ordinary node: after it,
##   the conversation continues and the rest of the game is untouched.

const Harness = preload("res://tests/test_harness.gd")
const BASE_DIR := "user://checks"

var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null
var _abilities: InnerAbilities = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "dialogue_check_test.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null:
		Harness.finish(self, ["GameState is unavailable."], "")
		return
	Harness.clear_session_state(self)
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		Harness.finish(self, ["abilities: " + _abilities.describe_errors()], "")
		return

	_check_parsing()
	_check_rejections()
	_check_resolution()
	_check_visible_and_hidden()
	_check_no_reroll()
	_check_failure_branch_is_not_a_wall()
	_check_conditions_with_dictionary_flags()
	Harness.finish(self, _failures, "checks parse strictly and resolve through one shared core.")


# --- fixtures ---------------------------------------------------------------


func _check_block(overrides: Dictionary = {}) -> Dictionary:
	var block := {
		"ability": "orientation",
		"difficulty": 11,
		"kind": "visible",
		"success": "good",
		"failure": "bad",
	}
	block.merge(overrides, true)
	return block


func _content(check_overrides: Dictionary = {}) -> Dictionary:
	return {
		"format_version": 2,
		"locale": "en",
		"chapter": "checks",
		"conversations": {
			"trial": {
				"default_source": "observed",
				"start": "roll",
				"nodes": [
					{
						"id": "roll",
						"speaker": "protagonist",
						"text": "You try it.",
						"check": _check_block(check_overrides),
					},
					{"id": "good", "speaker": "protagonist", "text": "It works.", "next": null},
					{"id": "bad", "speaker": "protagonist", "text": "It does not.", "next": null},
				],
			}
		},
	}


func _write(name: String, data: Dictionary) -> String:
	var path := "%s/%s.json" % [BASE_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write fixture %s." % path)
		return ""
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return path


func _load(name: String, data: Dictionary) -> DialogueGraph:
	var path := _write(name, data)
	if path.is_empty():
		return null
	return DialogueGraph.load_from_file(path)


func _new_runtime(graph: DialogueGraph, seed_value: int) -> DialogueRuntime:
	var resolver := CheckResolver.new(seed_value)
	var runtime := DialogueRuntime.new(_game_state, _narrative, null, _abilities, resolver)
	runtime.start(graph, &"trial")
	return runtime


## Regression: a recorded check puts a Dictionary in a flag, and the choice filter
## that stops an attempt being offered twice is exactly a `not_flags` entry on that
## flag. Converting such a flag with bool() crashed: GDScript cannot construct a
## bool from a Dictionary.
func _check_conditions_with_dictionary_flags() -> void:
	Harness.clear_session_state(self)
	var data := {
		"format_version": 2,
		"locale": "en",
		"chapter": "checks",
		"conversations": {
			"gate": {
				"default_source": "observed",
				"start": "offer",
				"nodes": [
					{
						"id": "offer",
						"speaker": "protagonist",
						"text": "Which way.",
						"choices": [
							{
								"id": "try",
								"text": "Try it.",
								"next": "try_roll",
								"conditions": {"not_flags": ["check:gate:try_roll"]},
							},
							{"id": "walk", "text": "Walk on.", "next": "walked"},
						],
					},
					{
						"id": "try_roll",
						"speaker": "protagonist",
						"text": "You try.",
						"check": _check_block({"difficulty": 5}),
					},
					{"id": "good", "speaker": "protagonist", "text": "It opens.", "next": null},
					{"id": "bad", "speaker": "protagonist", "text": "It holds.", "next": null},
					{"id": "walked", "speaker": "protagonist", "text": "You walk on.", "next": null},
				],
			}
		},
	}
	var graph := _load("dict_flags", data)
	if graph == null:
		return
	# A record-shaped flag value, exactly the shape the runtime writes.
	_game_state.set_flag(
		StoryFlags.check_record_flag(&"gate", &"try_roll"),
		{"success": false, "die": 2, "total": 6, "difficulty": 5}
	)
	var runtime := DialogueRuntime.new(_game_state, _narrative, null, _abilities, CheckResolver.new(1))
	runtime.start(graph, &"gate")
	var ids := runtime.get_available_choice_ids()
	if ids.has(&"try"):
		_failures.append("A choice gated on a recorded check result was still offered.")
	if not ids.has(&"walk"):
		_failures.append("Filtering one choice removed the others.")


# --- cases ------------------------------------------------------------------


func _check_parsing() -> void:
	var graph := _load("parsing", _content({
		"modifiers": [{"flag": "met_q", "value": 2}],
		"repeatable": true,
	}))
	if graph == null:
		return
	if not graph.is_valid():
		_failures.append("A valid check fixture was rejected: %s" % graph.describe_errors())
		return
	var node: DialogueGraph.DialogueNode = graph.get_conversation(&"trial").nodes[&"roll"]
	if node.check.is_empty():
		_failures.append("The check block did not survive parsing.")
		return
	if String(node.check["ability"]) != "orientation":
		_failures.append("The check lost its ability id.")
	if int(node.check["difficulty"]) != 11:
		_failures.append("The check lost its difficulty.")
	if String(node.check["kind"]) != "visible":
		_failures.append("The check lost its kind.")
	if not bool(node.check["repeatable"]):
		_failures.append("The check lost its repeatable flag.")
	var modifiers: Array = node.check["modifiers"]
	if modifiers.size() != 1 or String(modifiers[0]["flag"]) != "met_q":
		_failures.append("The check lost its situational modifier.")
	if node.check_targets.size() != 2 or not node.check_targets.has(&"good"):
		_failures.append("The check did not record both of its branches.")


## Each of these is a content mistake that would otherwise surface as a scene that
## quietly does nothing, or as a check that always fails.
func _check_rejections() -> void:
	_expect_rejected("missing ability", _content({"ability": ""}), "ability")
	_expect_rejected("zero difficulty", _content({"difficulty": 0}), "difficulty")
	_expect_rejected("absurd difficulty", _content({"difficulty": 400}), "difficulty")
	_expect_rejected("unknown kind", _content({"kind": "loud"}), "kind")
	_expect_rejected("missing success branch", _content({"success": ""}), "success")
	_expect_rejected("missing failure branch", _content({"failure": ""}), "failure")
	_expect_rejected(
		"a branch that does not exist", _content({"success": "nowhere"}), "missing node"
	)
	_expect_rejected(
		"a modifier without a flag", _content({"modifiers": [{"value": 1}]}), "flag"
	)

	var conflict := _content()
	var nodes: Array = conflict["conversations"]["trial"]["nodes"]
	(nodes[0] as Dictionary)["choices"] = [{"id": "a", "text": "A.", "next": "good"}]
	_expect_rejected("a check that also offers choices", conflict, "choices")

	var with_next := _content()
	var nodes_next: Array = with_next["conversations"]["trial"]["nodes"]
	(nodes_next[0] as Dictionary)["next"] = "good"
	_expect_rejected("a check with a plain next node", with_next, "next")


func _expect_rejected(label: String, data: Dictionary, needle: String) -> void:
	var graph := _load("reject_%s" % label.replace(" ", "_"), data)
	if graph == null:
		return
	if graph.is_valid():
		_failures.append("A check with %s was accepted." % label)
		return
	var joined := graph.describe_errors()
	if not (needle in joined):
		_failures.append(
			"Rejecting a check with %s produced '%s', which does not mention '%s'."
			% [label, joined, needle]
		)


func _check_resolution() -> void:
	Harness.clear_session_state(self)
	var graph := _load("resolution", _content())
	if graph == null:
		return
	var runtime := _new_runtime(graph, 7)
	var result := runtime.get_last_check()
	if result.is_empty():
		_failures.append("Entering a check node produced no check result.")
		return
	if String(result.get("kind", "")) != "visible":
		_failures.append("The result lost the visible kind.")
	if int(result.get("ability_value", -1)) != _abilities.get_value(&"orientation"):
		_failures.append("The result did not use the ability's value.")
	if int(result.get("difficulty", -1)) != 11:
		_failures.append("The result did not carry the node's difficulty.")
	var expected_branch := &"good" if bool(result["success"]) else &"bad"
	runtime.advance()
	var line := runtime.get_current_line()
	if String(line.get("node_id", "")) != String(expected_branch):
		_failures.append(
			"The check continued to '%s' instead of '%s'."
			% [line.get("node_id", "<none>"), expected_branch]
		)
	var record: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"trial", &"roll"), null
	)
	if not (record is Dictionary):
		_failures.append("The check result was not recorded in GameState.")


func _check_visible_and_hidden() -> void:
	for kind: String in ["visible", "hidden"]:
		Harness.clear_session_state(self)
		var graph := _load("kind_%s" % kind, _content({"kind": kind}))
		if graph == null:
			continue
		var runtime := _new_runtime(graph, 11)
		var result := runtime.get_last_check()
		if String(result.get("kind", "")) != kind:
			_failures.append("A '%s' check reported kind '%s'." % [kind, result.get("kind", "")])
		if int(result.get("die", 0)) < CheckResolver.MIN_TOTAL:
			_failures.append("A '%s' check produced no dice." % kind)
		if int(result.get("die", 0)) > CheckResolver.MAX_TOTAL:
			_failures.append("A '%s' check rolled outside 2d6." % kind)


## The anti-reroll rule at the level the player experiences it: come back with a
## completely different seed and the check still falls the same way.
func _check_no_reroll() -> void:
	Harness.clear_session_state(self)
	var graph := _load("reroll", _content({"difficulty": 10}))
	if graph == null:
		return
	var first := _new_runtime(graph, 1)
	var first_result := first.get_last_check().duplicate()
	var first_die := int(first_result.get("die", 0))
	var first_success := bool(first_result.get("success", false))
	if bool(first_result.get("reused", false)):
		_failures.append("The first resolution of a check was marked as reused.")

	var second := _new_runtime(graph, 99999)
	var second_result := second.get_last_check()
	if not bool(second_result.get("reused", false)):
		_failures.append("A repeated check was not reported as reused.")
	if int(second_result.get("die", -1)) != first_die:
		_failures.append(
			"A repeated check re-rolled: die %d after %d."
			% [int(second_result.get("die", -1)), first_die]
		)
	if bool(second_result.get("success", not first_success)) != first_success:
		_failures.append("A repeated check changed its outcome.")


func _check_failure_branch_is_not_a_wall() -> void:
	Harness.clear_session_state(self)
	# Difficulty 30 cannot be met by a value of 3 on 2d6, so this always fails —
	# which is exactly the case that must still leave a playable conversation.
	var graph := _load("always_fails", _content({"difficulty": 30}))
	if graph == null:
		return
	var runtime := _new_runtime(graph, 3)
	var result := runtime.get_last_check()
	if bool(result.get("success", true)):
		_failures.append("An impossible check reported success.")
		return
	runtime.advance()
	var line := runtime.get_current_line()
	if String(line.get("node_id", "")) != "bad":
		_failures.append("The failure branch did not run.")
	if String(line.get("text", "")).is_empty():
		_failures.append("The failure branch had no line of its own.")
	runtime.advance()
	if runtime.is_active():
		_failures.append("The conversation did not end after the failure branch.")
	var recorded: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"trial", &"roll"), null
	)
	if not (recorded is Dictionary) or (recorded as Dictionary).is_empty():
		_failures.append("A failed check was not recorded, so it could be re-rolled later.")
