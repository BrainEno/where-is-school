extends SceneTree
## Granular smoke check: the main scene must instantiate and compose the classroom.
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
	if game_root.get_node_or_null("Classroom") == null:
		push_error("FAIL: expected Classroom instance under Main.")
		quit(1)
		return
	print("PASS main scene instantiates and composes the classroom.")
	quit(0)
