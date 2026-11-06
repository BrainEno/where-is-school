class_name NarrativeEntry
extends RefCounted
## One recorded piece of narrative information with its provenance and origin.

var id: StringName
var kind: int
var text_zh: String
var text_en: String
## Identifier of the dialogue node, inspection, or sequence that produced this
## entry. Kept for debugging and for tests; presentation code displays the texts.
var source_id: StringName
## Monotonic insertion order so a restored ledger keeps its reading order.
var order: int


func _init(
	p_id: StringName,
	p_kind: int,
	p_text_zh: String,
	p_text_en: String,
	p_source_id: StringName = &"",
	p_order: int = 0
) -> void:
	id = p_id
	kind = p_kind
	text_zh = p_text_zh
	text_en = p_text_en
	source_id = p_source_id
	order = p_order


func to_dictionary() -> Dictionary:
	return {
		"id": String(id),
		"kind": NarrativeProvenance.id_of(kind),
		"zh": text_zh,
		"en": text_en,
		"source": String(source_id),
		"order": order,
	}


static func from_dictionary(data: Dictionary) -> NarrativeEntry:
	var kind_id: String = str(data.get("kind", ""))
	if not NarrativeProvenance.has_id(kind_id):
		push_error("NarrativeEntry.from_dictionary: invalid kind '%s' for id '%s'." % [kind_id, data.get("id", "")])
		return null
	var entry := NarrativeEntry.new(
		StringName(str(data.get("id", ""))),
		NarrativeProvenance.from_id(kind_id),
		str(data.get("zh", "")),
		str(data.get("en", "")),
		StringName(str(data.get("source", ""))),
		int(data.get("order", 0))
	)
	if entry.id == &"" or entry.text_zh.is_empty():
		push_error("NarrativeEntry.from_dictionary: entry is missing an id or Chinese text: %s." % data)
		return null
	return entry
