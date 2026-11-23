extends Node
## The one background-music player for the whole session. Scene/beat selection is
## owned by ScoreDirector; this node owns playback and the existing Music bus/dial.
## Score files are already mixed and looped: never fade or alter their level here.

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")

## The startup and ending tracks. Other score paths are chosen by ScoreDirector.
const TRACK_PATH := "res://assets/audio/music/score/01_classroom_wake.mp3"
const END_TRACK_PATH := "res://assets/audio/music/score/11_end_card.mp3"

## Bus the player is attached to. `default_bus_layout.tres` gives it a fixed -6 dB trim;
## the player's own `volume_db` is the independent music dial.
const BUS_NAME := &"Music"

## The existing music dial, unchanged: -6 dB on top of the -6 dB bus trim.
const DEFAULT_VOLUME_DB := -6.0

## The existing optional stop fade; score starts and loops do not fade.
const SILENT_DB := -60.0
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
		OfflineDiagnostics.note("assets.load_failed", {"kind": "music"})
		push_error("Music: '%s' could not be loaded; the background music is silent." % path)
		return false
	_kill_tween()
	# The score is stored as MP3. Set the stream loop explicitly, not a timer or
	# a fade: the decoder wraps at the stream boundary. The end card is one-shot.
	if stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		mp3.loop = path != END_TRACK_PATH
		mp3.loop_offset = 0.0
		# Godot's beat-synchronised MP3 loop applies a short crossfade internally.
		# Disable that path: these files use their full, pre-prepared boundaries.
		mp3.bpm = 0.0
		mp3.beat_count = 0
	_player.stream = stream
	_player.volume_db = _volume_db
	_player.play()
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
## quiet room may want the music louder — but `DEFAULT_VOLUME_DB` is what ships.
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


func _notification(what: int) -> void:
	# Freed, not merely taken out of the tree: a node moved between parents keeps playing.
	# The player child still exists here; it is freed after this node's notification.
	if what != NOTIFICATION_PREDELETE:
		return
	_kill_tween()
	if _player != null:
		# A player that has only left the tree (as at quit) has *paused* its playback, and
		# a paused playback is never deleted; stopping hands it to the server.
		_player.stop()
	if not AudioRelease.wait_for_mix():
		# Not an error the player can act on (the audio driver is not mixing), and not
		# hidden either: the engine's own leak warning follows, and this says why.
		print_verbose(
			"Music: no audio mix within %d ms of the stop; the playback may be reported as"
			% AudioRelease.TIMEOUT_MSEC
			+ " leaked at exit."
		)


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
