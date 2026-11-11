extends SceneTree
## The HUD at the three window sizes the game is expected to run in.
##
## `tests/dialogue_layout_test.gd` already measures the reading surface at 1280x720,
## 1600x900 and 1920x1080. This covers the other half of the interface — the objective
## line, the interaction prompt and the language hint — inside the real `GameUI`, with the
## shipped strings in both languages, at whichever resolution the process was started with:
##
## - every label is inside the viewport, not a pixel off the right or bottom edge;
## - no label is clipped: the prompt and the objective show all of their lines, and their
##   height is at least one line;
## - the type is not shrunk to make room: the configured font size is the same at every
##   resolution (the layouts have to survive 1280x720 by fitting, not by shrinking);
## - the Chinese strings — which are wider per character — fit where the English ones do.
##
## Run it at each size:
##
##     godot --headless --resolution 1280x720 --script res://tests/hud_layout_test.gd
##
## CI does exactly that three times (`hud_layout_720`, `hud_layout_900`, `hud_layout_1080`).
##
## Then the same measurements again at the **largest text size** (issue #62), through the
## real `Settings` node, plus the interface that only exists since then - the pause menu,
## the settings screen with every row, the new-game question, the end card with its
## buttons and the title screen - in both languages: every label and button inside the
## viewport (or, in the settings list, inside the scrolling area's width), no button
## narrower than its own text, and the type at the size the setting asks for.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"

## The sizes the game is expected to run in. A run whose viewport is none of these is
## reported, not silently accepted: a test that always measures the same size proves nothing.
const VERIFIED_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)
]

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "hud_layout_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	# A save left behind by an earlier check in this job would be resumed at boot and
	# this layout would be measured in whatever room that run ended in (ADR 0005 §7).
	# After the autoloads, so the node that owns the file exists.
	Harness.clear_session_state(self)
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	L10n.set_locale("en")
	# Before main.tscn, so every interface node connects to it as it would in the game.
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	var main := packed.instantiate()
	var sequence := main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(main)
	await _frames(3)

	var ui := main.get_node_or_null("GameUI")
	var hud := main.get_node_or_null("GameUI/HUD") as GameHud
	if ui == null or hud == null:
		Harness.finish(self, ["GameUI did not expose its HUD."], "")
		return
	if sequence != null:
		sequence.call("allow_player_control")
	await _frames(2)

	# The size this run measures. A headless display server does not honour `--resolution`,
	# so the root window is sized here instead: measuring whatever size the runner happened
	# to have would be a test that proves nothing about 1280x720.
	var target := _expected_resolution()
	if target == Vector2i.ZERO:
		target = Vector2i(1600, 900)
	root.min_size = Vector2i.ZERO
	root.size = target
	await _frames(3)
	var viewport := root.get_visible_rect().size
	print("hud layout: viewport %s, verified sizes %s" % [str(viewport), str(VERIFIED_SIZES)])
	_expect(
		VERIFIED_SIZES.has(Vector2i(viewport)),
		"This run is not at one of the verified sizes: %s." % str(viewport)
	)
	_expect(
		Vector2i(viewport) == target,
		"The viewport is %s; it was set to %s and the labels would be measured at the "
		% [str(viewport), str(target)]
		+ "wrong size."
	)

	# The shipped strings, not invented ones: the objective key the story sets, and the
	# longest prompt the content actually asks the HUD to print. The prompt line is a short
	# contextual label ("Look", "Open"); the long paragraphs belong to the dialogue panel,
	# which `tests/dialogue_layout_test.gd` measures at these same three sizes.
	await _measure_hud(main, hud, viewport, "standard")

	# --- The largest text size -------------------------------------------------
	if settings == null:
		_failures.append("The Settings autoload could not be created.")
	else:
		var prompt_label := _label(main, "GameUI/HUD/PromptLabel")
		var standard_size := prompt_label.get_theme_font_size(&"font_size") if prompt_label != null else 0
		settings.call("set_text_size", &"largest")
		await _frames(3)
		var factor := float(settings.call("text_scale"))
		_expect(factor >= 1.25, "The largest text size scales by only %.2f." % factor)
		await _measure_hud(main, hud, viewport, "largest")
		if prompt_label != null:
			_expect(
				prompt_label.get_theme_font_size(&"font_size") > standard_size,
				"At the largest size the prompt is still %d px (standard %d px)."
				% [prompt_label.get_theme_font_size(&"font_size"), standard_size]
			)
		await _measure_menus(main, viewport, factor)
		await _measure_title(viewport, factor)
		settings.call("reset_to_defaults")

	main.queue_free()
	await process_frame
	Harness.finish(
		self,
		_failures,
		"the HUD's objective, prompt and language hint stay inside the viewport, unclipped "
		+ "and unshrunk, in both languages, at the resolution this run was started with; "
		+ "at the largest text size so do the HUD, pause menu, settings screen, new-game "
		+ "question, end card and title screen."
	)


func _measure_hud(main: Node, hud: GameHud, viewport: Vector2, size_tag: String) -> void:
	for locale: String in ["en", "zh-CN"]:
		Harness.stage = "HUD (%s text) at %s in %s" % [size_tag, str(viewport), locale]
		L10n.set_locale(locale)
		await _frames(2)
		hud.set_objective("objective.animal")
		hud.set_prompt_text(_longest_prompt(locale))
		await _frames(4)
		var objective := _label(main, "GameUI/HUD/ObjectiveLabel")
		var prompt := _label(main, "GameUI/HUD/PromptLabel")
		var language := _label(main, "GameUI/HUD/LanguageLabel")
		_expect_all_inside("objective", objective, viewport, locale)
		_expect_all_inside("prompt", prompt, viewport, locale)
		_expect_all_inside("language hint", language, viewport, locale)
		_expect(
			objective != null and not objective.text.strip_edges().is_empty(),
			"The objective line is empty in %s; the layout was measured on nothing." % locale
		)
		_expect(
			prompt != null and not prompt.text.strip_edges().is_empty(),
			"The prompt is empty in %s; the layout was measured on nothing." % locale
		)
		_expect(
			objective != null and objective.get_visible_line_count() >= objective.get_line_count(),
			"The objective line is clipped in %s (%d of %d lines fit at %s)."
			% [
				locale,
				objective.get_visible_line_count() if objective != null else 0,
				objective.get_line_count() if objective != null else 0,
				str(viewport)
			]
		)
		_expect(
			prompt != null and prompt.get_visible_line_count() >= prompt.get_line_count(),
			"The prompt is clipped in %s (%d of %d lines fit at %s)."
			% [
				locale,
				prompt.get_visible_line_count() if prompt != null else 0,
				prompt.get_line_count() if prompt != null else 0,
				str(viewport)
			]
		)
		# No shrinking to fit: the same configured size the theme carries, at every window
		# size. If a layout only fits at 1280x720 because the type got smaller, it is the
		# layout that is wrong.
		if prompt != null:
			_expect(
				prompt.get_theme_font_size(&"font_size") >= 14,
				"The prompt type is %d px in %s: the interface is being shrunk to fit."
				% [prompt.get_theme_font_size(&"font_size"), locale]
			)
			_expect(
				prompt.size.y >= float(prompt.get_line_height()),
				"The prompt is %.0f px tall, shorter than one line (%d px)."
				% [prompt.size.y, prompt.get_line_height()]
			)
		hud.clear_prompt()
		await _frames(1)



## The pause menu, the settings screen, the new-game question and the end card, at the
## largest size, in both languages.
func _measure_menus(main: Node, viewport: Vector2, factor: float) -> void:
	var menu := main.get_node_or_null("PauseMenu") as PauseMenu
	var ui := main.get_node_or_null("GameUI") as GameUI
	if menu == null or ui == null:
		_failures.append("main.tscn has no pause menu or GameUI to measure.")
		return
	for locale: String in ["en", "zh-CN"]:
		var tag := "%s at %s in %s, largest text" % ["%s", str(viewport), locale]
		Harness.stage = tag % "menus"
		L10n.set_locale(locale)
		await _frames(2)
		menu.open()
		await _frames(4)
		_expect_controls_fit(menu, viewport, tag % "pause menu")
		var entry := menu.get_entry(&"resume")
		if entry != null:
			_expect(
				entry.get_theme_font_size(&"font_size") == UiTextScale.scaled(MenuStyle.ENTRY_SIZE, factor),
				"%s: the entries are %d px, not the largest size."
				% [tag % "pause menu", entry.get_theme_font_size(&"font_size")]
			)
		var panel := menu.get_settings_panel()
		panel.open()
		await _frames(4)
		_expect_controls_fit(panel, viewport, tag % "settings screen")
		_expect(
			panel.get_row_ids().size() >= 20,
			"%s: only %d rows were built." % [tag % "settings screen", panel.get_row_ids().size()]
		)
		# Scroll to the end so the last rows are laid out and measured too.
		var scroll := panel.get_scroll()
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _frames(2)
		_expect_controls_fit(panel, viewport, tag % "settings screen, scrolled")
		panel.close()
		await _frames(2)
		menu.activate(&"new_game")
		await _frames(3)
		_expect(menu.get_confirm().visible, "%s: New game did not ask." % (tag % "pause menu"))
		_expect_controls_fit(menu.get_confirm(), viewport, tag % "new-game question")
		menu.get_confirm().get_cancel_button().pressed.emit()
		await _frames(2)
		menu.close()
		await _frames(2)
		ui.end_card.present(L10n.t("end.slice.title"), L10n.t("end.slice.body"), L10n.t("ui.end_hint"))
		ui.end_card.modulate = Color.WHITE
		await _frames(4)
		_expect(ui.end_card.has_actions(), "%s: the end card has no buttons." % (tag % "end card"))
		_expect_controls_fit(ui.end_card, viewport, tag % "end card")
		ui.end_card.hide()
		await _frames(1)
	var save := root.get_node_or_null(^"Save")
	if save != null:
		save.delete_save()


func _measure_title(viewport: Vector2, factor: float) -> void:
	var packed: PackedScene = load("res://scenes/ui/title_screen.tscn")
	if packed == null:
		_failures.append("title_screen.tscn could not be loaded.")
		return
	var title := packed.instantiate() as TitleScreen
	root.add_child(title)
	await _frames(4)
	for locale: String in ["en", "zh-CN"]:
		var tag := "title screen at %s in %s, largest text" % [str(viewport), locale]
		Harness.stage = tag
		L10n.set_locale(locale)
		await _frames(3)
		_expect_controls_fit(title, viewport, tag)
		var entry := title.get_entry(&"new_game")
		_expect(
			entry != null
			and entry.get_theme_font_size(&"font_size") == UiTextScale.scaled(MenuStyle.ENTRY_SIZE, factor),
			"%s: the entries are not at the largest size." % tag
		)
	title.queue_free()
	await _frames(2)


## Every visible label and button under `node` is inside the viewport - or, inside a
## scrolling list, inside its width - and no button is narrower than its own text.
func _expect_controls_fit(node: Node, viewport: Vector2, tag: String) -> void:
	var measured := 0
	for control: Control in _visible_text_controls(node):
		measured += 1
		var box := control.get_global_rect()
		var what := "%s '%s'" % [control.name, _short_text(control)]
		var scroll := _scroll_parent(control)
		if scroll != null:
			var area := scroll.get_global_rect()
			_expect(
				box.position.x >= area.position.x - 0.5 and box.end.x <= area.end.x + 0.5,
				"%s: %s spills out of the list sideways (%s in %s)." % [tag, what, str(box), str(area)]
			)
		else:
			_expect(
				box.position.x >= -0.5 and box.position.y >= -0.5
				and box.end.x <= viewport.x + 0.5 and box.end.y <= viewport.y + 0.5,
				"%s: %s runs off the %s viewport (%s)." % [tag, what, str(viewport), str(box)]
			)
		var needed := control.get_combined_minimum_size()
		_expect(
			box.size.x + 0.5 >= needed.x and box.size.y + 0.5 >= needed.y,
			"%s: %s is %s, smaller than its text needs (%s)." % [tag, what, str(box.size), str(needed)]
		)
		var label := control as Label
		if label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			_expect(
				label.get_visible_line_count() >= label.get_line_count(),
				"%s: %s shows %d of %d lines." % [
					tag, what, label.get_visible_line_count(), label.get_line_count()
				]
			)
	_expect(measured > 0, "%s: nothing visible was measured." % tag)


func _visible_text_controls(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in node.get_children():
		var control := child as Control
		if control != null and not control.is_visible_in_tree():
			continue
		if child is Label or child is Button:
			if not String(child.get("text")).strip_edges().is_empty():
				out.append(control)
		out.append_array(_visible_text_controls(child))
	return out


func _scroll_parent(control: Control) -> ScrollContainer:
	var walk := control.get_parent()
	while walk != null:
		if walk is ScrollContainer:
			return walk as ScrollContainer
		walk = walk.get_parent()
	return null


func _short_text(control: Control) -> String:
	var text := String(control.get("text")).replace("\n", " ")
	return text.substr(0, 24)


func _expect_all_inside(what: String, label: Label, viewport: Vector2, locale: String) -> void:
	if label == null:
		_failures.append("The %s label is missing in %s." % [what, locale])
		return
	_expect(label.visible, "The %s is not visible in %s." % [what, locale])
	var box := label.get_global_rect()
	_expect(
		box.size.x > 0.0 and box.size.y > 0.0,
		"The %s has no size in %s (%s)." % [what, locale, str(box.size)]
	)
	_expect(
		box.position.x >= -0.5 and box.position.y >= -0.5,
		"The %s starts outside the viewport in %s at %s." % [what, locale, str(box.position)]
	)
	_expect(
		box.end.x <= viewport.x + 0.5 and box.end.y <= viewport.y + 0.5,
		"The %s runs off the %s viewport in %s (ends at %s)."
		% [what, str(viewport), locale, str(box.end)]
	)


func _label(main: Node, path: String) -> Label:
	return main.get_node_or_null(path) as Label


## The `--resolution WxH` the process was started with, or zero when it was not passed.
func _expected_resolution() -> Vector2i:
	var args := OS.get_cmdline_args()
	for index in args.size():
		if args[index] != "--resolution" or index + 1 >= args.size():
			continue
		var parts := String(args[index + 1]).split("x")
		if parts.size() != 2:
			return Vector2i.ZERO
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## The longest `prompt` string the shipped inspections contain, in `locale`: the worst case
## for the prompt line, read from the game's own content rather than typed here.
func _longest_prompt(locale: String) -> String:
	var best := ""
	var chapters: Array[String] = InspectionLibrary.CHAPTERS
	for chapter: String in chapters:
		var path := InspectionLibrary.chapter_path(locale, chapter)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		best = _longest_prompt_in(parsed, best)
	if best.is_empty():
		best = L10n.objective_text("objective.animal")
	return best


func _longest_prompt_in(node: Variant, best: String) -> String:
	if node is Dictionary:
		var dictionary := node as Dictionary
		if dictionary.has("prompt") and dictionary["prompt"] is String:
			var prompt := String(dictionary["prompt"])
			if prompt.length() > best.length():
				best = prompt
		for key: Variant in dictionary.keys():
			best = _longest_prompt_in(dictionary[key], best)
	elif node is Array:
		for item: Variant in (node as Array):
			best = _longest_prompt_in(item, best)
	return best


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
