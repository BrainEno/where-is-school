class_name CharacterDialogueAnimation
extends Node
## Presentation -> actor animation bridge. It owns no dialogue, routing or movement.
## Only explicitly opted-in visuals speak: the visible incarnation of an NpcActor,
## or a stationary visual with a speaker id of its own (the seated classmate).

@export var controller_path: NodePath = ^"../DialogueController"

var _controller: DialogueController


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as DialogueController
	if _controller == null:
		push_error("CharacterDialogueAnimation: no DialogueController at '%s'." % controller_path)
		return
	_controller.line_presented.connect(_on_line_presented)
	_controller.presentation_active_changed.connect(_on_presentation_active_changed)
	_on_line_presented(_controller.get_current_line() if _controller.is_busy() else {})


func _on_line_presented(line: Dictionary) -> void:
	# A quoted/imagined voice is not a request for the onstage actor to speak.
	var speaker := StringName(String(line.get("speaker_id", "")))
	if bool(line.get("subjective", false)):
		speaker = &""
	_apply_speaker(speaker)


func _on_presentation_active_changed(active: bool) -> void:
	if not active:
		_apply_speaker(&"")


func _apply_speaker(speaker: StringName) -> void:
	for node in get_tree().get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor == null:
			continue
		var animator := actor.get_character_animator()
		if animator != null:
			animator.set_talking(not speaker.is_empty() and actor.npc_id == speaker
				and animator.is_visible_in_tree())
	for node in get_tree().get_nodes_in_group("seated_dialogue_speaker"):
		var visual := node as CharacterVisualAnimation
		if visual != null:
			visual.set_talking(not speaker.is_empty() and visual.dialogue_speaker_id == speaker
				and visual.is_visible_in_tree())
