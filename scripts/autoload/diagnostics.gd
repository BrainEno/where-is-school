extends Node
## Local-only game diagnostics. Call from the main thread at gameplay boundaries,
## not per frame. This is not an engine logger or a substitute for handling errors.

const Schema := preload("res://scripts/diagnostics/event_schema.gd")
const Store := preload("res://scripts/diagnostics/log_store.gd")
const Level := Schema.Level
const LOG_DIR := "user://logs"
const EXPORT_NAME := Store.EXPORT_NAME
const BUFFER_LIMIT := 64
const FLUSH_MSEC := 3000
const RETRY_MSEC := 10000
const DEDUPE_MSEC := 1500

var _directory: String
var _schema := Schema.new()
var _minimum: int = Level.INFO
var _categories: Array[String] = []
var _pending: Array[Dictionary] = []
var _in_flight: Array[Dictionary] = []
var _worker: Thread = null
var _last_record_msec := 0
var _next_flush_msec := 0
var _write_error := OK
var _discarded_records := 0


## Resolve the service at runtime: --script tests compile their dependencies before
## Godot registers autoload globals. An isolated scene without the service still runs.
static func active() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Diagnostics") if tree != null and tree.root != null else null


static func note(event: String, context: Dictionary = {}) -> void:
	var log := active()
	if log != null:
		log.record(event, context)


func _init(directory: String = LOG_DIR) -> void:
	_directory = directory


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	_next_flush_msec = Time.get_ticks_msec() + FLUSH_MSEC
	record("session.started")


## Changes what is collected from now on, not what is already in history.
## An empty category list means all categories; INFO and above are on by default.
func set_filter(minimum: int, categories: Array[String] = []) -> void:
	_minimum = clampi(minimum, Level.DEBUG, Level.ERROR)
	_categories = categories.duplicate()


func record(event: String, context: Dictionary = {}) -> void:
	var definition: Array = Schema.EVENTS.get(event, [])
	if definition.is_empty() or int(definition[0]) < _minimum:
		return
	if not _categories.is_empty() and not definition[1] in _categories:
		return
	var unix := clampi(int(Time.get_unix_time_from_system()), 0, Schema.MAX_UNIX)
	var row := _schema.build(event, definition, context, unix)
	var now := Time.get_ticks_msec()
	if not _pending.is_empty() and now - _last_record_msec <= DEDUPE_MSEC:
		var previous: Dictionary = _pending[-1]
		if previous["event"] == event and previous["context"] == row["context"] \
				and int(previous["repeat"]) < Schema.MAX_REPEAT:
			previous["repeat"] += 1
			previous["last_unix_s"] = maxi(previous["last_unix_s"], unix)
			_last_record_msec = now
			return
	_pending.append(row)
	_trim_buffer()
	_last_record_msec = now


func _trim_buffer() -> void:
	while _pending.size() > BUFFER_LIMIT:
		_pending.pop_front()
		_discarded_records += 1


func _process(_delta: float) -> void:
	if _worker != null:
		if not _worker.is_alive():
			_finish_worker()
		return
	if _pending.is_empty() or Time.get_ticks_msec() < _next_flush_msec:
		return
	_in_flight = _pending
	_pending = []
	_worker = Thread.new()
	var error := _worker.start(Store.append.bind(_directory, _in_flight))
	if error != OK:
		_worker = null
		_complete_batch(error)


func _finish_worker() -> void:
	if _worker != null:
		var result: Variant = _worker.wait_to_finish()
		_worker = null
		_complete_batch(result if result is int else FAILED)


func _complete_batch(error: int) -> void:
	_write_error = error
	if error != OK:
		# A closed/read-only directory or full disk is not a gameplay failure. Retry
		# with back-off, keeping the newest records in memory, without logging the logger.
		_in_flight.append_array(_pending)
		_pending = _in_flight
		_trim_buffer()
	_in_flight = []
	_next_flush_msec = Time.get_ticks_msec() + (FLUSH_MSEC if error == OK else RETRY_MSEC)


## Synchronous only at explicit barriers (exit, player export, tests).
func flush() -> int:
	_finish_worker()
	if not _pending.is_empty():
		_in_flight = _pending
		_pending = []
		_complete_batch(Store.append(_directory, _in_flight))
	return _write_error


func _exit_tree() -> void:
	record("session.ended")
	flush()


func directory_path() -> String:
	# For local display or the file manager only; this path never goes into the report.
	return ProjectSettings.globalize_path(_directory)


func open_directory() -> int:
	var error := Store.ensure_directory(_directory)
	return OS.shell_open(directory_path()) if error == OK else error


## Explicit local export, with no network code and no reading of save files or raw logs.
## A writable report can still include pending memory records if log writes fail.
func export_report() -> Dictionary:
	flush()
	var history := Store.history(_directory, _schema)
	var rows: Array = history["rows"]
	rows.append_array(_pending)
	var report := {
		"schema": Schema.VERSION,
		"created_unix_s": int(Time.get_unix_time_from_system()),
		"game_version": _game_version(),
		"godot_version": _godot_version(),
		"os": OS.get_name(), # platform family; not distro, username, device or OS build.
		"runtime": _runtime_snapshot(),
		"history": {
			"limit": Store.HISTORY_LIMIT,
			"discarded_this_process": _discarded_records,
			"skipped_units": history["skipped"],
			"read_error": history["error"],
			"write_error": _write_error,
			"pending_records": _pending.size(),
		},
		"events": rows.slice(maxi(0, rows.size() - Store.HISTORY_LIMIT)),
		"privacy": {
			"local_only": true,
			"includes": ["versions", "OS family", "current scene and public location ID",
				"selected progression gates", "pause and dialogue status", "recent structured events"],
			"excludes": ["account or device IDs", "personal paths", "raw engine logs",
				"save contents", "dialogue or narrative text", "choices and knowledge entries"],
			"sharing": "Review this file before sharing it manually. The game does not send it.",
		},
	}
	var error := Store.write_export(_directory, report)
	var partial: bool = _write_error != OK or history["error"] != OK \
		or int(history["skipped"]) > 0 or _discarded_records > 0
	return {"ok": error == OK, "error": error, "partial": partial}


func _on_scene_changed() -> void:
	record("session.scene_changed", {"scene": _scene_id(get_tree().current_scene)})


static func _scene_id(scene: Node) -> String:
	if scene == null:
		return "none"
	match scene.scene_file_path:
		"res://scenes/ui/title_screen.tscn":
			return "title"
		"res://scenes/main/main.tscn":
			return "world"
	return "other"


func _runtime_snapshot() -> Dictionary:
	var tree := get_tree()
	var scene := tree.current_scene
	var id := _scene_id(scene)
	var flags := {}
	var location: Variant = null
	var dialogue := {"active": false, "awaiting_choice": false}
	if id == "world":
		var host := scene.get_node_or_null(^"LocationHost")
		var room: Variant = host.get_current() if host != null else null
		if room != null:
			location = _schema.location_id(room.location_id)
		var state := get_node_or_null(^"/root/GameState")
		if state != null:
			for flag: StringName in [StoryFlags.CLASS_DISMISSED, StoryFlags.LEFT_CLASSROOM]:
				var value: Variant = state.get_flag(flag)
				if value is bool:
					flags[String(flag)] = value
		var controller := scene.get_node_or_null(^"DialogueController")
		if controller != null:
			dialogue["active"] = controller.is_busy()
			var runtime: Variant = controller.get_runtime()
			if runtime != null:
				dialogue["awaiting_choice"] = runtime.is_awaiting_choice()
	return {"scene_id": id, "location_id": location, "flags": flags,
		"paused": tree.paused, "dialogue": dialogue}


static func _game_version() -> String:
	var version: Variant = ProjectSettings.get_setting("application/config/version", "")
	if not (version is String) or version.length() > 64:
		return "unknown"
	var pattern := RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$")
	return version if pattern != null and pattern.search(version) != null else "unknown"


static func _godot_version() -> String:
	var version := Engine.get_version_info()
	var core := "%d.%d.%d" % [version["major"], version["minor"], version["patch"]]
	return core + "-stable" if version["status"] == "stable" else core
