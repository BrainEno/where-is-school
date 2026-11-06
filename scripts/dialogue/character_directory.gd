extends RefCounted
class_name CharacterDirectory
## Display metadata for speakers. Content files reference speakers by id only, so
## renaming a character or restyling the UI never touches dialogue data.
##
## This is a code table rather than a .tres resource on purpose: it is tiny,
## typed, diff-reviewable, and needs no import step in headless CI.

const SPEAKERS: Dictionary = {
	&"protagonist": {
		"name": "You",
		"accent": Color(0.83, 0.80, 0.72),
		"role": "",
		"portrait": "res://assets/characters/protagonist_portrait.svg",
	},
	&"q": {
		"name": "Q",
		"accent": Color(0.90, 0.72, 0.49),
		"role": "classmate, next desk",
		"portrait": "res://assets/characters/q_portrait.svg",
	},
	&"b": {
		"name": "B",
		"accent": Color(0.74, 0.55, 0.50),
		"role": "biology teacher",
		"portrait": "res://assets/characters/b_portrait.svg",
	},
	&"n": {
		"name": "N",
		"accent": Color(0.63, 0.74, 0.76),
		"role": "substitute",
		"portrait": "res://assets/characters/n_portrait.svg",
	},
	&"aside": {
		"name": "",
		"accent": Color(0.62, 0.63, 0.60),
		"role": "",
	},
	&"caption": {
		"name": "",
		"accent": Color(0.62, 0.63, 0.60),
		"role": "",
	},
	&"system": {
		"name": "",
		"accent": Color(0.55, 0.56, 0.53),
		"role": "",
	},
}


static func has_speaker(speaker_id: StringName) -> bool:
	return SPEAKERS.has(speaker_id)


static func display_name(speaker_id: StringName) -> String:
	if not SPEAKERS.has(speaker_id):
		return String(speaker_id)
	return String(SPEAKERS[speaker_id]["name"])


static func role(speaker_id: StringName) -> String:
	if not SPEAKERS.has(speaker_id):
		return ""
	return String(SPEAKERS[speaker_id]["role"])


static func accent(speaker_id: StringName) -> Color:
	if not SPEAKERS.has(speaker_id):
		return Color(0.75, 0.75, 0.72)
	return SPEAKERS[speaker_id]["accent"]


static func portrait_path(speaker_id: StringName, imagined: bool = false) -> String:
	if not SPEAKERS.has(speaker_id):
		return ""
	if String(speaker_id) == "n" and imagined:
		return "res://assets/characters/n_portrait_unsure.svg"
	if String(speaker_id) == "q" and imagined:
		return "res://assets/characters/q_portrait_flat.svg"
	return String(SPEAKERS[speaker_id].get("portrait", ""))


static func is_narration(speaker_id: StringName) -> bool:
	return speaker_id == &"aside" or speaker_id == &"caption" or speaker_id == &"system"


## Verifies that a dialogue script only names known speakers. Returns a list of
## readable problems, empty when clean.
static func validate_script(script: DialogueScript) -> PackedStringArray:
	var problems := PackedStringArray()
	if script == null:
		problems.append("CharacterDirectory.validate_script received a null script.")
		return problems
	for node_id in script.node_ids():
		var node: DialogueNode = script.get_node(node_id)
		for line in node.lines:
			if not has_speaker(line.speaker):
				problems.append(
					"Dialogue '%s' node '%s' uses unknown speaker '%s'."
					% [String(script.id), String(node_id), String(line.speaker)]
				)
	return problems
