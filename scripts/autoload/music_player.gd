extends Node
## The game's background music: one loop, one player, owned by the scene tree's root.
##
## The track is a real recording — `art/audio/Guitar_loop_01.wav`, trimmed and crossfaded by
## `tools/build_music_loop.py` into `assets/audio/music/guitar_ambient_loop_01.wav`. It is
## imported *as a loop*: `edit/loop_mode=2` with explicit loop points in the `.import`
## sidecar, so the stream that loads here already repeats. Nothing in this script duplicates
## the WAV, sets `loop_mode` at runtime or otherwise pretends: a missing import setting would
## show up as music that stops after 46 seconds, which `tests/music_test.gd` fails on.
##
## Why an autoload and not a node in each location: the music has to survive a scene change.
## A player inside `classroom.tscn` restarts with the room, so walking to the corridor would
## restart the take — and two rooms' players would overlap for a frame. As an autoload the
## player exists once, for the whole session, and `play_track()` refuses to restart what is
## already playing.
##
## It cannot drown anything out, and it cannot be turned down by accident along with the
## rest: the player sits on its own `Music` bus (`default_bus_layout.tres`), so
## `set_volume_db()` moves the music and leaves `CueAudio`'s cues on `Master` where they are.
## The default level is deliberately below the room tone's own peak: a bed, not a scene.
##
## Loaded as the `Music` autoload. Callers look it up by path (`/root/Music`) or use the
## `Music` global, exactly as they do with `CueAudio`.
##
## It also lets go of the track when the game quits (#67). Stopping a player only marks its
## playback for removal: the audio thread takes it off the server's list on its next mix,
## a few tens of milliseconds later, and the main thread frees it at its next audio update
## (or when the audio server is destroyed). On quit the engine frees the scene tree and
## then stops the audio driver (`AudioServer::finish()`) without that mix having run, so a
## track still playing at quit outlived everything: every run, the game's and each
## headless check's, ended with "2 ObjectDB instances were leaked"
## (`AudioStreamPlaybackWAV` and this `AudioStreamWAV`) and "1 resources still in use"
## naming this file. When this node is freed it stops the music and waits, bounded by
## `RELEASE_TIMEOUT_MSEC`, for one mix to run after the stop, so the leak is removed at its
## source instead of filtered out of the log.

## The one track. A `res://` path, so no machine's absolute path can leak into a build.
const TRACK_PATH := "res://assets/audio/music/guitar_ambient_loop_01.wav"

## Bus the player is attached to. `default_bus_layout.tres` defines it and trims it by
## `BUS_TRIM_DB`; the player's own `volume_db` is the independent music dial.
const BUS_NAME := &"Music"

## Where the music dial starts, on top of the bus trim: about -18 dB against full scale for
## a recording whose peak is already -8.7 dBFS. Quiet enough to talk over, loud enough to
## hear the guitar.
const DEFAULT_VOLUME_DB := -12.0

## Floor the fade-in starts from, and the fade lengths.
const SILENT_DB := -60.0
const FADE_IN_SECONDS := 3.0
const FADE_OUT_SECONDS := 1.2

## The longest quitting waits for the audio thread to mix once more. One mix is about 23 ms
## at the dummy driver's 1024 frames / 44.1 kHz; a real driver's buffer is similar.
const RELEASE_TIMEOUT_MSEC := 250
const RELEASE_POLL_MSEC := 2

var _player: AudioStreamPlayer
var _tween: Tween
var _volume_db := DEFAULT_VOLUME_DB
var _bus: StringName = BUS_NAME
var _bus_missing_warned := false
## A weak reference to every playback `play_track()` started that may still be alive. Weak,
## so watching a playback never keeps it alive; pruned on each start.
var _playbacks: Array[WeakRef] = []


func _ready() -> void:
	# Music is not gameplay: it keeps playing while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	play_track(TRACK_PATH)


## The player this node owns. Public so a test can measure what is actually playing —
## bus, volume, stream, position — without going through a second player.
func get_player() -> AudioStreamPlayer:
	_build()
	return _player


## The bus the music is on. `Master` only if the bus layout did not load, which is a
## configuration mistake rather than a choice.
func get_bus_name() -> StringName:
	_build()
	return _bus


## Starts the track, or does nothing if it is already the track that is playing.
## Returns whether playback was started, so a caller can tell "began" from "already on".
func play_track(path: String = TRACK_PATH) -> bool:
	_build()
	if _player.playing and _player.stream != null and _player.stream.resource_path == path:
		return false
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("Music: '%s' could not be loaded; the background music is silent." % path)
		return false
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_watch_playback()
	_fade_to(_volume_db, FADE_IN_SECONDS)
	return true


## Stops the music, fading out unless `immediately` is set. The player stays in the tree and
## its stream stays loaded, so starting it again costs nothing.
func stop(immediately: bool = false) -> void:
	_build()
	if not _player.playing:
		return
	if immediately:
		_kill_tween()
		_player.stop()
		_player.volume_db = _volume_db
		return
	_fade_to(SILENT_DB, FADE_OUT_SECONDS)
	var stopped := func() -> void:
		_player.stop()
		_player.volume_db = _volume_db
	if _tween != null:
		_tween.tween_callback(stopped)


func is_playing() -> bool:
	_build()
	return _player.playing


## The music dial, independent of every other sound in the game: 0.0 dB is the recording at
## its own level, negative is quieter. Values above the default are allowed — a player in a
## quiet room may want the guitar louder — but `DEFAULT_VOLUME_DB` is what ships.
func set_volume_db(db: float) -> void:
	_build()
	_volume_db = db
	if _player.playing:
		_kill_tween()
		_player.volume_db = db


func get_volume_db() -> float:
	return _volume_db


## The track the player is holding, or "" before the first `play_track()`.
func get_track_path() -> String:
	_build()
	return _player.stream.resource_path if _player.stream != null else ""


## Length of the track in seconds, read off the imported stream.
func get_track_length() -> float:
	_build()
	return _player.stream.get_length() if _player.stream != null else 0.0


## Stops the music at once and waits, at most `timeout_msec` and on the calling thread, until
## the audio thread has mixed once since the stop. That mix takes every stopped playback
## off the audio server's list; the main thread then frees them at its next audio update,
## or, at quit, when the audio server is destroyed - before the engine counts leaked
## objects. Returns whether that mix was seen (`true` too when nothing was playing).
## Freeing this node calls it, so a quit cannot leave the track to the engine's shutdown.
##
## The playbacks themselves cannot be watched to the end from here: the server holds them
## until the main thread's own cleanup, which cannot run while this waits on it.
func release_playbacks(timeout_msec: int = RELEASE_TIMEOUT_MSEC) -> bool:
	_kill_tween()
	if _player != null:
		# `seek()` and a caller's own `play()` start playbacks `play_track()` never saw, so
		# what the player holds now is watched too. Then stop, which hands each playback to
		# the audio server for deletion; a player that has only left the tree has *paused*
		# its playback, and a paused one is never deleted.
		_watch_playback()
		_player.stop()
	if held_playbacks() == 0:
		_playbacks.clear()
		return true
	var stopped_usec := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + maxi(timeout_msec, 0)
	while not _mixed_since(stopped_usec):
		if Time.get_ticks_msec() >= deadline:
			return false
		OS.delay_msec(RELEASE_POLL_MSEC)
	return true


## How many playbacks started here are still alive: playing, fading, or waiting for the
## audio thread or the main thread's cleanup.
func held_playbacks() -> int:
	var held := 0
	for watch: WeakRef in _playbacks:
		if watch.get_ref() != null:
			held += 1
	return held


func _notification(what: int) -> void:
	# Freed, not merely taken out of the tree: a node moved between parents keeps playing.
	# The player child still exists here; it is freed after this node's notification.
	if what == NOTIFICATION_PREDELETE and not release_playbacks():
		# Not an error the player can act on (no mix in the time allowed: the audio driver
		# is not running), and not hidden either: the engine's own leak warning follows,
		# and this says where it comes from.
		print_verbose(
			"Music: the audio thread did not mix within %d ms of the stop; the playback may"
			% RELEASE_TIMEOUT_MSEC
			+ " be reported as leaked at exit."
		)


## Whether a mix has started since `usec` (`Time.get_ticks_usec()`) and finished. The driver
## stamps the start of each mix under its lock, and reading the stamp takes the same lock,
## so a mix in progress ends before this returns; `now` is read first, which can only make
## the stamp look earlier than it was, never later.
static func _mixed_since(usec: int) -> bool:
	var now := Time.get_ticks_usec()
	var since := AudioServer.get_time_since_last_mix()
	return now - int(since * 1000000.0) > usec


func _watch_playback() -> void:
	var alive: Array[WeakRef] = []
	var current: AudioStreamPlayback = null
	if _player.has_stream_playback():
		current = _player.get_stream_playback()
	for watch: WeakRef in _playbacks:
		var playback: Variant = watch.get_ref()
		if playback != null and playback != current:
			alive.append(watch)
	if current != null:
		var watch: WeakRef = weakref(current)
		alive.append(watch)
	_playbacks = alive


func _build() -> void:
	if _player != null:
		return
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index == -1:
		_bus = &"Master"
		if not _bus_missing_warned:
			_bus_missing_warned = true
			push_warning(
				"Music: no '%s' bus; playing on Master. default_bus_layout.tres did not load."
				% String(BUS_NAME)
			)
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = _bus
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)


func _fade_to(db: float, seconds: float) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, seconds)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
