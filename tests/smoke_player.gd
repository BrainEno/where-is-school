extends SceneTree
## Granular smoke check: player, camera, and the interactables group.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("FAIL: main scene could not be loaded.")
		quit(1)
		return
	var game_root: Node = packed_scene.instantiate()
	if game_root == null:
		push_error("FAIL: main scene could not be instantiated.")
		quit(1)
		return
	root.add_child(game_root)
	await process_frame
	var player: Node = null
	for child in game_root.find_children("*", "CharacterBody3D", true, false):
		player = child
		break
	if player == null:
		push_error("FAIL: no CharacterBody3D player found.")
		quit(1)
		return
	var camera: Node = player.get_node_or_null("Camera3D")
	if camera == null:
		push_error("FAIL: player has no Camera3D.")
		quit(1)
		return
	if not (camera as Camera3D).current:
		push_error("FAIL: player camera is not current.")
		quit(1)
		return
	var interactables: int = game_root.get_tree().get_nodes_in_group("interactables").size()
	if interactables < 6:
		push_error("FAIL: expected at least 6 interactables, found %d." % interactables)
		quit(1)
		return
	print("PASS player, current camera, and %d interactables." % interactables)
	quit(0)
