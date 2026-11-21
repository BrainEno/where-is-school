class_name ConcussionView
extends CanvasLayer
## The dazed look after a hurt landing: the world as a static postmodern paste-up that
## fades over ten minutes of play (docs/CONCUSSION_VIEW.md).
##
## The protagonist lands hard on the container roof (`ContainerLanding`, the hurt branch of
## the curtain fall) and from that contact the screen is a collage of itself - sheets pasted
## slightly off, printed in different manners, a quotation of the middle of the frame, a few
## Memphis marks (`assets/shaders/injury/concussion_collage.gdshader`). It is an art style,
## not a symptom: nothing moves, nothing pulses, the camera is untouched, and the middle of
## the frame stays legible. It is at its strongest at the landing and thins out until, after
## `DURATION` seconds of play, it is gone.
##
## **State.** The only state is the story flag `concussion_seconds_left` (int). The landing
## writes `DURATION` (`begin()`); this node counts it down while the tree runs - a paused
## game (the pause menu, settings) does not heal - and writes the whole seconds back, so a
## save carries the remaining time like any other flag and Continue resumes the same look.
## 0 or absent is a clear view. A new game clears the flags and so the look.
##
## **Layering.** A full-screen world filter: group `world_filter`, layer -2, so it sits under
## the outline overlay (0) and the UI, and under the yard's impact misprint (-1), which then
## prints the collage like it prints the rest of the yard. The fade to black of a room change
## draws over it, and the paste-up is reshuffled behind that black (`seed` per room), so no
## change is ever seen happening.

## Seconds of play the look lasts after a hurt landing.
const DURATION := 600
## How quickly the look arrives at the landing: the moment of contact, not a fade.
const ARRIVAL_SECONDS := 0.35
## `daze = remaining ^ FADE_CURVE`: below 1 the look lingers, then leaves gently.
const FADE_CURVE := 0.6

@export var sheet_path: NodePath = ^"Sheet"
@export var host_path: NodePath = ^"../LocationHost"

var _sheet: ColorRect = null
var _game_state: Node = null
var _seconds_left := 0.0
## The value last written to (or read from) the flag, so this node's own writes are not
## taken for a new landing.
var _written := 0
## 0..1 while the look arrives at a landing; 1 otherwise.
var _arrival := 1.0


## Starts the look: the hurt landing calls this at the moment of contact.
static func begin(from: Node) -> void:
	var state := from.get_node_or_null(^"/root/GameState") if from != null else null
	if state != null:
		state.set_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, DURATION)


## The strength of the look for `seconds_left` of play remaining: 1 at the landing, 0 at
## the end. Static so tests and captures can ask for it without a scene.
static func daze_for(seconds_left: float) -> float:
	var remaining := clampf(seconds_left / float(DURATION), 0.0, 1.0)
	return pow(remaining, FADE_CURVE)


func _ready() -> void:
	_sheet = get_node_or_null(sheet_path) as ColorRect
	_game_state = get_node_or_null(^"/root/GameState")
	if _game_state != null:
		_game_state.story_flag_changed.connect(_on_story_flag_changed)
		_game_state.story_state_replaced.connect(_adopt_story)
	var host := get_node_or_null(host_path) as LocationHost
	if host != null:
		host.location_entered.connect(_on_location_entered)
		if host.get_current() != null:
			_reseed(host.get_current().location_id)
	_adopt_story()


func _process(delta: float) -> void:
	if _seconds_left <= 0.0:
		set_process(false)
		return
	_seconds_left = maxf(0.0, _seconds_left - delta)
	_arrival = minf(1.0, _arrival + delta / ARRIVAL_SECONDS)
	var whole := ceili(_seconds_left)
	if whole != _written and _game_state != null:
		_written = whole
		_game_state.set_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, whole)
	_apply()
	if _seconds_left <= 0.0:
		set_process(false)


## Seconds of play left on the look, as counted now (finer than the saved flag).
func get_seconds_left() -> float:
	return _seconds_left


## The strength drawn this frame (0..1), arrival included.
func get_daze() -> float:
	return daze_for(_seconds_left) * _arrival


func _on_story_flag_changed(flag: StringName, previous: Variant, _value: Variant) -> void:
	if flag != StoryFlags.CONCUSSION_SECONDS_LEFT:
		return
	var seconds := _read_flag()
	if seconds == _written:
		return
	# A value larger than the one before is a landing: the look arrives at the contact.
	var before := int(previous) if previous is int or previous is float else 0
	if seconds > before:
		_arrival = 0.0
	_set_seconds(seconds)


## Takes the remaining time from the story, as a loaded save or a new game left it.
func _adopt_story() -> void:
	_arrival = 1.0
	_set_seconds(_read_flag())


func _set_seconds(seconds: int) -> void:
	_written = seconds
	_seconds_left = float(seconds)
	set_process(_seconds_left > 0.0)
	_apply()


func _read_flag() -> int:
	if _game_state == null:
		return 0
	var value: Variant = _game_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)
	if value is int or value is float:
		return clampi(int(value), 0, DURATION)
	return 0


func _on_location_entered(location: LocationRoot, _spawn_id: StringName) -> void:
	if location != null:
		_reseed(location.location_id)


## Each room gets its own paste-up. Called on entry, which happens behind black.
func _reseed(location_id: StringName) -> void:
	var material := _material()
	if material != null:
		material.set_shader_parameter(&"seed", float(absi(hash(String(location_id))) % 997) / 7.0)


func _apply() -> void:
	var daze := get_daze()
	var material := _material()
	if material != null:
		material.set_shader_parameter(&"daze", daze)
	# Not drawn at all when clear: a full-screen read of the frame is not free. Drawn for
	# the whole of the look, including the first frame of the arrival (daze 0 there draws
	# the frame unchanged).
	var on := _seconds_left > 0.0
	visible = on
	if _sheet != null:
		_sheet.visible = on


func _material() -> ShaderMaterial:
	return _sheet.material as ShaderMaterial if _sheet != null else null
