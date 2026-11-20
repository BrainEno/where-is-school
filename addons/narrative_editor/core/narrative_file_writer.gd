extends "res://addons/narrative_editor/core/narrative_file_cleanup.gd"
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
##
## The script is the top of three layers (issue #223): the transactions are here; what
## happens to files afterwards is `narrative_file_cleanup.gd`, and the filesystem seams
## and verified moves are `narrative_file_primitives.gd`. They are one object, so an
## override of a seam in a subclass of this script applies to all three.


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
