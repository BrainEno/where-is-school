class_name JournalCatalog
extends RefCounted
## Where every knowledge entry the content can record comes from, in every language.
##
## `NarrativeState` keeps an entry's text as it was worded when it was recorded, in the
## language that was on screen at that moment. That is the right thing for a save (the
## entry is a fact about the run), but a notebook that showed it as stored would stay in
## the old language after a switch and mix two languages on one page. The catalog is the
## other half: it reads the dialogue and inspection content once and indexes, per
## language, every `record` (and every inspection `recall`) by its `entry_id`:
##
##     {"entry_id": StringName, "source": int, "speaker_id": StringName, "text": String,
##      "chapter": String, "origin": "dialogue" | "inspection",
##      "origin_id": StringName, "order": int}
##
## so the notebook can word an entry in whatever language is on screen, by identity,
## exactly like the backlog re-renders its rows (issue #18). It never writes state.
##
## `order` is the place in the authored content (chapter order, then file order). The
## notebook does not sort by it - the player's own reading order is the order of the
## log - but it is what places an entry in a chapter when two chapters could claim it.
##
## The content contract the catalog can check, and `problems()` reports:
## - an `entry_id` means one thing: every place that records it gives the same source;
## - every language records the same ids with the same sources (the dialogue and
##   inspection parity checks compare structure, not record ids across both kinds);
## - every entry has a non-empty text in every language.

const ORIGIN_DIALOGUE := "dialogue"
const ORIGIN_INSPECTION := "inspection"

## Chapter files that are not the name of a place. The prologue is the classroom scene;
## inner-voice reactions happen in the protagonist's head, wherever he stands.
const CHAPTER_PLACES: Dictionary = {
	"prologue": "classroom",
	"inner_voice": "",
}
## The section an entry from no particular place is filed under.
const ELSEWHERE_KEY := "journal.place.elsewhere"

## locale -> {entry_id -> descriptor}
var _index: Dictionary = {}
## entry_id -> the first locale's descriptor order, for stable sorting.
var _order: Dictionary = {}
var _problems: Array[String] = []


## Builds the catalog from libraries that are already loaded (the dialogue controller's),
## so nothing is parsed twice. Either library may be null; the catalog then covers what
## the other one has.
static func build(dialogue: DialogueLibrary, inspections: InspectionLibrary) -> JournalCatalog:
	var catalog := JournalCatalog.new()
	for locale: String in L10n.LOCALES:
		catalog._index[locale] = {}
		var counter := 0
		if dialogue != null:
			counter = catalog._index_dialogue(dialogue, locale, counter)
		if inspections != null:
			counter = catalog._index_inspections(inspections, locale, counter)
	catalog._check_parity()
	return catalog


## True when the content knows an entry with this id in at least one language.
func has_entry(entry_id: StringName) -> bool:
	for locale: String in _index.keys():
		if (_index[locale] as Dictionary).has(entry_id):
			return true
	return false


## The descriptor of an entry in a language, or an empty dictionary.
func lookup(entry_id: StringName, locale: String) -> Dictionary:
	var table: Dictionary = _index.get(L10n.normalize(locale), {})
	var found: Variant = table.get(entry_id, null)
	if found is Dictionary:
		return (found as Dictionary).duplicate()
	return {}


## The words for an entry in a language. Falls back to the text the log stored when the
## content no longer has the entry (an old save, a removed line): a notebook row is never
## blank, and never silently dropped.
func text_for(entry: NarrativeEntry, locale: String) -> String:
	if entry == null:
		return ""
	var found := lookup(entry.entry_id, locale)
	var text := String(found.get("text", "")).strip_edges()
	return text if not text.is_empty() else entry.text


## The chapter an entry was authored in, or "" when the content does not know it.
func chapter_for(entry_id: StringName) -> String:
	for locale: String in L10n.LOCALES:
		var found := lookup(entry_id, locale)
		if not found.is_empty():
			return String(found.get("chapter", ""))
	return ""


## The locale key of the place an entry belongs to: `place.classroom`, ... or
## `journal.place.elsewhere` when it was recorded nowhere in particular.
func place_key_for(entry_id: StringName) -> String:
	return place_key_for_chapter(chapter_for(entry_id))


static func place_key_for_chapter(chapter: String) -> String:
	var place := chapter
	if CHAPTER_PLACES.has(chapter):
		place = String(CHAPTER_PLACES[chapter])
	if place.is_empty():
		return ELSEWHERE_KEY
	var key := "place.%s" % place
	return key if L10n.has_key(key) else ELSEWHERE_KEY


## Position in the authored content; entries the content does not know sort last.
func order_of(entry_id: StringName) -> int:
	return int(_order.get(entry_id, 1 << 30))


func get_entry_ids(locale: String = "") -> Array[StringName]:
	var code := L10n.normalize(locale) if not locale.is_empty() else L10n.LOCALES[0]
	var ids: Array[StringName] = []
	for key: Variant in (_index.get(code, {}) as Dictionary).keys():
		ids.append(StringName(key))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return order_of(a) < order_of(b))
	return ids


func size(locale: String = "") -> int:
	var code := L10n.normalize(locale) if not locale.is_empty() else L10n.LOCALES[0]
	return (_index.get(code, {}) as Dictionary).size()


## Every way the content breaks the contract above. Empty is good.
func problems() -> Array[String]:
	return _problems.duplicate()


# --- Indexing ----------------------------------------------------------------------


func _index_dialogue(library: DialogueLibrary, locale: String, counter: int) -> int:
	for graph: DialogueGraph in library.get_graphs_for(locale):
		var ids := graph.get_conversation_ids()
		for conversation_id: StringName in ids:
			var conversation := graph.get_conversation(conversation_id)
			if conversation == null:
				continue
			for node_id: StringName in conversation.order:
				var node: DialogueGraph.DialogueNode = conversation.nodes.get(node_id, null)
				if node == null:
					continue
				counter = _index_effects(node.effects, graph.chapter, conversation_id, locale, counter)
				for choice: Variant in node.choices:
					var typed := choice as DialogueGraph.DialogueChoice
					if typed != null:
						counter = _index_effects(
							typed.effects, graph.chapter, conversation_id, locale, counter
						)
	return counter


func _index_effects(
	effects: Array, chapter: String, conversation_id: StringName, locale: String, counter: int
) -> int:
	for effect: Variant in effects:
		if not (effect is Dictionary):
			continue
		var data: Dictionary = effect
		if String(data.get("type", "")) != "record":
			continue
		var source := NarrativeEntry.source_from_id(String(data.get("source", "")))
		_add(locale, {
			"entry_id": StringName(String(data.get("entry_id", ""))),
			"source": source,
			"speaker_id": StringName(String(data.get("speaker", "protagonist"))),
			"text": String(data.get("text", "")).strip_edges(),
			"chapter": chapter,
			"origin": ORIGIN_DIALOGUE,
			"origin_id": conversation_id,
			"order": counter,
		})
		counter += 1
	return counter


func _index_inspections(library: InspectionLibrary, locale: String, counter: int) -> int:
	# Chapter order first, so the classroom's things come before the street's.
	var ids := library.get_ids_for(locale)
	var by_chapter: Dictionary = {}
	for inspection_id: StringName in ids:
		var inspection := library.get_inspection_in(locale, inspection_id)
		if inspection == null:
			continue
		if not by_chapter.has(inspection.chapter):
			by_chapter[inspection.chapter] = []
		(by_chapter[inspection.chapter] as Array).append(inspection)
	for chapter: String in InspectionLibrary.CHAPTERS:
		for item: Variant in by_chapter.get(chapter, []):
			var inspection := item as InspectionLibrary.InspectionData
			if not String(inspection.record_entry_id).is_empty():
				_add(locale, {
					"entry_id": inspection.record_entry_id,
					"source": inspection.record_source,
					"speaker_id": inspection.speaker_id,
					"text": inspection.record_text,
					"chapter": inspection.chapter,
					"origin": ORIGIN_INSPECTION,
					"origin_id": inspection.inspection_id,
					"order": counter,
				})
				counter += 1
			if not String(inspection.recall_entry_id).is_empty():
				# What the controller records for a recall: always RECALLED, the
				# inspection's speaker, the recall line itself.
				_add(locale, {
					"entry_id": inspection.recall_entry_id,
					"source": int(NarrativeEntry.Source.RECALLED),
					"speaker_id": inspection.speaker_id,
					"text": inspection.recall_text,
					"chapter": inspection.chapter,
					"origin": ORIGIN_INSPECTION,
					"origin_id": inspection.inspection_id,
					"order": counter,
				})
				counter += 1
	return counter


func _add(locale: String, descriptor: Dictionary) -> void:
	var entry_id: StringName = descriptor["entry_id"]
	if String(entry_id).is_empty():
		return
	var table: Dictionary = _index[locale]
	if table.has(entry_id):
		# Recorded from more than one place (two branches that reach the same fact). The
		# first stays; a second that disagrees on the kind of knowledge is a content bug.
		var first: Dictionary = table[entry_id]
		if int(first["source"]) != int(descriptor["source"]):
			_problems.append(
				"%s: entry '%s' is recorded as %s in %s '%s' but as %s in %s '%s'." % [
					locale, entry_id,
					NarrativeEntry.source_to_id(int(first["source"])), first["origin"],
					first["origin_id"],
					NarrativeEntry.source_to_id(int(descriptor["source"])), descriptor["origin"],
					descriptor["origin_id"],
				]
			)
		return
	if int(descriptor["source"]) < 0:
		_problems.append(
			"%s: entry '%s' in %s '%s' has no valid source."
			% [locale, entry_id, descriptor["origin"], descriptor["origin_id"]]
		)
	if String(descriptor["text"]).is_empty():
		_problems.append(
			"%s: entry '%s' in %s '%s' has no text."
			% [locale, entry_id, descriptor["origin"], descriptor["origin_id"]]
		)
	table[entry_id] = descriptor
	if not _order.has(entry_id):
		_order[entry_id] = int(descriptor["order"])


func _check_parity() -> void:
	var reference: String = L10n.LOCALES[0]
	var reference_table: Dictionary = _index.get(reference, {})
	for locale: String in L10n.LOCALES:
		if locale == reference:
			continue
		var table: Dictionary = _index.get(locale, {})
		for entry_id: Variant in reference_table.keys():
			if not table.has(entry_id):
				_problems.append(
					"%s records '%s' but %s never does." % [reference, entry_id, locale]
				)
				continue
			var a := int((reference_table[entry_id] as Dictionary)["source"])
			var b := int((table[entry_id] as Dictionary)["source"])
			if a != b:
				_problems.append(
					"'%s' is %s in %s but %s in %s." % [
						entry_id, NarrativeEntry.source_to_id(a), reference,
						NarrativeEntry.source_to_id(b), locale,
					]
				)
		for entry_id: Variant in table.keys():
			if not reference_table.has(entry_id):
				_problems.append(
					"%s records '%s' but %s never does." % [locale, entry_id, reference]
				)
