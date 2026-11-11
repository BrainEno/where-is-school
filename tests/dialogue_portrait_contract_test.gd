extends SceneTree
## The optional 2D dialogue portrait, as a contract rather than as art.
##
## No approved portrait exists yet, so nothing here ships an image: every texture is
## generated in code for the length of the test and thrown away. What is checked is the
## promise the panel and the profile make about portraits:
##
## 1. Every shipped `CharacterProfile` still loads, and none of them asks for a
##    portrait. Old files that predate the fields read as "no portrait".
## 2. No portrait means no change. A line shown without a portrait has exactly the
##    rects it had before portraits existed (band, body, name, hint, options), and
##    showing a portrait in between leaves nothing behind.
## 3. With a portrait, at 1280x720, 1600x900 and 1920x1080 and in English and
##    Chinese, with a long paragraph, short and long names and 0 / 1 / 2 / 4 options:
##    the portrait stays inside the screen, is drawn behind the band, overlaps none of
##    the name, role, source label, title, body, options or hint, is not stretched,
##    never takes a click, and the band keeps its width and its type size.
## 4. A portrait that cannot be used (bad path, missing file, not a texture, no
##    pixels, absurd proportions, a crop that leaves nothing) is reported with a status
##    and a message naming the character, and the line is laid out exactly as if the
##    speaker had no portrait.

const Harness = preload("res://tests/test_harness.gd")

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LOCALES: Array[String] = ["en", "zh-CN"]
const CHOICE_COUNTS: Array[int] = [0, 1, 2, 4]
const PROBE_ID := &"portrait_probe"
const LONG_NAME_ZH := "名字非常非常长的一个人物名称"
const LONG_NAME_EN := "A Speaker Whose Name Is Far Too Long For The Name Row"
const TOLERANCE := 0.5

var _failures: Array[String] = []
var _panel: DialoguePanel = null
var _samples: Dictionary = {}
## A tall figure-shaped texture (aspect 0.6) and a wide one (aspect 1.6) that has to be
## scaled down to respect the width cap. Both are plain generated pixels.
var _tall_texture: Texture2D = null
var _wide_texture: Texture2D = null
var _advance_count: int = 0
var _checked_cases: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 420.0, "dialogue_portrait_contract_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	if not L10n.errors().is_empty():
		_failures.append("Locale tables reported errors: %s" % " | ".join(L10n.errors()))
	L10n.set_locale("en")
	CharacterDirectory.reset_cache_for_tests()

	_check_shipped_profiles()
	_check_profile_resolution()

	_tall_texture = _fixture(600, 1000)
	_wide_texture = _fixture(1200, 750)

	var packed: PackedScene = load("res://scenes/ui/dialogue_panel.tscn")
	if packed == null:
		Harness.finish(self, ["dialogue_panel.tscn could not be loaded."], "")
		return
	_panel = packed.instantiate()
	root.add_child(_panel)
	_panel.advance_requested.connect(func() -> void: _advance_count += 1)
	await process_frame
	await process_frame
	_check_scene_contract()

	_samples = {
		"en": _longest_text("res://data/inspections/en/classroom.json"),
		"zh-CN": _longest_text("res://data/inspections/zh-CN/classroom.json"),
	}
	if String(_samples["en"]).length() < 120 or String(_samples["zh-CN"]).length() < 40:
		_failures.append(
			"The content files did not yield usable sample text (en %d, zh-CN %d)."
			% [String(_samples["en"]).length(), String(_samples["zh-CN"]).length()]
		)
		Harness.finish(self, _failures, "")
		return

	for size in RESOLUTIONS:
		await _resize(size)
		for locale in LOCALES:
			L10n.set_locale(locale)
			for index in CHOICE_COUNTS.size():
				await _run_layout_case(size, locale, CHOICE_COUNTS[index], index % 2 == 1)

	await _resize(RESOLUTIONS[0])
	L10n.set_locale("en")
	await _run_failure_cases()
	await _run_edge_cases()
	await _run_click_case()

	_panel.close()
	await process_frame
	root.size = Vector2i(1600, 900)
	print("portrait contract: %d layout comparisons checked" % _checked_cases)
	Harness.finish(
		self,
		_failures,
		"optional dialogue portraits leave the text layout untouched when absent, stay clear of the text at 1280x720, 1600x900 and 1920x1080 in en and zh-CN when present, and fail visibly but harmlessly when unusable."
	)


# --- Profiles -----------------------------------------------------------------


## Every profile in data/characters loads as before and none requests a portrait.
func _check_shipped_profiles() -> void:
	var files := DirAccess.get_files_at("res://data/characters")
	var seen := 0
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var path := "res://data/characters/%s" % file_name
		var resource: Resource = ResourceLoader.load(path)
		if not (resource is CharacterProfile):
			_failures.append("%s no longer loads as a CharacterProfile." % path)
			continue
		seen += 1
		var profile: CharacterProfile = resource
		if String(profile.character_id).is_empty():
			_failures.append("%s lost its character_id." % path)
		if profile.has_portrait() or profile.portrait != null or not profile.portrait_path.is_empty():
			_failures.append("%s asks for a portrait; no portrait has been approved yet." % path)
		if profile.portrait_side != CharacterProfile.PortraitSide.LEFT \
				or not is_equal_approx(profile.portrait_height_ratio, 0.72) \
				or profile.portrait_crop != Rect2(0.0, 0.0, 1.0, 1.0):
			_failures.append("%s does not read the default portrait composition." % path)
		var resolved := profile.resolve_portrait()
		if String(resolved["status"]) != "none" or resolved["texture"] != null:
			_failures.append("%s resolves a portrait: %s." % [path, resolved])
	if seen < 5:
		_failures.append("Only %d character profiles were found in data/characters." % seen)

	var directory := CharacterDirectory.load_cached()
	if not directory.errors.is_empty():
		_failures.append("CharacterDirectory reported errors: %s" % " | ".join(directory.errors))
	for character_id in directory.get_ids():
		var profile := directory.get_profile(character_id)
		if profile == null or profile.has_portrait():
			_failures.append("Directory profile '%s' is missing or has a portrait." % character_id)


## `resolve_portrait()` on its own, without the panel.
func _check_profile_resolution() -> void:
	var tall := _fixture(600, 1000)
	var profile := _profile(tall, CharacterProfile.PortraitSide.LEFT)
	var resolved := profile.resolve_portrait()
	if String(resolved["status"]) != "ok" or resolved["texture"] != tall:
		_failures.append("An uncropped valid portrait did not resolve to itself: %s." % resolved)

	profile.portrait_crop = Rect2(0.25, 0.0, 0.5, 1.0)
	resolved = profile.resolve_portrait()
	var cropped: Texture2D = resolved["texture"]
	if String(resolved["status"]) != "ok" or cropped == null \
			or not cropped.get_size().is_equal_approx(Vector2(300.0, 1000.0)):
		_failures.append("A half-width crop did not produce a 300x1000 texture: %s." % resolved)

	profile.portrait_height_ratio = 5.0
	if not is_equal_approx(profile.get_portrait_height_ratio(), CharacterProfile.PORTRAIT_MAX_HEIGHT_RATIO):
		_failures.append("An out-of-range height ratio was not clamped.")
	profile.portrait_height_ratio = -1.0
	if not is_equal_approx(profile.get_portrait_height_ratio(), CharacterProfile.PORTRAIT_MIN_HEIGHT_RATIO):
		_failures.append("A negative height ratio was not clamped.")

	# The embedded texture wins over the path, so a stale path cannot hide a set texture.
	var both := _profile(tall, CharacterProfile.PortraitSide.LEFT)
	both.portrait_path = "res://does/not/exist.png"
	if String(both.resolve_portrait()["status"]) != "ok":
		_failures.append("portrait_path overrode a set portrait texture.")

	var empty := CharacterProfile.new()
	empty.character_id = PROBE_ID
	if empty.has_portrait() or String(empty.resolve_portrait()["status"]) != "none":
		_failures.append("A fresh CharacterProfile claims a portrait.")


# --- Panel layout -----------------------------------------------------------


## The node is part of the scene, behind the band, and transparent to the mouse.
func _check_scene_contract() -> void:
	var portrait := _panel.get_node_or_null("Portrait") as TextureRect
	var frame := _panel.get_node_or_null("Frame") as Control
	var wash := _panel.get_node_or_null("Wash") as Control
	if portrait == null or frame == null or wash == null:
		_failures.append("The dialogue panel has no Portrait / Frame / Wash node.")
		return
	if portrait.get_index() > wash.get_index() or portrait.get_index() > frame.get_index():
		_failures.append("The portrait is not drawn behind the wash and the frame.")
	if portrait.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_failures.append("The portrait node takes the mouse.")
	if portrait.visible:
		_failures.append("The portrait is visible before any line is shown.")
	if portrait.texture != null:
		_failures.append("The scene ships a portrait texture.")
	var report := _panel.get_portrait_report()
	if String(report["status"]) != "none" or bool(report["visible"]):
		_failures.append("A fresh panel reports a portrait: %s." % report)


func _run_layout_case(size: Vector2i, locale: String, choice_count: int, long_name: bool) -> void:
	var zh := locale == "zh-CN"
	var prose := String(_samples[locale])
	var speaker_id := PROBE_ID if long_name else &"q"
	var speaker_name := (LONG_NAME_ZH if zh else LONG_NAME_EN) if long_name else "Q"
	var label := "%dx%d %s %s name, %d option(s)" % [
		size.x, size.y, locale, "long" if long_name else "short", choice_count
	]
	var choices: Array = []
	for index in choice_count:
		var text := prose.substr(0, mini(38 if zh else 64, prose.length()))
		choices.append({"text": ("%s（%d）" if zh else "%s (%d)") % [text, index + 1]})

	var plain := _line(prose, speaker_id, speaker_name)
	await _show(plain, choices)
	var baseline := _snapshot()
	_check_no_portrait("%s, before" % label)
	_check_baseline_geometry(label, size, baseline)

	for side in [CharacterProfile.PortraitSide.LEFT, CharacterProfile.PortraitSide.RIGHT]:
		var side_label := "%s, %s portrait" % [
			label, "right" if side == CharacterProfile.PortraitSide.RIGHT else "left"
		]
		var with_portrait := _line(prose, speaker_id, speaker_name)
		with_portrait["portrait_profile"] = _profile(_tall_texture, side)
		await _show(with_portrait, choices)
		_check_portrait_layout(side_label, size, baseline, _tall_texture.get_size().aspect())

	await _show(plain, choices)
	_check_no_portrait("%s, after" % label)
	_compare(label + ", shown again without a portrait", baseline, _snapshot())
	_checked_cases += 1


## A portrait that cannot be used changes nothing but the report.
func _run_failure_cases() -> void:
	var prose := String(_samples["en"])
	var plain := _line(prose, PROBE_ID, "Probe")
	await _show(plain, [])
	var baseline := _snapshot()

	var cases: Array[Dictionary] = []
	var invalid := _profile(null, CharacterProfile.PortraitSide.LEFT)
	invalid.portrait_path = "portraits/probe.png"
	cases.append({"name": "relative path", "profile": invalid, "status": "invalid_path"})
	var missing := _profile(null, CharacterProfile.PortraitSide.LEFT)
	missing.portrait_path = "res://art/portraits/portrait_probe_missing.png"
	cases.append({"name": "missing file", "profile": missing, "status": "missing"})
	var not_texture := _profile(null, CharacterProfile.PortraitSide.LEFT)
	not_texture.portrait_path = "res://data/characters/q.tres"
	cases.append({"name": "not a texture", "profile": not_texture, "status": "not_texture"})
	cases.append({
		"name": "no portrait at all",
		"profile": _profile(null, CharacterProfile.PortraitSide.LEFT),
		"status": "none",
	})
	cases.append({
		"name": "0x0 texture",
		"profile": _profile(ImageTexture.new(), CharacterProfile.PortraitSide.LEFT),
		"status": "empty_size",
	})
	cases.append({
		"name": "50:1 strip",
		"profile": _profile(_fixture(400, 8), CharacterProfile.PortraitSide.LEFT),
		"status": "bad_aspect",
	})
	cases.append({
		"name": "1:50 sliver",
		"profile": _profile(_fixture(8, 400), CharacterProfile.PortraitSide.RIGHT),
		"status": "bad_aspect",
	})
	var bad_crop := _profile(_tall_texture, CharacterProfile.PortraitSide.LEFT)
	bad_crop.portrait_crop = Rect2(2.0, 2.0, 1.0, 1.0)
	cases.append({"name": "crop outside the image", "profile": bad_crop, "status": "bad_crop"})

	for entry in cases:
		var label := "failure path '%s'" % String(entry["name"])
		var line := _line(prose, PROBE_ID, "Probe")
		line["portrait_profile"] = entry["profile"]
		await _show(line, [])
		var report := _panel.get_portrait_report()
		var expected := String(entry["status"])
		if String(report["status"]) != expected:
			_failures.append("%s: status %s, expected %s." % [label, report["status"], expected])
		if bool(report["visible"]):
			_failures.append("%s: a portrait is drawn." % label)
		if expected != "none":
			var message := String(report["message"])
			if message.is_empty() or not message.contains(String(PROBE_ID)):
				_failures.append("%s: the message does not name the character: '%s'." % [label, message])
		if not _panel.visible or _panel.get_body_text() != prose:
			_failures.append("%s: the line itself was not shown." % label)
		_compare(label, baseline, _snapshot())


## Proportions and settings that are legal but have to be adapted, not refused.
func _run_edge_cases() -> void:
	var size := RESOLUTIONS[0]
	var prose := String(_samples["zh-CN"])
	L10n.set_locale("zh-CN")
	var plain := _line(prose, &"q", "Q")
	await _show(plain, [])
	var baseline := _snapshot()

	# A landscape portrait is capped at the width ratio and scaled as a whole.
	var wide := _line(prose, &"q", "Q")
	wide["portrait_profile"] = _profile(_wide_texture, CharacterProfile.PortraitSide.LEFT)
	await _show(wide, [])
	_check_portrait_layout("wide portrait", size, baseline, _wide_texture.get_size().aspect())
	var rect: Rect2 = _panel.get_portrait_report()["rect"]
	if rect.size.x > float(size.x) * _panel.portrait_max_width_ratio + TOLERANCE:
		_failures.append("wide portrait: %.0f px wide, over the width cap." % rect.size.x)

	# A hand-edited height ratio far out of range is clamped, never drawn off screen.
	var tall_profile := _profile(_tall_texture, CharacterProfile.PortraitSide.RIGHT)
	tall_profile.portrait_height_ratio = 4.0
	var tall := _line(prose, &"q", "Q")
	tall["portrait_profile"] = tall_profile
	await _show(tall, [])
	_check_portrait_layout("height ratio 4.0", size, baseline, _tall_texture.get_size().aspect())

	# A crop frames part of the figure; the drawn aspect follows the crop.
	var crop_profile := _profile(_tall_texture, CharacterProfile.PortraitSide.LEFT)
	crop_profile.portrait_crop = Rect2(0.2, 0.0, 0.6, 0.8)
	var cropped := _line(prose, &"q", "Q")
	cropped["portrait_profile"] = crop_profile
	await _show(cropped, [])
	_check_portrait_layout("cropped portrait", size, baseline, (600.0 * 0.6) / (1000.0 * 0.8))

	# A viewport too narrow for both: the band keeps its minimum width and the portrait
	# steps aside (status "no_room") instead of squeezing the text.
	await _resize(Vector2i(760, 720))
	var narrow := _line(prose, &"q", "Q")
	narrow["portrait_profile"] = _profile(_tall_texture, CharacterProfile.PortraitSide.LEFT)
	await _show(narrow, [])
	var report := _panel.get_portrait_report()
	var panel_rect: Rect2 = _panel.get_layout_report()["panel_rect"]
	if panel_rect.size.x < _panel.band_min_width - TOLERANCE or panel_rect.end.x > 760.0 + TOLERANCE:
		_failures.append("760x720: the band was squeezed or pushed off screen (%s)." % panel_rect)
	if bool(report["visible"]):
		var portrait_rect: Rect2 = report["rect"]
		_check_clear_of_text("760x720", portrait_rect)
		if absf(portrait_rect.size.x / portrait_rect.size.y - _tall_texture.get_size().aspect()) > 0.01:
			_failures.append("760x720: the portrait was stretched to %s." % portrait_rect)
	elif String(report["status"]) != "no_room":
		_failures.append("760x720: the portrait vanished with status %s." % report["status"])
	await _resize(size)
	L10n.set_locale("en")


## Clicking the portrait does nothing; clicking the band still continues.
func _run_click_case() -> void:
	var prose := String(_samples["en"])
	var line := _line(prose, &"q", "Q")
	line["portrait_profile"] = _profile(_tall_texture, CharacterProfile.PortraitSide.LEFT)
	await _show(line, [])
	var report := _panel.get_portrait_report()
	if not bool(report["visible"]):
		_failures.append("click case: no portrait to click.")
		return
	if int(report["mouse_filter"]) != Control.MOUSE_FILTER_IGNORE:
		_failures.append("click case: the portrait takes the mouse.")
	var portrait_rect: Rect2 = report["rect"]
	var band: Rect2 = _panel.get_layout_report()["panel_rect"]
	# A point on the figure that is clear of the band: left of it and above the wash.
	var point := Vector2(
		minf(portrait_rect.position.x + portrait_rect.size.x * 0.4, band.position.x - 12.0),
		maxf(portrait_rect.position.y + 20.0, band.position.y - 90.0)
	)
	if not portrait_rect.has_point(point) or band.grow(60.0).has_point(point):
		_failures.append("click case: could not find a point on the portrait clear of the band.")
		return
	_advance_count = 0
	await _click_at(point)
	var hovered := root.gui_get_hovered_control()
	if hovered != null and hovered.name == "Portrait":
		_failures.append("click case: the portrait is the hovered control.")
	if _advance_count != 0:
		_failures.append("click case: clicking the portrait advanced the dialogue.")
	var body := _panel.get_body_label()
	await _click_at(body.get_global_rect().get_center())
	if _advance_count != 1:
		_failures.append(
			"click case: clicking the band with a portrait up advanced %d time(s), expected 1."
			% _advance_count
		)


# --- Checks -------------------------------------------------------------------


func _check_no_portrait(label: String) -> void:
	var report := _panel.get_portrait_report()
	if bool(report["visible"]) or String(report["status"]) != "none":
		_failures.append("%s: a speaker without a portrait reports %s." % [label, report])
	var node := _panel.get_node("Portrait") as TextureRect
	if node.visible or node.texture != null:
		_failures.append("%s: the portrait node is still showing a texture." % label)


## Without a portrait the band is exactly where the panel always put it.
func _check_baseline_geometry(label: String, size: Vector2i, snapshot: Dictionary) -> void:
	var left := minf(float(size.x) * _panel.side_margin_ratio, _panel.side_margin_max)
	var width := clampf(
		float(size.x) * _panel.band_width_ratio, _panel.band_min_width, _panel.band_max_width
	)
	width = minf(width, float(size.x) - left * 2.0)
	var panel_rect: Rect2 = snapshot["panel"]
	if absf(panel_rect.position.x - left) > TOLERANCE or absf(panel_rect.size.x - width) > TOLERANCE:
		_failures.append(
			"%s: without a portrait the band is %s, expected x %.1f width %.1f."
			% [label, panel_rect, left, width]
		)
	if absf(panel_rect.end.y - (float(size.y) - _panel.bottom_margin)) > TOLERANCE:
		_failures.append("%s: without a portrait the band bottom moved (%s)." % [label, panel_rect])


func _check_portrait_layout(label: String, size: Vector2i, baseline: Dictionary, aspect: float) -> void:
	var report := _panel.get_portrait_report()
	if String(report["status"]) != "ok" or not bool(report["visible"]):
		_failures.append("%s: the portrait is not shown (%s)." % [label, report])
		return
	if int(report["mouse_filter"]) != Control.MOUSE_FILTER_IGNORE:
		_failures.append("%s: the portrait takes the mouse." % label)
	var rect: Rect2 = report["rect"]
	var viewport := Vector2(size)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		_failures.append("%s: the portrait has no size (%s)." % [label, rect])
		return
	if rect.position.x < -TOLERANCE or rect.position.y < -TOLERANCE \
			or rect.end.x > viewport.x + TOLERANCE or rect.end.y > viewport.y + TOLERANCE:
		_failures.append("%s: the portrait leaves the screen (%s in %s)." % [label, rect, viewport])
	# It enters from an edge: it stands on the bottom and touches its side.
	if absf(rect.end.y - viewport.y) > TOLERANCE:
		_failures.append("%s: the portrait does not stand on the bottom edge (%s)." % [label, rect])
	var touches_side := absf(rect.position.x) <= TOLERANCE or absf(rect.end.x - viewport.x) <= TOLERANCE
	if not touches_side:
		_failures.append("%s: the portrait floats away from the screen edge (%s)." % [label, rect])
	if absf(rect.size.x / rect.size.y - aspect) > 0.01:
		_failures.append(
			"%s: the portrait is drawn at aspect %.3f, the texture is %.3f."
			% [label, rect.size.x / rect.size.y, aspect]
		)
	if rect.size.x > viewport.x * _panel.portrait_max_width_ratio + TOLERANCE:
		_failures.append("%s: the portrait is wider than the cap (%s)." % [label, rect])
	_check_clear_of_text(label, rect)

	var layout := _panel.get_layout_report()
	var panel_rect: Rect2 = layout["panel_rect"]
	var base_panel: Rect2 = baseline["panel"]
	if panel_rect.position.x < -TOLERANCE or panel_rect.end.x > viewport.x + TOLERANCE \
			or panel_rect.position.y < -TOLERANCE or panel_rect.end.y > viewport.y + TOLERANCE:
		_failures.append("%s: the band leaves the screen (%s)." % [label, panel_rect])
	# At these sizes there is room for both, so the text column keeps its full width:
	# the band moves, it does not narrow.
	if panel_rect.size.x < base_panel.size.x - TOLERANCE:
		_failures.append(
			"%s: the band narrowed from %.0f to %.0f px although there was room."
			% [label, base_panel.size.x, panel_rect.size.x]
		)
	if int(layout["body_font_size"]) != _panel.body_size \
			or int(layout["speaker_font_size"]) != _panel.speaker_size:
		_failures.append("%s: the type size changed with a portrait." % label)
	if float(layout["covers_width"]) > 0.72 or float(layout["covers_height"]) > 0.66:
		_failures.append("%s: the band grew past its share of the screen." % label)
	var body_rect: Rect2 = layout["body_rect"]
	var content_height := float(layout["body_content_height"])
	if not bool(layout["body_scrolling"]) and content_height > body_rect.size.y + 2.0:
		_failures.append("%s: the body is clipped with a portrait." % label)
	if bool(layout["body_scrolling"]) and not bool(baseline["scrolling"]):
		_failures.append("%s: a portrait made a paragraph that fitted scroll." % label)
	if int(layout["choice_count"]) != int(baseline["choices"].size()):
		_failures.append("%s: the options changed with a portrait." % label)


## The portrait may sit under the band's padding, never under a word or an option.
func _check_clear_of_text(label: String, rect: Rect2) -> void:
	for path in [
		"Frame/Content/HeaderRow/SpeakerLabel",
		"Frame/Content/HeaderRow/RoleLabel",
		"Frame/Content/HeaderRow/SourceBadge",
		"Frame/Content/TitleLabel",
		"Frame/Content/BodyLabel",
		"Frame/Content/HintLabel",
	]:
		var node := _panel.get_node_or_null(path) as Control
		if node == null or not node.is_visible_in_tree():
			continue
		if rect.intersects(node.get_global_rect()):
			_failures.append(
				"%s: the portrait %s overlaps %s %s." % [label, rect, path, node.get_global_rect()]
			)
	for button in _panel.get_choice_buttons():
		if rect.intersects(button.get_global_rect()):
			_failures.append(
				"%s: the portrait %s overlaps option %s %s."
				% [label, rect, button.name, button.get_global_rect()]
			)


func _snapshot() -> Dictionary:
	var layout := _panel.get_layout_report()
	var choices: Array[Rect2] = []
	for button in _panel.get_choice_buttons():
		choices.append(button.get_global_rect())
	return {
		"panel": layout["panel_rect"],
		"body": layout["body_rect"],
		"frame": (_panel.get_node("Frame") as Control).get_global_rect(),
		"wash": (_panel.get_node("Wash") as Control).get_global_rect(),
		"speaker": (_panel.get_node("Frame/Content/HeaderRow/SpeakerLabel") as Control).get_global_rect(),
		"hint": (_panel.get_node("Frame/Content/HintLabel") as Control).get_global_rect(),
		"scrolling": bool(layout["body_scrolling"]),
		"choices": choices,
	}


func _compare(label: String, expected: Dictionary, actual: Dictionary) -> void:
	for key in ["panel", "body", "frame", "wash", "speaker", "hint"]:
		var a: Rect2 = expected[key]
		var b: Rect2 = actual[key]
		if not _rect_close(a, b):
			_failures.append("%s: %s moved from %s to %s." % [label, key, a, b])
	if bool(expected["scrolling"]) != bool(actual["scrolling"]):
		_failures.append("%s: body scrolling changed." % label)
	var expected_choices: Array = expected["choices"]
	var actual_choices: Array = actual["choices"]
	if expected_choices.size() != actual_choices.size():
		_failures.append("%s: %d options became %d." % [label, expected_choices.size(), actual_choices.size()])
		return
	for index in expected_choices.size():
		if not _rect_close(expected_choices[index], actual_choices[index]):
			_failures.append(
				"%s: option %d moved from %s to %s."
				% [label, index + 1, expected_choices[index], actual_choices[index]]
			)


func _rect_close(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= TOLERANCE and a.size.distance_to(b.size) <= TOLERANCE


# --- Helpers ------------------------------------------------------------------


## A plain generated texture: two flat tones split diagonally, so it is visibly an
## image in a debugger and obviously not a character. Never saved anywhere.
func _fixture(width: int, height: int) -> Texture2D:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.36, 0.30, 0.26, 1.0))
	image.fill_rect(Rect2i(0, 0, int(width * 0.5), int(height * 0.5)), Color(0.55, 0.42, 0.33, 1.0))
	return ImageTexture.create_from_image(image)


func _profile(texture: Texture2D, side: int) -> CharacterProfile:
	var profile := CharacterProfile.new()
	profile.character_id = PROBE_ID
	profile.display_name = "Probe"
	profile.portrait = texture
	profile.portrait_side = side as CharacterProfile.PortraitSide
	return profile


func _line(text: String, speaker_id: StringName, speaker_name: String) -> Dictionary:
	var role_key := "role.%s" % String(speaker_id)
	return {
		"conversation_id": &"portrait_probe",
		"node_id": &"probe",
		"speaker_id": speaker_id,
		"speaker_name": speaker_name,
		"speaker_role": L10n.t(role_key) if L10n.has_key(role_key) else "",
		"accent_color": Color(0.776, 0.733, 0.643, 1.0),
		"title": "",
		"text": text,
		"source": NarrativeEntry.Source.REPORTED,
		"badge": NarrativeEntry.badge_key_for(NarrativeEntry.Source.REPORTED),
		"subjective": false,
		"tags": PackedStringArray(),
	}


func _show(line: Dictionary, choices: Array) -> void:
	_panel.show_line(line)
	_panel.complete_reveal()
	if not choices.is_empty():
		_panel.set_choices(choices)
	# One frame to apply the width, one to measure, one to settle.
	await process_frame
	await process_frame
	await process_frame
	await process_frame


func _resize(size: Vector2i) -> void:
	root.size = size
	await process_frame
	await process_frame
	await process_frame


func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = position
	release.global_position = position
	root.push_input(release, true)
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
