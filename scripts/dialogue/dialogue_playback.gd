class_name DialoguePlayback
extends RefCounted
## How a conversation moves on when the player is not pressing anything: by hand (the
## default), by itself after a reading pause (auto), or fast through what was read (skip).
##
## This object only decides. It holds no node and reads no input; the dialogue controller
## tells it what is on screen (`begin_line`, the `view` passed to `tick`) and does what
## `tick` returns: nothing, finish the line that is typing, or advance - through the very
## same path a key press takes, so neither mode can do anything a player could not.
##
## **Auto.** A line is given time once it is fully on screen: a short breath plus its length
## at a reading speed for its language (`READING_CPS`), scaled by the player's choice
## (`AUTO_SPEED_FACTOR`), clamped to `MIN_PAUSE`..`MAX_PAUSE`, with `CHECK_PAUSE` more while a
## check's numbers are showing. Auto never picks an option: at a choice it waits. It stays on
## when a conversation ends - the next one plays the same way - until it is switched off.
##
## **Skip.** Every line the player has read before is shown whole and passed after
## `SKIP_STEP`. Skip stops by itself - and says why (`mode_changed`'s reason) - at a line that
## has not been read (unless the player chose to skip everything), at a choice, and when the
## presentation closes. A tap of the skip input toggles it; holding the input for
## `HOLD_SECONDS` or more makes it momentary, so letting go stops it. If auto was on when skip
## started, auto comes back when skip ends.
##
## **Never while the player is elsewhere.** `view.blocked` (the backlog is open, the window
## lost focus) freezes the clock: no line is passed while nobody can read it.

## Why playback changed mode. The panel turns the interesting ones into a notice.
signal mode_changed(mode: int, reason: StringName)

enum Mode { MANUAL, AUTO, SKIP }

## What `tick` asks the controller to do.
const NOTHING := &""
const COMPLETE := &"complete"
const ADVANCE := &"advance"

const AUTO_SPEEDS: Array[StringName] = [&"slow", &"normal", &"fast"]
const AUTO_SPEED_FACTOR: Dictionary = {&"slow": 1.5, &"normal": 1.0, &"fast": 0.6}
const SKIP_SCOPES: Array[StringName] = [&"read", &"all"]

## Seconds of breath before the reading time, so even a one-word line is not snatched away.
const BASE_PAUSE := 0.9
## Characters a reader gets through per second at the normal speed. Chinese is counted in
## characters and read at roughly a third of the rate of English letters.
const READING_CPS: Dictionary = {"zh-CN": 8.0, "en": 22.0}
const DEFAULT_READING_CPS := 18.0
const MIN_PAUSE := 1.2
const MAX_PAUSE := 14.0
const CHECK_PAUSE := 1.6
## Seconds each read line stays on screen while skipping: long enough to see the text flick
## past, short enough that a read conversation is gone in a moment.
const SKIP_STEP := 0.07
## A press of the skip input held at least this long is a hold, not a tap.
const HOLD_SECONDS := 0.4

## Stop reasons, for the notice and for the tests.
const REASON_TOGGLED := &"toggled"
const REASON_RELEASED := &"released"
const REASON_UNREAD := &"unread"
const REASON_CHOICE := &"choice"
const REASON_CLOSED := &"closed"
const REASON_STARTED := &"started"

var mode: Mode = Mode.MANUAL
var auto_speed: StringName = &"normal"
var skip_scope: StringName = &"read"

var _clock := 0.0
var _waited := 0.0
var _line_identity := ""
var _line_read := false
var _line_characters := 0
var _line_locale := ""
var _holding := false
var _pressed_at := 0.0
var _resume_auto := false


func is_auto() -> bool:
	return mode == Mode.AUTO


func is_skipping() -> bool:
	return mode == Mode.SKIP


## True while the skip input is down and skip may end when it is let go.
func is_holding_skip() -> bool:
	return _holding


## Seconds the line on screen has been waited on so far.
func get_waited() -> float:
	return _waited


func set_auto_speed(value: StringName) -> void:
	if AUTO_SPEEDS.has(value):
		auto_speed = value


func set_skip_scope(value: StringName) -> void:
	if SKIP_SCOPES.has(value):
		skip_scope = value


# --- Switching ---------------------------------------------------------------------


func toggle_auto() -> void:
	set_auto(mode != Mode.AUTO)


func set_auto(enabled: bool) -> void:
	if enabled:
		_resume_auto = false
		_holding = false
		_set_mode(Mode.AUTO, REASON_STARTED)
	elif mode == Mode.AUTO:
		_set_mode(Mode.MANUAL, REASON_TOGGLED)
	elif mode == Mode.SKIP:
		# Switching auto off while skipping means "do not come back to auto afterwards".
		_resume_auto = false


## The skip input went down: start skipping, or stop if it was already on.
func press_skip() -> void:
	if mode == Mode.SKIP:
		_holding = false
		_stop_skip(REASON_TOGGLED)
		return
	_resume_auto = mode == Mode.AUTO
	_holding = true
	_pressed_at = _clock
	_set_mode(Mode.SKIP, REASON_STARTED)


## The skip input came up. After a hold, that ends skip; after a tap, skip stays on.
func release_skip() -> void:
	if not _holding:
		return
	_holding = false
	if mode == Mode.SKIP and _clock - _pressed_at >= HOLD_SECONDS:
		_stop_skip(REASON_RELEASED)


## Back to reading by hand, whatever was on.
func stop() -> void:
	_holding = false
	_resume_auto = false
	if mode != Mode.MANUAL:
		_set_mode(Mode.MANUAL, REASON_TOGGLED)


# --- Lines -------------------------------------------------------------------------


## A new line is on screen. `was_read` is the read log's answer from *before* this showing.
func begin_line(identity: String, characters: int, was_read: bool, locale: String) -> void:
	_line_identity = identity
	_line_characters = maxi(characters, 0)
	_line_read = was_read
	_line_locale = locale
	_waited = 0.0


## The pause auto gives the line on screen, in seconds, once it is fully shown.
func auto_pause(check_showing: bool = false) -> float:
	var cps := float(READING_CPS.get(_line_locale, DEFAULT_READING_CPS))
	var pause := BASE_PAUSE + float(_line_characters) / maxf(cps, 1.0)
	pause *= float(AUTO_SPEED_FACTOR.get(auto_speed, 1.0))
	pause = clampf(pause, MIN_PAUSE, MAX_PAUSE)
	if check_showing:
		pause += CHECK_PAUSE
	return pause


## Advances the clock by `delta` and says what to do with the line on screen.
##
## `view` keys, all optional and false by default:
## - `presenting`: a line is on screen;
## - `revealing`: it is still typing itself out;
## - `choices`: options are waiting to be picked;
## - `blocked`: the player cannot be reading it (backlog open, window unfocused);
## - `check`: a check's numbers are on screen.
func tick(delta: float, view: Dictionary) -> StringName:
	_clock += maxf(delta, 0.0)
	if mode == Mode.MANUAL:
		return NOTHING
	if not bool(view.get("presenting", false)):
		if mode == Mode.SKIP:
			_stop_skip(REASON_CLOSED)
		_waited = 0.0
		return NOTHING
	if bool(view.get("blocked", false)):
		return NOTHING
	if bool(view.get("choices", false)):
		if mode == Mode.SKIP:
			_stop_skip(REASON_CHOICE)
		_waited = 0.0
		return NOTHING
	if mode == Mode.SKIP:
		if not _line_read and skip_scope != &"all":
			_stop_skip(REASON_UNREAD)
			return NOTHING
		if bool(view.get("revealing", false)):
			return COMPLETE
		_waited += delta
		if _waited >= SKIP_STEP:
			_waited = 0.0
			return ADVANCE
		return NOTHING
	# Auto.
	if bool(view.get("revealing", false)):
		_waited = 0.0
		return NOTHING
	_waited += delta
	if _waited >= auto_pause(bool(view.get("check", false))):
		_waited = 0.0
		return ADVANCE
	return NOTHING


func _stop_skip(reason: StringName) -> void:
	var back_to_auto := _resume_auto
	_resume_auto = false
	_holding = false
	_set_mode(Mode.AUTO if back_to_auto else Mode.MANUAL, reason)


func _set_mode(next: Mode, reason: StringName) -> void:
	_waited = 0.0
	if next == mode and reason != REASON_STARTED:
		return
	mode = next
	mode_changed.emit(int(mode), reason)
