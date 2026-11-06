class_name CorridorDirector
extends Node
## Places the player at the matching spawn point on scene entry
## and states the corridor objective. No pacing logic lives here.

@export var player: Node3D
@export var spawn_from_classroom: Marker3D


func _ready() -> void:
	var spawn_id: StringName = &"from_classroom"
	var root := get_tree().get_root()
	var scene_flow: Node = root.get_node_or_null("SceneFlow") if root else null
	if scene_flow != null:
		spawn_id = scene_flow.consume_spawn_id()
	if (spawn_id == &"from_classroom" or spawn_id == &"") and player != null and spawn_from_classroom != null:
		player.global_position = spawn_from_classroom.global_position
		player.global_rotation = spawn_from_classroom.global_rotation
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("set_objective"):
		ui.set_objective("Leave through the gate.")
