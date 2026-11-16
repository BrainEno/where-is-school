class_name ReadingProgress
extends RefCounted
## How much of the game's text the player has read, across runs: "Text read: 37% (120 / 324)".
##
## The notebook shows it; it is worked out here, from the loaded content and the read log,
## so the notebook never opens a story file and the number means the same thing everywhere.
##
## **What is counted.** Every line the game can put in the dialogue panel, once:
##
## - each conversation node with text (`conv:<conversation>/<node>`), whether or not its
##   conditions let this run reach it;
## - each inspection's first reading (`inspection:<id>/first`) and, where it has one, the
##   recollection that follows it (`inspection:<id>/recall`).
##
## A repeat look (`inspection:<id>/repeat`) is not counted: it is a second look at
## something already read, so looking at a desk ten times cannot raise the number. The
## identities are the backlog's (`DialogueHistory.identify`), which are the read log's.
##
## **What is read.** What `ReadLog.is_read()` says for the text in the language on screen.
## That is the same answer skip goes by, so an edited line counts as unread again until it
## has been read as it is now, and a line read in Chinese counts in English too.
##
## **Languages.** The set of lines is the union over every language the game ships, so the
## total cannot change with the language; each line is counted once however many languages
## it was read in.
##
## **Areas.** A line belongs to the place its chapter is filed under in the notebook
## (`JournalCatalog.place_key_for_chapter`): the prologue is the classroom; the inner voices,
## and rooms without a name yet, are "Elsewhere". Only areas with something read and something
## left are named, so a place the player has never read a line in is never mentioned.
##
## Built once from the content (`build`), measured whenever it is asked (`measure`): the
## numbers are always the read log's current ones.

## How many unfinished areas are named before the rest are summed up as "and N more".
const AREAS_LISTED := 3

## {identity: String, area: String (a locale key), texts: {locale: text}}, in content order.
var _lines: Array[Dictionary] = []
## identity -> index into `_lines`.
var _index: Dictionary = {}
## Area keys in content order, "Elsewhere" last.
var _areas: Array[String] = []


## Every countable line in `dialogue` and `inspections`, in every language they hold. Either
## may be null (nothing to count from it).
static func build(dialogue: DialogueLibrary, inspections: InspectionLibrary) -> ReadingProgress:
	var progress := ReadingProgress.new()
	for locale: String in L10n.LOCALES:
		if dialogue != null:
			progress._add_dialogue(dialogue, locale)
		if inspections != null:
			progress._add_inspections(inspections, locale)
	# Places in the order the content walks them; what is filed nowhere in particular last.
	if progress._areas.has(JournalCatalog.ELSEWHERE_KEY):
		progress._areas.erase(JournalCatalog.ELSEWHERE_KEY)
		progress._areas.append(JournalCatalog.ELSEWHERE_KEY)
	return progress


## How many lines are counted. The same in every language.
func total() -> int:
	return _lines.size()


## Every counted identity, in content order.
func get_identities() -> PackedStringArray:
	var ids := PackedStringArray()
	for line: Dictionary in _lines:
		ids.append(String(line["identity"]))
	return ids


## The area key (`place.classroom`, `journal.place.elsewhere`, ...) of a counted line, or ""
## when `identity` is not counted.
func area_of(identity: String) -> String:
	if not _index.has(identity):
		return ""
	return String(_lines[int(_index[identity])]["area"])


## The text `identity` has in `locale`, or "" when it has none there.
func text_of(identity: String, locale: String) -> String:
	if not _index.has(identity):
		return ""
	return String((_lines[int(_index[identity])]["texts"] as Dictionary).get(locale, ""))


## The progress now, against `read_log`, for the language `locale`:
##
##     {"read": int, "total": int, "percent": int (rounded down, so 100 means all of it),
##      "areas": [{"place_key": String, "read": int, "total": int, "left": int}, ...]}
##
## `areas` holds only the areas started and not finished, in content order. A null log
## has read nothing.
func measure(read_log: ReadLog, locale: String) -> Dictionary:
	var read := 0
	var by_area: Dictionary = {}
	for line: Dictionary in _lines:
		var area := String(line["area"])
		if not by_area.has(area):
			by_area[area] = {"read": 0, "total": 0}
		var counts: Dictionary = by_area[area]
		counts["total"] = int(counts["total"]) + 1
		if read_log != null and _is_line_read(read_log, line, locale):
			read += 1
			counts["read"] = int(counts["read"]) + 1
	var areas: Array[Dictionary] = []
	for area: String in _areas:
		var counts: Dictionary = by_area.get(area, {"read": 0, "total": 0})
		var area_read := int(counts["read"])
		var area_total := int(counts["total"])
		if area_read > 0 and area_read < area_total:
			areas.append({
				"place_key": area, "read": area_read, "total": area_total,
				"left": area_total - area_read,
			})
	var count := _lines.size()
	return {
		"read": read,
		"total": count,
		"percent": int(floor(read * 100.0 / count)) if count > 0 else 0,
		"areas": areas,
	}


## The progress as the notebook says it, in the language on screen: one line for the share
## read, and one naming what is left where, when something is. "" when there is nothing to
## count.
static func describe(progress: Dictionary) -> String:
	var total_lines := int(progress.get("total", 0))
	if total_lines <= 0:
		return ""
	var text := L10n.t("journal.read_progress", {
		"percent": int(progress.get("percent", 0)),
		"read": int(progress.get("read", 0)),
		"total": total_lines,
	})
	var areas: Array = progress.get("areas", [])
	if areas.is_empty():
		return text
	var parts := PackedStringArray()
	for index in mini(areas.size(), AREAS_LISTED):
		var area: Dictionary = areas[index]
		parts.append(L10n.t("journal.read_area_left", {
			"place": L10n.t(String(area.get("place_key", JournalCatalog.ELSEWHERE_KEY))),
			"count": int(area.get("left", 0)),
		}))
	if areas.size() > AREAS_LISTED:
		parts.append(L10n.t("journal.read_areas_more", {"count": areas.size() - AREAS_LISTED}))
	return "%s\n%s" % [
		text, L10n.t("journal.read_areas", {"areas": L10n.t("journal.route_separator").join(parts)})
	]


# --- Building ------------------------------------------------------------------------------


func _add_dialogue(dialogue: DialogueLibrary, locale: String) -> void:
	for graph: DialogueGraph in dialogue.get_graphs_for(locale):
		var area := JournalCatalog.place_key_for_chapter(graph.chapter)
		for conversation_id: StringName in graph.get_conversation_ids():
			var conversation := graph.get_conversation(conversation_id)
			if conversation == null:
				continue
			for node_id: StringName in conversation.order:
				var node: DialogueGraph.DialogueNode = conversation.nodes.get(node_id, null)
				# The runtime shows a node only when it has text (`DialogueRuntime._enter_node`).
				if node == null or node.text.is_empty():
					continue
				_add(DialogueHistory.identify({
					"conversation_id": conversation_id, "node_id": node_id,
				}), area, locale, node.text)


func _add_inspections(inspections: InspectionLibrary, locale: String) -> void:
	for inspection_id: StringName in inspections.get_ids(locale):
		var inspection := inspections.get_inspection_in(locale, inspection_id)
		if inspection == null:
			continue
		var area := JournalCatalog.place_key_for_chapter(inspection.chapter)
		if not inspection.text.is_empty():
			_add(DialogueHistory.identify({
				"inspection_id": inspection_id, "variant": "first",
			}), area, locale, inspection.text)
		# Queued after the first reading only, and only when there is one to tell
		# (`DialogueController.present_inspection`).
		if not inspection.recall_text.is_empty():
			_add(DialogueHistory.identify({
				"inspection_id": inspection_id, "variant": "recall",
			}), area, locale, inspection.recall_text)


func _add(identity: String, area: String, locale: String, text: String) -> void:
	if not ReadLog.is_identifiable(identity):
		return
	if not _index.has(identity):
		_index[identity] = _lines.size()
		_lines.append({"identity": identity, "area": area, "texts": {}})
		if not _areas.has(area):
			_areas.append(area)
	(_lines[int(_index[identity])]["texts"] as Dictionary)[locale] = text


# --- Measuring -----------------------------------------------------------------------------


## The line in `locale` when it exists there. A line missing from that language (content
## parity forbids it, but a broken file should not change the total) is judged by the first
## language that has it.
static func _is_line_read(read_log: ReadLog, line: Dictionary, locale: String) -> bool:
	var identity := String(line["identity"])
	var texts: Dictionary = line["texts"]
	if texts.has(locale):
		return read_log.is_read(identity, locale, String(texts[locale]))
	for other: String in L10n.LOCALES:
		if texts.has(other):
			return read_log.is_read(identity, other, String(texts[other]))
	return false
