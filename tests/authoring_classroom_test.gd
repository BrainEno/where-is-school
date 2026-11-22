extends SceneTree
## Open the drawer over the real seated-student interaction, edit and walk the
## new route, export it, then continue the original encounter without contamination.

const Harness := preload("res://tests/test_harness.gd")
const Bootstrap := preload("res://scripts/dev/authoring/bootstrap.gd")
const Overlay := preload("res://scripts/dev/authoring/author_overlay.gd")
const Form := preload("res://scripts/dev/authoring/author_form.gd")
const Store := preload("res://scripts/dev/authoring/draft_store.gd")
const Exchange := preload("res://scripts/dev/authoring/author_exchange.gd")
const LogStore := preload("res://scripts/diagnostics/log_store.gd")
const EventSchema := preload("res://scripts/diagnostics/event_schema.gd")
const Patch := preload("res://scripts/dev/authoring/dialogue_patch.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const MainScene := preload("res://scenes/main/main.tscn")
const SAMPLE := "文案测试：一行。\n第二行，龘。"
const OPTION := "流程测试选项"
const REPLY := "独立试玩的回应"
const INSERT := "插入对白的测试"

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
		await _edit_branches()
		await _walk_draft()
		_export_round_trip()
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
	root.add_child(bootstrap)
	if not _check.expect(await Harness.wait_until(func() -> bool:
		var entry := _world.get_node_or_null(^"AuthorOverlay/EditStory") as Button
		return entry != null and entry.is_visible_in_tree()
	, 5), "Author bootstrap did not attach to the live game"):
		return false
	_overlay = _world.get_node(^"AuthorOverlay") as Overlay
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


func _edit_branches() -> void:
	Harness.stage = "editing graph through drawer"
	_pick("node", "st_1")
	_drawer.action.emit("insert")
	_enter(_drawer.body, INSERT)
	_drawer.action.emit("apply")
	_check.expect(_drawer.selected("node").begins_with(Patch.ID_PREFIX), "Inserted line was not selected in the drawer")
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


func _export_round_trip() -> void:
	Harness.stage = "manual JSON export and reopen"
	var export_path := OS.get_environment("WIS_TEST_AUTHOR_DRAFT")
	if export_path.is_empty():
		export_path = ProjectSettings.globalize_path(_directory.path_join("export.json"))
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
