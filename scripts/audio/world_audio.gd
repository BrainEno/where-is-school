extends Node
## The sounds the world makes when it is touched, as opposed to the sounds the pointer makes.
##
## `scripts/audio/cue_audio.gd` answers the mouse: a tick when a walk is accepted, a thud when
## the world refuses, a hair of a tick when something becomes usable. Those four are feedback
## for aiming, and they are deliberately dry synthesis - a player must never confuse "the game
## heard my click" with "something in the room moved".
##
## This node is the other half. A footstep on a wooden floor, a chair dragged back, a page
## turned, a bag lifted off a desk, a door swinging: the small sounds that tell a player the
## room is made of things rather than pictures. The distinction is the whole design:
##
## - **These own the `SFX` bus**, because the player's sound-effects dial must reach them and
##   the room tone already sits there. The pointer cues stay on `Master` so a mixer tweak to
##   the room cannot silence feedback.
## - **They are quiet and short**, but not as quiet as a cue. A footstep at 0.30 peak is a
##   footstep; the same level for a hover tick would be an event.
## - **Nothing repeats faster than `min_interval_seconds`.** Steps are the one sound that can
##   fire ten times a second, so they are paced by a stride rather than by the frame; every
##   kind has a floor it cannot beat.
## - **Every buffer is computed, not loaded.** Same reason as `cue_audio.gd`: no sample
##   library, no licence, no import sidecar, and the script is the whole provenance.
##   `tests/world_audio_test.py` measures the buffers without a speaker.
##
## Loaded as the `WorldAudio` autoload. Callers look it up by path (`/root/WorldAudio`) so a
## headless test that registers no autoloads gets silence instead of a compile error.

const SAMPLE_RATE := 22050

## A footstep: heel, then the floor answering. Walking fires this once per step.
const KIND_STEP := &"step"
## A chair pulled back or pushed in: wood sliding on wood, with a scrape.
const KIND_CHAIR := &"chair"
## A page turned: paper, dry and brief.
const KIND_PAPER := &"paper"
## An object picked up: a small weight lifting off a surface.
const KIND_PICKUP := &"pickup"
## A door: the latch, then the swing.
const KIND_DOOR := &"door"

const KINDS: Array[StringName] = [KIND_STEP, KIND_CHAIR, KIND_PAPER, KIND_PICKUP, KIND_DOOR]

## The shortest gap between two plays of the same kind. A step is the tight one: at a jog the
## feet land about four times a second, and a fifth sound in that second is a machine gun.
const MIN_INTERVAL_SECONDS := {
	KIND_STEP: 0.26,
	KIND_CHAIR: 0.35,
	KIND_PAPER: 0.20,
	KIND_PICKUP: 0.30,
	KIND_DOOR: 0.50,
}

## How loud each kind plays, on the `SFX` bus. Louder than a pointer cue (those sit at -20 dB
## and below) and still under the room: the room tone is the floor these sounds stand on.
const VOLUME_DB := {
	KIND_STEP: -18.0,
	KIND_CHAIR: -15.0,
	KIND_PAPER: -19.0,
	KIND_PICKUP: -14.0,
	KIND_DOOR: -13.0,
}

## Peak of each buffer before the player's volume: the shape is loud-then-decay, so this is
## the strike and not the average.
const PEAK := {
	KIND_STEP: 0.30,
	KIND_CHAIR: 0.34,
	KIND_PAPER: 0.20,
	KIND_PICKUP: 0.28,
	KIND_DOOR: 0.32,
}

## Where stereo matters a step and a door are heard from the side the body is on, but a
## placeholder that panned would need a listener position this node does not have. Mono, and
## the position is the caller's problem when there is something to position it with.
const VOICES_PER_KIND := 3

## The bus the world sounds play on, if the layout has one. `cue_audio.gd` keeps `Master`
## on purpose; this node wants the dial.
const BUS := &"SFX"

var _streams: Dictionary = {}
var _players: Dictionary = {}
var _counts: Dictionary = {}
var _last_msec: Dictionary = {}
var _silent := false
var _built := false


func _ready() -> void:
	_build()


func _notification(what: int) -> void:
	# Same release contract as `cue_audio.gd`: a sound still ringing at quit is a leak, and a
	# world sound is longer than a cue, so this matters more here than there.
	if what != NOTIFICATION_PREDELETE:
		return
	var voices: Array = []
	for kind: StringName in _players:
		voices.append_array(_players[kind] as Array)
	if AudioRelease.stop_all(voices) > 0 and not AudioRelease.wait_for_mix():
		print_verbose(
			"WorldAudio: no audio mix within %d ms of the stop; a world sound may be"
			% AudioRelease.TIMEOUT_MSEC
			+ " reported as leaked at exit."
		)


## Every buffer is pure data and cheap to make, so all five exist before the first step.
func _build() -> void:
	if _built:
		return
	_built = true
	_streams[KIND_STEP] = _step(PEAK[KIND_STEP])
	_streams[KIND_CHAIR] = _chair(PEAK[KIND_CHAIR])
	_streams[KIND_PAPER] = _paper(PEAK[KIND_PAPER])
	_streams[KIND_PICKUP] = _pickup(PEAK[KIND_PICKUP])
	_streams[KIND_DOOR] = _door(PEAK[KIND_DOOR])
	var bus := BUS if AudioServer.get_bus_index(BUS) != -1 else &"Master"
	for kind: StringName in KINDS:
		_counts[kind] = 0
		_last_msec[kind] = -1000000
		var voices: Array[AudioStreamPlayer] = []
		for index in VOICES_PER_KIND:
			var player := AudioStreamPlayer.new()
			player.name = "Voice%s%d" % [String(kind).capitalize(), index]
			player.stream = _streams[kind]
			player.volume_db = float(VOLUME_DB[kind])
			player.bus = bus
			add_child(player)
			voices.append(player)
		_players[kind] = voices


## A deterministic noise source. Same seed in, same buffer out, which is what lets the test
## compare two builds of the same kind and find them identical.
class Noise:
	var _state: int

	func _init(seed_value: int) -> void:
		_state = seed_value & 0x7FFFFFFF

	## Uniform in [-1, 1).
	func next() -> float:
		_state = (_state * 1103515245 + 12345) & 0x7FFFFFFF
		return float(_state % 20001) / 10000.0 - 1.0


## The soft attack every physical sound needs: a buffer that starts at full amplitude clicks,
## and a click reads as a bug in the audio rather than as an object.
static func _attack(time: float, seconds: float) -> float:
	return time / seconds if time < seconds else 1.0


## A wooden floor under a shoe: a low body that dies fast, a burst of noise for the scuff, and
## a short tail that is the room rather than the shoe.
func _step(peak: float) -> AudioStreamWAV:
	var total := int(0.17 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var noise := Noise.new(4211)
	# A one-pole low-pass over the noise: a heel scuff is dull, and white noise is a hiss.
	var smoothed := 0.0
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		var body := exp(-time / 0.028)
		var scuff := exp(-time / 0.045)
		smoothed += 0.42 * (noise.next() - smoothed)
		var thud := sin(TAU * 92.0 * time) * body
		var click := smoothed * scuff * 0.55
		samples[index] = (0.75 * thud + click) * _attack(time, 0.004) * peak
	return _to_wav(samples)


## A chair dragged across a floor: a scrape that starts and stops, over a wooden knock as the
## legs catch. The scrape is band-limited noise with a slow amplitude wobble, which is what
## separates "sliding" from "hissing".
func _chair(peak: float) -> AudioStreamWAV:
	var total := int(0.42 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var noise := Noise.new(9137)
	var smooth := 0.0
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		# The object is only moving for the middle of the buffer; it starts and stops.
		var travel := sin(PI * clampf(time / 0.42, 0.0, 1.0))
		travel *= travel
		smooth += 0.30 * (noise.next() - smooth)
		# A slow irregularity in the scrape: a chair does not slide at a constant rate.
		var wobble := 0.72 + 0.28 * sin(TAU * 11.0 * time + 0.6)
		var knock := sin(TAU * 148.0 * time) * exp(-time / 0.035)
		var scrape := smooth * travel * wobble
		samples[index] = (0.55 * scrape + 0.45 * knock) * _attack(time, 0.012) * peak
	return _to_wav(samples)


## A page: almost all noise, very little body, and it is over in a sixth of a second. The
## texture is the sound; a page with a pitch to it is a folder being fanned.
func _paper(peak: float) -> AudioStreamWAV:
	var total := int(0.19 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var noise := Noise.new(3307)
	var fine := 0.0
	var coarse := 0.0
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		# Two noise bands: the crisp edge of the sheet, and the body of the paper behind it.
		fine += 0.62 * (noise.next() - fine)
		coarse += 0.16 * (noise.next() - coarse)
		var envelope := _attack(time, 0.006) * exp(-time / 0.058)
		samples[index] = (0.62 * fine + 0.38 * coarse) * envelope * peak
	return _to_wav(samples)


## Something lifted off a desk: a scrape of contact breaking, then a small settling. The
## falling rather than rising amplitude is the difference between picking something up and
## putting it down - this is the up one.
func _pickup(peak: float) -> AudioStreamWAV:
	var total := int(0.26 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var noise := Noise.new(6619)
	var smooth := 0.0
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		smooth += 0.35 * (noise.next() - smooth)
		# The break of contact is sharper than the ring afterwards.
		var contact := exp(-time / 0.018)
		var ring := exp(-time / 0.085)
		var tone := sin(TAU * 330.0 * time) + 0.35 * sin(TAU * 495.0 * time + 0.9)
		samples[index] = (
			(0.42 * smooth * contact + 0.38 * tone * ring) * _attack(time, 0.005) * peak
		)
	return _to_wav(samples)


## A door: the latch first - a hard, short, high tick - then the swing, which is the long
## part and is mostly wood and air rather than a tone.
func _door(peak: float) -> AudioStreamWAV:
	var total := int(0.55 * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var noise := Noise.new(7723)
	var smooth := 0.0
	for index in total:
		var time := float(index) / float(SAMPLE_RATE)
		smooth += 0.22 * (noise.next() - smooth)
		# The latch: 40 ms of bright metal, then nothing.
		var latch := (
			sin(TAU * 1450.0 * time) + 0.6 * sin(TAU * 2180.0 * time + 0.4)
		) * exp(-time / 0.011)
		# The swing: air moving round a heavy panel for the rest of the buffer.
		var swing_time := maxf(time - 0.06, 0.0)
		var swing := smooth * exp(-swing_time / 0.19) * _attack(swing_time, 0.02)
		# The stop: the door meets the frame at the end.
		var stop_time := maxf(time - 0.34, 0.0)
		var stop := sin(TAU * 118.0 * stop_time) * exp(-stop_time / 0.03) * _attack(
			stop_time, 0.003
		)
		var value := 0.55 * latch + 0.30 * swing + 0.5 * stop
		samples[index] = value * _attack(time, 0.003) * peak
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


## Plays one world sound. Returns whether one actually started: a rate-limited or muted kind
## says false, so a caller can tell "the footstep was heard" from "the footstep was swallowed".
func play(kind: StringName) -> bool:
	_build()
	if _silent:
		return false
	if not _streams.has(kind):
		push_warning("WorldAudio: '%s' is not a world sound." % String(kind))
		return false
	var now := Time.get_ticks_msec()
	var interval := int(float(MIN_INTERVAL_SECONDS[kind]) * 1000.0)
	if now - int(_last_msec.get(kind, -1000000)) < interval:
		return false
	_last_msec[kind] = now
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	var voices: Array = _players.get(kind, [])
	var chosen: AudioStreamPlayer = null
	for voice: AudioStreamPlayer in voices:
		if not voice.playing:
			chosen = voice
			break
	if chosen == null and not voices.is_empty():
		chosen = voices[0]
	if chosen == null or not is_inside_tree():
		return false
	chosen.play()
	return true


func play_step() -> bool:
	return play(KIND_STEP)


func play_chair() -> bool:
	return play(KIND_CHAIR)


func play_paper() -> bool:
	return play(KIND_PAPER)


func play_pickup() -> bool:
	return play(KIND_PICKUP)


func play_door() -> bool:
	return play(KIND_DOOR)


## There is deliberately no `set_gain_db()` here. These sounds own the `SFX` bus, so the
## player's sound-effects dial already reaches them through it; adding a second gain on top
## would attenuate them twice and make the dial's scale lie. `cue_audio.gd` needs its own
## gain only because the cues own no bus.


func set_silent(value: bool) -> void:
	_silent = value
	if not value:
		return
	for kind: StringName in KINDS:
		for voice: AudioStreamPlayer in (_players.get(kind, []) as Array):
			voice.stop()


func is_silent() -> bool:
	return _silent


func stream_for(kind: StringName) -> AudioStreamWAV:
	_build()
	return _streams.get(kind) as AudioStreamWAV


func get_play_count(kind: StringName) -> int:
	return int(_counts.get(kind, 0))


func get_total_plays() -> int:
	var total := 0
	for kind: StringName in KINDS:
		total += get_play_count(kind)
	return total


func get_counts() -> Dictionary:
	var counts := {}
	for kind: StringName in KINDS:
		counts[String(kind)] = get_play_count(kind)
	return counts


func reset_counts() -> void:
	for kind: StringName in KINDS:
		_counts[kind] = 0
		_last_msec[kind] = -1000000
