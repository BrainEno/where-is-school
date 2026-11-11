extends Node
## Session-wide narrative knowledge log.
##
## GameState owns small gameplay flags. This node owns what the protagonist
## knows and how they know it (observed / reported / recalled / imagined), so a
## character's claim or a private fantasy can never be stored as fact.
##
## Entries are append-only and de-duplicated by entry_id: re-reading the same
## prop does not create a second record and revisiting a scene stays consistent.
## `to_snapshot()`/`restore_snapshot()` are the data shape `SaveManager` writes and
## reads (ADR 0005); a restore validates every entry with the same rules `record()`
## uses, so a save is never a second, more permissive way in.

signal entry_recorded(entry: NarrativeEntry)
signal entries_cleared
## Emitted after a restore, with how many entries the file produced. The restored
## entries are already in the log when this fires, so a listener can rebuild a view
## without diffing.
signal entries_restored(count: int)

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
	var problem := validate(entry_id, source, text)
	if not problem.is_empty():
		push_error("NarrativeState.record: %s." % problem)
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


## The rules `record()` applies, as a sentence. Shared with the save reader so
## stored knowledge and live knowledge cannot drift apart.
func validate(entry_id: StringName, source: int, text: String) -> String:
	if String(entry_id).strip_edges().is_empty():
		return "an entry has no identifier"
	if text.strip_edges().is_empty():
		return "entry '%s' has no text" % entry_id
	if NarrativeEntry.source_to_id(source).is_empty():
		return "entry '%s' has unknown source %d" % [entry_id, source]
	return ""


## Replaces the log with the entries a snapshot describes.
##
## Structural problems (no `entries` array) are refused and change nothing. A single
## entry that cannot be trusted is *rejected on its own* - never downgraded to
## `observed` - reported in `rejected`, and the rest of the file still loads: one bad
## line in a save must not cost the player the run (ADR 0005 §5).
##
## Returns `{ok, restored, rejected}`.
func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var serialized: Variant = snapshot.get("entries", null)
	if serialized == null:
		serialized = []
	if not (serialized is Array):
		var detail := "'entries' is not an array"
		push_error("NarrativeState.restore_snapshot: %s; the log is unchanged." % detail)
		return {"ok": false, "restored": 0, "rejected": [detail]}

	var incoming: Array[NarrativeEntry] = []
	var rejected: Array[String] = []
	var seen: Dictionary = {}
	for item: Variant in serialized:
		if not (item is Dictionary):
			rejected.append("an entry is not an object")
			continue
		var parsed := NarrativeEntry.parse_dict(item)
		if parsed["ok"] != true:
			rejected.append(String(parsed["detail"]))
			continue
		var entry: NarrativeEntry = parsed["entry"]
		if seen.has(entry.entry_id):
			rejected.append("entry '%s' appears twice" % entry.entry_id)
			continue
		seen[entry.entry_id] = true
		incoming.append(entry)

	_entries.clear()
	_by_id.clear()
	for entry in incoming:
		_entries.append(entry)
		_by_id[entry.entry_id] = entry
	for problem in rejected:
		push_error("NarrativeState.restore_snapshot: rejected %s." % problem)
	entries_restored.emit(_entries.size())
	return {"ok": true, "restored": _entries.size(), "rejected": rejected}


func clear() -> void:
	_entries.clear()
	_by_id.clear()
	entries_cleared.emit()
