class_name GateExit
extends Interactable
## The school gate at the far end of the corridor.
## Plays the closing beat, then hands off to the street.

@export var closing_conversation: DialogueConversation
@export var target_scene: String = "res://scenes/locations/street/street.tscn"
@export var spawn_id: StringName = &"from_gate"

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
	var root := get_tree().get_root()
	var scene_flow: Node = root.get_node_or_null("SceneFlow") if root else null
	if scene_flow != null:
		scene_flow.travel(target_scene, spawn_id)
	else:
		get_tree().change_scene_to_file(target_scene)
