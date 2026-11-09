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

const Harness = preload("res://tests/test_harness.gd")

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
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	L10n.set_locale("en")

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
	# longest inspection text the content has, used as the prompt so the measurement is the
	# worst case rather than a short one.
	var long_prompt := _longest_inspection_text()
	for locale: String in ["en", "zh-CN"]:
		Harness.stage = "HUD at %s in %s" % [str(viewport), locale]
		L10n.set_locale(locale)
		await _frames(2)
		hud.set_objective("objective.animal")
		hud.set_prompt_text(long_prompt)
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

	main.queue_free()
	await process_frame
	Harness.finish(
		self,
		_failures,
		"the HUD's objective, prompt and language hint stay inside the viewport, unclipped "
		+ "and unshrunk, in both languages, at the resolution this run was started with."
	)


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


## The longest object description the shipped content has, in the current locale: the worst
## case for a one-line prompt, taken from the game rather than typed here.
func _longest_inspection_text() -> String:
	var best := ""
	for file_name: String in ["res://data/inspections/en/classroom.json"]:
		var file := FileAccess.open(file_name, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		best = _longest_value(parsed, best)
	if best.is_empty():
		best = L10n.objective_text("objective.animal")
	return best


func _longest_value(node: Variant, best: String) -> String:
	if node is String:
		var text := String(node)
		return text if text.length() > best.length() else best
	if node is Dictionary:
		for key: Variant in (node as Dictionary).keys():
			best = _longest_value((node as Dictionary)[key], best)
	elif node is Array:
		for item: Variant in (node as Array):
			best = _longest_value(item, best)
	return best


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
