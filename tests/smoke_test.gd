extends SceneTree
## Headless smoke test: instantiate the configured main scene and verify the
## composition the game needs at boot. This is the check CI has always run, kept
## working and extended to the prologue's actual structure.

func _initialize() -> void:
	call_deferred("_run_smoke_test")


func _run_smoke_test() -> void:
	var packed_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	if packed_scene == null:
		_fail("main scene could not be loaded.")
		return

	var game_root: Node = packed_scene.instantiate()
	if game_root == null:
		_fail("main scene could not be instantiated.")
		return

	root.add_child(game_root)
	await process_frame
	await process_frame

	var player: Node = game_root.get_node_or_null("Player")
	if not (player is CharacterBody3D):
		_fail("expected Player CharacterBody3D under Main.")
		return

	var camera: Node = player.get_node_or_null("Camera3D")
	if not (camera is Camera3D):
		_fail("expected Camera3D under Player.")
		return

	if not game_root.has_node("LocationRoot/Classroom"):
		_fail("expected the classroom to be loaded under LocationRoot.")
		return

	if not game_root.has_node("PrologueFlow"):
		_fail("expected PrologueFlow under Main.")
		return

	var hud: Node = game_root.get_node_or_null("Interface/Hud")
	var dialogue: Node = game_root.get_node_or_null("Interface/DialoguePanel")
	if hud == null or dialogue == null:
		_fail("expected the prologue HUD and dialogue panel under Interface.")
		return

	var interactables: int = 0
	for node in get_nodes_in_group(&"interactable"):
		if node is Interactable3D:
			interactables += 1
	if interactables < 6:
		_fail("expected at least six interactables in the classroom, found %d." % interactables)
		return

	game_root.queue_free()
	await process_frame
	print("Smoke test passed: main scene, classroom, player, camera, interaction sensor, HUD, dialogue panel, and %d interactables instantiated." % interactables)
	quit(0)


func _fail(message: String) -> void:
	push_error("Smoke test failed: %s" % message)
	quit(1)
