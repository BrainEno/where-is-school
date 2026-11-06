class_name NarrativeProvenance
extends RefCounted
## How a piece of narrative information reached the protagonist.
##
## Every dialogue line, inspection result, and ledger entry carries one of these
## kinds so the game can keep four things apart that a school story tends to
## blur together:
##
## - something the player directly saw or handled (objective fact);
## - something a character said out loud (a statement, not necessarily true);
## - something the protagonist half-remembers (uncertain recollection);
## - something the protagonist imagined (never happened in the playable world).
##
## UI code reads [method label_zh] / [method label_en] to show the distinction
## to the player; gameplay code reads [method is_objective] before treating an
## entry as established world state.

enum Kind {
	OBSERVED = 0,
	HEARD = 1,
	RECOLLECTED = 2,
	IMAGINED = 3,
}

const _IDS: Dictionary = {
	"observed": Kind.OBSERVED,
	"heard": Kind.HEARD,
	"recollected": Kind.RECOLLECTED,
	"imagined": Kind.IMAGINED,
}

const _LABELS_ZH: Dictionary = {
	Kind.OBSERVED: "看到的",
	Kind.HEARD: "听到的",
	Kind.RECOLLECTED: "记得的",
	Kind.IMAGINED: "想象的",
}

const _LABELS_EN: Dictionary = {
	Kind.OBSERVED: "observed",
	Kind.HEARD: "heard",
	Kind.RECOLLECTED: "remembered",
	Kind.IMAGINED: "imagined",
}


static func has_id(id: String) -> bool:
	return _IDS.has(id)


static func from_id(id: String) -> int:
	if not _IDS.has(id):
		push_error("Unknown narrative provenance id '%s'. Expected one of: %s." % [id, ", ".join(_IDS.keys())])
		return Kind.OBSERVED
	return _IDS[id]


static func id_of(kind: int) -> String:
	for id: String in _IDS:
		if _IDS[id] == kind:
			return id
	push_error("Unknown narrative provenance kind '%s'." % kind)
	return "observed"


static func is_valid(kind: int) -> bool:
	return _LABELS_ZH.has(kind)


static func label_zh(kind: int) -> String:
	return _LABELS_ZH.get(kind, "")


static func label_en(kind: int) -> String:
	return _LABELS_EN.get(kind, "")


## True only for information the player obtained by looking at or touching the
## playable world. Hearsay, memory, and imagination are explicitly excluded.
static func is_objective(kind: int) -> bool:
	return kind == Kind.OBSERVED
