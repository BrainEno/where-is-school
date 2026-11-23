extends SceneTree
## Open the drawer over the real seated-student interaction, edit and walk the
## new route, export it, then continue the original encounter without contamination.

const Harness := preload("res://tests/test_harness.gd")
const Bootstrap := preload("res://scripts/story_editor/bootstrap.gd")
const Overlay := preload("res://scripts/story_editor/author_overlay.gd")
const Form := preload("res://scripts/story_editor/author_form.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const Exchange := preload("res://scripts/story_editor/author_exchange.gd")
const LogStore := preload("res://scripts/diagnostics/log_store.gd")
const EventSchema := preload("res://scripts/diagnostics/event_schema.gd")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const MainScene := preload("res://scenes/main/main.tscn")
const SAMPLE := "文案测试：一行。\n第二行，龘。"
const OPTION := "流程测试选项"
const REPLY := "独立试玩的回应"
const INSERT := "插入对白的测试"
const LEAVE_ROUND := ["离开选项的第一句测试。", "离开选项的第二句测试。", "稍后追加的第三句测试。"]
const WAIT_ROUND := ["等待选项的占位已补写。", "等待选项的第二句测试。"]
const WAIT_NOTE := "待补写的备注（测试）"

var _check := Harness.Checker.new()
var _directory := "user://classroom-authoring-test-" + Patch.new_id()
var _world: Node
var _controller: DialogueController
var _ui: GameUI
var _overlay: Overlay
var _drawer: Form
var _panel: DialoguePanel
var _store: Store
var _game_state: Node
var _knowledge: Node
var _player: PlayerController


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "authoring_classroom_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_knowledge = autoloads["narrative_state"]
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	loc.set_locale("zh-CN")
	await _boot_world()
	if await _open_at_student():
		var before := _snapshot()
		var live_events := _dialogue_events()
		_check.expect(not live_events.is_empty(), "The real classroom did not record a dialogue event")
		_try_world_input()
		await _edit_fields()
		_test_find_and_validation()
		await _edit_branches()
		await _walk_draft()
		await _edit_followups()
		_export_round_trip()
		_test_clear_and_undo()
		_test_stale_form()
		_test_local_save_failure()
		_check.expect(_snapshot() == before, "Editor or trial changed live story, camera, saves, reveals, or history")
		_check.expect(_dialogue_events() == live_events, "Trial emitted gameplay diagnostics into the real session")
		_send_action(&"ui_cancel")
		_check.expect(not paused and _ui.dialogue_panel.visible and _snapshot() == before,
			"Closing the drawer did not preserve the real choice/reveal state")
		_controller.select_choice(0)
		_check.expect(String(_controller.get_current_line().get("node_id", "")) == "st_let_be", "Original choice broken after close")
		_controller.advance_presentation()
		_controller.advance_presentation()
		_check.expect(not _controller.has_pending_choices(), "Could not resume the original conversation")
	paused = false
	_world.queue_free()
	await process_frame
	for name: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	Harness.finish(self, _check.failures, "classroom authoring edits, isolated trial and explicit JSON export; real play intact")


func _boot_world() -> void:
	Harness.stage = "actual classroom loading"
	_world = MainScene.instantiate()
	var opening := _world.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(_world)
	current_scene = _world
	opening.allow_player_control()
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_controller = _world.get_node(^"DialogueController")
	_ui = _world.get_node(^"GameUI")
	_player = _world.get_node(^"Player")
	_ui.fade.set_clear()
	if MobileLayout.enabled:
		Input.emulate_mouse_from_touch = true
		Input.emulate_touch_from_mouse = true
		root.min_size = Vector2i.ZERO
		root.size = Vector2i(852, 393)
		root.set_meta(MobileLayout.TEST_SAFE_AREA, Rect2(48, 0, 756, 377))
		root.set_meta(MobileLayout.TEST_DENSITY, 1.0)
	elif DisplayServer.get_name() == "headless":
		# No window manager sets a desktop extent in the headless driver.
		root.size = Vector2i(1600, 900)
	await process_frame # Let initial Control layouts propagate, without advancing narrative.


func _open_at_student() -> bool:
	Harness.stage = "live student choice owns the paused screen"
	var host := _world.get_node(^"LocationHost") as LocationHost
	var classroom := host.get_current()
	var student := classroom.find_interactable(&"student_talk") if classroom != null else null
	if not _check.expect(student != null and not _world.has_node(^"AuthorOverlay"), "Missing student or author code reached normal gameplay"):
		return false
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	interaction.request_activation(student)
	if not _check.expect(await Harness.wait_until(_controller.has_pending_choices, 5), "Student did not present real choices"):
		return false
	_check.expect(String(_controller.get_current_line().get("node_id", "")) == "st_reciting", "Not the authored classroom start node")
	_store = Store.new(_directory)
	_store.load_workspace()
	var bootstrap := Bootstrap.new()
	bootstrap._store = _store
	# The retail app installs this autoload from the pause menu once Settings → Story
	# editor is on; here the test installs it the way the menus do.
	bootstrap.name = "StoryEditor"
	root.add_child(bootstrap)
	if not _check.expect(await Harness.wait_until(func() -> bool:
		var entry := _world.get_node_or_null(^"AuthorOverlay/EditStory") as Button
		return entry != null and entry.is_visible_in_tree()
	, 5), "Author bootstrap did not attach to the live game"):
		return false
	_overlay = _world.get_node(^"AuthorOverlay") as Overlay
	_check.expect(bootstrap.has_overlay(), "The installed editor did not report its overlay")
	var launch := _overlay.get_node(^"EditStory") as Button
	if MobileLayout.enabled:
		_check.expect(MobileLayout.safe_rect(launch).encloses(launch.get_global_rect()), "Author launcher is outside the OS safe area")
		_check.expect(launch.size.y >= MobileLayout.hit_size(launch), "Author launcher is smaller than the touch minimum")
		_launch_touch(launch.get_global_rect().get_center(), true)
		await process_frame # The deferred opener from a cancelled release must never fire.
		_check.expect(not paused and launch.visible, "Cancelled first finger activated the author launcher")
		_launch_touch(launch.get_global_rect().get_center(), false)
	else:
		await _tap(launch)
	if not _check.expect(await Harness.wait_until(func() -> bool: return paused, 5), "Author launcher did not pause the classroom"):
		return false
	_drawer = _overlay.get_node(^"AuthorDrawer") as Form
	_panel = _overlay.get_node(^"AuthorDialoguePreview") as DialoguePanel
	_check.expect(_drawer.selected("node") == "st_reciting" and _drawer.selected("conversation") == "student",
		"Entering from the student line did not preselect its stable IDs")
	_check.expect(_panel.get_body_text() == _ui.dialogue_panel.get_body_text(), "Detached view did not start with the current words")
	if MobileLayout.enabled:
		_check.expect(MobileLayout.safe_rect(_drawer).encloses(_drawer.get_global_rect()), "Drawer is outside landscape safe area")
		_check.expect(_drawer.button("trial").size.y >= MobileLayout.hit_size(_drawer), "Trial button is smaller than the touch minimum")
	return true


func _edit_fields() -> void:
	_drawer.set_keyboard_compact(true)
	_check.expect(_drawer.button("apply_text").is_visible_in_tree(), "Compact text editor has no save key")
	_check.expect(not _drawer.button("cancel").is_visible_in_tree(), "Compact editor shows conflicting cancel key")
	_drawer.set_keyboard_compact(false)
	Harness.stage = "mutating preview wording only"
	var original := _panel.get_body_text()
	var choice_before := _panel.find_child("Choice1", true, false)
	var revised_body := (SAMPLE + "\n").repeat(12).strip_edges()
	_enter(_drawer.body, revised_body)
	_drawer.body.set_caret_line(1)
	_drawer.body.set_caret_column(3)
	_check.expect(await Harness.wait_until(func() -> bool: return _panel.get_body_text() == revised_body, 4), "Changed body never reached preview")
	_check.expect(_drawer.body.get_caret_line() == 1 and _drawer.body.get_caret_column() == 3, "Preview moved the editing caret")
	_check.expect(_panel.find_child("Choice1", true, false) == choice_before, "Editing text recreated the option buttons")
	_drawer.action.emit("original")
	_check.expect(_panel.get_body_text() == original, "Original comparison now displays the draft")
	_drawer.action.emit("original")
	_pick("field", "leave")
	_check.expect(not _drawer.body.has_undo(), "Changing fields can undo into another field's wording")
	var body := _panel.get_node(^"%BodyLabel") as RichTextLabel
	var scroll := body.get_v_scroll_bar()
	_check.expect(await Harness.wait_until(func() -> bool:
		return body.scroll_active and not _panel._layout_dirty and _panel._preview_scroll < 0.0 \
			and scroll.max_value - scroll.page > 20.0
	, 4), "Long draft should scroll in the real preview panel")
	scroll.value = 20.0
	_enter(_drawer.body, OPTION)
	_check.expect(await Harness.wait_until(func() -> bool:
		return is_instance_valid(choice_before) and OPTION in (choice_before as Button).text \
			and not _panel._layout_dirty and _panel._preview_scroll < 0.0
	, 4), "Option wording did not update the existing preview button")
	_check.expect(is_equal_approx(scroll.value, 20.0), "Changing an option reset the current reading position")


func _test_find_and_validation() -> void:
	Harness.stage = "search does not retarget pending text"
	_drawer.button("current_line").pressed.emit()
	_check.expect(_drawer.selected("node") == "st_reciting" and _drawer.selected("field").is_empty(),
		"Jump to the live line did not select its body")
	_drawer.button("find").pressed.emit()
	var query := _drawer.find_child("FindQuery", true, false) as LineEdit
	var hits := _drawer.find_child("Pick_match", true, false) as OptionButton
	if not _check.expect(query != null and hits != null and query.is_visible_in_tree(), "Find did not expose its query"):
		return
	query.text = "no-author-test-result"
	query.text_changed.emit(query.text)
	_check.expect(hits.disabled and hits.item_count == 1, "No-results search left a stale target")
	query.text = OPTION
	query.text_changed.emit(query.text)
	_check.expect(not hits.disabled and hits.item_count == 2, "Search did not find the edited option exactly once")
	var before := _panel.get_body_text()
	_enter(_drawer.body, " \n")
	_drawer.button("apply_text").pressed.emit()
	_check.expect("未应用" in _drawer.status.text and "文字已保存" not in _drawer.status.text,
		"Invalid text was reported as saved")
	_check.expect(_store.buffer.get("dirty") == true and _store.buffer.get("text") == " \n",
		"Invalid input was not kept in the editable journal buffer")
	_pick("match", "0")
	_check.expect(_drawer.selected("field").is_empty() and _drawer.body.text == " \n" and _panel.get_body_text() == before,
		"A search result retargeted rejected input or changed the validated preview")
	_export_while_rejected()
	_overlay.close_editor()
	_check.expect(not paused, "A rejected but backed-up field trapped the author in the editor")
	_store = Store.new(_directory)
	_store.load_workspace()
	_overlay.store = _store
	_overlay.open_editor()
	_check.expect(_drawer.body.text == " \n" and _panel.get_body_text() == before,
		"A fresh workspace lost rejected input or applied it to the preview")
	_drawer.button("cancel").pressed.emit()
	_check.expect(_drawer.body.text == before, "Discard input did not restore the applied field")
	_drawer.button("find").pressed.emit()
	_pick("match", "0")
	_check.expect(_drawer.selected("field") == "leave" and _drawer.body.text == OPTION and not query.is_visible_in_tree(),
		"Opening a search result did not select its option text and close Find")
	_drawer.button("find").pressed.emit()
	query.text = "CORRIDOR_SPEAKER"
	query.text_changed.emit(query.text)
	_pick("match", "0")
	_check.expect(_drawer.selected("chapter") == "corridor" and _drawer.selected("conversation") == "corridor_speaker"
			and _drawer.selected("node") == "cs_1", "Find did not jump across chapters by conversation ID")
	_drawer.button("current_line").pressed.emit()
	_check.expect(_drawer.selected("node") == "st_reciting" and _panel.get_body_text() == before,
		"Current line did not return across chapters to the edited live node")


func _export_while_rejected() -> void:
	_check.expect(_drawer.button("export").text == "导出已应用", "Export did not disclose the unapplied field")
	_drawer.button("export").pressed.emit()
	var pickers := _overlay.find_children("*", "FileDialog", true, false)
	if not _check.expect(pickers.size() == 1, "A rejected field blocked export of the rest of the draft"):
		return
	var dialog := pickers[0] as FileDialog
	var path := ProjectSettings.globalize_path(_directory.path_join("applied-only.json"))
	dialog.hide()
	dialog.file_selected.emit(path)
	_check.expect(FileAccess.get_file_as_string(path) == _store.export_json() and _store.buffer.get("dirty") == true,
		"Export serialized rejected input or removed it from the local buffer")


func _edit_branches() -> void:
	Harness.stage = "editing graph through drawer"
	_pick("node", "st_1")
	_drawer.action.emit("insert")
	_enter(_drawer.body, INSERT)
	_drawer.action.emit("apply")
	_check.expect(_drawer.selected("node").begins_with(Patch.ID_PREFIX), "Inserted line was not selected in the drawer")
	_drawer.action.emit("original")
	_check.expect(not _panel.visible and _drawer.button("trial_here").disabled and "原文没有" in _drawer.status.text,
		"Original comparison did not explain the missing source for a draft-only node")
	_drawer.action.emit("original")
	_drawer.button("trial_here").pressed.emit()
	_check.expect(_panel.visible and not _drawer.visible and _panel.get_body_text() == INSERT,
		"Trial from the selected node restarted the conversation or ignored the draft")
	_send_action(&"ui_cancel")
	_check.expect(_drawer.visible and paused, "Selected-node trial did not return to the same edit")
	_pick("node", "st_reciting")
	_drawer.action.emit("choice")
	_enter(_drawer.body, "新增选项测试")
	_drawer.new_reply.button_pressed = true
	_pick("target", "st_1") # The trial must pass the new response and still reach the old route.
	_enter(_drawer.reply, REPLY)
	_drawer.action.emit("apply")
	_check.expect(_store.change_count() == 4 and _drawer.selected("field").begins_with(Patch.ID_PREFIX),
		"Four authored edits were not accepted and saved")


func _walk_draft() -> void:
	Harness.stage = "isolated trial through new response, inserted line, and real ending"
	_drawer.action.emit("trial")
	_check.expect(_panel.visible and not _drawer.visible and paused, "Trial did not reuse detached dialogue controls")
	var third := _panel.find_child("Choice3", true, false) as Button
	_check.expect(await Harness.wait_until(func() -> bool: return not _panel._layout_dirty, 4), "Trial layout did not settle")
	_panel.reveal_choice(2)
	if _check.expect(await Harness.wait_until(func() -> bool:
		return third != null and third.is_visible_in_tree() and not _panel._layout_dirty
	, 4), "Third option could not be reached in trial"):
		await _tap(third)
	_check.expect(_panel.get_body_text() == REPLY, "New third option did not walk to its response")
	_panel.advance_requested.emit()
	_check.expect(_panel.get_body_text() == _store.nodes_for("prologue", "student").filter(
		func(node: Dictionary) -> bool: return node["id"] == "st_1")[0]["text"], "Reply skipped the original rejoin point")
	_panel.advance_requested.emit()
	_check.expect(_panel.get_body_text() == INSERT, "Original route did not pass through the inserted line")
	for index in 16:
		if _panel.has_choices():
			_panel.choice_selected.emit(0)
		else:
			_panel.advance_requested.emit()
		if not _panel.visible:
			break
	_check.expect(not _panel.visible, "Trial did not finish")
	_check.expect(not _game_state.has_flag(&"student_talked"), "Preview applied the real student_talked effect")
	await _tap(_overlay.get_node(^"BackToDraft") as Button)
	_check.expect(_drawer.visible and paused, "Returning from trial did not restore the editor")


func _edit_followups() -> void:
	Harness.stage = "authoring separate follow-ups on leave and wait"
	_pick("node", "st_reciting")
	_check.expect(_drawer.button("followup").disabled, "Follow-up should require a specific option, not just a node")
	_pick("field", "leave")
	_check.expect(not _drawer.button("followup").disabled, "The selected existing option cannot start a new round")
	if MobileLayout.enabled:
		_check.expect(_drawer.button("followup").get_combined_minimum_size().y >= MobileLayout.hit_size(_drawer),
			"Follow-up button does not meet the mobile hit target")
	_drawer.action.emit("followup")
	_enter(_drawer.body, LEAVE_ROUND[0])
	_drawer.action.emit("round_add")
	_pick("speaker", "protagonist")
	_enter(_drawer.body, LEAVE_ROUND[1])
	_pick("line", "0")
	_check.expect(_drawer.body.text == LEAVE_ROUND[0] and _drawer.selected("speaker") == "student" and not _drawer.body.has_undo(),
		"Switching draft lines lost input, speaker, or field undo isolation")
	_drawer.action.emit("apply")
	if not _check.expect(_store.change_count() == 5 and _drawer.selected("field") == "leave", "First round was not saved on leave"):
		return
	_drawer.action.emit("followup")
	_enter(_drawer.body, LEAVE_ROUND[2])
	_drawer.action.emit("apply")
	_pick("field", "wait")
	_drawer.action.emit("followup")
	_drawer.action.emit("apply")
	_check.expect(_store.change_count() == 6 and _drawer.round_placeholder.visible, "Blank unmarked line was applied or its form discarded")
	_drawer.round_placeholder.button_pressed = true
	_enter(_drawer.body, WAIT_NOTE)
	_drawer.action.emit("round_add")
	_enter(_drawer.body, WAIT_ROUND[1])
	_drawer.action.emit("round_add")
	_enter(_drawer.body, "Discard only this unsaved row")
	_drawer.action.emit("round_remove")

	Harness.stage = "recovering an unfinished multi-line form against the same option"
	_drawer.action.emit("close")
	if not _check.expect(not paused, "Closing an unfinished round did not keep the world usable"):
		return
	_store = Store.new(_directory)
	_store.load_workspace()
	_overlay.store = _store
	_overlay.open_editor()
	_check.expect(_store.change_count() == 6 and _drawer.round_placeholder.visible and _drawer.selected("line") == "1" \
		and _drawer.body.text == WAIT_ROUND[1], "Unfinished round lost the selected line or prematurely changed topology")
	_pick("line", "0")
	_check.expect(_drawer.body.text == WAIT_NOTE and _drawer.round_placeholder.button_pressed, "Placeholder note/checkbox lost on reopen")
	_drawer.action.emit("apply")
	var wait_first := _store.first_followup("prologue", "student", "st_reciting", "wait")
	var leave_first := _store.first_followup("prologue", "student", "st_reciting", "leave")
	if not _check.expect(not wait_first.is_empty() and not leave_first.is_empty() and wait_first != leave_first \
		and _drawer.selected("field") == "wait" and _store.placeholder_count() == 1, "Both existing choices did not get separate rounds"):
		return

	Harness.stage = "walking both original options in isolation and exporting a placeholder"
	await _walk_option(0, LEAVE_ROUND, "st_let_be")
	await _walk_option(1, [Patch.PLACEHOLDER + "\n" + WAIT_NOTE, WAIT_ROUND[1]], "st_1")
	_drawer.action.emit("original")
	await _walk_option(0, [], "st_let_be")
	_drawer.action.emit("original")
	var pending_path := _export_path().get_basename() + "-pending.json"
	_drawer.action.emit("export")
	var picker := _overlay.find_children("*", "FileDialog", true, false)
	if not _check.expect(picker.size() == 1, "Placeholder draft could not be explicitly exported"):
		return
	picker[0].hide()
	picker[0].file_selected.emit(pending_path)
	_check.expect(Patch.valid_envelope(Patch.read_json(pending_path)) and not _store.is_unexported(), "Placeholder export had no portable draft")

	Harness.stage = "finding and completing placeholder without changing its stable ID"
	_pick("node", "st_reciting")
	_pick("field", "wait")
	_check.expect(_drawer.button("show_followup").is_visible_in_tree(), "Existing round has no direct entry for editing")
	_drawer.action.emit("show_followup")
	_check.expect(_drawer.selected("node") == wait_first and _drawer.body.text.is_empty() and WAIT_NOTE in _panel.get_body_text(),
		"Selected placeholder could not be edited separately from its note")
	_enter(_drawer.body, WAIT_ROUND[0])
	_check.expect(await Harness.wait_until(func() -> bool:
		return _store.placeholder_count() == 0 and _panel.get_body_text() == WAIT_ROUND[0]
	, 4), "Placeholder was not replaced in place by the authored line")
	_check.expect(_store.first_followup("prologue", "student", "st_reciting", "wait") == wait_first,
		"Filling a placeholder broke its stable route ID")
	await _walk_option(1, WAIT_ROUND, "st_1")


func _walk_option(index: int, lines: Array, resume_id: String) -> void:
	_pick("node", "st_reciting")
	_drawer.action.emit("trial")
	var option := _panel.find_child("Choice%d" % (index + 1), true, false) as Button
	if _check.expect(await Harness.wait_until(func() -> bool: return not _panel._layout_dirty, 4), "Follow-up trial layout did not settle"):
		_panel.reveal_choice(index)
		if _check.expect(await Harness.wait_until(func() -> bool:
			return is_instance_valid(option) and option.is_visible_in_tree() and not _panel._layout_dirty
		, 4), "Original option %d could not be reached in trial" % index):
			await _tap(option)
			for line: String in lines:
				_check.expect(_panel.get_body_text() == line, "Option %d skipped a follow-up, changed its order, or leaked another round" % index)
				_panel.advance_requested.emit()
			var resumed := Patch.find_record(_store.nodes_for("prologue", "student"), resume_id)
			_check.expect(_panel.get_body_text() == resumed["text"], "Option %d did not continue to its original route" % index)
	_send_action(&"ui_cancel")
	_check.expect(_drawer.visible and paused, "Follow-up trial could not return to editing")


func _export_path() -> String:
	var override := OS.get_environment("WIS_TEST_AUTHOR_DRAFT")
	return override if not override.is_empty() else ProjectSettings.globalize_path(_directory.path_join("export.json"))


func _export_round_trip() -> void:
	Harness.stage = "manual JSON export and reopen"
	var export_path := _export_path()
	_drawer.action.emit("export")
	var picker := _overlay.find_children("*", "FileDialog", true, false)
	if not _check.expect(picker.size() == 1, "Export did not open the save dialog"):
		return
	picker[0].hide()
	picker[0].canceled.emit()
	_check.expect(_store.is_unexported() and not FileAccess.file_exists(export_path), "Cancelling export changed the draft or created a file")
	var protected_path := ProjectSettings.globalize_path(_directory.path_join("already-there.json"))
	var protected_file := FileAccess.open(protected_path, FileAccess.WRITE)
	protected_file.store_string("keep me")
	protected_file.close()
	_drawer.action.emit("export")
	picker[0].hide()
	picker[0].file_selected.emit(protected_path)
	_check.expect(FileAccess.get_file_as_string(protected_path) == "keep me" and _store.is_unexported(), "Export overwrote the existing destination")
	_check.expect(not Exchange.is_export_destination(ProjectSettings.globalize_path("res://data/dialogue/new-draft.json")),
		"An absolute path inside the project bypassed the dialogue export boundary")
	_drawer.action.emit("export")
	picker[0].hide() # Inject the user's explicit desktop destination, not an automatic save.
	picker[0].file_selected.emit(export_path)
	var exported := Patch.read_json(export_path)
	_check.expect(Patch.valid_envelope(exported) and not _store.is_unexported(), "Manual export did not persist the current log")
	var restored := Store.new(_directory)
	restored.load_workspace()
	_check.expect(restored.export_json() == _store.export_json(), "Fresh workspace lost the authored changes")


func _test_clear_and_undo() -> void:
	Harness.stage = "clear requires confirmation and can be undone"
	var prior := _store.export_json()
	_drawer.button("clear").pressed.emit()
	_check.expect(_store.export_json() == prior, "First press erased the draft")
	_drawer.button("clear").pressed.emit()
	_check.expect(not _store.has_exportable_changes(), "Confirmed clear did not reset the draft")
	_drawer.button("undo").pressed.emit()
	var restored := Store.new(_directory)
	restored.load_workspace()
	_check.expect(_store.export_json() == prior and restored.export_json() == prior, "Undo clear did not restore the draft on disk")


func _test_stale_form() -> void:
	Harness.stage = "a stale structure form cannot be applied as ordinary text"
	var prior := _store.export_json()
	_overlay.close_editor()
	_store.buffer = {"chapter": "prologue", "conversation": "student", "node": "st_reciting",
		"mode": "insert", "text": "Obsolete insert buffer; this node has choices."}
	_check.expect(_store.save_editor_state(), "Could not record a stale-form fixture")
	_overlay.open_editor()
	_check.expect("未恢复原表单" in _drawer.status.text and _drawer.body.text != _store.buffer["text"],
		"Obsolete insert input was presented as editable text at its old anchor")
	_overlay.close_editor()
	_check.expect(_store.export_json() == prior, "Opening an incompatible form applied its text to the draft")
	_overlay.open_editor()


func _test_local_save_failure() -> void:
	Harness.stage = "blocked local save allows safe retry and explicit temporary exit"
	var directory := _directory.path_join("blocked")
	for slot in ["draft-0.json", "draft-1.json"]:
		_check.expect(DirAccess.make_dir_recursive_absolute(directory.path_join(slot)) == OK, "Could not block journal slot")
	var workspace := Store.new(directory)
	workspace.load_workspace()
	_overlay.close_editor()
	_overlay.store = workspace
	_overlay.open_editor()
	_enter(_drawer.body, SAMPLE)
	_drawer.button("apply_text").pressed.emit()
	_check.expect(workspace.has_save_error() and _panel.get_body_text() == SAMPLE
			and "文字已保存" not in _drawer.status.text, "Write failure falsely acknowledged a preview-only edit")
	_drawer.button("close").pressed.emit()
	_check.expect(paused and _overlay.is_editing() and "会丢稿" in _drawer.status.text, "First exit did not warn about unsaved work")
	_drawer.button("close").pressed.emit()
	_check.expect(not paused and not _overlay.is_editing(), "Author could not temporarily leave on persistent failure")
	_overlay.open_editor()
	_check.expect(_drawer.body.text == SAMPLE and "未写入" in _drawer.status.text, "Temporary exit lost the in-memory work")
	for slot in ["draft-0.json", "draft-1.json"]:
		DirAccess.remove_absolute(directory.path_join(slot))
	_drawer.button("apply_text").pressed.emit()
	var reloaded := Store.new(directory)
	reloaded.load_workspace()
	_check.expect(not workspace.has_save_error() and reloaded.editable_text("prologue", "student", "st_reciting", "") == SAMPLE,
		"Retry did not make the retained input durable")
	_overlay.close_editor()
	_overlay.store = _store
	_overlay.open_editor()
	for index in 2:
		var path := directory.path_join("draft-%d.json" % index)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func _dialogue_events() -> Array:
	var log := root.get_node(^"Diagnostics")
	log.flush()
	var rows: Array = LogStore.history(log.directory_path(), EventSchema.new())["rows"]
	return rows.filter(func(row: Dictionary) -> bool: return String(row["event"]).begins_with("dialogue."))


func _try_world_input() -> void:
	var before := _snapshot()
	for action: StringName in [&"move_forward", &"interact", &"dialogue_advance", &"backlog", &"journal", &"pause"]:
		_send_action(action)
	_check.expect(paused and not (_world.get_node(^"PauseMenu") as PauseMenu).is_open() and _snapshot() == before,
		"Gameplay input reached an always-running menu or dialogue behind the drawer")


func _send_action(action: StringName) -> void:
	for down: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = down
		root.push_input(event, true)


func _snapshot() -> Array:
	var camera := _world.get_node(^"CameraRig/Camera3D") as Camera3D
	return [_controller.get_current_line().duplicate(true), _game_state.get_snapshot(), _knowledge.to_snapshot(),
		_ui.backlog.get_entries().duplicate(true), _controller.get_read_log().line_count(),
		_controller.get_read_log().choice_count(), _controller.get_playback().get_waited(),
		_controller.get_playback().mode, _controller.get_session_seed(), _player.global_position,
		camera.global_transform, _ui.dialogue_panel.get_node(^"%BodyLabel").visible_characters,
		root.get_node(^"Save").saves_written]


func _enter(field: TextEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit()


func _pick(field: String, id: String) -> void:
	var picker := _drawer.find_child("Pick_" + field, true, false) as OptionButton
	for index in picker.item_count:
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	_check.fail("No picker option %s / %s" % [field, id])


func _tap(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for down: bool in [true, false]:
		_send_mouse(point, down, false)
	await process_frame # Allow the click to propagate before asserting its result.


func _launch_touch(point: Vector2, cancelled: bool) -> void:
	for down: bool in [true, false]:
		_send_mouse(point, down, true)
		var touch := InputEventScreenTouch.new()
		touch.position = point
		touch.pressed = down
		touch.canceled = cancelled and not down
		root.push_input(touch, true)


func _send_mouse(point: Vector2, down: bool, emulated: bool) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = down
	if emulated:
		mouse.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(mouse, true)
