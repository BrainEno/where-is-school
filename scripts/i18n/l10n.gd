class_name L10n
extends RefCounted
## Locale table and string lookup for everything the interface itself says.
##
## Content (dialogue lines, inspection descriptions) is *not* in here: that lives
## in data/dialogue/<locale>/ and data/inspections/<locale>/ so a writer can edit
## prose without touching a single identifier. This class only holds the short
## strings the UI generates: hints, badges, prompts, objective labels.
##
## Why a static class and not an autoload: headless test runs (`--script`) do not
## create autoloads, and every screen must still be able to resolve a string. The
## signal-backed part (persisting the choice and telling the UI to redraw) lives
## in scripts/i18n/loc.gd, which is the autoload `Loc`.

const LOCALES: Array[String] = ["en", "zh-CN"]
const DEFAULT_LOCALE := "en"
const TABLE_DIR := "res://data/locale"
const FORMAT_VERSION := 1

## The locale currently used for display. Readable from anywhere.
static var current: String = DEFAULT_LOCALE

static var _tables: Dictionary = {}
static var _names: Dictionary = {}
static var _errors: Array[String] = []
static var _loaded: bool = false
static var _missing_reported: Dictionary = {}


static func table_path(locale: String) -> String:
	return "%s/%s.json" % [TABLE_DIR, normalize(locale)]


## Returns a supported locale code, or the default one for anything unknown.
static func normalize(locale: String) -> String:
	var code := locale.strip_edges()
	for candidate in LOCALES:
		if code == candidate:
			return candidate
	# "zh", "zh_CN", "zh-Hans" and "cn" all mean the same table for now.
	var lowered := code.to_lower()
	if lowered.begins_with("zh") or lowered == "cn":
		return "zh-CN"
	if lowered.begins_with("en"):
		return "en"
	return DEFAULT_LOCALE


static func is_supported(locale: String) -> bool:
	return LOCALES.has(locale.strip_edges())


## Loads every locale table once. Returns the accumulated errors (empty is good);
## a missing or malformed table is never fatal for the game, it just falls back.
static func load_tables() -> Array[String]:
	if _loaded:
		return _errors
	_loaded = true
	_errors.clear()
	for locale in LOCALES:
		var path := table_path(locale)
		if not FileAccess.file_exists(path):
			_errors.append("Locale file not found: %s" % path)
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_errors.append("Locale file could not be opened: %s" % path)
			continue
		var json := JSON.new()
		var parse_error := json.parse(file.get_as_text())
		file.close()
		if parse_error != OK:
			_errors.append(
				"%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
			)
			continue
		if not (json.data is Dictionary):
			_errors.append("%s: root value must be an object." % path)
			continue
		var data: Dictionary = json.data
		var version := int(data.get("format_version", 0))
		if version != FORMAT_VERSION:
			_errors.append("%s: format_version %d is not supported (expected %d)." % [path, version, FORMAT_VERSION])
			continue
		var declared := String(data.get("locale", ""))
		if declared != locale:
			_errors.append("%s: declares locale '%s' but is stored as '%s'." % [path, declared, locale])
		var raw_strings: Variant = data.get("strings")
		if not (raw_strings is Dictionary):
			_errors.append("%s: 'strings' must be an object." % path)
			continue
		var strings: Dictionary = {}
		for key: Variant in (raw_strings as Dictionary).keys():
			strings[String(key)] = String((raw_strings as Dictionary)[key])
		_tables[locale] = strings
		_names[locale] = String(data.get("name", locale))
	_errors.append_array(_compare_keys())
	return _errors


## Every locale must define exactly the same keys, otherwise a language switch
## silently drops a label. Reported as an error instead.
static func _compare_keys() -> Array[String]:
	var problems: Array[String] = []
	if _tables.size() < 2:
		return problems
	var reference_locale: String = _tables.keys()[0]
	var reference: Dictionary = _tables[reference_locale]
	for locale: String in _tables.keys():
		if locale == reference_locale:
			continue
		var table: Dictionary = _tables[locale]
		for key: String in reference.keys():
			if not table.has(key):
				problems.append(
					"%s: missing key '%s' (present in %s)." % [table_path(locale), key, reference_locale]
				)
		for key: String in table.keys():
			if not reference.has(key):
				problems.append(
					"%s: key '%s' does not exist in %s." % [table_path(locale), key, reference_locale]
				)
	return problems


static func errors() -> Array[String]:
	load_tables()
	return _errors


static func available_locales() -> Array[String]:
	return LOCALES


## Self-name of the locale ("简体中文"), so the switch hint never shows a
## translated name of a language the player cannot read.
static func locale_name(locale: String = "") -> String:
	load_tables()
	var code := normalize(locale if not locale.is_empty() else current)
	return String(_names.get(code, code))


static func other_locale() -> String:
	load_tables()
	var index := LOCALES.find(current)
	return LOCALES[(index + 1) % LOCALES.size()]


## Switches the display language. Returns true when something changed.
static func set_locale(locale: String) -> bool:
	load_tables()
	if not is_supported(locale):
		push_error("L10n: unsupported locale '%s'." % locale)
		return false
	var code := normalize(locale)
	if code == current:
		return false
	current = code
	return true


static func has_key(key: String, locale: String = "") -> bool:
	load_tables()
	var code := normalize(locale if not locale.is_empty() else current)
	var table: Dictionary = _tables.get(code, {})
	return table.has(key)


static func keys(locale: String) -> Array[String]:
	load_tables()
	var table: Dictionary = _tables.get(normalize(locale), {})
	var result: Array[String] = []
	for key: Variant in table.keys():
		result.append(String(key))
	result.sort()
	return result


## Looks up `key` and substitutes `{name}`-style placeholders from `args`.
## A missing key renders as [[key]] and reports itself once, so a gap shows up in
## a screenshot instead of turning into an empty label.
static func t(key: String, args: Dictionary = {}) -> String:
	load_tables()
	if not is_supported(current):
		current = DEFAULT_LOCALE
	var text := _lookup(current, key)
	if text.is_empty() and not has_key(key, current):
		var fallback := _lookup(DEFAULT_LOCALE, key)
		if not _missing_reported.has(key):
			_missing_reported[key] = true
			push_warning("L10n: missing key '%s' in locale '%s'." % [key, current])
		if not fallback.is_empty():
			text = fallback
		else:
			return "[[%s]]" % key
	for arg_key: Variant in args.keys():
		text = text.replace("{%s}" % String(arg_key), str(args[arg_key]))
	return text


## Looks up a key in a specific locale without switching the current one. Used by
## the tests and by tools that compare the two tables.
static func t_for(key: String, locale: String) -> String:
	load_tables()
	return _lookup(normalize(locale), key)


## Convenience for objective keys: an objective is stored as a key in GameState,
## and this resolves it for display. An unknown objective shows as [[key]].
static func objective_text(objective_key: String) -> String:
	if objective_key.strip_edges().is_empty():
		return ""
	return t(objective_key)


static func _lookup(locale: String, key: String) -> String:
	var table: Dictionary = _tables.get(normalize(locale), {})
	return String(table.get(key, ""))


## Test hook: forget every loaded table so a test can reload from disk.
static func reset_for_tests() -> void:
	_tables.clear()
	_names.clear()
	_errors.clear()
	_loaded = false
	_missing_reported.clear()
	current = DEFAULT_LOCALE
