extends RefCounted
## Editor-only: the bottom layer of the narrative file writer (issue #223).
##
## `narrative_file_writer.gd` was one 1368-line script; it is three layers of one object
## now, each extending the one below, so a subclass that overrides a seam still overrides
## it for every layer (the tests in `tests/narrative_editor_test.gd` do exactly that):
##
## - **this file** - the filesystem seams (`_write_bytes()`, `_read_text()`, `_rename()`,
##   `_discard()`, `_before_file_operation()`, `_remove_empty_directory()`), verified moves,
##   reserved sibling directories, diagnostics and the bookkeeping of preserved paths;
## - `narrative_file_cleanup.gd` - isolating, discarding and quarantining files once a
##   transaction is decided;
## - `narrative_file_writer.gd` - the transactions themselves: guarded single writes, pair
##   saves, rollback and crash recovery. Callers preload only that one.
##
## The guarantees and their limits are stated once, in `narrative_file_writer.gd`.

const TEMP_SUFFIX := ".saving"
const BACKUP_SUFFIX := ".backup"
const STAGE_PREFIX := ".ne-stage-"
const RECOVERY_PREFIX := ".ne-recovery-"
const DIRECTORY_ATTEMPTS := 64

var warnings: Array[String] = []
## Quarantine files deliberately retained after a conflict or an uncertain cleanup.
var preserved_paths: Array[String] = []

var _operation_id: String = ""
var _directory_serial: int = 0


func _move_verified(from_path: String, to_path: String, expected_text: String, phase: String) -> Dictionary:
	if not _path_exists(from_path):
		return {"ok": false, "moved": false, "reason": "源文件不存在：%s" % from_path}
	if _path_exists(to_path):
		return {"ok": false, "moved": false, "reason": "目标路径已存在，未改写：%s" % to_path}
	_before_file_operation(phase, from_path, to_path)
	if _path_exists(to_path):
		return {"ok": false, "moved": false, "reason": "检查后目标路径重新出现，未改写：%s" % to_path}
	var source := _read_text(from_path)
	if not bool(source["ok"]):
		return {
			"ok": false,
			"moved": false,
			"reason": "移动前无法读取源文件 %s：%s" % [from_path, String(source["reason"])],
		}
	if String(source["text"]) != expected_text:
		return {"ok": false, "moved": false, "reason": "移动前源文件内容已变化：%s" % from_path}
	var code := _rename(from_path, to_path)
	if code != OK:
		return {
			"ok": false,
			"moved": false,
			"reason": "移动失败（错误码 %d）：%s -> %s" % [code, from_path, to_path],
		}
	var actual := _read_text(to_path)
	if not bool(actual["ok"]):
		return {
			"ok": false,
			"moved": true,
			"path": to_path,
			"reason": "移动后无法读取实际文件：%s" % String(actual["reason"]),
		}
	if String(actual["text"]) != expected_text:
		return {
			"ok": false,
			"moved": true,
			"path": to_path,
			"actual_text": String(actual["text"]),
			"reason": "移动后发现实际文件内容与预期不同",
		}
	return {"ok": true, "moved": true, "path": to_path, "reason": ""}


func _reserve_directory(parent: String, prefix: String) -> Dictionary:
	for attempt in DIRECTORY_ATTEMPTS:
		_directory_serial += 1
		var name := "%s%s-%d" % [prefix, _operation_id, _directory_serial]
		var directory := parent.path_join(name)
		var code := _make_dir(directory)
		if code == OK:
			return {"ok": true, "directory": directory, "path": directory}
		if not DirAccess.dir_exists_absolute(globalize(directory)):
			return {
				"ok": false,
				"reason": "无法创建专用目录 %s（错误码 %d）" % [directory, code],
			}
	return {"ok": false, "reason": "专用目录名连续冲突，未移动任何文件：%s" % parent}


func _new_stage(target: String) -> Dictionary:
	var reservation := _reserve_directory(target.get_base_dir(), STAGE_PREFIX)
	if not bool(reservation["ok"]):
		return reservation
	var directory := String(reservation["directory"])
	return {
		"ok": true,
		"directory": directory,
		"path": directory.path_join(target.get_file() + TEMP_SUFFIX),
	}


func _preflight_artifact(target: String) -> String:
	for artifact: String in [target + TEMP_SUFFIX, target + BACKUP_SUFFIX]:
		if _path_exists(artifact):
			return _diagnostic("事务预检", artifact, "发现未处理的 .saving 或 .backup 文件", [target, artifact])
	for directory: String in _private_directories(target.get_base_dir()):
		return _diagnostic("事务预检", directory, "发现上次保存留下的隔离恢复目录", [target, directory])
	return ""


func _private_directories(parent: String) -> Array[String]:
	var found: Array[String] = []
	var directory := DirAccess.open(parent)
	if directory == null:
		return found
	directory.include_hidden = true
	directory.include_navigational = false
	if directory.list_dir_begin() != OK:
		return found
	var name := directory.get_next()
	while not name.is_empty():
		if directory.current_is_dir() and (
			name.begins_with(STAGE_PREFIX) or name.begins_with(RECOVERY_PREFIX)
		):
			found.append(parent.path_join(name))
		name = directory.get_next()
	directory.list_dir_end()
	return found


func _has_recovery_directory(parent: String) -> bool:
	for directory: String in _private_directories(parent):
		if directory.get_file().begins_with(RECOVERY_PREFIX):
			return true
	return false


func _isolation_directory_contains_only(directory_path: String, expected_file: String) -> bool:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.include_hidden = true
	directory.include_navigational = false
	if directory.list_dir_begin() != OK:
		return false
	var found_expected := false
	var has_unknown := false
	var name := directory.get_next()
	while not name.is_empty():
		if name == expected_file and not directory.current_is_dir():
			found_expected = true
		else:
			has_unknown = true
		name = directory.get_next()
	directory.list_dir_end()
	return found_expected and not has_unknown


func _diagnostic(stage: String, path: String, reason: String, materials: Array[String]) -> String:
	var related: Array[String] = []
	if not path.is_empty():
		related.append(path)
	for item: String in materials:
		if not item.is_empty() and not related.has(item):
			related.append(item)
	var retained: Array[String] = []
	for item: String in preserved_paths:
		if _path_exists(item) and not retained.has(item):
			retained.append(item)
	var retained_text := "无可确认的隔离副本"
	if not retained.is_empty():
		retained_text = "、".join(PackedStringArray(retained))
	var related_text := "无"
	if not related.is_empty():
		related_text = "、".join(PackedStringArray(related))
	return (
		"保存已停止：%s 阶段，路径 %s：%s。相关路径：%s。已隔离保留：%s。请手工比对恢复。"
		% [stage, path, reason, related_text, retained_text]
	)


func _snapshot_conflict(target: String, expected_exists: bool, expected_text: String) -> String:
	var exists := _path_exists(target)
	if expected_exists and not exists:
		return "文件在打开后已被删除或移走"
	if not expected_exists and exists:
		return "目标文件在保存期间新建"
	if not exists:
		return ""
	var current := _read_text(target)
	if not bool(current["ok"]):
		if not _path_exists(target):
			return "文件在检查时已被删除或移走"
		return "无法读取文件：%s" % String(current["reason"])
	if String(current["text"]) != expected_text:
		return "文件在打开后已被外部修改"
	return ""


func _begin_operation() -> void:
	warnings.clear()
	preserved_paths.clear()
	_directory_serial = 0
	_operation_id = "%d-%d" % [Time.get_ticks_usec(), randi()]


func _before_file_operation(_phase: String, _source: String, _destination: String) -> void:
	pass


func _make_dir(path: String) -> Error:
	return DirAccess.make_dir_absolute(globalize(path))


func _path_exists(path: String) -> bool:
	if path.is_empty():
		return false
	var absolute := globalize(path)
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute) or _is_link(path)


func _is_link(path: String) -> bool:
	var directory := DirAccess.open(path.get_base_dir())
	return directory != null and directory.is_link(path.get_file())


func _remember_preserved(path: String) -> void:
	if not path.is_empty() and not preserved_paths.has(path):
		preserved_paths.append(path)


func _forget_preserved(path: String) -> void:
	preserved_paths.erase(path)


## Removes only an empty directory. A late file or unknown entry makes this fail untouched.
func _remove_empty_directory(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(globalize(path)):
		return true
	return DirAccess.remove_absolute(globalize(path)) == OK


func _legacy_transaction_paths(targets: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	for target: String in targets:
		for suffix: String in [TEMP_SUFFIX, BACKUP_SUFFIX]:
			var path := target + suffix
			if not paths.has(path):
				paths.append(path)
	return paths


func _target_parents(targets: Array[String]) -> Array[String]:
	var parents: Array[String] = []
	for target: String in targets:
		var parent := target.get_base_dir()
		if not parents.has(parent):
			parents.append(parent)
	return parents


func _paths_from_records(records: Array[Dictionary]) -> Array[String]:
	var paths: Array[String] = []
	for record: Dictionary in records:
		var path := String(record.get("path", ""))
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	return paths


func _preserve_quarantine_records(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var path := String(record.get("path", ""))
		if _path_exists(path):
			_remember_preserved(path)
		var source := String(record.get("source", ""))
		if _path_exists(source):
			_remember_preserved(source)


# --- filesystem -------------------------------------------------------------


## Refuses to open a path that appeared after its initial check. Staging paths are private
## sibling-directory entries; the check/open interval remains a documented non-CAS window.
func _write_bytes(target: String, text: String) -> String:
	if _path_exists(target):
		return "暂存路径已经存在，拒绝改写：%s" % target
	_before_file_operation("write_stage_before_open", target, "")
	if _path_exists(target):
		return "暂存路径在打开前重新出现，拒绝改写：%s" % target
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "%s（错误码 %d）" % [target, FileAccess.get_open_error()]
	file.store_string(text)
	file.flush()
	file.close()
	if not FileAccess.file_exists(target):
		return "%s 写入后不存在" % target
	return ""


func _read_text(target: String) -> Dictionary:
	if _is_link(target):
		return {"ok": false, "reason": "路径是符号链接或重解析点"}
	if not FileAccess.file_exists(target):
		return {"ok": false, "reason": "文件不存在或不是普通文件"}
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "无法打开（错误码 %d）" % FileAccess.get_open_error()}
	var initial_length := file.get_length()
	var text := file.get_as_text()
	var final_length := file.get_length()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"ok": false, "reason": "读取失败（错误码 %d）" % read_error}
	if final_length != initial_length:
		return {"ok": false, "reason": "读取期间文件长度发生变化"}
	return {"ok": true, "text": text}


func _rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(globalize(from_path), globalize(to_path))


func _discard(target: String) -> bool:
	if not _path_exists(target):
		return false
	return DirAccess.remove_absolute(globalize(target)) == OK


static func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
