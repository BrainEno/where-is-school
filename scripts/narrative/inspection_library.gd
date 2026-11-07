class_name InspectionLibrary
extends RefCounted
## Inspectable object content, in every language, per chapter.
##
## Layout mirrors the dialogue: data/inspections/<locale>/<chapter>.json.
## Descriptions stay short on purpose: a player should be able to read a desk
## without reading a paragraph.

const CHAPTERS: Array[String] = ["classroom", "corridor", "street", "residential", "playground", "alley", "estate_gate"]
const INSPECTION_DIR := "res://data/inspections"


class InspectionData extends RefCounted:
	var inspection_id: StringName = &""
	var title: String = ""
	## Short contextual prompt shown next to the interact key.
	var prompt: String = "Look"
	var speaker_id: StringName = &"protagonist"
	## Narrative category of the observation text itself.
	var source: int = 0
	var text: String = ""
	## Shown instead of `text` after the first read; may be empty.
	var repeat_text: String = ""
	## Optional second line: the protagonist's uncertain memory about the object.
	var recall_text: String = ""
	var recall_entry_id: StringName = &""
	## Entry recorded the first time the object is read.
	var record_entry_id: StringName = &""
	var record_source: int = 0
	var record_text: String = ""
	## Applied once, on first read only.
	var effects: Array = []


var errors: Array[String] = []
var _entries: Dictionary = {}
var _locale: String = L10n.DEFAULT_LOCALE


static func chapter_path(locale: String, chapter: String) -> String:
	return "%s/%s/%s.json" % [INSPECTION_DIR, locale, chapter]


static func load_all() -> InspectionLibrary:
	var library := InspectionLibrary.new()
	for locale in L10n.LOCALES:
		library._entries[locale] = {}
		for chapter in CHAPTERS:
			library._parse_file(chapter_path(locale, chapter), locale)
	library._check_parity()
	library.set_locale(L10n.current)
	return library


func set_locale(locale: String) -> bool:
	var code := L10n.normalize(locale)
	if not _entries.has(code):
		errors.append("InspectionLibrary: no content loaded for locale '%s'." % locale)
		return false
	_locale = code
	return true


func get_locale() -> String:
	return _locale


func is_valid() -> bool:
	return errors.is_empty()


func has_inspection(inspection_id: StringName) -> bool:
	return _entries.get(_locale, {}).has(inspection_id)


func get_inspection(inspection_id: StringName) -> InspectionData:
	return _entries.get(_locale, {}).get(inspection_id, null)


func get_ids(locale: String = "") -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _entries.get(locale if not locale.is_empty() else _locale, {}).keys():
		ids.append(key)
	ids.sort()
	return ids


func get_ids_for(locale: String) -> Array[StringName]:
	return get_ids(locale)


func describe_errors() -> String:
	if errors.is_empty():
		return "Inspection content loaded without errors."
	return "Inspection content has %d error(s):\n%s" % [errors.size(), "\n".join(errors)]


# --- Parsing ----------------------------------------------------------------


func _parse_file(path: String, locale: String) -> void:
	if not FileAccess.file_exists(path):
		errors.append("Inspection file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append(
			"Inspection file could not be opened: %s (error %d)" % [path, FileAccess.get_open_error()]
		)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		errors.append(
			"%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		file.close()
		return
	file.close()

	var root: Variant = json.data
	if not (root is Dictionary):
		errors.append("%s: root value must be an object." % path)
		return
	var data: Dictionary = root
	if data.has("locale") and String(data["locale"]) != locale:
		errors.append(
			"%s: declares locale '%s' but is stored under '%s'." % [path, data["locale"], locale]
		)

	var entries: Dictionary = _entries[locale]
	var raw_inspections: Variant = data.get("inspections", data)
	if not (raw_inspections is Dictionary):
		errors.append("%s: 'inspections' must be an object." % path)
		return
	for key: Variant in (raw_inspections as Dictionary).keys():
		if String(key) in ["format_version", "locale"]:
			continue
		var inspection_id := StringName(String(key))
		var raw: Variant = (raw_inspections as Dictionary)[key]
		if not (raw is Dictionary):
			errors.append("%s: inspection '%s' must be an object." % [path, inspection_id])
			continue
		if entries.has(inspection_id):
			errors.append("%s: duplicate inspection id '%s'." % [path, inspection_id])
			continue
		var entry := _parse_entry(inspection_id, raw as Dictionary, path, locale)
		if entry != null:
			entries[inspection_id] = entry


func _parse_entry(
	inspection_id: StringName, data: Dictionary, path: String, locale: String
) -> InspectionData:
	var context := "%s: inspection '%s'" % [path, inspection_id]
	var entry := InspectionData.new()
	entry.inspection_id = inspection_id
	entry.title = String(data.get("title", "")).strip_edges()
	entry.prompt = String(data.get("prompt", "Look")).strip_edges()
	if entry.prompt.is_empty():
		entry.prompt = L10n.t("prompt.look")
	entry.speaker_id = StringName(String(data.get("speaker", "protagonist")))
	entry.source = _source_or_error(
		String(data.get("source", "observed")), context + " source", NarrativeEntry.Source.OBSERVED
	)
	entry.text = String(data.get("text", "")).strip_edges()
	if entry.text.is_empty():
		errors.append("%s: needs non-empty 'text'." % context)
		return null
	entry.repeat_text = String(data.get("repeat_text", "")).strip_edges()

	if data.has("recall"):
		var recall: Variant = data["recall"]
		if not (recall is Dictionary):
			errors.append("%s: 'recall' must be an object." % context)
		else:
			entry.recall_text = String((recall as Dictionary).get("text", "")).strip_edges()
			entry.recall_entry_id = StringName(String((recall as Dictionary).get("entry_id", "")))
			if entry.recall_text.is_empty() or String(entry.recall_entry_id).is_empty():
				errors.append("%s: 'recall' needs 'text' and 'entry_id'." % context)

	if data.has("record"):
		var record: Variant = data["record"]
		if not (record is Dictionary):
			errors.append("%s: 'record' must be an object." % context)
		else:
			var record_data: Dictionary = record
			entry.record_entry_id = StringName(String(record_data.get("entry_id", "")))
			entry.record_text = String(record_data.get("text", "")).strip_edges()
			entry.record_source = _source_or_error(
				String(record_data.get("source", "observed")),
				context + " record source",
				NarrativeEntry.Source.OBSERVED
			)
			if String(entry.record_entry_id).is_empty() or entry.record_text.is_empty():
				errors.append("%s: 'record' needs 'entry_id' and 'text'." % context)
	entry.effects = _parse_effects(data.get("effects", []), context, locale)
	return entry


func _parse_effects(raw: Variant, context: String, locale: String) -> Array:
	var effects: Array = []
	if raw == null:
		return effects
	if not (raw is Array):
		errors.append("%s: 'effects' must be an array." % context)
		return effects
	for index in (raw as Array).size():
		var raw_effect: Variant = (raw as Array)[index]
		var effect_context := "%s effect #%d" % [context, index]
		if not (raw_effect is Dictionary):
			errors.append("%s: must be an object." % effect_context)
			continue
		var effect: Dictionary = raw_effect
		match String(effect.get("type", "")):
			"set_flag":
				if String(effect.get("flag", "")).is_empty() or not effect.has("value"):
					errors.append("%s: set_flag needs 'flag' and 'value'." % effect_context)
					continue
			"set_objective":
				var key := String(effect.get("key", "")).strip_edges()
				if key.is_empty():
					errors.append(
						"%s: set_objective needs a 'key' (a locale key, not literal text)."
						% effect_context
					)
					continue
				if not L10n.has_key(key, locale):
					errors.append(
						"%s: objective key '%s' does not exist in data/locale/%s.json."
						% [effect_context, key, locale]
					)
					continue
			_:
				errors.append(
					"%s: unsupported type '%s' (inspections support set_flag/set_objective)."
					% [effect_context, String(effect.get("type", ""))]
				)
				continue
		effects.append(effect)
	return effects


func _check_parity() -> void:
	var reference_locale: String = L10n.LOCALES[0]
	var reference := InspectionLibrary.new()
	# get_ids()/get_inspection() read the library's own locale, so the two shells
	# used for the comparison must be told which language they are holding.
	reference._locale = reference_locale
	for locale in L10n.LOCALES:
		if locale == reference_locale:
			reference._entries[reference_locale] = _entries[reference_locale]
			continue
		var other := InspectionLibrary.new()
		other._locale = locale
		other._entries[locale] = _entries[locale]
		errors.append_array(
			DialogueParity.compare_inspections(reference, other, reference_locale, locale)
		)


func _source_or_error(source_name: String, context: String, fallback: int) -> int:
	var value := NarrativeEntry.source_from_id(source_name)
	if value < 0:
		errors.append("%s: unknown source '%s'." % [context, source_name])
		return fallback
	return value
