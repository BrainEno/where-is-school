extends SceneTree
## No new canonical content: fixture operations exercise the same graph parser as live data.

const Harness := preload("res://tests/test_harness.gd")
const Patch := preload("res://scripts/dev/authoring/dialogue_patch.gd")
const Journal := preload("res://scripts/dev/authoring/draft_journal.gd")
const Store := preload("res://scripts/dev/authoring/draft_store.gd")
const CHAPTER := "prologue"
const FIXTURE := "演练用文字。\n第二行。"

var _check := Harness.Checker.new()
var _directory := "user://authoring-test-" + Patch.new_id()


func _initialize() -> void:
	Harness.arm_watchdog(self, 40.0, "authoring_patch_test.gd")
	call_deferred("_run")


func _run() -> void:
	_test_implicit_continuation()
	_test_store_patch()
	_test_empty_draft_recovery()
	for name: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	Harness.finish(self, _check.failures, "author drafts preserve topology, reject conflicts, round trip, and recover a torn slot")


func _test_implicit_continuation() -> void:
	var base := {"format_version": 1.0, "locale": "zh-CN", "chapter": "fixture", "conversations": {
		"simple": {"start": "a", "nodes": [
			{"id": "a", "speaker": "student", "text": "A"},
			{"id": "b", "speaker": "student", "text": "B", "next": null},
		]},
	}}
	var inserted := {"kind": "insert", "conversation": "simple", "node": "a", "before": "b",
		"reply": {"id": Patch.new_id(), "speaker": "student", "text": FIXTURE, "next": "b",
			"effects": [{"type": "set_flag", "flag": "untrusted"}]}}
	var result := Patch.apply_chapter(base, "fixture", {"ops": [inserted]})
	if not _check.expect(not result.has("error"), "Fall-through insertion failed: %s" % result.get("error", "")):
		return
	var nodes: Array = result["data"]["conversations"]["simple"]["nodes"]
	_check.expect(nodes[0]["next"] == inserted["reply"]["id"] and nodes[1]["next"] == "b" and nodes[2]["next"] == null,
		"Insertion did not preserve the implicit continuation and the explicit ending")
	_check.expect(not nodes[1].has("effects") and base["conversations"]["simple"]["nodes"].size() == 2,
		"Patch smuggled an effect or changed the shipped data in place")
	inserted["before"] = "removed"
	_check.expect(Patch.apply_chapter(base, "fixture", {"ops": [inserted]}).has("error"), "Changed predecessor edge accepted")


func _test_store_patch() -> void:
	var store := Store.new(_directory)
	store.load_workspace()
	if not _check.expect(store.blocked.is_empty(), "Draft store failed to load base content: " + store.blocked):
		return
	var base := Patch.read_json(DialogueLibrary.chapter_path(Patch.LOCALE, CHAPTER))
	_check.expect(store.set_text(CHAPTER, "student", "st_reciting", "", FIXTURE), "Cannot edit line")
	_check.expect(not store.set_text(CHAPTER, "student", "st_reciting", "", " \n"), "Blank body accepted")
	var inserted := store.insert_line(CHAPTER, "student", "st_1", "student", "Inserted fixture")
	_check.expect(not inserted.is_empty(), "Can't insert after a regular classroom line: " + store.error)
	var choice := store.add_choice(CHAPTER, "student", "st_reciting", "Added option", "st_1", "student", "New response")
	_check.expect(not choice.is_empty(), "Can't add option and response: " + store.error)
	var count := store.change_count()
	_check.expect(store.add_choice(CHAPTER, "student", "st_reciting", "Loop", "st_reciting").is_empty(), "A new cycle was accepted")
	_check.expect(store.change_count() == count, "Refused edit changed operation log")
	_check.expect(store.save_editor_state(), "Failed to write generation 1")
	var first := store.export_json()
	_check.expect(store.set_text(CHAPTER, "student", "st_reciting", "leave", "Renamed option"), "Cannot edit option text")
	store.buffer = {"dirty": true, "text": "未完成的测试"}
	_check.expect(store.save_editor_state(), "Failed to write generation 2")
	var entry: Dictionary = store.portable_draft()["chapters"][CHAPTER]
	var normalized: Dictionary = JSON.parse_string(store.export_json())
	var result := Patch.apply_chapter(base, CHAPTER, normalized["chapters"][CHAPTER])
	if not _check.expect(not result.has("error"), "Export did not reapply: %s" % result.get("error", "")):
		return
	_check.expect(entry["result"] == Patch.digest(result["data"]), "Result digest changed after JSON round trip")
	_check.expect(Patch.apply_chapter(result["data"], CHAPTER, entry).get("already_applied", false), "Applied draft is not idempotent")
	_check_conflict(base, entry)
	var saved := Store.new(_directory)
	saved.load_workspace()
	_check.expect(saved.export_json() == store.export_json() and saved.buffer == store.buffer,
		"Newest slot lost changes or the unfinished input buffer")
	_check.expect(Journal.write_checked(_directory.path_join("draft-0.json"), "{torn") == OK, "Cannot write torn fixture")
	var recovered := Store.new(_directory)
	recovered.load_workspace()
	_check.expect(recovered.export_json() == first and recovered.buffer.is_empty(), "Did not recover intact older slot")
	_check.expect(store.undo() and store.export_json() == first, "Undo did not restore the previous validated draft")


func _check_conflict(base: Dictionary, entry: Dictionary) -> void:
	var edition := base.duplicate(true)
	var rows: Array = Patch.get_conversation(edition, "student")["nodes"]
	var node := Patch.find_record(rows, "st_reciting")
	var different := Patch.find_record(rows, "st_2")
	different["text"] = "Unrelated update"
	var merged := Patch.apply_chapter(edition, CHAPTER, entry)
	_check.expect(not merged.has("error"), "Unrelated update must not block transfer")
	if not merged.has("error"):
		var candidate_rows: Array = Patch.get_conversation(merged["data"], "student")["nodes"]
		_check.expect(Patch.find_record(candidate_rows, "st_2")["text"] == "Unrelated update", "Unrelated wording overwritten")
	node["text"] = "Concurrent owner update"
	_check.expect(Patch.apply_chapter(edition, CHAPTER, entry).has("error"), "Conflicting owner wording would be overwritten")


func _test_empty_draft_recovery() -> void:
	var path := _directory.path_join("draft-1.json")
	_check.expect(Journal.write_checked(path, "{also torn") == OK, "Cannot write second torn fixture")
	var journal := Journal.new(_directory)
	_check.expect(journal.recover().is_empty() and not journal.problem.is_empty(), "Two corrupt slots were treated as a clean draft")
	_check.expect(not journal.save({"draft": {}}) and FileAccess.get_file_as_string(path) == "{also torn",
		"Journal silently overwrote both corrupt slots")
