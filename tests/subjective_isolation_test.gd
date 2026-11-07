extends SceneTree
## Subjective conversations must not be able to write objective story state.
##
## The rule is old ("an imagined scene cannot change the world"), but two holes
## were open:
##
## - a `once` choice in a subjective conversation wrote a choice flag, which is
##   story state, even though it only meant "this option was taken";
## - a `check` inside one wrote its result (dice, total, branch) so the roll could
##   not be repeated. A fantasy could therefore leave a permanent object behind.
##
## Both are now refused twice: the graph validator rejects the content while it is
## being loaded, and the runtime refuses to write anything if invalid content
## reaches it anyway. This test asserts both halves, and asserts them by comparing
## a full GameState snapshot before and after, so a new field cannot slip past.

const Harness = preload("res://tests/test_harness.gd")

const BASE_DIR := "user://subjective_isolation"

var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null
var _abilities: InnerAbilities = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "subjective_isolation_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	DirAccess.make_dir_recursive_absolute(BASE_DIR)
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		Harness.finish(self, ["abilities: " + _abilities.describe_errors()], "")
		return

	_check_validation_rejects_once()
	_check_validation_rejects_check()
	_check_runtime_refuses_once()
	_check_runtime_refuses_check()
	_check_honest_subjective_still_works()

	Harness.finish(
		self, _failures,
		"a fantasy cannot write a flag, an objective, a choice record, or a dice result."
	)


# --- fixtures ---------------------------------------------------------------


func _content(overrides: Dictionary = {}) -> Dictionary:
	var conversation := {
		"default_source": "observed",
		"subjective": true,
		"start": "a",
		"nodes": [
			{
				"id": "a",
				"speaker": "protagonist",
				"text": "You imagine the conversation going well.",
				"choices": [
					{"id": "say_it", "text": "Say it.", "next": "b"},
					{"id": "leave_it", "text": "Leave it.", "next": "b"},
				],
			},
			{"id": "b", "speaker": "protagonist", "text": "It goes well.", "next": null},
		],
	}
	conversation.merge(overrides, true)
	return {
		"format_version": 2,
		"locale": "en",
		"chapter": "subjective",
		"conversations": {"fantasy": conversation},
	}


func _load(name: String, data: Dictionary) -> DialogueGraph:
	var path := "%s/%s.json" % [BASE_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write fixture %s." % path)
		return null
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return DialogueGraph.load_from_file(path)


# --- validation -------------------------------------------------------------


func _check_validation_rejects_once() -> void:
	var data := _content()
	var node: Dictionary = (data["conversations"]["fantasy"]["nodes"] as Array)[0]
	(node["choices"] as Array)[0]["once"] = true
	var graph := _load("rejects_once", data)
	if graph == null:
		return
	if graph.is_valid():
		_failures.append("A 'once' choice in a subjective conversation was accepted.")
		return
	if not _mentions(graph.describe_errors(), "once"):
		_failures.append(
			"The rejection does not explain the 'once' bookkeeping: %s" % graph.describe_errors()
		)


func _check_validation_rejects_check() -> void:
	var data := _content()
	var node: Dictionary = (data["conversations"]["fantasy"]["nodes"] as Array)[1]
	node["check"] = {
		"ability": "orientation", "difficulty": 9, "kind": "hidden",
		"success": "b", "failure": "b",
	}
	var graph := _load("rejects_check", data)
	if graph == null:
		return
	if graph.is_valid():
		_failures.append("A check inside a subjective conversation was accepted.")
		return
	if not _mentions(graph.describe_errors(), "check"):
		_failures.append(
			"The rejection does not mention the check: %s" % graph.describe_errors()
		)


# --- runtime ----------------------------------------------------------------


## The runtime is handed the invalid graph on purpose. It must play the scene and
## leave GameState exactly as it found it.
func _check_runtime_refuses_once() -> void:
	Harness.clear_session_state(self)
	var data := _content()
	var node: Dictionary = (data["conversations"]["fantasy"]["nodes"] as Array)[0]
	(node["choices"] as Array)[0]["once"] = true
	var graph := _load("runtime_once", data)
	if graph == null:
		return
	var before: Dictionary = _game_state.get_snapshot().duplicate(true)
	var runtime := _new_runtime(graph)
	if runtime == null:
		return
	var rejections := _count_rejections(runtime)
	runtime.choose(0)
	_drain(runtime)
	var after: Dictionary = _game_state.get_snapshot()
	var choice_flag := StoryFlags.choice_flag(&"fantasy", &"say_it")
	if _has_flag(after, choice_flag):
		_failures.append("The runtime wrote the 'once' choice flag of a subjective conversation.")
	if not _same_state(before, after):
		_failures.append("A subjective 'once' choice changed story state: %s" % _describe_diff(before, after))
	if rejections.call() == 0:
		_failures.append("Refusing the 'once' flag did not report why.")


func _check_runtime_refuses_check() -> void:
	Harness.clear_session_state(self)
	var data := _content()
	var node: Dictionary = (data["conversations"]["fantasy"]["nodes"] as Array)[1]
	node["check"] = {
		"ability": "orientation", "difficulty": 9, "kind": "visible",
		"success": "b", "failure": "b",
	}
	var graph := _load("runtime_check", data)
	if graph == null:
		return
	var before: Dictionary = _game_state.get_snapshot().duplicate(true)
	var runtime := _new_runtime(graph)
	if runtime == null:
		return
	var rejections := _count_rejections(runtime)
	_drain(runtime)
	var after: Dictionary = _game_state.get_snapshot()
	var record_flag := StoryFlags.check_record_flag(&"fantasy", &"b")
	if _has_flag(after, record_flag):
		_failures.append("The runtime recorded a dice result inside a subjective conversation.")
	if runtime.get_last_check().size() > 0:
		_failures.append("A check was rolled inside a subjective conversation.")
	if not _same_state(before, after):
		_failures.append("A subjective check changed story state: %s" % _describe_diff(before, after))
	if rejections.call() == 0:
		_failures.append("Refusing the check did not report why.")


## The guards must not be so broad that a legitimate subjective scene stops
## working: it may still run, and it may still record memories (which are not
## objective knowledge).
func _check_honest_subjective_still_works() -> void:
	Harness.clear_session_state(self)
	var data := _content()
	var node: Dictionary = (data["conversations"]["fantasy"]["nodes"] as Array)[0]
	(node["choices"] as Array)[1]["effects"] = [
		{"type": "record", "entry_id": "imagined_goodbye", "source": "imagined",
		 "speaker": "protagonist", "text": "You imagined saying a proper goodbye."},
	]
	var graph := _load("honest", data)
	if graph == null:
		return
	if not graph.is_valid():
		_failures.append("A legitimate subjective conversation was rejected: %s" % graph.describe_errors())
		return
	var runtime := _new_runtime(graph)
	if runtime == null:
		return
	runtime.choose(1)
	_drain(runtime)
	if not _narrative.has_entry(&"imagined_goodbye"):
		_failures.append("A subjectively-imagined memory was not recorded.")
	if _flag(StoryFlags.OBJECTIVE_KEY):
		_failures.append("A subjective conversation set an objective.")


# --- helpers ----------------------------------------------------------------


func _new_runtime(graph: DialogueGraph) -> DialogueRuntime:
	var runtime := DialogueRuntime.new(
		_game_state, _narrative, CharacterDirectory.load_all(), _abilities, CheckResolver.new(11)
	)
	if not runtime.start(graph, &"fantasy"):
		_failures.append("The subjective fixture conversation did not start.")
		return null
	return runtime


func _drain(runtime: DialogueRuntime) -> void:
	var steps := 0
	while runtime.is_active() and steps < 200:
		steps += 1
		if not runtime.get_available_choice_ids().is_empty():
			runtime.choose(0)
			continue
		runtime.advance()


## Counts `effect_rejected` emissions lazily: the signal carries a reason string and
## the caller only needs to know whether one arrived.
func _count_rejections(runtime: DialogueRuntime) -> Callable:
	var counter := {"count": 0}
	runtime.effect_rejected.connect(
		func(_reason: String) -> void:
			counter["count"] = int(counter["count"]) + 1
	)
	return func() -> int: return int(counter["count"])


func _same_state(before: Dictionary, after: Dictionary) -> bool:
	return JSON.stringify(_stable(before)) == JSON.stringify(_stable(after))


func _stable(value: Dictionary) -> Dictionary:
	var sorted := {}
	var keys := value.keys()
	keys.sort()
	for key: Variant in keys:
		sorted[key] = value[key]
	return sorted


func _describe_diff(before: Dictionary, after: Dictionary) -> String:
	var changed: Array[String] = []
	var keys := {}
	for key: Variant in before.keys():
		keys[key] = true
	for key: Variant in after.keys():
		keys[key] = true
	for key: Variant in keys.keys():
		if JSON.stringify(before.get(key, null)) != JSON.stringify(after.get(key, null)):
			changed.append(String(key))
	return ", ".join(changed) if not changed.is_empty() else "(no key differed)"


func _has_flag(snapshot: Dictionary, flag: StringName) -> bool:
	return snapshot.has(flag)


func _flag(flag: StringName) -> bool:
	var value: Variant = _game_state.get_flag(flag, false)
	return value == true


func _mentions(text: String, needle: String) -> bool:
	return text.to_lower().contains(needle.to_lower())
