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
## The swap publishes by rename onto a name that is free. Every name it may leave behind -
## the preferred `settings.cfg.bak` and the unique ones it falls back to - is found by
## pattern rather than assumed, because a leftover nobody can remove used to refuse every
## later settings change (#394), and a refused step is named in the report so the settings
## screen can say what failed instead of only "not saved".
##
## The keys are named here too, next to the path, because a reader looking for where the
## language is stored should not have to read two autoloads to find it:

## The whole preferences file. One file, not one per subsystem.
const PATH := "user://settings.cfg"
const BACKUP_PATH := PATH + ".bak"

## Every leftover this system may leave beside the file: the preferred backup name and the
## unique ones `_free_backup_name()` falls back to. They are matched by name, never by a
## single fixed path, because a leftover is exactly the thing that must not be able to
## wedge the next write (issue #394).
const LEFTOVER_PREFIX := "settings.cfg."
const LEFTOVER_SUFFIX := ".bak"
## The tag that marks a unique leftover as ours: `Crypto.generate_random_bytes(HEX_BYTES)`
## in hex, which is what `_free_backup_name()` and `write()` both build their names from.
const HEX_BYTES := 6
const HEX_TAG_LENGTH := HEX_BYTES * 2
## The stage name gets its own longer tag: it is not looked up by name, and a collision with
## a remnant of an earlier run would be resolved only by chance.
const STAGE_BYTES := 12
const HEX_DIGITS := "0123456789abcdef"

## `[display] locale` - the language choice, owned by `Loc`. `Settings` never writes it and
## deliberately preserves it (`reset_to_defaults()` leaves it alone).
const SECTION_DISPLAY := "display"
const KEY_LOCALE := "locale"


static func exists() -> bool:
	return FileAccess.file_exists(PATH) or not leftovers().is_empty()


## The preferences a caller should read: the file, or - when it is missing or unreadable -
## the newest leftover an interrupted swap left behind. Both owners must read the same
## thing before changing their keys, or one of them writes over the other's idea of the file.
static func read(config: ConfigFile) -> Error:
	if not FileAccess.file_exists(PATH):
		return _read_copy(config)
	var error := config.load(PATH)
	return OK if error == OK else _read_copy(config)


## The copy an interrupted swap left behind, newest first: a half-finished swap should restore
## what it was about to publish, not an older one. The last resort is the missing or unreadable
## file itself, so the caller still sees the error a first run or a corrupt file means.
static func _read_copy(config: ConfigFile) -> Error:
	for path: String in leftovers():
		if FileAccess.file_exists(path) and config.load(path) == OK:
			return OK
	return config.load(PATH)


## A missing file is a first run: the ConfigFile starts empty.
static func open() -> ConfigFile:
	var config := ConfigFile.new()
	read(config)
	return config


## Publish `config`, naming the step of any failure in `report` so the settings screen can
## say which part of the swap the machine refused instead of only "it did not save".
static func write(config: ConfigFile, report: Dictionary = {}) -> Error:
	report.clear()
	# Never reuse a fixed staging name: a remnant from another run (even a directory)
	# must not make every subsequent settings change fail.
	var stage := PATH + ".tmp-" + Crypto.new().generate_random_bytes(STAGE_BYTES).hex_encode()
	var error := config.save(stage)
	if error != OK:
		error = _refuse(report, "write staging file", error)
	else:
		var staged := ConfigFile.new()
		error = staged.load(stage)
		if error != OK:
			error = _refuse(report, "verify staged preferences", error)
		elif not _same_values(config, staged):
			error = _refuse(report, "verify staged preferences", ERR_FILE_CORRUPT)
		else:
			error = _publish(stage, DirAccess.rename_absolute, report)
			if error == OK:
				error = _confirm(config, report)
	if error != OK and FileAccess.file_exists(stage):
		DirAccess.remove_absolute(stage)
	return error


## The leftovers of earlier swaps, newest first: `read()` takes the first of them that parses,
## and every one of them is retired once a published file has been read back. Timestamps are
## whole seconds, so a tie breaks by name and the order stays the same on every run.
static func leftovers() -> PackedStringArray:
	var directory := DirAccess.open("user://")
	if directory == null:
		return PackedStringArray()
	var found: Array[Dictionary] = []
	for name: String in directory.get_files():
		if not owns_name(name):
			continue
		var path := "user://".path_join(name)
		# The time comes from opening the path, which only a file answers: a leftover that is
		# somebody else's folder is still listed, just with no age to sort by. Asking first
		# also keeps a file deleted between listing and sorting from logging an error.
		var msec := 0
		if FileAccess.file_exists(path):
			msec = FileAccess.get_modified_time(path)
		found.append({"msec": msec, "path": path})
	var by_age := func(one: Dictionary, other: Dictionary) -> bool:
		if int(one["msec"]) != int(other["msec"]):
			return int(one["msec"]) > int(other["msec"])
		return String(one["path"]) < String(other["path"])
	found.sort_custom(by_age)
	var paths := PackedStringArray()
	for entry: Dictionary in found:
		paths.append(String(entry["path"]))
	return paths


## True for the names this swap leaves behind - the preferred backup name and the unique
## ones with our hex tag - and false for anything a person put beside the file. The swap
## deletes leftovers, so it has to be sure whose they are.
static func owns_name(name: String) -> bool:
	if name == BACKUP_PATH.get_file():
		return true
	if not name.begins_with(LEFTOVER_PREFIX) or not name.ends_with(LEFTOVER_SUFFIX):
		return false
	var tag := name.trim_prefix(LEFTOVER_PREFIX).trim_suffix(LEFTOVER_SUFFIX)
	if tag.length() != HEX_TAG_LENGTH:
		return false
	for index in tag.length():
		if not HEX_DIGITS.contains(tag[index].to_lower()):
			return false
	return true


## Removes the leftovers of finished swaps and returns the ones that stayed.
##
## A leftover that will not go away - read-only, or held by another program, which is also
## how the preferred backup name gets stuck in the first place - is reported and left alone:
## it is not worth refusing every later settings change over, and each write then keeps one
## small copy of what it replaced. The warning names the paths so the directory can be
## cleaned up by whoever owns it.
static func retire_leftovers() -> PackedStringArray:
	var stuck := PackedStringArray()
	for path: String in leftovers():
		if DirAccess.remove_absolute(path) == OK or not FileAccess.file_exists(path):
			continue
		stuck.append(path)
	if not stuck.is_empty():
		push_warning("SettingsStore: preferences saved; leftovers stayed: %s." % str(stuck))
	return stuck


static func _warn_save(step: String, error: Error) -> void:
	push_warning("SettingsStore: could not %s (error %d: %s)." % [step, error, error_string(error)])


## Names the refused step for the log and for `report`, and returns the error unchanged: a
## caller that ignores `report` still sees the same `Error` it saw before.
static func _refuse(report: Dictionary, step: String, error: Error) -> Error:
	_warn_save(step, error)
	report["step"] = step
	report["error"] = error
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


## Always rename onto a vacant name. Some engines/filesystems cannot replace an existing
## file, or delete it before moving the new one. So the previous file is preserved first -
## under a name that is free, which is what keeps a leftover nobody can remove (a read-only
## file, a directory someone made) from wedging every later settings change.
## `move_file` lets the regression test fail exactly one step of the swap.
static func _publish(stage: String, move_file: Callable, report: Dictionary = {}) -> Error:
	var preserving := FileAccess.file_exists(PATH)
	var kept := ""
	if preserving:
		kept = _free_backup_name()
		if kept.is_empty():
			return _refuse(report, "find a free name beside the preferences file", ERR_CANT_CREATE)
		var aside: Error = move_file.call(PATH, kept)
		if aside != OK:
			return _refuse(report, "move the previous preferences aside to %s" % kept, aside)
	var error: Error = move_file.call(stage, PATH)
	if error == OK:
		return OK
	if preserving:
		# The previous file is still on the disk, only under `kept`, and `read()` finds it on the
		# next run. Naming it in the report is what makes a half-finished swap something a person
		# can finish by hand instead of a preferences file that appears to have gone missing.
		if move_file.call(kept, PATH) != OK:
			var waiting := "publish the staged preferences; the previous file is still at %s" % kept
			return _refuse(report, waiting, error)
	return _refuse(report, "publish staged preferences", error)


## The file is the truth once it reads back as what was asked for; only then are the
## leftovers of the swap retired. While it does not read back, the copy that was moved aside
## stays on disk, and `read()` finds it on the next run.
static func _confirm(asked: ConfigFile, report: Dictionary) -> Error:
	var published := ConfigFile.new()
	var error := published.load(PATH)
	if error != OK:
		return _refuse(report, "read back the published preferences", error)
	if not _same_values(asked, published):
		return _refuse(report, "read back the published preferences", ERR_FILE_CORRUPT)
	retire_leftovers()
	return OK


## The preferred backup name when something does not occupy it, otherwise a unique one.
static func _free_backup_name() -> String:
	if not _occupied(BACKUP_PATH):
		return BACKUP_PATH
	var crypto := Crypto.new()
	for attempt in 8:
		var candidate := "%s.%s%s" % [PATH, crypto.generate_random_bytes(HEX_BYTES).hex_encode(), LEFTOVER_SUFFIX]
		if not _occupied(candidate):
			return candidate
	return ""


## A name is taken by a file or by a directory: neither can be the target of a rename on
## the platforms that refuse to replace what is already there.
static func _occupied(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


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
