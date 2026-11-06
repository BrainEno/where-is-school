extends Node
## Procedural, asset-free audio cues for the prologue.
##
## The art bible calls for restrained, material sound. This node synthesises a
## handful of short cues at runtime (soft bell, door, chair, paper, room tone) so
## the classroom can carry atmosphere without shipping unreviewed third-party
## audio. Every cue is generated from a deterministic formula — no samples, no
## downloads, no licensing questions.
##
## This is deliberately a placeholder: a future audio pass replaces [method play]
## with authored streams behind the same call sites.

const MIX_RATE := 22050.0

var _players: Array[AudioStreamPlayer] = []
var _room_tone: AudioStreamPlayer
var _room_tone_linear: float = 0.0
var _room_tone_target: float = 0.0
var _cue_cache: Dictionary = {}
var _master_volume: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 4:
		var player := AudioStreamPlayer.new()
		player.name = "CuePlayer%d" % index
		add_child(player)
		_players.append(player)

	_room_tone = AudioStreamPlayer.new()
	_room_tone.name = "RoomTone"
	add_child(_room_tone)
	_room_tone.stream = _make_room_tone()
	_room_tone.volume_db = -60.0


func _process(delta: float) -> void:
	if _room_tone == null:
		return
	_room_tone_linear = move_toward(_room_tone_linear, _room_tone_target, delta * 0.25)
	if _room_tone_linear > 0.0005:
		if not _room_tone.playing:
			_room_tone.play()
		_room_tone.volume_db = linear_to_db(_room_tone_linear)
	elif _room_tone.playing:
		_room_tone.stop()
		_room_tone.volume_db = -60.0


## Plays a named cue. Unknown names are reported instead of silently ignored.
func play(cue: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _stream_for(cue)
	if stream == null:
		push_warning("AudioCues.play: unknown cue '%s'." % String(cue))
		return
	var player: AudioStreamPlayer = _free_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db + linear_to_db(maxf(_master_volume, 0.0001))
	player.play()


func set_room_tone(level: float) -> void:
	_room_tone_target = clampf(level, 0.0, 1.0) * 0.06


func set_master_volume(linear: float) -> void:
	_master_volume = clampf(linear, 0.0, 1.0)


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0] if not _players.is_empty() else null


func _stream_for(cue: StringName) -> AudioStream:
	if _cue_cache.has(cue):
		return _cue_cache[cue]
	var stream: AudioStream = null
	match cue:
		&"bell": stream = _make_bell()
		&"chalk": stream = _make_noise_burst(0.05, 2600.0, 0.16, 0.0)
		&"paper": stream = _make_noise_burst(0.16, 1500.0, 0.20, 0.08)
		&"chair": stream = _make_thud(0.18, 120.0, 0.28)
		&"door": stream = _make_thud(0.42, 74.0, 0.34)
		&"cloth": stream = _make_noise_burst(0.30, 900.0, 0.14, 0.02)
		&"pencil": stream = _make_noise_burst(0.09, 3200.0, 0.10, 0.0)
		&"distant": stream = _make_distant_murmur()
		&"step": stream = _make_thud(0.10, 160.0, 0.16)
	if stream != null:
		_cue_cache[cue] = stream
	return stream


# --- synthesis --------------------------------------------------------------

func _make_bell() -> AudioStreamWAV:
	# A modest institutional bell: two detuned partials with a soft attack and a
	# long, quiet tail. Never loud enough to startle.
	var duration := 2.2
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var attack: float = clampf(t / 0.012, 0.0, 1.0)
		var decay: float = exp(-t * 2.1)
		var tone: float = (
			sin(TAU * 523.0 * t) * 0.55
			+ sin(TAU * 784.0 * t) * 0.22
			+ sin(TAU * 1046.0 * t) * 0.12
		)
		var sample: float = tone * attack * decay * 0.22
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav_from(data)


func _make_thud(duration: float, frequency: float, amplitude: float) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-t * (6.0 / maxf(duration, 0.01)))
		var body: float = sin(TAU * frequency * t) * 0.7
		var knock: float = sin(TAU * frequency * 3.1 * t) * 0.3
		var sample: float = (body + knock) * env * amplitude
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav_from(data)


func _make_noise_burst(duration: float, cutoff: float, amplitude: float, tail: float) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration + tail * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff) * 17 + frames
	var previous := 0.0
	var alpha: float = clampf(cutoff / MIX_RATE, 0.01, 0.9)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var env: float = clampf(t / 0.01, 0.0, 1.0) * exp(-t * (4.0 / maxf(duration, 0.01)))
		var white: float = rng.randf_range(-1.0, 1.0)
		previous = lerpf(previous, white, alpha)
		var sample: float = previous * env * amplitude
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav_from(data)


func _make_distant_murmur() -> AudioStreamWAV:
	var duration := 1.6
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var env: float = sin(PI * clampf(t / duration, 0.0, 1.0))
		var wobble: float = sin(TAU * 0.9 * t) + 0.4 * sin(TAU * 2.3 * t + 1.1)
		var sample: float = wobble * env * 0.06
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav_from(data)


func _make_room_tone() -> AudioStreamWAV:
	# Looped, very quiet low room hum: fluorescent fittings and a distant yard.
	var duration := 4.0
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var previous := 0.0
	for i in frames:
		var t: float = float(i) / MIX_RATE
		var loop_env: float = 0.5 + 0.5 * sin(TAU * (t / duration))
		previous = lerpf(previous, rng.randf_range(-1.0, 1.0), 0.02)
		var hum: float = sin(TAU * 100.0 * t) * 0.35 + previous * 0.9
		var sample: float = hum * loop_env * 0.5
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := _wav_from(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav


func _wav_from(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = data
	return wav
