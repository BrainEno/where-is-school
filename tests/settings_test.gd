extends SceneTree
## Unit tests for Settings persistence (headless).

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var settings_script: GDScript = load("res://scripts/autoload/settings.gd") as GDScript
	var tmp_path: String = "user://settings_test_tmp.cfg"
	var absolute_tmp: String = ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(absolute_tmp):
		DirAccess.remove_absolute(absolute_tmp)

	var a: Node = settings_script.new()
	a.save_path = tmp_path
	a.text_speed = "normal"
	a.text_scale = "normal"
	a.set_text_speed("fast")
	a.set_text_scale("large")
	a.free()

	var b: Node = settings_script.new()
	b.save_path = tmp_path
	b.load_settings()
	if b.text_speed != "fast":
		failures.append("text_speed not persisted (got '%s')" % b.text_speed)
	if b.text_scale != "large":
		failures.append("text_scale not persisted (got '%s')" % b.text_scale)
	if not is_equal_approx(b.typewriter_cps(), 140.0):
		failures.append("typewriter_cps mismatch for fast")
	if not is_equal_approx(b.font_scale(), 1.25):
		failures.append("font_scale mismatch for large")

	# --- invalid values are rejected, current value preserved
	b.set_text_speed("ludicrous")
	b.set_text_scale("enormous")
	if b.text_speed != "fast" or b.text_scale != "large":
		failures.append("invalid values were accepted")

	# --- unknown values in the config file are ignored
	b.save_path = tmp_path
	var config := ConfigFile.new()
	config.set_value("accessibility", "text_speed", "warp")
	config.set_value("accessibility", "text_scale", "giant")
	config.save(tmp_path)
	b.load_settings()
	if b.text_speed != "normal" or b.text_scale != "normal":
		failures.append("corrupt config values were accepted")
	b.free()

	if FileAccess.file_exists(absolute_tmp):
		DirAccess.remove_absolute(absolute_tmp)

	if not failures.is_empty():
		for failure in failures:
			push_error("settings_test failed: %s" % failure)
		quit(1)
		return
	print("settings_test passed")
	quit(0)
