class_name ReadLog
extends RefCounted
## What the player has already read and which options they have already taken, across runs.
##
## The backlog (`DialogueHistory`) is the record of *this* run and disappears with it. This
## is the other memory a narrative game keeps: the lines the player has seen in any run, so
## that a second playthrough can skip what it has already read (and stop at what it has not),
## and so that an option taken before can look different from one never tried. It lives in
## its own file, `user://read_log.json`, not in the save: starting a new game must not forget
## it, and deleting the save must not either (see `docs/ARCHITECTURE.md` §5n).
##
## **What "read" means.** A line is identified the way the backlog identifies it
## (`DialogueHistory.identify`: `conv:<conversation>/<node>`, `inspection:<id>/<variant>`),
## so it is independent of the text and of the language. Next to the identity the log keeps a
## short fingerprint of the text *per language it was read in*. A line counts as read when:
##
## - its identity is known, and
## - it was never read in the current language (reading it in Chinese counts for English), or
##   the text in the current language still has the fingerprint it had when it was read.
##
## The second rule is what makes an edited line unread again: after a rewrite the identity is
## the same, but the player has not read *this* text, and skipping over it would hide the
## change from the person most likely to want to see it. A line the content cannot identify
## (`unidentified:...`) is never read: skipping it would be a guess.
##
## **The file.** One JSON object with a format tag and a version. A file that is not ours, not
## JSON, or not an object is copied to `read_log.broken.json` and the log starts empty, so a
## bug report still has the bytes. Single bad entries are dropped and reported in `problems`.
## A file written by a *newer* version is read for what this version understands and then
## never written back (`is_read_only()`), so running an older build cannot erase a newer
## build's memory. Writes go to a temporary file, are read back and compared, and only then
## replace the old file; on a failure the old file is left as it was and the log stays in
## memory, marked dirty, for the next attempt.
##
## The log is small (an identity and a 16-character fingerprint per line the game has) and
## bounded (`MAX_LINES`, `MAX_CHOICES`) so a content history of renamed nodes cannot grow it
## without limit.

const DEFAULT_PATH := "user://read_log.json"
const FORMAT := "where-is-school/read-log"
const VERSION := 1
## Far above the content the game has (a few hundred lines per language) and far below
## anything that would make the file slow to read at start-up.
const MAX_LINES := 20000
const MAX_CHOICES := 10000
## Characters of the SHA-256 kept per text. 64 bits: a collision between two versions of
## the same line is not a realistic event.
const FINGERPRINT_LENGTH := 16

static var _shared: ReadLog = null

## Where this log is read from and written to.
var path: String = DEFAULT_PATH
## Everything that was wrong with the file on the last load, as readable sentences.
var problems: Array[String] = []

## identity -> {locale -> fingerprint}
var _lines: Dictionary = {}
## choice identity -> true
var _choices: Dictionary = {}
var _dirty := false
var _read_only := false
var _loaded := false
var _full_warned := false


func _init(log_path: String = DEFAULT_PATH) -> void:
	path = log_path


## The log the game uses: loaded from `DEFAULT_PATH` the first time it is asked for, and
## shared by the dialogue controller (which reads and marks lines) and the settings screen
## (which can forget them), so the two never hold different copies.
static func shared() -> ReadLog:
	if _shared == null:
		_shared = ReadLog.new(DEFAULT_PATH)
		_shared.load_file()
	return _shared


## Replaces the shared log, for a test that must not read or write the player's file. Pass
## null to go back to the default on the next `shared()`.
static func use_shared(replacement: ReadLog) -> void:
	_shared = replacement


## The identity of option `choice_id` at `node_id` in `conversation_id`.
static func choice_identity(conversation_id: StringName, node_id: StringName, choice_id: StringName) -> String:
	return "choice:%s/%s/%s" % [String(conversation_id), String(node_id), String(choice_id)]


## The short fingerprint the log keeps of a text.
static func fingerprint(text: String) -> String:
	return text.sha256_text().substr(0, FINGERPRINT_LENGTH)


## Whether `identity` names a line the content can find again. Lines that cannot be
## identified are never remembered, so they are never skipped.
static func is_identifiable(identity: String) -> bool:
	return not identity.is_empty() and not identity.begins_with("unidentified:")


# --- Reading -------------------------------------------------------------------------


func is_read(identity: String, locale: String, text: String) -> bool:
	if not is_identifiable(identity) or not _lines.has(identity):
		return false
	var seen: Dictionary = _lines[identity]
	if not seen.has(locale):
		return true
	return String(seen[locale]) == fingerprint(text)


func has_chosen(choice_id: String) -> bool:
	return _choices.has(choice_id)


func line_count() -> int:
	return _lines.size()


func choice_count() -> int:
	return _choices.size()


func is_dirty() -> bool:
	return _dirty


## True when the file on disk was written by a newer version: it is read, never replaced.
func is_read_only() -> bool:
	return _read_only


func is_loaded() -> bool:
	return _loaded


# --- Writing -------------------------------------------------------------------------


## Remembers that `text` was shown as `identity` in `locale`. Returns true when that is news
## (a new line, a new language, or a changed text).
func mark_read(identity: String, locale: String, text: String) -> bool:
	if not is_identifiable(identity) or locale.is_empty():
		return false
	var print_now := fingerprint(text)
	var seen: Dictionary = _lines.get(identity, {})
	if String(seen.get(locale, "")) == print_now:
		return false
	if not _lines.has(identity) and _lines.size() >= MAX_LINES:
		_warn_full("lines", MAX_LINES)
		return false
	seen[locale] = print_now
	_lines[identity] = seen
	_dirty = true
	return true


func mark_chosen(choice_id: String) -> bool:
	if choice_id.is_empty() or _choices.has(choice_id):
		return false
	if _choices.size() >= MAX_CHOICES:
		_warn_full("choices", MAX_CHOICES)
		return false
	_choices[choice_id] = true
	_dirty = true
	return true


## Forgets every line and every option, and writes the empty log. Returns the result of
## the write; the memory is cleared either way.
func forget_all() -> Dictionary:
	_lines.clear()
	_choices.clear()
	_dirty = true
	_full_warned = false
	if _read_only:
		# Forgetting is the player's explicit request, and it is the one write that may
		# replace a newer file: nothing in it would be kept by a clear anyway.
		_read_only = false
	return save_file()


## Writes the log if anything changed since the last write.
func flush() -> Dictionary:
	if not _dirty:
		return {"ok": true, "written": false}
	return save_file()


# --- The file ------------------------------------------------------------------------


## Reads the file. Returns true when the log reflects the file (or there is no file yet);
## false when the file was unusable and the log started empty.
func load_file() -> bool:
	problems.clear()
	_lines.clear()
	_choices.clear()
	_dirty = false
	_read_only = false
	_loaded = true
	if not FileAccess.file_exists(path):
		return true
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_problem("%s could not be opened (error %d)" % [path, FileAccess.get_open_error()])
		return false
	var json := JSON.new()
	if json.parse(text) != OK:
		_problem("%s is not JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		_quarantine(text)
		return false
	var data: Variant = json.data
	if not data is Dictionary:
		_problem("%s does not hold an object" % path)
		_quarantine(text)
		return false
	var root: Dictionary = data
	if String(root.get("format", "")) != FORMAT:
		_problem("%s is not a read log (format %s)" % [path, str(root.get("format", null))])
		_quarantine(text)
		return false
	var version: Variant = root.get("version", null)
	if not (version is int or version is float) or int(version) < 1:
		_problem("%s has no usable version (%s)" % [path, str(version)])
		_quarantine(text)
		return false
	if int(version) > VERSION:
		_read_only = true
		_problem(
			"%s was written by a newer version (%d > %d); it is read but not replaced"
			% [path, int(version), VERSION]
		)
	_read_lines(root.get("lines", {}))
	_read_choices(root.get("choices", []))
	return true


## Writes the log: temporary file, read back, compared, then moved into place.
func save_file() -> Dictionary:
	if _read_only:
		return {"ok": false, "error": "read_only", "detail": "%s belongs to a newer version" % path}
	var bytes := JSON.stringify(_to_dictionary(), "", true).to_utf8_buffer()
	var temp := "%s.tmp" % path
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _write_failed("open", FileAccess.get_open_error(), temp)
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _write_failed("write", error, temp)
	if FileAccess.get_file_as_bytes(temp) != bytes:
		DirAccess.remove_absolute(temp)
		return _write_failed("verify", ERR_FILE_CORRUPT, temp)
	error = DirAccess.rename_absolute(temp, path)
	if error != OK and FileAccess.file_exists(path):
		# Some platforms refuse to rename onto an existing file. The old log is only a
		# convenience, and the verified copy is already on disk, so it may go first.
		DirAccess.remove_absolute(path)
		error = DirAccess.rename_absolute(temp, path)
	if error != OK:
		return _write_failed("rename", error, path)
	_dirty = false
	return {"ok": true, "written": true}


func _to_dictionary() -> Dictionary:
	var choices := _choices.keys()
	choices.sort()
	return {
		"format": FORMAT,
		"version": VERSION,
		"lines": _lines.duplicate(true),
		"choices": choices,
	}


func _read_lines(value: Variant) -> void:
	if not value is Dictionary:
		_problem("'lines' is not an object; no line is remembered")
		return
	var dropped := 0
	for identity_value: Variant in (value as Dictionary).keys():
		var identity := String(identity_value)
		var seen: Variant = (value as Dictionary)[identity_value]
		if not is_identifiable(identity) or not seen is Dictionary:
			dropped += 1
			continue
		var kept: Dictionary = {}
		for locale_value: Variant in (seen as Dictionary).keys():
			var print_value: Variant = (seen as Dictionary)[locale_value]
			if print_value is String and _is_fingerprint(String(print_value)) \
					and not String(locale_value).is_empty():
				kept[String(locale_value)] = String(print_value)
		if kept.is_empty() or _lines.size() >= MAX_LINES:
			dropped += 1
			continue
		_lines[identity] = kept
	if dropped > 0:
		_problem("%d line entr%s could not be used" % [dropped, "y" if dropped == 1 else "ies"])


func _read_choices(value: Variant) -> void:
	if not value is Array:
		_problem("'choices' is not a list; no option is remembered")
		return
	var dropped := 0
	for item: Variant in value:
		if not item is String or not String(item).begins_with("choice:") \
				or _choices.size() >= MAX_CHOICES:
			dropped += 1
			continue
		_choices[String(item)] = true
	if dropped > 0:
		_problem("%d option entr%s could not be used" % [dropped, "y" if dropped == 1 else "ies"])


func _is_fingerprint(value: String) -> bool:
	if value.length() != FINGERPRINT_LENGTH:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


## Keeps the bytes that could not be read, next to the log, before it is replaced.
func _quarantine(text: String) -> void:
	var broken := path.get_basename() + ".broken.json"
	var file := FileAccess.open(broken, FileAccess.WRITE)
	if file == null:
		_problem("the unreadable log could not be copied to %s" % broken)
		return
	file.store_string(text)
	file.close()
	_problem("the unreadable log was copied to %s" % broken)


func _problem(message: String) -> void:
	problems.append(message)
	push_warning("ReadLog: %s." % message)


func _write_failed(step: String, error: int, where: String) -> Dictionary:
	var detail := "%s failed for %s (error %d)" % [step, where, error]
	push_warning("ReadLog: could not save what was read: %s." % detail)
	return {"ok": false, "error": step, "detail": detail}


func _warn_full(kind: String, limit: int) -> void:
	if _full_warned:
		return
	_full_warned = true
	push_warning("ReadLog: the log already holds %d %s; nothing more is remembered." % [limit, kind])
