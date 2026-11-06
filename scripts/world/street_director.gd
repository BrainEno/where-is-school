class_name StreetDirector
extends Node
## Places the player at the gate spawn on scene entry, states the street
## objective, and removes the green shape once the observation conversation
## has played out ("briefly seen, then not").

@export var player: Node3D
@export var spawn_from_gate: Marker3D
@export var green_shape: Node3D
@export var green_shape_inspect: Node3D

const GREEN_ANIMAL_ID: StringName = &"street_green_animal"


func _ready() -> void:
	var root := get_tree().get_root()
	var scene_flow: Node = root.get_node_or_null("SceneFlow") if root else null
	var spawn_id: StringName = &"from_gate"
	if scene_flow != null:
		spawn_id = scene_flow.consume_spawn_id()
	if (spawn_id == &"from_gate" or spawn_id == &"") and player != null and spawn_from_gate != null:
		player.global_position = spawn_from_gate.global_position
		player.global_rotation = spawn_from_gate.global_rotation
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("set_objective"):
		ui.set_objective("Follow the road.")
	if ui != null and ui.has_signal("conversation_finished") and not ui.is_connected("conversation_finished", _on_conversation_finished):
		ui.connect("conversation_finished", _on_conversation_finished)


func _on_conversation_finished(conversation_id: StringName) -> void:
	if conversation_id != GREEN_ANIMAL_ID:
		return
	if green_shape != null:
		green_shape.visible = false
	if green_shape_inspect != null:
		var interactable: Interactable = green_shape_inspect as Interactable
		if interactable != null:
			interactable.enabled = false
