extends SceneTree
## Headless smoke test: instantiate the configured main scene and check its core nodes.

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

	var player: Node = game_root.get_node_or_null("Player")
	if not (player is CharacterBody3D):
		push_error("Smoke test failed: expected Player CharacterBody3D under Main.")
		game_root.queue_free()
		quit(1)
		return

	var camera: Node = player.get_node_or_null("Camera3D")
	if not (camera is Camera3D):
		push_error("Smoke test failed: expected Camera3D under Player.")
		game_root.queue_free()
		quit(1)
		return

	var ground: Node = game_root.get_node_or_null("Ground")
	if not (ground is StaticBody3D):
		push_error("Smoke test failed: expected Ground StaticBody3D under Main.")
		game_root.queue_free()
		quit(1)
		return

	game_root.queue_free()
	await process_frame
	print("Smoke test passed: main scene, player, camera, and ground instantiated.")
	quit(0)
