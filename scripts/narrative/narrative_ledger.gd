extends Node
## Append-only record of what the prologue has told the player, tagged by how
## the player came to know it.
##
## The point of this autoload is a single hard rule: story facts never confirm
## themselves. Everything the game records carries a [member NarrativeRecord.Kind],
## and the only kind that counts as a fact is [constant NarrativeRecord.Kind.OBSERVED].
## A line of Q's chatter is [constant NarrativeRecord.Kind.TOLD]; something the
## protagonist half-remembers is [constant NarrativeRecord.Kind.RECALLED]; and the
## imagined confrontation with B is [constant NarrativeRecord.Kind.IMAGINED] and is
## explicitly *not* something that happened.
##
## The ledger is presentation-agnostic plain data. It does not read the scene tree,
## it does not know about nodes, and it can be exercised headlessly (see
## tests/unit/test_narrative_ledger.gd).

signal record_added(record: NarrativeRecord)
signal ledger_cleared

const MAX_RECORDS := 256

var _records: Array[NarrativeRecord] = []


func add(record: NarrativeRecord) -> bool:
	if record == null:
		push_error("NarrativeLedger.add received a null record.")
		return false
	if not record.is_valid():
		push_error("NarrativeLedger.add refused an invalid record with id '%s'." % record.id)
		return false
	if has(record.id):
		return false
	_records.append(record)
	while _records.size() > MAX_RECORDS:
		_records.remove_at(0)
	record_added.emit(record)
	return true


func record(
	record_id: StringName,
	kind: NarrativeRecord.Kind,
	title: String,
	body: String = "",
	source_id: StringName = &""
) -> bool:
	return add(NarrativeRecord.create(record_id, kind, title, body, source_id))


func get_record(record_id: StringName) -> NarrativeRecord:
	for record in _records:
		if record.id == record_id:
			return record
	return null


func has(record_id: StringName) -> bool:
	return get_record(record_id) != null


func has_kind(record_id: StringName, kind: NarrativeRecord.Kind) -> bool:
	var record: NarrativeRecord = get_record(record_id)
	return record != null and record.kind == kind


## True only for things the player saw happen in the playable scene.
func has_observed(record_id: StringName) -> bool:
	return has_kind(record_id, NarrativeRecord.Kind.OBSERVED)


func records() -> Array[NarrativeRecord]:
	return _records.duplicate()


func records_of_kind(kind: NarrativeRecord.Kind) -> Array[NarrativeRecord]:
	var filtered: Array[NarrativeRecord] = []
	for record in _records:
		if record.kind == kind:
			filtered.append(record)
	return filtered


func kind_counts() -> Dictionary:
	var counts: Dictionary = {}
	for record in _records:
		counts[record.kind] = int(counts.get(record.kind, 0)) + 1
	return counts


## Ordered record ids, oldest first. Used by tests to prove an interaction or a
## subjective sequence did not append anything.
func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for record in _records:
		result.append(record.id)
	return result


func to_dict() -> Dictionary:
	var entries: Array = []
	for record in _records:
		entries.append(record.to_dict())
	return {"records": entries}


func clear() -> void:
	_records.clear()
	ledger_cleared.emit()
