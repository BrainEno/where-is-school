extends RefCounted
class_name DialogueLine
## A single presented line of dialogue. Pure data; no UI, no scene access.

## Speaker identifier resolved through [CharacterDirectory]. Use &"aside" for
## unspoken stage direction and &"caption" for scene captions.
var speaker: StringName = &""
var text: String = ""
## When true the line is part of a rehearsal/expectation, not of the scene.
var imagined: bool = false
## Optional short parenthetical shown under the speaker name.
var note: String = ""


static func create(line_speaker: StringName, line_text: String, is_imagined: bool = false) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = line_speaker
	line.text = line_text
	line.imagined = is_imagined
	return line


static func aside(line_text: String) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = &"aside"
	line.text = line_text
	return line


static func caption(line_text: String) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = &"caption"
	line.text = line_text
	return line


static func imagined_by(line_speaker: StringName, line_text: String) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = line_speaker
	line.text = line_text
	line.imagined = true
	line.note = "imagined"
	return line


func is_valid() -> bool:
	return not String(speaker).is_empty() and not text.strip_edges().is_empty()


func _to_string() -> String:
	return "DialogueLine(%s: %s)" % [String(speaker), text]
