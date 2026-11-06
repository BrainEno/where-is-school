class_name QTalk
extends Interactable
## Q talks differently depending on how the opening went.
## The scene chooses which starting entry of the same conversation to play;
## story branching stays inside dialogue data wherever possible.

@export var conversation: DialogueConversation


func interact(player: Node) -> void:
	if not enabled:
		return
	var tree := get_tree()
	var root := tree.get_root()
	var state: Node = root.get_node_or_null("GameState") if root else null
	var override: StringName = &""
	if state != null and state.get_flag(&"choice.pretend_remembered", false) == true:
		override = &"ft_start_pretend"
	var ui := tree.get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("start_conversation"):
		ui.start_conversation(conversation, override)
	else:
		push_error("QTalk: no node in group 'game_ui' with start_conversation()")
	super(player)
