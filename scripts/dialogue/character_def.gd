class_name CharacterDef
extends Resource
## Presentation metadata for a speaker. Not referenced by gameplay logic,
## only by the dialogue UI. Characters B never appears; B has no def on purpose.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Kind drives styling: "character", "narration", "inner", "imagination".
@export var kind: String = "character"
## Placeholder portrait tint used in place of illustrated portraits.
@export var portrait_color: Color = Color(0.4, 0.4, 0.4)


func initial() -> String:
	if display_name.strip_edges().is_empty():
		return "?"
	return display_name.substr(0, 1).to_upper()
