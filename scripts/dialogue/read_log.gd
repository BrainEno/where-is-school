class_name ReadLog
extends RefCounted
## Every line the player has read, in any run, by content identity.
##
## "Skip read text" needs to know whether *this* line was on screen before - in this run
## or an earlier one - and nothing else in the game remembers that across a new game. So
## this is a player-profile file like `settings.cfg`, not part of the save:
##
## - it is never written by `Save` and never read from a save, so ADR 0005's payload and
##   its validation are untouched, and a new game does not forget what was read;
## - it holds identities only (`conv:<conversation>/<node>`, `inspection:<id>/<variant>`,
##   the same strings `DialogueHistory.identify()` gives the backlog), never text, so a
##   translation or a rewritten line keeps its read mark exactly as long as its id lives;
## - a line with no stable identity (`unidentified:...`) is never marked, because the next
##   unidentified line would wrongly count as read.
##
## The file is small and rewritten whole. A write goes to a temporary file that is read
## back before it replaces the old one, so a crash mid-write leaves either the old log or
## the new one; a log that cannot be parsed is moved aside (never deleted) and the game
## carries on with an empty log, reporting why. Losing it only means lines count as unread.

const PATH := "user://read_lines.json"
const FORMAT_VERSION := 1
## Prefixes of identities stable enough to remember.
const STABLE_PREFIXES: Array[String] = ["conv:", "inspection:"]

var _path: String = PATH
## identity -> true
var _read: Dictionary = {}
var _dirty := false
var _problems: Array[String] = []
var writes: int = 0


func _init(path: String = PATH) -> void:
	_path = path


## A log read from `path`, or an empty one when there is none yet.
static func open(path: String = PATH) -> ReadLog:
	var opened := ReadLog.new(path)
	opened.load_file()
	return opened


func get_path() -> String:
	return _path


static func is_stable(identity: String) -> bool:
	for prefix: String in STABLE_PREFIXES:
		if identity.begins_with(prefix) and identity.length() > prefix.length():
			return true
	return false


func has_read(identity: String) -> bool:
	return _read.has(identity)


## Marks a line as read. Returns true when it had not been read before.
func mark(identity: String) -> bool:
	if not is_stable(identity) or _read.has(identity):
		return false
	_read[identity] = true
	_dirty = true
	return true


func size() -> int:
	return _read.size()


func is_dirty() -> bool:
	return _dirty


func get_identities() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _read.keys():
		out.append(String(key))
	out.sort()
	return out


## How many of `identities` have been read.
func count_read(identities: Array) -> int:
	var count := 0
	for identity: Variant in identities:
		if _read.has(String(identity)):
			count += 1
	return count


func get_problems() -> Array[String]:
	var out: Array[String] = []
	out.append_array(_problems)
	return out


## Forgets everything, on disk as well. For tests and for a future "forget what I read".
func forget() -> void:
	_read.clear()
	_dirty = false
	for path: String in [_path, _temp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Reading ------------------------------------------------------------------------


func load_file() -> void:
	_read.clear()
	_dirty = false
	_problems.clear()
	var path := _path
	if not FileAccess.file_exists(path):
		# A write that crashed after the old file was removed leaves only the new one.
		if FileAccess.file_exists(_temp_path()):
			path = _temp_path()
		else:
			return
	# `JSON.parse_string` logs an engine error on bad input; a damaged log is expected
	# here and reported through `get_problems()` instead.
	var json := JSON.new()
	var parsed: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		parsed = json.data
	var problem := _accept(parsed)
	if problem.is_empty():
		if path != _path:
			# Finish the interrupted swap now that the bytes are known to be good.
			_dirty = true
			flush()
		return
	_problems.append("%s: %s" % [path, problem])
	_read.clear()
	_set_aside(path)


func _accept(parsed: Variant) -> String:
	if not parsed is Dictionary:
		return "not a JSON object"
	var data: Dictionary = parsed
	var version: Variant = data.get("version", null)
	if not (version is int or version is float) or int(version) != FORMAT_VERSION:
		return "version %s is not %d" % [str(version), FORMAT_VERSION]
	var lines: Variant = data.get("lines", null)
	if not lines is Array:
		return "'lines' is not a list"
	var skipped := 0
	for item: Variant in lines:
		if item is String and is_stable(item):
			_read[String(item)] = true
		else:
			skipped += 1
	if skipped > 0:
		# One bad id is not a reason to throw the rest away.
		_problems.append("%s: %d entr%s ignored" % [_path, skipped, "y" if skipped == 1 else "ies"])
	return ""


## Keeps the bytes that failed for a bug report, out of the way of the next write.
func _set_aside(path: String) -> void:
	var broken := "%s.broken" % _path
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	if FileAccess.file_exists(broken):
		dir.remove(broken.get_file())
	dir.rename(path.get_file(), broken.get_file())


# --- Writing ------------------------------------------------------------------------


## Writes the log if anything changed since the last write. Returns false on a failed
## write, which leaves the previous file in place and the log marked dirty.
func flush() -> bool:
	if not _dirty:
		return true
	var text := JSON.stringify({"version": FORMAT_VERSION, "lines": get_identities()}, "", false)
	var temp := _temp_path()
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_report("could not open %s (error %d)" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(temp) != text:
		_report("%s did not read back as written" % temp)
		return false
	var dir := DirAccess.open(_path.get_base_dir())
	if dir == null:
		_report("could not open %s" % _path.get_base_dir())
		return false
	if FileAccess.file_exists(_path) and dir.remove(_path.get_file()) != OK:
		_report("could not replace %s" % _path)
		return false
	var error := dir.rename(temp.get_file(), _path.get_file())
	if error != OK:
		_report("could not move %s into place (error %d)" % [temp, error])
		return false
	_dirty = false
	writes += 1
	return true


func _temp_path() -> String:
	return "%s.tmp" % _path


func _report(message: String) -> void:
	_problems.append(message)
	push_warning("ReadLog: %s" % message)
