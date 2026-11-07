class_name InspectionLibrary
extends RefCounted
## Inspectable object content: short observation text, repeat text, an optional
## uncertain recollection, and the state changes the first read performs.
##
## Descriptions are written for the game and stay deliberately short: the player
## should be able to read a desk without reading a paragraph.

const INSPECTION_PATHS: Array[String] = [
	"res://data/inspections/classroom.json",
	"res://data/inspections/corridor.json",
]


class InspectionData extends RefCounted:
	var inspection_id: StringName = &""
	var title: String = ""
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


static func load_all() -> InspectionLibrary:
	var library := InspectionLibrary.new()
	for path in INSPECTION_PATHS:
		library._parse_file(path)
	return library


func is_valid() -> bool:
	return errors.is_empty()


func has_inspection(inspection_id: StringName) -> bool:
	return _entries.has(inspection_id)


func get_inspection(inspection_id: StringName) -> InspectionData:
	return _entries.get(inspection_id, null)


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _entries.keys():
		ids.append(key)
	return ids


func describe_errors() -> String:
	if errors.is_empty():
		return "Inspection content loaded without errors."
	return "Inspection content has %d error(s):\n%s" % [errors.size(), "\n".join(errors)]


# --- Parsing ----------------------------------------------------------------


func _parse_file(path: String) -> void:
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
		return
	file.close()

	var root: Variant = json.data
	if not (root is Dictionary):
		errors.append("%s: root value must be an object." % path)
		return

	for key: Variant in (root as Dictionary).keys():
		var inspection_id := StringName(String(key))
		var raw: Variant = (root as Dictionary)[key]
		if not (raw is Dictionary):
			errors.append("%s: inspection '%s' must be an object." % [path, inspection_id])
			continue
		if _entries.has(inspection_id):
			errors.append("Duplicate inspection id '%s' in %s" % [inspection_id, path])
			continue
		var entry := _parse_entry(inspection_id, raw as Dictionary, path)
		if entry != null:
			_entries[inspection_id] = entry


func _parse_entry(inspection_id: StringName, data: Dictionary, path: String) -> InspectionData:
	var context := "%s: inspection '%s'" % [path, inspection_id]
	var entry := InspectionData.new()
	entry.inspection_id = inspection_id
	entry.title = String(data.get("title", "")).strip_edges()
	entry.prompt = String(data.get("prompt", "Look")).strip_edges()
	if entry.prompt.is_empty():
		entry.prompt = "Look"
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
			entry.recall_entry_id = StringName(
				String((recall as Dictionary).get("entry_id", ""))
			)
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
	entry.effects = _parse_effects(data.get("effects", []), context)
	return entry


func _parse_effects(raw: Variant, context: String) -> Array:
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
				if String(effect.get("text", "")).strip_edges().is_empty():
					errors.append("%s: set_objective needs 'text'." % effect_context)
					continue
			_:
				errors.append(
					"%s: unsupported type '%s' (inspections support set_flag/set_objective)."
					% [effect_context, String(effect.get("type", ""))]
				)
				continue
		effects.append(effect)
	return effects


func _source_or_error(
	source_name: String, context: String, fallback: int
) -> int:
	var value := NarrativeEntry.source_from_id(source_name)
	if value < 0:
		errors.append("%s: unknown source '%s'." % [context, source_name])
		return fallback
	return value
