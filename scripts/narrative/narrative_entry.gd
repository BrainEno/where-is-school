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

const SOURCE_LABELS: Dictionary = {
	Source.OBSERVED: "SEEN",
	Source.REPORTED: "HEARD",
	Source.RECALLED: "REMEMBERED",
	Source.IMAGINED: "IMAGINED",
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


static func badge_for(value: int) -> String:
	return String(SOURCE_LABELS.get(value, "NOTE"))


func get_source_name() -> String:
	return source_to_id(source)


func to_dict() -> Dictionary:
	return {
		"entry_id": String(entry_id),
		"source": get_source_name(),
		"speaker_id": String(speaker_id),
		"text": text,
	}


static func from_dict(data: Dictionary) -> NarrativeEntry:
	var source_name := String(data.get("source", "observed"))
	var source_value := source_from_id(source_name)
	if source_value < 0:
		push_error(
			"NarrativeEntry.from_dict: unknown source '%s' in entry '%s'."
			% [source_name, String(data.get("entry_id", ""))]
		)
		source_value = int(Source.OBSERVED)
	return NarrativeEntry.new(
		StringName(data.get("entry_id", "")),
		source_value,
		StringName(data.get("speaker_id", "")),
		String(data.get("text", ""))
	)
