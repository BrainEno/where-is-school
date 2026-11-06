extends SceneTree
## Minimal headless test runner: no addons, no network, deterministic exit code.
##
## Usage:
##   godot --headless --path . --script res://tests/test_runner.gd
##   godot --headless --path . --script res://tests/test_runner.gd -- --filter=ledger
##
## A test suite is any GDScript under res://tests that extends `TestCaseHelper`
## (see tests/unit/). Each suite may implement `_run()` and assert with the
## helpers on the base class. Failures print with file/line-ish context and set a
## non-zero exit code, so CI can trust a green run.

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _current_file: String = ""
var _filter: String = ""


func _initialize() -> void:
	_parse_args()
	call_deferred("_run_all")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")


func _run_all() -> void:
	var files: Array[String] = []
	for dir in TEST_DIRS:
		files.append_array(_collect(dir))
	files.sort()

	if files.is_empty():
		push_error("Test runner found no test files in %s." % str(TEST_DIRS))
		quit(1)
		return

	print("== where-is-school test runner ==")
	print("Godot: %s" % Engine.get_version_info().get("string", "unknown"))
	for path in files:
		if not _filter.is_empty() and not path.contains(_filter):
			continue
		await _run_file(path)

	print("\n== results: %d passed, %d failed ==" % [_passed, _failed])
	if _failed > 0:
		for failure in _failures:
			printerr("FAILED: %s" % failure)
		quit(1)
		return
	print("All tests passed.")
	quit(0)


func _collect(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			result.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return result


func _run_file(path: String) -> void:
	_current_file = path
	var script: Script = load(path) as Script
	if script == null:
		_record(false, "%s could not be loaded as a Script." % path)
		return
	if not script.can_instantiate():
		_record(false, "%s could not be instantiated (script failed to compile)." % path)
		return
	var instance: Object = script.new()
	if instance == null:
		_record(false, "%s could not be instantiated (missing class?)." % path)
		return
	if not instance.has_method("run_suite"):
		_record(false, "%s does not extend TestCaseHelper." % path)
		return

	instance.set("runner", self)
	var before: int = _passed + _failed
	print("\n-- %s" % path.get_file())
	await instance.call("run_suite")
	# A suite that asserts nothing is not evidence of anything. Refuse it rather
	# than letting a renamed or silently-skipped test look green.
	if _passed + _failed == before:
		_record(false, "%s ran zero assertions." % path.get_file())


func report_assert(condition: bool, message: String, detail: String = "") -> void:
	_record(condition, message + ("" if detail.is_empty() else " :: " + detail))


func _record(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		return
	_failed += 1
	var entry := "%s — %s" % [_current_file.get_file(), message]
	_failures.append(entry)
	printerr("  ✗ %s" % message)
