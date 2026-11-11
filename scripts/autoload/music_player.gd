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

var _player: AudioStreamPlayer
var _tween: Tween
var _volume_db := DEFAULT_VOLUME_DB
var _bus: StringName = BUS_NAME
var _bus_missing_warned := false


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
