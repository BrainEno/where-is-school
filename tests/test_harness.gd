extends RefCounted
## Shared helpers for the headless test scripts.
##
## Tests run with `godot --headless --script res://tests/<name>.gd`. Several of
## them need the two autoloads (GameState, NarrativeState) available even when the
## engine did not register them for a plain script run, so this harness creates
## them on demand instead of assuming a boot order.

const GAME_STATE_SCRIPT := "res://scripts/autoload/game_state.gd"
const NARRATIVE_STATE_SCRIPT := "res://scripts/autoload/narrative_state.gd"


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
	}


## Hard watchdog: a test that stalls must still terminate with a failure instead
## of eating the CI job's whole time budget. The timer ignores Engine.time_scale.
static func arm_watchdog(tree: SceneTree, seconds: float, label: String) -> void:
	var timer := tree.create_timer(seconds, true, false, true)
	timer.timeout.connect(
		func() -> void:
			push_error("TEST WATCHDOG: %s exceeded %.0f seconds and was aborted." % [label, seconds])
			print("FAIL: %s timed out after %.0f seconds." % [label, seconds])
			tree.quit(2)
	)


static func reset_state(tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null(^"GameState")
	if game_state != null:
		game_state.clear()
	var narrative_state := tree.root.get_node_or_null(^"NarrativeState")
	if narrative_state != null:
		narrative_state.clear()


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
