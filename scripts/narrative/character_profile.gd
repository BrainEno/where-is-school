class_name CharacterProfile
extends Resource
## Display identity for a speaker. Text content lives in data files and refers
## to characters by `character_id`; this resource only holds presentation data.

@export var character_id: StringName = &""
@export var display_name: String = ""
## Short role shown next to the name, e.g. "classmate". Not a title or diagnosis.
@export var short_role: String = ""
@export var accent_color: Color = Color(0.776, 0.733, 0.643, 1.0)
