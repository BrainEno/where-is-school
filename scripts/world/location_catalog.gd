class_name LocationCatalog
extends RefCounted
## What a location declares about itself, read from `data/story/locations.json`.
##
## Before this existed, everything a room knows about itself lived in the middle of
## `opening_sequence.gd`: a `match` on the destination id chose the objective line,
## a second `match` chose the arrival conversation and its flag, and the room the
## game starts in was a `const`. Adding a location therefore meant editing a script
## called "opening", which is the reason this class exists.
##
## An entry answers three questions and nothing else:
##
## - which scene is it (and, for the start location, which spawn marker);
## - what the objective line says when the player arrives (`objective.<key>`);
## - which line plays the first time the player arrives, and the flag that proves it
##   has played.
##
## Exits are not listed here. An exit already names its destination scene, spawn and
## id, so a room's connections live in the room, next to the door they belong to.
##
## Validation at load is deliberately strict: a typo in a flag name or a scene path
## should fail here, once, instead of producing a location that silently never
## announces itself.

const PATH := "res://data/story/locations.json"
const FLAGS_SCRIPT := "res://scripts/narrative/story_flags.gd"
const FORMAT_VERSION := 1


## One location. Plain data: no methods that reach into the game.
class Entry extends RefCounted:
	var location_id: StringName = &""
	## `res://` path of the location scene.
	var scene: String = ""
	## Spawn marker used when this is the location the game starts in.
	var spawn: StringName = &"default"
	## Locale key of the objective line shown on arrival; empty means "the story
	## decides", which is what the classroom does for its whole first act.
	var objective: String = ""
	## Conversation played once, the first time the player arrives.
	var arrival_conversation: StringName = &""
	## Flag set when that conversation has played, so it never plays twice.
	var arrival_flag: StringName = &""
	## Flags set on every arrival, not just the first one.
	var arrival_flags: Array[StringName] = []
	## True for the location the game opens in. Exactly one entry may be.
	var is_start: bool = false


var errors: Array[String] = []
var _entries: Dictionary = {}


static func load_all(path: String = PATH) -> LocationCatalog:
	var catalog := LocationCatalog.new()
	var text := _file_text(path)
	if text.is_empty():
		catalog.errors.append("%s: could not be read." % path)
		return catalog

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		catalog.errors.append("%s: not a JSON object." % path)
		return catalog
	var data: Dictionary = parsed

	var version := int(data.get("format_version", 0))
	if version != FORMAT_VERSION:
		catalog.errors.append(
			"%s: format_version %d, expected %d." % [path, version, FORMAT_VERSION]
		)

	var raw: Variant = data.get("locations", null)
	if not (raw is Dictionary):
		catalog.errors.append("%s: 'locations' must be an object." % path)
		return catalog

	var known_flags := _known_flags()
	for key: Variant in (raw as Dictionary).keys():
		var location_id := StringName(String(key))
		var body: Variant = (raw as Dictionary)[key]
		if not (body is Dictionary):
			catalog.errors.append("%s/%s: entry must be an object." % [path, location_id])
			continue
		catalog._add_entry(location_id, body as Dictionary, path, known_flags)

	if catalog.get_start() == null:
		catalog.errors.append("%s: no location is marked \"start\": true." % path)
	return catalog


func _add_entry(
	location_id: StringName, body: Dictionary, path: String, known_flags: Dictionary
) -> void:
	var entry := Entry.new()
	entry.location_id = location_id
	entry.scene = String(body.get("scene", ""))
	entry.spawn = StringName(String(body.get("spawn", "default")))
	entry.objective = String(body.get("objective", ""))
	entry.arrival_conversation = StringName(String(body.get("arrival_conversation", "")))
	entry.arrival_flag = StringName(String(body.get("arrival_flag", "")))
	entry.is_start = bool(body.get("start", false))
	for flag: Variant in body.get("arrival_flags", []):
		entry.arrival_flags.append(StringName(String(flag)))

	var label := "%s/%s" % [path, location_id]
	if entry.scene.is_empty():
		errors.append("%s: 'scene' is required." % label)
	elif not ResourceLoader.exists(entry.scene):
		errors.append("%s: scene '%s' does not exist." % [label, entry.scene])
	if String(entry.arrival_conversation).is_empty() != String(entry.arrival_flag).is_empty():
		# A line with no flag plays every time the player walks through the door; a
		# flag with no line can never be set. Both are authoring mistakes.
		errors.append(
			"%s: 'arrival_conversation' and 'arrival_flag' are set together or not at all."
			% label
		)
	for flag: StringName in entry.arrival_flags:
		if not known_flags.has(flag):
			errors.append("%s: 'arrival_flags' names unknown flag '%s'." % [label, flag])
	if not String(entry.arrival_flag).is_empty() and not known_flags.has(entry.arrival_flag):
		errors.append("%s: 'arrival_flag' names unknown flag '%s'." % [label, entry.arrival_flag])
	if entry.is_start and String(entry.spawn).is_empty():
		errors.append("%s: the start location needs a 'spawn' marker." % label)

	_entries[location_id] = entry


func is_valid() -> bool:
	return errors.is_empty()


func has(location_id: StringName) -> bool:
	return _entries.has(location_id)


## The entry for a location, or null. Callers that are happy with "a room the
## catalog has never heard of" are allowed to keep going: the catalog is what a room
## *declares*, and a room that declares nothing still works, it just announces
## nothing.
func get_entry(location_id: StringName) -> Entry:
	return _entries.get(location_id, null)


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _entries.keys():
		ids.append(key)
	ids.sort()
	return ids


func get_start() -> Entry:
	for key: Variant in _entries.keys():
		var entry: Entry = _entries[key]
		if entry.is_start:
			return entry
	return null


func describe_errors() -> String:
	if errors.is_empty():
		return ""
	return "locations: %s" % " | ".join(errors)


## Every flag name `StoryFlags` declares. Read from the script's constants rather
## than restated here, so adding a flag does not mean editing two lists.
static func _known_flags() -> Dictionary:
	var known := {}
	var script: Script = load(FLAGS_SCRIPT)
	if script == null:
		return known
	for key: Variant in script.get_script_constant_map().keys():
		var value: Variant = script.get_script_constant_map()[key]
		if value is StringName:
			known[value] = true
	return known


static func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
