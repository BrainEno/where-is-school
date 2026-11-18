extends SceneTree
## Proves JsonTable and LocaleParity behave as specified across success and failure paths.

const Harness = preload("res://tests/test_harness.gd")
const TEMP_DIR := "user://json_table_test"

var checks := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "json_table_test.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))

	_test_json_table_read_dict()
	_test_json_table_read_text_and_bytes()
	_test_json_table_describe_errors()
	_test_locale_parity_differences()
	_test_locale_parity_id_and_table()

	Harness.finish(self, checks.failures, "JsonTable and LocaleParity contracts verified.")


func _test_json_table_read_dict() -> void:
	var valid_path := TEMP_DIR + "/valid.json"
	var invalid_path := TEMP_DIR + "/invalid.json"
	var array_path := TEMP_DIR + "/array.json"
	var missing_path := TEMP_DIR + "/missing.json"

	_write_file(valid_path, '{"key": "value", "number": 42}')
	_write_file(invalid_path, '{"bad_json":')
	_write_file(array_path, '[1, 2, 3]')

	# 1. Valid file
	var valid_errors: Array[String] = []
	var valid_data := JsonTable.read_dict(valid_path, valid_errors)
	checks.expect(valid_errors.is_empty(), "Valid JSON should produce no errors.")
	checks.expect(valid_data.get("key", "") == "value", "Valid JSON dictionary read key.")
	checks.expect(int(valid_data.get("number", 0)) == 42, "Valid JSON dictionary read number.")

	# 2. Missing file
	var missing_errors: Array[String] = []
	var missing_data := JsonTable.read_dict(missing_path, missing_errors)
	checks.expect(missing_data.is_empty(), "Missing JSON file should return empty dictionary.")
	checks.expect(missing_errors.size() == 1, "Missing JSON file should record 1 error.")
	checks.expect(
		missing_errors[0].contains("does not exist"),
		"Missing JSON file error should mention missing."
	)

	# 3. Invalid JSON syntax
	var syntax_errors: Array[String] = []
	var syntax_data := JsonTable.read_dict(invalid_path, syntax_errors)
	checks.expect(syntax_data.is_empty(), "Invalid JSON syntax should return empty dictionary.")
	checks.expect(syntax_errors.size() == 1, "Invalid JSON should record 1 error.")
	checks.expect(
		syntax_errors[0].contains("invalid JSON at line"),
		"Invalid JSON error should mention line number."
	)

	# 4. Top-level array instead of dictionary
	var array_errors: Array[String] = []
	var array_data := JsonTable.read_dict(array_path, array_errors)
	checks.expect(array_data.is_empty(), "Array JSON should return empty dictionary.")
	checks.expect(array_errors.size() == 1, "Array JSON should record 1 error.")
	checks.expect(
		array_errors[0].contains("not a JSON object"),
		"Array JSON error should mention not a JSON object."
	)

	# 5. Custom messages
	var custom_missing_errors: Array[String] = []
	JsonTable.read_dict(
		missing_path,
		custom_missing_errors,
		"%s: custom not dict",
		"Custom missing: %s"
	)
	checks.expect(
		custom_missing_errors[0] == "Custom missing: " + missing_path,
		"Custom missing format applied correctly."
	)


func _test_json_table_read_text_and_bytes() -> void:
	var path := TEMP_DIR + "/sample.txt"
	var text_content := "Sample content for testing."
	_write_file(path, text_content)

	var read := JsonTable.read_text(path)
	checks.expect(read == text_content, "JsonTable.read_text returns exact content.")

	var bytes := JsonTable.file_bytes(path)
	checks.expect(bytes == text_content.length(), "JsonTable.file_bytes matches content length.")

	var missing := JsonTable.read_text(TEMP_DIR + "/non_existent.txt")
	checks.expect(missing.is_empty(), "JsonTable.read_text returns empty string for missing file.")

	var zero_bytes := JsonTable.file_bytes(TEMP_DIR + "/non_existent.txt")
	checks.expect(zero_bytes == 0, "JsonTable.file_bytes returns 0 for missing file.")


func _test_json_table_describe_errors() -> void:
	var empty_errs: Array[String] = []
	var empty_desc := JsonTable.describe_errors("Test catalog", empty_errs)
	checks.expect(
		empty_desc == "Test catalog loaded without errors.",
		"describe_errors formats success cleanly."
	)

	var errs: Array[String] = ["first failure", "second failure"]
	var err_desc := JsonTable.describe_errors("Test catalog", errs)
	checks.expect(
		err_desc == "Test catalog has 2 error(s):\nfirst failure\nsecond failure",
		"describe_errors formats errors correctly."
	)

	var plural_desc := JsonTable.describe_errors("Inner abilities", errs, "have")
	checks.expect(
		plural_desc == "Inner abilities have 2 error(s):\nfirst failure\nsecond failure",
		"describe_errors formats custom verb correctly."
	)


func _test_locale_parity_differences() -> void:
	var ref_keys: Array = ["alpha", "beta", "gamma"]
	var target_keys: Array = ["beta", "gamma", "delta"]

	var diff := LocaleParity.find_key_differences(ref_keys, target_keys)
	var missing: Array = diff.get("missing", [])
	var extra: Array = diff.get("extra", [])

	checks.expect(missing == ["alpha"], "find_key_differences identifies missing keys.")
	checks.expect(extra == ["delta"], "find_key_differences identifies extra keys.")


func _test_locale_parity_id_and_table() -> void:
	var ref_ids: Array = ["intro", "clue_a"]
	var target_ids: Array = ["clue_a", "extra_clue"]

	var id_problems := LocaleParity.check_id_parity(
		"en", ref_ids, "zh-CN", target_ids, "entry", "path/test.json"
	)
	checks.expect(id_problems.size() == 2, "check_id_parity reports both missing and extra.")
	checks.expect(
		id_problems[0].contains("has no text (present in en)"),
		"check_id_parity reports missing text."
	)
	checks.expect(
		id_problems[1].contains("does not exist in en"),
		"check_id_parity reports extra text."
	)

	var ref_table := {"entry_1": {}, "entry_2": {}}
	var target_table := {"entry_2": {}, "entry_3": {}}
	var table_problems := LocaleParity.check_table_parity(
		"en", ref_table, "zh-CN", target_table
	)
	checks.expect(table_problems.size() == 2, "check_table_parity reports both directions.")
	checks.expect(
		table_problems[0] == "en records 'entry_1' but zh-CN never does.",
		"check_table_parity reports missing key in target."
	)
	checks.expect(
		table_problems[1] == "zh-CN records 'entry_3' but en never does.",
		"check_table_parity reports extra key in target."
	)


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()
