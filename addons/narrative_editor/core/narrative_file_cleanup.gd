extends "res://addons/narrative_editor/core/narrative_file_primitives.gd"
## Editor-only: the middle layer of the narrative file writer (issue #223) - what happens
## to files once a transaction has decided their fate.
##
## A file that must go is first moved into a freshly reserved sibling directory and read
## at its new path (`_isolate_file()`), so what is deleted is provably the file that was
## inspected; backups of a finished pair are only discarded when they still hold the
## original bytes; staged files and quarantine batches are verified as a batch before any
## of them is removed, and anything uncertain is kept and reported in `preserved_paths`.
##
## See `narrative_file_primitives.gd` for the layering and `narrative_file_writer.gd` for
## the guarantees.


## Moves a path into a freshly reserved sibling directory and inspects the actual moved file.
## The optional parent lets a private stage file be quarantined beside its final target.
func _isolate_file(
	path: String, expected_text: String, phase: String, isolation_parent: String = ""
) -> Dictionary:
	if not _path_exists(path):
		return {"ok": false, "source": path, "reason": "源文件不存在"}
	var before := _read_text(path)
	if not bool(before["ok"]):
		return {"ok": false, "source": path, "reason": String(before["reason"])}
	if String(before["text"]) != expected_text:
		return {"ok": false, "source": path, "reason": "隔离前内容已变化"}

	var parent := isolation_parent if not isolation_parent.is_empty() else path.get_base_dir()
	var reservation := _reserve_directory(parent, RECOVERY_PREFIX)
	if not bool(reservation["ok"]):
		return {"ok": false, "source": path, "reason": String(reservation["reason"])}
	var destination := String(reservation["path"]).path_join("held")
	var moved := _move_verified(path, destination, expected_text, "%s_before_isolate_rename" % phase)
	if not bool(moved["ok"]):
		var quarantine_path := String(moved.get("path", ""))
		if bool(moved.get("moved", false)):
			_remember_preserved(quarantine_path)
		else:
			var directory := String(reservation["path"])
			if not _remove_empty_directory(directory):
				_remember_preserved(directory)
		return {
			"ok": false,
			"source": path,
			"path": quarantine_path if not quarantine_path.is_empty() else path,
			"directory": String(reservation["path"]),
			"actual_text": String(moved.get("actual_text", "")),
			"reason": String(moved["reason"]),
		}
	return {
		"ok": true,
		"source": path,
		"path": destination,
		"directory": String(reservation["path"]),
		"expected": expected_text,
	}


## Moves an inspected quarantine copy only if the destination is still absent, then reads it back.
func _move_isolated_file(
	isolated: Dictionary, destination: String, expected_text: String, phase: String
) -> String:
	var source := String(isolated.get("path", ""))
	if source.is_empty() or not _path_exists(source):
		return "隔离文件不存在：%s" % source
	var moved := _move_verified(source, destination, expected_text, phase)
	if not bool(moved["ok"]):
		if bool(moved.get("moved", false)):
			_remember_preserved(String(moved.get("path", destination)))
		else:
			_remember_preserved(source)
		return String(moved["reason"]) + "；恢复材料保留在 " + String(moved.get("path", source))
	_remove_empty_directory(String(isolated.get("directory", "")))
	_forget_preserved(source)
	return ""


## Removes pair backups only after both targets, both fixed backup names, both moved backup
## copies, and all transaction artifact names have been rechecked as one batch.
func _discard_pair_backups(
	targets: Array[String], texts: Array[String], originals: Array[String]
) -> String:
	var backups: Array[String] = []
	var legacy_temps: Array[String] = []
	var target_guards: Array[Dictionary] = []
	for index in targets.size():
		var target := targets[index]
		var conflict := _snapshot_conflict(target, true, texts[index])
		if not conflict.is_empty():
			return _diagnostic("双语备份清理预检", target, conflict, [target, target + BACKUP_SUFFIX])
		var backup := target + BACKUP_SUFFIX
		if not _path_exists(backup):
			return _diagnostic("双语备份清理预检", backup, "原文备份不存在", [target, backup])
		var state := _read_text(backup)
		if not bool(state["ok"]) or String(state["text"]) != originals[index]:
			return _diagnostic(
				"双语备份清理预检", backup, "备份内容已变化或无法读取", [target, backup]
			)
		var temp := target + TEMP_SUFFIX
		if _path_exists(temp):
			return _diagnostic("双语备份清理预检", temp, "发现新的 .saving 文件", [target, backup, temp])
		backups.append(backup)
		legacy_temps.append(temp)
		target_guards.append({"path": target, "exists": true, "text": texts[index]})

	var isolated_backups: Array[Dictionary] = []
	for index in backups.size():
		var isolated := _isolate_file(
			backups[index], originals[index], "pair_backup_cleanup", backups[index].get_base_dir()
		)
		if not bool(isolated["ok"]):
			_preserve_quarantine_records(isolated_backups)
			var materials := _paths_from_records(isolated_backups)
			materials.append_array(backups)
			materials.append_array(targets)
			materials.append(String(isolated.get("path", "")))
			return _diagnostic(
				"双语备份清理隔离", backups[index], String(isolated["reason"]), materials
			)
		isolated_backups.append(isolated)

	var absent_paths: Array[String] = []
	absent_paths.append_array(backups)
	absent_paths.append_array(legacy_temps)
	var verification := _verify_quarantine_batch(
		isolated_backups,
		"pair_backup_cleanup",
		absent_paths,
		target_guards,
		_target_parents(targets)
	)
	if not bool(verification["ok"]):
		var materials := _paths_from_records(isolated_backups)
		materials.append_array(backups)
		materials.append_array(legacy_temps)
		materials.append_array(targets)
		return _diagnostic(
			"双语备份清理复核",
			String(verification.get("path", "")),
			String(verification["reason"]),
			materials
		)

	# Cleanup moves both backups into fresh quarantine paths and checks the entire batch again
	# before its first unlink. Do not split the pair's guard review across individual deletes.
	# A later unlink failure is reported as a warning because an earlier copy may be gone.
	var removed := _remove_quarantine_batch(
		isolated_backups,
		"pair_backup_cleanup",
		absent_paths,
		target_guards,
		_target_parents(targets)
	)
	if not String(removed.get("safety_failure", "")).is_empty():
		var materials := _paths_from_records(isolated_backups)
		materials.append_array(backups)
		materials.append_array(legacy_temps)
		materials.append_array(targets)
		materials.append(String(removed.get("failure_path", "")))
		return _diagnostic(
			"双语备份清理复核",
			String(removed.get("failure_path", "")),
			String(removed["safety_failure"]),
			materials
		)
	for path: String in removed["failed_paths"]:
		warnings.append("双语保存已完成，但恢复材料仍保留在 %s；请手工检查。" % path)
	for path: String in removed["leftover_directories"]:
		warnings.append("双语保存已完成，但隔离目录未能安全移除：%s。" % path)
	return ""


## Single-file validation writes also quarantine and inspect their backup before cleanup.
func _discard_backup_if_matches(
	target: String,
	expected_text: String,
	required: bool,
	expected_target_text: String,
	verify_target: bool = true
) -> String:
	var backup := target + BACKUP_SUFFIX
	if not _path_exists(backup):
		if required:
			return _diagnostic("单文件备份清理", backup, "必需备份不存在", [target, backup])
		return ""
	var state := _read_text(backup)
	if not bool(state["ok"]) or String(state["text"]) != expected_text:
		return _diagnostic("单文件备份清理", backup, "备份内容已变化或无法读取", [target, backup])
	var isolated := _isolate_file(backup, expected_text, "single_backup_cleanup", backup.get_base_dir())
	if not bool(isolated["ok"]):
		return _diagnostic(
			"单文件备份隔离",
			backup,
			String(isolated["reason"]),
			[target, backup, String(isolated.get("path", ""))]
		)
	var absent: Array[String] = [backup, target + TEMP_SUFFIX]
	var guards: Array[Dictionary] = []
	if verify_target:
		guards.append({"path": target, "exists": true, "text": expected_target_text})
	var verification := _verify_quarantine_batch(
		[isolated], "single_backup_cleanup", absent, guards, [target.get_base_dir()]
	)
	if not bool(verification["ok"]):
		return _diagnostic(
			"单文件备份清理复核",
			String(verification.get("path", backup)),
			String(verification["reason"]),
			[target, backup, String(isolated["path"])]
		)
	var removed := _remove_quarantine_batch(
		[isolated],
		"single_backup_cleanup",
		absent,
		guards,
		[target.get_base_dir()]
	)
	if not String(removed.get("safety_failure", "")).is_empty():
		return _diagnostic(
			"单文件备份清理复核",
			String(removed.get("failure_path", backup)),
			String(removed["safety_failure"]),
			[target, backup, String(isolated["path"]), String(removed.get("failure_path", ""))]
		)
	if not removed["failed_paths"].is_empty():
		warnings.append("单文件保存已完成，但恢复材料仍保留在 %s。" % removed["failed_paths"][0])
	for path: String in removed["leftover_directories"]:
		warnings.append("单文件保存已完成，但隔离目录未能安全移除：%s。" % path)
	return ""


func _append_staged_cleanup(
	message: String,
	targets: Array[String],
	paths: Array[String],
	texts: Array[String],
	directories: Array[String]
) -> String:
	var cleanup := _cleanup_staged(targets, paths, texts, directories)
	if bool(cleanup["ok"]):
		return message
	return "%s\n%s" % [message, String(cleanup["message"])]


## Isolates every writer-owned stage before deleting any. A late legacy `.saving`, changed
## stage or unreadable quarantine keeps every still-available candidate copy.
func _cleanup_staged(
	targets: Array[String],
	paths: Array[String],
	texts: Array[String],
	directories: Array[String]
) -> Dictionary:
	var records: Array[Dictionary] = []
	for index in mini(paths.size(), texts.size()):
		if not _path_exists(paths[index]):
			continue
		var parent := directories[index].get_base_dir() if index < directories.size() else ""
		var isolated := _isolate_file(paths[index], texts[index], "saving_cleanup", parent)
		if not bool(isolated["ok"]):
			_preserve_quarantine_records(records)
			var materials := _paths_from_records(records)
			materials.append(paths[index])
			materials.append(String(isolated.get("path", "")))
			materials.append_array(_legacy_transaction_paths(targets))
			return {
				"ok": false,
				"message": _diagnostic(
					"暂存文件清理隔离", paths[index], String(isolated["reason"]), materials
				),
			}
		records.append(isolated)

	for directory: String in directories:
		if not _remove_empty_directory(directory):
			_preserve_quarantine_records(records)
			_remember_preserved(directory)
			var materials := _paths_from_records(records)
			materials.append(directory)
			return {
				"ok": false,
				"message": _diagnostic(
					"暂存目录清理", directory, "目录非空或无法移除；暂存恢复材料仍保留", materials
				),
			}

	var absent_paths: Array[String] = []
	absent_paths.append_array(paths)
	absent_paths.append_array(_legacy_transaction_paths(targets))
	var verification := _verify_quarantine_batch(
		records, "saving_cleanup", absent_paths, [], _target_parents(targets)
	)
	if not bool(verification["ok"]):
		var materials := _paths_from_records(records)
		materials.append_array(absent_paths)
		return {
			"ok": false,
			"message": _diagnostic(
				"暂存文件清理复核",
				String(verification.get("path", "")),
				String(verification["reason"]),
				materials
			),
		}
	var removed := _remove_quarantine_batch(
		records,
		"saving_cleanup",
		absent_paths,
		[],
		_target_parents(targets)
	)
	if not String(removed.get("safety_failure", "")).is_empty():
		var materials := _paths_from_records(records)
		materials.append_array(absent_paths)
		materials.append(String(removed.get("failure_path", "")))
		return {
			"ok": false,
			"message": _diagnostic(
				"暂存文件清理复核",
				String(removed.get("failure_path", "")),
				String(removed["safety_failure"]),
				materials
			),
		}
	if not removed["failed_paths"].is_empty():
		return {
			"ok": false,
			"message": _diagnostic(
				"暂存文件清理",
				String(removed["failed_paths"][0]),
				"隔离暂存文件删除失败",
				removed["failed_paths"]
			),
		}
	if not removed["leftover_directories"].is_empty():
		return {
			"ok": false,
			"message": _diagnostic(
				"暂存文件清理",
				String(removed["leftover_directories"][0]),
				"隔离目录非空或无法安全移除",
				removed["leftover_directories"]
			),
		}
	return {"ok": true, "message": ""}


## Reviews the whole quarantine batch, exposes a deterministic post-review hook, and then
## rechecks the guards. Removal makes a final fresh isolation and content check; only the
## last check-to-unlink interval remains an ordinary filesystem race, not a CAS delete.
func _verify_quarantine_batch(
	records: Array[Dictionary],
	phase: String,
	must_be_absent: Array[String],
	snapshots: Array[Dictionary],
	parents: Array[String] = []
) -> Dictionary:
	for record: Dictionary in records:
		_before_file_operation(
			"%s_before_delete" % phase,
			String(record["path"]),
			String(record["source"])
		)
	var reviewed := _check_quarantine_batch(records, must_be_absent, snapshots, parents)
	if not bool(reviewed["ok"]):
		return reviewed
	for record: Dictionary in records:
		_before_file_operation(
			"%s_after_review_before_unlink" % phase,
			String(record["path"]),
			String(record["source"])
		)
	return _check_quarantine_batch(records, must_be_absent, snapshots, parents)


func _check_quarantine_batch(
	records: Array[Dictionary],
	must_be_absent: Array[String],
	snapshots: Array[Dictionary],
	parents: Array[String]
) -> Dictionary:
	var owned_directories: Array[String] = []
	for record: Dictionary in records:
		var directory := String(record.get("directory", ""))
		if not directory.is_empty() and not owned_directories.has(directory):
			owned_directories.append(directory)
	for parent: String in parents:
		for directory: String in _private_directories(parent):
			if not owned_directories.has(directory):
				_preserve_quarantine_records(records)
				_remember_preserved(directory)
				return {
					"ok": false,
					"path": directory,
					"reason": "清理窗口中出现其他暂存或隔离目录",
				}
	for path: String in must_be_absent:
		if _path_exists(path):
			_preserve_quarantine_records(records)
			_remember_preserved(path)
			return {"ok": false, "path": path, "reason": "清理窗口中同名事务文件重新出现"}
	for snapshot: Dictionary in snapshots:
		var path := String(snapshot["path"])
		var conflict := _snapshot_conflict(
			path, bool(snapshot["exists"]), String(snapshot.get("text", ""))
		)
		if not conflict.is_empty():
			_preserve_quarantine_records(records)
			if _path_exists(path):
				_remember_preserved(path)
			return {"ok": false, "path": path, "reason": conflict}
	for record: Dictionary in records:
		var path := String(record["path"])
		var state := _read_text(path)
		if not bool(state["ok"]):
			_preserve_quarantine_records(records)
			return {
				"ok": false,
				"path": path,
				"reason": "隔离文件删除前无法读取：%s" % String(state["reason"]),
			}
		if String(state["text"]) != String(record["expected"]):
			_preserve_quarantine_records(records)
			return {"ok": false, "path": path, "reason": "隔离文件删除前被外部改写"}
		var directory := String(record.get("directory", ""))
		if not _isolation_directory_contains_only(directory, path.get_file()):
			_preserve_quarantine_records(records)
			_remember_preserved(directory)
			return {"ok": false, "path": directory, "reason": "隔离目录中出现无法确认的其他内容"}
	# Recheck absent names and targets after every isolation copy has been read.
	for path: String in must_be_absent:
		if _path_exists(path):
			_preserve_quarantine_records(records)
			_remember_preserved(path)
			return {"ok": false, "path": path, "reason": "核对隔离文件期间同名事务文件重新出现"}
	for snapshot: Dictionary in snapshots:
		var path := String(snapshot["path"])
		var conflict := _snapshot_conflict(
			path, bool(snapshot["exists"]), String(snapshot.get("text", ""))
		)
		if not conflict.is_empty():
			_preserve_quarantine_records(records)
			if _path_exists(path):
				_remember_preserved(path)
			return {"ok": false, "path": path, "reason": conflict}
	return {"ok": true, "reason": ""}


func _remove_quarantine_batch(
	records: Array[Dictionary],
	phase: String,
	must_be_absent: Array[String],
	snapshots: Array[Dictionary],
	parents: Array[String]
) -> Dictionary:
	var failed_paths: Array[String] = []
	var leftover_directories: Array[String] = []
	var final_records: Array[Dictionary] = []
	var original_paths := _paths_from_records(records)
	var parents_to_check: Array[String] = []
	for parent: String in parents:
		if not parent.is_empty() and not parents_to_check.has(parent):
			parents_to_check.append(parent)

	# The first quarantine copy may still be reachable by another process. Move each member
	# again into a fresh private directory, then inspect the bytes at the new path before any
	# unlink. The original quarantine files are not deleted one-by-one before the whole batch
	# has made it through this move and the final guard check.
	for record: Dictionary in records:
		var source := String(record.get("path", ""))
		var old_directory := String(record.get("directory", ""))
		var parent := old_directory.get_base_dir() if not old_directory.is_empty() else source.get_base_dir()
		if not parent.is_empty() and not parents_to_check.has(parent):
			parents_to_check.append(parent)
		var isolated := _isolate_file(
			source,
			String(record.get("expected", "")),
			"%s_final_delete" % phase,
			parent
		)
		if not bool(isolated["ok"]):
			_preserve_quarantine_records(records)
			_preserve_quarantine_records(final_records)
			var failure_path := String(isolated.get("path", source))
			if not failure_path.is_empty() and _path_exists(failure_path):
				_remember_preserved(failure_path)
			var failed_directory := String(isolated.get("directory", ""))
			if not failed_directory.is_empty() and _path_exists(failed_directory):
				_remember_preserved(failed_directory)
			failed_paths.append(failure_path if not failure_path.is_empty() else source)
			return {
				"failed_paths": failed_paths,
				"leftover_directories": leftover_directories,
				"safety_failure": "最终删除隔离失败：%s" % String(isolated.get("reason", "无法确认移动后的文件")),
				"failure_path": failure_path,
			}
		final_records.append(isolated)

	# Retire only the now-empty first-round directories. If an unknown entry appeared, keep
	# every final candidate and report the directory instead of cleaning any member.
	var old_directories: Array[String] = []
	for record: Dictionary in records:
		var directory := String(record.get("directory", ""))
		if not directory.is_empty() and not old_directories.has(directory):
			old_directories.append(directory)
	for directory: String in old_directories:
		if not _remove_empty_directory(directory):
			leftover_directories.append(directory)
			_remember_preserved(directory)
	if not leftover_directories.is_empty():
		_preserve_quarantine_records(records)
		_preserve_quarantine_records(final_records)
		for directory: String in leftover_directories:
			_remember_preserved(directory)
		return {"failed_paths": failed_paths, "leftover_directories": leftover_directories}

	var absent_paths: Array[String] = []
	for path: String in must_be_absent:
		if not absent_paths.has(path):
			absent_paths.append(path)
	for path: String in original_paths:
		if not absent_paths.has(path):
			absent_paths.append(path)
	for record: Dictionary in final_records:
		_before_file_operation(
			"%s_after_final_isolate_before_unlink" % phase,
			String(record.get("source", "")),
			String(record.get("path", ""))
		)
	var final_review := _check_quarantine_batch(
		final_records, absent_paths, snapshots, parents_to_check
	)
	if not bool(final_review["ok"]):
		_preserve_quarantine_records(records)
		_preserve_quarantine_records(final_records)
		var failure_path := String(final_review.get("path", ""))
		if not failure_path.is_empty() and _path_exists(failure_path):
			_remember_preserved(failure_path)
		if not failure_path.is_empty():
			failed_paths.append(failure_path)
		return {
			"failed_paths": failed_paths,
			"leftover_directories": leftover_directories,
			"safety_failure": String(final_review.get("reason", "最终批量复核失败")),
			"failure_path": failure_path,
		}

	# The final review covers all members and guards before the first unlink. The remaining
	# check-to-delete interval is an ordinary filesystem race: Godot exposes no CAS unlink.
	for index in final_records.size():
		var record: Dictionary = final_records[index]
		var path := String(record["path"])
		if not _discard(path):
			for pending_index in range(index, final_records.size()):
				var pending: Dictionary = final_records[pending_index]
				var pending_path := String(pending["path"])
				if _path_exists(pending_path):
					if not failed_paths.has(pending_path):
						failed_paths.append(pending_path)
					_remember_preserved(pending_path)
				var pending_directory := String(pending.get("directory", ""))
				if not pending_directory.is_empty() and _path_exists(pending_directory):
					if not leftover_directories.has(pending_directory):
						leftover_directories.append(pending_directory)
						_remember_preserved(pending_directory)
			var failure := {
				"failed_paths": failed_paths,
				"leftover_directories": leftover_directories,
			}
			if not _path_exists(path):
				failure["safety_failure"] = "最终隔离文件在删除调用时消失；无法确认删除是否由本次操作完成"
				failure["failure_path"] = path
			return failure
		_forget_preserved(path)
		var directory := String(record.get("directory", ""))
		if not _remove_empty_directory(directory):
			leftover_directories.append(directory)
			_remember_preserved(directory)
	return {"failed_paths": failed_paths, "leftover_directories": leftover_directories}
