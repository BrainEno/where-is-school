extends RefCounted
class_name PrologueState
## Read/write helpers for the prologue's story state.
##
## Nothing else in the project calls [method Node.set] on GameState flags by
## hand, and nothing else in the project writes ledger records. Everything goes
## through these two small functions, which means the whole "what does the game
## know" surface can be audited in one screen.
##
## Kept as static helpers on a RefCounted rather than an autoload: it holds no
## state of its own, it just needs to be shared.

static func set_flag(flag: StringName, value: Variant) -> void:
	if String(flag).is_empty():
		push_error("PrologueState.set_flag received an empty flag.")
		return
	GameState.set_flag(flag, value)


static func flag(flag: StringName, default_value: Variant = null) -> Variant:
	return GameState.get_flag(flag, default_value)


static func has(flag: StringName) -> bool:
	return GameState.has_flag(flag)


static func has_all(flags: Array) -> bool:
	for flag_name in flags:
		if not GameState.has_flag(StringName(flag_name)):
			return false
	return true


## Appends a declared record to the ledger. Unknown ids are a content bug, so
## they are reported loudly instead of quietly creating a typo-shaped record.
static func record(record_id: StringName) -> bool:
	if String(record_id).is_empty():
		return false
	if NarrativeLedger.has(record_id):
		return false
	var entry: Dictionary = PrologueRecords.entry_for(record_id)
	if entry.is_empty():
		push_error("PrologueState.record: unknown record id '%s'." % String(record_id))
		return false
	return NarrativeLedger.record(
		record_id,
		entry["kind"],
		String(entry["title"]),
		String(entry["body"]),
		StringName(entry["source"])
	)


static func has_record(record_id: StringName) -> bool:
	return NarrativeLedger.has(record_id)


static func observed(record_id: StringName) -> bool:
	return NarrativeLedger.has_observed(record_id)


## Human-readable summary used by tests, the notebook header, and the PR notes.
static func summary() -> String:
	var counts: Dictionary = NarrativeLedger.kind_counts()
	return "observed=%d heard=%d recalled=%d imagined=%d" % [
		int(counts.get(NarrativeRecord.Kind.OBSERVED, 0)),
		int(counts.get(NarrativeRecord.Kind.HEARD, 0)),
		int(counts.get(NarrativeRecord.Kind.RECALLED, 0)),
		int(counts.get(NarrativeRecord.Kind.IMAGINED, 0)),
	]


static func reset() -> void:
	GameState.clear()
	NarrativeLedger.clear()
