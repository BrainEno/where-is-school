class_name ExitDoor
extends Interactable
## Classroom exit. Locked (conversationally) until N dismisses the class.

@export var conversation: DialogueConversation
@export var target_scene: String = ""
@export var spawn_id: StringName = &"from_classroom"


func interact(player: Node) -> void:
	if not enabled:
		return
	var tree := get_tree()
	var root := tree.get_root()
	var state: Node = root.get_node_or_null("GameState") if root else null
	var dismissed: bool = state != null and state.get_flag(&"flow.class_dismissed", false) == true
	if dismissed:
		var scene_flow: Node = root.get_node_or_null("SceneFlow") if root != null else null
		if scene_flow != null:
			scene_flow.travel(target_scene, spawn_id)
		else:
			get_tree().change_scene_to_file(target_scene)
	else:
		var ui := tree.get_first_node_in_group("game_ui")
		if ui != null and ui.has_method("start_conversation"):
			ui.start_conversation(conversation)
		else:
			push_error("ExitDoor: no node in group 'game_ui' with start_conversation()")
	super(player)
