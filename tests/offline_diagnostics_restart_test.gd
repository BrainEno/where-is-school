extends SceneTree
## Two separate game processes share only an isolated user:// directory. No test
## calls the export API: the settings buttons receive actual viewport key events.

const Harness := preload("res://tests/test_harness.gd")
const Log := preload("res://scripts/autoload/diagnostics.gd")
const SessionScript := preload("res://scripts/ui/game_session.gd")
const SaveScript := preload("res://scripts/autoload/save_manager.gd")
const REPORT_PATH := Log.LOG_DIR + "/" + Log.EXPORT_NAME
const PRIVATE_MARKER := "MOCK_PRIVATE_DIAGNOSTICS_PATH"

var checks := Harness.Checker.new()
var _session: Node
var _save: Node
var _state: Node


func _initialize() -> void:
	Harness.arm_watchdog(self, 50.0, "offline_diagnostics_restart_test.gd")
	_run.call_deferred()


func _run() -> void:
	# Prevent this test from ever using a player's real save/log directory by mistake.
	var isolated := OS.get_environment("DIAGNOSTICS_TEST_HOME")
	var data_dir := OS.get_user_data_dir()
	if not checks.expect(not isolated.is_empty() and data_dir.begins_with(isolated + "/"),
			"Use the isolated runner (tests/run_offline_diagnostics.sh)."):
		_finish()
		return
	var args := OS.get_cmdline_user_args()
	if not checks.expect(args.size() == 1 and args[0] in ["collect", "export"],
			"Select exactly one phase: collect or export."):
		_finish()
		return
	_session = root.get_node_or_null(^"Session")
	_save = root.get_node_or_null(^"Save")
	_state = root.get_node_or_null(^"GameState")
	var loc := root.get_node_or_null(^"Loc")
	if not checks.expect(_session != null and _save != null and _state != null and loc != null,
			"The game's autoloads are missing."):
		_finish()
		return
	loc.set_locale("zh-CN")
	if not checks.expect(change_scene_to_file(SessionScript.TITLE_SCENE) == OK, "Cannot load the actual title scene."):
		_finish()
		return
	await scene_changed
	var title := current_scene as TitleScreen
	if not checks.expect(title != null, "The real title scene did not enter the tree."):
		_finish()
		return
	if args[0] == "collect":
		await _collect(title)
	else:
		await _export_phase(title)
	_finish()


func _collect(title: TitleScreen) -> void:
	if not checks.expect(not FileAccess.file_exists(REPORT_PATH) and not _save.has_save(),
			"The first launch must start with a fresh save and no export."):
		return
	title.focus_entry(&"new_game")
	await _tap(KEY_ENTER)
	if not checks.expect(await Harness.wait_until(_world_ready, 18.0), "Start did not enter the actual game world."):
		return
	var host := current_scene.get_node("LocationHost") as LocationHost
	var before := host.get_current()
	# Inject a refusal at the real location boundary; nothing in the world should move.
	var missing := "res://" + PRIVATE_MARKER + "/missing.tscn"
	var changed := host.load_location(missing, &"", current_scene.get_node("Player"), &"corridor")
	checks.expect(not changed and host.get_current() == before, "The failed transition changed the world.")
	# Use the real save system to create the warning, not a diagnostics-only test call.
	_state.set_flag(&"private_fixture", PRIVATE_MARKER)
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, false)
	if not checks.expect(_save.save_game()["ok"], "Could not write a real checkpoint for the recovery fixture."):
		return
	var backup := SaveScript.SAVE_PATH + ".diagnostics-fixture.bak"
	if not checks.expect(DirAccess.rename_absolute(SaveScript.SAVE_PATH, backup) == OK,
			"Could not simulate the interrupted save swap."):
		return
	checks.expect(_save.recover_pending_swap()["recovered"], "The real save recovery warning was not reached.")
	checks.expect(_session.go_to_title()["ok"], "Could not return to the title.")
	await scene_changed
	var exit_title := current_scene as TitleScreen
	if not checks.expect(exit_title != null, "Could not reach the title's Quit entry."):
		return
	exit_title.focus_entry(&"quit")
	# Verify all assertions before pressing Quit, which must be the code path ending
	# the process. The next launch checks that the teardown event made it to disk.
	if checks.failures.is_empty():
		print("PASS: 第一进程：实际游戏进入地点，模拟存档恢复警告与场景切换错误，经标题退出。")
		await _tap(KEY_ENTER)
		checks.fail("The title Quit button did not close the process.")


func _export_phase(title: TitleScreen) -> void:
	if not checks.expect(not FileAccess.file_exists(REPORT_PATH), "The first run must not pre-generate the report."):
		return
	title.focus_entry(&"settings")
	await _tap(KEY_ENTER)
	var panel := title.get_settings_panel()
	var report := await _use_export_button(panel)
	if report.is_empty():
		return
	var runtime: Dictionary = report["runtime"]
	checks.expect(runtime["scene_id"] == "title" and runtime["location_id"] == null,
		"Restart at the title should show no current location, even with a checkpoint.")
	var events: Array = report["events"]
	checks.expect(_has_event(events, "session.ended", "INFO"), "No normal exit event survived the first process.")
	checks.expect(_has_event(events, "save.recovered", "WARNING"), "No real save warning survived restart.")
	checks.expect(_has_event(events, "world.transition_refused", "ERROR", "scene_missing"),
		"No real transition failure and reason survived restart.")
	checks.expect(_has_event(events, "world.entered", "INFO") and _has_event(events, "save.written", "INFO"),
		"The real location and checkpoint traces are missing.")
	checks.expect(not FileAccess.file_exists(Log.LOG_DIR + "/godot.log"),
		"The desktop engine wrote its unsanitized default log.")
	checks.expect(String(report["game_version"]) != "unknown" and String(report["godot_version"]).begins_with("4.")
		and report["os"] == OS.get_name() and report["privacy"]["local_only"],
		"Export lacks game/engine version, platform family or privacy note.")
	await _tap(KEY_ESCAPE)
	title.focus_entry(&"continue")
	await _tap(KEY_ENTER)
	if not checks.expect(await Harness.wait_until(_world_ready, 18.0), "Continue did not load after restart."):
		return
	var pause_menu := current_scene.get_node("PauseMenu") as PauseMenu
	pause_menu.open()
	pause_menu.focus_entry(&"settings")
	await _tap(KEY_ENTER)
	var world_report := await _use_export_button(pause_menu.get_settings_panel())
	if not world_report.is_empty():
		var live: Dictionary = world_report["runtime"]
		checks.expect(live["scene_id"] == "world" and live["location_id"] == "classroom" and live["paused"]
			and live["flags"] == {"left_classroom": false} and live["dialogue"]["active"] is bool,
			"The paused world export lacks the current room or includes non-allowlisted state.")
		checks.expect(_has_event(world_report["events"], "save.loaded", "INFO"), "Continue left no load trace.")
		print("诊断包：%d 条结构化记录；核查标题与暂停菜单、实际重启、隔离存档和隐私。" % world_report["events"].size())
	pause_menu.close()


func _use_export_button(panel: SettingsPanel) -> Dictionary:
	if not checks.expect(panel.is_open() and panel.get_row_control(&"open_logs") != null
			and panel.get_row_control(&"export_diagnostics") != null,
			"The player did not reach Settings with both diagnostic actions."):
		return {}
	panel.focus_row(&"export_diagnostics")
	await _tap(KEY_ENTER)
	var text := FileAccess.get_file_as_string(REPORT_PATH)
	var report: Variant = JSON.parse_string(text)
	checks.expect(Log.EXPORT_NAME in panel.get_status_text(), "Settings did not report a successful export.")
	checks.expect(not PRIVATE_MARKER in text and not OS.get_user_data_dir() in text
		and not "res://" in text and not "private_fixture" in text and not "save.json" in text,
		"The exported package contains paths, raw console text, or save fixture data.")
	if checks.expect(report is Dictionary, "Settings did not produce a readable JSON report."):
		return report
	return {}


func _world_ready() -> bool:
	if current_scene == null or current_scene.scene_file_path != SessionScript.MAIN_SCENE:
		return false
	var host := current_scene.get_node_or_null("LocationHost") as LocationHost
	return host != null and host.get_current() != null and not _session.is_starting_new_game()


func _has_event(events: Array, event: String, level: String, reason: String = "") -> bool:
	for row: Dictionary in events:
		if row["event"] == event and row["level"] == level \
				and (reason.is_empty() or row["context"].get("reason") == reason):
			return true
	return false


func _tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var input := InputEventKey.new()
		input.keycode = key
		input.physical_keycode = key
		input.pressed = pressed
		root.push_input(input)
		await process_frame


func _finish() -> void:
	Harness.finish(self, checks.failures, "第二进程从玩家设置导出并读取了跨进程离线诊断包。")
