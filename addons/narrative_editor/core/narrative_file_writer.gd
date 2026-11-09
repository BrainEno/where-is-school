extends RefCounted
## Editor-only: write content files without ever leaving one language behind.
##
## A save writes two files, English and Chinese, that have to change together. The naive
## version — write English, write Chinese, report success — has two failure modes that are
## both worse than refusing to save: the game ends up with one language that says something
## and one that does not, and the tool still shows a green save. So a save is staged:
##
## 1. every target is written to a temporary file next to itself, first. A full disk or a
##    locked file is discovered while nothing on disk has been replaced yet;
## 2. the temporary files replace the targets one by one, each through a backup: the
##    current file is moved aside, the new one is moved in, and the backup is deleted once
##    the whole save has succeeded. A rename onto an existing file is the operation some
##    platforms refuse *after* deleting the destination, and a content tool must never be
##    the thing that deletes an author's file because a rename failed;
## 3. if any step refuses, every target that was already replaced is put back from its
##    backup, and the failure names the file that refused. A save that reports failure has
##    left both languages exactly as they were, or — if even the restore failed — says
##    which file is now sitting under `.backup` and has to be put back by hand.
##
## The visible file therefore changes all at once: a reader of the content never sees a
## half-written JSON file, which would fail to parse in the game for as long as the write
## took.
##
## `_write_bytes()` and `_rename()` are the seams the tests replace, so the rollback path is
## exercised for real instead of being described in a comment.

const TEMP_SUFFIX := ".saving"
const BACKUP_SUFFIX := ".backup"


## Writes `text` to `target`, replacing whatever is there. Returns "" on success, or a
## message that names the file and the reason.
func write_atomic(target: String, text: String) -> String:
	var temp := target + TEMP_SUFFIX
	var failure := _write_bytes(temp, text)
	if not failure.is_empty():
		_discard(temp)
		return failure
	var replaced := _replace(target, temp, false)
	if not replaced.is_empty():
		_discard(temp)
		return replaced
	return ""


## Stages every target, then replaces them. Returns "" on success. On failure nothing is
## left half-written: replaced targets are put back from their backups and temporary files
## are removed.
func save_pair(targets: Array[String], texts: Array[String], originals: Array[String]) -> String:
	if targets.size() != texts.size() or targets.size() != originals.size():
		return "内部错误：目标文件、新文本和原文本的数量不一致。"
	if targets.is_empty():
		return ""
	var temps: Array[String] = []
	for index in targets.size():
		var temp := targets[index] + TEMP_SUFFIX
		var failure := _write_bytes(temp, texts[index])
		if not failure.is_empty():
			for written: String in temps:
				_discard(written)
			_discard(temp)
			return "写临时文件失败：%s。磁盘上的内容没有改动。" % failure
		temps.append(temp)

	var replaced: Array[int] = []
	for index in targets.size():
		var failure := _replace(targets[index], temps[index], true)
		if not failure.is_empty():
			_discard(temps[index])
			return _rollback(targets, originals, replaced, index, failure)
		replaced.append(index)
	for index in targets.size():
		_discard(targets[index] + BACKUP_SUFFIX)
	return ""


func _rollback(
	targets: Array[String], originals: Array[String], replaced: Array[int], failed: int, failure: String
) -> String:
	var candidates: Array[int] = replaced.duplicate()
	if not candidates.has(failed):
		candidates.append(failed)
	var unrestored: Array[String] = []
	for index: int in candidates:
		var target := targets[index]
		if not FileAccess.file_exists(target + BACKUP_SUFFIX):
			# Either it was never replaced (its content is still the file itself) or the
			# failed step already put the original back.
			continue
		if not _restore_backup(target):
			unrestored.append(target)
	if unrestored.is_empty():
		return "%s 已经写入的内容都已还原；两个语言的磁盘内容没有变化。" % failure
	return (
		"%s 还原时这些文件也没有成功，原始内容在它们旁边的 %s 文件里，需要手工恢复：%s"
		% [failure, BACKUP_SUFFIX, "、".join(PackedStringArray(unrestored))]
	)


## Moves `temp` over `target` without ever destroying the only copy of `target`: the file
## that is there is moved to `target + ".backup"` first. When `keep_backup` is false the
## backup is removed on success, which is what a single-file write wants; a paired save
## keeps it until both files are in place.
func _replace(target: String, temp: String, keep_backup: bool) -> String:
	var had_target := FileAccess.file_exists(target)
	var backup := target + BACKUP_SUFFIX
	if had_target:
		_discard(backup)
		var displace := _rename(target, backup)
		if displace != OK:
			return "无法把 %s 移到备份 %s（错误码 %d）。" % [target, BACKUP_SUFFIX, displace]
	var code := _rename(temp, target)
	if code != OK:
		if had_target and not _restore_backup(target):
			return (
				"无法写入 %s（重命名失败，错误码 %d），原始内容留在 %s。"
				% [target, code, backup]
			)
		return "无法写入 %s（重命名失败，错误码 %d）。" % [target, code]
	if had_target and not keep_backup:
		_discard(backup)
	return ""


## Puts `target` back from its backup. The replacement, if it exists, is removed first: the
## original is in the backup, so this cannot lose anything.
func _restore_backup(target: String) -> bool:
	var backup := target + BACKUP_SUFFIX
	if not FileAccess.file_exists(backup):
		return false
	_discard(target)
	return _rename(backup, target) == OK


## Backups and temporary files a crashed save left next to the content. The store reports
## them instead of deleting them: one of them may be the only copy of a line.
func leftovers(targets: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for target: String in targets:
		for suffix: String in [TEMP_SUFFIX, BACKUP_SUFFIX]:
			if FileAccess.file_exists(target + suffix):
				found.append(target + suffix)
	return found


## Puts a backup left by a crashed save back, when the file it belongs to is missing. The
## only case where this is unambiguous — and the case where doing nothing would lose text.
func recover_missing(targets: Array[String]) -> Array[String]:
	var recovered: Array[String] = []
	for target: String in targets:
		var backup := target + BACKUP_SUFFIX
		if FileAccess.file_exists(backup) and not FileAccess.file_exists(target):
			if _rename(backup, target) == OK:
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


func _rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(globalize(from_path), globalize(to_path))


func _discard(target: String) -> void:
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(globalize(target))


static func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
