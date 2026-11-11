extends SceneTree
## The background music: the imported loop, the one player that owns it, and the dial.
##
## A headless run has no speakers, and this is not a listening test. What it pins down is
## everything that can regress silently around a music bed:
##
## 1. the WAV is imported *as a loop* — `edit/loop_mode=2` with explicit loop points in the
##    `.import` sidecar, and the loaded stream carries those points. A script that sets
##    `loop_mode` at runtime would leave this failing, which is the point: the requirement is
##    an import setting, not a boolean in a `_ready()`;
## 2. the stream is the recording's own format — 48 kHz, mono, not resampled, not downmixed;
## 3. one player exists, it is the autoload's, and it starts itself once;
## 4. `play_track()` asked for the track that is already playing does not restart it, and a
##    scene change does not restart it either (that is why the player is an autoload);
## 5. the music sits on its own `Music` bus, so its dial moves the guitar and nothing else —
##    the interaction cues stay on `Master` at their own levels;
## 6. the default level is a bed: at least 10 dB below the bus's own trim;
## 7. `stop()` stops and `play_track()` starts again, and seeking past the loop end wraps
##    instead of falling silent.
##
## What it cannot check: whether the loop *sounds* seamless, or how loud the guitar actually
## is in the mix. The seam is measured by `tools/build_music_loop.py` (the step across the
## loop point is -72 dBFS, i.e. 8 LSB of 16-bit), and both are ears-only checks listed in the
## pull request.

const Harness = preload("res://tests/test_harness.gd")
const MusicScript := preload("res://scripts/autoload/music_player.gd")
const CueAudioScript := preload("res://scripts/audio/cue_audio.gd")

const TRACK_PATH := "res://assets/audio/music/guitar_ambient_loop_01.wav"
const TRACK_SIDECAR := "res://assets/audio/music/guitar_ambient_loop_01.wav.import"
const BUS_NAME := &"Music"
const SAMPLE_RATE := 48000

## 46.343 s: the take is 46.738 s, minus 0.59 s of dead air trimmed at the head.
const LENGTH_TOLERANCE := 0.05

const TIMEOUT_SECONDS := 120.0

var _failures: Array[String] = []
var _checks: int = 0
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "music_test.gd")
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	_check_import_settings()
	await _check_stream()
	await _check_bus()
	await _check_single_player()
	await _check_scene_change()
	await _check_volume_is_independent()
	await _check_loop_wraps()
	await _check_stop_and_restart()
	_report()


# --- 1. the loop is an import setting ---------------------------------------------


func _check_import_settings() -> void:
	var sidecar := FileAccess.get_file_as_string(TRACK_SIDECAR)
	if sidecar.is_empty():
		_fail("the sidecar %s is missing or empty" % TRACK_SIDECAR)
		return
	_expect("edit/loop_mode=2" in sidecar, "the import does not ask for a forward loop")
	_expect("edit/loop_begin=0" in sidecar, "the loop does not begin at the first sample")
	var loop_end := _sidecar_int(sidecar, "edit/loop_end")
	if loop_end <= 0:
		_fail("the import has no loop end (found %d)" % loop_end)
	else:
		_checks += 1
		_notes.append("import loop: 0..%d samples" % loop_end)
	_expect("compress/mode=2" in sidecar, "the loop is not the compressed WAV the budget allows")
	_expect("edit/trim=false" in sidecar, "the import is trimming on its own; the tool decides")
	_expect("edit/normalize=false" in sidecar, "the import is normalising the recording")


func _check_stream() -> void:
	if not ResourceLoader.exists(TRACK_PATH):
		_fail("%s does not exist" % TRACK_PATH)
		return
	var stream := load(TRACK_PATH) as AudioStreamWAV
	if stream == null:
		_fail("%s did not import as an AudioStreamWAV" % TRACK_PATH)
		return
	await process_frame

	_expect(
		stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"the imported stream is not a forward loop (mode %d)" % stream.loop_mode
	)
	_expect(stream.loop_begin == 0, "the imported loop begins at %d" % stream.loop_begin)
	# QOA decodes in 20-sample slices, so `get_length()` may round up by a slice; anything
	# further than that short of the end would be a loop that stops early.
	var frames := int(round(stream.get_length() * float(stream.mix_rate)))
	_expect(
		stream.loop_end >= frames - 128,
		"the imported loop ends at %d of this stream's %d samples, so it would play once "
		% [stream.loop_end, frames]
		+ "and then stop"
	)
	_expect(stream.mix_rate == SAMPLE_RATE, "the loop was resampled to %d Hz" % stream.mix_rate)
	_expect(not stream.stereo, "the mono recording was made stereo")
	_expect(
		absf(stream.get_length() - 46.343) <= LENGTH_TOLERANCE,
		"the loop is %.3f s, not the 46.343 s the build tool writes" % stream.get_length()
	)
	_notes.append(
		"stream: %.3f s, %d Hz, %s, %d samples of loop"
		% [
			stream.get_length(),
			stream.mix_rate,
			"mono" if not stream.stereo else "stereo",
			stream.loop_end,
		]
	)


# --- 2. one player, on its own bus -------------------------------------------------


func _check_bus() -> void:
	_expect(
		AudioServer.get_bus_index(BUS_NAME) != -1,
		"no '%s' bus: default_bus_layout.tres did not load" % String(BUS_NAME)
	)
	var music := Harness.ensure_autoload(self, "Music", "res://scripts/autoload/music_player.gd")
	if music == null:
		_fail("the Music autoload could not be created")
		return
	await process_frame
	_checks += 1
	_expect(
		StringName(music.get_bus_name()) == BUS_NAME,
		"the music plays on '%s', not its own bus" % String(music.get_bus_name())
	)
	var bus_index := AudioServer.get_bus_index(BUS_NAME)
	if bus_index != -1:
		var bus_db := AudioServer.get_bus_volume_db(bus_index)
		_expect(bus_db <= 0.0, "the '%s' bus is boosted to %.1f dB" % [String(BUS_NAME), bus_db])
		var total := bus_db + float(music.get_volume_db())
		_expect(
			total <= -10.0,
			"the music plays at %.1f dB against full scale, which is not a bed" % total
		)


func _check_single_player() -> void:
	var music := root.get_node_or_null(^"Music")
	if music == null:
		_fail("the Music autoload is not in the tree")
		return
	var players := _audio_players(music)
	_expect(players.size() == 1, "the music node owns %d players, not 1" % players.size())
	if players.is_empty():
		return
	var player: AudioStreamPlayer = players[0]
	_expect(player.playing, "the music did not start itself")
	_expect(
		String(music.get_track_path()) == TRACK_PATH,
		"the player holds '%s'" % String(music.get_track_path())
	)
	_expect(player.stream.resource_path == TRACK_PATH, "the player holds another stream")

	# Asking for the track that is already playing must not restart it.
	var before := player.get_playback_position()
	var restarted := bool(music.play_track())
	await _wait(0.25)
	var after := player.get_playback_position()
	_expect(not restarted, "play_track() reported a restart of the track already playing")
	_expect(
		after > before or after < 0.05,
		"the position did not advance (%.3f -> %.3f), so playback is stalled"
		% [before, after]
	)
	_expect(_audio_players(music).size() == 1, "a second play_track() added a second player")


# --- 3. a scene change does not restart it -----------------------------------------


func _check_scene_change() -> void:
	var music := root.get_node_or_null(^"Music")
	if music == null:
		_fail("the Music autoload disappeared before the scene change")
		return
	var player: AudioStreamPlayer = music.get_player()
	var before := player.get_playback_position()
	var packed := PackedScene.new()
	var scene := Node3D.new()
	scene.name = "MusicSceneChangeProbe"
	var error := packed.pack(scene)
	scene.free()
	if error != OK:
		_fail("could not build the probe scene (error %d)" % error)
		return
	if change_scene_to_packed(packed) != OK:
		_fail("could not change scene to the probe")
		return
	await _wait(0.35)
	_expect(
		root.get_node_or_null(^"Music") == music,
		"the scene change replaced the music node"
	)
	_expect(player.playing, "the scene change stopped the music")
	var after := player.get_playback_position()
	_expect(
		after >= before or after < 0.05,
		"the scene change restarted the track (%.3f -> %.3f)" % [before, after]
	)
	_expect(
		not _audio_players(music).is_empty() and _audio_players(music).size() == 1,
		"the scene change left %d music players" % _audio_players(music).size()
	)
	_checks += 1


# --- 4. the dial moves the music and nothing else ----------------------------------


func _check_volume_is_independent() -> void:
	var music := root.get_node_or_null(^"Music")
	var cues := Harness.ensure_autoload(self, "CueAudio", "res://scripts/audio/cue_audio.gd")
	if music == null or cues == null:
		_fail("the music or the cue audio node is missing")
		return
	var player: AudioStreamPlayer = music.get_player()
	var bus_index := AudioServer.get_bus_index(BUS_NAME)
	var bus_before := AudioServer.get_bus_volume_db(bus_index) if bus_index != -1 else 0.0
	var cue_before := _cue_volumes(cues)

	music.set_volume_db(-30.0)
	await process_frame
	_expect(
		is_equal_approx(player.volume_db, -30.0),
		"set_volume_db(-30) left the player at %.1f dB" % player.volume_db
	)
	if bus_index != -1:
		_expect(
			is_equal_approx(AudioServer.get_bus_volume_db(bus_index), bus_before),
			"turning the music down moved the '%s' bus as well" % String(BUS_NAME)
		)
	_expect(
		_cue_volumes(cues) == cue_before,
		"turning the music down changed the cue volumes (%s -> %s)"
		% [str(cue_before), str(_cue_volumes(cues))]
	)
	for voice: AudioStreamPlayer in _audio_players(cues):
		_expect(
			voice.bus == &"Master",
			"a cue is on '%s'; the music's bus cannot be theirs" % String(voice.bus)
		)
	music.set_volume_db(MusicScript.DEFAULT_VOLUME_DB)
	await process_frame
	_checks += 1


# --- 5. the loop wraps, and stop() / play() behave ---------------------------------


func _check_loop_wraps() -> void:
	var music := root.get_node_or_null(^"Music")
	if music == null:
		_fail("the Music autoload is missing for the loop check")
		return
	var player: AudioStreamPlayer = music.get_player()
	var length := float(music.get_track_length())
	_expect(length > 40.0, "the track is only %.2f s long" % length)
	player.seek(maxf(length - 0.3, 0.0))
	await _wait(0.9)
	_expect(player.playing, "the music stopped at the end of the loop instead of wrapping")
	var position := player.get_playback_position()
	_expect(
		position < length * 0.5,
		"the position is %.3f s past a wrap at %.3f s" % [position, length]
	)
	_notes.append("wrap: seek to %.2f s, then position %.3f s and still playing" % [length - 0.3, position])


func _check_stop_and_restart() -> void:
	var music := root.get_node_or_null(^"Music")
	if music == null:
		_fail("the Music autoload is missing for the stop check")
		return
	var player: AudioStreamPlayer = music.get_player()
	music.stop(true)
	await process_frame
	_expect(not player.playing, "stop(true) left the music playing")
	_expect(not bool(music.is_playing()), "is_playing() says the music is playing after a stop")
	_expect(bool(music.play_track()), "play_track() did not start the music after a stop")
	await process_frame
	_expect(player.playing, "the music did not resume after a stop")
	_expect(_audio_players(music).size() == 1, "restarting added a player")
	_checks += 1


# --- helpers -----------------------------------------------------------------------


func _sidecar_int(sidecar: String, key: String) -> int:
	for line in sidecar.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with(key + "="):
			return int(trimmed.substr(key.length() + 1))
	return -1


func _audio_players(node: Node) -> Array[AudioStreamPlayer]:
	var found: Array[AudioStreamPlayer] = []
	for child in node.get_children():
		var player := child as AudioStreamPlayer
		if player != null:
			found.append(player)
	return found


func _cue_volumes(cues: Node) -> Array[float]:
	var volumes: Array[float] = []
	for voice: AudioStreamPlayer in _audio_players(cues):
		volumes.append(voice.volume_db)
	return volumes


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	print("::notice title=music::%s" % "|".join(_notes))
	Harness.finish(
		self,
		_failures,
		"%d check(s): the recording imports as a loop, one player survives a scene change, "
		% _checks
		+ "the music dial moves nothing else, and the loop wraps."
	)
