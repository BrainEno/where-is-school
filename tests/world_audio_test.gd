extends SceneTree
## The sounds the world makes when it is touched.
##
## `tests/interaction_audio_test.gd` covers the pointer's feedback: the four cues that answer
## aiming. This file covers the other node, the one that answers touching - footsteps, a chair
## drawn in, a page, a pickup, a door - and the split between them, which is the design:
##
## 1. five kinds, every one with a buffer, and no two buffers the same;
## 2. real, quiet, short audio: 16-bit mono at 22.05 kHz, under the room, not clipped;
## 3. **the world sounds own the `SFX` bus and the pointer cues do not.** The cues are
##    deliberately unreachable from the mixer so a room tweak cannot silence feedback; the
##    world sounds have to be reachable, because the player's sound-effects dial is about them;
## 4. every kind is rate-limited against itself, and a rate-limited play says so;
## 5. the buffers are deterministic: two builds of the same kind are byte-identical, so a
##    change in the noise is a change someone made rather than a change that happened.
##
## Nothing here hears anything. `tests/world_audio_test.py` reads the synthesis itself; this
## file pins the node's behaviour, which is the part that can regress without a diff.

const Harness = preload("res://tests/test_harness.gd")
const WorldAudioScript := preload("res://scripts/audio/world_audio.gd")
const CueAudioScript := preload("res://scripts/audio/cue_audio.gd")

const TIMEOUT_SECONDS := 60.0

var checks := Harness.Checker.new()
## Untyped on purpose: every member is reached dynamically through the autoload, and a static
## `Node` type would fail to compile on the first property access.
var _audio = null


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "world_audio_test.gd")
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	await _check_registry()
	await _check_buffers()
	await _check_bus()
	await _check_rate_limits()
	await _check_determinism()
	await _check_silence()
	Harness.finish(
		self,
		checks.failures,
		"five world sounds are synthesised, distinct, quiet, on the SFX bus, rate-limited "
		+ "against themselves, and deterministic."
	)


func _check_registry() -> void:
	Harness.stage = "world audio registry"
	_audio = Harness.ensure_autoload(self, "WorldAudio", "res://scripts/audio/world_audio.gd")
	checks.expect(_audio != null, "The WorldAudio autoload could not be created.")
	if _audio == null:
		return
	for method: String in [
		"play", "play_step", "play_chair", "play_paper", "play_pickup", "play_door",
		"stream_for", "get_play_count", "get_total_plays", "get_counts", "reset_counts",
		"set_silent", "is_silent",
	]:
		checks.expect(_audio.has_method(method), "WorldAudio has no %s()." % method)
	var kinds: Array = _audio.KINDS
	checks.expect(kinds.size() == 5, "WorldAudio advertises %d kinds, not five." % kinds.size())
	var seen := {}
	for kind: StringName in kinds:
		checks.expect(not seen.has(kind), "WorldAudio lists the kind '%s' twice." % String(kind))
		seen[kind] = true
		checks.expect(
			_audio.stream_for(kind) != null,
			"The '%s' world sound has no stream." % String(kind)
		)


func _check_buffers() -> void:
	Harness.stage = "world audio buffers"
	if _audio == null:
		return
	var bodies: Array[PackedByteArray] = []
	for kind: StringName in _audio.KINDS:
		var stream := _audio.stream_for(kind) as AudioStreamWAV
		if stream == null:
			continue
		checks.expect(stream.stereo == false, "The '%s' sound is not mono." % String(kind))
		checks.expect(
			stream.format == AudioStreamWAV.FORMAT_16_BITS,
			"The '%s' sound is not 16-bit." % String(kind)
		)
		checks.expect(
			int(stream.mix_rate) == int(WorldAudioScript.SAMPLE_RATE),
			"The '%s' sound runs at %d Hz, not %d."
			% [String(kind), int(stream.mix_rate), int(WorldAudioScript.SAMPLE_RATE)]
		)
		var length := stream.get_length()
		checks.expect(
			length > 0.05 and length < 0.8,
			"The '%s' sound is %.3f s: these are touches, not events." % [String(kind), length]
		)
		var peak := _peak(stream)
		checks.expect(
			peak > 0.05 and peak < 0.5,
			"The '%s' sound peaks at %.3f: inaudible or louder than the room."
			% [String(kind), peak]
		)
		bodies.append(stream.data)
	var shared := ""
	for first in bodies.size():
		for second in range(first + 1, bodies.size()):
			if bodies[first] == bodies[second]:
				shared = " (kinds %d and %d)" % [first, second]
	checks.expect(
		shared.is_empty(),
		"Two world sounds share one buffer%s; each is meant to be its own sound." % shared
	)
	# The two sounds whose relationship the design states: a door is the long one.
	var door := _audio.stream_for(&"door") as AudioStreamWAV
	var paper := _audio.stream_for(&"paper") as AudioStreamWAV
	if door != null and paper != null:
		checks.expect(
			door.get_length() > paper.get_length() * 2.0,
			"The door (%.3f s) is not clearly longer than a page (%.3f s)."
			% [door.get_length(), paper.get_length()]
		)


## The split that justifies a second node: these reach the mixer, the cues do not.
func _check_bus() -> void:
	Harness.stage = "world audio bus"
	if _audio == null:
		return
	var world_players := 0
	for child in _audio.get_children():
		var player := child as AudioStreamPlayer
		if player == null:
			continue
		world_players += 1
		checks.expect(
			player.bus == &"SFX" or AudioServer.get_bus_index(&"SFX") == -1,
			"A world sound is on the '%s' bus; the sound-effects dial reaches these through SFX."
			% player.bus
		)
		checks.expect(
			player.volume_db <= -10.0 and player.volume_db > -30.0,
			"A world sound plays at %.1f dB: above the cues and under the room."
			% player.volume_db
		)
		checks.expect(player.stream != null, "A world-audio voice has no stream.")
	checks.expect(
		world_players == _audio.KINDS.size() * int(WorldAudioScript.VOICES_PER_KIND),
		"There are %d world-audio voices for %d kinds."
		% [world_players, _audio.KINDS.size()]
	)

	var cues := Harness.ensure_autoload(self, "CueAudio", "res://scripts/audio/cue_audio.gd")
	if cues != null:
		for child in cues.get_children():
			var cue_player := child as AudioStreamPlayer
			if cue_player == null:
				continue
			checks.expect(
				cue_player.bus == &"Master",
				"A pointer cue moved to the '%s' bus; the cues own no bus by design."
				% cue_player.bus
			)


## Every kind is limited against itself: the second play inside the interval is refused,
## and after the interval it is allowed again.
func _check_rate_limits() -> void:
	Harness.stage = "world audio rate limits"
	if _audio == null:
		return
	for kind: StringName in _audio.KINDS:
		_audio.reset_counts()
		var first: bool = _audio.play(kind)
		checks.expect(first, "The '%s' sound did not play at all." % String(kind))
		var second: bool = _audio.play(kind)
		checks.expect(
			not second,
			"The '%s' sound played twice inside its own interval; every kind is rate-limited."
			% String(kind)
		)
		checks.expect(
			_audio.get_play_count(kind) == 1,
			"The refused '%s' play was counted: the count is supposed to mean 'heard'."
			% String(kind)
		)
	# Measured, not assumed: the wait has to actually outlast the longest interval, and a
	# "wait" that returned early would test the refusal rather than its expiry.
	var longest := 0.0
	for kind: StringName in _audio.KINDS:
		longest = maxf(longest, float(WorldAudioScript.MIN_INTERVAL_SECONDS[kind]))
	var before := Time.get_ticks_msec()
	await create_timer(longest + 0.15).timeout
	var waited := Time.get_ticks_msec() - before
	checks.expect(
		waited >= int(longest * 1000.0),
		"The wait lasted only %d ms, under the %d ms longest interval."
		% [waited, int(longest * 1000.0)]
	)
	_audio.reset_counts()
	checks.expect(
		_audio.play(&"door"),
		"The door never came back after waiting %d ms for a %.2f s interval."
		% [waited, float(WorldAudioScript.MIN_INTERVAL_SECONDS[&"door"])]
	)


## Same kind, built twice, same bytes: the noise is seeded, not drawn from the global RNG.
func _check_determinism() -> void:
	Harness.stage = "world audio determinism"
	if _audio == null:
		return
	var second = WorldAudioScript.new()
	root.add_child(second)
	for kind: StringName in _audio.KINDS:
		var first_stream := _audio.stream_for(kind) as AudioStreamWAV
		var second_stream = second.stream_for(kind) as AudioStreamWAV
		if first_stream == null or second_stream == null:
			continue
		checks.expect(
			first_stream.data == second_stream.data,
			"The '%s' sound differs between two builds; the synthesis is not deterministic."
			% String(kind)
		)
	second.queue_free()


func _check_silence() -> void:
	Harness.stage = "world audio silence"
	if _audio == null:
		return
	_audio.reset_counts()
	_audio.set_silent(true)
	checks.expect(_audio.is_silent(), "set_silent(true) did not take.")
	checks.expect(not _audio.play(&"step"), "A muted world sound reported that it played.")
	checks.expect(
		_audio.get_total_plays() == 0,
		"A muted world sound was counted: the count is supposed to mean 'heard'."
	)
	_audio.set_silent(false)
	checks.expect(not _audio.is_silent(), "set_silent(false) did not take.")
	# The last interval may still be running from the rate-limit stage; reset first.
	_audio.reset_counts()
	checks.expect(_audio.play(&"paper"), "The world stayed silent after being unmuted.")


## The highest absolute sample in a buffer, 0..1. Reads the same 16-bit mono data the player
## does, so it measures what will be heard rather than what the generator intended.
func _peak(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var highest := 0
	var count := data.size() / 2
	for index in count:
		var value := absi(data.decode_s16(index * 2))
		if value > highest:
			highest = value
	return float(highest) / 32768.0
