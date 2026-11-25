extends RefCounted

## Reading helpers for the inner-voice registry, moved out of `inner_abilities.gd` to keep
## that file under the size cap (issue #349). Preload-only, like `inner_voice_migration.gd`:
## no `class_name`, no state. Every function reports into the `errors` array its caller owns,
## so the messages keep the file, ability id and field they had before the move. The
## constants the exception rule needs are passed in, so this file does not preload the
## registry back.

## Reads an integer field without ever guessing. JSON has one number type, so a
## fractional or non-numeric value would otherwise become 0 through `int()` and a
## mistyped difficulty would quietly turn into an easy check.
static func read_int(
	source: Dictionary, key: String, fallback: int, context: String, errors: Array[String]
) -> int:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	if not (raw is int or raw is float):
		errors.append(
			"%s: '%s' must be a number (got %s)." % [context, key, JSON.stringify(raw)]
		)
		return fallback
	if raw is float and not is_equal_approx(float(raw), roundf(float(raw))):
		errors.append(
			"%s: '%s' must be a whole number (got %s)." % [context, key, str(raw)]
		)
	return int(raw)


static func read_json(path: String, errors: Array[String]) -> Dictionary:
	return JsonTable.read_dict(
		path,
		errors,
		"%s: root value must be an object.",
		"File not found: %s",
		"Could not open %s (error %d)."
	)


## Which fields of this voice may keep the source wording. Deliberately field by field:
## an exception is a decision about one string, and a per-voice or per-file switch would
## quietly excuse the next copied line too.
static func parse_exceptions(
	text: Dictionary, path: String, ability_id: StringName, is_reference: bool,
	errors: Array[String], exception_key: String, text_fields: Array[String]
) -> Array[String]:
	var declared: Array[String] = []
	if not text.has(exception_key):
		return declared
	var raw: Variant = text[exception_key]
	if not (raw is Array):
		errors.append(
			"%s: ability '%s': '%s' must be an array of field names (got %s)."
			% [path, ability_id, exception_key, JSON.stringify(raw)]
		)
		return declared
	if is_reference:
		errors.append(
			"%s: ability '%s': '%s' only makes sense in a translated language, not in the "
			% [path, ability_id, exception_key]
			+ "reference one — its text is the source."
		)
		return declared
	var entries: Array = raw
	for position in entries.size():
		var entry: Variant = entries[position]
		if not (entry is String) or String(entry).strip_edges().is_empty():
			errors.append(
				"%s: ability '%s': %s[%d] must be a field name (got %s)."
				% [path, ability_id, exception_key, position, JSON.stringify(entry)]
			)
			continue
		var field := String(entry).strip_edges()
		if not text_fields.has(field):
			errors.append(
				"%s: ability '%s': %s names '%s', which is not translated text; use one of %s."
				% [
					path,
					ability_id,
					exception_key,
					field,
					", ".join(text_fields),
				]
			)
			continue
		if declared.has(field):
			errors.append(
				"%s: ability '%s': '%s' is listed twice in %s."
				% [path, ability_id, field, exception_key]
			)
			continue
		declared.append(field)
	return declared
