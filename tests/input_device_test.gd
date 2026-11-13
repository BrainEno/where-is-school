extends SceneTree
## Synthetic end-to-end check of input-device detection and shared prompt presentation.
##
## A genuine InputEvent is injected through Viewport.push_input, then the real Settings
## autoload and a GameHud instance are observed. This verifies transitions, live InputMap
## labels, mouse affordances, controller disconnect fallback, and that a device change does
## not replay/synthesize an interaction.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const HUD_SCRIPT := "res://scripts/ui/hud.gd"
const DIALOGUE_SCENE := "res://scenes/ui/dialogue_panel.tscn"

class InputProbe:
	extends Node
	var events: Array[InputEvent] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed() and not event.is_echo():
			events.append(event.duplicate())

	func count_action(action: StringName) -> int:
		var total := 0
		for event: InputEvent in events:
			if event.is_action_pressed(action):
				total += 1
		return total


var _failures: Array[String] = []
var _settings: Node = null
var _hud: GameHud = null
var _dialogue: DialoguePanel = null
var _probe: InputProbe = null
var _checks := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "input_device_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	_settings = Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if _settings == null:
		Harness.finish(self, ["Settings autoload could not be created."], "")
		return
	_settings.call("restore_default_bindings")
	_settings.call("set_input_device", &"keyboard")
	_hud = _make_hud()
	root.add_child(_hud)
	_probe = InputProbe.new()
	root.add_child(_probe)
	await process_frame
	_hud.set_prompt_text("Talk")
	_expect(_hud.get_prompt_text().begins_with("[E]"), "Keyboard prompt is not the InputMap E binding.")
	var dialogue_scene := load(DIALOGUE_SCENE) as PackedScene
	if dialogue_scene == null:
		Harness.finish(self, ["dialogue_panel.tscn could not be loaded."], "")
		return
	_dialogue = dialogue_scene.instantiate() as DialoguePanel
	root.add_child(_dialogue)
	await process_frame
	_expect(
		String(_dialogue.call("_hint_text")).contains("[Space]"),
		"Dialogue hint is not using the keyboard advance binding."
	)

	# An unbound controller button chooses the pad presentation without activating anything.
	await _push_pad(JOY_BUTTON_GUIDE)
	_expect(_settings.call("get_input_device") == &"gamepad", "Controller button did not select gamepad prompts.")
	_expect(_hud.get_prompt_text().begins_with("[A]"), "The HUD did not redraw its prompt as the mapped A button.")
	var pad_dialogue_hint := String(_dialogue.call("_hint_text"))
	_expect(
		pad_dialogue_hint.contains("[A]") and pad_dialogue_hint.contains("[Y]"),
		"Dialogue hints did not switch to the mapped A/Y pad buttons: %s." % pad_dialogue_hint
	)
	_expect(_probe.count_action(&"interact") == 0, "A device-only controller input triggered an interaction.")

	# The action's real button is injected once. The detector must not replay it when it
	# emits input_device_changed; the probe should see exactly one original event.
	_probe.events.clear()
	await _push_pad(JOY_BUTTON_A)
	_expect(_probe.events.size() == 1, "A controller input was replayed or duplicated (%d events)." % _probe.events.size())
	_expect(_settings.call("is_using_gamepad"), "A controller press changed prompts back to keyboard.")

	# A real key returns to keyboard labels. The mappings are read live, not guessed.
	_probe.events.clear()
	await _push_key(KEY_E)
	_expect(_settings.call("get_input_device") == &"keyboard", "Keyboard key did not restore keyboard prompts.")
	_expect(_hud.get_prompt_text().begins_with("[E]"), "Keyboard prompt did not return to E.")
	_expect(_probe.events.size() == 1, "Keyboard input was replayed or duplicated.")

	# Pointer motion selects the mouse prompt family; mouse-clickable world actions show a
	# localized click affordance instead of continuing to claim that E is the active device.
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(7.0, 2.0)
	root.push_input(mouse)
	await process_frame
	_expect(_settings.call("get_input_device") == &"mouse", "Mouse motion did not select mouse prompts.")
	_expect(_hud.get_prompt_text().begins_with("[%s]" % L10n.t("key.click")), "Mouse prompt is not the localized click affordance.")
	_expect(
		String(_dialogue.call("_hint_text")).begins_with(L10n.t("key.click")),
		"Dialogue advance did not use the mouse-specific hint."
	)

	# The action labels used elsewhere are all derived from actual InputMap bindings.
	_settings.call("set_input_device", &"keyboard")
	_expect(MenuStyle.key(_hud, &"interact") == "E", "Interact keyboard label is not E.")
	_expect(MenuStyle.key(_hud, &"dialogue_advance") == "Space", "Dialogue keyboard label is not Space.")
	_expect(MenuStyle.key(_hud, &"backlog") == "Tab", "Log keyboard label is not Tab.")
	var keyboard_confirm := String(_settings.call("binding_label", &"ui_accept", &"keyboard"))
	_expect(
		MenuStyle.key(_hud, &"ui_accept") == MenuStyle.local_key_name(keyboard_confirm),
		"Menu confirm hint differs from the active InputMap binding."
	)
	_settings.call("set_input_device", &"gamepad")
	_expect(MenuStyle.key(_hud, &"interact") == "A", "Interact gamepad label is not the mapped A button.")
	_expect(MenuStyle.key(_hud, &"dialogue_advance") == "A", "Continue gamepad label is not the mapped A button.")
	_expect(MenuStyle.key(_hud, &"backlog") == "Y", "Log gamepad label is not the mapped Y button.")
	_expect(MenuStyle.key(_hud, &"cancel") == "B", "Cancel gamepad label is not the mapped B button.")

	# Simulate the callback Godot sends when the active pad is removed. Keyboard is always
	# an available fallback, even if no key has been pressed since the disconnect.
	_settings.call("_on_joy_connection_changed", 0, false)
	_expect(_settings.call("get_input_device") == &"keyboard", "Disconnect did not fall back to keyboard prompts.")
	_expect(MenuStyle.key(_hud, &"interact") == "E", "Disconnect fallback did not restore the keyboard binding.")

	_hud.queue_free()
	_dialogue.queue_free()
	_probe.queue_free()
	await process_frame
	Harness.finish(
		self,
		_failures,
		"synthetic key, mouse and pad events switch prompts; bindings match InputMap; "
		+ "disconnect falls back to keyboard; and switching never duplicates an action."
	)


func _make_hud() -> GameHud:
	var hud := Control.new()
	hud.set_script(load(HUD_SCRIPT))
	hud.name = "HUDInputProbe"
	for label_name in [&"ObjectiveLabel", &"PromptLabel", &"LanguageLabel"]:
		var label := Label.new()
		label.name = String(label_name)
		hud.add_child(label)
	return hud as GameHud


func _push_pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	root.push_input(event)
	await process_frame


func _push_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
