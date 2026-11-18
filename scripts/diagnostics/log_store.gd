extends RefCounted
## Bounded local JSONL store. Only this module names or opens managed files.
## `append()` runs on one worker at a time, using its own handles and immutable batch.

const FILE_BYTES := 64 * 1024
const FILE_COUNT := 4
const MAX_LINE_BYTES := 768
const HISTORY_LIMIT := 160
const EXPORT_NAME := "diagnostics-latest.json"
const PREFIX := "events-"
const SUFFIX := ".jsonl"
const SEQUENCE_DIGITS := 12


static func ensure_directory(path: String) -> int:
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null and parent.is_link(path.get_file()):
		return ERR_UNAUTHORIZED
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error == OK and not DirAccess.dir_exists_absolute(path):
		return ERR_CANT_CREATE
	return error


static func append(path: String, rows: Array[Dictionary]) -> int:
	if rows.is_empty():
		return OK
	var lines := PackedStringArray()
	for row: Dictionary in rows:
		lines.append(JSON.stringify(row))
	var bytes := ("\n".join(lines) + "\n").to_utf8_buffer()
	if bytes.size() > FILE_BYTES:
		return ERR_INVALID_DATA
	var error := ensure_directory(path)
	if error != OK:
		return error
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.get_open_error()

	var files := _managed_files(dir)
	var name := files[-1] if not files.is_empty() else ""
	var existing := _open_tail(path.path_join(name), bytes.size()) if not name.is_empty() else null
	var keep := FILE_COUNT if existing != null else FILE_COUNT - 1
	while files.size() > keep:
		# Remove only this store's oldest regular files. Do not exceed the cap to work
		# around a failed removal, and do not touch saves, Godot logs or user files.
		error = dir.remove(files[0])
		if error != OK:
			return error
		files.remove_at(0)
	if existing == null:
		var next := _sequence(name) + 1 if not name.is_empty() else 1
		name = "%s%012d%s" % [PREFIX, next, SUFFIX]
		if _sequence(name) < 0 or dir.is_link(name) or dir.file_exists(name):
			return ERR_ALREADY_EXISTS
		existing = FileAccess.open(path.path_join(name), FileAccess.WRITE_READ)
		if existing == null:
			return FileAccess.get_open_error()

	var before := existing.get_length()
	existing.seek_end()
	var stored := existing.store_buffer(bytes)
	existing.flush()
	if not stored or existing.get_error() != OK or existing.get_length() != before + bytes.size():
		# Best effort: leave the previous rows intact and let the worker retry the batch.
		# If truncation itself fails, a reader still ignores any incomplete final line.
		existing.resize(before)
		existing.close()
		return ERR_FILE_CANT_WRITE
	existing.close()
	return OK


## Returns an appendable file only if it fits and ends on a complete line. After an
## interrupted write, rotate instead of gluing the next entry onto a broken line.
static func _open_tail(path: String, bytes_needed: int) -> FileAccess:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return null
	var length := file.get_length()
	if length + bytes_needed > FILE_BYTES:
		return null
	if length > 0:
		file.seek(length - 1)
		if file.get_8() != 10:
			return null
	return file


static func _sequence(name: String) -> int:
	if not name.begins_with(PREFIX) or not name.ends_with(SUFFIX):
		return -1
	var digits := name.trim_prefix(PREFIX).trim_suffix(SUFFIX)
	if digits.length() != SEQUENCE_DIGITS:
		return -1
	for i: int in digits.length():
		if digits.unicode_at(i) < 48 or digits.unicode_at(i) > 57:
			return -1
	return int(digits)


static func _managed_files(dir: DirAccess) -> PackedStringArray:
	var files := PackedStringArray()
	for name: String in dir.get_files():
		if _sequence(name) >= 0 and not dir.is_link(name):
			files.append(name)
	files.sort()
	return files


## Only read our last four capped files; partial, invalid and foreign rows stay out.
## The schema is passed in because membership of published location IDs is game data.
static func history(path: String, schema: RefCounted) -> Dictionary:
	var rows: Array[Dictionary] = []
	var skipped := 0
	var error := ensure_directory(path)
	if error != OK:
		return {"rows": rows, "skipped": skipped, "error": error}
	var dir := DirAccess.open(path)
	if dir == null:
		return {"rows": rows, "skipped": skipped, "error": DirAccess.get_open_error()}
	var files := _managed_files(dir)
	var json := JSON.new()
	for index: int in range(files.size() - 1, maxi(-1, files.size() - FILE_COUNT - 1), -1):
		var file := FileAccess.open(path.path_join(files[index]), FileAccess.READ)
		if file == null or file.get_length() > FILE_BYTES:
			skipped += 1
			continue
		var lines := file.get_buffer(file.get_length()).get_string_from_utf8().split("\n")
		file.close()
		# `split`'s last element is either empty or an unfinished line after a crash.
		if not lines[-1].is_empty():
			skipped += 1
		for line_index: int in range(lines.size() - 2, -1, -1):
			var line := lines[line_index]
			if line.to_utf8_buffer().size() > MAX_LINE_BYTES or json.parse(line) != OK:
				skipped += 1
				continue
			var row: Dictionary = schema.import_record(json.data)
			if row.is_empty():
				skipped += 1
				continue
			rows.append(row)
			if rows.size() >= HISTORY_LIMIT:
				rows.reverse()
				return {"rows": rows, "skipped": skipped, "error": OK}
	rows.reverse()
	return {"rows": rows, "skipped": skipped, "error": OK}


static func write_export(path: String, report: Dictionary) -> int:
	var error := ensure_directory(path)
	if error != OK:
		return error
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.get_open_error()
	var temporary := EXPORT_NAME + ".tmp"
	if dir.is_link(temporary) or dir.is_link(EXPORT_NAME):
		return ERR_UNAUTHORIZED
	var bytes := (JSON.stringify(report, "  ") + "\n").to_utf8_buffer()
	var file := FileAccess.open(path.path_join(temporary), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_buffer(bytes)
	file.close()
	if not stored or FileAccess.get_file_as_bytes(path.path_join(temporary)) != bytes:
		dir.remove(temporary)
		return ERR_FILE_CANT_WRITE
	error = dir.rename(temporary, EXPORT_NAME)
	if error != OK:
		dir.remove(temporary)
	return error
