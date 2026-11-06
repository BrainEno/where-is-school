class_name Inspectable
extends Interactable
## Generic inspectable prop: plays a conversation and records the observation.
## Every Inspectable marks `observed.inspect.<interaction_id>` on first look;
## that namespace feeds progression checks (e.g. the bell condition).
## Revisiting the prop plays `repeat_conversation` when provided.

@export var conversation: DialogueConversation
@export var repeat_conversation: DialogueConversation
## When false, the inspection is not counted toward world-progress checks (used for the schoolbag).
@export var counts_for_progress: bool = true


func _ready() -> void:
	super()
	if interaction_id == &"":
		push_error("Inspectable at %s has no interaction_id; the observation flag will be malformed." % get_path())


func interact(player: Node) -> void:
	if not enabled:
		return
	var state: Node = _state()
	var already_inspected: bool = state != null and state.get_flag(&"observed.inspect." + interaction_id, false) == true

	var target: DialogueConversation = conversation
	if already_inspected and repeat_conversation != null:
		target = repeat_conversation

	if state != null and counts_for_progress and not already_inspected:
		state.set_flag(&"observed.inspect." + interaction_id, true)

	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("start_conversation"):
		ui.start_conversation(target)
	else:
		push_error("Inspectable: no node in group 'game_ui' with start_conversation(); cannot show dialogue for %s" % interaction_id)

	super(player)


func _state() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.get_root()
	if root == null:
		return null
	return root.get_node_or_null("GameState")
