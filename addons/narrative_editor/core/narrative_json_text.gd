extends RefCounted
## Editor-only: one JSON file, kept as the exact characters on disk, edited in place.
##
## Rewriting a content file with `JSON.stringify()` would be three lines of code and is
## exactly what this class exists to avoid. Re-serialising normalises numbers, drops
## whatever a future schema adds, and turns a one-word correction into a whole-file diff:
## the author could no longer read their own save. Instead the text is scanned once into
## spans, and a save replaces only the spans that were edited, so everything else —
## indentation, key order, unknown fields, the trailing newline — survives byte for byte.
##
## The scanner is deliberately small rather than clever: it understands exactly what JSON
## allows and reports a position for anything else. It is not a validator; `JSON` stays
## the parser of record, and the store re-parses every candidate before writing it.
##
## Field addresses are arrays of keys and indices, e.g.
## `["conversations", "q_wake", "nodes", 3, "text"]`, and are printed the way the rest of
## the project prints them: `conversations/q_wake/nodes/3/text`.

const WHITESPACE := " \t\r\n"
const DELIMITERS := " \t\r\n,]}:"

var path: String = ""
## The text as it is on disk (or as it was last saved).
var text: String = ""
## Empty when the file was read and scanned; a human-readable reason otherwise.
var error: String = ""

var _root: Dictionary = {}
## pointer -> {"start": int, "end": int, "text": String, "value": String}
var _edits: Dictionary = {}
var _edit_order: Array[String] = []
var _cursor: int = 0
var _scan_error: String = ""


# --- loading ----------------------------------------------------------------


func load_file(file_path: String) -> bool:
	path = file_path
	error = ""
	_edits.clear()
	_edit_order.clear()
	if not FileAccess.file_exists(file_path):
		error = "找不到文件：%s" % file_path
		return false
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		error = "无法打开 %s（错误码 %d）。" % [file_path, FileAccess.get_open_error()]
		return false
	text = file.get_as_text()
	file.close()
	if not _scan():
		error = "%s：%s" % [file_path, _scan_error]
		return false
	return true


## Re-scans `text`. Used after a successful save, when the file on disk *is* the text
## that was just written.
func scan_text(new_text: String) -> bool:
	text = new_text
	_edits.clear()
	_edit_order.clear()
	if not _scan():
		error = "%s：%s" % [path, _scan_error]
		return false
	return true


func _scan() -> bool:
	_root = {}
	_scan_error = ""
	_cursor = 0
	_skip_space()
	if _cursor >= text.length():
		_scan_error = "文件是空的。"
		return false
	var node := _scan_value()
	if not _scan_error.is_empty():
		return false
	_skip_space()
	if _cursor < text.length():
		_scan_error = "第 %d 个字符处之后还有多余内容。" % _cursor
		return false
	_root = node
	return true


# --- reading ----------------------------------------------------------------


func has_path(field_path: Array) -> bool:
	return not _node_at(field_path).is_empty()


## The kind of the value at `field_path`: `object`, `array`, `string`, `number`,
## `literal`, or an empty string when the address does not exist.
func kind_at(field_path: Array) -> String:
	var node := _node_at(field_path)
	if node.is_empty():
		return ""
	return String(node.get("kind", ""))


## The decoded string at `field_path`, or an empty string when it is missing or is not
## a string. Callers that need to tell "missing" from "empty" use `has_path()`.
func get_string(field_path: Array) -> String:
	var node := _node_at(field_path)
	if node.is_empty() or String(node.get("kind", "")) != "string":
		return ""
	return String(node.get("value", ""))


## The value at `field_path`, parsed out of its own span. Only used for read-only
## display; the store keeps whole-file parses for anything structural.
func get_value(field_path: Array) -> Variant:
	var node := _node_at(field_path)
	if node.is_empty():
		return null
	return JSON.parse_string(text.substr(int(node["start"]), int(node["end"]) - int(node["start"])))


# --- editing ----------------------------------------------------------------


## Replaces the string at `field_path`. Returns false when the address does not exist or
## does not hold a string: the editor never invents a field, and never changes the kind
## of an existing one.
func set_string(field_path: Array, value: String) -> bool:
	var node := _node_at(field_path)
	if node.is_empty():
		return false
	if String(node.get("kind", "")) != "string":
		return false
	var pointer := pointer_of(field_path)
	if value == String(node.get("value", "")):
		# Writing back the text that is already there must not produce an edit: an author
		# who opens a line, reads it and saves has not changed anything.
		if _edits.has(pointer):
			_edits.erase(pointer)
			_edit_order.erase(pointer)
		return true
	if not _edits.has(pointer):
		_edit_order.append(pointer)
	_edits[pointer] = {
		"start": int(node["start"]),
		"end": int(node["end"]),
		"text": encode_string(value),
		"value": value,
	}
	return true


func is_dirty() -> bool:
	return not _edits.is_empty()


func edit_count() -> int:
	return _edits.size()


## The addresses that are currently edited, in the order they were first touched.
func edited_pointers() -> Array[String]:
	var pointers: Array[String] = []
	for pointer in _edit_order:
		pointers.append(String(pointer))
	return pointers


## The value the author sees: the pending edit when there is one, the text on disk
## otherwise. Lists and search read through this so an unsaved line is searchable.
func effective_string(field_path: Array, fallback: String = "") -> String:
	var pointer := pointer_of(field_path)
	if _edits.has(pointer):
		return String(_edits[pointer]["value"])
	if has_path(field_path):
		return get_string(field_path)
	return fallback


func discard_edits() -> void:
	_edits.clear()
	_edit_order.clear()


## The whole file with the edits applied, without touching the disk.
func build_text() -> String:
	if _edits.is_empty():
		return text
	var spans: Array[Dictionary] = []
	for pointer in _edit_order:
		var edit: Dictionary = _edits[pointer]
		spans.append(edit)
	# Applied from the end, so an earlier span's offsets stay valid after a later one
	# changed the length of the text.
	spans.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["start"]) > int(right["start"])
	)
	var built := text
	for span in spans:
		var start := int(span["start"])
		var end := int(span["end"])
		built = built.substr(0, start) + String(span["text"]) + built.substr(end)
	return built


func pointer_of(field_path: Array) -> String:
	var parts: PackedStringArray = []
	for part: Variant in field_path:
		parts.append(str(part))
	return "/".join(parts)


# --- scanning ---------------------------------------------------------------


func _skip_space() -> void:
	while _cursor < text.length() and WHITESPACE.contains(text[_cursor]):
		_cursor += 1


func _peek() -> String:
	if _cursor >= text.length():
		return ""
	return text[_cursor]


func _scan_value() -> Dictionary:
	_skip_space()
	if _cursor >= text.length():
		_scan_error = "值在文件结束前就断了。"
		return {}
	var head := _peek()
	if head == "{":
		return _scan_object()
	if head == "[":
		return _scan_array()
	if head == "\"":
		return _scan_string()
	return _scan_literal()


func _scan_object() -> Dictionary:
	var start := _cursor
	_cursor += 1
	var members: Dictionary = {}
	var order: Array[String] = []
	_skip_space()
	var done := false
	if _peek() == "}":
		_cursor += 1
		done = true
	while not done:
		_skip_space()
		if _peek() != "\"":
			_scan_error = "对象里的键必须是字符串（第 %d 个字符）。" % _cursor
			return {}
		var key_node := _scan_string()
		if not _scan_error.is_empty():
			return {}
		_skip_space()
		if _peek() != ":":
			_scan_error = "键 '%s' 后面缺少冒号（第 %d 个字符）。" % [String(key_node["value"]), _cursor]
			return {}
		_cursor += 1
		var value_node := _scan_value()
		if not _scan_error.is_empty():
			return {}
		var key := String(key_node["value"])
		members[key] = value_node
		order.append(key)
		_skip_space()
		var next_char := _peek()
		if next_char == ",":
			_cursor += 1
		elif next_char == "}":
			_cursor += 1
			done = true
		else:
			_scan_error = "对象在第 %d 个字符处需要一个逗号或右大括号。" % _cursor
			return {}
	return {"kind": "object", "start": start, "end": _cursor, "members": members, "order": order}


func _scan_array() -> Dictionary:
	var start := _cursor
	_cursor += 1
	var items: Array[Dictionary] = []
	_skip_space()
	var done := false
	if _peek() == "]":
		_cursor += 1
		done = true
	while not done:
		var item := _scan_value()
		if not _scan_error.is_empty():
			return {}
		items.append(item)
		_skip_space()
		var next_char := _peek()
		if next_char == ",":
			_cursor += 1
		elif next_char == "]":
			_cursor += 1
			done = true
		else:
			_scan_error = "数组在第 %d 个字符处需要一个逗号或右方括号。" % _cursor
			return {}
	return {"kind": "array", "start": start, "end": _cursor, "items": items}


func _scan_string() -> Dictionary:
	var start := _cursor
	_cursor += 1
	while _cursor < text.length():
		var head := text[_cursor]
		if head == "\\":
			# Skip the escape and whatever it escapes; the value is decoded by the real
			# parser below, not by reassembling it here.
			_cursor += 2
			continue
		if head == "\"":
			_cursor += 1
			var raw := text.substr(start, _cursor - start)
			var decoded: Variant = JSON.parse_string(raw)
			if not (decoded is String):
				_scan_error = "第 %d 个字符处的字符串无法解析。" % start
				return {}
			return {"kind": "string", "start": start, "end": _cursor, "value": decoded}
		_cursor += 1
	_scan_error = "第 %d 个字符处的字符串没有结束引号。" % start
	return {}


func _scan_literal() -> Dictionary:
	var start := _cursor
	while _cursor < text.length() and not DELIMITERS.contains(text[_cursor]):
		_cursor += 1
	var raw := text.substr(start, _cursor - start)
	if raw.is_empty():
		_scan_error = "第 %d 个字符处无法识别的值。" % start
		return {}
	if raw == "true" or raw == "false" or raw == "null":
		return {"kind": "literal", "start": start, "end": _cursor, "text": raw}
	if raw.is_valid_int() or raw.is_valid_float():
		return {"kind": "number", "start": start, "end": _cursor, "text": raw}
	_scan_error = "第 %d 个字符处的 '%s' 不是合法的 JSON 值。" % [start, raw]
	return {}


func _node_at(field_path: Array) -> Dictionary:
	var node := _root
	if node.is_empty():
		return {}
	for part: Variant in field_path:
		var kind := String(node.get("kind", ""))
		if kind == "object":
			var members: Dictionary = node.get("members", {})
			var key := str(part)
			if not members.has(key):
				return {}
			node = members[key]
		elif kind == "array":
			var items: Array = node.get("items", [])
			var index := int(part)
			if index < 0 or index >= items.size():
				return {}
			node = items[index]
		else:
			return {}
	return node


# --- writing ----------------------------------------------------------------


## JSON string literal for `value`: quotes and backslashes escaped, control characters
## escaped, everything else written as the UTF-8 it already is. The content files carry
## their Chinese as text, not as `\uXXXX`, and a save must not change that.
static func encode_string(value: String) -> String:
	var out := "\""
	for index in value.length():
		var character := value[index]
		if character == "\"":
			out += "\\\""
		elif character == "\\":
			out += "\\\\"
		elif character == "\n":
			out += "\\n"
		elif character == "\r":
			out += "\\r"
		elif character == "\t":
			out += "\\t"
		elif character == "\b":
			out += "\\b"
		elif character == "\f":
			out += "\\f"
		elif character.unicode_at(0) < 0x20:
			out += "\\u%04x" % character.unicode_at(0)
		else:
			out += character
	return out + "\""
