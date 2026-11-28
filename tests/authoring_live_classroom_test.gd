extends SceneTree
## Drive the real seated-student interaction in the staged author project, then in
## an independent regular project with only the two exported native chapters replaced.

const Harness := preload("res://tests/test_harness.gd")
const Main := preload("res://scenes/main/main.tscn")
const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const StoryEditorEntry := preload("res://scripts/ui/story_editor_entry.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const BODY := "现场测试：当前句已应用。\n验证换行与原画面。"
const FIRST := "现场测试：新增对白一。"
const HUB := "现场测试：新增对白二和四个选项。"
const NESTED := "现场测试：新选项下的第二轮。"
const UNAPPLIED := "现场测试：未应用输入应跨进程保留。"
const SAME := &"st_reciting"
const OPTION := &"wait"
const CONVERSATION := &"student"
const CHAPTER := "prologue"

var _check := Harness.Checker.new()
var _world: Node
var _controller: DialogueController
var _runtime: DialogueRuntime
var _menu: PauseMenu
var _panel: DialoguePanel
var _editor: Node
var _student: Interactable
# The native-only run also compiles on the original base, whose store has no live API.
# Only the author paths below look up the staged store.
var _store: Variant
var _events := {"lines": 0, "camera": 0, "checks": 0}


func _initialize() -> void:
	var dev_run := "--dev-run" in OS.get_cmdline_user_args()
	Harness.arm_watchdog(self, 240.0 if dev_run else 130.0, "authoring_live_classroom_test.gd")
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var imported := "--imported-chapter" in arguments
	var recovered := "--recovered" in arguments
	var dev_run := "--dev-run" in arguments
	var archive := OS.get_environment("WIS_TEST_NATIVE_ZIP")
	var profile := OS.get_environment("XDG_DATA_HOME")
	var author := root.get_node_or_null(^"Authoring")
	if not _check.expect(profile.is_absolute_path() and OS.get_user_data_dir().begins_with(profile + "/")
			and (imported or recovered or dev_run or archive.is_absolute_path()), "Use the staged projects and an isolated test data directory") \
			or not _check.expect((author == null) == (imported or dev_run), "Wrong project variant for classroom test"):
		Harness.finish(self, _check.failures, "")
		return
	if dev_run:
		if not _check.expect(not StoryEditorEntry.live_editing_allowed(), "Harness window should be refused"):
			Harness.finish(self, _check.failures, "")
			return
		StoryEditorEntry.window_forced = 1
		(root.get_node(^"Settings") as Node).call("set_story_editor_enabled", true)
	if author != null:
		# Before this file ever sets a locale itself: the staged author profile is new at boot,
		# and #395 is that it starts in the Chinese master without anyone pressing 「切到简中」.
		_check.expect(String((root.get_node(^"Loc") as Node).call("get_locale")) == "zh-CN",
			"An author run did not boot into the Simplified Chinese master (#395)")
	if not recovered:
		Harness.ensure_state_autoloads(self)
		Harness.clear_session_state(self)
	(root.get_node(^"Loc") as Node).call("set_locale", "zh-CN")
	await _boot()
	var verdict: String
	if dev_run:
		await _verify_development_live_editor()
		verdict = "ordinary development run installs, edits and releases the live line editor"
	elif imported:
		await _verify_replacement()
		verdict = "native chapter loads with authoring off"
	elif recovered:
		await _verify_restart()
		verdict = "new author process recovered the live graph, progress and unapplied input separately"
	else:
		await _edit_and_export(author, archive)
		await _verify_live_beyond_prologue()
		# The script's PASS marker for this invocation is the phrase this verdict must keep
		# leading with (`tools/authoring/test_live_classroom.sh`); #395 extends the run, it
		# does not rename it.
		verdict = "same classroom cursor edits, nested routes and bilingual export, then live " \
			+ "editing in another chapter's room"
	paused = false
	_world.queue_free()
	await process_frame
	Harness.finish(self, _check.failures, verdict)

func _boot() -> void:
	_world = Main.instantiate()
	var opening := _world.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(_world)
	current_scene = _world
	opening.allow_player_control()
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	var ui := _world.get_node(^"GameUI") as GameUI
	ui.fade.set_clear()
	_panel = ui.dialogue_panel
	_controller = _world.get_node(^"DialogueController") as DialogueController
	_runtime = _controller.get_runtime()
	_menu = _world.get_node(^"PauseMenu") as PauseMenu
	var host := _world.get_node(^"LocationHost") as LocationHost
	_student = host.get_current().find_interactable(&"student_talk")
	_controller.line_presented.connect(func(_line: Dictionary) -> void: _events["lines"] += 1)
	_controller.camera_focus_requested.connect(func(_id: StringName) -> void: _events["camera"] += 1)
	_controller.check_resolved.connect(func(_result: Dictionary) -> void: _events["checks"] += 1)
	if MobileLayout.enabled:
		Input.emulate_mouse_from_touch = true
		root.min_size = Vector2i.ZERO
		root.size = Vector2i(852, 393)
		root.set_meta(MobileLayout.TEST_SAFE_AREA, Rect2(48, 0, 756, 377))
		root.set_meta(MobileLayout.TEST_DENSITY, 1.0)
	elif DisplayServer.get_name() == "headless":
		root.size = Vector2i(1600, 900)
	# The harness assembles the real world with autostart off; announce the same
	# scene boundary the author's autoload normally sees from change_scene_to_file.
	scene_changed.emit()
	await process_frame


func _start_student() -> bool:
	if not _check.expect(is_instance_valid(_student), "The seated classroom student is missing"):
		return false
	var interaction := _world.get_node(^"Player/InteractionController") as InteractionController
	interaction.request_activation(_student)
	return _check.expect(await Harness.wait_until(func() -> bool:
		return _runtime.get_current_node_id() == SAME and _controller.has_pending_choices() and not _panel._layout_dirty
	, 6.0), "Real seated-student choices did not appear")


func _edit_and_export(author: Node, archive: String) -> void:
	Harness.stage = "staged author progress and real pause handoff"
	_editor = _world.get_node_or_null(^"LiveStoryEditor")
	root.get_node(^"Loc").call("set_locale", "en")
	if not _check.expect(_editor != null and OS.get_user_data_dir().get_file() == "Where Is School - Author",
			"Staged author runtime did not start in its own progress profile") or not await _start_student():
		return
	_store = author.get("_store")
	if not _check.expect(_store.blocked.is_empty(), "Author store rejected baseline: " + _store.blocked) or not await _open_editor():
		return
	_press("SimplifiedChinese")
	if not _check.expect(await Harness.wait_until(func() -> bool: return L10n.current == "zh-CN" and not _panel._layout_dirty, 4.0),
			"Could not switch the same paused line to the Chinese master") or not await _edit_line():
		return
	var sibling := _choice(&"leave").duplicate(true)
	if not await _edit_first_round(sibling):
		return
	if not await _walk_to_new_hub():
		return
	Harness.stage = "extend a new option in the same scene and export"
	var nested_id: StringName = _runtime.get_available_choice_ids()[1]
	if not await _open_editor() or not await _edit_choice(nested_id):
		return
	_text_field("Lines", 0).text = NESTED
	_text_field("Choices", 0).text = "测试接回原线"
	var second := _round_group("Choices").get_child(1).get_node(^"Row/Remove") as Button
	second.pressed.emit()
	_press("ApplyRound")
	if not _check.expect(not _button("ApplyRound").is_visible_in_tree(), "Could not apply a nested round"):
		return
	_press("ContinueGame")
	_walk_nested(nested_id)
	_finish_old_route()
	_check.expect(_store.live_buffer.is_empty(), "An applied form was left in recovery")
	if not await _keep_unapplied_and_export(archive):
		return
	var result: Dictionary = root.get_node(^"Save").call("save_game")
	_check.expect(result.get("ok", false) and FileAccess.file_exists("user://save.json"), "Author progress did not write to its real save")
	_check.expect(FileAccess.file_exists(ReadLog.DEFAULT_PATH), "Author traversal did not use its own read-log file")


func _keep_unapplied_and_export(archive: String) -> bool:
	Harness.stage = "export only the committed rounds, leaving a different option's input unsent"
	if not _check.expect(_controller.play_conversation(CONVERSATION), "Could not revisit the original hub") \
			or not await _open_editor() or not await _edit_choice(&"leave"):
		return false
	_text_field("Lines", 0).text = UNAPPLIED
	_press("KeepRound")
	if not _check.expect(not _store.live_buffer.is_empty(), "New unfinished input was not saved") or not _export(archive):
		return false
	_press("ContinueGame")
	_controller.select_choice(_runtime.get_available_choice_ids().find(&"leave"))
	_check.expect(_runtime.get_current_node_id() == &"st_let_be", "Unapplied input changed B's original destination")
	_controller.advance_presentation()
	return true


func _verify_restart() -> void:
	Harness.stage = "reuse the author profile from a new process (without resetting the save)"
	_editor = _world.get_node_or_null(^"LiveStoryEditor")
	var save := root.get_node(^"Save")
	var progress: Dictionary = save.call("load_game")
	_check.expect(progress.get("ok", false) and root.get_node(^"GameState").get_flag(&"student_talked", false),
		"Author gameplay progress could not be loaded in a new process")
	_check.expect(_controller.get_read_log().line_count() > 0, "Author read log did not survive restart")
	if not _check.expect(_editor != null, "Author editor did not reattach on restart") or not await _start_student():
		return
	_check.expect(_panel.get_body_text() == BODY, "Real dialogue did not use the recovered text")
	if not await _open_editor(): return
	_press("ResumeInput")
	if not _check.expect(_button("ApplyRound").is_visible_in_tree(), "Unapplied option form did not recover after restart"):
		return
	_check.expect(_text_field("Lines", 0).text == UNAPPLIED, "Recovered form did not contain the saved input")
	_press("KeepRound")
	_press("ContinueGame")
	if await _walk_to_new_hub():
		_walk_nested(_runtime.get_available_choice_ids()[1])
		_finish_old_route()


## The author's tool at every point of the game, not a prologue classroom extra (#395): leave
## the classroom for another room, start a conversation from a different chapter, and the pause
## handoff must land in the live editor on that line. While a real dialogue is on screen the
## drawer is a degradation - it is what the entry must NOT fall back to outside the prologue.
func _verify_live_beyond_prologue() -> void:
	Harness.stage = "live editing beyond the prologue, in another room"
	_editor = _world.get_node_or_null(^"LiveStoryEditor")
	var host := _world.get_node(^"LocationHost") as LocationHost
	var player := _world.get_node(^"Player") as PlayerController
	var ui := _world.get_node(^"GameUI") as GameUI
	# A paused tree swallows the layout pass that clears the panel's dirty flag, so the
	# wait below would starve on a line that is on screen. The classroom phase should
	# have ended unpaused; if it did not, hand the pause back the way the flow does.
	if paused:
		if _editor != null and bool(_editor.call("is_editing")):
			_editor.call("close_editor")
		elif _editor != null:
			_press("ContinueGame")
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return not paused
		, 4.0), "The world was still paused when the corridor began (#395)"):
			return
	if not _check.expect(_editor != null and host.load_location(
			"res://scenes/locations/corridor/corridor.tscn", &"FromClassroom", player, &"corridor"),
			"Could not move the author's run out of the prologue classroom (#395)"):
		return
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return host.get_current() != null and host.get_current().location_id == &"corridor" and not ui.fade.visible
	, 6.0), "The corridor did not load"):
		return
	# A conversation the classroom left running refuses play_conversation; the corridor must
	# start on an idle controller or the wait below would starve on a line that never began.
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return not _controller.is_busy()
	, 4.0), "The classroom conversation never went idle before the corridor"):
		_press("ContinueGame")
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return not _controller.is_busy()
		, 4.0), "Still busy after an advance; the corridor chapter cannot start"):
			return
	if not _check.expect(_controller.play_conversation(&"corridor_speaker"),
			"A non-prologue chapter's conversation would not start"):
		return
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _runtime.get_active_conversation_id() == &"corridor_speaker" \
				and _panel.is_visible_in_tree()
	, 6.0), "The corridor line did not reach the real panel (active=%s mode=%s panel_shown=%s paused=%s)" % [
			str(_runtime.get_active_conversation_id()), str(_controller.get_mode()),
			str(_panel.is_visible_in_tree()), str(paused)]):
		return
	# Settled geometry is what the click below needs, so ask for it - but with a bound:
	# the handoff and the edit are the acceptance, and if a panel that keeps re-queuing
	# its layout still edits, that is the fact the next assertion should report, with
	# this state attached, rather than a timeout that never says which condition held.
	if not await Harness.wait_until(func() -> bool: return not _panel._layout_dirty, 3.0):
		# A red run's log is not readable from CI, so this rides the annotation stream
		# instead: the extraction in test_live_classroom.sh carries TEST FAILURE lines.
		# On a green run it is an ERROR line nothing greps for, and the run stays green.
		push_error("TEST FAILURE: corridor panel layout never settled (stage=%s revealing=%s edit_line_valid=%s)"
			% [str(_panel._layout_stage), str(_panel.is_revealing()),
				str(_panel._edit_line.is_valid())])
	if not await _open_editor(): return
	var drawer := _world.get_node_or_null(^"AuthorOverlay/AuthorDrawer")
	var live_open := bool(_editor.call("is_editing"))
	_check.expect(live_open and paused,
		"The corridor dialogue did not open the live editor (#395)")
	_check.expect(drawer == null or not bool((drawer as CanvasItem).visible),
		"The corridor dialogue degraded to the draft drawer (#395)")
	if not live_open:
		# Recording the miss above is the verdict; editing a drawer that is not the live
		# editor would only turn one red bar into a null dereference.
		return
	# The classroom phase deliberately kept an unapplied input, and by design a buffered
	# input at one address refuses to begin editing at any other (#395's corridor line is
	# another address). Drop it here the way the panel's own notice tells the author to -
	# but keep a copy: the recovery invocation that follows this one is *built* on that
	# kept input, so the corridor visit must put the journal back exactly as it found it.
	var kept_input: Dictionary = _store.live_buffer.duplicate(true)
	if not kept_input.is_empty():
		_press("DiscardInput")
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return _store.live_buffer.is_empty()
		, 3.0), "Could not discard the classroom's unapplied input before the corridor edit"):
			return
	if not _check.expect(_runtime.get_current_node_id() == &"cs_1",
			"The corridor runtime was not on cs_1 before the edit (node=%s)"
			% str(_runtime.get_current_node_id())) \
			or not _check.expect(_panel._edit_line.is_valid(),
				"The corridor live editor did not bind the panel's edit callback"):
		return
	if not await _edit_line(&"cs_1"):
		return
	_press("ContinueGame")
	_check.expect(not bool(_editor.call("is_editing")) and not paused,
		"Closing on the corridor line did not hand the world back")
	if not kept_input.is_empty():
		_check.expect(_store.save_live_buffer(kept_input),
			"The corridor visit could not put the classroom's kept input back for the "
			+ "recovery run")


func _verify_development_live_editor() -> void:
	if not _check.expect(root.get_node_or_null(^"StoryEditor") != null and _world.has_node(^"LiveStoryEditor"), "Development window did not install live editor"): return
	_editor = _world.get_node(^"LiveStoryEditor")
	_store = _editor.get("store")
	if not await _start_student() or not await _open_editor() or not await _edit_line():
		return
	var before := _world_snapshot()
	if not await _edit_first_round(_choice(&"leave").duplicate(true)):
		return
	_check.expect(_world_snapshot() == before,
		"Adding the next dialogue round changed the running story cursor or effects")
	_press("ContinueGame")
	if not await _open_editor():
		return
	_press("EditLine")
	var live: Node = _world.get_node(^"LiveStoryEditor")
	var body := live.find_child("InlineBody", true, false) as TextEdit
	body.text = "release failure keeps this text"
	var saved_store: Variant = live.get("store")
	var refusing := Store.new("user://story_editor/release-refusal", true)
	refusing.blocked = "fixture refuses journal writes"
	live.set("store", refusing)
	(root.get_node(^"Settings") as Node).call("set_story_editor_enabled", false)
	await process_frame
	_check.expect(root.get_node_or_null(^"StoryEditor") != null and _world.has_node(^"LiveStoryEditor")
			and _world.has_node(^"AuthorOverlay") and paused and bool(live.call("is_editing"))
			and body.text == "release failure keeps this text",
		"A refused live-buffer save destroyed the editor or its unsaved text")
	live.set("store", saved_store)
	_press("ContinueGame")
	if not await Harness.wait_until(func() -> bool: return root.get_node_or_null(^"StoryEditor") == null and not _world.has_node(^"LiveStoryEditor"), 4.0):
		_check.expect(false, "A successful retry did not finish the deferred mode-off release")
		return
	_check.expect(String(saved_store.get("live_buffer").get("text", "")) == "release failure keeps this text",
		"The pending input did not survive the refused close and successful retry")
	_check.expect(not paused and not _controller._author_editing and not _panel._edit_line.is_valid(),
		"Mode off did not restore world controls")
	(root.get_node(^"Settings") as Node).call("set_story_editor_enabled", true)
	if not await Harness.wait_until(func() -> bool: return root.get_node_or_null(^"StoryEditor") != null and _world.has_node(^"LiveStoryEditor") and _world.has_node(^"AuthorOverlay"), 4.0):
		_check.expect(false, "Re-enabling the setting did not install the editor again")
		return
	if not await _open_editor(): return
	_editor = _world.get_node(^"LiveStoryEditor")
	_press("ExportChapter")
	if not _check.expect(bool(_editor.get("_exchange").call("is_busy")), "Chapter export did not open a file exchange"): return
	(root.get_node(^"Settings") as Node).call("set_story_editor_enabled", false)
	_check.expect(root.get_node_or_null(^"StoryEditor") != null and _world.has_node(^"LiveStoryEditor")
			and paused and bool(_editor.call("is_editing")),
		"Mode off destroyed the editor during a file exchange")
	var dialog: FileDialog = _editor.get("_exchange").get("_file_dialog")
	dialog.hide()
	dialog.canceled.emit()
	if not await Harness.wait_until(func() -> bool: return root.get_node_or_null(^"StoryEditor") == null and not _world.has_node(^"LiveStoryEditor"), 4.0):
		_check.expect(false, "Cancelling the exchange did not finish the pending release")
		return
	_check.expect(not paused and not _controller._author_editing and not _panel._edit_line.is_valid(),
		"Exchange cancellation did not restore game input state")
	StoryEditorEntry.window_forced = -1


func _edit_line(expected: StringName = SAME) -> bool:
	Harness.stage = "single/double click on the real reading surface and in-place redraw"
	var before := _world_snapshot()
	var shown := _panel.get_body_text()
	var body := _editor.find_child("InlineBody", true, false) as TextEdit
	if not _check.expect(body != null, "The live editor has no inline body to edit"):
		return false
	var point := _panel.get_body_label().get_global_rect().get_center()
	if MobileLayout.enabled:
		await _tap(_button("EditLine"), true)
	else:
		_send_mouse(point, false)
		_check.expect(not body.visible and _panel.get_body_text() == shown, "First click advanced or opened the editor")
		_send_mouse(point, true)
	if not _check.expect(body.is_visible_in_tree() and _runtime.get_current_node_id() == expected,
			"Original dialogue box did not open its inline text entry"):
		return false
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.unicode = 32
	space.pressed = true
	root.push_input(space, true)
	_check.expect(_runtime.get_current_node_id() == expected and paused, "Typing an advance key took a live action")
	body.text = "  \n"
	_press("ApplyLine")
	_check.expect(body.visible and _panel.get_body_text() == shown, "Blank text replaced the live line")
	body.text = BODY
	_press("ApplyLine")
	return _check.expect(not body.visible and _panel.get_body_text() == BODY and _panel.get_body_label().visible_characters == -1
		and _controller.get_runtime() == _runtime and _runtime.get_current_node_id() == expected
		and _world_snapshot() == before, "Application replaced the panel/runner or replayed the line, effects, or read/history")


func _edit_first_round(sibling: Dictionary) -> bool:
	Harness.stage = "partial round keeps the original route; complete round changes only that edge"
	if not await _edit_choice(OPTION):
		return false
	var before := _choice(OPTION).duplicate(true)
	_press("AddLine")
	_press("AddChoice")
	_press("AddChoice")
	_text_field("Lines", 0).text = FIRST
	_text_field("Lines", 1).text = HUB
	_text_field("Choices", 0).text = "现场测试选项一"
	_press("ApplyRound")
	_check.expect(_choice(OPTION) == before and _button("ApplyRound").is_visible_in_tree(), "Invalid round disconnected a real option")
	_press("KeepRound")
	_check.expect(not _store.live_buffer.is_empty(), "Unfinished round was not journaled")
	_press("ContinueGame")
	if not _check.expect(not paused and _runtime.get_current_node_id() == SAME and _choice(OPTION) == before,
			"Leaving with a partial form changed the active route") or not await _open_editor():
		return false
	_press("ResumeInput")
	_check.expect(_text_field("Lines", 0).text == FIRST and _round_group("Choices").get_child_count() == 4,
		"Recovered form no longer has its two sentences and four choices")
	for index in range(1, 4):
		_text_field("Choices", index).text = "现场测试选项 %d" % (index + 1)
	var target := _round_group("Choices").get_child(3).get_node(^"Row/Target") as OptionButton
	for index in target.item_count:
		if target.get_item_metadata(index) == "st_quiet":
			target.select(index)
	var snapshot := _world_snapshot()
	_press("ApplyRound")
	if not _check.expect(_world_snapshot() == snapshot and _panel.get_body_text() == BODY and _choice(&"leave") == sibling
			and _choice(OPTION)["next"] != before["next"], "Applying A replayed the hub, replaced its sibling, or did not attach"):
		return false
	_press("ContinueGame")
	return true


func _walk_to_new_hub() -> bool:
	var index := _runtime.get_available_choice_ids().find(OPTION)
	if not _check.expect(index >= 0, "Original option is missing after returning to play"):
		return false
	_panel.reveal_choice(index)
	if not _check.expect(await Harness.wait_until(func() -> bool: return not _panel._layout_dirty, 4.0), "Resumed options did not settle"):
		return false
	await _tap(_panel.get_choice_buttons()[index], MobileLayout.enabled)
	if not _check.expect(_controller.get_runtime() == _runtime and _panel.get_body_text() == FIRST, "Actual choice did not enter the first new line"):
		return false
	if _editor != null and not MobileLayout.enabled:
		if not await _open_editor():
			return false
		var cursor := _runtime.get_current_node_id()
		var revealing := _panel.is_revealing()
		_send_mouse(_panel.get_body_label().get_global_rect().get_center(), false)
		_check.expect(_runtime.get_current_node_id() == cursor and _panel.is_revealing() == revealing,
			"A single click on a plain line finished the reveal or advanced it while paused")
		_press("ContinueGame")
	_controller.advance_presentation()
	return _check.expect(_panel.get_body_text() == HUB and _runtime.get_available_choice_ids().size() == 4,
		"Actual runtime did not reach the second line with all four stable options")


func _walk_nested(id: StringName) -> void:
	_controller.select_choice(_runtime.get_available_choice_ids().find(id))
	_check.expect(_panel.get_body_text() == NESTED and _runtime.get_available_choice_ids().size() == 1, "Could not enter the second round in the same runner")
	# Both locale graphs must retain the new cursor, including while the EN is pending.
	root.get_node(^"Loc").call("set_locale", "en")
	_check.expect(_panel.get_body_text() == "〔待译〕 " + NESTED and _runtime.get_available_choice_ids().size() == 1,
		"English candidate lost a new node or presented it as finished translation")
	root.get_node(^"Loc").call("set_locale", "zh-CN")
	_controller.select_choice(0)
	_check.expect(_runtime.get_current_node_id() == &"st_1", "Nested choice did not return to the original route")


func _finish_old_route() -> void:
	for step in 20:
		if not _controller.is_busy():
			break
		if _controller.has_pending_choices():
			_controller.select_choice(0)
		else:
			_controller.advance_presentation()
	_check.expect(not _controller.is_busy() and root.get_node(^"GameState").get_flag(&"student_talked", false),
		"The unmodified ending of the conversation did not finish or apply its existing effect")


func _verify_replacement() -> void:
	Harness.stage = "the same classroom in an ordinary project with native files only"
	_check.expect(_world.get_node_or_null(^"LiveStoryEditor") == null and _menu.get_story_entry() == null,
		"The replacement test accidentally loaded an editor")
	_check.expect(_controller.get_dialogue_library().is_valid(), "Native chapters did not pass the normal loader and parity checks")
	if not await _start_student():
		return
	_check.expect(_panel.get_body_text() == BODY, "Native chapter did not show the authored line without editor code")
	_controller.select_choice(_runtime.get_available_choice_ids().find(&"leave"))
	_check.expect(_runtime.get_current_node_id() == &"st_let_be", "Unchanged sibling cannot be played without authoring")
	_controller.advance_presentation()
	if _check.expect(_controller.play_conversation(CONVERSATION), "Could not replay the classroom conversation") and await _walk_to_new_hub():
		_walk_nested(_runtime.get_available_choice_ids()[1])
		_finish_old_route()


func _open_editor() -> bool:
	_menu.open()
	if not _check.expect(_menu.get_story_entry() != null and _menu.open_story_editor(), "Pause menu did not hand off to the live editor"):
		return false
	return _check.expect(await Harness.wait_until(func() -> bool: return paused and not _panel._layout_dirty, 4.0),
		"The original panel did not lay out while the world was paused")


func _edit_choice(id: StringName) -> bool:
	var index := _runtime.get_available_choice_ids().find(id)
	if not _check.expect(index >= 0, "The desired stable option is no longer on screen"):
		return false
	_panel.reveal_choice(index)
	if not _check.expect(await Harness.wait_until(func() -> bool: return not _panel._layout_dirty, 4.0), "Choices did not settle"):
		return false
	var option := _panel.get_choice_buttons()[index]
	var edit := option.get_parent().get_node_or_null(^"EditChoice") as Button
	if not _check.expect(edit != null and edit.is_visible_in_tree(), "Missing edit control beside actual option"):
		return false
	var before := _runtime.get_current_node_id()
	await _tap(option, MobileLayout.enabled)
	_check.expect(_runtime.get_current_node_id() == before, "Original option was still selectable during edit mode")
	if MobileLayout.enabled:
		_check.expect(MobileLayout.safe_rect(edit).encloses(edit.get_global_rect()) and edit.size.y >= MobileLayout.hit_size(edit),
			"The option edit control is outside the safe area or too small")
	await _tap(edit, MobileLayout.enabled)
	return _check.expect(_button("ApplyRound").is_visible_in_tree() and _runtime.get_current_node_id() == before,
		"The actual option's Edit button selected the option instead of editing it")


func _export(path: String) -> bool:
	_press("ExportChapter")
	var dialogs := _editor.find_children("*", "FileDialog", true, false)
	if not _check.expect(dialogs.size() == 1, "Export whole chapter did not open the picker"):
		return false
	var dialog := dialogs[0] as FileDialog
	dialog.hide()
	dialog.canceled.emit()
	_check.expect(not FileAccess.file_exists(path), "Cancelled export created a chapter")
	_press("ExportChapter")
	dialog.hide()
	dialog.file_selected.emit(path)
	return _check.expect(FileAccess.file_exists(path), "Export did not write a checked native archive")


func _world_snapshot() -> Array:
	return [current_scene.get_instance_id(), _runtime.get_instance_id(), _panel.get_instance_id(),
		_panel.modulate, _runtime.get_current_node_id(), _runtime._steps, _events.duplicate(),
		root.get_node(^"GameState").get_snapshot(), root.get_node(^"NarrativeState").to_snapshot(),
		(_world.get_node(^"GameUI") as GameUI).backlog.get_entries().size(), _controller.get_read_log().line_count(),
		_controller.get_read_log().choice_count(), (_world.get_node(^"CameraRig/Camera3D") as Camera3D).global_transform,
		(_world.get_node(^"Player") as PlayerController).global_position]


func _choice(id: StringName) -> Dictionary:
	var hub := Patch.find_record(_store.nodes_for(CHAPTER, String(CONVERSATION)), String(SAME))
	return Patch.find_record(Patch.choices_at(hub), String(id))


func _round_group(name: String) -> VBoxContainer:
	return _editor.find_child("NextRound", true, false).find_child(name, true, false) as VBoxContainer


func _text_field(group: String, index: int) -> TextEdit:
	return _round_group(group).get_child(index).get_node(^"Text") as TextEdit


func _button(name: String) -> Button:
	return _editor.find_child(name, true, false) as Button


func _press(name: String) -> void:
	_button(name).pressed.emit()


func _tap(control: Control, touch: bool = false) -> void:
	_send_mouse(control.get_global_rect().get_center(), false, touch)
	await process_frame # Real press and release propagation.


func _send_mouse(point: Vector2, double: bool, touch: bool = false) -> void:
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.pressed = down
		mouse.double_click = double and down
		if touch:
			mouse.device = InputEvent.DEVICE_ID_EMULATION
		root.push_input(mouse, true)
