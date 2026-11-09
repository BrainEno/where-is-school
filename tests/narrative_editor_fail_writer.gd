extends "res://addons/narrative_editor/core/narrative_file_writer.gd"
## A writer that fails on purpose, so the editor's rollback is exercised for real.
##
## `tests/narrative_editor_test.gd` needs the save path to fail where it can: while staging
## a temporary file, while moving a language file aside, and while moving the new file in
## after the other language has already been replaced. The last one is the case that
## matters — a half-written save — and it cannot be provoked through the filesystem on a CI
## runner.
##
## Nothing here is a fake implementation: it is the real writer with two overridable
## methods returning an error at a chosen point. Failures are aimed at a destination path
## rather than at a call number, because the validation step before a save renames files of
## its own and a call counter would drift with it.

## Any path containing this text fails to be written as a temporary file.
var fail_write_fragment: String = ""
## A rename whose destination matches this text fails. `fail_rename_exact` makes it an
## equality check instead of a substring check, which is how the second half of a
## replacement (temp -> content file) is targeted without also matching `file.backup`.
var fail_rename_destination: String = ""
var fail_rename_exact: bool = false
## When true only the first matching rename fails, so the rollback that follows can
## succeed — which is what a real transient failure looks like.
var fail_rename_once: bool = true

var rename_calls: int = 0
var rename_failures: int = 0


func _write_bytes(target: String, text: String) -> String:
	if not fail_write_fragment.is_empty() and target.contains(fail_write_fragment):
		return "测试故意让 %s 写入失败" % target
	return super._write_bytes(target, text)


func _rename(from_path: String, to_path: String) -> Error:
	rename_calls += 1
	if fail_rename_destination.is_empty():
		return super._rename(from_path, to_path)
	var matched := (
		to_path == fail_rename_destination
		if fail_rename_exact
		else to_path.contains(fail_rename_destination)
	)
	if not matched:
		return super._rename(from_path, to_path)
	if fail_rename_once and rename_failures > 0:
		return super._rename(from_path, to_path)
	rename_failures += 1
	return ERR_BUSY
