class_name DialogueAutoplay
extends Node
## Auto-advance and "skip read text": two ways of reading that press continue for the
## player, and nothing else.
##
## It never talks to the runtime. Everything it does goes through
## `DialogueController.advance_presentation()`, the same path the continue key takes, so
## effects, records, flags, the backlog and the sequence director see exactly what they
## would see from a player pressing the key - only sooner.
##
## - **Auto** (toggled with `dialogue_auto`): once a line has finished typing, waits for
##   as long as it takes to read it - a pause plus a reading rate, slower for CJK than for
##   Latin text, scaled by the "auto speed" setting - and continues. It waits at choices
##   (a choice is never made for the player), longer under a visible check so the dice can
##   be read, and not at all while the log is open. It stays on until it is turned off,
##   across conversations, for the session.
## - **Skip** (held with `dialogue_skip`): finishes and continues lines quickly, but only
##   lines this player has read before, in this run or any earlier one (`ReadLog`). It
##   stops at the first unread line, at a choice and at a visible check, and says why.
##   The "skip" setting can widen it to every line. With the "skip key" setting on
##   "toggle", one press starts skipping and a second press - or anything skip has to
##   stop at - ends it, so nobody has to hold a key or a trigger down.
##
## While the tree is paused (the pause menu, the notebook) it does not run at all.
##
## Every line shown is marked read when it appears. A language switch re-shows the same
## line without a `line_presented`, so it neither marks anything nor resets the wait.

signal mode_changed(mode: StringName)
## Holding skip ran into something it must not skip: `unread`, `choice` or `check`.
signal skip_stopped(reason: StringName)
## The mode or the reason skip is stopped changed: what an indicator should redraw on.
signal state_changed

## Every live autoplay is in this group, so a screen that is not part of the world (the
## settings) can reach the read log the running game uses.
const GROUP := &"dialogue_autoplay"

const MODE_OFF := &"off"
const MODE_AUTO := &"auto"
const MODE_SKIP := &"skip"

const STOP_UNREAD := &"unread"
const STOP_CHOICE := &"choice"
const STOP_CHECK := &"check"

const AUTO_SPEEDS: Array[StringName] = [&"slow", &"normal", &"fast"]
const DEFAULT_AUTO_SPEED := &"normal"
## The pause before reading time starts to count, per auto speed.
const AUTO_PAUSE_SECONDS: Dictionary = {&"slow": 1.6, &"normal": 1.1, &"fast": 0.6}
## Multiplies the reading rates below.
const AUTO_RATE_SCALE: Dictionary = {&"slow": 0.7, &"normal": 1.0, &"fast": 1.6}
## Comfortable reading rates, in visible characters per second. A CJK character carries
## roughly a word's worth of meaning, so it gets far more time than a Latin letter.
const LATIN_CHARACTERS_PER_SECOND := 18.0
const CJK_CHARACTERS_PER_SECOND := 7.0
## Extra time on a line while a visible check shows its dice.
const CHECK_EXTRA_SECONDS := 1.5

const SKIP_SCOPES: Array[StringName] = [&"read", &"all"]
const DEFAULT_SKIP_SCOPE := &"read"
const SKIP_HOLD := &"hold"
const SKIP_TOGGLE := &"toggle"
## Time between skipped lines: fast, but each line is still drawn for a few frames.
const SKIP_INTERVAL_SECONDS := 0.06

var _controller: DialogueController = null
var _panel: DialoguePanel = null
var _backlog: BacklogPanel = null
var _overlay: CheckOverlay = null
var _read_log: ReadLog = null

var _auto := false
## Set by a test (or a future on-screen button) to skip without holding a key.
var _skip_forced := false
## Skip started by a press, in "toggle" mode.
var _skip_toggled := false
var _mode: StringName = MODE_OFF
var _identity := ""
var _was_read := false
## Seconds the current line has been fully readable.
var _readable_for := 0.0
var _skip_clock := 0.0
var _stop_reason: StringName = &""
var _advances := 0
## The last (mode, stop reason) announced through `state_changed`.
var _announced := ""
## `hold_seconds()` of the line on screen, kept so it is not re-measured every frame.
var _hold_text := ""
var _hold_speed: StringName = &""
var _hold_base := 0.0


func _init() -> void:
	name = "Autoplay"
	add_to_group(GROUP)


## Everything is optional except the controller, so a test can build half a scene.
func bind(
	controller: DialogueController, panel: DialoguePanel, backlog: BacklogPanel,
	overlay: CheckOverlay, read_log: ReadLog
) -> void:
	_controller = controller
	_panel = panel
	_backlog = backlog
	_overlay = overlay
	_read_log = read_log if read_log != null else ReadLog.new()
	if _controller == null:
		return
	if not _controller.line_presented.is_connected(_on_line_presented):
		_controller.line_presented.connect(_on_line_presented)
	if not _controller.presentation_active_changed.is_connected(_on_presentation_active):
		_controller.presentation_active_changed.connect(_on_presentation_active)


# --- Public -----------------------------------------------------------------------


func get_read_log() -> ReadLog:
	return _read_log


func get_mode() -> StringName:
	return _mode


func is_auto() -> bool:
	return _auto


func set_auto(enabled: bool) -> void:
	if _auto == enabled:
		return
	_auto = enabled
	_readable_for = 0.0
	_update_mode()


func toggle_auto() -> void:
	set_auto(not _auto)


## True while skip is asked for, whether or not the line on screen lets it run.
func is_skip_requested() -> bool:
	if _skip_forced or _skip_toggled:
		return true
	if get_skip_mode() == SKIP_TOGGLE:
		return false
	return InputMap.has_action(&"dialogue_skip") and Input.is_action_pressed(&"dialogue_skip")


## "toggle": a press starts or ends skipping. Only while a line is up, so a stray press
## in the world does not arm skip for a conversation that has not started.
func toggle_skip() -> void:
	if _skip_toggled:
		_skip_toggled = false
		_stop_reason = &""
	elif _presenting():
		_skip_toggled = true
		_stop_reason = &""
		_skip_clock = 0.0
	_update_mode()


func is_skip_toggled() -> bool:
	return _skip_toggled


func set_skip_forced(held: bool) -> void:
	_skip_forced = held
	_skip_clock = 0.0
	if not held:
		_stop_reason = &""
	_update_mode()


## Why skip is not running although it is asked for, or empty.
func get_stop_reason() -> StringName:
	return _stop_reason


## True when the line on screen had been read before it appeared this time.
func current_line_was_read() -> bool:
	return _was_read


func get_current_identity() -> String:
	return _identity


## How many times this node has continued a line, for tests and diagnostics.
func get_advance_count() -> int:
	return _advances


func get_auto_speed() -> StringName:
	var settings := _settings()
	if settings != null and settings.has_method("get_auto_speed"):
		return StringName(settings.call("get_auto_speed"))
	return DEFAULT_AUTO_SPEED


func get_skip_mode() -> StringName:
	var settings := _settings()
	if settings != null and settings.has_method("get_skip_mode"):
		return StringName(settings.call("get_skip_mode"))
	return SKIP_HOLD


func get_skip_scope() -> StringName:
	var settings := _settings()
	if settings != null and settings.has_method("get_skip_scope"):
		return StringName(settings.call("get_skip_scope"))
	return DEFAULT_SKIP_SCOPE


## How long auto waits on `text` once it has finished typing.
static func hold_seconds(text: String, speed: StringName = DEFAULT_AUTO_SPEED) -> float:
	var latin := 0
	var cjk := 0
	var plain := _strip_markup(text)
	for index in plain.length():
		var code := plain.unicode_at(index)
		if code <= 32:
			continue
		if is_cjk(code):
			cjk += 1
		else:
			latin += 1
	var scale := float(AUTO_RATE_SCALE.get(speed, 1.0))
	var reading := float(latin) / (LATIN_CHARACTERS_PER_SECOND * scale)
	reading += float(cjk) / (CJK_CHARACTERS_PER_SECOND * scale)
	return float(AUTO_PAUSE_SECONDS.get(speed, AUTO_PAUSE_SECONDS[DEFAULT_AUTO_SPEED])) + reading


## CJK ideographs, kana, Hangul and full-width forms and punctuation.
static func is_cjk(code: int) -> bool:
	return (code >= 0x2E80 and code <= 0x9FFF) or (code >= 0xAC00 and code <= 0xD7AF) \
		or (code >= 0xF900 and code <= 0xFAFF) or (code >= 0xFE30 and code <= 0xFE4F) \
		or (code >= 0xFF00 and code <= 0xFFEF) or (code >= 0x20000 and code <= 0x2FA1F)


static func _strip_markup(text: String) -> String:
	var regex := RegEx.create_from_string("\\[/?[a-z_]+[^\\]]*\\]")
	return regex.sub(text, "", true) if regex != null else text


## How long auto waits on the line on screen now.
func current_hold_seconds() -> float:
	var text := ""
	if _controller != null:
		text = String(_controller.get_current_line().get("text", ""))
	var speed := get_auto_speed()
	if text != _hold_text or speed != _hold_speed:
		_hold_text = text
		_hold_speed = speed
		_hold_base = hold_seconds(text, speed)
	var hold := _hold_base
	if _check_showing():
		hold += CHECK_EXTRA_SECONDS
	return hold


## Writes the read log now, if it changed.
func flush() -> bool:
	return _read_log.flush() if _read_log != null else true


# --- Driving ----------------------------------------------------------------------


func _process(delta: float) -> void:
	_update_mode()
	if not _presenting():
		_readable_for = 0.0
		return
	if _backlog != null and _backlog.is_open():
		return
	if _awaiting_choice():
		_stop_skip(STOP_CHOICE)
		_readable_for = 0.0
		return
	if is_skip_requested():
		var blocked := _skip_block()
		if blocked.is_empty():
			_stop_reason = &""
			if _panel != null and _panel.is_revealing():
				_panel.complete_reveal()
			_skip_clock += delta
			if _skip_clock >= SKIP_INTERVAL_SECONDS:
				_skip_clock = 0.0
				_advance()
			return
		_stop_skip(blocked)
	elif _skip_toggled or get_skip_mode() != SKIP_TOGGLE:
		_stop_reason = &""
	if not _auto:
		return
	if _panel != null and _panel.is_revealing():
		_readable_for = 0.0
		return
	_readable_for += delta
	if _readable_for >= current_hold_seconds():
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _pressed(event, &"dialogue_auto"):
		get_viewport().set_input_as_handled()
		toggle_auto()
	elif get_skip_mode() == SKIP_TOGGLE and _pressed(event, &"dialogue_skip"):
		get_viewport().set_input_as_handled()
		toggle_skip()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not InputMap.has_action(action) or not event.is_action_pressed(action):
		return false
	# A trigger streams events past its deadzone; only the crossing counts.
	return not event is InputEventJoypadMotion or Input.is_action_just_pressed(action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _advance() -> void:
	_readable_for = 0.0
	_advances += 1
	_controller.advance_presentation()


func _presenting() -> bool:
	if _controller == null or not _controller.is_busy():
		return false
	return _panel == null or _panel.visible


func _awaiting_choice() -> bool:
	if _controller != null and _controller.has_pending_choices():
		return true
	return _panel != null and _panel.has_choices()


## What stops skip on the line on screen, or empty when it may be skipped.
func _skip_block() -> StringName:
	if _check_showing():
		return STOP_CHECK
	if not _was_read and get_skip_scope() != &"all":
		return STOP_UNREAD
	return &""


func _stop_skip(reason: StringName) -> void:
	if not is_skip_requested():
		return
	_skip_clock = 0.0
	if _stop_reason == reason and not _skip_toggled:
		return
	_stop_reason = reason
	# A toggled skip ends where it stops; the reason stays up until the next line.
	_skip_toggled = false
	skip_stopped.emit(reason)
	_update_mode()


func _check_showing() -> bool:
	return _overlay != null and _overlay.is_showing()


func _update_mode() -> void:
	var mode := MODE_OFF
	if is_skip_requested() and _presenting() and String(_stop_reason).is_empty() \
			and _skip_block().is_empty() and not _awaiting_choice():
		mode = MODE_SKIP
	elif _auto:
		mode = MODE_AUTO
	if mode != _mode:
		_mode = mode
		mode_changed.emit(mode)
	var state := "%s/%s" % [_mode, _stop_reason]
	if state != _announced:
		_announced = state
		state_changed.emit()


func _on_line_presented(line: Dictionary) -> void:
	_identity = DialogueHistory.identify(line)
	_was_read = _read_log != null and _read_log.has_read(_identity)
	if _read_log != null:
		_read_log.mark(_identity)
	_readable_for = 0.0
	_stop_reason = &""


func _on_presentation_active(active: bool) -> void:
	_readable_for = 0.0
	_skip_clock = 0.0
	if not active:
		_identity = ""
		_was_read = false
		_stop_reason = &""
		_skip_toggled = false
		flush()
	_update_mode()


func _settings() -> Node:
	return get_node_or_null(^"/root/Settings")
