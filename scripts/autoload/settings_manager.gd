extends Node
## Autoload `Settings`: the player's text, sound, display and input preferences.
##
## One file, `user://settings.cfg` (`SettingsStore.PATH`), shared with `Loc` (which owns
## `[display] locale`).
## Every write here loads the file first and only touches the keys this node owns, so a
## language choice is never lost to a volume change and the other way round.
##
## What is stored, and how it is checked on the way back in:
##
## - `[text] size` — one of `TEXT_SIZES`; every on-screen text is multiplied by its scale.
## - `[text] speed` — one of `TEXT_SPEEDS`; how fast a line types itself out.
## - `[text] auto_speed` — one of `AUTO_SPEEDS`; how long auto waits on a finished line.
## - `[text] skip_scope` — one of `SKIP_SCOPES`; whether skip stops at a line not yet read.
## - `[audio] master|music|sfx` — whole percentages, 0..100.
## - `[display] ui_scale` — one of `UI_SCALES`, "auto" by default (see `effective_ui_scale`).
## - `[controls] sprint_mode` — one of `SPRINT_MODES`; hold the sprint input, or press it once.
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


const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")
const StoryEditorEntry := preload("res://scripts/ui/story_editor_entry.gd")
const InputSettings := preload("res://scripts/save/input_settings.gd")
signal setting_changed(key: StringName)
signal bindings_changed
signal input_device_changed(device: StringName)
signal mobile_area_changed

## The file, and the one place its path is written. `SettingsStore` is shared with `Loc`,
## which owns `[display] locale`: two owners, one file, one path (issue #215). The constant
## below is kept so the tests and this file's own diagnostics read like they always did.
const SETTINGS_PATH := SettingsStore.PATH
const SECTION_TEXT := "text"
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := SettingsStore.SECTION_DISPLAY
const SECTION_INPUT := "input"
const SECTION_META := "settings"
const SECTION_CONTROLS := "controls"
## Author tools that a player's copy may carry (issue: the story editor in the iPhone build).
## `[authoring] story_editor` is off unless the player turns it on.
const SECTION_AUTHORING := "authoring"
const FORMAT_VERSION := 1

const TEXT_SIZES: Array[StringName] = [&"standard", &"large", &"largest"]
const TEXT_SIZE_SCALE: Dictionary = {&"standard": 1.0, &"large": 1.15, &"largest": 1.3}
const DEFAULT_TEXT_SIZE := &"standard"

const TEXT_SPEEDS: Array[StringName] = [&"slow", &"normal", &"fast", &"instant"]
## Characters per second. 0 means the whole line appears at once.
const TEXT_SPEED_CPS: Dictionary = {&"slow": 28.0, &"normal": 55.0, &"fast": 110.0, &"instant": 0.0}
const DEFAULT_TEXT_SPEED := &"normal"

## The reading modes' settings. The values are `DialoguePlayback`'s, which owns their meaning.
const AUTO_SPEEDS: Array[StringName] = [&"slow", &"normal", &"fast"]
const DEFAULT_AUTO_SPEED := &"normal"
## "read": skip stops at the first line not read before. "all": skip passes every line.
const SKIP_SCOPES: Array[StringName] = [&"read", &"all"]
const DEFAULT_SKIP_SCOPE := &"read"

## "hold": jog only while the sprint input is down. "toggle": one press starts jogging and
## the next one stops it, for a player who cannot hold a key and steer at the same time.
const SPRINT_MODES: Array[StringName] = [&"hold", &"toggle"]
const DEFAULT_SPRINT_MODE := &"hold"

## Sound and display constants belong to `SettingsOutputs` (issue #223); re-exported here.
const VOLUME_KEYS: Array[StringName] = SettingsOutputs.VOLUME_KEYS
const VOLUME_BUS: Dictionary = SettingsOutputs.VOLUME_BUS
const DEFAULT_VOLUME := 100

const UI_SCALES: Array[StringName] = SettingsOutputs.UI_SCALES
const DEFAULT_UI_SCALE := &"auto"
## The window size the interface is designed and checked at; see `SettingsOutputs`.
const UI_REFERENCE_SIZE := SettingsOutputs.UI_REFERENCE_SIZE
## The smallest logical size the layout is verified at; see `SettingsOutputs`.
const UI_MINIMUM_LOGICAL := SettingsOutputs.UI_MINIMUM_LOGICAL

## The binding rules live in `InputSettings` (and `InputBindings`); these are its constants
## under the names callers have always used.
const DEVICE_KEYBOARD := InputSettings.DEVICE_KEYBOARD
const DEVICE_MOUSE := InputSettings.DEVICE_MOUSE
const DEVICE_TOUCH := InputSettings.DEVICE_TOUCH
const DEVICE_GAMEPAD := InputSettings.DEVICE_GAMEPAD

## Everything the settings screen lets the player rebind, in the order it lists them.
const REBINDABLE_ACTIONS: Array[StringName] = InputSettings.REBINDABLE_ACTIONS
## Pairs that may share an input because they never listen at the same time.
const SHARED_PAIRS: Array = InputSettings.SHARED_PAIRS
## Rebinding never offers these: Esc cancels a capture, so it cannot be captured.
const RESERVED_KEYS: Array[int] = InputSettings.RESERVED_KEYS
## Actions whose keyboard key is Esc and stays Esc.
const KEYBOARD_LOCKED_ACTIONS: Array[StringName] = InputSettings.KEYBOARD_LOCKED_ACTIONS
## Xbox-style names, which is what SDL reports for most pads.
const JOY_BUTTON_NAMES: Dictionary = InputSettings.JOY_BUTTON_NAMES

var _text_size: StringName = DEFAULT_TEXT_SIZE
var _text_speed: StringName = DEFAULT_TEXT_SPEED
var _auto_speed: StringName = DEFAULT_AUTO_SPEED
var _skip_scope: StringName = DEFAULT_SKIP_SCOPE
var _sprint_mode: StringName = DEFAULT_SPRINT_MODE
var _ui_scale: StringName = DEFAULT_UI_SCALE
var _story_editor := false
var _volumes: Dictionary = {}
## The bus levels `default_bus_layout.tres` sets, read once: 100 % means "as mixed".
var _bus_trim: Dictionary = {}
## The rebinding half: the input map, its defaults and the stored overrides.
var _input_settings: InputSettings
var _load_problems: Array[String] = []
## Which part of the swap the machine refused the last time a preference was written, as
## `{step, error}`. A refused write already shows as "not saved" on the settings screen; the
## step is what turns that into something an author can act on (#394). Every attempt
## overwrites it, so it never describes an older failure.
var _store_failure := {}
var _applying_scale := false
var _applied_ui_scale := 1.0
var _mobile_area := Rect2()
var _mobile_window := Vector2i.ZERO
var _mobile_density := 0.0
var _metrics_elapsed := 1.0


func _ready() -> void:
	# Menus run while the tree is paused, and they read and write through this node.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key: StringName in VOLUME_KEYS:
		_volumes[key] = DEFAULT_VOLUME
	_capture_bus_trim()
	_input_settings = InputSettings.new(
		_write, _open, func() -> Array[String]: return _load_problems,
		default_events, func() -> void: bindings_changed.emit()
	)
	_input_settings.prepare()
	if MobileLayout.enabled:
		_input_settings.set_input_device(DEVICE_TOUCH)
	# Safe insets can change on a 180-degree turn or when system bars reappear,
	# without a resize event. Only the mobile path polls, and only four times a second.
	set_process(MobileLayout.enabled)
	load_settings()
	get_tree().node_added.connect(_on_node_added)
	var root := get_tree().root
	if root != null and not root.size_changed.is_connected(_apply_ui_scale):
		root.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


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


func get_auto_speed() -> StringName:
	return _auto_speed


func set_auto_speed(value: StringName) -> void:
	if not AUTO_SPEEDS.has(value) or value == _auto_speed:
		return
	_auto_speed = value
	_store(SECTION_TEXT, "auto_speed", String(value))
	setting_changed.emit(&"auto_speed")


func get_skip_scope() -> StringName:
	return _skip_scope


func set_skip_scope(value: StringName) -> void:
	if not SKIP_SCOPES.has(value) or value == _skip_scope:
		return
	_skip_scope = value
	_store(SECTION_TEXT, "skip_scope", String(value))
	setting_changed.emit(&"skip_scope")


## The story editor switch. Off is the player's game: no launcher, no overlay and no
## draft reads. On, the world offers 「剧情编辑」; drafts live in `user://story_editor/`, apart
## from the save file. The return value is whether the preference file took the change, which on
## an author's run is not the same question as whether the switch moved - see below.
func is_story_editor_enabled() -> bool:
	return _story_editor


func set_story_editor_enabled(value: bool) -> bool:
	if value == _story_editor:
		return true
	var stored := _store(SECTION_AUTHORING, "story_editor", value) == OK
	if not stored and not StoryEditorEntry.development_run():
		# A player's copy refuses the change outright. An author's own run is not locked out of the
		# tool by a file it cannot write, and is not trapped inside it either: the switch moves for
		# this run, in both directions, and nothing is remembered (#395, #396). The file is how the
		# author persists a choice, not who is allowed to make one - so a stored "on" still wins on
		# the next run, and the `false` below is what tells the row to say that out loud.
		return false
	_story_editor = value
	_sync_story_editor.call_deferred()
	setting_changed.emit(&"story_editor")
	return stored


func _sync_story_editor() -> void:
	if is_inside_tree() and get_tree().root.get_node_or_null(^"Settings") == self:
		StoryEditorEntry.reconcile(get_tree().root, _story_editor)


func get_sprint_mode() -> StringName:
	return _sprint_mode


func set_sprint_mode(value: StringName) -> void:
	if not SPRINT_MODES.has(value) or value == _sprint_mode:
		return
	_sprint_mode = value
	_store(SECTION_CONTROLS, "sprint_mode", String(value))
	setting_changed.emit(&"sprint_mode")


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
	return SettingsOutputs.bus_db(float(_bus_trim.get(key, 0.0)), percent)


func _capture_bus_trim() -> void:
	_bus_trim = SettingsOutputs.capture_bus_trim()


func _apply_volume(key: StringName) -> void:
	SettingsOutputs.apply_volume(
		key, get_volume(key), float(_bus_trim.get(key, 0.0)), get_node_or_null(^"/root/CueAudio")
	)


func _apply_all_volumes() -> void:
	for key: StringName in VOLUME_KEYS:
		_apply_volume(key)


## Room tones are moved onto the `SFX` bus as they enter the tree (`SettingsOutputs`).
func _on_node_added(node: Node) -> void:
	SettingsOutputs.route_ambience(node)


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


## The factor the 2D layer is drawn at for a window size and a choice. See
## `SettingsOutputs.effective_ui_scale`.
static func effective_ui_scale(window_size: Vector2, choice: StringName) -> float:
	return SettingsOutputs.effective_ui_scale(window_size, choice)


func get_applied_ui_scale() -> float:
	return _applied_ui_scale


func _apply_ui_scale() -> void:
	if _applying_scale:
		return
	var root := get_tree().root
	if root == null:
		return
	_applying_scale = true
	_applied_ui_scale = SettingsOutputs.apply_ui_scale(root, _ui_scale)
	_applying_scale = false


func _process(delta: float) -> void:
	_metrics_elapsed += delta
	if _metrics_elapsed < 0.25:
		return
	_metrics_elapsed = 0.0
	var window := get_tree().root
	var safe := MobileLayout.safe_pixels(window)
	var dpi := MobileLayout.density(window)
	if safe != _mobile_area or window.size != _mobile_window or dpi != _mobile_density:
		_mobile_area = safe
		_mobile_window = window.size
		_mobile_density = dpi
		mobile_area_changed.emit()


# --- Input ---------------------------------------------------------------------


## The rebinding half lives in `InputSettings` (`scripts/save/input_settings.gd`): the
## input map, its defaults and its stored overrides. These forward so the settings screen,
## the menus and the tests keep one node to talk to.

func get_input_device() -> StringName:
	return _input_settings.get_input_device()


func is_using_gamepad() -> bool:
	return _input_settings.is_using_gamepad()


func _input(event: InputEvent) -> void:
	var before := _input_settings.get_input_device()
	_input_settings.notice_device(event)
	if _input_settings.get_input_device() != before:
		input_device_changed.emit(_input_settings.get_input_device())


## A disconnected active controller has no buttons to describe. Fall back immediately to
## the always-available keyboard; connecting a pad alone does not steal the active hand.
func _on_joy_connection_changed(_device_id: int, connected: bool) -> void:
	var before := _input_settings.get_input_device()
	_input_settings.joy_connection_changed(connected, MobileLayout.enabled)
	if _input_settings.get_input_device() != before:
		input_device_changed.emit(_input_settings.get_input_device())


## For tests and explicit settings flows: select a presentation family without an event.
func set_input_device(device: StringName) -> void:
	var before := _input_settings.get_input_device()
	_input_settings.set_input_device(device)
	if _input_settings.get_input_device() != before:
		input_device_changed.emit(_input_settings.get_input_device())


## The default events of an action, as `project.godot` declares them.
func default_events(action: StringName) -> Array:
	return _input_settings.default_events(action)


func is_keyboard_event(event: InputEvent) -> bool:
	return _input_settings.is_keyboard_event(event)


func is_gamepad_event(event: InputEvent) -> bool:
	return _input_settings.is_gamepad_event(event)


## The event the settings screen shows and replaces for an action on a device.
func primary_event(action: StringName, device: StringName) -> InputEvent:
	return _input_settings.primary_event(action, device)


## A short name for what triggers an action on a device: "E", "Space", "A", "D-pad ↑".
func binding_label(action: StringName, device: StringName = &"") -> String:
	return _input_settings.binding_label(action, device)


## Instance spelling of `event_label`, for callers that only hold the node.
func label_for_event(event: InputEvent) -> String:
	return _input_settings.label_for_event(event)


func get_rebindable_actions() -> Array[StringName]:
	return _input_settings.get_rebindable_actions()


## A short name for an input: "E", "Space", "A", "D-pad ↑". See `InputBindings`.
static func event_label(event: InputEvent) -> String:
	return InputSettings.event_label(event)


## `key:69`, `mouse:1`, `joy_button:0`, `joy_axis:1:-`. Empty for anything else.
static func encode_event(event: InputEvent) -> String:
	return InputSettings.encode_event(event)


## The inverse of `encode_event`, or null for anything that is not a valid binding.
static func decode_event(text: String) -> InputEvent:
	return InputSettings.decode_event(text)


## Replaces the primary binding of `action` on the device the event belongs to.
## Returns `{ok, reason, conflict}`; `reason` is "unknown_action", "unsupported",
## "reserved" or "conflict" when the binding is refused, and nothing changes then.
func rebind(action: StringName, event: InputEvent) -> Dictionary:
	return _input_settings.rebind(action, event)


## Every rebindable action back to `project.godot`, and the stored overrides removed.
func restore_default_bindings() -> void:
	_input_settings.restore_default_bindings()


## Whether the settings screen offers this side of an action for rebinding.
## False for the keyboard side of the Esc actions; the settings screen shows them fixed.
func can_rebind(action: StringName, device: StringName) -> bool:
	return _input_settings.can_rebind(action, device)


## True when an action's events are exactly its defaults.
func is_default_binding(action: StringName) -> bool:
	return _input_settings.is_default_binding(action)


func _apply_events(action: StringName, events: Array) -> void:
	_input_settings.apply_events(action, events)


func _encoded(events: Array) -> PackedStringArray:
	return _input_settings.encoded(events)


# --- Loading and saving ----------------------------------------------------------


## Reads the file and applies it. Missing keys keep their defaults; bad ones are reported.
func load_settings() -> void:
	_load_problems.clear()
	var config := ConfigFile.new()
	var loaded := SettingsStore.read(config)
	if loaded != OK and SettingsStore.exists():
		# A file that is there but does not parse is damage, not a first run: say so.
		_load_problems.append(
			"%s could not be read (error %d); every setting is at its default"
			% [SETTINGS_PATH, loaded]
		)
	_text_size = DEFAULT_TEXT_SIZE
	_text_speed = DEFAULT_TEXT_SPEED
	_auto_speed = DEFAULT_AUTO_SPEED
	_skip_scope = DEFAULT_SKIP_SCOPE
	_sprint_mode = DEFAULT_SPRINT_MODE
	_ui_scale = DEFAULT_UI_SCALE
	_story_editor = false
	for key: StringName in VOLUME_KEYS:
		_volumes[key] = DEFAULT_VOLUME
	for action: StringName in REBINDABLE_ACTIONS:
		_apply_events(action, default_events(action))
	if loaded == OK:
		_text_size = _read_choice(config, SECTION_TEXT, "size", TEXT_SIZES, DEFAULT_TEXT_SIZE)
		_text_speed = _read_choice(config, SECTION_TEXT, "speed", TEXT_SPEEDS, DEFAULT_TEXT_SPEED)
		_auto_speed = _read_choice(config, SECTION_TEXT, "auto_speed", AUTO_SPEEDS, DEFAULT_AUTO_SPEED)
		_skip_scope = _read_choice(config, SECTION_TEXT, "skip_scope", SKIP_SCOPES, DEFAULT_SKIP_SCOPE)
		_sprint_mode = _read_choice(
			config, SECTION_CONTROLS, "sprint_mode", SPRINT_MODES, DEFAULT_SPRINT_MODE
		)
		_ui_scale = _read_choice(config, SECTION_DISPLAY, "ui_scale", UI_SCALES, DEFAULT_UI_SCALE)
		if config.has_section_key(SECTION_AUTHORING, "story_editor"):
			var stored: Variant = config.get_value(SECTION_AUTHORING, "story_editor")
			if stored is bool:
				_story_editor = stored
			else:
				_load_problems.append(
					"[%s] story_editor = %s is not true or false" % [SECTION_AUTHORING, str(stored)]
				)
		for key: StringName in VOLUME_KEYS:
			_volumes[key] = _read_volume(config, String(key))
		_load_bindings(config)
	if StoryEditorEntry.development_override() or StoryEditorEntry.development_default():
		# An author's launch (#394), or a development run's boot default (#395), turns the
		# switch on for this run whatever the file says - `development_default()` says who.
		_story_editor = true
	_apply_all_volumes()
	_apply_ui_scale()
	_sync_story_editor.call_deferred()
	setting_changed.emit(&"all")
	bindings_changed.emit()


func get_load_problems() -> Array[String]:
	var out: Array[String] = []
	out.append_array(_load_problems)
	return out


func _read_choice(
	config: ConfigFile, section: String, key: String, allowed: Array[StringName], fallback: StringName
) -> StringName:
	return SettingsStore.read_choice(config, section, key, allowed, fallback, _load_problems)


func _read_volume(config: ConfigFile, key: String) -> int:
	return SettingsStore.read_percent(config, SECTION_AUDIO, key, DEFAULT_VOLUME, _load_problems)


## Applies the stored `[input]` lists. Each is checked whole against the rules `rebind`
## keeps (`InputSettings.load_section`), and a list that breaks one keeps the defaults.
func _load_bindings(config: ConfigFile) -> void:
	_input_settings.load_section(config)


## Back to every default. The language (`[display] locale`) is the player's and `Loc`'s,
## and stays. Used by the tests so one check never inherits another's preferences.
func reset_to_defaults() -> void:
	var config := _open()
	for section: String in [
		SECTION_TEXT, SECTION_AUDIO, SECTION_INPUT, SECTION_CONTROLS, SECTION_AUTHORING, SECTION_META
	]:
		if config.has_section(section):
			config.erase_section(section)
	if config.has_section_key(SECTION_DISPLAY, "ui_scale"):
		config.erase_section_key(SECTION_DISPLAY, "ui_scale")
	_write(config)
	load_settings()


func _store(section: String, key: String, value: Variant) -> Error:
	var config := _open()
	config.set_value(section, key, value)
	config.set_value(SECTION_META, "version", FORMAT_VERSION)
	return _write(config)


## The file as it is now, so a write never drops keys this node does not own.
func _open() -> ConfigFile:
	return SettingsStore.open()


func _write(config: ConfigFile) -> Error:
	var report := {}
	var error := SettingsStore.write(config, report)
	_store_failure = report
	if error != OK:
		push_warning("Settings: could not write %s (error %d): %s." % [
			SETTINGS_PATH, error, String(report.get("step", "write"))
		])
	return error


## Which step of the swap the machine refused last, and with which `Error`; empty when the
## last write went through. `Settings` rows that report a refusal to the player use this to
## say what failed instead of only that something did (#394).
func get_last_store_failure() -> Dictionary:
	return _store_failure.duplicate(true)
