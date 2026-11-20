class_name JournalPage
extends RefCounted
## What the notebook shows at one moment: the log's entries, worded in the language on
## screen, filed under the place each was learned in, optionally narrowed to one kind of
## knowledge or to pairs of records that this run can put beside each other.
##
## Pure: it reads the entries it is given and a `JournalCatalog`, and returns plain
## dictionaries. The panel draws them; the tests read them without building a single
## control. Nothing here touches `NarrativeState` or the story flags.
##
## Shape of `compose()`:
##
##     {"filter": int,                     # ALL, COMPARE or a NarrativeEntry.Source
##      "total": int,                      # entries in the log, whatever the filter
##      "shown": int,                      # rows on this page
##      "unread": int,                     # entries not yet seen in the notebook
##      "counts": {ALL: int, COMPARE: int, Source.OBSERVED: int, ...}, # COMPARE counts pairs
##      "place_counts": {place_key: int, ...},  # every entry, whatever the filter
##      "sections": [{"place_key": String, "rows": [row, ...]}, ...]}
##
## In COMPARE a section has `comparison_id`, `title_key`, and `question_key` instead of
## `place_key`, and two rows in authored order. A pair is present only if both ids are in
## the log. It does not change the saved entries or turn a question into knowledge.
##
## Shape of a row:
##
##     {"entry_id": StringName, "source": int, "badge_key": String,
##      "speaker_id": StringName, "attribution": String, "text": String,
##      "place_key": String, "is_new": bool, "index": int}
##
## Order is the player's: sections appear in the order their first entry was learned and
## rows keep the order of the log. The notebook is a record of this run, not an index of
## the content. Comparison sections keep their authored order, even if read backwards.

const ALL := -1
const COMPARE := -2
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
	# A record's position in the log, never a second store of what the player knows.
	var known: Dictionary[StringName, int] = {}
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
		known[entry.entry_id] = index
		if filter == COMPARE or (filter != ALL and entry.source != filter):
			continue
		if not section_at.has(place_key):
			section_at[place_key] = sections.size()
			sections.append({"place_key": place_key, "rows": []})
		(sections[int(section_at[place_key])]["rows"] as Array).append(
			_row(entry, place_key, index, is_new, catalog, locale, characters)
		)
		shown += 1
	if catalog != null:
		for pair: Dictionary in catalog.get_comparisons():
			var left: StringName = pair["left"]
			var right: StringName = pair["right"]
			if not known.has(left) or not known.has(right):
				continue
			counts[COMPARE] = int(counts[COMPARE]) + 1
			if filter != COMPARE:
				continue
			var rows: Array[Dictionary] = []
			for id: StringName in [left, right]:
				var index := known[id]
				rows.append(_row(
					entries[index], catalog.place_key_for(id), index, not read_ids.has(id),
					catalog, locale, characters
				))
			sections.append({
				"comparison_id": pair["id"],
				"title_key": pair["title_key"],
				"question_key": pair["question_key"],
				"rows": rows,
			})
			shown += rows.size()
	return {
		"filter": filter,
		"total": int(counts[ALL]),
		"shown": shown,
		"unread": unread,
		"counts": counts,
		"place_counts": place_counts,
		"sections": sections,
	}


static func _row(
	entry: NarrativeEntry,
	place_key: String,
	index: int,
	is_new: bool,
	catalog: JournalCatalog,
	locale: String,
	characters: CharacterDirectory
) -> Dictionary:
	return {
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


static func empty_counts() -> Dictionary:
	var counts := {ALL: 0, COMPARE: 0}
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


## The tabs in reading order, also the order followed by keyboard and gamepad focus.
static func filter_order() -> Array[int]:
	var order: Array[int] = [ALL]
	order.append_array(SOURCES)
	order.append(COMPARE)
	return order


## The tab after `filter`, stepping by `step` and wrapping at either end.
static func step_filter(filter: int, step: int) -> int:
	var order := filter_order()
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


## Locale key of a tab label, or the badge for a source tab.
static func filter_label_key(filter: int) -> String:
	if filter == ALL:
		return "journal.filter.all"
	if filter == COMPARE:
		return "journal.filter.compare"
	return NarrativeEntry.badge_key_for(filter)


## Locale key of the one-line caveat shown under a filter: what this kind of knowledge
## can and cannot be trusted for.
static func caveat_key(filter: int) -> String:
	if filter == ALL:
		return "journal.caveat.all"
	if filter == COMPARE:
		return "journal.caveat.compare"
	return "journal.caveat.%s" % NarrativeEntry.source_to_id(filter)
