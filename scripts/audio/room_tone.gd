class_name RoomTone
extends AudioStreamPlayer
## Restrained, generated ambience for the prologue.
##
## The repository contains no audio assets yet (see docs/ASSET_PROVENANCE.md), and
## the task forbids shipping unclear-rights material. So the slice synthesises a
## very quiet low-frequency room tone and a short, dull bell at load time with
## AudioStreamGenerator. Nothing is downloaded, nothing is licensed, and replacing
## this node with real authored audio later changes no gameplay code.
##
## Sound here is only used for two things: the room is not silent, and a bell is
## a bell. It never carries story information that the text does not also carry.

@export var tone_volume_db: float = -26.0
@export var tone_hz: float = 61.5
@export var bell_volume_db: float = -12.0
@export var bell_hz: float = 196.0
@export var bell_seconds: float = 1.6

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _sample_rate: float = 22050.0
var _bell_remaining: int = 0
var _bell_phase: float = 0.0
var _bell_elapsed: float = 0.0


func _exit_tree() -> void:
	# An AudioStreamGeneratorPlayback holds an internal buffer that outlives a plain
	# `stop()`. It is an engine-side reference released on AudioServer shutdown, so
	# the only user-side action is to stop feeding it. This is why the headless boot
	# reports one leaked AudioStreamGeneratorPlayback at exit; it is not a node leak.
	stop()
func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _sample_rate
	generator.buffer_length = 0.4
	stream = generator
	volume_db = tone_volume_db
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null or not is_inside_tree():
		return
	var frames: int = _playback.get_frames_available()
	if frames <= 0:
		return
	var increment: float = tone_hz / _sample_rate
	var bell_increment: float = bell_hz / _sample_rate
	for _i in frames:
		# Two detuned low partials: a room hum, not a musical drone.
		_phase = fmod(_phase + increment, 1.0)
		var sample: float = (
			sin(_phase * TAU) * 0.55
			+ sin(_phase * TAU * 2.004) * 0.18
			+ sin(_phase * TAU * 3.011) * 0.07
		) * 0.06
		if _bell_remaining > 0:
			_bell_phase = fmod(_bell_phase + bell_increment, 1.0)
			_bell_elapsed += 1.0 / _sample_rate
			var decay: float = clampf(1.0 - (_bell_elapsed / bell_seconds), 0.0, 1.0)
			var bell: float = (
				sin(_bell_phase * TAU) * 0.6
				+ sin(_bell_phase * TAU * 2.76) * 0.3
				+ sin(_bell_phase * TAU * 5.4) * 0.1
			) * decay * decay * 0.22
			sample += bell
			_bell_remaining -= 1
		_playback.push_frame(Vector2(sample, sample))


## Rings the lesson bell. Called by PrologueHud/flow at the Beat F transition.
func ring_bell() -> void:
	_bell_remaining = int(_sample_rate * bell_seconds)
	_bell_elapsed = 0.0
	_bell_phase = 0.0
	volume_db = maxf(tone_volume_db, bell_volume_db)
