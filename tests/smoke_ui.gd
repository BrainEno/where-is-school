extends SceneTree
## Granular smoke check: UI group registration and the lesson director.
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
	var game_ui: Node = game_root.get_tree().get_first_node_in_group("game_ui")
	if game_ui == null:
		push_error("FAIL: no node in group 'game_ui'.")
		quit(1)
		return
	var director: Node = game_root.find_child("LessonDirector", true, false)
	if director == null:
		push_error("FAIL: LessonDirector missing.")
		quit(1)
		return
	var n_npc: Node = game_root.find_child("N_NPC", true, false)
	if n_npc == null:
		push_error("FAIL: N_NPC missing.")
		quit(1)
		return
	if (n_npc as Node3D).visible:
		push_error("FAIL: N_NPC should start hidden.")
		quit(1)
		return
	print("PASS UI group registered; director present; substitute hidden until the bell beat.")
	quit(0)
