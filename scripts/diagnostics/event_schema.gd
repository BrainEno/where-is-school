extends RefCounted
## The privacy boundary for both newly recorded and previously persisted events.
## There is deliberately no API for a free-text message, a path or a payload.

enum Level { DEBUG, INFO, WARNING, ERROR }

const VERSION := 1
const LEVEL_NAMES := ["DEBUG", "INFO", "WARNING", "ERROR"]
const SCENE_IDS := ["title", "world", "other", "none"]
const MAX_REPEAT := 9999
const MAX_UNIX := 253402300799 # 9999-12-31 UTC; also exactly representable in JSON.

# Each row fixes the level, category, message and (optionally) the context fields.
# Field rules are an enum of literal strings, a published location ID, or a small integer.
const EVENTS := {
	"session.started": [Level.INFO, "session", "Game process started."],
	"session.ended": [Level.INFO, "session", "Game process closed normally."],
	"session.scene_changed": [Level.INFO, "session", "Game scene changed.", {"scene": SCENE_IDS}],
	"session.scene_refused": [Level.ERROR, "session", "Could not change game scene.", {
		"scene": SCENE_IDS, "error_code": "integer",
	}],
	"session.new_game_refused": [Level.ERROR, "session", "Could not start a new game.", {
		"reason": ["save_stage_failed", "state_left", "scene_change_failed", "staged_discard_failed"],
	}],
	"world.entered": [Level.INFO, "world", "Location transition committed.", {
		"from_location": "location", "to_location": "location",
	}],
	"world.transition_refused": [Level.ERROR, "world", "Location transition refused; old world kept.", {
		"from_location": "location", "to_location": "location",
		"reason": ["no_scene", "scene_missing", "not_packed_scene", "instantiation_failed",
			"invalid_root", "no_location_id", "mismatched_location", "no_player",
			"no_teleport", "no_spawn", "placement_failed"],
	}],
	"world.navigation_failed": [Level.ERROR, "world", "Navigation region could not be registered."],
	"world.navigation_unsynchronized": [Level.WARNING, "world", "Navigation did not synchronize."],
	"world.recovery_timeout": [Level.ERROR, "world", "Transition recovery exceeded its time limit."],
	"save.written": [Level.INFO, "save", "Checkpoint written.", {"version": "integer"}],
	"save.loaded": [Level.INFO, "save", "Checkpoint loaded.", {"version": "integer"}],
	"save.recovered": [Level.WARNING, "save", "Recovered a checkpoint from an interrupted write."],
	"save.cleanup_incomplete": [Level.WARNING, "save", "Some temporary save files could not be removed.", {
		"count": "integer",
	}],
	"save.read_refused": [Level.ERROR, "save", "Checkpoint rejected.", {
		"reason": ["unreadable", "not_json", "format", "version", "payload", "no_state", "seed"],
	}],
	"save.operation_failed": [Level.ERROR, "save", "Save operation failed.", {
		"reason": ["empty", "suspended", "write", "verify", "delete"],
	}],
	"save.quarantine_failed": [Level.ERROR, "save", "Could not preserve a copy of an unreadable save."],
	"dialogue.started": [Level.INFO, "dialogue", "Conversation started."],
	"dialogue.ended": [Level.INFO, "dialogue", "Conversation ended."],
	"dialogue.no_line": [Level.WARNING, "dialogue", "A conversation ended without showing a line."],
	"dialogue.start_refused": [Level.ERROR, "dialogue", "Could not start a conversation.", {
		"reason": ["busy", "no_graph", "unknown_conversation", "no_state"],
	}],
	"dialogue.progress_failed": [Level.ERROR, "dialogue", "Dialogue could not advance normally.", {
		"reason": ["missing_node", "step_limit", "choice_out_of_range", "locale_rebind"],
	}],
	"dialogue.effect_refused": [Level.WARNING, "dialogue", "A dialogue effect was rejected."],
	"assets.load_failed": [Level.ERROR, "assets", "A game asset or content table could not be loaded.", {
		"kind": ["music", "dialogue", "inspections", "locations", "characters", "abilities"],
	}],
	"assets.text_load_timing": [Level.DEBUG, "assets", "Text corpus loading time.", {
		"elapsed_ms": "integer", "dialogue_locales": "integer", "inspection_locales": "integer",
	}],
	"state.flag_refused": [Level.ERROR, "state", "A story flag lacked an identifier."],
	"state.knowledge_write_refused": [Level.ERROR, "state", "A knowledge entry could not be recorded."],
	"state.knowledge_refused": [Level.WARNING, "state", "Narrative entries were rejected.", {
		"count": "integer",
	}],
	"state.restore_refused": [Level.ERROR, "state", "Narrative state could not be restored."],
}

var _locations: Dictionary = {}


func _init() -> void:
	# Use the published IDs, not arbitrary IDs supplied by a save or the scene being loaded.
	# The logger does not need to load/validate any of the actual location scenes.
	var locations: Variant = JsonTable.read_dict(LocationCatalog.PATH).get("locations")
	if locations is Dictionary:
		for key: Variant in locations:
			if key is String and key.length() <= 40 and key.is_valid_identifier():
				_locations[key] = true


func location_id(value: Variant) -> Variant:
	if value is String or value is StringName:
		var id := String(value)
		if id.length() <= 40 and _locations.has(id):
			return id
	return null


func build(event: String, definition: Array, fields: Dictionary, unix: int) -> Dictionary:
	return {
		"schema": VERSION,
		"event": event,
		"level": LEVEL_NAMES[definition[0]],
		"category": definition[1],
		"message": definition[2],
		"context": _context(definition, fields),
		"at_unix_s": unix,
		"last_unix_s": unix,
		"repeat": 1,
	}


## Reconstruct from the schema, never pass through text or keys read from disk.
func import_record(value: Variant) -> Dictionary:
	if not (value is Dictionary) or _integer(value.get("schema"), VERSION, VERSION) == null:
		return {}
	var event: Variant = value.get("event")
	if not (event is String) or not EVENTS.has(event):
		return {}
	var first: Variant = _integer(value.get("at_unix_s"), 0, MAX_UNIX)
	var last: Variant = _integer(value.get("last_unix_s"), 0, MAX_UNIX)
	var repeat: Variant = _integer(value.get("repeat"), 1, MAX_REPEAT)
	if first == null or last == null or repeat == null or last < first:
		return {}
	var fields: Variant = value.get("context")
	var row := build(event, EVENTS[event], fields if fields is Dictionary else {}, first)
	row["last_unix_s"] = last
	row["repeat"] = repeat
	return row


func _context(definition: Array, fields: Dictionary) -> Dictionary:
	var clean := {}
	if definition.size() < 4:
		return clean
	var rules: Dictionary = definition[3]
	for key: String in rules:
		var rule: Variant = rules[key]
		var value: Variant = fields.get(key)
		var safe: Variant = null
		if rule is Array:
			if (value is String or value is StringName) and String(value) in rule:
				safe = String(value)
		elif rule == "location":
			safe = location_id(value)
		elif rule == "integer":
			safe = _integer(value, 0, 1000000)
		if safe != null:
			clean[key] = safe
	return clean


static func _integer(value: Variant, minimum: int, maximum: int) -> Variant:
	if value is int or value is float:
		if value >= minimum and value <= maximum and value == int(value):
			return int(value)
	return null
