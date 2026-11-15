class_name JournalPage
extends RefCounted
## What the notebook shows at one moment: the log's entries, worded in the language on
## screen, filed under the place each was learned in, optionally narrowed to one kind of
## knowledge.
##
## Pure: it reads the entries it is given and a `JournalCatalog`, and returns plain
## dictionaries. The panel draws them; the tests read them without building a single
## control. Nothing here touches `NarrativeState` or the story flags.
##
## Shape of `compose()`:
##
##     {"filter": int,                     # ALL or a NarrativeEntry.Source
##      "total": int,                      # entries in the log, whatever the filter
##      "shown": int,                      # rows on this page
##      "unread": int,                     # entries not yet seen in the notebook
##      "counts": {ALL: int, Source.OBSERVED: int, ...},
##      "place_counts": {place_key: int, ...},  # every entry, whatever the filter
##      "sections": [{"place_key": String, "rows": [row, ...]}, ...]}
##
## and of a row:
##
##     {"entry_id": StringName, "source": int, "badge_key": String,
##      "speaker_id": StringName, "attribution": String, "text": String,
##      "place_key": String, "is_new": bool, "index": int}
##
## Order is the player's: sections appear in the order their first entry was learned and
## rows keep the order of the log. The notebook is a record of this run, not an index of
## the content.

const ALL := -1
## Every kind of knowledge, in the order the notebook offers them.
const SOURCES: Array[int] = [
	NarrativeEntry.Source.OBSERVED,
	NarrativeEntry.Source.REPORTED,
	NarrativeEntry.Source.RECALLED,
	NarrativeEntry.Source.IMAGINED,
]
## The narrator is not attributed: "you saw" is what OBSERVED already says.
const UNATTRIBUTED_SPEAKERS: Array[StringName] = [&"protagonist", &""]


static func compose(
	entries: Array[NarrativeEntry],
	catalog: JournalCatalog,
	locale: String,
	filter: int = ALL,
	read_ids: Dictionary = {},
	characters: CharacterDirectory = null
) -> Dictionary:
	var counts := empty_counts()
	var unread := 0
	var sections: Array[Dictionary] = []
	var section_at: Dictionary = {}
	var place_counts: Dictionary = {}
	var shown := 0
	for index in entries.size():
		var entry := entries[index]
		if entry == null:
			continue
		counts[ALL] = int(counts[ALL]) + 1
		if counts.has(entry.source):
			counts[entry.source] = int(counts[entry.source]) + 1
		var is_new := not read_ids.has(entry.entry_id)
		if is_new:
			unread += 1
		var place_key := (
			catalog.place_key_for(entry.entry_id) if catalog != null
			else JournalCatalog.ELSEWHERE_KEY
		)
		place_counts[place_key] = int(place_counts.get(place_key, 0)) + 1
		if filter != ALL and entry.source != filter:
			continue
		if not section_at.has(place_key):
			section_at[place_key] = sections.size()
			sections.append({"place_key": place_key, "rows": []})
		var row := {
			"entry_id": entry.entry_id,
			"source": entry.source,
			"badge_key": NarrativeEntry.badge_key_for(entry.source),
			"speaker_id": entry.speaker_id,
			"attribution": attribution(entry, characters),
			"text": catalog.text_for(entry, locale) if catalog != null else entry.text,
			"place_key": place_key,
			"is_new": is_new,
			"index": index,
		}
		(sections[int(section_at[place_key])]["rows"] as Array).append(row)
		shown += 1
	return {
		"filter": filter,
		"total": int(counts[ALL]),
		"shown": shown,
		"unread": unread,
		"counts": counts,
		"place_counts": place_counts,
		"sections": sections,
	}


static func empty_counts() -> Dictionary:
	var counts := {ALL: 0}
	for source: int in SOURCES:
		counts[source] = 0
	return counts


## "Q said so", in the language on screen, for an entry someone else is the source of.
## Empty for the protagonist's own observations, recollections and imaginings.
static func attribution(entry: NarrativeEntry, characters: CharacterDirectory) -> String:
	if entry == null or UNATTRIBUTED_SPEAKERS.has(entry.speaker_id):
		return ""
	var who := String(entry.speaker_id)
	if characters != null:
		who = characters.get_localized_name(entry.speaker_id)
	elif L10n.has_key("name.%s" % entry.speaker_id):
		who = L10n.t("name.%s" % entry.speaker_id)
	return L10n.t("journal.said_by", {"name": who})


## The filter after `filter`, stepping by `step` through ALL and the four sources and
## wrapping at either end.
static func step_filter(filter: int, step: int) -> int:
	var order: Array[int] = [ALL]
	order.append_array(SOURCES)
	var at := order.find(filter)
	if at < 0:
		at = 0
	return order[posmod(at + step, order.size())]


## The ids of every row on a page, in drawing order.
static func row_ids(page: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for section: Variant in page.get("sections", []):
		for row: Variant in (section as Dictionary).get("rows", []):
			ids.append(StringName((row as Dictionary).get("entry_id", &"")))
	return ids


## The text of every row on a page, in drawing order.
static func row_texts(page: Dictionary) -> PackedStringArray:
	var texts := PackedStringArray()
	for section: Variant in page.get("sections", []):
		for row: Variant in (section as Dictionary).get("rows", []):
			texts.append(String((row as Dictionary).get("text", "")))
	return texts


## Locale key of the label for a filter: `journal.filter.all` or the source's badge.
static func filter_label_key(filter: int) -> String:
	if filter == ALL:
		return "journal.filter.all"
	return NarrativeEntry.badge_key_for(filter)


## Locale key of the one-line caveat shown under a filter: what this kind of knowledge
## can and cannot be trusted for.
static func caveat_key(filter: int) -> String:
	if filter == ALL:
		return "journal.caveat.all"
	return "journal.caveat.%s" % NarrativeEntry.source_to_id(filter)
