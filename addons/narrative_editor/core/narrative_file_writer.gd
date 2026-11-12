extends RefCounted
## Editor-only: write content files without losing a concurrent editor's bytes.
##
## Pair saves compare the open snapshot before staging and again before each replacement.
## Staged files and files awaiting cleanup live in sibling directories reserved with mkdir;
## after a move, the writer reads the file at its new path before deciding what to do with it.
## Sibling directories keep moves on the source volume and their unique names prevent ordinary
## path collisions. The public Godot API still has no cross-platform atomic no-replace rename
## or compare-and-swap unlink: a process that can reach a private path can race the final
## existence/content check and the following rename or delete. This code narrows and reports
## those windows; it cannot claim to eliminate them.
##
## `.saving` and `.backup` beside a target remain recognized as legacy/recovery artifacts.
## New staging uses a uniquely reserved sibling directory rather than opening a shared
## `<target>.saving` path, so a late `.saving` is never mistaken for this transaction's file.
##
## `_before_file_operation()`, `_write_bytes()` and `_rename()` are deterministic test seams.

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


## Writes one validation file through the same guarded replacement path as a pair save.
func write_atomic(target: String, text: String) -> String:
	_begin_operation()
	var artifact := _preflight_artifact(target)
	if not artifact.is_empty():
		return artifact

	var expected_exists := _path_exists(target)
	var expected_text := ""
	if expected_exists:
		var current := _read_text(target)
		if not bool(current["ok"]):
			return _diagnostic("单文件保存预检", target, String(current["reason"]), [target])
		expected_text = String(current["text"])

	var stage := _new_stage(target)
	if not bool(stage["ok"]):
		return _diagnostic("单文件暂存目录", target, String(stage["reason"]), [target])
	var temp := String(stage["path"])
	var stage_dir := String(stage["directory"])
	var failure := _write_bytes(temp, text)
	if not failure.is_empty():
		var removed := _remove_empty_directory(stage_dir)
		var material_paths: Array[String] = [target, temp, stage_dir]
		if not removed:
			_remember_preserved(stage_dir)
		return _diagnostic("单文件暂存", temp, failure, material_paths)

	var staged := _read_text(temp)
	if not bool(staged["ok"]) or String(staged["text"]) != text:
		return _append_staged_cleanup(
			_diagnostic(
				"单文件暂存复核",
				temp,
				String(staged.get("reason", "暂存内容与候选文本不同")),
				[target, temp]
			),
			[target], [temp], [text], [stage_dir]
		)

	failure = _replace(target, temp, text, expected_exists, expected_text)
	if not failure.is_empty():
		return _append_staged_cleanup(failure, [target], [temp], [text], [stage_dir])
	if not _remove_empty_directory(stage_dir):
		warnings.append("保存已完成，但暂存目录无法安全移除，保留在 %s。" % stage_dir)

	if expected_exists:
		failure = _discard_backup_if_matches(target, expected_text, true, text)
		if not failure.is_empty():
			return failure
	return ""


## Checks every original and legacy artifact before validation writes files.
func check_pair(targets: Array[String], originals: Array[String]) -> String:
	if targets.size() != originals.size():
		return "内部错误：目标文件和原文的数量不一致。"
	for index in targets.size():
		var target := targets[index]
		var conflict := _snapshot_conflict(target, true, originals[index])
		if not conflict.is_empty():
			return _diagnostic("保存预检", target, conflict, [target])
		var artifact := _preflight_artifact(target)
		if not artifact.is_empty():
			return artifact
	return ""


## Stages both files, replaces them one by one, and retains all recoverable bytes if a
## conflict appears before the pair's cleanup commit point.
func save_pair(targets: Array[String], texts: Array[String], originals: Array[String]) -> String:
	_begin_operation()
	if targets.size() != texts.size() or targets.size() != originals.size():
		return "内部错误：目标文件、新文本和原文的数量不一致。"
	if targets.is_empty():
		return ""
	var failure := check_pair(targets, originals)
	if not failure.is_empty():
		return failure

	var staged_paths: Array[String] = []
	var staged_texts: Array[String] = []
	var stage_directories: Array[String] = []
	for index in targets.size():
		var target := targets[index]
		var legacy_temp := target + TEMP_SUFFIX
		if _path_exists(legacy_temp):
			return _append_staged_cleanup(
				_diagnostic(
					"双语暂存",
					legacy_temp,
					"保存预检后出现新的 .saving 文件；未改写它",
					[legacy_temp, target]
				),
				targets,
				staged_paths,
				staged_texts,
				stage_directories
			)

		var stage := _new_stage(target)
		if not bool(stage["ok"]):
			return _append_staged_cleanup(
				_diagnostic("双语暂存目录", target, String(stage["reason"]), [target]),
				targets,
				staged_paths,
				staged_texts,
				stage_directories
			)
		var temp := String(stage["path"])
		var stage_dir := String(stage["directory"])
		failure = _write_bytes(temp, texts[index])
		if not failure.is_empty():
			var removed := _remove_empty_directory(stage_dir)
			var materials: Array[String] = [target, temp, stage_dir]
			if not removed:
				_remember_preserved(stage_dir)
			return _append_staged_cleanup(
				_diagnostic("双语暂存", temp, failure, materials),
				targets,
				staged_paths,
				staged_texts,
				stage_directories
			)

		# A successful write is not proof that the stage still contains our bytes. Register it
		# before reading so failure cleanup can isolate and inspect the actual moved file.
		staged_paths.append(temp)
		staged_texts.append(texts[index])
		stage_directories.append(stage_dir)
		var staged := _read_text(temp)
		if not bool(staged["ok"]) or String(staged["text"]) != texts[index]:
			return _append_staged_cleanup(
				_diagnostic(
					"双语暂存复核",
					temp,
					String(staged.get("reason", "暂存内容与候选文本不同")),
					[target, temp]
				),
				targets,
				staged_paths,
				staged_texts,
				stage_directories
			)

	var replaced: Array[int] = []
	for index in targets.size():
		failure = _replace(targets[index], staged_paths[index], texts[index], true, originals[index])
		if not failure.is_empty():
			var rollback := _rollback(targets, texts, originals, replaced, failure)
			return _append_staged_cleanup(
				rollback, targets, staged_paths, staged_texts, stage_directories
			)
		replaced.append(index)
		if not _remove_empty_directory(stage_directories[index]):
			failure = _diagnostic(
				"双语暂存目录清理",
				stage_directories[index],
				"安装后目录中出现其他内容或无法移除；未继续清理备份",
				[targets[index], stage_directories[index], targets[index] + BACKUP_SUFFIX]
			)
			var rollback := _rollback(targets, texts, originals, replaced, failure)
			return _append_staged_cleanup(
				rollback, targets, staged_paths, staged_texts, stage_directories
			)

	# Both backups stay recoverable until both targets, both backup copies, all legacy names,
	# and the complete quarantine batch have been checked. The helper removes neither backup
	# until all checks have passed.
	failure = _discard_pair_backups(targets, texts, originals)
	if not failure.is_empty():
		return failure
	return ""


func _rollback(
	targets: Array[String],
	texts: Array[String],
	originals: Array[String],
	replaced: Array[int],
	failure: String
) -> String:
	if replaced.is_empty():
		return "%s 没有内容文件被替换。" % failure
	var restore_errors: Array[String] = []
	for offset in replaced.size():
		var index: int = replaced[replaced.size() - 1 - offset]
		var restore_failure := _restore_written_target(
			targets[index], texts[index], originals[index]
		)
		if not restore_failure.is_empty():
			restore_errors.append(restore_failure)
	if restore_errors.is_empty():
		return "%s 已安全还原本次替换的文件。" % failure
	var details := "\n".join(PackedStringArray(restore_errors))
	return "%s 回滚期间检测到外部变化或无法确认，未覆盖相关内容。请保留目标与恢复材料，并手工比对恢复：\n%s" % [failure, details]


## Moves a verified stage to its target, preserving the displaced snapshot as `.backup`.
## Every move checks both names, checks the source after the injected operation seam, and
## verifies the actual bytes at the destination. This is still not an OS-level CAS.
func _replace(
	target: String,
	temp: String,
	new_text: String,
	expected_exists: bool,
	expected_text: String
) -> String:
	var backup := target + BACKUP_SUFFIX
	var legacy_temp := target + TEMP_SUFFIX
	if _path_exists(backup):
		return _diagnostic("目标替换前", backup, "已有 .backup，拒绝覆盖", [target, backup, temp])
	if _path_exists(legacy_temp):
		return _diagnostic("目标替换前", legacy_temp, "出现新的 .saving 文件，拒绝继续", [target, legacy_temp, temp])
	var staged := _read_text(temp)
	if not bool(staged["ok"]):
		return _diagnostic("目标替换前", temp, String(staged["reason"]), [target, temp, backup])
	if String(staged["text"]) != new_text:
		return _diagnostic("目标替换前", temp, "暂存文件已被改写", [target, temp, backup])
	var conflict := _snapshot_conflict(target, expected_exists, expected_text)
	if not conflict.is_empty():
		return _diagnostic("目标替换前", target, conflict, [target, backup, temp])

	if expected_exists:
		var displace := _move_verified(
			target, backup, expected_text, "replace_target_to_backup"
		)
		if not bool(displace["ok"]):
			return _diagnostic(
				"替换时备份原文",
				target,
				String(displace["reason"]),
				[target, backup, temp, String(displace.get("path", ""))]
			)

	if _path_exists(target):
		var reason := "目标在暂存文件换入前重新出现；未改写它"
		if expected_exists:
			var restore_failure := _restore_displaced_target(target, expected_text)
			if not restore_failure.is_empty():
				reason += "；" + restore_failure
		return _diagnostic("安装新文件", target, reason, [target, backup, temp])
	if _path_exists(legacy_temp):
		var reason := "外部 .saving 在目标移开后出现；未用它继续保存"
		if expected_exists:
			var restore_failure := _restore_displaced_target(target, expected_text)
			if not restore_failure.is_empty():
				reason += "；" + restore_failure
		return _diagnostic("安装新文件", legacy_temp, reason, [target, backup, temp, legacy_temp])

	staged = _read_text(temp)
	if not bool(staged["ok"]) or String(staged["text"]) != new_text:
		var reason := String(staged.get("reason", "暂存内容在换入前已改变"))
		if expected_exists:
			var restore_failure := _restore_displaced_target(target, expected_text)
			if not restore_failure.is_empty():
				reason += "；" + restore_failure
		return _diagnostic("安装新文件", temp, reason, [target, backup, temp])

	var install := _move_verified(temp, target, new_text, "install_staged_target")
	if not bool(install["ok"]):
		var reason := String(install["reason"])
		if expected_exists:
			var restore_failure := _restore_displaced_target(target, expected_text)
			if not restore_failure.is_empty():
				reason += "；" + restore_failure
		return _diagnostic(
			"安装新文件", target, reason, [target, backup, temp, String(install.get("path", ""))]
		)
	return ""


## Restores a displaced original only when the target name is still vacant.
func _restore_displaced_target(target: String, expected_text: String) -> String:
	var backup := target + BACKUP_SUFFIX
	if not _path_exists(backup):
		return "备份不存在：%s" % backup
	if _path_exists(target):
		return "目标已重新出现，未覆盖；备份保留在 " + backup
	var moved := _move_verified(backup, target, expected_text, "restore_displaced_backup")
	if not bool(moved["ok"]):
		return String(moved["reason"]) + "；检查 " + backup + " 与 " + target
	return ""


## Rollback moves the transaction's installed target aside, inspects the moved bytes, then
## restores the original only if no external target appeared. A mismatch remains in quarantine.
func _restore_written_target(target: String, new_text: String, original_text: String) -> String:
	var backup := target + BACKUP_SUFFIX
	if not _path_exists(backup):
		return _diagnostic("回滚前核对备份", backup, "原文备份不存在", [target, backup])
	var saved := _read_text(backup)
	if not bool(saved["ok"]) or String(saved["text"]) != original_text:
		return _diagnostic("回滚前核对备份", backup, "备份内容已变化或无法读取", [target, backup])
	var conflict := _snapshot_conflict(target, true, new_text)
	if not conflict.is_empty():
		return _diagnostic("回滚前核对目标", target, conflict, [target, backup])

	var isolated_target := _isolate_file(target, new_text, "rollback_target", target.get_base_dir())
	if not bool(isolated_target["ok"]):
		return _diagnostic(
			"回滚目标隔离",
			target,
			String(isolated_target["reason"]),
			[target, backup, String(isolated_target.get("path", ""))]
		)

	_before_file_operation("rollback_after_target_isolate", String(isolated_target["path"]), target)
	if _path_exists(target):
		_preserve_quarantine_records([isolated_target])
		return _diagnostic(
			"回滚恢复前",
			target,
			"外部进程在目标隔离后重新创建了同名文件；未覆盖它",
			[target, backup, String(isolated_target["path"])]
		)
	if _path_exists(target + TEMP_SUFFIX):
		_preserve_quarantine_records([isolated_target])
		_remember_preserved(target + TEMP_SUFFIX)
		return _diagnostic(
			"回滚恢复前",
			target + TEMP_SUFFIX,
			"出现新的 .saving 文件；未继续清理恢复材料",
			[target, backup, String(isolated_target["path"]), target + TEMP_SUFFIX]
		)

	var isolated_backup := _isolate_file(backup, original_text, "rollback_backup", target.get_base_dir())
	if not bool(isolated_backup["ok"]):
		_preserve_quarantine_records([isolated_target])
		return _diagnostic(
			"回滚备份隔离",
			backup,
			String(isolated_backup["reason"]),
			[target, backup, String(isolated_target["path"]), String(isolated_backup.get("path", ""))]
		)
	if _path_exists(target) or _path_exists(backup) or _path_exists(target + TEMP_SUFFIX):
		_preserve_quarantine_records([isolated_target, isolated_backup])
		for artifact: String in [target, backup, target + TEMP_SUFFIX]:
			if _path_exists(artifact):
				_remember_preserved(artifact)
		return _diagnostic(
			"回滚原文移回前",
			target,
			"目标、.backup 或 .saving 在隔离后被重新创建；未覆盖任何一方",
			[
				target,
				backup,
				target + TEMP_SUFFIX,
				String(isolated_target["path"]),
				String(isolated_backup["path"]),
			]
		)

	var restore := _move_isolated_file(
		isolated_backup, target, original_text, "rollback_restore_original"
	)
	if not restore.is_empty():
		_preserve_quarantine_records([isolated_target, isolated_backup])
		return _diagnostic(
			"回滚原文移回目标",
			target,
			restore,
			[target, backup, String(isolated_target["path"]), String(isolated_backup["path"])]
		)

	var verify_target: Array[Dictionary] = [
		{"path": target, "exists": true, "text": original_text}
	]
	var verification := _verify_quarantine_batch(
		[isolated_target],
		"rollback_candidate_cleanup",
		[backup, target + TEMP_SUFFIX],
		verify_target,
		[target.get_base_dir()]
	)
	if not bool(verification["ok"]):
		return _diagnostic(
			"回滚后清理事务目标",
			String(verification.get("path", target)),
			String(verification["reason"]),
			[target, String(isolated_target["path"])]
		)
	var removed := _remove_quarantine_batch(
		[isolated_target],
		"rollback_candidate_cleanup",
		[backup, target + TEMP_SUFFIX],
		verify_target,
		[target.get_base_dir()]
	)
	if not String(removed.get("safety_failure", "")).is_empty():
		return _diagnostic(
			"回滚后清理事务目标",
			String(removed.get("failure_path", target)),
			String(removed["safety_failure"]),
			[target, backup, String(isolated_target["path"]), String(removed.get("failure_path", ""))]
		)
	if not removed["failed_paths"].is_empty():
		return _diagnostic(
			"回滚后清理事务目标",
			String(removed["failed_paths"][0]),
			"隔离文件删除失败",
			[target, String(isolated_target["path"])]
		)
	if not removed["leftover_directories"].is_empty():
		_remember_preserved(String(removed["leftover_directories"][0]))
		return _diagnostic(
			"回滚后清理事务目标",
			String(removed["leftover_directories"][0]),
			"隔离目录无法安全移除",
			[target, String(isolated_target["path"]), String(removed["leftover_directories"][0])]
		)
	return ""


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


## Leftovers from interrupted saves. Recovery directories are reported but never auto-deleted.
func leftovers(targets: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for target: String in targets:
		for suffix: String in [TEMP_SUFFIX, BACKUP_SUFFIX]:
			var artifact := target + suffix
			if _path_exists(artifact) and not found.has(artifact):
				found.append(artifact)
		for directory: String in _private_directories(target.get_base_dir()):
			if not found.has(directory):
				found.append(directory)
	return found


## Restores a missing target from its legacy `.backup`, but never overwrites a newly-created target.
func recover_missing(targets: Array[String]) -> Array[String]:
	_begin_operation()
	var recovered: Array[String] = []
	for target: String in targets:
		var backup := target + BACKUP_SUFFIX
		if not _path_exists(backup) or _path_exists(target):
			continue
		if _has_recovery_directory(target.get_base_dir()):
			continue
		var backup_state := _read_text(backup)
		if not bool(backup_state["ok"]):
			warnings.append(
				_diagnostic("崩溃恢复预检", backup, String(backup_state["reason"]), [backup])
			)
			continue
		var expected := String(backup_state["text"])
		var isolated := _isolate_file(backup, expected, "crash_recovery_backup", target.get_base_dir())
		if not bool(isolated["ok"]):
			warnings.append(
				_diagnostic(
					"崩溃恢复隔离",
					backup,
					String(isolated["reason"]),
					[backup, String(isolated.get("path", ""))]
				)
			)
			continue
		var move_failure := _move_isolated_file(isolated, target, expected, "crash_recovery_restore")
		if move_failure.is_empty():
			recovered.append(target)
		else:
			warnings.append(
				_diagnostic("崩溃恢复", target, move_failure, [backup, String(isolated["path"])])
			)
	return recovered


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
