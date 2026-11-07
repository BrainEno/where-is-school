extends Node
## Session-wide narrative knowledge log.
##
## GameState owns small gameplay flags. This node owns what the protagonist
## knows and how they know it (observed / reported / recalled / imagined), so a
## character's claim or a private fantasy can never be stored as fact.
##
## Entries are append-only and de-duplicated by entry_id: re-reading the same
## prop does not create a second record and revisiting a scene stays consistent.
## Persistence is left to the future SaveManager (see docs/ARCHITECTURE.md);
## to_snapshot()/restore_snapshot() exist so it has an explicit data shape.

signal entry_recorded(entry: NarrativeEntry)
signal entries_cleared

var _entries: Array[NarrativeEntry] = []
var _by_id: Dictionary = {}


## Records an entry. Returns false when the id already exists or the data is
## invalid, so callers can react instead of assuming success.
func record(
	entry_id: StringName,
	source: int,
	speaker_id: StringName,
	text: String
) -> bool:
	if String(entry_id).is_empty():
		push_error("NarrativeState.record received an empty entry id.")
		return false
	if text.strip_edges().is_empty():
		push_error("NarrativeState.record received empty text for entry '%s'." % entry_id)
		return false
	if _by_id.has(entry_id):
		return false

	var entry := NarrativeEntry.new(entry_id, source, speaker_id, text)
	_entries.append(entry)
	_by_id[entry_id] = entry
	entry_recorded.emit(entry)
	return true


func has_entry(entry_id: StringName) -> bool:
	return _by_id.has(entry_id)


func get_entry(entry_id: StringName) -> NarrativeEntry:
	return _by_id.get(entry_id, null)


func get_entries() -> Array[NarrativeEntry]:
	return _entries.duplicate()


func get_entries_for_source(source: int) -> Array[NarrativeEntry]:
	var result: Array[NarrativeEntry] = []
	for entry in _entries:
		if entry.source == source:
			result.append(entry)
	return result


func count_for_source(source: int) -> int:
	var total := 0
	for entry in _entries:
		if entry.source == source:
			total += 1
	return total


func to_snapshot() -> Dictionary:
	var serialized: Array = []
	for entry in _entries:
		serialized.append(entry.to_dict())
	return {"entries": serialized}


func restore_snapshot(snapshot: Dictionary) -> void:
	_entries.clear()
	_by_id.clear()
	var serialized: Variant = snapshot.get("entries", [])
	if serialized is Array:
		for item: Variant in serialized:
			if item is Dictionary:
				var entry := NarrativeEntry.from_dict(item)
				_entries.append(entry)
				_by_id[entry.entry_id] = entry
	entries_cleared.emit()


func clear() -> void:
	_entries.clear()
	_by_id.clear()
	entries_cleared.emit()
