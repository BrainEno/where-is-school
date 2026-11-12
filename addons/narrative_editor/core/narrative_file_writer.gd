extends RefCounted
## Editor-only: write content files without ever leaving one language behind.
##
## Paired saves use an optimistic snapshot: the original texts passed by the store must
## still be on disk before staging starts and again immediately before each target moves to
## its backup. This narrows the window in which another editor can race a save, but ordinary
## file operations are not a compare-and-swap; a process can still write between a check
## and a rename.
##
## Every target is staged next to itself, then replaced through a backup. If a later step
## fails, a target is restored only while it still contains the text this writer installed.
## A changed or unreadable target is left in place; during rollback, any backup is retained
## as well so an author's concurrent work is not destroyed.
##
## `_write_bytes()` and `_rename()` are seams the tests replace, so rollback is exercised
## against the real filesystem implementation rather than a fake transaction.

const TEMP_SUFFIX := ".saving"
const BACKUP_SUFFIX := ".backup"


## Writes `text` to `target`, replacing its current contents only if the staged operation
## succeeds. Returns "" on success, or a message that names the file and the reason.
func write_atomic(target: String, text: String) -> String:
	var temp := target + TEMP_SUFFIX
	var backup := target + BACKUP_SUFFIX
	if FileAccess.file_exists(temp):
		return "发现未处理的临时文件 %s；未改写它，请先检查并手工处理。" % temp
	if FileAccess.file_exists(backup):
		return "发现未处理的备份文件 %s；未改写它，请先检查并手工处理。" % backup

	var expected_exists := FileAccess.file_exists(target)
	var expected_text := ""
	if expected_exists:
		var current := _read_text(target)
		if not bool(current["ok"]):
			return "无法读取 %s：%s。" % [target, String(current["reason"])]
		expected_text = String(current["text"])

	var failure := _write_bytes(temp, text)
	if not failure.is_empty():
		return _with_temp_cleanup(
			"写临时文件失败：%s。" % failure,
			[temp],
			[text]
		)
	failure = _replace(target, temp, text, expected_exists, expected_text)
	if not failure.is_empty():
		return _with_temp_cleanup(failure, [temp], [text])

	var installed := _read_text(target)
	if not bool(installed["ok"]) or String(installed["text"]) != text:
		var conflict := (
			"保存已停止：%s 在替换期间已被修改、删除或无法读取；未改写当前内容。"
			% target
		)
		if expected_exists:
			conflict += " " + _restore_written_target(target, text, expected_text)
		return conflict
	if expected_exists:
		failure = _discard_backup_if_matches(target, expected_text, true)
		if not failure.is_empty():
			return failure
	return ""


## Checks every original before the writer creates any staging file. The store calls this
## before candidate validation (which itself uses temporary files); save_pair repeats the
## check immediately before staging to close that intervening gap.
func check_pair(targets: Array[String], originals: Array[String]) -> String:
	if targets.size() != originals.size():
		return "内部错误：目标文件和原文的数量不一致。"
	for index in targets.size():
		var target := targets[index]
		var conflict := _snapshot_conflict(target, true, originals[index])
		if not conflict.is_empty():
			return conflict
		for suffix: String in [TEMP_SUFFIX, BACKUP_SUFFIX]:
			var artifact := target + suffix
			if FileAccess.file_exists(artifact):
				return "保存已停止：发现未处理的文件 %s；未改写它，请先检查并手工处理。" % artifact
	return ""


## Stages every target, then replaces them. Returns "" on success. On failure, targets
## already replaced are restored only if they still contain this transaction's new text.
## A concurrent change is preserved with its backup and reported for manual recovery.
func save_pair(targets: Array[String], texts: Array[String], originals: Array[String]) -> String:
	if targets.size() != texts.size() or targets.size() != originals.size():
		return "内部错误：目标文件、新文本和原文的数量不一致。"
	if targets.is_empty():
		return ""
	var failure := check_pair(targets, originals)
	if not failure.is_empty():
		return failure

	var staged_paths: Array[String] = []
	var staged_texts: Array[String] = []
	for index in targets.size():
		var temp := targets[index] + TEMP_SUFFIX
		# Do not truncate a .saving file that appeared after the first preflight check.
		if FileAccess.file_exists(temp):
			staged_paths.append(temp)
			staged_texts.append(texts[index])
			return _with_temp_cleanup(
				"保存已停止：保存期间出现临时文件 %s；未改写它。" % temp,
				staged_paths,
				staged_texts
			)
		staged_paths.append(temp)
		staged_texts.append(texts[index])
		failure = _write_bytes(temp, texts[index])
		if not failure.is_empty():
			return _with_temp_cleanup(
				"写临时文件失败：%s。" % failure,
				staged_paths,
				staged_texts
			)
		var staged := _read_text(temp)
		if not bool(staged["ok"]) or String(staged["text"]) != texts[index]:
			return _with_temp_cleanup(
				"保存已停止：临时文件 %s 在写入期间被修改或无法读取；未用它替换内容。"
				% temp,
				staged_paths,
				staged_texts
			)

	var replaced: Array[int] = []
	for index in targets.size():
		# _replace re-reads the target immediately before moving it aside, and verifies the
		# moved backup as well. This is intentionally in the replacement loop, not just the
		# initial preflight: staging and the previous language's rename take time.
		failure = _replace(
			targets[index], staged_paths[index], texts[index], true, originals[index]
		)
		if not failure.is_empty():
			var rollback := _rollback(targets, texts, originals, replaced, failure)
			return _with_temp_cleanup(rollback, staged_paths, staged_texts)
		replaced.append(index)

	# Check the full pair before discarding either backup. If a writer changed one of the
	# installed targets during the transaction, roll back only the targets still ours.
	for index in targets.size():
		failure = _snapshot_conflict(targets[index], true, texts[index])
		if not failure.is_empty():
			var rollback := _rollback(
				targets,
				texts,
				originals,
				replaced,
				"保存已停止：保存期间检测到目标文件变化。%s" % failure
			)
			return _with_temp_cleanup(rollback, staged_paths, staged_texts)

	# Backups are kept until both new files are verified. Do not remove a backup that an
	# external process changed during the transaction; report it for recovery instead.
	for index in targets.size():
		var backup := targets[index] + BACKUP_SUFFIX
		var state := _read_text(backup)
		if not bool(state["ok"]) or String(state["text"]) != originals[index]:
			var backup_conflict := (
				"保存已停止：备份 %s 在事务期间丢失、被修改或无法读取；未删除其他备份。"
				+ "请保留双语目标文件和现存备份，手工比对恢复。"
			)
			return backup_conflict % backup
	for index in targets.size():
		failure = _snapshot_conflict(targets[index], true, texts[index])
		if not failure.is_empty():
			return (
				"保存已停止：清理备份前检测到目标变化。%s 请保留目标文件和现存备份，手工比对恢复。"
				% failure
			)
		failure = _discard_backup_if_matches(targets[index], originals[index], true)
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
	var unrestored: Array[String] = []
	for index: int in replaced:
		var restore_failure := _restore_written_target(
			targets[index], texts[index], originals[index]
		)
		if not restore_failure.is_empty():
			unrestored.append(restore_failure)
	if unrestored.is_empty():
		return "%s 已还原本次替换的文件。" % failure
	return (
		"%s 恢复时检测到外部变化，未改写相关内容。请保留以下目标文件和备份，手工比对恢复：\n%s"
		% [failure, "\n".join(PackedStringArray(unrestored))]
	)


## Moves a staged file over its target while preserving the displaced file as a backup.
## `expected_exists` and `expected_text` are the target snapshot; they are checked at the
## last practical point before the target rename. This is not an OS-level atomic CAS.
func _replace(
	target: String,
	temp: String,
	new_text: String,
	expected_exists: bool,
	expected_text: String
) -> String:
	var backup := target + BACKUP_SUFFIX
	if FileAccess.file_exists(backup):
		return "保存已停止：发现未处理的备份文件 %s；未改写它。" % backup
	var staged := _read_text(temp)
	if not bool(staged["ok"]):
		return "无法读取临时文件 %s：%s。" % [temp, String(staged["reason"])]
	if String(staged["text"]) != new_text:
		return "保存已停止：临时文件 %s 在替换前已被修改；未用它改写目标。" % temp
	var conflict := _snapshot_conflict(target, expected_exists, expected_text)
	if not conflict.is_empty():
		return conflict

	if expected_exists:
		var displace := _rename(target, backup)
		if displace != OK:
			return "无法把 %s 移到备份 %s（错误码 %d）。" % [target, BACKUP_SUFFIX, displace]
		# If the target changed between the snapshot read and rename, the moved file is
		# still preserved. Put it back only if no one has recreated the target meanwhile.
		var moved := _read_text(backup)
		if not bool(moved["ok"]) or String(moved["text"]) != expected_text:
			var restore_failure := _restore_displaced_target(target)
			var message := "保存已停止：%s 在替换期间发生变化；没有继续写入。" % target
			if not restore_failure.is_empty():
				message += " " + restore_failure
			return message

	# The first rename leaves the target path vacant. If another process creates it in the
	# meantime, do not rely on platform-specific rename-overwrite behavior.
	if FileAccess.file_exists(target):
		var message := "保存已停止：%s 在暂存文件换入前重新出现；未改写它。" % target
		if expected_exists:
			var restore_failure := _restore_displaced_target(target)
			if not restore_failure.is_empty():
				message += " " + restore_failure
		return message
	staged = _read_text(temp)
	if not bool(staged["ok"]) or String(staged["text"]) != new_text:
		var message := "保存已停止：临时文件 %s 在换入前已被修改或无法读取。" % temp
		if expected_exists:
			var restore_failure := _restore_displaced_target(target)
			if not restore_failure.is_empty():
				message += " " + restore_failure
		return message

	var code := _rename(temp, target)
	if code != OK:
		var message := "无法写入 %s（重命名失败，错误码 %d）。" % [target, code]
		if expected_exists:
			var restore_failure := _restore_displaced_target(target)
			if not restore_failure.is_empty():
				message += " " + restore_failure
		return message
	return ""


## Restores a file moved aside by _replace when installing the staged file failed. The
## target must still be absent: a newly appeared file is external content and is never
## deleted or overwritten here.
func _restore_displaced_target(target: String) -> String:
	var backup := target + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		return "备份 %s 不存在，无法自动还原。" % backup
	if FileAccess.file_exists(target):
		return "目标 %s 已重新出现，未改写它；备份保留在 %s。" % [target, backup]
	var code := _rename(backup, target)
	if code != OK:
		return "无法自动还原 %s（错误码 %d）；原文保留在 %s。" % [target, code, backup]
	return ""


## Restores a successfully replaced target only while it still has our exact new text and
## the backup still has the original snapshot. A concurrent edit, deletion or unreadable
## file leaves both the target and backup untouched for manual recovery.
func _restore_written_target(target: String, new_text: String, original_text: String) -> String:
	var backup := target + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		return "缺少备份 %s，无法自动还原目标 %s。" % [backup, target]
	var saved_original := _read_text(backup)
	if not bool(saved_original["ok"]):
		return "无法读取备份 %s；目标 %s 未动，备份请手工检查。" % [backup, target]
	if String(saved_original["text"]) != original_text:
		return "备份 %s 在事务期间被修改；目标 %s 未动，两个文件都保留。" % [backup, target]
	var current := _read_text(target)
	if not bool(current["ok"]):
		return "目标 %s 已被删除或无法读取；未自动改写，备份保留在 %s。" % [target, backup]
	if String(current["text"]) != new_text:
		return "目标 %s 在事务期间被外部修改；未改写它，备份保留在 %s。" % [target, backup]
	if not _discard(target):
		return "无法安全移除本次写入的目标 %s；备份保留在 %s。" % [target, backup]
	var code := _rename(backup, target)
	if code != OK:
		return "无法还原 %s（错误码 %d）；原文仍在 %s。" % [target, code, backup]
	return ""


func _snapshot_conflict(target: String, expected_exists: bool, expected_text: String) -> String:
	var exists := FileAccess.file_exists(target)
	if expected_exists and not exists:
		return "保存已停止：文件在打开后已被删除或移走：%s。" % target
	if not expected_exists and exists:
		return "保存已停止：目标文件在保存期间新建：%s。" % target
	if not exists:
		return ""
	var current := _read_text(target)
	if not bool(current["ok"]):
		if not FileAccess.file_exists(target):
			return "保存已停止：文件在检查时已被删除或移走：%s。" % target
		return "保存已停止：无法读取文件 %s：%s。" % [target, String(current["reason"])]
	if String(current["text"]) != expected_text:
		return "保存已停止：文件在打开后已被外部修改：%s。" % target
	return ""


func _discard_backup_if_matches(target: String, expected_text: String, required: bool) -> String:
	var backup := target + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		if required:
			return "保存已停止：备份文件在清理前丢失：%s。" % backup
		return ""
	var state := _read_text(backup)
	if not bool(state["ok"]) or String(state["text"]) != expected_text:
		return "保存已停止：备份 %s 已变化或无法读取，未删除它；请手工检查。" % backup
	if not _discard(backup):
		return "无法清理备份 %s；请手工检查。" % backup
	return ""


func _with_temp_cleanup(message: String, paths: Array[String], texts: Array[String]) -> String:
	var retained := _cleanup_staged(paths, texts)
	if retained.is_empty():
		return message
	return "%s 以下临时文件已变化或无法读取，因此保留供手工检查：%s" % [message, "、".join(PackedStringArray(retained))]


func _cleanup_staged(paths: Array[String], texts: Array[String]) -> Array[String]:
	var retained: Array[String] = []
	for index in mini(paths.size(), texts.size()):
		var path := paths[index]
		if not FileAccess.file_exists(path):
			continue
		var staged := _read_text(path)
		if not bool(staged["ok"]) or String(staged["text"]) != texts[index]:
			retained.append(path)
			continue
		if not _discard(path):
			retained.append(path)
	return retained


## Backups and temporary files a crashed save left next to the content. The store reports
## them instead of deleting them: one of them may be the only copy of a line.
func leftovers(targets: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for target: String in targets:
		for suffix: String in [TEMP_SUFFIX, BACKUP_SUFFIX]:
			if FileAccess.file_exists(target + suffix):
				found.append(target + suffix)
	return found


## Puts a backup left by a crashed save back only when its target is missing. If the target
## exists, the backup is ambiguous and is left for the store to report rather than deleted.
func recover_missing(targets: Array[String]) -> Array[String]:
	var recovered: Array[String] = []
	for target: String in targets:
		var backup := target + BACKUP_SUFFIX
		if FileAccess.file_exists(backup) and not FileAccess.file_exists(target):
			if _rename(backup, target) == OK and FileAccess.file_exists(target):
				recovered.append(target)
	return recovered


# --- filesystem -------------------------------------------------------------


## Overridden by the tests to fail on purpose. Everything else in this class goes through
## it, so a single override covers the whole save path.
func _write_bytes(target: String, text: String) -> String:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "%s（错误码 %d）" % [target, FileAccess.get_open_error()]
	file.store_string(text)
	file.flush()
	file.close()
	if not FileAccess.file_exists(target):
		return "%s 写入后不存在" % target
	return ""


## Reads through one seam so tests can model an unreadable file even on CI runners where
## the process may have permission to read a chmod-restricted fixture.
func _read_text(target: String) -> Dictionary:
	if not FileAccess.file_exists(target):
		return {"ok": false, "reason": "文件不存在"}
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "无法打开（错误码 %d）" % FileAccess.get_open_error()}
	var initial_length := file.get_length()
	var text := file.get_as_text()
	var position := file.get_position()
	var final_length := file.get_length()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"ok": false, "reason": "读取失败（错误码 %d）" % read_error}
	if final_length != initial_length or position < initial_length:
		return {"ok": false, "reason": "读取期间文件长度发生变化"}
	return {"ok": true, "text": text}


func _rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(globalize(from_path), globalize(to_path))


func _discard(target: String) -> bool:
	if not FileAccess.file_exists(target):
		return true
	var result := DirAccess.remove_absolute(globalize(target))
	return result == OK or not FileAccess.file_exists(target)


static func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
