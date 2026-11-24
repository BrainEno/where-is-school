class_name ConcussionView
extends CanvasLayer
## The dazed look after a hurt landing: the world as a static postmodern paste-up that
## fades over four minutes of play (docs/CONCUSSION_VIEW.md).
##
## The protagonist lands hard on the container roof (`ContainerLanding`, the hurt branch of
## the curtain fall) and from that contact the screen is a collage of itself - sheets pasted
## slightly off, printed in different manners, a cracked shard of mirror quoting the middle
## of the frame (`assets/shaders/injury/concussion_collage.gdshader`). It is an art style,
## not a symptom: nothing moves, nothing pulses, the camera is untouched, and the middle of
## the frame stays legible. It is at its strongest at the landing and thins out quickly at
## first, then slowly, until after `DURATION` seconds of play it is gone.
##
## **A second fall** (jumping off the container roof, `RoofWayDown`) restarts it heavier:
## `begin(from, true)` writes `HEAVY_SECONDS`, and every second above `DURATION` is drawn
## stronger than the landing (`daze` up to `HEAVY_DAZE`), pressing the same paste-up harder.
##
## **The yard tap** ends it: a mouthful of water or a wash of the face clears it
## (`clear()`). That is only a flag write; this node eases the picture out over
## `RELIEF_SECONDS`, never a cut.
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
const DURATION := 240
## Seconds a second fall writes: the part above `DURATION` is the heavier look.
const HEAVY_SECONDS := 300
## The strength drawn at `HEAVY_SECONDS` (the landing is 1).
const HEAVY_DAZE := 1.25
## How quickly the look arrives at the landing: the moment of contact, not a fade.
const ARRIVAL_SECONDS := 0.35
## How long the picture takes to clear after water: quick, but never a cut.
const RELIEF_SECONDS := 1.4
## Fast, then slow: `daze` falls as `exp(-FADE_RATE * elapsed share)`, rescaled to end at 0.
## 2.4 takes about half of the look in the first minute of four.
const FADE_RATE := 2.4

@export var sheet_path: NodePath = ^"Sheet"
@export var host_path: NodePath = ^"../LocationHost"

var _sheet: ColorRect = null
var _game_state: Node = null
var _seconds_left := 0.0
## The value last written to (or read from) the flag, so this node's own writes are not
## taken for a new landing.
var _written := 0
## A change written by someone else (a landing, a fall, the tap) is eased: the strength
## drawn goes from `_ease_from` to the counted one while `_ease` runs 0..1 over
## `_ease_seconds`. 1 when nothing is changing.
var _ease := 1.0
var _ease_from := 0.0
var _ease_seconds := ARRIVAL_SECONDS


## Starts the look: the hurt landing calls this at the moment of contact. A second fall
## (`heavier`) writes `HEAVY_SECONDS`, never less than what is already left.
static func begin(from: Node, heavier: bool = false) -> void:
	var state := _state_of(from)
	if state == null:
		return
	if not heavier:
		state.set_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, DURATION)
		return
	var left: Variant = state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)
	var now := int(left) if left is int or left is float else 0
	state.set_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, maxi(HEAVY_SECONDS, now))


## Water from the yard tap, drunk or on the face: the look is gone at once (eased over
## `RELIEF_SECONDS`).
static func clear(from: Node) -> void:
	var state := _state_of(from)
	if state != null:
		state.set_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)


## The strength of the look for `seconds_left` of play remaining: 1 at the landing, 0 at
## the end, above 1 (to `HEAVY_DAZE`) after a second fall. Fast first, then slow. Static
## so tests and captures can ask for it without a scene.
static func daze_for(seconds_left: float) -> float:
	if seconds_left > DURATION:
		var over := clampf((seconds_left - DURATION) / float(HEAVY_SECONDS - DURATION), 0.0, 1.0)
		return lerpf(1.0, HEAVY_DAZE, over)
	var elapsed := 1.0 - clampf(seconds_left / float(DURATION), 0.0, 1.0)
	var floor_value := exp(-FADE_RATE)
	return maxf(0.0, (exp(-FADE_RATE * elapsed) - floor_value) / (1.0 - floor_value))


## The remaining seconds at which the look has `daze` strength (the inverse of `daze_for`).
static func seconds_for(daze: float) -> float:
	if daze <= 0.0:
		return 0.0
	if daze > 1.0:
		var over := clampf((daze - 1.0) / (HEAVY_DAZE - 1.0), 0.0, 1.0)
		return DURATION + over * (HEAVY_SECONDS - DURATION)
	var floor_value := exp(-FADE_RATE)
	var elapsed := -log(daze * (1.0 - floor_value) + floor_value) / FADE_RATE
	return float(DURATION) * (1.0 - clampf(elapsed, 0.0, 1.0))


static func _state_of(from: Node) -> Node:
	return from.get_node_or_null(^"/root/GameState") if from != null else null


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
	if not _is_drawn():
		set_process(false)
		return
	_seconds_left = maxf(0.0, _seconds_left - delta)
	_ease = minf(1.0, _ease + delta / _ease_seconds)
	var whole := ceili(_seconds_left)
	if whole != _written and _game_state != null:
		_written = whole
		# A tick, not an event: the flag is saved as always, but nobody else is woken once a
		# second for it (#348). The landing, the water and a loaded save still announce.
		_game_state.set_flag_quiet(StoryFlags.CONCUSSION_SECONDS_LEFT, whole)
	_apply()
	if not _is_drawn():
		set_process(false)


## Seconds of play left on the look, as counted now (finer than the saved flag).
func get_seconds_left() -> float:
	return _seconds_left


## The strength drawn this frame (0..`HEAVY_DAZE`), an arrival or a relief included.
func get_daze() -> float:
	var counted := daze_for(_seconds_left)
	if _ease >= 1.0:
		return counted
	return lerpf(_ease_from, counted, smoothstep(0.0, 1.0, _ease))


func _on_story_flag_changed(flag: StringName, previous: Variant, _value: Variant) -> void:
	if flag != StoryFlags.CONCUSSION_SECONDS_LEFT:
		return
	var seconds := _read_flag()
	if seconds == _written:
		return
	# A value larger than the one before is a landing or a fall: the look arrives at the
	# contact. A smaller one is the tap's water: the picture settles, quickly.
	var before := int(previous) if previous is int or previous is float else 0
	_ease_from = get_daze()
	_ease_seconds = ARRIVAL_SECONDS if seconds > before else RELIEF_SECONDS
	_ease = 0.0
	_set_seconds(seconds)


## Takes the remaining time from the story, as a loaded save or a new game left it.
func _adopt_story() -> void:
	_ease = 1.0
	_set_seconds(_read_flag())


func _set_seconds(seconds: int) -> void:
	_written = seconds
	_seconds_left = float(seconds)
	set_process(_is_drawn())
	_apply()


func _read_flag() -> int:
	if _game_state == null:
		return 0
	var value: Variant = _game_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)
	if value is int or value is float:
		return clampi(int(value), 0, HEAVY_SECONDS)
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
	# the frame unchanged) and the last of a wash, which eases out after the flag is 0.
	var on := _is_drawn()
	visible = on
	if _sheet != null:
		_sheet.visible = on


func _is_drawn() -> bool:
	return _seconds_left > 0.0 or _ease < 1.0


func _material() -> ShaderMaterial:
	return _sheet.material as ShaderMaterial if _sheet != null else null
