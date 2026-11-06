extends RefCounted
class_name NarrativeRecord
## One thing the player has learned, plus how they learned it.
##
## [member kind] is the whole point: the same sentence can be a fact, a rumour,
## a recollection, or an invention, and gameplay code must not confuse them.

enum Kind {
	## Seen or handled by the player directly in the playable scene.
	OBSERVED,
	## Said aloud by a character. Could be wrong, careless, or self-serving.
	HEARD,
	## The protagonist's incomplete, unreliable recollection.
	RECALLED,
	## The protagonist's expectation or rehearsal. This did not happen.
	IMAGINED,
}

const KIND_LABELS: Dictionary = {
	Kind.OBSERVED: "Observed",
	Kind.HEARD: "Heard",
	Kind.RECALLED: "Uncertain memory",
	Kind.IMAGINED: "Imagined — did not happen",
}

var id: StringName = &""
var kind: Kind = Kind.OBSERVED
var title: String = ""
var body: String = ""
var source_id: StringName = &""


static func create(
	record_id: StringName,
	record_kind: Kind,
	record_title: String,
	record_body: String = "",
	record_source_id: StringName = &""
) -> NarrativeRecord:
	var record := NarrativeRecord.new()
	record.id = record_id
	record.kind = record_kind
	record.title = record_title
	record.body = record_body
	record.source_id = record_source_id
	return record


static func kind_label(record_kind: Kind) -> String:
	return String(KIND_LABELS.get(record_kind, "Unclassified"))


func label() -> String:
	return kind_label(kind)


func is_valid() -> bool:
	return not String(id).is_empty() and not title.is_empty()


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"kind": int(kind),
		"title": title,
		"body": body,
		"source": String(source_id),
	}


static func from_dict(data: Dictionary) -> NarrativeRecord:
	var record_kind: Kind = Kind.OBSERVED
	var raw_kind: int = int(data.get("kind", int(Kind.OBSERVED)))
	if raw_kind >= 0 and raw_kind <= int(Kind.IMAGINED):
		record_kind = raw_kind as Kind
	return create(
		StringName(String(data.get("id", ""))),
		record_kind,
		String(data.get("title", "")),
		String(data.get("body", "")),
		StringName(String(data.get("source", "")))
	)


func _to_string() -> String:
	return "NarrativeRecord(%s, %s, %s)" % [String(id), label(), title]
