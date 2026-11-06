class_name GateExit
extends Interactable
## The school gate at the far end of the corridor.
## Plays the closing beat, then hands off to the milestone end card.

@export var closing_conversation: DialogueConversation

var _waiting_for_end: bool = false


func interact(player: Node) -> void:
	if not enabled:
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui == null or not ui.has_method("start_conversation"):
		push_error("GateExit: no node in group 'game_ui' with start_conversation()")
		return
	if not ui.is_connected("conversation_finished", _on_conversation_finished):
		ui.connect("conversation_finished", _on_conversation_finished)
	_waiting_for_end = true
	ui.start_conversation(closing_conversation)
	super(player)


func _on_conversation_finished(conversation_id: StringName) -> void:
	if not _waiting_for_end:
		return
	if conversation_id != &"gate_end":
		return
	_waiting_for_end = false
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("show_end_card"):
		ui.show_end_card()
