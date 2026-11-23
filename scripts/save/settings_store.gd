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
## language and the other way round. This class owns the filename and staging procedure.
##
## The keys are named here too, next to the path, because a reader looking for where the
## language is stored should not have to read two autoloads to find it:

## The whole preferences file. One file, not one per subsystem.
const PATH := "user://settings.cfg"
const BACKUP_PATH := PATH + ".bak"

## `[display] locale` - the language choice, owned by `Loc`. `Settings` never writes it and
## deliberately preserves it (`reset_to_defaults()` leaves it alone).
const SECTION_DISPLAY := "display"
const KEY_LOCALE := "locale"


static func exists() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(BACKUP_PATH)


## An interrupted fallback swap may have moved the old file aside without publishing
## the new one. Both owners must read the same fallback before changing their keys.
static func read(config: ConfigFile) -> Error:
	var path := BACKUP_PATH if not FileAccess.file_exists(PATH) and exists() else PATH
	return config.load(path)


## A missing file is a first run: the ConfigFile starts empty.
static func open() -> ConfigFile:
	var config := ConfigFile.new()
	read(config)
	return config


static func write(config: ConfigFile) -> Error:
	# Never reuse a fixed staging name: a remnant from another run (even a directory)
	# must not make every subsequent settings change fail.
	var stage := PATH + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var error := config.save(stage)
	if error == OK:
		var staged := ConfigFile.new()
		error = staged.load(stage)
		if error == OK and not _same_values(config, staged):
			error = ERR_FILE_CORRUPT
	if error != OK:
		push_warning("SettingsStore: could not stage or verify preferences (%s)." % error_string(error))
	else:
		error = _publish(stage, DirAccess.rename_absolute)
		if error != OK:
			push_warning("SettingsStore: could not replace preferences (%s)." % error_string(error))
	if error != OK and FileAccess.file_exists(stage):
		DirAccess.remove_absolute(stage)
	return error


## Verify each key and its serialized value, not their order in the engine's maps.
static func _same_values(expected: ConfigFile, staged: ConfigFile) -> bool:
	var sections := expected.get_sections()
	if sections.size() != staged.get_sections().size():
		return false
	for section: String in sections:
		var keys := expected.get_section_keys(section)
		if not staged.has_section(section) or keys.size() != staged.get_section_keys(section).size():
			return false
		for key: String in keys:
			if not staged.has_section_key(section, key) or \
					var_to_str(expected.get_value(section, key)) != var_to_str(staged.get_value(section, key)):
				return false
	return true


## Always rename onto a vacant name. Some engines/filesystems cannot replace an
## existing file, or delete it before moving the new one. Preserve the old file first.
## `move_file` lets the regression test fail exactly one step of the swap.
static func _publish(stage: String, move_file: Callable) -> Error:
	var moved_previous := FileAccess.file_exists(PATH)
	if moved_previous:
		if FileAccess.file_exists(BACKUP_PATH):
			# A previous swap reached publish but did not clean up. Only retire that
			# backup if the preferred file is itself readable.
			if ConfigFile.new().load(PATH) != OK:
				return ERR_FILE_CORRUPT
			var cleanup := DirAccess.remove_absolute(BACKUP_PATH)
			if cleanup != OK:
				return cleanup
		var aside: Error = move_file.call(PATH, BACKUP_PATH)
		if aside != OK:
			return aside
	var error: Error = move_file.call(stage, PATH)
	if error != OK:
		if moved_previous and move_file.call(BACKUP_PATH, PATH) != OK:
			push_warning("SettingsStore: previous preferences remain in settings.cfg.bak.")
		return error
	if FileAccess.file_exists(BACKUP_PATH) and DirAccess.remove_absolute(BACKUP_PATH) != OK:
		push_warning("SettingsStore: preferences saved; old backup could not be removed.")
	return OK


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
