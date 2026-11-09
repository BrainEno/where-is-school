extends Node
## The four sounds the interaction cues make, synthesised at runtime.
##
## The cues the mouse draws (`scripts/interaction/world_cue.gd` and the two cue nodes) are
## silent shapes. This node gives each of them a voice, so the feedback a click produces is
## heard as well as seen: a soft dry tick where a walk was accepted, the same tick a little
## brighter on an object, a duller closed thud when the world refuses, and a very quiet
## tick when the pointer finds something it can use.
##
## Three rules keep it from turning into interface noise:
##
## - **Nothing is a file.** The four buffers are computed here, once, at startup, from the
##   same kind of additive synthesis `tools/generate_placeholder_audio.py` uses for the room
##   tones. No sample library, no import sidecar, nothing to license or lose. The cues are
##   also deterministic: no randomness in the tones that repeat (only the refusal's noise
##   floor, and that is a seeded integer sequence).
## - **Quiet by construction.** Every cue sits well under the room tone (-30 dB or lower),
##   decays in a fraction of a second, and owns no bus. A cue is an acknowledgement, not an
##   event.
## - **One rate limit, on the only thing that can repeat fast.** The hover tick fires when
##   the highlighted object changes, which happens as the player looks around. It is
##   therefore held to one tick per `HOVER_MIN_INTERVAL_SECONDS`; the three click sounds are
##   not limited, because a click is always worth hearing and a player cannot click twice in
##   ten milliseconds anyway.
##
## Loaded as the `CueAudio` autoload. Callers look it up by node path (`/root/CueAudio`)
## rather than by a global constant, so a headless test that never registers autoloads
## simply gets silence instead of a compile error.

const SAMPLE_RATE := 22050

const KIND_DESTINATION := &"destination"
const KIND_TARGET := &"target"
const KIND_REFUSED := &"refused"
const KIND_HOVER := &"hover"
## Every kind this node can make, in the order a player meets them.
const KINDS: Array[StringName] = [KIND_DESTINATION, KIND_TARGET, KIND_REFUSED, KIND_HOVER]

## One tick per this many seconds, for the hover sound only.
const HOVER_MIN_INTERVAL_SECONDS := 0.12

## Players per kind: a second click may land while the first is still decaying.
const VOICES_PER_KIND := 2

## -30 dB for the hover tick: audible when the room is quiet, never in front of it.
const VOLUME_DB := {
	KIND_DESTINATION: -20.0,
	KIND_TARGET: -20.0,
	KIND_REFUSED: -22.0,
	KIND_HOVER: -30.0,
}

## Peak amplitude of each buffer, before the player's volume. Small on purpose: a cue that
## has to be turned down in the mixer is a cue that was written too loud.
const PEAK := {
	KIND_DESTINATION: 0.20,
	KIND_TARGET: 0.22,
	KIND_REFUSED: 0.26,
	KIND_HOVER: 0.075,
}

var _streams: Dictionary = {}
var _players: Dictionary = {}
var _counts: Dictionary = {}
var _last_hover_msec: int = -1000000
var _silent := false
var _built := false


func _ready() -> void:
	_build()


## Everything the node can play, in or out of the tree, quiet or not: the streams are pure
## data, so building them early keeps the first click from being the moment they are made.
func _build() -> void:
	if _built:
		return
	_built = true
	_streams[KIND_DESTINATION] = _tone(430.0, 0.15, 0.045, 0.30, PEAK[KIND_DESTINATION])
	_streams[KIND_TARGET] = _tone(575.0, 0.15, 0.042, 0.38, PEAK[KIND_TARGET])
	_streams[KIND_REFUSED] = _refusal(0.24, PEAK[KIND_REFUSED])
	_streams[KIND_HOVER] = _tone(1180.0, 0.045, 0.010, 0.18, PEAK[KIND_HOVER])
	for kind: StringName in KINDS:
		_counts[kind] = 0
		var voices: Array[AudioStreamPlayer] = []
		for index in VOICES_PER_KIND:
			var player := AudioStreamPlayer.new()
			player.name = "Voice%d" % index
			player.stream = _streams[kind]
			player.volume_db = float(VOLUME_DB[kind])
			player.bus = &"Master"
			add_child(player)
			voices.append(player)
		_players[kind] = voices


## A fast, dry tick: two partials under an exponential decay with a 2 ms attack, which is
## what keeps it from clicking on its own.
func _tone(
	frequency: float,
	duration: float,
	decay: float,
	partial: float,
	peak: float
) -> AudioStreamWAV:
	var total := int(duration * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var normaliser := 1.0 / (1.0 + partial)
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		var envelope := exp(-time / decay)
		if time < 0.002:
			envelope *= time / 0.002
		var value := (
			sin(TAU * frequency * time)
			+ partial * sin(TAU * frequency * 2.0 * time + 0.7)
		)
		samples[index] = value * normaliser * envelope * peak
	return _to_wav(samples)


## The refusal is duller and longer than the click, and it is the only cue with a noise
## floor: a closed, low sound rather than a low note.
func _refusal(duration: float, peak: float) -> AudioStreamWAV:
	var total := int(duration * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	# A fixed seed, advanced by an integer recurrence: the same noise every time.
	var state := 9781
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		var envelope := exp(-time / 0.075)
		if time < 0.004:
			envelope *= time / 0.004
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(state % 20001) / 10000.0 - 1.0
		var body := sin(TAU * 138.0 * time) + 0.4 * sin(TAU * 207.0 * time + 1.1)
		samples[index] = (0.72 * body + 0.28 * noise) * envelope * peak
	return _to_wav(samples)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index in samples.size():
		data.encode_s16(index * 2, int(roundf(clampf(samples[index], -1.0, 1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


## Plays the sound for one cue kind. Returns whether anything was actually started, so a
## caller (and a test) can tell "the world refused" from "the world refused while muted".
func play(kind: StringName) -> bool:
	_build()
	if _silent:
		return false
	if not _streams.has(kind):
		push_warning("CueAudio: '%s' is not a cue kind." % String(kind))
		return false
	if kind == KIND_HOVER:
		var now := Time.get_ticks_msec()
		if now - _last_hover_msec < int(HOVER_MIN_INTERVAL_SECONDS * 1000.0):
			return false
		_last_hover_msec = now
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	var voices: Array = _players.get(kind, [])
	for voice: AudioStreamPlayer in voices:
		# Round-robin over two voices: the second click cuts nothing off, it plays beside it.
		if not voice.playing:
			if is_inside_tree():
				voice.play()
			return true
	var first: AudioStreamPlayer = voices[0] if not voices.is_empty() else null
	if first != null and is_inside_tree():
		first.play()
	return true


func play_destination() -> bool:
	return play(KIND_DESTINATION)


func play_target() -> bool:
	return play(KIND_TARGET)


func play_refused() -> bool:
	return play(KIND_REFUSED)


func play_hover() -> bool:
	return play(KIND_HOVER)


## Mute switch, for the tests and for the settings screen that does not exist yet. Muting
## stops what is playing as well: a cue that keeps ringing after being muted is a bug.
func set_silent(value: bool) -> void:
	_silent = value
	if not value:
		return
	for kind: StringName in KINDS:
		for voice: AudioStreamPlayer in (_players.get(kind, []) as Array):
			voice.stop()


func is_silent() -> bool:
	return _silent


## The buffer for a kind, or null. Public so a test can measure what is actually played:
## length, peak, mono, sample rate — the properties a placeholder synth must keep.
func stream_for(kind: StringName) -> AudioStreamWAV:
	_build()
	return _streams.get(kind) as AudioStreamWAV


## How many times a kind has been played this session. Diagnostics for the capture run and
## for the tests; nothing in the game reads it.
func get_play_count(kind: StringName) -> int:
	return int(_counts.get(kind, 0))


func get_total_plays() -> int:
	var total := 0
	for kind: StringName in KINDS:
		total += get_play_count(kind)
	return total


## Every count at once, in the shape the capture run writes into its log.
func get_counts() -> Dictionary:
	var counts := {}
	for kind: StringName in KINDS:
		counts[String(kind)] = get_play_count(kind)
	return counts


func reset_counts() -> void:
	for kind: StringName in KINDS:
		_counts[kind] = 0
	_last_hover_msec = -1000000
