extends SceneTree
## Proves VoiceDirector resolves character speech clips and acoustic profiles.

const Harness = preload("res://tests/test_harness.gd")

var checks := Harness.Checker.new()


func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "voice_director_test.gd")
	call_deferred("_run")


func _run() -> void:
	_test_clip_path_resolution()
	_test_speaker_acoustic_profiles()
	_test_playback_lifecycle()

	Harness.finish(self, checks.failures, "VoiceDirector contracts verified.")


func _test_clip_path_resolution() -> void:
	# The naming rule, not the shipped files: an unvoiced line must resolve to nothing, and a
	# line with no clip must not invent one. What used to be asserted here - that four specific
	# files resolve - pinned the project to clips that said nothing (0.05 to 0.28 seconds
	# against two-second lines). Those are gone, and `voice_coverage_test.py` is what keeps a
	# clip honest now: it measures every shipped clip against the line it plays for.
	var missing_clip := VoiceDirector.resolve_clip_path(
		"zh-CN", &"unknown_conv", &"unknown_node", &""
	)
	checks.expect(
		missing_clip.is_empty(),
		"Unvoiced conversation returns empty clip path."
	)
	checks.expect(
		VoiceDirector.resolve_clip_path("zh-CN", &"", &"", &"").is_empty(),
		"A line with no conversation and no inspection resolves to nothing."
	)
	# A clip that is named for a conversation node is looked for at
	# `<conversation_id>_<node_id>`, so a name that only *looks* like one must not match.
	checks.expect(
		VoiceDirector.resolve_clip_path("zh-CN", &"q_wake", &"q_1", &"")
		== ""
		or ResourceLoader.exists(
			VoiceDirector.resolve_clip_path("zh-CN", &"q_wake", &"q_1", &"")
		),
		"Whatever a node resolves to, it exists on disk."
	)


func _test_speaker_acoustic_profiles() -> void:
	var profiles: Dictionary = VoiceDirector.SPEAKER_PROFILES
	checks.expect(
		profiles.has(&"protagonist"),
		"Protagonist acoustic profile is defined."
	)
	checks.expect(
		profiles.has(&"q"),
		"Q acoustic profile is defined."
	)
	checks.expect(
		profiles.has(&"n"),
		"N acoustic profile is defined."
	)

	var q_profile: Dictionary = profiles.get(&"q", {})
	checks.expect(
		float(q_profile.get("pitch_scale", 1.0)) > 1.0,
		"Q profile has slightly higher energetic pitch scale."
	)

	var p_profile: Dictionary = profiles.get(&"protagonist", {})
	checks.expect(
		float(p_profile.get("pitch_scale", 1.0)) <= 1.0,
		"Protagonist profile has grounded, introspective pitch scale."
	)


func _test_playback_lifecycle() -> void:
	# The playback path is exercised against a clip this test writes itself, in a directory it
	# owns. Nothing is asserted about shipped audio: the project ships none, by decision, and a
	# test that needed one to exist would be a test that argues with the decision.
	var scratch := "user://voice_director_test_clips"
	_write_fixture_clip(scratch + "/zh-CN/q_wake_q_1.wav")

	var director := VoiceDirector.new()
	# Set before it enters the tree, so the player and the fixture directory are both in place
	# by the time `_ready()` runs.
	director.voice_dir = scratch
	root.add_child(director)

	var voiced_line: Dictionary = {
		"locale": "zh-CN",
		"speaker_id": &"q",
		"conversation_id": &"q_wake",
		"node_id": &"q_1",
		"inspection_id": &"",
		"text": "你刚才睡得还挺好啊。",
	}

	var started := director.play_line_voice(voiced_line)
	checks.expect(started, "play_line_voice returns true for a clip that exists.")
	checks.expect(
		not director.get_active_clip_path().is_empty(),
		"director tracks the active clip path."
	)
	checks.expect(
		director.get_active_clip_path().ends_with("q_wake_q_1.wav"),
		"The resolved clip is not the one written for this line (%s)."
		% director.get_active_clip_path()
	)

	# An English line with no dub of its own falls back to the primary performance.
	var fallback_line: Dictionary = {
		"locale": "en",
		"speaker_id": &"q",
		"conversation_id": &"q_wake",
		"node_id": &"q_1",
		"inspection_id": &"",
		"text": "Enjoy your nap, did you?",
	}
	var fallback_started := director.play_line_voice(fallback_line)
	checks.expect(
		fallback_started,
		"play_line_voice falls back to the zh-CN clip when the locale is unvoiced."
	)

	director.stop_voice(false)
	checks.expect(
		director.get_active_clip_path().is_empty(),
		"stop_voice clears the active clip path."
	)

	var unvoiced_line: Dictionary = {
		"locale": "zh-CN",
		"speaker_id": &"q",
		"conversation_id": &"non_existent",
		"node_id": &"none",
		"inspection_id": &"",
		"text": "无音频测试行",
	}
	checks.expect(
		not director.play_line_voice(unvoiced_line),
		"play_line_voice returns false when no clip exists."
	)

	director.queue_free()
	_remove_fixture(scratch)


## A quarter second of a quiet tone: enough for the loader, short enough to be free.
func _write_fixture_clip(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var frames := PackedByteArray()
	var count := 22050 / 4
	frames.resize(count * 2)
	for index in count:
		frames.encode_s16(index * 2, int(sin(TAU * 440.0 * float(index) / 22050.0) * 8000.0))
	wav.data = frames
	wav.save_to_wav(path)


func _remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child in directory.get_directories():
		_remove_fixture(path + "/" + child)
	for file in directory.get_files():
		directory.remove(file)
	DirAccess.remove_absolute(path)
