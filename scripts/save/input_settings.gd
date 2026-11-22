extends RefCounted
## The rebinding half of the `Settings` autoload: what the settings screen's controls
## section reads, changes and restores.
##
## It lives here, not in `scripts/autoload/settings_manager.gd`, because the manager had
## grown past the repository's file-size ceiling (`gdlintrc`, `max-file-lines`). The split
## is by responsibility, not by size: that file owns the stored preferences and this one
## owns the input map, and the rules for a legal binding already live in `InputBindings`.
##
## The host passes its own helpers in (`store`, `open`, `read`, `problems`), so there is one
## settings file, one read-modify-write discipline and one list of load problems: this class
## never writes `user://settings.cfg` itself.

const InputBindings := preload("res://scripts/save/input_bindings.gd")

const SECTION_INPUT := "input"
const SECTION_META := "settings"
const FORMAT_VERSION := 1
## The binding rules and their names are `InputBindings`'; these are them under the names
## the settings screen and the tests have always used.
const DEVICE_KEYBOARD := InputBindings.DEVICE_KEYBOARD
const DEVICE_MOUSE := InputBindings.DEVICE_MOUSE
const DEVICE_TOUCH := InputBindings.DEVICE_TOUCH
const DEVICE_GAMEPAD := InputBindings.DEVICE_GAMEPAD
const REBINDABLE_ACTIONS: Array[StringName] = InputBindings.REBINDABLE_ACTIONS
const SHARED_PAIRS: Array = InputBindings.SHARED_PAIRS
const RESERVED_KEYS: Array[int] = InputBindings.RESERVED_KEYS
const KEYBOARD_LOCKED_ACTIONS: Array[StringName] = InputBindings.KEYBOARD_LOCKED_ACTIONS
const JOY_BUTTON_NAMES: Dictionary = InputBindings.JOY_BUTTON_NAMES

## The four callables the host supplies; see the class comment.
var store: Callable
var open_file: Callable
var read_problems: Callable
var defaults_of: Callable
var changed: Callable

## action -> Array[InputEvent], as `project.godot` declares them.
var _default_events: Dictionary = {}
var _device: StringName = DEVICE_KEYBOARD


func _init(
	store_callable: Callable, open_callable: Callable, problems_callable: Callable,
	defaults_callable: Callable, changed_callable: Callable
) -> void:
	store = store_callable
	open_file = open_callable
	read_problems = problems_callable
	defaults_of = defaults_callable
	changed = changed_callable


## Reads `project.godot`'s bindings once and puts the menus' pad navigation in place. The
## defaults come from the project settings, not the live input map, which may already carry
## the player's rebinding.
func prepare() -> void:
	_default_events = InputBindings.project_defaults()
	InputBindings.ensure_ui_navigation()


func get_input_device() -> StringName:
	return _device


func is_using_gamepad() -> bool:
	return _device == DEVICE_GAMEPAD


## The last meaningful device event selects the prompt family. Only presentation changes:
## this never replays or synthesizes an action.
func notice_device(event: InputEvent) -> void:
	_set_detected_device(InputBindings.detected_device(event, _device))


## A disconnected active controller has no buttons to describe. Fall back immediately to
## the always-available keyboard; connecting a pad alone does not steal the active hand.
func joy_connection_changed(connected: bool, mobile: bool) -> void:
	if not connected and _device == DEVICE_GAMEPAD:
		_set_detected_device(DEVICE_TOUCH if mobile else DEVICE_KEYBOARD)


func set_input_device(device: StringName) -> void:
	_set_detected_device(device)


func _set_detected_device(device: StringName) -> void:
	if device not in InputBindings.DEVICES or device == _device:
		return
	_device = device


## The default events of an action, as `project.godot` declares them.
func default_events(action: StringName) -> Array:
	var events: Array = []
	for event: InputEvent in (_default_events.get(action, []) as Array):
		events.append(event.duplicate())
	return events


func is_keyboard_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


func is_gamepad_event(event: InputEvent) -> bool:
	return InputBindings.is_gamepad_event(event)


func matches_device(event: InputEvent, device: StringName) -> bool:
	if device == DEVICE_GAMEPAD:
		return is_gamepad_event(event)
	return event is InputEventKey


## The event the settings screen shows and replaces for an action on a device: the first
## key for the keyboard, the first button or stick direction for the pad.
func primary_event(action: StringName, device: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if matches_device(event, device):
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


## A short name for an input: "E", "Space", "A", "D-pad ↑". See `InputBindings`.
static func event_label(event: InputEvent) -> String:
	return InputBindings.event_label(event)


## `key:69`, `mouse:1`, `joy_button:0`, `joy_axis:1:-`. Empty for anything else.
static func encode_event(event: InputEvent) -> String:
	return InputBindings.encode_event(event)


## The inverse of `encode_event`, or null for anything that is not a valid binding.
static func decode_event(text: String) -> InputEvent:
	return InputBindings.decode_event(text)


## Replaces the primary binding of `action` on the device the event belongs to.
## Returns `{ok, reason, conflict}`; `reason` is "unknown_action", "unsupported",
## "reserved" or "conflict" when the binding is refused, and nothing changes then.
func rebind(action: StringName, event: InputEvent) -> Dictionary:
	var checked := InputBindings.check_rebind(action, event)
	var result := {
		"ok": false, "reason": String(checked["reason"]), "conflict": checked["conflict"]
	}
	if not bool(checked["ok"]):
		return result
	var clean: InputEvent = checked["clean"]
	var device := DEVICE_GAMEPAD if is_gamepad_event(clean) else DEVICE_KEYBOARD
	InputBindings.apply_events(
		action, InputBindings.events_with(action, clean, device, matches_device)
	)
	_store_action(action)
	changed.call()
	result["ok"] = true
	return result


## Every rebindable action back to `project.godot`, and the stored overrides removed.
func restore_default_bindings() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		apply_events(action, default_events(action))
	var config: ConfigFile = open_file.call()
	if config.has_section(SECTION_INPUT):
		config.erase_section(SECTION_INPUT)
	store.call(config)
	changed.call()


## Whether the settings screen offers this side of an action for rebinding.
## False for the keyboard side of the Esc actions; the settings screen shows them fixed.
func can_rebind(action: StringName, device: StringName) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	return device == DEVICE_GAMEPAD or not KEYBOARD_LOCKED_ACTIONS.has(action)


## True when an action's events are exactly its defaults.
func is_default_binding(action: StringName) -> bool:
	return encoded(InputMap.action_get_events(action)) == encoded(default_events(action))


func apply_events(action: StringName, events: Array) -> void:
	InputBindings.apply_events(action, events)


func encoded(events: Array) -> PackedStringArray:
	return InputBindings.encoded(events)


func _store_action(action: StringName) -> void:
	var config: ConfigFile = open_file.call()
	if is_default_binding(action):
		if config.has_section_key(SECTION_INPUT, String(action)):
			config.erase_section_key(SECTION_INPUT, String(action))
	else:
		config.set_value(SECTION_INPUT, String(action), encoded(InputMap.action_get_events(action)))
	config.set_value(SECTION_META, "version", FORMAT_VERSION)
	store.call(config)


## Puts every binding back to its project default, for a full reset.
func reset_actions() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		apply_events(action, default_events(action))


## Applies the stored `[input]` lists. Each is checked whole against the rules `rebind`
## keeps (`InputBindings.load_section`), and a list that breaks one keeps the defaults.
func load_section(config: ConfigFile) -> void:
	InputBindings.load_section(config, SECTION_INPUT, defaults_of, read_problems.call())
