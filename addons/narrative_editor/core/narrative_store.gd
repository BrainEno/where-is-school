extends RefCounted
## Editor-only: one content session — load a chapter in both languages, edit text, save.
##
## This is the narrative editor's session coordinator, and it knows nothing about Control
## nodes, the editor or the dock. It takes a data root and a writer, delegates read-only
## presentation and candidate validation to sibling helpers, and remains headlessly testable.
##
## Three rules decide its shape.
##
## 1. **Only text is writable.** There is a setter per text field and no setter for
##    anything else — node ids, speakers, branches, conditions, effects, checks, `once`
##    flags and the ability numbers are read out of the parsed file and never written. A
##    tool that cannot express an edit cannot make one by accident.
## 2. **A save is all or nothing.** Both languages are validated (JSON, structure, field
##    rules, then the runtime's own loader) before either file is staged, and the writer
##    rolls back if the second file refuses. A save that reports failure has written
##    nothing.
## 3. **A save is minimal.** Edits are applied to the spans of the strings that changed,
##    so the file keeps its formatting, its field order and every field the tool does not
##    know about, and the diff is the line the author edited.
##
## Messages shown to the author inside the dock are written in Chinese with the file, the
## address and the field spelled out; this editor-only data layer is intentionally localized.

const JsonText := preload("res://addons/narrative_editor/core/narrative_json_text.gd")
const NarrativePaths := preload("res://addons/narrative_editor/core/narrative_paths.gd")
const FileWriter := preload("res://addons/narrative_editor/core/narrative_file_writer.gd")
const NarrativeDescriber := preload("res://addons/narrative_editor/core/narrative_describer.gd")
const NarrativeValidator := preload("res://addons/narrative_editor/core/narrative_validator.gd")

const KIND_DIALOGUE := "dialogue"
const KIND_INSPECTIONS := "inspections"
const KIND_ABILITIES := "abilities"
const KINDS: Array[String] = [KIND_DIALOGUE, KIND_INSPECTIONS, KIND_ABILITIES]

## The leaves a translation may differ on. Everything else has to match between the two
## language files, which is what the save-time structure check enforces.
const DIALOGUE_TEXT_LEAVES: Array[String] = ["text", "title", "prompt", "repeat_text"]
const ABILITY_TEXT_LEAVES: Array[String] = ["name", "description"]

## Inspection fields the author may edit, in the order the dock shows them. The label is
## what the dock puts above the two text boxes.
const INSPECTION_FIELDS: Array[Dictionary] = [
	{"field_id": "title", "key": "title", "label": "标题（检视栏里的小标题）"},
	{"field_id": "prompt", "key": "prompt", "label": "提示（交互键旁边的那句话）"},
	{"field_id": "text", "key": "text", "label": "第一次查看时的正文"},
	{"field_id": "repeat_text", "key": "repeat_text", "label": "再看一次时的正文（可留空）"},
	{"field_id": "recall.text", "key": "recall", "sub": "text", "label": "紧接着的一句回忆（可留空）"},
	{"field_id": "record.text", "key": "record", "sub": "text", "label": "记进回忆录的那段文字（可留空）"},
]


var errors: Array[String] = []
var warnings: Array[String] = []

var paths: NarrativePaths = null
var writer: FileWriter = null

var kind: String = KIND_DIALOGUE
var chapter: String = ""
var locales: Array[String] = []
var reference_locale: String = "en"

var _docs: Dictionary = {}
var _saved_text: Dictionary = {}
var _structure: Dictionary = {}
var _candidate: Dictionary = {}
var _parsed_candidates: Dictionary = {}
var _describer: NarrativeDescriber = null
var _loaded: bool = false


func _init(data_root: String = NarrativePaths.DEFAULT_DATA_ROOT, file_writer: Variant = null) -> void:
	paths = NarrativePaths.new(data_root)
	writer = file_writer if file_writer != null else FileWriter.new()
	locales = L10n.LOCALES.duplicate()
	if not locales.is_empty():
		reference_locale = locales[0]
	_describer = NarrativeDescriber.new()
	_configure_describer()


func _configure_describer() -> void:
	_describer.configure(
		kind,
		locales,
		reference_locale,
		_docs,
		_structure,
		errors,
		paths.ability_structure_file(),
		ABILITY_TEXT_LEAVES,
		INSPECTION_FIELDS
	)


# --- opening ----------------------------------------------------------------


## Loads both languages of one unit. `chapter` is ignored for the ability text, which is
## one file per language rather than one per chapter.
func open(unit_kind: String, unit_chapter: String = "") -> bool:
	errors.clear()
	warnings.clear()
	_docs.clear()
	_saved_text.clear()
	_structure.clear()
	_candidate.clear()
	_parsed_candidates.clear()
	_loaded = false
	kind = unit_kind
	chapter = unit_chapter
	_configure_describer()
	if not KINDS.has(kind):
		errors.append("未知的内容类型：%s。" % kind)
		return false
	if locales.is_empty():
		errors.append("项目没有登记任何语言（L10n.LOCALES 是空的）。")
		return false
	_recover_incomplete_save()
	for locale: String in locales:
		var file := _file_for(locale)
		var doc := JsonText.new()
		if not doc.load_file(file):
			errors.append(doc.error)
			continue
		_docs[locale] = doc
		_saved_text[locale] = doc.text
		var parsed: Variant = JSON.parse_string(doc.text)
		if parsed == null:
			errors.append("%s 不是合法的 JSON。" % file)
			continue
		_structure[locale] = parsed
	if not errors.is_empty():
		return false
	_loaded = true
	if kind != KIND_ABILITIES:
		for missing: String in paths.missing_files(kind):
			warnings.append("缺少文件：%s（另一种语言有，这一种没有）。" % missing)
		for message: String in paths.chapter_warnings(kind):
			warnings.append(message)
	return true


## A save that was interrupted — the editor closed, the machine stopped — leaves a
## `.backup` next to the content instead of a hole. If the file it belongs to is gone, the
## backup is the only copy of that language and is put back; if both exist, the save had
## finished and the leftover is reported rather than deleted, because deleting a file
## nobody asked about is how a tool loses text.
func _recover_incomplete_save() -> void:
	var targets: Array[String] = []
	for locale: String in locales:
		targets.append(_file_for(locale))
	for recovered: String in writer.recover_missing(targets):
		warnings.append("上次保存没有完成，已经把备份还原成 %s。" % recovered)
	for leftover: String in writer.leftovers(targets):
		warnings.append("上次保存留下了 %s；它不属于内容，确认后可以删除。" % leftover)


## Re-reads what is on disk, throwing away unsaved edits. The dock asks before it is
## allowed to do this; the store itself has no opinion about confirmation.
func reload() -> bool:
	return open(kind, chapter)


func is_loaded() -> bool:
	return _loaded


func file_paths() -> Array[String]:
	var files: Array[String] = []
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			files.append((doc as JsonText).path)
	return files


func describe_errors() -> String:
	if errors.is_empty():
		return ""
	return "\n".join(errors)


## Chapters the open kind has files for. Dialogue and inspections have different chapter
## lists on disk, and the ability text has no chapters at all.
func available_chapters(unit_kind: String) -> Array[String]:
	if unit_kind == KIND_ABILITIES:
		return []
	return paths.chapters_on_disk(unit_kind)


# --- listing ----------------------------------------------------------------


func list_ids() -> Array[String]:
	_configure_describer()
	return _describer.list_ids()


func node_entries(conversation_id: String) -> Array[Dictionary]:
	_configure_describer()
	return _describer.node_entries(conversation_id)


func conversation_defaults(conversation_id: String) -> Dictionary:
	_configure_describer()
	return _describer.conversation_defaults(conversation_id)


# --- models -----------------------------------------------------------------


func node_model(conversation_id: String, node_index: int) -> Dictionary:
	_configure_describer()
	return _describer.node_model(conversation_id, node_index)


func inspection_model(inspection_id: String) -> Dictionary:
	_configure_describer()
	return _describer.inspection_model(inspection_id)


func ability_model(ability_id: String) -> Dictionary:
	_configure_describer()
	return _describer.ability_model(ability_id)


# --- editing ----------------------------------------------------------------


## Applies one field of a model. This is the only write path the dock has, and it can only
## reach addresses the model itself produced.
func set_field(field: Dictionary, locale: String, value: String) -> bool:
	var address: Variant = field.get("address", null)
	if not (address is Array):
		errors.append("内部错误：字段没有地址。")
		return false
	return set_text_at(address as Array, locale, value)


## Writes a string at a JSON address in one language. Used by the tests directly and by
## `set_field()` for the dock.
func set_text_at(address: Array, locale: String, value: String) -> bool:
	var doc: Variant = _docs.get(locale, null)
	if doc == null:
		errors.append("没有 %s 语言的文档。" % locale)
		return false
	var text_doc: JsonText = doc
	if not _is_editable_address(address):
		errors.append(
			"%s：%s 不是可以编辑的文本字段（结构信息一律只读）。"
			% [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	if not text_doc.has_path(address):
		errors.append(
			"%s：找不到字段 %s。" % [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	if text_doc.kind_at(address) != "string":
		errors.append(
			"%s：%s 不是文本字段，编辑器不能改它。" % [text_doc.path, text_doc.pointer_of(address)]
		)
		return false
	return text_doc.set_string(address, value)


func is_dirty() -> bool:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null and (doc as JsonText).is_dirty():
			return true
	return false


func edit_count() -> int:
	var total := 0
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			total += (doc as JsonText).edit_count()
	return total


## One line per edited field, for the dock's status strip.
func dirty_summary() -> Array[String]:
	var summary: Array[String] = []
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc == null:
			continue
		var text_doc: JsonText = doc
		if not text_doc.is_dirty():
			continue
		for pointer: String in text_doc.edited_pointers():
			summary.append("%s：%s" % [locale, pointer])
	return summary


func discard_edits() -> void:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null:
			(doc as JsonText).discard_edits()


## The store refuses every address outside the text fields offered by the model, even when
## it is called directly. A node id, branch, condition or ability number is never writable.
func _is_editable_address(address: Array) -> bool:
	if address.is_empty():
		return false
	var leaf := str(address[address.size() - 1])
	match kind:
		KIND_DIALOGUE:
			if leaf != "text" or address.size() < 5:
				return false
			if str(address[0]) != "conversations" or str(address[2]) != "nodes":
				return false
			# conversations/<id>/nodes/<i>/text
			if address.size() == 5:
				return true
			# conversations/<id>/nodes/<i>/choices/<j>/text
			return address.size() == 7 and str(address[4]) == "choices"
		KIND_INSPECTIONS:
			if address.size() == 2:
				return ["title", "prompt", "text", "repeat_text"].has(leaf)
			if address.size() == 3:
				return ["recall", "record"].has(str(address[1])) and leaf == "text"
			return false
		KIND_ABILITIES:
			return (
				address.size() == 3
				and str(address[0]) == "abilities"
				and ABILITY_TEXT_LEAVES.has(leaf)
			)
	return false


# --- saving -----------------------------------------------------------------


## Runs every check a save would run, and writes nothing. `save()` is this plus the write.
func validate() -> bool:
	errors.clear()
	_candidate.clear()
	_parsed_candidates.clear()
	if not _loaded:
		errors.append("还没有打开任何内容。")
		return false
	if not is_dirty():
		return true
	var validator: NarrativeValidator = NarrativeValidator.new()
	var result: Dictionary = validator.validate(
		kind,
		chapter,
		locales,
		reference_locale,
		_docs,
		writer,
		paths,
		DIALOGUE_TEXT_LEAVES,
		ABILITY_TEXT_LEAVES
	)
	var validation_errors: Array = result["errors"]
	for message: Variant in validation_errors:
		errors.append(String(message))
	_candidate = result["candidate"]
	_parsed_candidates = result["parsed_candidates"]
	return errors.is_empty()


func save() -> bool:
	if not validate():
		return false
	if not is_dirty():
		return true
	var targets: Array[String] = []
	var texts: Array[String] = []
	var originals: Array[String] = []
	for locale: String in locales:
		var doc: JsonText = _docs[locale]
		targets.append(doc.path)
		texts.append(String(_candidate[locale]))
		originals.append(String(_saved_text.get(locale, "")))
	var failure := writer.save_pair(targets, texts, originals)
	if not failure.is_empty():
		errors.append("保存失败，两个语言文件都保持原样：%s" % failure)
		return false
	for index in locales.size():
		var locale := locales[index]
		var doc: JsonText = _docs[locale]
		if not doc.scan_text(texts[index]):
			errors.append(doc.error)
			return false
		_saved_text[locale] = texts[index]
		_structure[locale] = _parsed_candidates[locale]
	_candidate.clear()
	_parsed_candidates.clear()
	return true


# --- searching --------------------------------------------------------------


## Finds `query` in the ids, speakers and text of the open unit, in both languages, and
## leaves one hit per field with the languages that matched. The dock turns a hit into a
## selection.
func search(query: String) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var needle := query.strip_edges().to_lower()
	if needle.is_empty() or not _loaded:
		return hits
	_configure_describer()
	for field: Dictionary in _describer.all_fields():
		var matched: Array[String] = []
		var snippet := ""
		for locale: String in locales:
			var value := String((field["values"] as Dictionary).get(locale, ""))
			var context_text := String(field.get("search_context", "")).to_lower()
			if value.to_lower().contains(needle) or context_text.contains(needle):
				matched.append(locale)
				if snippet.is_empty():
					snippet = _snippet(value, needle)
		if matched.is_empty():
			continue
		var hit: Dictionary = field.duplicate(true)
		hit.erase("values")
		hit["locales"] = matched
		hit["snippet"] = snippet
		hits.append(hit)
	return hits


func _snippet(value: String, needle: String) -> String:
	var flat := " ".join(value.split("\n", false))
	if flat.length() <= 80:
		return flat
	var at := flat.to_lower().find(needle)
	if at < 0:
		return flat.substr(0, 80) + "…"
	var start := maxi(0, at - 30)
	var end := mini(flat.length(), at + 50)
	return ("…" if start > 0 else "") + flat.substr(start, end - start) + ("…" if end < flat.length() else "")


# --- lookups ----------------------------------------------------------------


func _file_for(locale: String) -> String:
	match kind:
		KIND_INSPECTIONS:
			return paths.inspection_file(locale, chapter)
		KIND_ABILITIES:
			return paths.ability_text_file(locale)
		_:
			return paths.dialogue_file(locale, chapter)
