extends SceneTree
## Photographs the dialogue identity block (#167): the small portrait that leads the
## speaker's name, in the real game window over the real classroom.
##
## `capture_dialogue_ui.gd` photographs whatever the opening conversation happens to show;
## this script puts chosen lines on the same panel so every case the issue asks to see is
## in frame: the protagonist, Q and N; a long Chinese and a long English paragraph; a
## real choice list; a line with no portrait (B) and narration with no speaker; an
## over-long name; the same line at 1280x720, 1600x900 and 1920x1080; and the largest
## text size. Every sentence and option is read from the shipped content at run time.
##
## Run it with a display (Xvfb in CI, `.github/workflows/dialogue-identity-capture.yml`):
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_dialogue_identity.gd
##
## Full frames land in `docs/screenshots/dialogue_identity/*.png` (the workflow uploads
## them as an artifact; nothing is committed by CI). Each frame is also written as a small
## JPEG next to it - the band and its wash for the single-case frames, the whole picture
## for the resolution frames - which the workflow publishes as notice annotations.

const Harness = preload("res://tests/test_harness.gd")
const OUT_DIR := "res://docs/screenshots/dialogue_identity"
const LOG_PATH := "res://docs/screenshots/dialogue_identity/IDENTITY_CAPTURE.log"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const STANDARD := Vector2i(1600, 900)
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)
]
## Width of the small JPEGs: band crops and whole frames.
const CROP_WIDTH := 760
const FULL_WIDTH := 640
const JPEG_QUALITY := 0.62
## Not a story name: a probe for the trimming of the name beside the portrait.
const LONG_NAME_EN := "A Speaker Whose Name Is Far Too Long For The Name Row"

var _failures: Array[String] = []
var _shots: Array[String] = []
var _main: Node = null
var _ui: GameUI = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "capture_dialogue_identity.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	loc.set_locale("zh-CN")
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")

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
	if _ui == null or _dialogue == null or _ui.dialogue_panel == null:
		_finish(["Main did not expose GameUI, its dialogue panel and DialogueController."])
		return
	_panel = _ui.dialogue_panel

	# Let the opening run its course, so the panel is ours and the classroom is behind it.
	Engine.time_scale = 4.0
	await _wait_for_line(90.0)
	await _settle(90.0)
	Engine.time_scale = 1.0

	var zh_lines := _lines("res://data/dialogue/zh-CN/prologue.json")
	var en_lines := _lines("res://data/dialogue/en/prologue.json")
	var prose_zh := _longest_text("res://data/inspections/zh-CN/classroom.json")
	var prose_en := _longest_text("res://data/inspections/en/classroom.json")
	if zh_lines.is_empty() or en_lines.is_empty() or prose_zh.is_empty() or prose_en.is_empty():
		_finish(["The shipped content did not yield lines to show."])
		return

	await _resize(STANDARD)
	# 1-3. The three speakers with a portrait, each with their own longest line.
	for speaker in ["protagonist", "q", "n"]:
		await _show("zh-CN", _line(_longest_by(zh_lines, speaker), speaker))
		await _shot("id-%s-1600x900-zh" % speaker, true)

	# 4-5. Long paragraphs, in both languages.
	await _show("zh-CN", _line(prose_zh, "protagonist"))
	await _shot("id-long-zh-1600x900", true)
	await _show("en", _line(prose_en, "q"))
	await _shot("id-long-en-1600x900", true)

	# 6. A real choice list: the node with the most options, its line and its options.
	var choice_node := _richest_choice(zh_lines)
	var choice_line := _line(String(choice_node["text"]), String(choice_node["speaker"]))
	await _show("zh-CN", choice_line, choice_node["choices"])
	await _shot("id-choices-1600x900-zh", true)

	# 7. No portrait: B, and narration with no speaker at all.
	await _show("zh-CN", _line(_longest_by(zh_lines, "b"), "b"))
	await _shot("id-b-1600x900-zh", true)
	await _show("zh-CN", _line(prose_zh, ""))
	await _shot("id-narration-1600x900-zh", true)

	# 8. A name too long for the row beside the portrait.
	var long_name := _line(_longest_by(en_lines, "n"), "probe_long_name")
	long_name["speaker_name"] = LONG_NAME_EN
	long_name["portrait_profile"] = CharacterDirectory.load_cached().get_profile(&"n")
	await _show("en", long_name)
	await _shot("id-long-name-1600x900-en", true)

	# 9-11. The same Q line at the three window sizes.
	for size in RESOLUTIONS:
		await _resize(size)
		await _show("zh-CN", _line(_longest_by(zh_lines, "q"), "q"))
		await _shot("id-q-%dx%d-full" % [size.x, size.y], false)

	# 12. The largest text size, at the smallest window.
	if settings != null:
		await _resize(RESOLUTIONS[0])
		settings.call("set_text_size", &"largest")
		await _frames(3)
		await _show("zh-CN", _line(_longest_by(zh_lines, "q"), "q"))
		await _shot("id-q-1280x720-largest", true)
		settings.call("reset_to_defaults")

	_panel.close()
	await _resize(STANDARD)
	_finish(_failures)


# --- content -----------------------------------------------------------------


## Every node of every conversation in a dialogue file, as `{speaker, text, choices}`.
func _lines(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Could not read %s." % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return result
	var conversations: Dictionary = (parsed as Dictionary).get("conversations", {})
	for conversation: Variant in conversations.values():
		for node: Variant in (conversation as Dictionary).get("nodes", []):
			var entry := node as Dictionary
			if entry == null or not entry.has("text"):
				continue
			var choices: Array = []
			for choice: Variant in entry.get("choices", []):
				choices.append({"text": String((choice as Dictionary).get("text", ""))})
			result.append({
				"speaker": String(entry.get("speaker", "")),
				"text": String(entry["text"]),
				"choices": choices,
			})
	return result


func _longest_by(lines: Array[Dictionary], speaker: String) -> String:
	var best := ""
	for entry in lines:
		if String(entry["speaker"]) == speaker and String(entry["text"]).length() > best.length():
			best = String(entry["text"])
	if best.is_empty():
		_failures.append("No line for '%s' in the shipped content." % speaker)
	return best


func _richest_choice(lines: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = lines[0]
	for entry in lines:
		if (entry["choices"] as Array).size() > (best["choices"] as Array).size():
			best = entry
	return best


func _longest_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Could not read %s." % path)
		return ""
	var best := {"text": ""}
	_collect_longest(JSON.parse_string(file.get_as_text()), best)
	return String(best["text"])


func _collect_longest(node: Variant, best: Dictionary) -> void:
	if node is Dictionary:
		for key: Variant in (node as Dictionary).keys():
			var value: Variant = (node as Dictionary)[key]
			if String(key) == "text" and value is String \
					and String(value).length() > String(best["text"]).length():
				best["text"] = value
			else:
				_collect_longest(value, best)
	elif node is Array:
		for item: Variant in node:
			_collect_longest(item, best)


func _line(text: String, speaker_id: String) -> Dictionary:
	var profile := CharacterDirectory.load_cached().get_profile(StringName(speaker_id))
	var accent := profile.accent_color if profile != null else Color(0.776, 0.733, 0.643, 1.0)
	return {
		"conversation_id": &"identity_capture",
		"node_id": &"capture",
		"speaker_id": StringName(speaker_id),
		"speaker_name": profile.display_name if profile != null else "",
		"speaker_role": "",
		"accent_color": accent,
		"title": "",
		"text": text,
		"source": NarrativeEntry.Source.REPORTED,
		"badge": NarrativeEntry.badge_key_for(NarrativeEntry.Source.REPORTED),
		"subjective": false,
		"tags": PackedStringArray(),
	}


# --- helpers -----------------------------------------------------------------


func _show(locale: String, line: Dictionary, choices: Array = []) -> void:
	if _dialogue.is_busy():
		await _settle(30.0)
	L10n.set_locale(locale)
	_panel.show_line(line)
	_panel.complete_reveal()
	if not choices.is_empty():
		_panel.set_choices(choices)
	await _frames(6)


func _shot(name: String, crop_to_band: bool) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("The %s frame came back empty." % name)
		return
	var error := image.save_png("%s/%s.png" % [OUT_DIR, name])
	if error != OK:
		_failures.append("Could not write %s.png (error %d)." % [name, error])
		return
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	var width := FULL_WIDTH
	if crop_to_band:
		small = small.get_region(_band_region(image.get_size()))
		width = CROP_WIDTH
	var ratio := float(small.get_height()) / maxf(float(small.get_width()), 1.0)
	var height := maxi(roundi(ratio * width), 1)
	small.resize(width, height, Image.INTERPOLATE_LANCZOS)
	small.save_jpg("%s/%s.jpg" % [OUT_DIR, name], JPEG_QUALITY)
	_shots.append(name)
	var portrait := _panel.get_portrait_report()
	var layout := _panel.get_layout_report()
	print(
		"SHOT %s  %dx%d  portrait=%s %s  band %s  scrolling=%s"
		% [
			name,
			image.get_width(),
			image.get_height(),
			portrait["status"],
			portrait["rect"],
			layout["panel_rect"],
			str(layout["body_scrolling"]),
		]
	)


## The band, its wash and the portrait, with a margin of the scene around them.
func _band_region(frame_size: Vector2i) -> Rect2i:
	var band: Rect2 = _panel.get_layout_report()["panel_rect"]
	var wash := (_panel.get_node("Wash") as Control).get_global_rect()
	var area := band.merge(wash)
	var portrait := _panel.get_portrait_report()
	if bool(portrait["visible"]):
		area = area.merge(portrait["rect"])
	area = area.grow(28.0)
	var region := Rect2i(Vector2i(area.position.floor()), Vector2i(area.size.ceil()))
	return region.intersection(Rect2i(Vector2i.ZERO, frame_size))


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(6)


func _wait_for_line(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if _dialogue.is_busy():
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
		file.store_line("RESULT: %d identity frames captured." % _shots.size())
		file.close()
	if failures.is_empty() and not _shots.is_empty():
		print("PASS: captured %d identity frames." % _shots.size())
		quit(0)
		return
	for failure in failures:
		printerr("FAILURE: %s" % failure)
	quit(1)
