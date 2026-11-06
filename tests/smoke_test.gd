extends SceneTree
## Headless smoke test: instantiate the configured main scene and check its core nodes.
## The main scene now composes the classroom prologue; it must instantiate cleanly,
## expose the player, camera, UI, and director, and contain interactable props.

func _initialize() -> void:
	call_deferred("_run_smoke_test")


func _run_smoke_test() -> void:
	var packed_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("Smoke test failed: main scene could not be loaded.")
		quit(1)
		return

	var game_root: Node = packed_scene.instantiate()
	if game_root == null:
		push_error("Smoke test failed: main scene could not be instantiated.")
		quit(1)
		return

	root.add_child(game_root)
	await process_frame

	var failures: Array[String] = []

	var classroom: Node = game_root.get_node_or_null("Classroom")
	if classroom == null:
		failures.append("expected Classroom instance under Main")

	var player: Node = _find_node_by_class(game_root, "CharacterBody3D")
	if not (player is CharacterBody3D):
		failures.append("expected a CharacterBody3D player under Main")

	var camera: Node = null
	if player != null:
		camera = player.get_node_or_null("Camera3D")
	if not (camera is Camera3D):
		failures.append("expected Camera3D under the player")
	elif not (camera as Camera3D).current:
		failures.append("expected player camera to be current")

	var director: Node = game_root.find_child("LessonDirector", true, false)
	if director == null:
		failures.append("expected a LessonDirector under Main")

	var game_ui: Node = game_root.get_tree().get_first_node_in_group("game_ui")
	if game_ui == null:
		failures.append("expected a node in group 'game_ui'")

	var interactables: int = game_root.get_tree().get_nodes_in_group("interactables").size()
	if interactables < 6:
		failures.append("expected at least 6 interactables, found %d" % interactables)

	game_root.queue_free()
	await process_frame

	if not failures.is_empty():
		for failure in failures:
			push_error("Smoke test failed: %s" % failure)
		quit(1)
		return
	print("Smoke test passed: main scene composes the classroom; player, camera, director, UI and %d interactables present." % interactables)
	quit(0)


func _find_node_by_class(root_node: Node, class_text: String) -> Node:
	if root_node.is_class(class_text) or root_node.get_class() == class_text:
		return root_node
	for child in root_node.get_children():
		if child is Node:
			var found: Node = _find_node_by_class(child, class_text)
			if found != null:
				return found
	return null
