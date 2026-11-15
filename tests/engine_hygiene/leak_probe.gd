extends SceneTree
## The minimal reproduction for "N ObjectDB instances were leaked at exit" (issue #67).
##
## The warning appears in most headless checks at the same small counts, including checks
## that load no scene at all (`check_resolver_test.gd` is a dice formula and a watchdog). So
## the question is not which *test* leaks but which *step every test shares* does. This
## script is a ladder of those steps, one more per rung, selected on the command line:
##
##     godot --headless --verbose --path . \
##         --script res://tests/engine_hygiene/leak_probe.gd -- --rung=2
##
## | Rung | Does                                                                    |
## |---:|---|
## | 0 | nothing: print the root's children (which autoloads a `--script` run has) and quit |
## | 1 | + `Harness.arm_watchdog()` and `Harness.finish()`, as every check does        |
## | 2 | + `Harness.ensure_state_autoloads()` / `clear_session_state()`              |
## | 3 | + the `Settings` and `Session` autoloads the UI checks add                   |
## | 4 | + a real `main.tscn`, a few frames, then freed - what the gameplay checks do |
##
## Run each rung with `--verbose` and the engine names every object it still holds at exit
## (`Leaked instance: Class:id - Node path: ...`); `tools/engine_noise_report.py` lines the
## rungs up and prints what each one adds over the one below. Nothing here frees anything
## extra, silences a warning or changes a verdict: the ladder exists to *show* the source,
## and a fix belongs where the source is.
##
## Each rung prints `PASS:` when it ran to its end, so `tools/ci_run_check.sh` can read it
## like any other check.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const TOP_RUNG := 4

var _rung := 0


func _initialize() -> void:
	_rung = _read_rung()
	print("leak probe: rung %d" % _rung)
	if _rung >= 1:
		Harness.arm_watchdog(self, 60.0, "leak_probe.gd rung %d" % _rung)
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	print("leak probe: root children at start: %s" % _child_names())
	if _rung >= 2:
		var autoloads := Harness.ensure_state_autoloads(self)
		if autoloads["game_state"] == null:
			failures.append("The state autoloads could not be created.")
		Harness.clear_session_state(self)
	if _rung >= 3:
		var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
		Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
		if settings == null:
			failures.append("The Settings autoload could not be created.")
	if _rung >= 4:
		var world := (load(MAIN) as PackedScene).instantiate()
		var sequence := world.get_node_or_null(^"OpeningSequence")
		if sequence != null:
			sequence.set("autostart", false)
		root.add_child(world)
		for _frame in 10:
			await process_frame
		var save := root.get_node_or_null(^"Save")
		if save != null and save.has_method("unbind_world"):
			save.unbind_world()
		world.queue_free()
		for _frame in 5:
			await process_frame
		if _rung >= 2:
			Harness.clear_session_state(self)
	print("leak probe: root children at the end: %s" % _child_names())
	if _rung == 0:
		print("PASS: leak probe rung 0 ran.")
		quit(0)
		return
	Harness.finish(self, failures, "leak probe rung %d ran." % _rung)


func _read_rung() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rung="):
			return clampi(int(argument.trim_prefix("--rung=")), 0, TOP_RUNG)
	return 0


func _child_names() -> String:
	var names: Array[String] = []
	for child in root.get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	return ", ".join(names)
