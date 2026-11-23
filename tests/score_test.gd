extends SceneTree
## Music selection, stream looping and the end card. Run after import:
## godot --headless --path . --script res://tests/score_test.gd

const Harness := preload("res://tests/test_harness.gd")
const Score := preload("res://scripts/world/score_director.gd")
const DIR := "res://assets/audio/music/score/"
const FILES := [
	"01_classroom_wake.mp3", "02_dread_expectation.mp3", "03_corridor_walk.mp3",
	"04_street_load.mp3", "04b_street_pulse.mp3", "05_residential_fuzz.mp3",
	"05b_residential_heavy.mp3", "06_alley_dub.mp3", "07_yard_open.mp3",
	"07b_yard_thin.mp3", "08_imagined_lesson.mp3", "09_laboratory.mp3",
	"10_dream_annex.mp3", "11_end_card.mp3",
]
var _check := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "score_test.gd")
	call_deferred("_run")


func _run() -> void:
	var state := Harness.ensure_autoload(self, "GameState", "res://scripts/autoload/game_state.gd")
	var music := Harness.ensure_autoload(self, "Music", "res://scripts/autoload/music_player.gd")
	state.clear()
	var host := LocationHost.new()
	var room := LocationRoot.new()
	var player := Node3D.new()
	var score := Score.new()
	root.add_child(host)
	root.add_child(room)
	root.add_child(player)
	root.add_child(score)
	host._current = room
	room.location_id = &"classroom"
	score.setup(host, player, state, music)
	score.refresh()
	_expect_track(music, "01_classroom_wake.mp3")
	state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, false)
	state.set_flag(StoryFlags.MET_Q, true)
	_expect_track(music, "01_classroom_wake.mp3")
	state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)
	_expect_track(music, "02_dread_expectation.mp3")
	score.set_imagining(true)
	_expect_track(music, "08_imagined_lesson.mp3")
	score.set_imagining(false)
	_expect_track(music, "02_dread_expectation.mp3")
	state.set_flag(StoryFlags.BELL_RUNG, true)
	_expect_track(music, "01_classroom_wake.mp3")

	for id: StringName in Score.ROOM_TRACKS:
		if id == &"classroom":
			continue
		room.location_id = id
		host.location_entered.emit(room, &"")
		_expect_track(music, String(Score.ROOM_TRACKS[id]))
	room.location_id = &"corridor"
	player.position = Vector3(-35, -3.4, 13.4)
	score.refresh()
	_expect_track(music, "10_dream_annex.mp3")
	player.position = Vector3(-35, 0, 13.4)
	score.refresh()
	_expect_track(music, "03_corridor_walk.mp3")

	score.set_process(false) # Probe the files directly without the room selector replacing them.
	var voice: AudioStreamPlayer = music.get_player()
	for file: String in FILES:
		_check.expect(music.play_track(DIR + file) or music.get_track_path() == DIR + file,
			"could not start " + file)
		var stream := voice.stream as AudioStreamMP3
		_check.expect(stream != null, file + " is not an MP3 stream")
		if stream != null:
			_check.expect(stream.loop == (file != "11_end_card.mp3"), file + " loop setting")
			_check.expect(stream.loop_offset == 0.0 and stream.bpm == 0.0 				and stream.beat_count == 0, file + " beat loop or nonzero offset")
			_check.expect(is_equal_approx(voice.volume_db, music.get_volume_db()),
				file + " changes playback level")
			if file != "11_end_card.mp3":
				voice.seek(maxf(0.0, stream.get_length() - 0.15))
				var wrapped := await Harness.wait_until(func() -> bool:
					return voice.playing and voice.has_stream_playback() \
						and voice.get_stream_playback().get_loop_count() > 0, 3.0)
				_check.expect(wrapped, file + " did not wrap")
	# Ending must not restart at its natural end or after unrelated flag updates.
	score.show_ending()
	voice.seek(maxf(0.0, voice.stream.get_length() - 0.1))
	var ended := await Harness.wait_until(func() -> bool: return not voice.playing, 3.0)
	_check.expect(ended, "end card looped or did not end")
	state.set_flag(StoryFlags.TEXTBOOK_MISSING, true)
	score.refresh()
	await process_frame
	_check.expect(not voice.playing, "finished end card restarted")
	music.stop(true)
	score.free()
	player.free()
	room.free()
	host.free()
	state.clear()
	Harness.finish(self, _check.failures, "score selection, looping and ending")


func _expect_track(music: Node, file: String) -> void:
	_check.expect(music.get_track_path() == DIR + file,
		"expected " + file + ", got " + str(music.get_track_path()))
