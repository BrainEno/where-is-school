class_name EndExit
extends Interactable
## Prologue terminus. Stepping past this point ends the run and shows the
## end card. Story state is already settled by this stage; this only closes it.

@export var flow_flag: StringName = &"flow.prologue_complete"


func interact(player: Node) -> void:
	if not enabled:
		return
	var root := get_tree().get_root()
	var state: Node = root.get_node_or_null("GameState") if root else null
	if state != null:
		state.set_flag(flow_flag, true)
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("show_end_card"):
		ui.show_end_card()
	else:
		push_error("EndExit: no node in group 'game_ui' with show_end_card()")
	super(player)
