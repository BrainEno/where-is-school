extends SceneTree
## No new canonical content: fixture operations exercise the same graph parser as live data.

const Harness := preload("res://tests/test_harness.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const Journal := preload("res://scripts/story_editor/draft_journal.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const CHAPTER := "prologue"
const FIXTURE := "演练用文字。\n第二行。"

var _check := Harness.Checker.new()
var _directory := "user://authoring-test-" + Patch.new_id()


func _initialize() -> void:
	Harness.arm_watchdog(self, 40.0, "authoring_patch_test.gd")
	call_deferred("_run")


func _run() -> void:
	_test_implicit_continuation()
	_test_choice_followups()
	_test_store_patch()
	_test_empty_draft_recovery()
	_test_live_round_transaction()
	for name: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	Harness.finish(self, _check.failures, "author drafts preserve topology, reject conflicts, round trip, and recover a torn slot")


func _test_implicit_continuation() -> void:
	var base := {"format_version": DialogueGraph.FORMAT_VERSION, "locale": "zh-CN", "chapter": "fixture", "conversations": {
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


func _test_choice_followups() -> void:
	# Both choices originally share an ending. Their additions must be private,
	# preserve the old shared path and leave implicit order on other nodes alone.
	var left := {"id": "left", "text": "Left", "next": "join", "once": true}
	var right := {"id": "right", "text": "Right", "next": "join"}
	var base := {"format_version": DialogueGraph.FORMAT_VERSION, "locale": "zh-CN", "chapter": "fixture", "conversations": {
		"branch": {"start": "open", "nodes": [
			{"id": "open", "speaker": "student", "text": "Open"},
			{"id": "ask", "speaker": "student", "text": "Ask", "choices": [left, right]},
			{"id": "join", "speaker": "student", "text": "Join"},
			{"id": "end", "speaker": "student", "text": "End", "next": null},
		]},
	}}
	var snapshot := base.duplicate(true)
	var a := _followup_line("First")
	a["next"] = "end"
	a["effects"] = [{"type": "set_flag", "flag": "ignored"}]
	var b := _followup_line("Second")
	var pending := _followup_line("", true)
	var note := _followup_line("Draft note", true)
	var one := _followup_op(left, [a, b])
	var two := _followup_op(right, [pending, note])
	var entry := {"ops": [one, two]}
	var result := Patch.apply_chapter(base, "fixture", entry)
	if not _check.expect(not result.has("error"), "Follow-ups on shared edge refused: %s" % result.get("error", "")):
		return
	var rows: Array = Patch.get_conversation(result["data"], "branch")["nodes"]
	var hub := Patch.find_record(rows, "ask")
	var choices := Patch.choices_at(hub)
	_check.expect(base == snapshot and choices == [left.merged({"next": a["id"]}, true), right.merged({"next": pending["id"]}, true)],
		"Follow-ups changed the source, option wording, order or conditions")
	var entry_graph: DialogueGraph = result["graph"]
	var parsed := entry_graph.get_conversation(&"branch")
	for route: Array in [[a, b, pending], [pending, note, a]]:
		var reach := DialogueGraph.reachable_nodes(parsed, StringName(route[0]["id"]))
		_check.expect(reach.size() == 4 and reach.has(&"join") and reach.has(&"end") and reach.has(StringName(route[1]["id"])) \
			and not reach.has(StringName(route[2]["id"])), "One option leaked into the other's private round")
	_check.expect(Patch.find_record(rows, a["id"]) == {"id": a["id"], "speaker": "student", "text": "First", "next": b["id"]},
		"Follow-up trusted a caller-supplied edge or effect")
	var followups: Patch.Followups = result["followups"]
	_check.expect(followups.placeholders.size() == 2 and Patch.find_record(rows, pending["id"])["text"] == Patch.PLACEHOLDER,
		"Blank/note placeholders did not remain visible and separately tracked")
	var c := _followup_line("Third")
	var three := _followup_op(choices[0], [c], b["id"], "join")
	var extended := Patch.apply_chapter(base, "fixture", {"ops": [one, two, three]})
	if _check.expect(not extended.has("error"), "Cannot append in chronological order: %s" % extended.get("error", "")):
		var ext: Array = Patch.get_conversation(extended["data"], "branch")["nodes"]
		_check.expect(Patch.find_record(ext, b["id"])["next"] == c["id"] and Patch.find_record(ext, c["id"])["next"] == "join" \
			and Patch.find_record(ext, note["id"])["next"] == "join", "Appending did not preserve order or isolated rejoin")
	var leak := {"kind": "choice", "conversation": "branch", "node": "ask", "before": Patch.choice_signature(hub),
		"id": Patch.new_id(), "text": "Shared draft round", "next": b["id"]}
	_check.expect(Patch.apply_chapter(base, "fixture", {"ops": [one, two, leak]}).has("error"),
		"A later jump could turn a private follow-up into shared state")
	_check_followup_conflicts(base, one)


func _check_followup_conflicts(base: Dictionary, op: Dictionary) -> void:
	var edited := base.duplicate(true)
	var choices := Patch.choices_at(Patch.get_conversation(edited, "branch")["nodes"][1])
	choices[0]["text"] = "Concurrent wording"
	choices[1]["next"] = "end"
	var entry := {"ops": [op]}
	var merged := Patch.apply_chapter(edited, "fixture", entry)
	if _check.expect(not merged.has("error"), "Unrelated wording or sibling edge blocked the follow-up"):
		var merged_choices := Patch.choices_at(Patch.get_conversation(merged["data"], "branch")["nodes"][1])
		_check.expect(merged_choices[0]["text"] == "Concurrent wording" and merged_choices[1]["next"] == "end",
			"Follow-up overwrote concurrent wording or the other option")
	choices[0]["once"] = false
	_check.expect(Patch.apply_chapter(edited, "fixture", entry).has("error"), "Changed option conditions not detected")
	choices[0]["once"] = true
	choices[1]["next"] = "join"
	choices[0]["next"] = "end"
	_check.expect(Patch.apply_chapter(edited, "fixture", entry).has("error"), "Changed option edge not detected")
	choices.pop_front()
	_check.expect(Patch.apply_chapter(edited, "fixture", entry).has("error"), "Deleted option not detected")
	var first: Dictionary = op["lines"][0]
	for invalid: Array in [[], [first, first], [_followup_line("")], [first.merged({"speaker": "not-in-conversation"}, true)]]:
		_check.expect(Patch.apply_chapter(base, "fixture", {"ops": [op.merged({"lines": invalid}, true)]}).has("error"),
			"Accepted a malformed follow-up instead of rejecting it as a whole")


func _followup_line(text: String, placeholder: bool = false) -> Dictionary:
	return {"id": Patch.new_id(), "speaker": "student", "text": text, "placeholder": placeholder}


func _followup_op(choice: Dictionary, lines: Array, after: String = "", before: String = "join") -> Dictionary:
	return {"kind": "followup", "conversation": "branch", "node": "ask", "choice": choice["id"],
		"guard": Patch.option_signature(choice), "after": after, "before": before, "lines": lines}


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
	_check.expect(saved.export_json() == store.export_json() and saved.buffer == store.buffer and saved.recovery_notice().is_empty(),
		"Newest slot lost changes or a healthy older slot was misreported as damaged")
	_check.expect(Journal.write_checked(_directory.path_join("draft-0.json"), "{torn") == OK, "Cannot write torn fixture")
	var recovered := Store.new(_directory)
	recovered.load_workspace()
	_check.expect(recovered.export_json() == first and recovered.buffer.is_empty() and not recovered.recovery_notice().is_empty(),
		"Did not recover and report the intact older slot")
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


func _test_live_round_transaction() -> void:
	var directory := _directory.path_join("live")
	var store := Store.new(directory, true)
	store.load_workspace()
	if not _check.expect(store.blocked.is_empty(), "Could not load live fixture: " + store.blocked):
		return
	var address := {"chapter": CHAPTER, "conversation": "student", "node": "st_reciting", "choice": "wait"}
	var anchor := store.round_anchor(address)
	var form := {"lines": [{"speaker": "student", "text": "Fixture line"}],
		"choices": [{"text": "Continue fixture", "next": "st_1"}]}
	var loop := form.duplicate(true)
	loop["choices"].append({"text": "Invalid looping choice", "next": "st_reciting"})
	_check.expect(not store.apply_live_round(address, anchor, loop) and store.round_anchor(address) == anchor,
		"A round with a cyclic new choice changed its original anchor")
	var slot := directory.path_join("draft-1.json")
	_check.expect(DirAccess.make_dir_recursive_absolute(slot) == OK, "Could not inject a journal failure")
	_check.expect(not store.apply_live_round(address, anchor, form) and store.has_save_error()
		and store.round_anchor(address) == anchor and store.graph_override(CHAPTER, "zh-CN") == null,
		"A failed durable write published one or more edges")
	DirAccess.remove_absolute(slot)
	_check.expect(store.apply_live_round(address, anchor, form), "Valid round rejected on retry: " + store.error)
	var accepted := store.export_json()
	_check.expect(not store.apply_live_round(address, anchor, form) and store.export_json() == accepted,
		"Stale anchor changed or duplicated an accepted round")
	var restored := Store.new(directory, true)
	restored.load_workspace()
	_check.expect(restored.blocked.is_empty() and restored.export_json() == accepted, "Retried transaction was not durable")
	for name: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
