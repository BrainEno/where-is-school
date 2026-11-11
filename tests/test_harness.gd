extends RefCounted
## Shared helpers for the headless test scripts.
##
## Tests run with `godot --headless --script res://tests/<name>.gd`. Several of
## them need the two autoloads (GameState, NarrativeState) available even when the
## engine did not register them for a plain script run, so this harness creates
## them on demand instead of assuming a boot order.

## The stage the running test is in. A test sets it before each section; the watchdog
## reports it on timeout, so a silent hang says where it stopped instead of only how
## long it waited.
static var stage: String = ""

const GAME_STATE_SCRIPT := "res://scripts/autoload/game_state.gd"
const NARRATIVE_STATE_SCRIPT := "res://scripts/autoload/narrative_state.gd"
const SAVE_SCRIPT := "res://scripts/autoload/save_manager.gd"


static func ensure_autoload(tree: SceneTree, node_name: String, script_path: String) -> Node:
	if tree == null or tree.root == null:
		push_error("TestHarness: scene tree is not available yet.")
		return null
	var existing := tree.root.get_node_or_null(NodePath(node_name))
	if existing != null:
		return existing
	var script: Script = load(script_path)
	if script == null:
		push_error("TestHarness: could not load %s" % script_path)
		return null
	var instance: Node = script.new()
	if instance == null:
		push_error("TestHarness: could not instantiate %s" % script_path)
		return null
	instance.name = node_name
	tree.root.add_child(instance)
	return instance


static func ensure_state_autoloads(tree: SceneTree) -> Dictionary:
	return {
		"game_state": ensure_autoload(tree, "GameState", GAME_STATE_SCRIPT),
		"narrative_state": ensure_autoload(tree, "NarrativeState", NARRATIVE_STATE_SCRIPT),
		"save": ensure_autoload(tree, "Save", SAVE_SCRIPT),
	}


## Hard watchdog: a test that stalls must still terminate with a failure instead
## of eating the CI job's whole time budget. A Timer node is used (rather than a
## SceneTreeTimer) so the instance is owned by the tree and freed at exit.
static func arm_watchdog(tree: SceneTree, seconds: float, label: String) -> void:
	if tree == null or tree.root == null:
		push_error("TestHarness: cannot arm a watchdog without a scene tree.")
		return
	var timer := Timer.new()
	timer.name = "TestWatchdog"
	timer.wait_time = seconds
	timer.one_shot = true
	timer.ignore_time_scale = true
	timer.autostart = true
	timer.timeout.connect(
		func() -> void:
			var where := stage if not stage.is_empty() else "an unnamed stage"
			push_error(
				"TEST WATCHDOG: %s exceeded %.0f seconds (stage: %s) and was aborted."
				% [label, seconds, where]
			)
			print("FAIL: %s timed out after %.0f seconds (stage: %s)." % [label, seconds, where])
			tree.quit(2)
	)
	# autostart: the root is not inside the tree yet while _initialize() runs, so
	# calling start() here would fail; the timer begins once it enters the tree.
	tree.root.add_child(timer)


static func clear_session_state(tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null(^"GameState")
	if game_state != null:
		game_state.clear()
	var narrative_state := tree.root.get_node_or_null(^"NarrativeState")
	if narrative_state != null:
		narrative_state.clear()
	# The save file is shared by every check in the CI job (`user://` is one directory
	# per project, not per test), and the game resumes from it at boot. A check that
	# left one behind would start the next one in a different room.
	var save := tree.root.get_node_or_null(^"Save")
	if save != null and save.has_method("forget_all"):
		save.forget_all()


## Prints a single summary line and exits with the right code. Tests never call
## quit(0) without first collecting their failures, so a green run means the
## assertions actually ran.
static func finish(tree: SceneTree, failures: Array, success_message: String) -> void:
	if failures.is_empty():
		print("PASS: %s" % success_message)
		tree.quit(0)
		return
	for failure: Variant in failures:
		push_error("TEST FAILURE: %s" % String(failure))
	print("FAIL: %d problem(s) found." % failures.size())
	tree.quit(1)
