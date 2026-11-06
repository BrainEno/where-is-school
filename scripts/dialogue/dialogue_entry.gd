class_name DialogueEntry
extends Resource
## One beat of conversation: a speaker line, optional effects, and either
## a list of choices or a linear `next_id`. Empty next_id with no choices ends the conversation.

## Unique within the conversation. Stable; used as save/debug identifier.
@export var id: StringName = &""
## References a CharacterDef id (e.g. "q", "n", "narrator", "inner", "imagination").
@export var speaker_id: StringName = &""
@export_multiline var text: String = ""
## Linear continuation. Ignored when `choices` is non-empty.
@export var next_id: StringName = &""
## Story flag applied when this entry is shown. Empty means no flag is set.
@export var set_flag: StringName = &""
@export var set_value: Variant = true
@export var choices: Array[DialogueChoice] = []


func validate(conversation_id: String, entry_ids: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("%s: entry with empty id" % conversation_id)
		return errors
	if speaker_id == &"":
		errors.append("%s: entry '%s' has empty speaker_id" % [conversation_id, id])
	if text.strip_edges().is_empty():
		errors.append("%s: entry '%s' has empty text" % [conversation_id, id])
	if str(next_id) != "" and not entry_ids.has(next_id):
		errors.append("%s: entry '%s' points at unknown next_id '%s'" % [conversation_id, id, next_id])
	for choice in choices:
		if choice == null:
			errors.append("%s: entry '%s' contains a null choice" % [conversation_id, id])
			continue
		errors.append_array(choice.validate(conversation_id))
		if str(choice.next_id) != "" and not entry_ids.has(choice.next_id):
			errors.append("%s: entry '%s' choice '%s' points at unknown next_id '%s'" % [conversation_id, id, choice.text, choice.next_id])
	return errors
