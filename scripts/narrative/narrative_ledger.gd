class_name NarrativeLedger
extends RefCounted
## Runtime record of what the protagonist has observed, been told, recalled, and
## imagined during the prologue.
##
## Ownership: this object is *data*. It performs no scene access, no input
## handling, and no UI work, so it can be unit tested headlessly and serialized
## without touching the scene tree. PrologueFlow (a scene-level controller) is
## the only node that writes to it; DialoguePanel and NoteBook read from it.
##
## Each entry keeps its provenance. That is the mechanism that prevents an
## imagined confrontation with B, or Q's claim about the exam result, from being
## silently promoted to established fact.

signal entry_recorded(entry: NarrativeEntry)
signal ledger_reset

var _entries: Array[NarrativeEntry] = []
var _by_id: Dictionary = {}
var _next_order: int = 0


func record(
	id: StringName,
	kind: int,
	text_zh: String,
	text_en: String,
	source_id: StringName = &""
) -> NarrativeEntry:
	if id == &"":
		push_error("NarrativeLedger.record received an empty entry id.")
		return null
	if not NarrativeProvenance.is_valid(kind):
		push_error("NarrativeLedger.record received an unknown provenance kind '%s' for '%s'." % [kind, id])
		return null
	if text_zh.strip_edges().is_empty():
		push_error("NarrativeLedger.record received empty Chinese text for '%s'." % id)
		return null
	if text_en.strip_edges().is_empty():
		push_error("NarrativeLedger.record received empty English text for '%s'." % id)
		return null

	var existing: NarrativeEntry = _by_id.get(id)
	if existing != null:
		# Entries are append-only by identity: re-reading the same object rewrites
		# nothing, which is what keeps a revisit from duplicating the notebook.
		if existing.kind != kind or existing.text_zh != text_zh or existing.text_en != text_en:
			push_error("NarrativeLedger.record tried to rewrite existing entry '%s'. Use a new id." % id)
		return existing

	var entry := NarrativeEntry.new(id, kind, text_zh, text_en, source_id, _next_order)
	_next_order += 1
	_entries.append(entry)
	_by_id[id] = entry
	entry_recorded.emit(entry)
	return entry


func has(id: StringName) -> bool:
	return _by_id.has(id)


func get_entry(id: StringName) -> NarrativeEntry:
	return _by_id.get(id)


func all_entries() -> Array[NarrativeEntry]:
	return _entries.duplicate()


func entries_of_kind(kind: int) -> Array[NarrativeEntry]:
	var result: Array[NarrativeEntry] = []
	for entry: NarrativeEntry in _entries:
		if entry.kind == kind:
			result.append(entry)
	return result


## Objective world knowledge only. Used by gameplay code that must not react to
## hearsay or imagination (for example, whether the exit has been seen).
func has_observed(id: StringName) -> bool:
	var entry: NarrativeEntry = _by_id.get(id)
	return entry != null and NarrativeProvenance.is_objective(entry.kind)


func count() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()
	_by_id.clear()
	_next_order = 0
	ledger_reset.emit()


func to_array() -> Array:
	var result: Array = []
	for entry: NarrativeEntry in _entries:
		result.append(entry.to_dictionary())
	return result


func restore_from_array(data: Array) -> void:
	clear()
	for item: Variant in data:
		if typeof(item) != TYPE_DICTIONARY:
			push_error("NarrativeLedger.restore_from_array skipped a non-dictionary entry.")
			continue
		var entry := NarrativeEntry.from_dictionary(item as Dictionary)
		if entry == null:
			continue
		if _by_id.has(entry.id):
			push_error("NarrativeLedger.restore_from_array found duplicate entry id '%s'." % entry.id)
			continue
		_entries.append(entry)
		_by_id[entry.id] = entry
		_next_order = maxi(_next_order, entry.order + 1)
	ledger_reset.emit()
	for entry: NarrativeEntry in _entries:
		entry_recorded.emit(entry)
