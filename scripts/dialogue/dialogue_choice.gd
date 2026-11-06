class_name DialogueChoice
extends Resource
## A single selectable option shown on a dialogue entry.

## Text displayed on the button.
@export var text: String = ""
## Entry to jump to when chosen. Must exist in the same conversation.
@export var next_id: StringName = &""
## Optional gate: the choice is only shown while this flag equals `condition_equals`.
## Empty condition_flag means the choice is always shown.
@export var condition_flag: StringName = &""
@export var condition_equals: Variant = true
## Story flag applied when the choice is picked. Empty means no flag is set.
@export var set_flag: StringName = &""
@export var set_value: Variant = true


func validate(conversation_id: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if text.strip_edges().is_empty():
		errors.append("%s: choice with empty text" % conversation_id)
	if next_id == &"":
		errors.append("%s: choice '%s' has empty next_id" % [conversation_id, text])
	return errors
