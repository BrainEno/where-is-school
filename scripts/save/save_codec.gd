class_name SaveCodec
extends RefCounted
## The bytes of a save file, and nothing else.
##
## `SaveManager` decides *what* a save contains; this decides how it survives a trip
## through JSON. The two jobs are separate because the hard part is not the file, it
## is that JSON has no integers, no StringName and no notion of a type error.
##
## Every value is written as a tagged pair - `{"t": "i", "v": 3}` - so a flag that
## was an `int` comes back an `int`, a `StringName` comes back a `StringName`, and a
## nested check record keeps its own integers. Nothing is coerced: a tag this codec
## does not know is a payload error that names the path it was found at, because a
## silently narrowed value is exactly how a save system starts lying.
##
## The envelope carries `format` and `version` so a reader can refuse a file it does
## not understand *before* it looks at any of it (ADR 0005).

## Identifies the writer. A file without this tag is not ours to guess about.
const FORMAT := "where-is-school/save"
## Bumped when the payload shape changes; see `SaveManager.MIGRATIONS`.
const VERSION := 1

const TAG_BOOL := "b"
const TAG_INT := "i"
const TAG_FLOAT := "f"
const TAG_STRING := "s"
const TAG_STRING_NAME := "sn"
const TAG_ARRAY := "a"
const TAG_DICTIONARY := "d"
const TAG_NULL := "n"


## The wrapper around a payload. `saved_at_unix` is for humans and bug reports; no
## reader is allowed to branch on it.
static func wrap(payload: Dictionary, saved_at_unix: int) -> String:
	return JSON.stringify(
		{
			"format": FORMAT,
			"version": VERSION,
			"saved_at_unix": saved_at_unix,
			"payload": payload,
		},
		"\t"
	)


## Reads the envelope. Returns
## `{ok, payload, reason, detail, version}`; on failure `payload` is empty and
## `reason` is one of `not_json`, `format`, `version`.
static func unwrap(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return _refuse("not_json", "the file is empty")
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return _refuse("not_json", "the file is not a JSON object")
	var envelope: Dictionary = parsed
	var format := String(envelope.get("format", ""))
	if format != FORMAT:
		return _refuse(
			"format",
			"the file declares format '%s', not '%s'" % [format, FORMAT]
		)
	var version_value: Variant = envelope.get("version", null)
	if not (version_value is float or version_value is int):
		return _refuse("version", "the file declares no numeric version")
	var version := int(version_value)
	if version > VERSION:
		return _refuse(
			"version",
			"the save was written by a newer build (version %d; this build reads %d)"
			% [version, VERSION]
		)
	if version < 1:
		return _refuse("version", "the save declares version %d, which never existed" % version)
	var payload: Variant = envelope.get("payload", null)
	if not (payload is Dictionary):
		return _refuse("payload", "the file has no payload object")
	return {"ok": true, "payload": payload, "reason": "", "detail": "", "version": version}


# --- Flags ------------------------------------------------------------------


## Encodes a flag table. Keys become plain strings; every value keeps its type.
static func encode_flags(flags: Dictionary) -> Dictionary:
	var encoded: Dictionary = {}
	for key: Variant in flags.keys():
		encoded[String(key)] = encode_value(flags[key])
	return encoded


## Decodes a flag table that `encode_flags` produced. All or nothing: one unknown
## tag refuses the table, because a half-known flag set is not a session.
## Returns `{ok, flags, reason, detail}`.
static func decode_flags(raw: Variant) -> Dictionary:
	if raw == null:
		return {"ok": true, "flags": {}, "reason": "", "detail": ""}
	if not (raw is Dictionary):
		return {
			"ok": false,
			"flags": {},
			"reason": "payload",
			"detail": "'flags' is not an object",
		}
	var flags: Dictionary = {}
	var table: Dictionary = raw
	for key: Variant in table.keys():
		var path := "flags.%s" % String(key)
		var decoded := decode_value(table[key], path)
		if decoded["ok"] != true:
			return {
				"ok": false,
				"flags": {},
				"reason": "payload",
				"detail": String(decoded["detail"]),
			}
		flags[StringName(String(key))] = decoded["value"]
	return {"ok": true, "flags": flags, "reason": "", "detail": ""}


# --- Values -----------------------------------------------------------------


static func encode_value(value: Variant) -> Dictionary:
	if value == null:
		return {"t": TAG_NULL}
	match typeof(value):
		TYPE_BOOL:
			return {"t": TAG_BOOL, "v": value}
		TYPE_INT:
			return {"t": TAG_INT, "v": value}
		TYPE_FLOAT:
			return {"t": TAG_FLOAT, "v": value}
		TYPE_STRING:
			return {"t": TAG_STRING, "v": value}
		TYPE_STRING_NAME:
			return {"t": TAG_STRING_NAME, "v": String(value)}
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(encode_value(item))
			return {"t": TAG_ARRAY, "v": items}
		TYPE_DICTIONARY:
			var members: Dictionary = {}
			var source: Dictionary = value
			for key: Variant in source.keys():
				members[String(key)] = encode_value(source[key])
			return {"t": TAG_DICTIONARY, "v": members}
	push_error("SaveCodec: cannot store a value of type %d." % typeof(value))
	return {"t": TAG_NULL}


## Returns `{ok, value, detail}`. `path` names the place in the file the value came
## from, so an error says `flags.check:gate:try_roll` instead of "somewhere".
static func decode_value(raw: Variant, path: String) -> Dictionary:
	if not (raw is Dictionary):
		return _bad_value(path, "expected a tagged value, found %s" % _type_name(raw))
	var tagged: Dictionary = raw
	var tag := String(tagged.get("t", ""))
	match tag:
		TAG_NULL:
			return {"ok": true, "value": null, "detail": ""}
		TAG_BOOL, TAG_INT, TAG_FLOAT, TAG_STRING:
			if not tagged.has("v"):
				return _bad_value(path, "'%s' has no value" % tag)
			return {"ok": true, "value": tagged["v"], "detail": ""}
		TAG_STRING_NAME:
			if not tagged.has("v"):
				return _bad_value(path, "'sn' has no value")
			return {"ok": true, "value": StringName(String(tagged["v"])), "detail": ""}
		TAG_ARRAY:
			var items: Variant = tagged.get("v", [])
			if not (items is Array):
				return _bad_value(path, "'a' does not hold an array")
			var decoded: Array = []
			var index := 0
			for item: Variant in items:
				var result := decode_value(item, "%s[%d]" % [path, index])
				if result["ok"] != true:
					return result
				decoded.append(result["value"])
				index += 1
			return {"ok": true, "value": decoded, "detail": ""}
		TAG_DICTIONARY:
			var members: Variant = tagged.get("v", {})
			if not (members is Dictionary):
				return _bad_value(path, "'d' does not hold an object")
			var source: Dictionary = members
			var decoded_members: Dictionary = {}
			for key: Variant in source.keys():
				var member_path := "%s.%s" % [path, String(key)]
				var result := decode_value(source[key], member_path)
				if result["ok"] != true:
					return result
				decoded_members[String(key)] = result["value"]
			return {"ok": true, "value": decoded_members, "detail": ""}
	if tag.is_empty():
		return _bad_value(path, "the value has no type tag")
	return _bad_value(path, "unknown type tag '%s'" % tag)


# --- Helpers ----------------------------------------------------------------


static func _refuse(reason: String, detail: String) -> Dictionary:
	return {"ok": false, "payload": {}, "reason": reason, "detail": detail, "version": 0}


static func _bad_value(path: String, detail: String) -> Dictionary:
	return {"ok": false, "value": null, "detail": "%s: %s" % [path, detail]}


static func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "a bool"
		TYPE_INT, TYPE_FLOAT:
			return "a number"
		TYPE_STRING, TYPE_STRING_NAME:
			return "a string"
		TYPE_ARRAY:
			return "an array"
		TYPE_DICTIONARY:
			return "an object"
	return "type %d" % typeof(value)
