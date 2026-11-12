class_name InputHint
extends RefCounted
## One presentation path for action names shown in prompts, menus and dialogue.
##
## The active device comes from the Settings autoload. Bindings are always read from the
## live InputMap through Settings, so rebinding an action changes the hint immediately.
## Mouse is a presentation family of its own: pointer-driven world interaction and
## dialogue clicks are labelled as clicks, while other actions keep their keyboard key.

const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_MOUSE := &"mouse"
const DEVICE_GAMEPAD := &"gamepad"


static func device(node: Node) -> StringName:
	var settings := _settings(node)
	if settings != null and settings.has_method("get_input_device"):
		return StringName(settings.call("get_input_device"))
	return DEVICE_KEYBOARD


static func is_gamepad(node: Node) -> bool:
	return device(node) == DEVICE_GAMEPAD


## A compact label for an action, reflecting the current device and active binding.
## Mouse world clicks can activate interactables, and a click advances a dialogue line.
static func action_key(node: Node, action: StringName) -> String:
	var active_device := device(node)
	if active_device == DEVICE_MOUSE and action in [&"interact", &"dialogue_advance"]:
		return L10n.t("key.click") if L10n.has_key("key.click") else "Click"
	var settings := _settings(node)
	var label := ""
	if settings != null and settings.has_method("binding_label"):
		var binding_device := DEVICE_GAMEPAD if active_device == DEVICE_GAMEPAD else DEVICE_KEYBOARD
		label = String(settings.call("binding_label", action, binding_device))
	else:
		label = _input_map_label(action, active_device)
	return local_key_name(label)


## Godot names keys in English; common controls have a short local spelling.
static func local_key_name(label: String) -> String:
	var lookup := "key.%s" % label.to_lower()
	return L10n.t(lookup) if L10n.has_key(lookup) else label


static func _settings(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_node_or_null(^"/root/Settings")


static func _input_map_label(action: StringName, active_device: StringName) -> String:
	if not InputMap.has_action(action):
		return String(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if active_device == DEVICE_GAMEPAD and (
			event is InputEventJoypadButton or event is InputEventJoypadMotion
		):
			return event.as_text().trim_suffix(" (Physical)")
		if active_device != DEVICE_GAMEPAD and event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return String(action)
