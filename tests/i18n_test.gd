extends SceneTree
## Language layer tests: the two locale tables must stay in step, lookups must be
## safe, and the Loc autoload must persist and broadcast the player's choice.
##
## Nothing here touches content: dialogue and inspection text is covered by the
## content test, which compares the two languages node by node.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_PATH := "user://settings.cfg"

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 90.0, "i18n_test.gd")
	call_deferred("_run")


func _run() -> void:
	_reset_settings()
	L10n.reset_for_tests()
	var errors := L10n.load_tables()
	if not errors.is_empty():
		_failures.append("\n".join(errors))

	_check_profiles()
	_check_tables()
	_check_lookup()
	await _check_loc_autoload()

	L10n.reset_for_tests()
	Harness.finish(self, _failures, "the language tables and the Loc autoload behave.")


func _reset_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _check_profiles() -> void:
	if L10n.LOCALES != Locales.codes() or L10n.DEFAULT_LOCALE != Locales.DEFAULT_LOCALE:
		_failures.append("L10n does not use the locale registry.")
	for code: String in L10n.LOCALES:
		if L10n.normalize(code) != code or Locales.reading_cps(code) <= 0.0:
			_failures.append("Locale profile is not usable: %s." % code)
	if L10n.normalize("unknown") != L10n.DEFAULT_LOCALE:
		_failures.append("Unknown locale should fall back to the default.")
	if Locales.reading_cps("unknown") != Locales.DEFAULT_READING_CPS:
		_failures.append("Unknown reading speed should use the neutral fallback.")
	var playback := DialoguePlayback.new()
	for code: String in L10n.LOCALES + ["unknown"]:
		playback.begin_line("test", 90, false, code)
		var expected := clampf(
			DialoguePlayback.BASE_PAUSE + 90.0 / Locales.reading_cps(code),
			DialoguePlayback.MIN_PAUSE, DialoguePlayback.MAX_PAUSE
		)
		if not is_equal_approx(playback.auto_pause(), expected):
			_failures.append("Playback did not use the registry speed for %s." % code)
	# A temporary third language only needs one registry entry, not new branches in
	# normalization or playback. Do not add a real language without its content.
	var profiles := Locales.PROFILES.duplicate(true)
	profiles["fr"] = {"reading_cps": 19.0, "prefixes": ["fr"], "aliases": []}
	if not Locales.codes(profiles).has("fr") or Locales.normalize("fr-CA", profiles) != "fr":
		_failures.append("The temporary language was not discovered or normalized.")
	if Locales.reading_cps("fr", profiles) != 19.0:
		_failures.append("The temporary language's reading speed was not used.")
	profiles["fr"].erase("reading_cps")
	if Locales.reading_cps("fr", profiles) != Locales.DEFAULT_READING_CPS:
		_failures.append("A missing reading speed should use the neutral fallback.")


func _check_tables() -> void:
	for locale in L10n.LOCALES:
		if L10n.keys(locale).is_empty():
			_failures.append("Locale '%s' has no strings." % locale)
		for key in L10n.keys(locale):
			if L10n.t_for(key, locale).strip_edges().is_empty():
				_failures.append("%s: '%s' is empty." % [locale, key])
	var reference := L10n.keys(L10n.DEFAULT_LOCALE)
	for locale in L10n.LOCALES:
		if L10n.keys(locale) != reference:
			_failures.append("Locale '%s' does not define the same keys as %s." % [locale, L10n.DEFAULT_LOCALE])


func _check_lookup() -> void:
	L10n.set_locale("en")
	var english := L10n.t("ui.language_switch", {"name": "简体中文"})
	if not english.contains("简体中文"):
		_failures.append("String placeholders are not substituted: '%s'." % english)
	if not L10n.set_locale("zh-CN"):
		_failures.append("Switching to zh-CN reported no change.")
	if L10n.t("prompt.door_try") == english:
		_failures.append("The door prompt did not change language.")
	if L10n.objective_text("objective.check_bag").is_empty():
		_failures.append("Objective keys do not resolve to text.")
	if L10n.objective_text("") != "":
		_failures.append("An empty objective key should render as nothing.")
	if L10n.normalize("zh") != "zh-CN" or L10n.normalize("en-GB") != "en":
		_failures.append("Locale codes are not normalized.")
	if not L10n.has_key("prompt.talk"):
		_failures.append("A known key is reported missing.")
	if L10n.t("definitely.not.a.key") != "[[definitely.not.a.key]]":
		_failures.append("A missing key does not render as a visible marker.")
	L10n.set_locale("en")


func _check_loc_autoload() -> void:
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if loc == null:
		_failures.append("The Loc autoload could not be created.")
		return
	await process_frame
	if loc.get_locale() != L10n.current:
		_failures.append("Loc does not report the current locale.")
	var signals: Array[String] = []
	loc.locale_changed.connect(func(code: String) -> void: signals.append(code))
	if not loc.set_locale("zh-CN"):
		_failures.append("Loc refused a supported locale.")
	if signals != ["zh-CN"]:
		_failures.append("Loc did not emit exactly one locale_changed signal.")
	if not loc.toggle():
		_failures.append("Loc could not toggle back.")
	if loc.get_locale() != "en":
		_failures.append("Toggling did not return to English.")
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_failures.append("The language choice was not saved.")
	elif String(config.get_value("display", "locale", "")) != "en":
		_failures.append("The saved locale is not the one that was chosen.")
	_reset_settings()
