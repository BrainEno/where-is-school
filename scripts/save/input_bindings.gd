class_name InputBindings
extends RefCounted
## The rules of the player's input bindings: how an event is written to `settings.cfg` and
## read back, how it is named on screen, which inputs two actions may share, and what a
## stored list must satisfy before it is applied.
##
## Split out of the `Settings` autoload (`settings_manager.gd`, issue #223). `Settings`
## keeps the state - the defaults it captured, the active device, the file it writes - and
## every public method; this script is static, holds no state, and touches nothing but the
## `InputMap` it is asked about. `Settings` re-exports the constants and the static
## functions below under their old names (`Settings.encode_event`, `SHARED_PAIRS`, ...), so
## nothing that called them had to change.
##
## **Format.** One short string per event: `key:69` (a physical keycode), `mouse:1`,
## `joy_button:0`, `joy_axis:1:-`. Anything else does not encode, and a stored list with
## one entry that does not decode is rejected whole - never half-applied.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_MOUSE := &"mouse"
const DEVICE_TOUCH := &"touch"
const DEVICE_GAMEPAD := &"gamepad"
const DEVICES: Array[StringName] = [DEVICE_KEYBOARD, DEVICE_MOUSE, DEVICE_GAMEPAD, DEVICE_TOUCH]

## Everything the settings screen lets the player rebind, in the order it lists them.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint",
	&"interact", &"dialogue_advance", &"backlog", &"journal", &"cancel", &"pause",
	&"toggle_language", &"toggle_fullscreen", &"dialogue_auto", &"dialogue_skip",
]
## Pairs that may share an input because they never listen at the same time: the same
## button uses a thing in the room and continues a line of dialogue, and Esc both closes
## the log and opens the menu (the log takes it first).
const SHARED_PAIRS: Array = [
	[&"interact", &"dialogue_advance"],
	[&"cancel", &"pause"],
]
## Rebinding never offers these: Esc cancels a capture, so it cannot be captured.
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE]
## Actions whose keyboard key is Esc and stays Esc, so a keyboard player can always reach
## the menus and close what is open. Their controller buttons can still be rebound.
const KEYBOARD_LOCKED_ACTIONS: Array[StringName] = [&"cancel", &"pause"]

## Xbox-style names, which is what SDL reports for most pads.
const JOY_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
}

## The menu actions every controller must be able to drive, and the button each needs.
const UI_NAVIGATION_BUTTONS: Dictionary = {
	&"ui_accept": JOY_BUTTON_A,
	&"ui_cancel": JOY_BUTTON_B,
	&"ui_up": JOY_BUTTON_DPAD_UP,
	&"ui_down": JOY_BUTTON_DPAD_DOWN,
	&"ui_left": JOY_BUTTON_DPAD_LEFT,
	&"ui_right": JOY_BUTTON_DPAD_RIGHT,
}


# --- Events ------------------------------------------------------------------


## The device family `event` shows the player is using, or `current` when it shows
## nothing. Mouse motion counts, so pointer users see click affordances; axis noise below
## the gameplay deadzone and the mouse events a touch screen emulates do not.
static func detected_device(event: InputEvent, current: StringName) -> StringName:
	if MobileLayout.is_emulated_mouse(event):
		return current
	if MobileLayout.enabled and event is InputEventScreenTouch and event.is_pressed():
		return DEVICE_TOUCH
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		return DEVICE_GAMEPAD
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		return DEVICE_GAMEPAD
	if event is InputEventKey and (event as InputEventKey).pressed:
		return DEVICE_KEYBOARD
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		return DEVICE_MOUSE
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length_squared() > 0.0:
		return DEVICE_MOUSE
	return current


static func is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## A short name for an input: "E", "Space", "Mouse 1", "A", "D-pad ↑", "LS ←".
static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var text := OS.get_keycode_string(code)
		return text if not text.is_empty() else "?"
	if event is InputEventMouseButton:
		return "Mouse %d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		var index := int((event as InputEventJoypadButton).button_index)
		return String(JOY_BUTTON_NAMES.get(index, "Button %d" % index))
	if event is InputEventJoypadMotion:
		return _axis_label(event as InputEventJoypadMotion)
	return "?"


static func _axis_label(motion: InputEventJoypadMotion) -> String:
	var positive := motion.axis_value > 0.0
	match int(motion.axis):
		JOY_AXIS_LEFT_X:
			return "LS →" if positive else "LS ←"
		JOY_AXIS_LEFT_Y:
			return "LS ↓" if positive else "LS ↑"
		JOY_AXIS_RIGHT_X:
			return "RS →" if positive else "RS ←"
		JOY_AXIS_RIGHT_Y:
			return "RS ↓" if positive else "RS ↑"
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
	return "Axis %d" % int(motion.axis)


## `key:69`, `mouse:1`, `joy_button:0`, `joy_axis:1:-`. Empty for anything else.
static func encode_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode != KEY_NONE:
			return "key:%d" % int(key.physical_keycode)
		return ""
	if event is InputEventMouseButton:
		return "mouse:%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "joy_button:%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "joy_axis:%d:%s" % [int(motion.axis), "+" if motion.axis_value > 0.0 else "-"]
	return ""


## The inverse of `encode_event`, or null for anything that is not a valid binding.
static func decode_event(text: String) -> InputEvent:
	var event := _decode_event(text)
	if event != null:
		# Any keyboard, any pad: a second controller is the same player.
		event.device = -1
	return event


static func _decode_event(text: String) -> InputEvent:
	var parts := text.strip_edges().split(":")
	if parts.size() < 2:
		return null
	for index in range(1, parts.size()):
		if index == 2 and parts[0] == "joy_axis":
			continue
		if not parts[index].is_valid_int():
			return null
	match parts[0]:
		"key":
			if parts.size() != 2:
				return null
			var code := parts[1].to_int()
			if code <= 0 or OS.get_keycode_string(code).is_empty():
				return null
			var key := InputEventKey.new()
			key.physical_keycode = code as Key
			return key
		"mouse":
			if parts.size() != 2:
				return null
			var button := parts[1].to_int()
			if button < MOUSE_BUTTON_LEFT or button > MOUSE_BUTTON_XBUTTON2:
				return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = button as MouseButton
			return mouse
		"joy_button":
			if parts.size() != 2:
				return null
			var joy_index := parts[1].to_int()
			if joy_index < 0 or joy_index >= JOY_BUTTON_SDL_MAX:
				return null
			var joy := InputEventJoypadButton.new()
			joy.button_index = joy_index as JoyButton
			return joy
		"joy_axis":
			if parts.size() != 3 or (parts[2] != "+" and parts[2] != "-"):
				return null
			var axis := parts[1].to_int()
			if axis < 0 or axis >= JOY_AXIS_SDL_MAX:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis as JoyAxis
			motion.axis_value = 1.0 if parts[2] == "+" else -1.0
			return motion
	return null


## The encoded form of every event, in order.
static func encoded(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for event: InputEvent in events:
		out.append(encode_event(event))
	return out


## Every entry must decode, and the list must not be empty; otherwise nothing is used.
## Duplicates collapse to the first.
static func decode_list(value: Variant) -> Array:
	var items: Array = []
	if value is PackedStringArray:
		for text: String in (value as PackedStringArray):
			items.append(text)
	elif value is Array:
		items = (value as Array).duplicate()
	else:
		return []
	var events: Array = []
	var seen: Dictionary = {}
	for item: Variant in items:
		if not (item is String or item is StringName):
			return []
		var event := decode_event(String(item))
		if event == null:
			return []
		var code := encode_event(event)
		if seen.has(code):
			continue
		seen[code] = true
		events.append(event)
	return events


# --- The input map -------------------------------------------------------------


## The defaults of every rebindable action, as `project.godot` declares them - read from
## the project settings rather than from the live input map, which may already carry the
## player's rebinding. `{action: Array[InputEvent]}`, every event a fresh copy.
static func project_defaults() -> Dictionary:
	var defaults: Dictionary = {}
	for action: StringName in REBINDABLE_ACTIONS:
		var events: Array = []
		var declared: Variant = ProjectSettings.get_setting("input/%s" % action, null)
		if declared is Dictionary:
			for item: Variant in ((declared as Dictionary).get("events", []) as Array):
				if item is InputEvent:
					events.append((item as InputEvent).duplicate())
		elif InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				events.append(event.duplicate())
		defaults[action] = events
	return defaults


## Godot's built-in menu actions get the pad's D-pad, A and B if the engine's defaults do
## not already include them, so every menu can be driven from a controller.
static func ensure_ui_navigation() -> void:
	for action: StringName in UI_NAVIGATION_BUTTONS.keys():
		if not InputMap.has_action(action):
			continue
		var button := int(UI_NAVIGATION_BUTTONS[action])
		var present := false
		for event: InputEvent in InputMap.action_get_events(action):
			var joy := event as InputEventJoypadButton
			if joy != null and int(joy.button_index) == button:
				present = true
				break
		if not present:
			var added := InputEventJoypadButton.new()
			added.button_index = button as JoyButton
			InputMap.action_add_event(action, added)


## Replaces every event of `action` with `events`. Does nothing for an unknown action.
static func apply_events(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


static func may_share(first: StringName, second: StringName) -> bool:
	for pair: Array in SHARED_PAIRS:
		if pair.has(first) and pair.has(second):
			return true
	return false


## The first other action using one of `action`'s inputs, apart from the shared pairs.
static func conflict_of(action: StringName) -> StringName:
	var mine := encoded(InputMap.action_get_events(action))
	for other: StringName in REBINDABLE_ACTIONS:
		if other == action or may_share(action, other) or not InputMap.has_action(other):
			continue
		for code: String in encoded(InputMap.action_get_events(other)):
			if mine.has(code):
				return other
	return StringName()


# --- Rebinding one input ---------------------------------------------------------


## Whether `event` may become `action`'s input. Returns `{ok, reason, conflict, clean}`:
## `reason` is "unknown_action", "unsupported", "reserved" or "conflict" when it may not,
## and `clean` is the event as it would be stored (any device) when it may.
static func check_rebind(action: StringName, event: InputEvent) -> Dictionary:
	var result := {"ok": false, "reason": "", "conflict": &"", "clean": null}
	if not REBINDABLE_ACTIONS.has(action) or not InputMap.has_action(action):
		result["reason"] = "unknown_action"
		return result
	var encoded_event := encode_event(event)
	if encoded_event.is_empty() or decode_event(encoded_event) == null or event is InputEventMouseButton:
		result["reason"] = "unsupported"
		return result
	var clean := decode_event(encoded_event)
	var key := clean as InputEventKey
	if key != null and (
		RESERVED_KEYS.has(int(key.physical_keycode)) or KEYBOARD_LOCKED_ACTIONS.has(action)
	):
		result["reason"] = "reserved"
		return result
	for other: StringName in REBINDABLE_ACTIONS:
		if other == action or may_share(action, other) or not InputMap.has_action(other):
			continue
		for existing: InputEvent in InputMap.action_get_events(other):
			if encode_event(existing) == encoded_event:
				result["reason"] = "conflict"
				result["conflict"] = other
				return result
	result["ok"] = true
	result["clean"] = clean
	return result


## `action`'s events with `clean` in place of the first event of the same family (the
## key for a key, the pad input for a pad input), or appended when it has none; the same
## input twice is one input. `matches_family(event, device)` decides the family.
static func events_with(action: StringName, clean: InputEvent, device: StringName,
		matches_family: Callable) -> Array:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var replaced := false
	for index in events.size():
		if bool(matches_family.call(events[index], device)):
			events[index] = clean
			replaced = true
			break
	if not replaced:
		events.append(clean)
	var seen: Dictionary = {}
	var out: Array = []
	for item: InputEvent in events:
		var code := encode_event(item)
		if seen.has(code):
			continue
		seen[code] = true
		out.append(item)
	return out


# --- Stored lists ------------------------------------------------------------------


## The rules `rebind` keeps one input at a time, checked on a whole stored list: a file
## edited by hand or written by another build must not take Esc away from the menus, give
## Esc to anything else, or leave an action without a key or a controller input it has by
## default. Empty when the list is fine; otherwise what is wrong with it.
static func broken_rule(action: StringName, events: Array, defaults: Array) -> String:
	var keys := PackedStringArray()
	var has_key := false
	var has_pad := false
	for event: InputEvent in events:
		if event is InputEventKey:
			has_key = true
			keys.append(encode_event(event))
		elif is_gamepad_event(event):
			has_pad = true
	var default_keys := PackedStringArray()
	var default_has_pad := false
	for event: InputEvent in defaults:
		if event is InputEventKey:
			default_keys.append(encode_event(event))
		elif is_gamepad_event(event):
			default_has_pad = true
	if KEYBOARD_LOCKED_ACTIONS.has(action):
		if keys != default_keys:
			return "changes the keyboard side, which stays Esc"
	else:
		for reserved: int in RESERVED_KEYS:
			if keys.has("key:%d" % reserved):
				return "binds a reserved key"
	if not has_key and not default_keys.is_empty():
		return "leaves the action without a key"
	if not has_pad and default_has_pad:
		return "leaves the action without a controller input"
	return ""


## Applies the `[input]` section of `config` to the input map. Every action is assumed to
## be at its defaults already; `defaults_of(action)` returns fresh copies of them. Every
## rejected entry is appended to `problems`, and the action keeps its defaults.
static func load_section(config: ConfigFile, section: String, defaults_of: Callable,
		problems: Array[String]) -> void:
	if not config.has_section(section):
		return
	var loaded: Array[StringName] = []
	for key: String in config.get_section_keys(section):
		var action := StringName(key)
		if not REBINDABLE_ACTIONS.has(action):
			problems.append("[input] %s is not a rebindable action" % key)
			continue
		var value: Variant = config.get_value(section, key)
		var decoded := decode_list(value)
		if decoded.is_empty():
			problems.append(
				"[input] %s = %s is not a valid binding list; defaults kept" % [key, str(value)]
			)
			continue
		var broken := broken_rule(action, decoded, defaults_of.call(action))
		if not broken.is_empty():
			problems.append("[input] %s = %s %s; defaults kept" % [key, str(value), broken])
			continue
		apply_events(action, decoded)
		loaded.append(action)
	drop_loaded_conflicts(loaded, defaults_of, problems)


## Two actions on one input is what `rebind` refuses, and a stored file can still say it:
## edited by hand, or two lists that were each fine against the defaults. The action read
## last goes back to its defaults until nothing clashes; the defaults never clash, so this
## ends, and it does not depend on the order the file lists a valid swap in.
static func drop_loaded_conflicts(loaded: Array[StringName], defaults_of: Callable,
		problems: Array[String]) -> void:
	var index := loaded.size() - 1
	while index >= 0:
		var action := loaded[index]
		var other := conflict_of(action)
		if String(other).is_empty():
			index -= 1
			continue
		problems.append("[input] %s shares an input with %s; defaults kept" % [action, other])
		apply_events(action, defaults_of.call(action))
		loaded.remove_at(index)
		index = loaded.size() - 1
