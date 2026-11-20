class_name SettingsStore
extends RefCounted
## Where the player's preferences live, and the only place that says so.
##
## `Settings` (text, sound, display scale, controls) and `Loc` (the language) write to one
## file, `user://settings.cfg`, and they write to it independently: changing the volume and
## changing the language are different actions by different nodes. What they must not each
## own is the *path*, because a path written twice is a path that can be changed in one
## place and left behind in the other - the language preference and every other setting then
## end up in two files, and the next launch restores one of them.
##
## Two reasons this is a script rather than a constant in one of the two autoloads:
##
## - whichever node held it, the other would have to reach into that node for a string it
##   has no other business with, and `Loc` knowing about the settings manager (or the
##   reverse) is a dependency neither needs;
## - `Loc` is a smaller, older node than `Settings`, and a test that loads one without the
##   other should still be able to read the path.
##
## The read-modify-write discipline stays where it is, inside each owner: every write loads
## the file first and sets only the keys that owner owns, so a volume change never drops the
## language and the other way round. This class only answers "which file".
##
## The keys are named here too, next to the path, because a reader looking for where the
## language is stored should not have to read two autoloads to find it:

## The whole preferences file. One file, not one per subsystem.
const PATH := "user://settings.cfg"

## `[display] locale` - the language choice, owned by `Loc`. `Settings` never writes it and
## deliberately preserves it (`reset_to_defaults()` leaves it alone).
const SECTION_DISPLAY := "display"
const KEY_LOCALE := "locale"


## True when the file exists, whether or not it parses. A file that is there and does not
## parse is damage to report, not a first run (see `Settings.load_settings()`).
static func exists() -> bool:
	return FileAccess.file_exists(PATH)


## The file as it is now. A write path loads this, changes its own keys, and saves it, so a
## key another owner wrote survives. A missing file is not an error here: `ConfigFile` starts
## empty, which is exactly what a first run looks like.
static func open() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(PATH)
	return config


## Saves `config`. Returns the engine's error, so the caller can tell the player that the
## settings did not persist instead of believing they did.
static func write(config: ConfigFile) -> Error:
	return config.save(PATH)


## The value of `[section] key` when it is one of `allowed`; otherwise `fallback`, and a
## stored value that is not allowed is described in `problems`. A missing key is not a
## problem: it is a setting the player never changed.
static func read_choice(
	config: ConfigFile, section: String, key: String, allowed: Array[StringName],
	fallback: StringName, problems: Array[String]
) -> StringName:
	if not config.has_section_key(section, key):
		return fallback
	var value: Variant = config.get_value(section, key)
	if value is String or value is StringName:
		var choice := StringName(String(value))
		if allowed.has(choice):
			return choice
	problems.append("[%s] %s = %s is not one of %s" % [section, key, str(value), str(allowed)])
	return fallback


## A whole percentage, 0..100, from `[section] key`; `fallback` when it is missing or is
## not one, and a stored value that is not one is described in `problems`.
static func read_percent(
	config: ConfigFile, section: String, key: String, fallback: int, problems: Array[String]
) -> int:
	if not config.has_section_key(section, key):
		return fallback
	var value: Variant = config.get_value(section, key)
	if (value is int or value is float) and float(value) >= 0.0 and float(value) <= 100.0:
		return int(round(float(value)))
	problems.append("[%s] %s = %s is not a percentage" % [section, key, str(value)])
	return fallback
