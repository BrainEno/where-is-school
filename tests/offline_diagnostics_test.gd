extends SceneTree
## Isolated store/filter/failure/privacy checks. The playthrough test covers the menu.

const Harness := preload("res://tests/test_harness.gd")
const Log := preload("res://scripts/autoload/diagnostics.gd")
const Store := preload("res://scripts/diagnostics/log_store.gd")
const Schema := preload("res://scripts/diagnostics/event_schema.gd")
const FIRST_FILE := "events-000000000001.jsonl"
const SECRET := "PRIVATE_DIAGNOSTICS_SENTINEL"
const PRIVATE_PATH := "C:/Users/" + SECRET + "/notes.txt"

var checks := Harness.Checker.new()
var _base := ""


func _initialize() -> void:
	Harness.arm_watchdog(self, 35.0, "offline_diagnostics_test.gd")
	_run.call_deferred()


func _run() -> void:
	_base = "user://diagnostics-check-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_filter_and_privacy()
	_rotation()
	_write_failure_and_recovery()
	await _background_flush()
	_remove_fixture(_base)
	Harness.finish(self, checks.failures,
		"离线日志等级、类别、结构、去重、隐私、轮转、限额、损坏恢复和写入降级通过。")


func _new_log(path: String) -> Log:
	var log := Log.new(path)
	root.add_child(log)
	log.set_process(false)
	return log


func _filter_and_privacy() -> void:
	var path := _base.path_join("privacy")
	var log := _new_log(path)
	checks.expect(not DirAccess.dir_exists_absolute(path), "A new logger should not require a directory at startup.")
	log.record("assets.text_load_timing", {"elapsed_ms": 123}) # DEBUG filtered by default
	log.set_filter(Log.Level.WARNING, ["world"])
	log.record("dialogue.effect_refused") # category filtered
	log.record("world.entered", {"to_location": "classroom"}) # INFO filtered
	log.record(SECRET, {"message": PRIVATE_PATH}) # unregistered event filtered
	for i: int in 3:
		log.record("world.transition_refused", {
			"from_location": &"classroom", "to_location": SECRET, "reason": "scene_missing",
			"text": PRIVATE_PATH, "save": {"secret": SECRET},
		})
	log.record("world.transition_refused", {"from_location": "corridor", "reason": "no_spawn"})
	log.set_filter(Log.Level.DEBUG, ["assets"])
	log.record("assets.text_load_timing", {"elapsed_ms": 19, "dialogue_locales": PRIVATE_PATH})
	checks.expect(log.flush() == OK, "First flush could not create the missing directory/file.")
	var filename := path.path_join(FIRST_FILE)
	var raw := FileAccess.get_file_as_string(filename)
	checks.expect(not SECRET in raw and not "Users/" in raw, "Private fields leaked into raw JSONL.")
	var lines := raw.split("\n", false)
	if checks.expect(lines.size() == 4, "Filters or contiguous deduplication wrote the wrong number of rows."):
		var row: Dictionary = JSON.parse_string(lines[1])
		checks.expect(row["event"] == "world.transition_refused" and row["level"] == "ERROR"
			and row["category"] == "world" and not String(row["message"]).is_empty()
			and row["schema"] == 1 and row["at_unix_s"] > 0 and row["last_unix_s"] >= row["at_unix_s"],
			"A row must carry a schema, category, level, stable event, message and UTC timestamps.")
		checks.expect(row["repeat"] == 3 and row["context"] == {
			"from_location": "classroom", "reason": "scene_missing",
		}, "The logger did not merge adjacent repeats or omit unsafe context.")
		var debug: Dictionary = JSON.parse_string(lines[-1])
		checks.expect(debug["level"] == "DEBUG" and debug["context"] == {"elapsed_ms": 19.0},
			"The debug filter or numeric field validation did not work.")

	# A previously stored file is untrusted. Export rebuilds rows, skips broken data,
	# and never copies a neighbouring legacy/raw log or a tempting save file.
	var file := FileAccess.open(filename, FileAccess.READ_WRITE)
	if checks.expect(file != null, "Cannot append prior-run privacy/corruption fixtures."):
		file.seek_end()
		file.store_line(JSON.stringify({"schema": 1, "event": "world.entered", "level": SECRET,
			"category": SECRET, "message": PRIVATE_PATH, "at_unix_s": 50, "last_unix_s": 50, "repeat": 1,
			"context": {"from_location": PRIVATE_PATH, "to_location": "classroom", "note": SECRET}}))
		file.store_line("corrupt " + SECRET)
		file.store_string('{"schema":') # intentionally no newline
		file.close()
	FileAccess.open(path.path_join("godot.log"), FileAccess.WRITE).store_string(PRIVATE_PATH)
	FileAccess.open(path.path_join("save.json"), FileAccess.WRITE).store_string(SECRET)
	log.set_filter(Log.Level.INFO)
	log.record("save.recovered")
	var result: Dictionary = log.export_report()
	checks.expect(result["ok"] and result["partial"], "Export did not report skipped/corrupt history.")
	var report_text := FileAccess.get_file_as_string(path.path_join(Store.EXPORT_NAME))
	checks.expect(not SECRET in report_text and not "Users/" in report_text,
		"Private contents on disk leaked into the report.")
	var report: Variant = JSON.parse_string(report_text)
	if checks.expect(report is Dictionary, "The report is not readable JSON."):
		var history: Dictionary = report["history"]
		var rows: Array = report["events"]
		checks.expect(history["skipped_units"] == 2 and rows.size() == 6,
			"Complete prior rows did not survive a corrupted or unterminated line.")
		if rows.size() >= 2:
			checks.expect(rows[-2]["context"] == {"to_location": "classroom"}
				and rows[-2]["level"] == "INFO" and rows[-1]["level"] == "WARNING",
				"Disk rows were not reconstructed from the schema or recovered after rotation.")
	log.free()


func _rotation() -> void:
	var path := _base.path_join("rotation")
	var log := _new_log(path)
	log.set_filter(Log.Level.INFO, ["save"])
	for index: int in 2000:
		log.record("save.written", {"version": index})
		if index % Log.BUFFER_LIMIT == Log.BUFFER_LIMIT - 2:
			if not checks.expect(log.flush() == OK, "Rotation batch could not be written."):
				break
	checks.expect(log.flush() == OK, "Rotation final batch could not be written.")
	var files := DirAccess.get_files_at(path)
	checks.expect(files.size() == Store.FILE_COUNT and not FIRST_FILE in files,
		"Rotation did not evict old files at the count limit.")
	for name: String in files:
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		checks.expect(file != null and file.get_length() <= Store.FILE_BYTES, "A log exceeded the byte cap.")
	var data := Store.history(path, Schema.new())
	var rows: Array = data["rows"]
	if checks.expect(rows.size() == Store.HISTORY_LIMIT and data["skipped"] == 0,
			"Recent history should be bounded and complete."):
		checks.expect(rows[-1]["context"]["version"] == 1999 and rows[0]["context"]["version"] == 1840,
			"Recent history is not the newest records, in storage order.")
	log.free()


func _write_failure_and_recovery() -> void:
	var path := _base.path_join("blocked")
	DirAccess.make_dir_recursive_absolute(_base)
	FileAccess.open(path, FileAccess.WRITE).store_string("blocks the log directory")
	var log := _new_log(path)
	checks.expect(log.flush() != OK, "A regular file cannot serve as a log directory.")
	checks.expect(log.open_directory() != OK, "Opening a blocked directory should report a failure.")
	checks.expect(not log.export_report()["ok"], "Export must report when its directory is inaccessible.")
	DirAccess.remove_absolute(path)
	# Leave the directory writable but make creation of the journal fail everywhere,
	# including CI runners whose account can still write chmod-read-only fixtures.
	var block := path.path_join(FIRST_FILE)
	DirAccess.make_dir_recursive_absolute(block)
	for index: int in Log.BUFFER_LIMIT + 20:
		log.record("save.written", {"version": index})
	var result: Dictionary = log.export_report()
	checks.expect(result["ok"] and result["partial"], "Writable export should include memory when log I/O fails.")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(Store.EXPORT_NAME)))
	if checks.expect(report is Dictionary, "Degraded export did not produce JSON."):
		var history: Dictionary = report["history"]
		var rows: Array = report["events"]
		checks.expect(history["write_error"] != OK and history["pending_records"] == Log.BUFFER_LIMIT
			and history["discarded_this_process"] == 21 and rows.size() == Log.BUFFER_LIMIT,
			"Failed writes did not report loss or keep a bounded buffer.")
		if not rows.is_empty():
			checks.expect(rows[0]["context"]["version"] == 20, "A full buffer did not retain its newest records.")
	DirAccess.remove_absolute(block)
	checks.expect(log.flush() == OK, "Logger did not resume after storage recovered.")
	checks.expect(Store.history(path, Schema.new())["rows"].size() == Log.BUFFER_LIMIT,
		"The retained batch was not written once after retry.")
	log.free()


func _background_flush() -> void:
	var path := _base.path_join("background")
	var log := _new_log(path)
	log.record("save.recovered")
	paused = true
	log.set_process(true)
	var flushed := await Harness.wait_until(func() -> bool:
		return FileAccess.file_exists(path.path_join(FIRST_FILE)) \
			and "save.recovered" in FileAccess.get_file_as_string(path.path_join(FIRST_FILE))
	, 9.0)
	paused = false
	checks.expect(flushed, "The periodic worker did not write its batch while the game was paused.")
	log.free()


func _remove_fixture(path: String) -> void:
	for child: String in DirAccess.get_directories_at(path):
		_remove_fixture(path.path_join(child))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
