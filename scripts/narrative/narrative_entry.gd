class_name NarrativeEntry
extends RefCounted
## One narrative statement plus how the protagonist came to know it.
##
## The four sources are deliberately distinct and must never be silently
## converted into one another:
##
## - OBSERVED: the player directly saw, heard, or did this in the playable world.
## - REPORTED: another character asserted it (Q, N). It is a claim, not evidence.
## - RECALLED: the protagonist's own memory, which may be incomplete or wrong.
## - IMAGINED: subjective anticipation. Nothing in it happened.
##
## Story flags record gameplay bookkeeping; entries record knowledge. Keeping
## them separate is what stops an imagined scene from becoming a fact.

enum Source {
	OBSERVED = 0,
	REPORTED = 1,
	RECALLED = 2,
	IMAGINED = 3,
}

## Content files use these lowercase identifiers; they are part of the data
## contract and must not be renamed without migrating existing dialogue.
const SOURCE_IDS: Dictionary = {
	"observed": Source.OBSERVED,
	"reported": Source.REPORTED,
	"recalled": Source.RECALLED,
	"imagined": Source.IMAGINED,
}

## Locale keys for the badge shown next to a speaker. The interface translates
## them, so the four categories read the same way in every language.
const SOURCE_LABEL_KEYS: Dictionary = {
	Source.OBSERVED: "badge.observed",
	Source.REPORTED: "badge.reported",
	Source.RECALLED: "badge.recalled",
	Source.IMAGINED: "badge.imagined",
}

var entry_id: StringName = &""
var source: int = Source.OBSERVED
var speaker_id: StringName = &""
var text: String = ""


func _init(
	p_entry_id: StringName = &"",
	p_source: int = Source.OBSERVED,
	p_speaker_id: StringName = &"",
	p_text: String = ""
) -> void:
	entry_id = p_entry_id
	source = p_source
	speaker_id = p_speaker_id
	text = p_text


## Returns -1 when the identifier is not part of the content contract, so
## loaders can report the invalid value instead of guessing a source.
static func source_from_id(source_name: String) -> int:
	if not SOURCE_IDS.has(source_name):
		return -1
	return int(SOURCE_IDS[source_name])


static func source_to_id(value: int) -> String:
	for key: String in SOURCE_IDS.keys():
		if int(SOURCE_IDS[key]) == int(value):
			return key
	return ""


## Locale key of the badge, e.g. "badge.imagined". Callers translate it.
static func badge_key_for(value: int) -> String:
	return String(SOURCE_LABEL_KEYS.get(value, "badge.observed"))


func get_source_name() -> String:
	return source_to_id(source)


func to_dict() -> Dictionary:
	return {
		"entry_id": String(entry_id),
		"source": get_source_name(),
		"speaker_id": String(speaker_id),
		"text": text,
	}


## The rules `NarrativeState.record()` applies to live data, applied to stored data.
## Returns `""` when the entry can be trusted, or a sentence naming what is wrong.
##
## This is a *shared* function on purpose: a save must not be a second, more
## permissive way to write knowledge into the log. `record()` refuses these too.
static func validate_dict(data: Dictionary) -> String:
	var entry_id := String(data.get("entry_id", ""))
	if entry_id.strip_edges().is_empty():
		return "an entry has no identifier"
	var text := String(data.get("text", ""))
	if text.strip_edges().is_empty():
		return "entry '%s' has no text" % entry_id
	var source_name := String(data.get("source", ""))
	if source_from_id(source_name) < 0:
		return "entry '%s' has unknown source '%s'" % [entry_id, source_name]
	return ""


## Parses a stored entry. Returns `{ok, entry, detail}`; `entry` is null when the
## data cannot be trusted.
##
## An unknown source is refused rather than downgraded to `observed`: that
## downgrade is the one transformation the whole knowledge model exists to prevent
## (ADR 0002), and it is exactly what this function used to do.
static func parse_dict(data: Dictionary) -> Dictionary:
	var problem := validate_dict(data)
	if not problem.is_empty():
		return {"ok": false, "entry": null, "detail": problem}
	return {
		"ok": true,
		"entry":
		NarrativeEntry.new(
			StringName(data.get("entry_id", "")),
			source_from_id(String(data.get("source", ""))),
			StringName(data.get("speaker_id", "")),
			String(data.get("text", ""))
		),
		"detail": "",
	}
