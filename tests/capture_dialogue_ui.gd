extends SceneTree
## Captures the reading surface from a real window, at the sizes the game is played in.
##
## `capture_playthrough.gd` proves the slice can be walked; this script proves the text
## can be read. It boots the same `main.tscn`, drives the same `DialogueController`, and
## photographs the same panel showing real content — one frame per supported resolution
## and language through 4K, plus a real choice list, inspection, recollection and the log.
##
## Run it with a display (Xvfb in CI):
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_dialogue_ui.gd
##
## Frames land in `docs/screenshots/ui-*.png`, next to the playthrough's frames, so the
## evidence of a run is one folder.

const Harness = preload("res://tests/test_harness.gd")
const EvidenceContract = preload("res://tests/evidence_contract.gd")
const OUT_DIR := "res://docs/screenshots"
const LOG_PATH := "res://docs/screenshots/UI_CAPTURE.log"

## Frames also printed as small inline JPEGs (`CROP: <file> <base64>`), which the workflow
## publishes as annotations, so the composition can be seen from the run report without
## downloading the artifact. Small on purpose: an annotation holds about 4 KB.
const INLINE_FRAMES: Array[String] = [
	"ui-dialogue-1600x900-zh.png", "ui-choices-1600x900-zh.png", "ui-inspection-1600x900-zh.png"
]
const INLINE_SIZE := Vector2i(400, 225)

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var _failures: Array[String] = []
var _shots: Array[String] = []
var _main: Node = null
var _ui: GameUI = null
var _dialogue: DialogueController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "capture_dialogue_ui.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	# The game resumes from a save at boot (ADR 0005), and this script is a second run in
	# a job whose first run already made one: without this the capture would photograph
	# the end of the slice instead of the opening conversation. After the autoloads, so
	# the node that owns the file exists when it is asked to forget it.
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	loc.set_locale("en")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_finish(["main.tscn could not be loaded."])
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _frames(6)
	_ui = _main.get_node_or_null("GameUI") as GameUI
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	if _ui == null or _dialogue == null:
		_finish(["Main did not expose GameUI and DialogueController."])
		return

	Engine.time_scale = 4.0
	if not await _wait_for_line(90.0):
		_finish(["The opening conversation never showed a line."])
		return

	# --- the same line, two languages, five sizes through 4K -------------
	for size in RESOLUTIONS:
		await _resize(size)
		loc.set_locale("en")
		await _frames(4)
		await _opening_shot("ui-dialogue-%dx%d-en.png" % [size.x, size.y], size, "en")
		loc.set_locale("zh-CN")
		await _frames(4)
		await _opening_shot("ui-dialogue-%dx%d-zh.png" % [size.x, size.y], size, "zh-CN")

	# The same real line, on a controller: the hint should use the InputMap's A and Y
	# bindings, not retain the keyboard's Space and Tab after the display-size changes.
	await _resize(Vector2i(1600, 900))
	var settings := Harness.ensure_autoload(
		self, "Settings", "res://scripts/autoload/settings_manager.gd"
	)
	if settings == null:
		_failures.append("Settings could not be created for the controller hint capture.")
	else:
		settings.call("set_input_device", &"gamepad")
		await _frames(4)
		await _shot("ui-dialogue-1600x900-pad.png", Vector2i(1600, 900))
		settings.call("set_input_device", &"keyboard")

	# --- a real choice list ---------------------------------------------
	await _resize(Vector2i(1600, 900))
	await _settle(60.0)
	loc.set_locale("zh-CN")
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("The class conversation could not be started for the options frame.")
	else:
		var waited := 0
		while not _dialogue.has_pending_choices() and waited < 900:
			_dialogue.advance_presentation()
			await _frames(1)
			waited += 1
		if _dialogue.has_pending_choices():
			await _frames(4)
			await _shot("ui-choices-1600x900-zh.png", Vector2i(1600, 900))
		else:
			_failures.append("The class conversation never reached its choice.")
		await _settle(60.0)

	# --- a real inspection, then its recollection -----------------------
	loc.set_locale("zh-CN")
	if not _dialogue.present_inspection(&"classroom_set_square"):
		_failures.append("The set square inspection could not be presented.")
	else:
		await _frames(4)
		await _shot("ui-inspection-1600x900-zh.png", Vector2i(1600, 900))
		_dialogue.advance_presentation()
		await _frames(4)
		await _shot("ui-recall-1600x900-zh.png", Vector2i(1600, 900))
		await _settle(30.0)

	# --- the log ---------------------------------------------------------
	loc.set_locale("en")
	if _ui.backlog != null:
		_ui.backlog.open()
		await _frames(5)
		await _shot("ui-log-1600x900-en.png", Vector2i(1600, 900))
		_ui.backlog.close()
		await _frames(3)

	Engine.time_scale = 1.0
	if _shots.is_empty():
		_failures.append("No frame was written.")
	_finish(_failures)


# --- helpers -----------------------------------------------------------------


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(6)


## A frame of the opening line (#186). These are the frames the repository keeps as the
## picture of the reading band, so before one is written the panel has to be drawing the
## authored sentence of the opening's first node in `locale`; afterwards the frame's
## `EVIDENCE` record is printed for the relay workflow and `MANIFEST.json`.
func _opening_shot(name: String, size: Vector2i, locale: String) -> void:
	# Half a sentence is not the sentence: wait for the reveal (a language switch can
	# start it again) rather than photograph the line cut off.
	var waited := 0
	while _ui.dialogue_panel.is_revealing() and waited < 600:
		await _frames(1)
		waited += 1
	var problem := EvidenceContract.compare_panel(
		_ui.dialogue_panel, _dialogue, locale,
		EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
	)
	if not problem.is_empty():
		_failures.append("%s does not show the authored opening line: %s" % [name, problem])
		return
	var before := _shots.size()
	await _shot(name, size)
	if _shots.size() == before:
		return
	print(EvidenceContract.evidence_line(EvidenceContract.evidence_record(
		name, size, locale, EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
	)))


func _shot(name: String, size: Vector2i) -> void:
	var report := _ui.dialogue_panel.get_layout_report()
	var path := "%s/%s" % [OUT_DIR, name]
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("The %s frame came back empty." % name)
		return
	var error := image.save_png(path)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [path, error])
		return
	_shots.append(name)
	EvidenceContract.write_jpeg_copy(image, path)
	if INLINE_FRAMES.has(name):
		var small := image.duplicate() as Image
		small.convert(Image.FORMAT_RGB8)
		small.resize(INLINE_SIZE.x, INLINE_SIZE.y, Image.INTERPOLATE_BILINEAR)
		print("CROP: %s %s" % [
			name.get_basename() + ".jpg", Marshalls.raw_to_base64(small.save_jpg_to_buffer(0.6))
		])
	print(
		"SHOT %s  %dx%d  band %.0f%%x%.0f%%  body %dpx  scrolling=%s"
		% [
			name,
			image.get_width(),
			image.get_height(),
			float(report.get("covers_width", 0.0)) * 100.0,
			float(report.get("covers_height", 0.0)) * 100.0,
			int(report.get("body_font_size", 0)),
			str(report.get("body_scrolling", false)),
		]
	)
	# The frame must be the size that was asked for, or the evidence is of another
	# resolution than its filename claims.
	if image.get_width() != size.x or image.get_height() != size.y:
		_failures.append(
			"%s is %dx%d, not %dx%d." % [name, image.get_width(), image.get_height(), size.x, size.y]
		)


func _wait_for_line(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if _dialogue.is_busy() and not String(_dialogue.get_current_line().get("text", "")).is_empty():
			return true
		await _frames(1)
	return false


func _settle(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if not _dialogue.is_busy():
			return true
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(1)
	return false


func _finish(failures: Array) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		for name in _shots:
			file.store_line("SHOT: %s" % name)
		for failure in failures:
			file.store_line("FAILURE: %s" % failure)
		if failures.is_empty():
			file.store_line("RESULT: %d dialogue frames captured." % _shots.size())
		file.close()
	if failures.is_empty():
		print("PASS: captured %d dialogue frames." % _shots.size())
		quit(0)
		return
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
