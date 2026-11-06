extends RefCounted
class_name TestCaseHelper
## Base class for headless test suites.
##
## Subclasses implement [method _run]. Assertions go through [method check] and
## friends, which report to [member runner] instead of guessing at exit codes.
## Failures are counted, printed, and surfaced by the runner's final exit code —
## there is no "print and carry on" path that could let CI go green.

var runner: Object


func run_suite() -> void:
	if not has_method("_run"):
		check(false, "suite has no _run()")
		return
	await call("_run")


# --- assertions -------------------------------------------------------------

func check(condition: bool, message: String, detail: String = "") -> void:
	if runner != null:
		runner.report_assert(condition, message, detail)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, message, "expected %s, got %s" % [str(expected), str(actual)])


func check_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	check(actual != unexpected, message, "value should differ from %s" % str(unexpected))


func check_true(condition: bool, message: String) -> void:
	check(condition, message, "expected true")


func check_false(condition: bool, message: String) -> void:
	check(not condition, message, "expected false")


func check_not_null(value: Variant, message: String) -> void:
	check(value != null, message, "expected non-null")


func check_null(value: Variant, message: String) -> void:
	check(value == null, message, "expected null")


func check_empty(value: Variant, message: String) -> void:
	var size: int = value.size() if value != null else 0
	check(size == 0, message, "expected empty, got %d entries: %s" % [size, str(value)])


func check_has(container: Variant, needle: Variant, message: String) -> void:
	check(container.has(needle), message, "%s missing from %s" % [str(needle), str(container)])


func check_contains_text(value: String, needle: String, message: String) -> void:
	check(value.contains(needle), message, "'%s' not found in '%s'" % [needle, value])


# --- helpers ----------------------------------------------------------------

func make_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func flush_frames(count: int = 2) -> void:
	for _i in count:
		await make_tree().process_frame


func add_to_tree(node: Node) -> Node:
	make_tree().root.add_child(node)
	return node


## Builds a fresh dialogue session and collects everything it emits, which is how
## integration tests observe consequences without a window.
func make_session(script: DialogueScript) -> Dictionary:
	var session := DialogueSession.new()
	var log := {"lines": [], "choices": [], "flags": [], "records": [], "cues": [], "finished": []}
	session.line_presented.connect(func(line, history): log["lines"].append(line))
	session.choices_presented.connect(func(choices): log["choices"].append(choices))
	session.flags_requested.connect(func(flags): log["flags"].append(flags))
	session.records_requested.connect(func(records): log["records"].append(records))
	session.cue_requested.connect(func(cue): log["cues"].append(cue))
	session.session_finished.connect(func(script_id): log["finished"].append(script_id))
	var game_state: Node = make_tree().root.get_node_or_null("GameState")
	var reader: Callable = Callable()
	if game_state != null:
		reader = Callable(game_state, "get_flag")
	var ok: bool = session.start(script, reader)
	if not ok:
		check(false, "DialogueSession failed to start '%s'" % String(script.id))
	return {"session": session, "log": log}
