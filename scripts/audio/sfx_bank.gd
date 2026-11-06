class_name SfxBank
extends RefCounted
## Synthesized sound effects built at runtime.
## No downloaded or recorded audio assets are used by the prologue; every
## effect is generated as a small PCM buffer, so licensing is unambiguous.

const SAMPLE_RATE: int = 22050


static func bell() -> AudioStreamWAV:
	# Two strikes of a struck metal tube: partials with fast decay.
	var samples: Array[float] = []
	samples.append_array(_strike(0.0))
	samples.append_array(_strike(0.9))
	return _to_stream(samples)


static func ui_blip() -> AudioStreamWAV:
	var samples: Array[float] = []
	samples.append_array(_tone(1560.0, 0.05, 0.25))
	return _to_stream(samples)


static func paper() -> AudioStreamWAV:
	var samples: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261106
	for i in range(int(SAMPLE_RATE * 0.14)):
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = exp(-t * 18.0)
		samples.append((rng.randf_range(-1.0, 1.0)) * envelope * 0.5)
	return _to_stream(samples)


static func imagination_swell() -> AudioStreamWAV:
	# A low, slow, uneasy swell used only for subjective imagination.
	var samples: Array[float] = []
	var duration: float = 2.4
	for i in range(int(SAMPLE_RATE * duration)):
		var t: float = float(i) / SAMPLE_RATE
		var rise: float = clampf(t / 0.8, 0.0, 1.0)
		var fall: float = clampf((duration - t) / 1.0, 0.0, 1.0)
		var envelope: float = minf(rise, fall)
		var tremolo: float = 0.75 + 0.25 * sin(TAU * 4.4 * t)
		var sample: float = (sin(TAU * 55.0 * t) * 0.7 + sin(TAU * 82.5 * t) * 0.3)
		samples.append(sample * envelope * tremolo * 0.6)
	return _to_stream(samples)


static func _strike(offset: float) -> Array[float]:
	var samples: Array[float] = []
	var duration: float = 1.1
	var total: int = int(SAMPLE_RATE * duration)
	var lead: int = int(SAMPLE_RATE * offset)
	if lead > 0:
		for i in range(lead):
			samples.append(0.0)
	for i in range(total):
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = exp(-t * 3.2)
		var sample: float = (
			sin(TAU * 740.0 * t) * 0.55
			+ sin(TAU * 1108.0 * t) * 0.30
			+ sin(TAU * 1480.0 * t) * 0.18
		)
		samples.append(sample * envelope * 0.7)
	return samples


static func _tone(frequency: float, duration: float, amplitude: float) -> Array[float]:
	var samples: Array[float] = []
	for i in range(int(SAMPLE_RATE * duration)):
		var t: float = float(i) / SAMPLE_RATE
		var envelope: float = exp(-t * 30.0)
		samples.append(sin(TAU * frequency * t) * envelope * amplitude)
	return samples


static func _to_stream(samples: Array[float]) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped: float = clampf(samples[i], -1.0, 1.0)
		var value: int = int(clamped * 32767.0)
		bytes.encode_s16(i * 2, value)
	stream.data = bytes
	return stream
