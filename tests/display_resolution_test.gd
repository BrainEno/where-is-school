extends SceneTree
## Exercises the display scaling contract at the five required 16:9 sizes.
##
## This headless test verifies the same uniform CanvasItem scale the window uses, the
## resulting logical canvas size, font density and expand aspect policy. Physical monitor
## mode switching is covered by display_mode_test.gd; pixel screenshots require a desktop
## renderer and are captured separately by the playtest checklist.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SettingsScript = preload("res://scripts/autoload/settings_manager.gd")
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const EXPECTED_AUTO_SCALES: Array[float] = [1.0, 1.0, 1.0, 1.25, 2.0]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "display_resolution_test.gd")
	call_deferred("_run")


func _run() -> void:
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if settings == null:
		Harness.finish(self, ["Settings autoload could not be created."], "")
		return
	var original_size := Vector2i(root.size)
	var original_scale := StringName(settings.call("get_ui_scale"))
	settings.call("set_ui_scale", &"auto")

	for index in RESOLUTIONS.size():
		var size := RESOLUTIONS[index]
		Harness.stage = "resolution %dx%d" % [size.x, size.y]
		root.size = size
		await process_frame
		await process_frame
		var scale := float(settings.call("get_applied_ui_scale"))
		_expect(
			is_equal_approx(scale, EXPECTED_AUTO_SCALES[index]),
			"Auto UI scale at %s is %.2f, expected %.2f."
			% [str(size), scale, EXPECTED_AUTO_SCALES[index]]
		)
		_expect(
			is_equal_approx(UiTextScale.scaled(20, scale), 20.0 * scale),
			"A 20 px UI font is not uniformly scaled at %s." % str(size)
		)
		if scale > 1.0:
			var logical := Vector2i(roundi(size.x / scale), roundi(size.y / scale))
			_expect(
				root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
				"The %s window is not using CanvasItem-only scaling." % str(size)
			)
			_expect(
				root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,
				"The %s canvas is not set to expand without stretching." % str(size)
			)
			_expect(
				root.content_scale_size == logical,
				"The logical canvas at %s is %s, expected %s."
				% [str(size), str(root.content_scale_size), str(logical)]
			)
		# Input coordinates use the same uniform canvas transform as controls; the scale
		# contract must not introduce separate horizontal and vertical factors.
		var logical_size := (
			root.content_scale_size
			if root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			else size
		)
		var x_scale := float(size.x) / float(logical_size.x)
		var y_scale := float(size.y) / float(logical_size.y)
		_expect(
			absf(x_scale - y_scale) < 0.002,
			"The UI would stretch at %s (x %.3f, y %.3f)." % [str(size), x_scale, y_scale]
		)

	# Manual UI size is honored only while the smallest verified logical canvas remains
	# available. At 1080p, 200% is capped to 150%, rather than shrinking layout space below
	# 1280x720; at 4K the same choice can use the full 200%.
	var manual_1080 := SettingsScript.effective_ui_scale(Vector2(1920, 1080), &"200")
	var manual_4k := SettingsScript.effective_ui_scale(Vector2(3840, 2160), &"200")
	_expect(is_equal_approx(manual_1080, 1.5), "Manual UI scale at 1080p is %.2f, not 1.5." % manual_1080)
	_expect(is_equal_approx(manual_4k, 2.0), "Manual UI scale at 4K is %.2f, not 2.0." % manual_4k)

	settings.call("set_ui_scale", original_scale)
	root.size = original_size
	await process_frame
	Harness.finish(
		self,
		_failures,
		"1280x720 through 3840x2160 use uniform UI scale, readable font density, "
		+ "an expanded non-stretched canvas, and a 1280x720 minimum logical area."
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
