class_name LocationExit
extends Interactable
## A door or threshold that moves the player to another location.
##
## The exit does not load anything itself. It reports the destination and lets
## the sequence director perform the transition, so scene changes stay in one
## place and story state survives them.

@export_file("*.tscn") var destination_scene: String = ""
@export var destination_spawn: StringName = &"default"
## Stable id of the destination location, written to StoryFlags.CURRENT_LOCATION.
@export var destination_id: StringName = &""
## When set, the exit only works once this flag is truthy. Until then the player
## is shown the blocked inspection text instead.
@export var required_flag: StringName = &""
## Inspection shown while the exit is still blocked.
@export var blocked_inspection_id: StringName = &""

@export_category("Milestone end")
## When true the exit does not change location: it ends the implemented slice
## with an explicit build card instead of inventing narrative content.
@export var is_milestone_end: bool = false
## Locale key prefix for the card ("end.slice" resolves end.slice.title/.body).
## The literal fields below stay as the fallback for a card that has no key.
@export var end_card_key: String = ""
@export var end_card_title: String = "End of this build"
@export var end_card_body: String = ""


func _ready() -> void:
	add_to_group("location_exit")
	super()


func is_open() -> bool:
	if String(required_flag).is_empty():
		return true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null:
		# Without story state the exit stays closed rather than guessing.
		push_error("LocationExit '%s': GameState is missing." % interact_id)
		return false
	return bool(game_state.get_flag(required_flag, false))
