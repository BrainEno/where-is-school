class_name JsonTable
extends RefCounted
## Reads, parses and formats errors for JSON data files across the project.
##
## Standardises file existence, read permissions, JSON syntax errors, top-level
## dictionary validation, and report formatting across narrative, dialogue, RPG
## and world data catalogs so that file I/O and parse boilerplate are written once.

## Reads and parses a JSON file into a Dictionary, recording failures into `errors`.
## Returns an empty Dictionary if the file is missing, cannot be opened, contains invalid
## JSON, or is not a top-level JSON object.
static func read_dict(
	path: String,
	errors: Array[String] = [],
	not_dict_message: String = "%s: not a JSON object.",
	missing_message: String = "%s does not exist.",
	open_error_message: String = "%s: cannot open file (error %d)."
) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append(missing_message % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append(open_error_message % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append(
			"%s: invalid JSON at line %d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return {}
	var raw: Variant = json.data
	if not (raw is Dictionary):
		if not_dict_message.contains("%s"):
			errors.append(not_dict_message % path)
		else:
			errors.append(not_dict_message)
		return {}
	return raw as Dictionary


## Reads the entire text of a file, or returns an empty string if missing/unreadable.
static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## Returns the byte size of a file, or 0 if it cannot be read.
static func file_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


## Formats a standard error report for data libraries.
static func describe_errors(
	noun: String,
	errors: Array[String],
	has_verb: String = "has"
) -> String:
	if errors.is_empty():
		return "%s loaded without errors." % noun
	return "%s %s %d error(s):\n%s" % [noun, has_verb, errors.size(), "\n".join(errors)]
