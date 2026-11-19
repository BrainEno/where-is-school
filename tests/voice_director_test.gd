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
	# 1. Inspection voice clip resolution (schoolbag)
	var bag_clip := VoiceDirector.resolve_clip_path(
		"zh-CN", &"", &"", &"classroom_schoolbag"
	)
	checks.expect(
		not bag_clip.is_empty(),
		"VoiceDirector resolves inspection voice clip for classroom_schoolbag."
	)
	checks.expect(
		ResourceLoader.exists(bag_clip),
		"Resolved inspection clip exists on disk: %s" % bag_clip
	)

	# 2. Q conversation node resolution (q_wake / q_1)
	var q_clip := VoiceDirector.resolve_clip_path(
		"zh-CN", &"q_wake", &"q_1", &""
	)
	checks.expect(
		not q_clip.is_empty(),
		"VoiceDirector resolves Q conversation voice clip for q_wake/q_1."
	)
	checks.expect(
		ResourceLoader.exists(q_clip),
		"Resolved Q conversation clip exists on disk: %s" % q_clip
	)

	# 3. N conversation node resolution (n_class / n_1)
	var n_clip := VoiceDirector.resolve_clip_path(
		"zh-CN", &"n_class", &"n_1", &""
	)
	checks.expect(
		not n_clip.is_empty(),
		"VoiceDirector resolves N conversation voice clip for n_class/n_1."
	)
	checks.expect(
		ResourceLoader.exists(n_clip),
		"Resolved N conversation clip exists on disk: %s" % n_clip
	)

	# 4. Unvoiced line resolution
	var missing_clip := VoiceDirector.resolve_clip_path(
		"zh-CN", &"unknown_conv", &"unknown_node", &""
	)
	checks.expect(
		missing_clip.is_empty(),
		"Unvoiced conversation returns empty clip path."
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
	var director := VoiceDirector.new()
	root.add_child(director)

	var voiced_line: Dictionary = {
		"speaker_id": &"q",
		"conversation_id": &"q_wake",
		"node_id": &"q_1",
		"inspection_id": &"",
		"text": "你刚才睡得还挺好啊。",
	}

	var started := director.play_line_voice(voiced_line)
	checks.expect(started, "play_line_voice returns true for existing clip.")
	checks.expect(
		not director.get_active_clip_path().is_empty(),
		"director tracks active clip path."
	)

	director.stop_voice(false)
	checks.expect(
		director.get_active_clip_path().is_empty(),
		"stop_voice clears active clip path."
	)

	var unvoiced_line: Dictionary = {
		"speaker_id": &"q",
		"conversation_id": &"non_existent",
		"node_id": &"none",
		"inspection_id": &"",
		"text": "无音频测试行",
	}
	var unvoiced_started := director.play_line_voice(unvoiced_line)
	checks.expect(
		not unvoiced_started,
		"play_line_voice returns false when no clip exists."
	)

	director.queue_free()
