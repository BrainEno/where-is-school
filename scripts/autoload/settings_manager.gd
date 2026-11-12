extends Node
## Autoload `Settings`: the player's text, sound, display and input preferences.
##
## One file, `user://settings.cfg`, shared with `Loc` (which owns `[display] locale`).
## Every write here loads the file first and only touches the keys this node owns, so a
## language choice is never lost to a volume change and the other way round.
##
## What is stored, and how it is checked on the way back in:
##
## - `[text] size` — one of `TEXT_SIZES`; every on-screen text is multiplied by its scale.
## - `[text] speed` — one of `TEXT_SPEEDS`; how fast a line types itself out.
## - `[audio] master|music|sfx` — whole percentages, 0..100.
## - `[display] ui_scale` — one of `UI_SCALES`, "auto" by default (see `effective_ui_scale`).
## - `[input] <action>` — every event of a rebound action, as short strings
##   (`key:69`, `joy_button:0`, `joy_axis:1:-`, `mouse:1`). An action whose stored list
##   does not decode completely is put back to its defaults, never half-applied.
##
## A value of the wrong type or outside its list is replaced by the default and reported in
## `get_load_problems()`; nothing here throws a player back to an unusable control scheme.
##
## The defaults are what `project.godot` declares: they are read from the `InputMap` at
## startup, before anything is applied, so "restore defaults" can never drift from the
## project file.

signal setting_changed(key: StringName)
signal bindings_changed
signal input_device_changed(device: StringName)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_TEXT := "text"
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_INPUT := "input"
const SECTION_META := "settings"
const FORMAT_VERSION := 1

const TEXT_SIZES: Array[StringName] = [&"standard", &"large", &"largest"]
const TEXT_SIZE_SCALE: Dictionary = {&"standard": 1.0, &"large": 1.15, &"largest": 1.3}
const DEFAULT_TEXT_SIZE := &"standard"

const TEXT_SPEEDS: Array[StringName] = [&"slow", &"normal", &"fast", &"instant"]
## Characters per second. 0 means the whole line appears at once.
const TEXT_SPEED_CPS: Dictionary = {&"slow": 28.0, &"normal": 55.0, &"fast": 110.0, &"instant": 0.0}
const DEFAULT_TEXT_SPEED := &"normal"

const VOLUME_KEYS: Array[StringName] = [&"master", &"music", &"sfx"]
const VOLUME_BUS: Dictionary = {&"master": &"Master", &"music": &"Music", &"sfx": &"SFX"}
const DEFAULT_VOLUME := 100

const UI_SCALES: Array[StringName] = [&"auto", &"100", &"125", &"150", &"200"]
const DEFAULT_UI_SCALE := &"auto"
## The window size the interface is designed and checked at (CI measures 1280x720 to
## 1920x1080). "Auto" starts enlarging the 2D layer only beyond the largest of those.
const UI_REFERENCE_SIZE := Vector2(1920.0, 1080.0)
## The smallest logical size the layout is verified at. A manual scale is capped so the
## interface never gets less room than this.
const UI_MINIMUM_LOGICAL := Vector2(1280.0, 720.0)

const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_GAMEPAD := &"gamepad"

## Everything the settings screen lets the player rebind, in the order it lists them.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint",
	&"interact", &"dialogue_advance", &"backlog", &"cancel", &"pause",
	&"toggle_language", &"toggle_fullscreen",
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

var _text_size: StringName = DEFAULT_TEXT_SIZE
var _text_speed: StringName = DEFAULT_TEXT_SPEED
var _ui_scale: StringName = DEFAULT_UI_SCALE
var _volumes: Dictionary = {}
## The bus levels `default_bus_layout.tres` sets, read once: 100 % means "as mixed".
var _bus_trim: Dictionary = {}
## action -> Array[InputEvent], as `project.godot` declares them.
var _default_events: Dictionary = {}
var _load_problems: Array[String] = []
var _device: StringName = DEVICE_KEYBOARD
var _applying_scale := false
var _applied_ui_scale := 1.0


func _ready() -> void:
	# Menus run while the tree is paused, and they read and write through this node.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key: StringName in VOLUME_KEYS:
		_volumes[key] = DEFAULT_VOLUME
	_capture_bus_trim()
	_capture_default_bindings()
	_ensure_ui_navigation()
	load_settings()
	get_tree().node_added.connect(_on_node_added)
	var root := get_tree().root
	if root != null and not root.size_changed.is_connected(_apply_ui_scale):
		root.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


# --- Text --------------------------------------------------------------------


func get_text_size() -> StringName:
	return _text_size


func set_text_size(value: StringName) -> void:
	if not TEXT_SIZES.has(value) or value == _text_size:
		return
	_text_size = value
	_store(SECTION_TEXT, "size", String(value))
	setting_changed.emit(&"text_size")


## The multiplier every text size in the interface is drawn at.
func text_scale() -> float:
	return float(TEXT_SIZE_SCALE.get(_text_size, 1.0))


## The largest multiplier the settings can produce, for the layout tests.
static func max_text_scale() -> float:
	var best := 1.0
	for size: StringName in TEXT_SIZES:
		best = maxf(best, float(TEXT_SIZE_SCALE[size]))
	return best


func get_text_speed() -> StringName:
	return _text_speed


func set_text_speed(value: StringName) -> void:
	if not TEXT_SPEEDS.has(value) or value == _text_speed:
		return
	_text_speed = value
	_store(SECTION_TEXT, "speed", String(value))
	setting_changed.emit(&"text_speed")


## Characters per second for the dialogue reveal; 0 means "show the whole line at once".
func reveal_characters_per_second() -> float:
	return float(TEXT_SPEED_CPS.get(_text_speed, 55.0))


# --- Sound -------------------------------------------------------------------


func get_volume(key: StringName) -> int:
	return int(_volumes.get(key, DEFAULT_VOLUME))


func set_volume(key: StringName, percent: int) -> void:
	if not VOLUME_KEYS.has(key):
		return
	var clamped := clampi(percent, 0, 100)
	if clamped == get_volume(key):
		return
	_volumes[key] = clamped
	_apply_volume(key)
	_store(SECTION_AUDIO, String(key), clamped)
	setting_changed.emit(StringName("volume_%s" % key))


## The level a bus is actually at for a percentage: the layout's own trim plus the dial.
func bus_db_for(key: StringName, percent: int) -> float:
	var trim := float(_bus_trim.get(key, 0.0))
	if percent <= 0:
		return -80.0
	return trim + linear_to_db(float(percent) / 100.0)


## The trim is the level `default_bus_layout.tres` gives each bus, read from the file
## rather than from the live bus, which may already carry a dial's setting.
func _capture_bus_trim() -> void:
	var authored := _authored_bus_levels()
	for key: StringName in VOLUME_KEYS:
		var bus_name := String(VOLUME_BUS[key])
		if authored.has(bus_name):
			_bus_trim[key] = float(authored[bus_name])
			continue
		var index := AudioServer.get_bus_index(VOLUME_BUS[key])
		_bus_trim[key] = AudioServer.get_bus_volume_db(index) if index != -1 else 0.0


func _authored_bus_levels() -> Dictionary:
	var levels: Dictionary = {}
	var path := String(
		ProjectSettings.get_setting("audio/buses/default_bus_layout", "res://default_bus_layout.tres")
	)
	if not ResourceLoader.exists(path):
		return levels
	var layout := load(path) as AudioBusLayout
	if layout == null:
		return levels
	for index in 16:
		var bus_name: Variant = layout.get("bus/%d/name" % index)
		if bus_name == null:
			break
		var level: Variant = layout.get("bus/%d/volume_db" % index)
		levels[String(bus_name)] = float(level) if level != null else 0.0
	return levels


func _apply_volume(key: StringName) -> void:
	var percent := get_volume(key)
	var index := AudioServer.get_bus_index(VOLUME_BUS[key])
	if index != -1:
		AudioServer.set_bus_mute(index, percent <= 0)
		AudioServer.set_bus_volume_db(index, bus_db_for(key, percent))
	if key == &"sfx":
		# The interaction cues own no bus by design (`cue_audio.gd`): the SFX dial reaches
		# them through their own gain instead.
		var cues := get_node_or_null(^"/root/CueAudio")
		if cues != null and cues.has_method("set_gain_db"):
			var gain := -80.0 if percent <= 0 else linear_to_db(float(percent) / 100.0)
			cues.call("set_gain_db", gain)


func _apply_all_volumes() -> void:
	for key: StringName in VOLUME_KEYS:
		_apply_volume(key)


## Room tones (`AmbiencePlayer`) are authored in location scenes on the default bus. They
## are sound effects as far as the player is concerned, so they are moved onto `SFX` as
## they enter the tree - the location scenes themselves stay as they are.
func _on_node_added(node: Node) -> void:
	var player := node as AudioStreamPlayer
	if player == null:
		return
	if player is AmbiencePlayer and player.bus == &"Master":
		player.bus = &"SFX"


# --- Display -------------------------------------------------------------------


func get_ui_scale() -> StringName:
	return _ui_scale


func set_ui_scale(value: StringName) -> void:
	if not UI_SCALES.has(value) or value == _ui_scale:
		return
	_ui_scale = value
	_store(SECTION_DISPLAY, "ui_scale", String(value))
	_apply_ui_scale()
	setting_changed.emit(&"ui_scale")


## The factor the 2D layer is drawn at for a window size and a choice.
##
## The layouts are measured at 1280x720, 1600x900 and 1920x1080, in real pixels. On a
## bigger window ("auto") the whole interface layer is enlarged in quarter steps so a 4K
## screen draws it like 1080p at twice the density, instead of as a postage stamp. A
## manual choice is capped so the logical size never drops below 1280x720, the smallest
## size the layout is checked at; at the three verified sizes "auto" is exactly 1.
static func effective_ui_scale(window_size: Vector2, choice: StringName) -> float:
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return 1.0
	var room := minf(
		window_size.x / UI_MINIMUM_LOGICAL.x, window_size.y / UI_MINIMUM_LOGICAL.y
	)
	var wanted := 1.0
	if choice == &"auto" or not UI_SCALES.has(choice):
		var ratio := minf(
			window_size.x / UI_REFERENCE_SIZE.x, window_size.y / UI_REFERENCE_SIZE.y
		)
		wanted = floorf(ratio * 4.0) / 4.0
	else:
		wanted = float(String(choice).to_int()) / 100.0
	return maxf(1.0, minf(wanted, floorf(room * 4.0) / 4.0))


func get_applied_ui_scale() -> float:
	return _applied_ui_scale


func _apply_ui_scale() -> void:
	if _applying_scale:
		return
	var root := get_tree().root
	if root == null:
		return
	_applying_scale = true
	var window_size := Vector2(root.size)
	var factor := effective_ui_scale(window_size, _ui_scale)
	if is_equal_approx(factor, 1.0):
		if root.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	else:
		var logical := Vector2i(
			roundi(window_size.x / factor), roundi(window_size.y / factor)
		)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		if root.content_scale_size != logical:
			root.content_scale_size = logical
	_applied_ui_scale = factor
	_applying_scale = false


# --- Input ---------------------------------------------------------------------


func get_input_device() -> StringName:
	return _device


func is_using_gamepad() -> bool:
	return _device == DEVICE_GAMEPAD


## Which hand is on the controls, so prompts can name the right button. Mouse motion does
## not count: a pad player who nudges the mouse should keep seeing pad prompts.
func _input(event: InputEvent) -> void:
	var device := _device
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		device = DEVICE_GAMEPAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		device = DEVICE_GAMEPAD
	elif event is InputEventKey and (event as InputEventKey).pressed:
		device = DEVICE_KEYBOARD
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		device = DEVICE_KEYBOARD
	if device != _device:
		_device = device
		input_device_changed.emit(device)


## For tests and for the menus: say which device is in use without a real event.
func set_input_device(device: StringName) -> void:
	if device != DEVICE_KEYBOARD and device != DEVICE_GAMEPAD:
		return
	if device == _device:
		return
	_device = device
	input_device_changed.emit(device)


## The defaults are what `project.godot` declares, read from the project settings rather
## than from the live input map, which may already carry the player's rebinding.
func _capture_default_bindings() -> void:
	_default_events.clear()
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
		_default_events[action] = events


## The default events of an action, as `project.godot` declares them.
func default_events(action: StringName) -> Array:
	var events: Array = []
	for event: InputEvent in (_default_events.get(action, []) as Array):
		events.append(event.duplicate())
	return events


## Godot's built-in menu actions get the pad's D-pad, A and B if the engine's defaults do
## not already include them, so every menu can be driven from a controller.
func _ensure_ui_navigation() -> void:
	var wanted: Dictionary = {
		&"ui_accept": JOY_BUTTON_A,
		&"ui_cancel": JOY_BUTTON_B,
		&"ui_up": JOY_BUTTON_DPAD_UP,
		&"ui_down": JOY_BUTTON_DPAD_DOWN,
		&"ui_left": JOY_BUTTON_DPAD_LEFT,
		&"ui_right": JOY_BUTTON_DPAD_RIGHT,
	}
	for action: StringName in wanted.keys():
		if not InputMap.has_action(action):
			continue
		var button := int(wanted[action])
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


func is_keyboard_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


func is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _matches_device(event: InputEvent, device: StringName) -> bool:
	if device == DEVICE_GAMEPAD:
		return is_gamepad_event(event)
	return event is InputEventKey


## The event the settings screen shows and replaces for an action on a device: the first
## key for the keyboard, the first button or stick direction for the pad.
func primary_event(action: StringName, device: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if _matches_device(event, device):
			return event
	return null


## A short name for what triggers an action on a device: "E", "Space", "A", "D-pad ↑".
func binding_label(action: StringName, device: StringName = &"") -> String:
	var which := device if not String(device).is_empty() else _device
	var event := primary_event(action, which)
	if event == null and which == DEVICE_GAMEPAD:
		event = primary_event(action, DEVICE_KEYBOARD)
	if event == null:
		return "—"
	return event_label(event)


## Instance spelling of `event_label`, for callers that only hold the node.
func label_for_event(event: InputEvent) -> String:
	return event_label(event)


func get_rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action: StringName in REBINDABLE_ACTIONS:
		out.append(action)
	return out


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
		var motion := event as InputEventJoypadMotion
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
	return "?"


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


## Replaces the primary binding of `action` on the device the event belongs to.
## Returns `{ok, reason, conflict}`; `reason` is "unknown_action", "unsupported",
## "reserved" or "conflict" when the binding is refused, and nothing changes then.
func rebind(action: StringName, event: InputEvent) -> Dictionary:
	var result := {"ok": false, "reason": "", "conflict": &""}
	if not REBINDABLE_ACTIONS.has(action) or not InputMap.has_action(action):
		result["reason"] = "unknown_action"
		return result
	var encoded := encode_event(event)
	if encoded.is_empty() or decode_event(encoded) == null or event is InputEventMouseButton:
		result["reason"] = "unsupported"
		return result
	var clean := decode_event(encoded)
	var key := clean as InputEventKey
	if key != null and (
		RESERVED_KEYS.has(int(key.physical_keycode)) or KEYBOARD_LOCKED_ACTIONS.has(action)
	):
		result["reason"] = "reserved"
		return result
	for other: StringName in REBINDABLE_ACTIONS:
		if other == action or _may_share(action, other) or not InputMap.has_action(other):
			continue
		for existing: InputEvent in InputMap.action_get_events(other):
			if encode_event(existing) == encoded:
				result["reason"] = "conflict"
				result["conflict"] = other
				return result
	var device := DEVICE_GAMEPAD if is_gamepad_event(clean) else DEVICE_KEYBOARD
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var replaced := false
	for index in events.size():
		if _matches_device(events[index], device):
			events[index] = clean
			replaced = true
			break
	if not replaced:
		events.append(clean)
	# The same input twice on one action is one input.
	var seen: Dictionary = {}
	InputMap.action_erase_events(action)
	for item: InputEvent in events:
		var code := encode_event(item)
		if seen.has(code):
			continue
		seen[code] = true
		InputMap.action_add_event(action, item)
	_store_action(action)
	bindings_changed.emit()
	result["ok"] = true
	return result


func _may_share(first: StringName, second: StringName) -> bool:
	for pair: Array in SHARED_PAIRS:
		if pair.has(first) and pair.has(second):
			return true
	return false


## Every rebindable action back to `project.godot`, and the stored overrides removed.
func restore_default_bindings() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		_apply_events(action, default_events(action))
	var config := _open()
	if config.has_section(SECTION_INPUT):
		config.erase_section(SECTION_INPUT)
	_write(config)
	bindings_changed.emit()


## Whether the settings screen offers this side of an action for rebinding.
## False for the keyboard side of the Esc actions; the settings screen shows them fixed.
func can_rebind(action: StringName, device: StringName) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	return device == DEVICE_GAMEPAD or not KEYBOARD_LOCKED_ACTIONS.has(action)


## True when an action's events are exactly its defaults.
func is_default_binding(action: StringName) -> bool:
	return _encoded(InputMap.action_get_events(action)) == _encoded(default_events(action))


func _apply_events(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _encoded(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for event: InputEvent in events:
		out.append(encode_event(event))
	return out


func _store_action(action: StringName) -> void:
	var config := _open()
	if is_default_binding(action):
		if config.has_section_key(SECTION_INPUT, String(action)):
			config.erase_section_key(SECTION_INPUT, String(action))
	else:
		config.set_value(SECTION_INPUT, String(action), _encoded(InputMap.action_get_events(action)))
	config.set_value(SECTION_META, "version", FORMAT_VERSION)
	_write(config)


# --- Loading and saving ----------------------------------------------------------


## Reads the file and applies it. Missing keys keep their defaults; bad ones are reported.
func load_settings() -> void:
	_load_problems.clear()
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH)
	if loaded != OK and FileAccess.file_exists(SETTINGS_PATH):
		# A file that is there but does not parse is damage, not a first run: say so.
		_load_problems.append(
			"%s could not be read (error %d); every setting is at its default"
			% [SETTINGS_PATH, loaded]
		)
	_text_size = DEFAULT_TEXT_SIZE
	_text_speed = DEFAULT_TEXT_SPEED
	_ui_scale = DEFAULT_UI_SCALE
	for key: StringName in VOLUME_KEYS:
		_volumes[key] = DEFAULT_VOLUME
	for action: StringName in REBINDABLE_ACTIONS:
		_apply_events(action, default_events(action))
	if loaded == OK:
		_text_size = _read_choice(config, SECTION_TEXT, "size", TEXT_SIZES, DEFAULT_TEXT_SIZE)
		_text_speed = _read_choice(config, SECTION_TEXT, "speed", TEXT_SPEEDS, DEFAULT_TEXT_SPEED)
		_ui_scale = _read_choice(config, SECTION_DISPLAY, "ui_scale", UI_SCALES, DEFAULT_UI_SCALE)
		for key: StringName in VOLUME_KEYS:
			_volumes[key] = _read_volume(config, String(key))
		_load_bindings(config)
	_apply_all_volumes()
	_apply_ui_scale()
	setting_changed.emit(&"all")
	bindings_changed.emit()


func get_load_problems() -> Array[String]:
	var out: Array[String] = []
	out.append_array(_load_problems)
	return out


func _read_choice(
	config: ConfigFile, section: String, key: String, allowed: Array[StringName], fallback: StringName
) -> StringName:
	if not config.has_section_key(section, key):
		return fallback
	var value: Variant = config.get_value(section, key)
	if value is String or value is StringName:
		var choice := StringName(String(value))
		if allowed.has(choice):
			return choice
	_load_problems.append("[%s] %s = %s is not one of %s" % [section, key, str(value), str(allowed)])
	return fallback


func _read_volume(config: ConfigFile, key: String) -> int:
	if not config.has_section_key(SECTION_AUDIO, key):
		return DEFAULT_VOLUME
	var value: Variant = config.get_value(SECTION_AUDIO, key)
	if (value is int or value is float) and float(value) >= 0.0 and float(value) <= 100.0:
		return int(round(float(value)))
	_load_problems.append("[audio] %s = %s is not a percentage" % [key, str(value)])
	return DEFAULT_VOLUME


func _load_bindings(config: ConfigFile) -> void:
	if not config.has_section(SECTION_INPUT):
		return
	var loaded: Array[StringName] = []
	for key: String in config.get_section_keys(SECTION_INPUT):
		var action := StringName(key)
		if not REBINDABLE_ACTIONS.has(action):
			_load_problems.append("[input] %s is not a rebindable action" % key)
			continue
		var value: Variant = config.get_value(SECTION_INPUT, key)
		var decoded := _decode_list(value)
		if decoded.is_empty():
			_load_problems.append(
				"[input] %s = %s is not a valid binding list; defaults kept" % [key, str(value)]
			)
			continue
		var broken := _broken_rule(action, decoded)
		if not broken.is_empty():
			_load_problems.append("[input] %s = %s %s; defaults kept" % [key, str(value), broken])
			continue
		_apply_events(action, decoded)
		loaded.append(action)
	_drop_loaded_conflicts(loaded)


## The rules `rebind` keeps one input at a time, checked on a whole stored list: a file
## edited by hand or written by another build must not take Esc away from the menus, give
## Esc to anything else, or leave an action without a key or a controller input it has by
## default. Empty when the list is fine; otherwise what is wrong with it.
func _broken_rule(action: StringName, events: Array) -> String:
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
	for event: InputEvent in default_events(action):
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


## Two actions on one input is what `rebind` refuses, and a stored file can still say it:
## edited by hand, or two lists that were each fine against the defaults. The action read
## last goes back to its defaults until nothing clashes; the defaults never clash, so this
## ends, and it does not depend on the order the file lists a valid swap in.
func _drop_loaded_conflicts(loaded: Array[StringName]) -> void:
	var index := loaded.size() - 1
	while index >= 0:
		var action := loaded[index]
		var other := _conflict_of(action)
		if String(other).is_empty():
			index -= 1
			continue
		_load_problems.append("[input] %s shares an input with %s; defaults kept" % [action, other])
		_apply_events(action, default_events(action))
		loaded.remove_at(index)
		index = loaded.size() - 1


## The first other action using one of `action`'s inputs, apart from the shared pairs.
func _conflict_of(action: StringName) -> StringName:
	var mine := _encoded(InputMap.action_get_events(action))
	for other: StringName in REBINDABLE_ACTIONS:
		if other == action or _may_share(action, other) or not InputMap.has_action(other):
			continue
		for code: String in _encoded(InputMap.action_get_events(other)):
			if mine.has(code):
				return other
	return StringName()


## Every entry must decode, and the list must not be empty; otherwise nothing is used.
func _decode_list(value: Variant) -> Array:
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


## Back to every default. The language (`[display] locale`) is the player's and `Loc`'s,
## and stays. Used by the tests so one check never inherits another's preferences.
func reset_to_defaults() -> void:
	var config := _open()
	for section: String in [SECTION_TEXT, SECTION_AUDIO, SECTION_INPUT, SECTION_META]:
		if config.has_section(section):
			config.erase_section(section)
	if config.has_section_key(SECTION_DISPLAY, "ui_scale"):
		config.erase_section_key(SECTION_DISPLAY, "ui_scale")
	_write(config)
	load_settings()


func _store(section: String, key: String, value: Variant) -> void:
	var config := _open()
	config.set_value(section, key, value)
	config.set_value(SECTION_META, "version", FORMAT_VERSION)
	_write(config)


## The file as it is now, so a write never drops keys this node does not own.
func _open() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return config


func _write(config: ConfigFile) -> void:
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Settings: could not write %s (error %d)." % [SETTINGS_PATH, error])
