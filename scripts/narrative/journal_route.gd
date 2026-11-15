class_name JournalRoute
extends RefCounted
## The places this run has reached, for the notebook's route line.
##
## Nothing new is stored to know it. A location already declares, in
## `data/story/locations.json`, the flags its arrival sets (`arrival_flags`, every time;
## `arrival_flag`, the first time its arrival line plays), and the story keeps those flags
## in `GameState` - and therefore in the save - anyway. A place counts as reached when:
##
## - it is where the game starts, or
## - one of its arrival flags is set, or
## - it is where the player stands now (`current_location`), or
## - something in the notebook was learned there.
##
## The last rule is what makes an old save or a skipped arrival line still show the place
## the player plainly was in. Places are listed in the catalog's file order, which is the
## order the story walks them in; a place not reached is not listed at all, so the line
## never tells the player where the story goes next.
##
## A row:
##
##     {"location_id": StringName, "place_key": String, "current": bool, "entries": int}
##
## Locations without a `place.<id>` name (a room no exit leads to yet) are left out: the
## route names places, it does not print identifiers.

const CURRENT_LOCATION_FLAG: StringName = &"current_location"
const OBJECTIVE_FLAG: StringName = &"objective_key"


## `flags` is anything with `get_flag(flag, default)` - the `GameState` node in the game,
## a stub in a test - or null for "nothing is known yet".
static func compose(
	locations: LocationCatalog, flags: Object, place_counts: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if locations == null:
		return rows
	var current := current_location(flags)
	for location_id: StringName in locations.get_ids_in_file_order():
		var entry := locations.get_entry(location_id)
		if entry == null:
			continue
		var place_key := "place.%s" % location_id
		if not L10n.has_key(place_key):
			continue
		var entries := int(place_counts.get(place_key, 0))
		var reached := entry.is_start or location_id == current or entries > 0
		if not reached and flags != null:
			reached = _flag_set(flags, entry.arrival_flag)
			for flag: StringName in entry.arrival_flags:
				reached = reached or _flag_set(flags, flag)
		if not reached:
			continue
		rows.append({
			"location_id": location_id,
			"place_key": place_key,
			"current": location_id == current,
			"entries": entries,
		})
	return rows


## Where the player stands, as the story records it; empty when nothing says.
static func current_location(flags: Object) -> StringName:
	if flags == null or not flags.has_method("get_flag"):
		return &""
	return StringName(String(flags.call("get_flag", CURRENT_LOCATION_FLAG, "")))


## The objective line on screen, or "" when there is none.
static func objective_text(flags: Object) -> String:
	if flags == null or not flags.has_method("get_flag"):
		return ""
	var key := String(flags.call("get_flag", OBJECTIVE_FLAG, "")).strip_edges()
	return L10n.objective_text(key) if not key.is_empty() else ""


## The route as one line in the language on screen: "Classroom (4) · Corridor (now)".
static func describe(rows: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for row: Dictionary in rows:
		var place := L10n.t(String(row["place_key"]))
		if bool(row["current"]):
			parts.append(L10n.t("journal.route_here", {"place": place}))
		elif int(row["entries"]) > 0:
			parts.append(L10n.t("journal.route_count", {"place": place, "count": int(row["entries"])}))
		else:
			parts.append(place)
	if parts.is_empty():
		return ""
	return L10n.t("journal.route", {"places": L10n.t("journal.route_separator").join(parts)})


static func _flag_set(flags: Object, flag: StringName) -> bool:
	if String(flag).is_empty():
		return false
	var value: Variant = flags.call("get_flag", flag, null)
	if value == null:
		return false
	if value is bool:
		return bool(value)
	return true
