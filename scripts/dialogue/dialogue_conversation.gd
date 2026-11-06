class_name DialogueConversation
extends Resource
## A named conversation graph. Data lives in data/dialogue/*.tres, never in gameplay scripts.

## Stable conversation id, e.g. "q_intro".
@export var id: StringName = &""
## Entry shown when the conversation starts (unless started with an override).
@export var start_id: StringName = &""
## Presentation style: "standard" or "imagination".
## "imagination" renders with a distinct banner and palette and MUST NOT set
## objective-world flags; the runner enforces flag namespace rules for it.
@export var presentation: String = "standard"
@export var entries: Array[DialogueEntry] = []

func get_entry(entry_id: StringName) -> DialogueEntry:
	for entry in entries:
		if entry != null and entry.id == entry_id:
			return entry
	return null


func entry_ids() -> Dictionary:
	var ids: Dictionary = {}
	for entry in entries:
		if entry == null:
			continue
		if ids.has(entry.id):
			push_error("DialogueConversation '%s': duplicate entry id '%s'" % [id, entry.id])
		ids[entry.id] = true
	return ids


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("conversation with empty id")
	var ids := entry_ids()
	if not ids.has(start_id):
		errors.append("%s: start_id '%s' does not match any entry" % [id, start_id])
	for entry in entries:
		if entry == null:
			errors.append("%s: contains a null entry" % id)
			continue
		errors.append_array(entry.validate(str(id), ids))
	if presentation == "imagination":
		for entry in entries:
			if entry == null:
				continue
			if str(entry.set_flag) != "" and not String(entry.set_flag).begins_with("imagination."):
				errors.append("%s: imagination entry '%s' sets non-imagination flag '%s'" % [id, entry.id, entry.set_flag])
			for choice in entry.choices:
				if choice == null:
					continue
				if str(choice.set_flag) != "" and not String(choice.set_flag).begins_with("imagination."):
					errors.append("%s: imagination choice '%s' sets non-imagination flag '%s'" % [id, choice.text, choice.set_flag])
	return errors
