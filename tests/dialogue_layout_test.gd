extends SceneTree
## Measures the dialogue panel instead of eyeballing it.
##
## The reading surface has to hold the worst content the game can produce — a long
## Chinese paragraph, a multi-paragraph recollection, four long options, a speaker name
## and a role that are both too long — at the five supported window sizes through 4K.
## "It looked fine on my screen" is not a test, so this script drives the real panel
## with its actual content at all five sizes and asserts:
##
## - the panel stays a band: inside the viewport, at most 72% of its width and 66% of
##   its height, so the room it is drawn over is still the main picture;
## - no text is clipped: the body is either fully visible or explicitly scrollable;
## - the type never shrinks to make room: the body keeps its configured size at every
##   resolution;
## - every option, the name, the role, the source label, the title and the hint stay
##   inside the panel, with the options above the bottom edge at every size.
##
## The text it uses is read from the shipped content, so the sizes measured are the
## sizes the game really has to draw.
##
## Every case runs twice: at the standard text size and at the **largest** one the
## settings offer (issue #62), set through the real `Settings` node so the panel's own
## wiring is what scales the type. The ceilings above do not move for the larger type:
## the band still has to stay a band, and what no longer fits scrolls instead of shrinking.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

## Hard ceilings on how much of the screen the band may occupy. They are the contract:
## the 3D scene stays the protagonist.
const MAX_WIDTH_RATIO := 0.72
const MAX_HEIGHT_RATIO := 0.66
const MAX_AREA_RATIO := 0.45

var _failures: Array[String] = []
var _panel: DialoguePanel = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "dialogue_layout_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	if not L10n.errors().is_empty():
		_failures.append("Locale tables reported errors: %s" % " | ".join(L10n.errors()))
	L10n.set_locale("en")
	# Before the panel, so it connects to the text size the way it does in the game.
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")

	var packed: PackedScene = load("res://scenes/ui/dialogue_panel.tscn")
	if packed == null:
		Harness.finish(self, ["dialogue_panel.tscn could not be loaded."], "")
		return
	_panel = packed.instantiate()
	root.add_child(_panel)
	await process_frame
	await process_frame
	_check_portrait_resources_are_warm()

	# The longest paragraphs the shipped content actually has, in both languages: the
	# object descriptions are the long ones, the prologue supplies the shorter beats.
	var samples := {
		"prose_en": _longest_text("res://data/inspections/en/classroom.json"),
		"prose_zh": _longest_text("res://data/inspections/zh-CN/classroom.json"),
		"beat_en": _longest_text("res://data/dialogue/en/prologue.json"),
		"beat_zh": _longest_text("res://data/dialogue/zh-CN/prologue.json"),
	}
	var report := "content samples: prose_en %d, prose_zh %d, beat_en %d, beat_zh %d" % [
		String(samples["prose_en"]).length(),
		String(samples["prose_zh"]).length(),
		String(samples["beat_en"]).length(),
		String(samples["beat_zh"]).length(),
	]
	print(report)
	if String(samples["prose_en"]).length() < 120 or String(samples["prose_zh"]).length() < 40 \
			or String(samples["beat_en"]).is_empty() or String(samples["beat_zh"]).is_empty():
		_failures.append("The content files did not yield usable sample text (%s)." % report)
		Harness.finish(self, _failures, "")
		return

	await _check_line_change_does_not_flash(String(samples["prose_zh"]))

	for size in RESOLUTIONS:
		root.size = size
		await process_frame
		await process_frame
		await process_frame
		await _run_cases(size, samples, "")

	# A visible check (`CheckOverlay`) shares the screen with the band; it must stay a
	# small frame at the top and never overlap the dialogue at the smallest size.
	await _check_overlay(size_smallest())

	# The same again at the largest text size.
	if settings == null:
		_failures.append("The Settings autoload could not be created.")
	else:
		var standard_body := _panel.body_size
		settings.call("set_text_size", &"largest")
		await process_frame
		var factor := float(settings.call("text_scale"))
		if _panel.body_size != UiTextScale.scaled(standard_body, factor) or factor < 1.25:
			_failures.append(
				"The largest text size left the body at %d px (standard %d px, factor %.2f)."
				% [_panel.body_size, standard_body, factor]
			)
		for size in RESOLUTIONS:
			root.size = size
			await process_frame
			await process_frame
			await process_frame
			await _run_cases(size, samples, "largest text, ")
		await _check_overlay(size_smallest())
		await _check_backlog(size_smallest(), samples)
		settings.call("reset_to_defaults")
		await process_frame

	Engine.time_scale = 1.0
	root.size = Vector2i(1600, 900)
	Harness.finish(
		self,
		_failures,
		"the dialogue panel keeps its hierarchy and its type at all five resolutions through 4K, "
		+ "at the standard and the largest text size."
	)


func size_smallest() -> Vector2i:
	return RESOLUTIONS[0]


func _logical_canvas_size(fallback: Vector2i) -> Vector2i:
	if root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		return root.content_scale_size
	return Vector2i(root.get_visible_rect().size) if root.get_visible_rect().size.x > 0.0 else fallback


func _run_cases(size: Vector2i, samples: Dictionary, prefix: String) -> void:
	var tag := "%s%dx%d" % [prefix, size.x, size.y]
	var layout_size := _logical_canvas_size(size)
	var prose_en := String(samples["prose_en"])
	var prose_zh := String(samples["prose_zh"])
	var beat_zh := String(samples["beat_zh"])
	var beat_en := String(samples["beat_en"])

	# 1. A long English paragraph, seen.
	L10n.set_locale("en")
	await _show(
		_line(prose_en, "protagonist", "You", "", NarrativeEntry.Source.OBSERVED, false)
	)
	_measure("%s long English prose" % tag, layout_size, true)

	# 2. A long Chinese paragraph, heard. Chinese is the script's own language and the
	#    one whose line lengths the layout has to survive.
	L10n.set_locale("zh-CN")
	await _show(
		_line(prose_zh, "q", "Q", "role.q", NarrativeEntry.Source.REPORTED, false)
	)
	_measure("%s long Chinese prose" % tag, layout_size, true)

	# 3. One paragraph long enough that no fixed box could hold it: the scroll path.
	L10n.set_locale("zh-CN")
	# 16 paragraphs of the shipped prose: ~1300 characters, which cannot fit the band at
	# any of the three sizes, so the scroll fallback is exercised instead of assumed.
	var wall := ""
	for index in 16:
		wall += prose_zh
		if index < 15:
			wall += "\n"
	await _show(_line(wall, "protagonist", "You", "", NarrativeEntry.Source.OBSERVED, false))
	_measure("%s over-long single paragraph" % tag, layout_size, false)
	if not bool(_panel.get_layout_report()["body_scrolling"]):
		_failures.append("%s: an over-long paragraph did not fall back to scrolling." % tag)

	# 4. Three paragraphs of recollection, with a title.
	var paragraphs := "%s\n\n%s\n\n%s" % [prose_zh, beat_zh, prose_zh]
	var recall_line := _line(
		paragraphs, "protagonist", "You", "", NarrativeEntry.Source.RECALLED, false
	)
	recall_line["title"] = L10n.t("badge.recalled")
	await _show(recall_line)
	_measure("%s multi-paragraph recollection" % tag, layout_size, false)

	# 5. Four long options under a long line: the layout that breaks first.
	var choice_line := _line(prose_zh, "n", "N", "role.n", NarrativeEntry.Source.REPORTED, false)
	await _show(choice_line)
	var options: Array = []
	for index in 4:
		options.append({
			"text": "%s（%d）" % [prose_zh.substr(0, mini(38, prose_zh.length())), index + 1],
		})
	_panel.set_choices(options)
	await process_frame
	await process_frame
	_measure("%s four long options" % tag, layout_size, false)
	await _measure_options("%s four long options" % tag, layout_size)

	# 6. A name and a role that are both too long, plus a title.
	var long_name := "名字非常非常长的一个人物名称"
	var long_role := "role.that.is.much.too.long.to.fit"
	var long_line := _line(prose_zh, "q", long_name, "", NarrativeEntry.Source.OBSERVED, false)
	long_line["speaker_role"] = long_role
	long_line["title"] = "一个同样很长的标题，用来检查标题行会不会越过面板"
	await _show(long_line)
	_measure("%s overlong name and role" % tag, layout_size, true)

	# 7. Consecutive inner voices: subjective, imagined, no role.
	var voice_line := _line(
		beat_en, "orientation", "Orientation", "", NarrativeEntry.Source.IMAGINED, true
	)
	await _show(voice_line)
	_measure("%s inner voice" % tag, layout_size, true)
	if _panel.get_node("Frame/Content/HeaderRow/SpeakerLabel").get_theme_color("font_color") \
			== Color(0.898, 0.871, 0.804, 1.0):
		_failures.append("%s inner voice: the subjective tint was not applied." % tag)

	_panel.set_choices([])
	_panel.close()
	await process_frame


func _line(
	text: String,
	speaker_id: String,
	speaker_name: String,
	role_key: String,
	source_value: int,
	subjective: bool
) -> Dictionary:
	return {
		"conversation_id": &"layout_probe",
		"node_id": &"probe",
		"speaker_id": StringName(speaker_id),
		"speaker_name": speaker_name,
		"speaker_role": L10n.t(role_key) if not role_key.is_empty() and L10n.has_key(role_key) else "",
		"accent_color": Color(0.776, 0.733, 0.643, 1.0),
		"title": "",
		"text": text,
		"source": source_value,
		"badge": NarrativeEntry.badge_key_for(source_value),
		"subjective": subjective,
		"tags": PackedStringArray(),
	}


func _show(line: Dictionary) -> void:
	_panel.show_line(line)
	_panel.complete_reveal()
	# Two frames: one to apply the new text and width, one to measure what it produced.
	await process_frame
	await process_frame
	await process_frame


func _check_portrait_resources_are_warm() -> void:
	var directory := CharacterDirectory.load_cached()
	for character_id: StringName in directory.get_ids():
		var profile := directory.get_profile(character_id)
		if profile == null or not profile.has_portrait():
			continue
		if not ResourceLoader.has_cached(profile.portrait_path):
			_failures.append(
				"The %s portrait was not resolved before dialogue was opened."
				% character_id
			)


func _check_line_change_does_not_flash(prose: String) -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	await _show(_line("A short line.", "q", "Q", "role.q", NarrativeEntry.Source.REPORTED, false))
	var initial_height := _panel.get_global_rect().size.y
	var long_text := ""
	for index in 2:
		long_text += prose
		if index < 1:
			long_text += "\n"
	_panel.show_line(
		_line(long_text, "q", "Q", "role.q", NarrativeEntry.Source.REPORTED, false)
	)
	_panel.complete_reveal()
	var observed_heights: Array[float] = [_panel.get_global_rect().size.y]
	for _frame in 3:
		await process_frame
		observed_heights.append(_panel.get_global_rect().size.y)
	var final_height: float = observed_heights[observed_heights.size() - 1]
	if final_height <= initial_height + 24.0:
		_failures.append(
			"The line-change probe did not produce a taller final band (%.0f -> %.0f px)."
			% [initial_height, final_height]
		)
	for frame_index in observed_heights.size() - 1:
		var height := observed_heights[frame_index]
		if height > maxf(initial_height, final_height) + 2.0:
			var message := (
				"The dialogue band flashed to %.0f px on frame %d before settling at %.0f px "
				% [height, frame_index, final_height]
				+ "(previous line %.0f px)." % initial_height
			)
			_failures.append(message)
			break
	if not _panel.is_visible_in_tree():
		_failures.append("The dialogue panel became hidden while changing lines.")
	_panel.close()
	await process_frame


func _measure(label: String, size: Vector2i, expect_body_fits: bool) -> void:
	var report := _panel.get_layout_report()
	var viewport: Vector2 = report["viewport"]
	if not is_equal_approx(viewport.x, float(size.x)) or not is_equal_approx(viewport.y, float(size.y)):
		_failures.append("%s: the viewport is %s, expected %s." % [label, viewport, size])

	var rect: Rect2 = report["panel_rect"]
	if rect.position.x < -0.5 or rect.position.y < -0.5:
		_failures.append("%s: the band starts outside the viewport at %s." % [label, rect.position])
	if rect.end.x > viewport.x + 0.5 or rect.end.y > viewport.y + 0.5:
		_failures.append("%s: the band ends outside the viewport at %s." % [label, rect.end])
	if float(report["covers_width"]) > MAX_WIDTH_RATIO:
		_failures.append(
			"%s: the band is %.0f%% of the screen width." % [label, float(report["covers_width"]) * 100.0]
		)
	if float(report["covers_height"]) > MAX_HEIGHT_RATIO:
		_failures.append(
			"%s: the band is %.0f%% of the screen height."
			% [label, float(report["covers_height"]) * 100.0]
		)
	if float(report["covers_width"]) * float(report["covers_height"]) > MAX_AREA_RATIO:
		_failures.append("%s: the band covers too much of the picture." % label)

	# The type is fixed. Shrinking it to fit is the failure mode this guards against.
	if int(report["body_font_size"]) != _panel.body_size:
		_failures.append(
			"%s: the body is %d px, not the configured %d px."
			% [label, int(report["body_font_size"]), _panel.body_size]
		)

	var body_rect: Rect2 = report["body_rect"]
	var content_height := float(report["body_content_height"])
	var scrolling: bool = report["body_scrolling"]
	if not scrolling and content_height > body_rect.size.y + 2.0:
		_failures.append(
			"%s: %.0f px of text in a %.0f px body with no scroll."
			% [label, content_height, body_rect.size.y]
		)
	if scrolling and content_height <= body_rect.size.y + 2.0:
		_failures.append("%s: the body scrolls although the text already fits." % label)
	if expect_body_fits and scrolling:
		_failures.append("%s: ordinary prose had to scroll." % label)
	if body_rect.size.y < 20.0:
		_failures.append("%s: the body was squeezed to %.0f px." % [label, body_rect.size.y])

	for path in [
		"Frame/Content/HeaderRow/SpeakerLabel",
		"Frame/Content/HeaderRow/RoleLabel",
		"Frame/Content/HeaderRow/SourceBadge",
		"Frame/Content/TitleLabel",
		"Frame/Content/HintLabel",
	]:
		var node := _panel.get_node_or_null(path) as Control
		if node == null or not node.visible:
			continue
		var node_rect := node.get_global_rect()
		if node_rect.size.x <= 0.0 or node_rect.size.y <= 0.0:
			_failures.append("%s: %s has no size." % [label, path])
			continue
		if node_rect.position.x < rect.position.x - 0.5 or node_rect.end.x > rect.end.x + 0.5:
			_failures.append(
				"%s: %s spills out of the band horizontally (%s)." % [label, path, node_rect]
			)
		if node_rect.end.y > rect.end.y + 0.5:
			_failures.append("%s: %s hangs below the band (%s)." % [label, path, node_rect])


func _measure_options(label: String, size: Vector2i) -> void:
	var report := _panel.get_layout_report()
	if int(report["choice_count"]) != 4:
		_failures.append("%s: %d options were built." % [label, int(report["choice_count"])])
		return
	var buttons := _panel.get_choice_buttons()
	if not bool(report.get("choices_windowed", false)):
		for index in buttons.size():
			_measure_option(label, size, index)
		return
	# Large type on a small screen: the options are shown a run at a time. Every one of
	# them must still be reachable, and once brought into view it must fit the band like
	# any other - nothing is clipped, it is only further down the list.
	print("%s: options shown %s at a time" % [label, str(_panel.get_choice_window())])
	if not _panel.get_node("Frame/Content/HintLabel").text.contains("/ 4"):
		_failures.append("%s: a partial list of options does not say so on the hint line." % label)
	for index in buttons.size():
		_panel.reveal_choice(index)
		for _frame in 4:
			await process_frame
		var window := _panel.get_choice_window()
		if index < window.x or index >= window.x + window.y:
			_failures.append("%s: option %d could not be brought into view (%s)." % [label, index + 1, window])
			continue
		_measure(label + " (option %d in view)" % (index + 1), size, false)
		_measure_option(label, size, index)


func _measure_option(label: String, size: Vector2i, index: int) -> void:
	var panel_rect: Rect2 = _panel.get_layout_report()["panel_rect"]
	var button := _panel.get_choice_buttons()[index]
	if not button.is_visible_in_tree():
		_failures.append("%s: option %d is not shown." % [label, index + 1])
		return
	var button_rect := button.get_global_rect()
	if button_rect.size.y < 24.0:
		_failures.append("%s: option %d is %.0f px tall." % [label, index + 1, button_rect.size.y])
	if button_rect.position.x < panel_rect.position.x - 0.5 \
			or button_rect.end.x > panel_rect.end.x + 0.5:
		_failures.append(
			"%s: option %d spills out horizontally (%s)." % [label, index + 1, button_rect]
		)
	if button_rect.end.y > panel_rect.end.y + 0.5:
		_failures.append(
			"%s: option %d hangs below the band (%s)." % [label, index + 1, button_rect]
		)
	if button_rect.end.y > float(size.y):
		_failures.append("%s: option %d is off screen." % [label, index + 1])
	if button.mouse_filter != Control.MOUSE_FILTER_STOP:
		_failures.append("%s: option %d does not accept the mouse." % [label, index + 1])


## A visible check is a small frame near the top. It must stay clear of the dialogue
## band even at the smallest resolution, or the player cannot read either of them.
func _check_overlay(size: Vector2i) -> void:
	root.size = size
	await process_frame
	await process_frame
	var packed: PackedScene = load("res://scenes/ui/check_overlay.tscn")
	if packed == null:
		_failures.append("check_overlay.tscn could not be loaded.")
		return
	var overlay: CheckOverlay = packed.instantiate()
	root.add_child(overlay)
	await process_frame
	overlay.present(
		&"orientation",
		"Orientation",
		{
			"dice": [4],
			"modifier": 2,
			"difficulty": 12,
			"success": true,
			"kind": "visible",
			"ability": "orientation",
		}
	)
	await process_frame
	await process_frame
	var band := _panel.get_global_rect()
	var frame := overlay.get_node_or_null("%Panel") as Control
	var overlay_rect := frame.get_global_rect() if frame != null else Rect2(Vector2.ZERO, Vector2.ZERO)
	if overlay_rect.size.x > 0.0:
		if overlay_rect.position.y < -0.5 or overlay_rect.end.y > float(size.y) + 0.5:
			_failures.append("The check overlay does not fit vertically: %s." % overlay_rect)
		if band.size.y > 0.0 and overlay_rect.end.y > band.position.y:
			_failures.append("The check overlay overlaps the dialogue band.")
	else:
		# Present() only paints when it is inside a sized container; if the scene has no
		# visible frame here the layout claim is vacuous, so say so instead of passing.
		_failures.append("The check overlay produced no measurable frame.")
	overlay.queue_free()
	await process_frame


## The log (Tab / Y) at the smallest size and the largest type: every row has its
## header and its text, and stays inside the list's width. A row with no text at all is
## the regression this guards: the rows once came out empty.
func _check_backlog(size: Vector2i, samples: Dictionary) -> void:
	root.size = size
	await process_frame
	var packed: PackedScene = load("res://scenes/ui/backlog_panel.tscn")
	if packed == null:
		_failures.append("backlog_panel.tscn could not be loaded.")
		return
	var backlog: BacklogPanel = packed.instantiate()
	root.add_child(backlog)
	await process_frame
	for locale: String in ["en", "zh-CN"]:
		L10n.set_locale(locale)
		var prose := String(samples["prose_zh" if locale == "zh-CN" else "prose_en"])
		var line := _line(prose, "q", "Q", "role.q", NarrativeEntry.Source.REPORTED, false)
		line["node_id"] = StringName("probe_%s" % locale)
		backlog.add_entry(line)
	backlog.open()
	for _index in 4:
		await process_frame
	var tag := "largest text, %dx%d log" % [size.x, size.y]
	var list := backlog.get_node_or_null("%BacklogList") as Control
	var scroll := backlog.get_node_or_null("%BacklogScroll") as Control
	if list == null or scroll == null:
		_failures.append("%s: the list is missing." % tag)
	else:
		var area := scroll.get_global_rect()
		if area.end.x > float(size.x) + 0.5 or area.end.y > float(size.y) + 0.5:
			_failures.append("%s: the list runs off the screen (%s)." % [tag, area])
		if list.get_child_count() != 2:
			_failures.append("%s: %d rows for 2 entries." % [tag, list.get_child_count()])
		for row in list.get_children():
			var header := row.get_node_or_null("Header") as Label
			var body := row.get_node_or_null("Body") as Label
			if header == null or body == null:
				_failures.append("%s: a row has no header or no text label." % tag)
				continue
			if header.text.strip_edges().is_empty() or body.text.strip_edges().is_empty():
				_failures.append("%s: a row is empty ('%s' / '%s')." % [tag, header.text, body.text])
			var box := body.get_global_rect()
			if box.size.x <= 0.0 or box.size.y < float(body.get_line_height()):
				_failures.append("%s: a row's text has no room (%s)." % [tag, box.size])
			if box.position.x < area.position.x - 0.5 or box.end.x > area.end.x + 0.5:
				_failures.append("%s: a row spills out of the list sideways (%s)." % [tag, box])
			if body.get_visible_line_count() < body.get_line_count():
				_failures.append("%s: a row is clipped." % tag)
	backlog.close()
	backlog.queue_free()
	await process_frame


func _longest_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Could not read %s." % path)
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var best := {"text": ""}
	_collect_longest(parsed, best)
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
