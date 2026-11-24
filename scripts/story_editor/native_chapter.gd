extends RefCounted
## A native chapter pair, not an operation document. Its exact source-byte fingerprints
## travel alongside the chapter files so a different checkout can refuse replacement.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const ENGLISH := "en"
const LOCALES := [Patch.LOCALE, ENGLISH]
const TEXT_FIELDS := ["text", "repeat_text", "title", "prompt"]
const PENDING_MARK := "〔待译〕 "


static func read_source(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Patch.MAX_BYTES:
		return {}
	var bytes := file.get_buffer(file.get_length())
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return {"data": json.data, "sha256": hash.finish().hex_encode()}


static func compile_pair(zh: Dictionary, graph: DialogueGraph, sources: Dictionary) -> Dictionary:
	var pending: Array[Dictionary] = []
	var path: Array[String] = []
	var en: Dictionary = _mirror(zh, sources[Patch.LOCALE]["data"], sources[ENGLISH]["data"], path, pending)
	en["locale"] = ENGLISH
	var translated := DialogueGraph.load_from_data(en, "authoring:%s/%s" % [ENGLISH, graph.chapter])
	var problems := DialogueParity.compare(graph, translated) if translated.is_valid() else translated.errors
	if not problems.is_empty():
		return {"error": "中英候选章节没有通过校验：\n" + "\n".join(problems)}
	return {"data": en, "graph": translated, "pending": pending}


## Read from each language by stable slot (the same convention as story_doc.text_slots).
## The draft's structure wins; existing English prose never gets overwritten by Chinese.
static func _mirror(value: Variant, old_zh: Variant, old_en: Variant, path: Array[String], pending: Array[Dictionary]) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: String in value:
			var source: Variant = old_zh.get(key) if old_zh is Dictionary else null
			var translation: Variant = old_en.get(key) if old_en is Dictionary else null
			path.append(key)
			if key in TEXT_FIELDS and value[key] is String:
				if not translation is String or source != value[key]:
					pending.append({"path": path.duplicate(), "zh": value[key],
						"zh_before": source, "en_before": translation})
				out[key] = translation if translation is String else PENDING_MARK + value[key]
			else:
				out[key] = _mirror(value[key], source, translation, path, pending)
			path.pop_back()
		return out
	if value is Array:
		var out := []
		for index in value.size():
			var item: Variant = value[index]
			var key := "id" if item is Dictionary and item.has("id") else "entry_id"
			var id := String(item.get(key, "")) if item is Dictionary else ""
			path.append(str(index) if id.is_empty() else ("#" if key == "id" else "@") + id)
			out.append(_mirror(item, _old_item(old_zh, index, key, id), _old_item(old_en, index, key, id), path, pending))
			path.pop_back()
		return out
	return value


static func _old_item(rows: Variant, index: int, key: String, id: String) -> Variant:
	if not rows is Array:
		return null
	if id.is_empty():
		return rows[index] if index < rows.size() else null
	for row: Variant in rows:
		if row is Dictionary and row.get(key) == id:
			return row
	return null


static func files(chapter: String, zh: Dictionary, pair: Dictionary, sources: Dictionary) -> Dictionary:
	var output := {}
	var base_hashes := {}
	var candidate_hashes := {}
	var base_lines := PackedStringArray()
	var candidate_lines := PackedStringArray()
	for locale: String in LOCALES:
		var path := DialogueLibrary.chapter_path(locale, chapter)
		var relative := path.trim_prefix("res://")
		var base_hash: String = sources[locale]["sha256"]
		if FileAccess.get_sha256(path) != base_hash:
			return {"error": "基础章节已变。请重开作者版核对草稿，不导出可能覆盖别处修改的文件。"}
		var text := _json(zh if locale == Patch.LOCALE else pair["data"])
		var hash := text.sha256_text()
		output[relative] = text
		base_hashes[relative] = base_hash
		candidate_hashes[relative] = hash
		base_lines.append("%s  %s" % [base_hash, relative])
		candidate_lines.append("%s  %s" % [hash, relative])
	var pending: Array = pair["pending"]
	output["BASE.sha256"] = "\n".join(base_lines) + "\n"
	output["CANDIDATE.sha256"] = "\n".join(candidate_lines) + "\n"
	output["pending_en.json"] = _json(pending)
	output["chapter-manifest.json"] = _json({"format": "where-is-school/chapter-candidate", "version": 1,
		"chapter": chapter, "base_commit": ProjectSettings.get_setting("authoring/base_commit", "local"),
		"base_sha256": base_hashes, "candidate_sha256": candidate_hashes, "pending_en": pending.size(),
		"status": "review_only", "note": "先核对 BASE.sha256。候选可试玩；待译清单未清零时不要作为英文正式稿。"})
	return {"files": output, "pending": pending.size()}


static func _json(value: Variant) -> String:
	return JSON.stringify(_native_numbers(value), "\t", false, true) + "\n"


## JSON.parse gives Godot doubles even for original integers (format_version,
## check difficulty, modifiers). Keep exact integers as integers in native files.
static func _native_numbers(value: Variant) -> Variant:
	if value is float and absf(value) <= 9_007_199_254_740_991.0 and floorf(value) == value:
		return int(value)
	if value is Dictionary:
		var fields := {}
		for key: String in value:
			fields[key] = _native_numbers(value[key])
		return fields
	if value is Array:
		var rows := []
		for item: Variant in value:
			rows.append(_native_numbers(item))
		return rows
	return value


## Verify the entries, not only that the ZIP was opened. No project files are written.
static func write_archive(path: String, entries: Dictionary) -> Error:
	if entries.is_empty():
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var absolute := ProjectSettings.globalize_path(path)
	var result := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result != OK:
		return result
	var temporary := absolute + "." + Patch.new_id() + ".writing"
	result = _pack(temporary, entries)
	if result == OK and not _verified(temporary, entries):
		result = ERR_FILE_CORRUPT
	if result == OK:
		result = ERR_ALREADY_EXISTS if FileAccess.file_exists(absolute) else DirAccess.rename_absolute(temporary, absolute)
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result


static func _pack(path: String, entries: Dictionary) -> Error:
	var pack := ZIPPacker.new()
	var result := pack.open(path)
	if result != OK:
		return result
	for name: String in entries:
		result = pack.start_file(name)
		if result != OK:
			break
		result = pack.write_file(String(entries[name]).to_utf8_buffer())
		var closed := pack.close_file()
		if result == OK:
			result = closed
		if result != OK:
			break
	var closed := pack.close()
	return closed if result == OK else result


static func _verified(path: String, entries: Dictionary) -> bool:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return false
	var matches := true
	for name: String in reader.get_files():
		if not name.ends_with("/") and not entries.has(name):
			matches = false
			break
	for name: String in entries:
		if not reader.file_exists(name) or reader.read_file(name) != String(entries[name]).to_utf8_buffer():
			matches = false
			break
	reader.close()
	return matches
