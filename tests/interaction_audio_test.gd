extends SceneTree
## The sounds the interaction cues make.
##
## A headless run cannot hear anything, and this is not an audio-quality test — it pins down
## the properties that make a synthesised placeholder safe to ship and that a reviewer can
## check without speakers:
##
## 1. the node can make exactly four cues, and every cue kind it advertises has a buffer;
## 2. the buffers are real audio — 16-bit, mono, 22.05 kHz, a few hundredths of a second
##    long, and quiet (a cue that has to be turned down was written too loud);
## 3. the four are *different* sounds: an accepted click, an accepted click on an object, a
##    refusal and a hover tick are not the same buffer four times;
## 4. a play is counted, an unknown kind is not played, and a muted node plays nothing;
## 5. the hover tick is held to one per `HOVER_MIN_INTERVAL_SECONDS` (it fires whenever the
##    highlighted object changes, which is the one thing that can machine-gun);
## 6. the wiring is real: `Interactable.set_highlighted(true)` ticks once and not on the way
##    out, and `PointerNavigator` asks for the sound that matches the cue it is drawing, on
##    the same `marker_enabled` switch.
##
## Nothing here asserts that a sound was *audible*: that needs a device. What it asserts is
## that the right buffer was sent to a player, which is the part that can regress silently.

const Harness = preload("res://tests/test_harness.gd")
const CueAudioScript := preload("res://scripts/audio/cue_audio.gd")
const InteractableScene := preload("res://scenes/interaction/interactable.tscn")
const NavigatorScript := preload("res://scripts/interaction/pointer_navigator.gd")

const TIMEOUT_SECONDS := 60.0

var _failures: Array[String] = []
var _checks: int = 0
## Deliberately untyped: the node is looked up at run time and every member is dynamic, so a
## static `Node` type would make the whole file fail to compile on the first property access.
var _audio = null


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "interaction_audio_test.gd")
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	await _check_registry()
	await _check_buffers()
	await _check_counts()
	await _check_silence()
	await _check_hover_limit()
	await _check_voices()
	await _check_interactable_wiring()
	await _check_navigator_wiring()
	Harness.finish(
		self,
		_failures,
		"four cue sounds are synthesised, distinct, quiet, rate-limited where they have to "
		+ "be, and asked for by the same code that draws the cue."
	)


# --- the node ---------------------------------------------------------------


func _check_registry() -> void:
	Harness.stage = "cue audio registry"
	_audio = Harness.ensure_autoload(self, "CueAudio", "res://scripts/audio/cue_audio.gd")
	_expect(_audio != null, "The CueAudio autoload could not be created.")
	if _audio == null:
		return
	for method: String in [
		"play", "play_destination", "play_target", "play_refused", "play_hover",
		"stream_for", "get_play_count", "get_total_plays", "get_counts", "reset_counts",
		"set_silent", "is_silent",
	]:
		_expect(_audio.has_method(method), "CueAudio has no %s()." % method)
	var kinds: Array = _audio.KINDS
	_expect(kinds.size() == 4, "CueAudio advertises %d kinds, not four." % kinds.size())
	var seen := {}
	for kind: StringName in kinds:
		_expect(not seen.has(kind), "CueAudio lists the kind '%s' twice." % String(kind))
		seen[kind] = true


## The four sounds are not equal to each other, and none of them is the same buffer as the
## drawn cue's palette decision: this is the seam a copy-paste would break.
func _check_buffers() -> void:
	Harness.stage = "cue audio buffers"
	if _audio == null:
		return
	var bodies: Array[PackedByteArray] = []
	for kind: StringName in _audio.KINDS:
		var stream := _audio.stream_for(kind) as AudioStreamWAV
		_expect(stream != null, "The '%s' cue has no stream." % String(kind))
		if stream == null:
			continue
		_expect(stream.stereo == false, "The '%s' cue is not mono." % String(kind))
		_expect(
			stream.format == AudioStreamWAV.FORMAT_16_BITS,
			"The '%s' cue is not 16-bit." % String(kind)
		)
		_expect(
			int(stream.mix_rate) == int(CueAudioScript.SAMPLE_RATE),
			"The '%s' cue runs at %d Hz, not %d."
			% [String(kind), int(stream.mix_rate), int(CueAudioScript.SAMPLE_RATE)]
		)
		var length := stream.get_length()
		_expect(
			length > 0.02 and length < 0.5,
			"The '%s' cue is %.3f s long: a cue is short or it is an event."
			% [String(kind), length]
		)
		var peak := _peak(stream)
		_expect(
			peak > 0.01 and peak < 0.4,
			"The '%s' cue peaks at %.3f: too quiet to hear or loud enough to sit over the room."
			% [String(kind), peak]
		)
		bodies.append(stream.data)
	# `PackedByteArray` compares by content, so this is a real "are these the same sound"
	# question rather than a hash that could collide.
	var shared := ""
	for first in bodies.size():
		for second in range(first + 1, bodies.size()):
			if bodies[first] == bodies[second]:
				shared = " (kinds %d and %d)" % [first, second]
	_expect(
		shared.is_empty(),
		"Two cue kinds share one buffer%s; the sounds are meant to be distinguishable." % shared
	)
	var hover := _audio.stream_for(&"hover") as AudioStreamWAV
	var refused := _audio.stream_for(&"refused") as AudioStreamWAV
	if hover != null and refused != null:
		_expect(
			refused.get_length() > hover.get_length() * 2.0,
			"The refusal (%.3f s) is not clearly longer than the hover tick (%.3f s)."
			% [refused.get_length(), hover.get_length()]
		)
		_expect(
			_peak(hover) < _peak(refused) * 0.6,
			"The hover tick is not quieter than the refusal."
		)


func _check_counts() -> void:
	Harness.stage = "cue audio counts"
	if _audio == null:
		return
	_audio.reset_counts()
	_expect(_audio.get_total_plays() == 0, "reset_counts() left a count behind.")
	_expect(_audio.play_destination(), "play_destination() reported nothing was played.")
	_expect(_audio.play_target(), "play_target() reported nothing was played.")
	_expect(_audio.play_refused(), "play_refused() reported nothing was played.")
	_expect(
		_audio.get_play_count(&"destination") == 1
		and _audio.get_play_count(&"target") == 1
		and _audio.get_play_count(&"refused") == 1,
		"The three click sounds were not each counted once (%s)." % str(_audio.get_counts())
	)
	_expect(_audio.get_total_plays() == 3, "The total play count does not add up.")
	var counts: Dictionary = _audio.get_counts()
	_expect(
		counts.size() == 4 and counts.has("refused"),
		"get_counts() is not keyed by the four cue names (%s)." % str(counts)
	)
	_expect(_audio.stream_for(&"nonsense") == null, "An unknown cue kind produced a stream.")
	_expect(not _audio.play(&"nonsense"), "An unknown cue kind was played.")
	_expect(
		_audio.get_total_plays() == 3,
		"An unknown cue kind was counted as a play."
	)


func _check_silence() -> void:
	Harness.stage = "cue audio silence"
	if _audio == null:
		return
	_audio.reset_counts()
	_audio.set_silent(true)
	_expect(_audio.is_silent(), "set_silent(true) did not take.")
	_expect(not _audio.play_destination(), "A muted cue reported that it played.")
	_expect(
		_audio.get_total_plays() == 0,
		"A muted cue was counted: the count is supposed to mean 'heard'."
	)
	_audio.set_silent(false)
	_expect(not _audio.is_silent(), "set_silent(false) did not take.")
	_expect(_audio.play_refused(), "The cue stayed silent after being unmuted.")


## The one sound that can fire many times a second is held to one per interval.
func _check_hover_limit() -> void:
	Harness.stage = "cue audio hover limit"
	if _audio == null:
		return
	_audio.reset_counts()
	var played := 0
	for attempt in 12:
		if _audio.play_hover():
			played += 1
	_expect(
		played == 1,
		"Twelve hover ticks in one frame produced %d plays; the limit is one per %.2f s."
		% [played, float(CueAudioScript.HOVER_MIN_INTERVAL_SECONDS)]
	)
	_expect(_audio.get_play_count(&"hover") == 1, "The hover count does not match the plays.")
	# Measured, not assumed: a "wait" that returns early would turn this stage into a test
	# of the rate limiter's refusal rather than of its expiry.
	var interval := int(CueAudioScript.HOVER_MIN_INTERVAL_SECONDS * 1000.0)
	var before := Time.get_ticks_msec()
	await _wait(float(CueAudioScript.HOVER_MIN_INTERVAL_SECONDS) + 0.25)
	var waited := Time.get_ticks_msec() - before
	_expect(
		waited >= interval,
		"The wait before the second hover tick lasted only %d ms, under the %d ms interval."
		% [waited, interval]
	)
	var played_again := _audio.play_hover()
	_expect(
		played_again,
		"The hover tick never came back: waited %d ms, interval %d ms, count %d, silent %s."
		% [waited, interval, _audio.get_play_count(&"hover"), str(_audio.is_silent())]
	)
	_expect(_audio.get_play_count(&"hover") == 2, "The second hover tick was not counted.")
	# The click sounds are not rate-limited: a click is always worth hearing.
	_audio.reset_counts()
	for attempt in 3:
		_audio.play_destination()
	_expect(
		_audio.get_play_count(&"destination") == 3,
		"The click sounds were rate-limited; only the hover tick is meant to be."
	)


## Two voices per kind, so a second click plays beside the first instead of cutting it off,
## and every voice carries the kind's own volume.
func _check_voices() -> void:
	Harness.stage = "cue audio voices"
	if _audio == null:
		return
	var players := 0
	for child in _audio.get_children():
		var player := child as AudioStreamPlayer
		if player == null:
			continue
		players += 1
		_expect(player.stream != null, "A cue voice has no stream.")
		_expect(
			player.volume_db <= -18.0,
			"A cue voice plays at %.1f dB: the cues are meant to sit under the room."
			% player.volume_db
		)
		_expect(
			player.bus == &"Master",
			"A cue voice is on the '%s' bus; there is no cue bus in this project." % player.bus
		)
	_expect(
		players == _audio.KINDS.size() * int(CueAudioScript.VOICES_PER_KIND),
		"There are %d cue voices for %d kinds." % [players, _audio.KINDS.size()]
	)


# --- the wiring -------------------------------------------------------------


func _check_interactable_wiring() -> void:
	Harness.stage = "interactable hover tick"
	if _audio == null:
		return
	var probe := InteractableScene.instantiate() as Interactable
	_expect(probe != null, "The interactable scene did not instantiate as an Interactable.")
	if probe == null:
		return
	probe.interact_id = &"audio_probe"
	probe.radius = 1.0
	root.add_child(probe)
	await process_frame
	_audio.reset_counts()
	probe.set_highlighted(true)
	_expect(
		_audio.get_play_count(&"hover") == 1,
		"Highlighting a prop did not make the hover tick (count %d)."
		% _audio.get_play_count(&"hover")
	)
	probe.set_highlighted(false)
	_expect(
		_audio.get_play_count(&"hover") == 1,
		"Un-highlighting a prop made a sound; the tick belongs to the pointer finding it."
	)
	probe.set_highlighted(true)
	_expect(
		_audio.get_play_count(&"hover") == 1,
		"A second highlight inside the hover interval was not held back."
	)
	probe.set_highlighted(false)
	# A prop can be told to stay quiet: a wall-mounted prop in a quiet room, for instance.
	probe.hover_cue_audio = false
	await _wait(float(CueAudioScript.HOVER_MIN_INTERVAL_SECONDS) + 0.05)
	probe.set_highlighted(true)
	_expect(
		_audio.get_play_count(&"hover") == 1,
		"hover_cue_audio = false did not silence the prop."
	)
	probe.hover_cue_audio = true
	probe.set_highlighted(false)
	probe.queue_free()
	await process_frame


func _check_navigator_wiring() -> void:
	Harness.stage = "navigator cue sound"
	if _audio == null:
		return
	var navigator := NavigatorScript.new() as PointerNavigator
	_expect(navigator != null, "The pointer navigator node could not be created.")
	if navigator == null:
		return
	navigator.name = "AudioProbeNavigator"
	root.add_child(navigator)
	await process_frame
	_audio.reset_counts()
	navigator._mark_refused(Vector3.ZERO)
	_expect(
		_audio.get_play_count(&"refused") == 1,
		"A refused click drew nothing and said nothing (refused count %d)."
		% _audio.get_play_count(&"refused")
	)
	navigator._mark_destination(Vector3.ZERO)
	_expect(
		_audio.get_play_count(&"destination") == 1,
		"An accepted floor click made no sound (destination count %d)."
		% _audio.get_play_count(&"destination")
	)
	navigator._mark_target(Vector3.ZERO)
	_expect(
		_audio.get_play_count(&"target") == 1,
		"A click on a prop made no sound (target count %d)."
		% _audio.get_play_count(&"target")
	)
	# `marker_enabled` is the bare-capture switch: it silences the cues as well as hiding
	# them, so a capture run does not sit there clicking into the void.
	navigator.marker_enabled = false
	_audio.reset_counts()
	navigator._mark_refused(Vector3.ZERO)
	navigator._mark_destination(Vector3.ZERO)
	navigator._mark_target(Vector3.ZERO)
	_expect(
		_audio.get_total_plays() == 0,
		"With marker_enabled off the cues still made %d sound(s)."
		% _audio.get_total_plays()
	)
	navigator.queue_free()
	await process_frame


# --- helpers ----------------------------------------------------------------


## Peak sample of a 16-bit mono buffer, as a fraction of full scale.
func _peak(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var peak := 0
	var index := 0
	while index + 1 < data.size():
		var value := absi(data.decode_s16(index))
		peak = maxi(peak, value)
		index += 2
	return float(peak) / 32767.0


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
