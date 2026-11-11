extends RefCounted
## Editor-only: the complete pre-save validation pipeline for a narrative edit.
##
## It receives a candidate session from the store, then checks JSON, language parity,
## content-specific field rules, and the runtime loader before returning anything to write.

const JsonText := preload("res://addons/narrative_editor/core/narrative_json_text.gd")
const NarrativePaths := preload("res://addons/narrative_editor/core/narrative_paths.gd")
const FileWriter := preload("res://addons/narrative_editor/core/narrative_file_writer.gd")
const Parity := preload("res://addons/narrative_editor/core/narrative_parity.gd")
const DialogueGraphScript := preload("res://scripts/dialogue/dialogue_graph.gd")
const InnerAbilitiesScript := preload("res://scripts/rpg/inner_abilities.gd")

const KIND_DIALOGUE := "dialogue"
const KIND_INSPECTIONS := "inspections"
const KIND_ABILITIES := "abilities"
const VALIDATION_DIR := "user://narrative_editor_validation"

var kind: String = KIND_DIALOGUE
var chapter: String = ""
var locales: Array[String] = []
var reference_locale: String = "en"
var errors: Array[String] = []
var paths: NarrativePaths = null
var writer: FileWriter = null

var _docs: Dictionary = {}
var _candidate: Dictionary = {}
var _parsed_candidates: Dictionary = {}
var _dialogue_text_leaves: Array[String] = []
var _ability_text_leaves: Array[String] = []


## Returns errors and parsed candidates; no content file is changed during validation.
func validate(
	unit_kind: String,
	unit_chapter: String,
	unit_locales: Array[String],
	unit_reference_locale: String,
	documents: Dictionary,
	file_writer: FileWriter,
	content_paths: NarrativePaths,
	dialogue_text_leaves: Array[String],
	ability_text_leaves: Array[String]
) -> Dictionary:
	kind = unit_kind
	chapter = unit_chapter
	locales = unit_locales
	reference_locale = unit_reference_locale
	_docs = documents
	writer = file_writer
	paths = content_paths
	_dialogue_text_leaves = dialogue_text_leaves
	_ability_text_leaves = ability_text_leaves
	errors.clear()
	_candidate.clear()
	_parsed_candidates.clear()
	for locale: String in locales:
		var doc: JsonText = _docs[locale]
		var text := doc.build_text()
		var json := JSON.new()
		if json.parse(text) != OK:
			errors.append(
			"%s：改写后的文本不是合法 JSON（第 %d 行：%s）。没有写入任何文件。"
			% [doc.path, json.get_error_line(), json.get_error_message()]
		)
		continue
		_candidate[locale] = text
		_parsed_candidates[locale] = json.data
	if not errors.is_empty():
		return _result()
	_check_parity()
	_check_field_rules()
	_check_with_runtime_validator()
	return _result()


func _result() -> Dictionary:
	return {
		"errors": errors.duplicate(),
		"candidate": _candidate,
		"parsed_candidates": _parsed_candidates,
	}


# --- validation -------------------------------------------------------------


func _check_parity() -> void:
	var reference: Variant = _parsed_candidates.get(reference_locale, null)
	if reference == null:
		errors.append("没有 %s 语言的文档可以比较。" % reference_locale)
		return
	for locale: String in locales:
		if locale == reference_locale:
			continue
		var translated: Variant = _parsed_candidates.get(locale, null)
		if translated == null:
			errors.append("没有 %s 语言的文档可以比较。" % locale)
			continue
		var problems := Parity.compare(
			reference,
			translated,
			reference_locale,
			locale,
			func(address: PackedStringArray) -> bool:
				return _is_parity_ignored(address)
		)
		for problem: String in problems:
			errors.append("%s 与 %s 的结构不一致：%s" % [reference_locale, locale, problem])


## The only addresses two languages are allowed to differ on: the declared locale, the
## player-visible text each language owns, and the per-language exception list in the
## ability text.
func _is_parity_ignored(address: PackedStringArray) -> bool:
	if address.is_empty():
		return false
	var leaf := address[address.size() - 1]
	if address.size() == 1 and leaf == "locale":
		return true
	if kind == KIND_ABILITIES:
		return _ability_text_leaves.has(leaf) or leaf == "untranslated_fields"
	return _dialogue_text_leaves.has(leaf)


func _check_field_rules() -> void:
	match kind:
		KIND_DIALOGUE:
			_check_dialogue_rules()
		KIND_INSPECTIONS:
			_check_inspection_rules()
		KIND_ABILITIES:
			_check_ability_rules()


func _check_dialogue_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var conversations: Variant = (root as Dictionary).get("conversations", null)
		if not (conversations is Dictionary):
			continue
		for conversation_id: Variant in (conversations as Dictionary).keys():
			var conversation: Variant = (conversations as Dictionary)[conversation_id]
			if not (conversation is Dictionary):
				continue
			var nodes: Variant = (conversation as Dictionary).get("nodes", null)
			if not (nodes is Array):
				continue
			var node_index := 0
			for node: Variant in (nodes as Array):
				if node is Dictionary:
					var data: Dictionary = node
					var where := "%s：%s/%s" % [path, String(conversation_id), String(data.get("id", "#%d" % node_index))]
					var text := String(data.get("text", "")).strip_edges()
					var choices: Variant = data.get("choices", [])
					var has_choices := choices is Array and (choices as Array).size() > 0
					if text.is_empty() and not has_choices:
						errors.append("%s：正文是空的，而且这个节点没有选项，玩家会看到一片空白。" % where)
					if choices is Array:
						var choice_index := 0
						for choice: Variant in (choices as Array):
							if choice is Dictionary:
								var choice_text := String((choice as Dictionary).get("text", "")).strip_edges()
								if choice_text.is_empty():
									errors.append(
										"%s：第 %d 个选项（%s）的文字是空的。"
										% [where, choice_index + 1, String((choice as Dictionary).get("id", ""))]
									)
							choice_index += 1
				node_index += 1


func _check_inspection_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var data: Dictionary = root
		for key: Variant in data.keys():
			if not _is_inspection_entry(key, data):
				continue
			var entry: Variant = data[key]
			if not (entry is Dictionary):
				continue
			var entry_data: Dictionary = entry
			for required: String in ["title", "prompt", "text"]:
				if String(entry_data.get(required, "")).strip_edges().is_empty():
					errors.append(
						"%s：检视 %s 的 %s 是空的。" % [path, String(key), required]
					)


func _check_ability_rules() -> void:
	for locale: String in locales:
		var root: Variant = _parsed_candidates.get(locale, null)
		if not (root is Dictionary):
			continue
		var path: String = _docs[locale].path if _docs.has(locale) else locale
		var abilities: Variant = (root as Dictionary).get("abilities", null)
		if not (abilities is Dictionary):
			continue
		for ability_id: Variant in (abilities as Dictionary).keys():
			var entry: Variant = (abilities as Dictionary)[ability_id]
			if not (entry is Dictionary):
				continue
			for leaf: String in _ability_text_leaves:
				if String((entry as Dictionary).get(leaf, "")).strip_edges().is_empty():
					errors.append("%s：内心声音 %s 的 %s 是空的。" % [path, String(ability_id), leaf])


## Runs the loader the game itself uses on the candidate text, so a file that would fail at
## start-up is caught before it is written. Dialogue and ability text both have a loader
## that takes a path or a directory; inspection text does not, and is covered by the
## structure check and the field rules above instead.
func _check_with_runtime_validator() -> void:
	if kind == KIND_DIALOGUE:
		_check_with_dialogue_graph()
	elif kind == KIND_ABILITIES:
		_check_with_inner_abilities()


func _check_with_dialogue_graph() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VALIDATION_DIR))
	for locale: String in locales:
		if not _candidate.has(locale):
			continue
		var temp := "%s/%s-%s.json" % [VALIDATION_DIR, locale, chapter]
		var doc: JsonText = _docs[locale]
		var failure := writer.write_atomic(temp, String(_candidate[locale]))
		if not failure.is_empty():
			errors.append("无法写校验用的临时文件：%s" % failure)
			continue
		var graph: Variant = DialogueGraphScript.load_from_file(temp)
		for message: String in graph.errors:
			errors.append(
				"%s：%s" % [doc.path, String(message).replace(temp, doc.path)]
			)
		_remove_file(temp)


func _check_with_inner_abilities() -> void:
	var folder := "%s/abilities" % VALIDATION_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var structure := paths.ability_structure_file()
	var structure_failure := writer.write_atomic(
		"%s/abilities.json" % folder, _read_file_text(structure)
	)
	if not structure_failure.is_empty():
		errors.append("无法写校验用的临时文件：%s" % structure_failure)
		return
	for locale: String in locales:
		if not _candidate.has(locale):
			continue
		var temp := "%s/%s.json" % [folder, locale]
		var failure := writer.write_atomic(temp, String(_candidate[locale]))
		if not failure.is_empty():
			errors.append("无法写校验用的临时文件：%s" % failure)
			return
	var abilities: InnerAbilities = InnerAbilitiesScript.load_all(folder)
	if abilities.is_valid():
		return
	for message: String in abilities.errors:
		errors.append("内心声音文案没有通过校验：%s" % _devalidate_path(message, folder))


func _devalidate_path(message: String, folder: String) -> String:
	var cleaned := message.replace("%s/abilities.json" % folder, paths.ability_structure_file())
	for locale: String in locales:
		cleaned = cleaned.replace(
			"%s/%s.json" % [folder, locale], paths.ability_text_file(locale)
		)
	return cleaned


func _is_inspection_entry(key: Variant, data: Dictionary) -> bool:
	if String(key) in ["format_version", "locale"]:
		return false
	var value: Variant = data[key]
	if not (value is Dictionary):
		return false
	return (value as Dictionary).has("text") or (value as Dictionary).has("title")


func _read_file_text(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _remove_file(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
