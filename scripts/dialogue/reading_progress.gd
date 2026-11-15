class_name ReadingProgress
extends RefCounted
## How much of the game's text the player has read, across every run.
##
## The total is counted from the content itself, with the identities the dialogue
## controller gives a line when it shows it, so the two can never disagree about what
## a "line" is:
##
## - every conversation node with text (`conv:<conversation>/<node>`) - a node without
##   text is a branch or a check and is never shown;
## - every inspection's first read (`inspection:<id>/first`) and, where it has one, its
##   recollection (`inspection:<id>/recall`).
##
## Repeat reads (`inspection:<id>/repeat`) are left out of the total: they are the same
## object looked at again, and counting them would reward walking back and forth. They
## are still remembered by `ReadLog`, so skipping works on them.
##
## Identities are the same in every language (the parity checker refuses a translation
## that changes a conversation's shape), so the total is counted in one language.

const VARIANTS_COUNTED: Array[String] = ["first", "recall"]
## Where a line is said, for "unread text left in ...", in story order. A dialogue
## chapter is named after its place; the inner voices are their own area. A chapter that
## maps to none of these (content the route does not name yet) still counts in the total
## and is never named.
const AREAS: Array[String] = [
	"classroom", "corridor", "street", "residential", "alley", "playground", "inner_voice",
]
const CHAPTER_AREAS: Dictionary = {"prologue": "classroom"}
## How many areas the notebook names before it says "and N more".
const AREAS_LISTED := 4


## Every identity the content can show, in a stable order.
static func identities(dialogue: DialogueLibrary, inspections: InspectionLibrary,
		locale: String = L10n.DEFAULT_LOCALE) -> Array[String]:
	var out: Array[String] = []
	var by_area := identities_by_area(dialogue, inspections, locale)
	for area: String in by_area.keys():
		out.append_array(by_area[area] as Array[String])
	return out


## The same identities, filed by area (`AREAS`, or "" for content no area names).
static func identities_by_area(dialogue: DialogueLibrary, inspections: InspectionLibrary,
		locale: String = L10n.DEFAULT_LOCALE) -> Dictionary:
	var out: Dictionary = {}
	if dialogue != null:
		for graph: DialogueGraph in dialogue.get_graphs_for(locale):
			var ids := graph.get_conversation_ids()
			ids.sort()
			for conversation_id: StringName in ids:
				var conversation := graph.get_conversation(conversation_id)
				if conversation == null:
					continue
				for node_id: StringName in conversation.order:
					var node: DialogueGraph.DialogueNode = conversation.nodes.get(node_id, null)
					if node != null and not node.text.strip_edges().is_empty():
						_file(out, area_of_chapter(graph.chapter), "conv:%s/%s" % [
							conversation_id, node_id
						])
	if inspections != null:
		for inspection_id: StringName in inspections.get_ids(locale):
			var inspection := inspections.get_inspection_in(locale, inspection_id)
			if inspection == null:
				continue
			var area := area_of_chapter(inspection.chapter)
			if not inspection.text.strip_edges().is_empty():
				_file(out, area, "inspection:%s/first" % inspection_id)
			if not inspection.recall_text.strip_edges().is_empty():
				_file(out, area, "inspection:%s/recall" % inspection_id)
	return out


static func area_of_chapter(chapter: String) -> String:
	var area := String(CHAPTER_AREAS.get(chapter, chapter))
	return area if AREAS.has(area) else ""


static func _file(by_area: Dictionary, area: String, identity: String) -> void:
	if not by_area.has(area):
		var fresh: Array[String] = []
		by_area[area] = fresh
	(by_area[area] as Array[String]).append(identity)


## The areas the player has started and not finished, in story order:
## [{"area": String, "read": int, "total": int}]. An area with nothing read yet is left
## out on purpose - naming it would tell the player about a place before they get there.
static func unfinished_areas(read_log: ReadLog, by_area: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if read_log == null:
		return rows
	for area: String in AREAS:
		var identities_here: Array = by_area.get(area, [])
		var read := read_log.count_read(identities_here)
		if read > 0 and read < identities_here.size():
			rows.append({"area": area, "read": read, "total": identities_here.size()})
	return rows


## {"read": int, "total": int, "percent": int}. Percent rounds down, so 100 means all of
## it and never "nearly all of it". With `by_area`, "areas" lists `unfinished_areas`.
static func measure(
	read_log: ReadLog, all_identities: Array[String], by_area: Dictionary = {}
) -> Dictionary:
	var total := all_identities.size()
	var read := read_log.count_read(all_identities) if read_log != null else 0
	var percent := 0
	if total > 0:
		percent = int(floor(100.0 * float(read) / float(total)))
	var result := {"read": read, "total": total, "percent": percent}
	if not by_area.is_empty():
		result["areas"] = unfinished_areas(read_log, by_area)
	return result


## "Text read: 37% (120 of 324 lines)" in the language on screen; empty without content.
## With `progress["areas"]` (see `unfinished_areas`), a second line says where the unread
## text is: "Unread text left in: Classroom (3) · Corridor (12)".
static func describe(progress: Dictionary) -> String:
	if int(progress.get("total", 0)) <= 0:
		return ""
	var text := L10n.t("journal.read_progress", {
		"percent": int(progress.get("percent", 0)),
		"read": int(progress.get("read", 0)),
		"total": int(progress.get("total", 0)),
	})
	var areas := describe_areas(progress.get("areas", []) as Array)
	return text if areas.is_empty() else "%s\n%s" % [text, areas]


static func describe_areas(rows: Array) -> String:
	var parts := PackedStringArray()
	for item: Variant in rows:
		if not item is Dictionary:
			continue
		if parts.size() >= AREAS_LISTED:
			break
		var row: Dictionary = item
		var area := String(row.get("area", ""))
		var key := "journal.read_area.%s" % area if area == "inner_voice" else "place.%s" % area
		if not L10n.has_key(key):
			continue
		var left := int(row.get("total", 0)) - int(row.get("read", 0))
		parts.append(L10n.t("journal.route_count", {"place": L10n.t(key), "count": left}))
	if parts.is_empty():
		return ""
	var listed := L10n.t("journal.route_separator").join(parts)
	if rows.size() > parts.size():
		var more := rows.size() - parts.size()
		listed = L10n.t("journal.read_areas_more", {"areas": listed, "count": more})
	return L10n.t("journal.read_areas", {"areas": listed})
