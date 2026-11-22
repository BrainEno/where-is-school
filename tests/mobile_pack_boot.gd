extends SceneTree
## One smoke test against the exported game pack, with no editor preview arguments,
## preview metrics, or test files packed into the retail app. Run with --main-pack and
## --script from an isolated runner or Simulator data container.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const TITLE := "res://scenes/ui/title_screen.tscn"


func _initialize() -> void:
	create_timer(50.0, true, false, true).timeout.connect(_fail.bind("packed mobile smoke timed out"))
	call_deferred("_run")


func _run() -> void:
	if not OS.has_feature("wis_handheld") or MobileLayout.preview or not MobileLayout.enabled:
		_fail("the exported pack did not enable the handheld layout itself")
		return
	# A script launch can omit the project's ordinary autoloads. Use the authentic
	# runtime scripts, in order, if the engine has not already installed them.
	var autoloads := {
		"GameState": "res://scripts/autoload/game_state.gd",
		"NarrativeState": "res://scripts/autoload/narrative_state.gd",
		"Save": "res://scripts/autoload/save_manager.gd",
		"Loc": "res://scripts/i18n/loc.gd",
		"Settings": "res://scripts/autoload/settings_manager.gd",
		"Session": "res://scripts/ui/game_session.gd",
	}
	for node_name: String in autoloads:
		if root.has_node(NodePath(node_name)):
			continue
		var script := load(autoloads[node_name]) as Script
		var singleton: Node = script.new()
		singleton.name = node_name
		root.add_child(singleton)
	Input.emulate_mouse_from_touch = true
	if change_scene_to_file(TITLE) != OK:
		_fail("could not boot the packed title")
		return
	await scene_changed
	var title := current_scene as TitleScreen
	if title == null or title.get_entry_ids().has(&"quit"):
		_fail("the packed title still exposes desktop Quit")
		return
	root.remove_child(title)
	title.queue_free()
	var world := MAIN.instantiate()
	var opening := world.get_node(^"OpeningSequence") as OpeningSequence
	opening.autostart = false
	root.add_child(world)
	current_scene = world
	opening.allow_player_control()
	var ui := world.get_node(^"GameUI") as GameUI
	ui.fade.set_clear()
	var touch_menu := ui.get_node_or_null(^"TouchActions/Pause") as Button
	var use := ui.get_node_or_null(^"TouchActions/Use") as Button
	var stick := ui.get_node_or_null(^"TouchActions/Joystick") as Control
	if touch_menu == null or use == null or stick == null:
		_fail("the packed world did not construct its gameplay controls")
		return
	var settings := root.get_node(^"Settings")
	settings.set_input_device(InputHint.DEVICE_MOUSE)
	await process_frame
	if not touch_menu.is_visible_in_tree() or not use.is_visible_in_tree() or not stick.is_visible_in_tree():
		_fail("the packed controls are hidden with pointer hints")
		return
	var pause_menu := world.get_node(^"PauseMenu") as PauseMenu
	await _tap(touch_menu)
	await process_frame
	if not pause_menu.is_open() or not paused:
		_fail("the packed menu button did not pause gameplay")
		return
	await _tap(pause_menu.get_entry(&"resume"))
	await process_frame
	if pause_menu.is_open() or paused:
		_fail("the packed menu did not return to gameplay")
		return
	print("DEVICE_PACK_TOUCH_OK os=%s engine=%s handheld=true preview=false" % [
		OS.get_name(), Engine.get_version_info()["string"]])
	quit()


func _tap(control: Control) -> void:
	for down: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = root.get_final_transform() * control.get_global_rect().get_center()
		touch.pressed = down
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await process_frame


func _fail(reason: String) -> void:
	print("DEVICE_PACK_TOUCH_FAILURE: " + reason)
	quit(1)
