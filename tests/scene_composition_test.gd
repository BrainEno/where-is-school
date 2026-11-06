extends SceneTree
## Scene composition tests: classroom, corridor, and main must instantiate
## with their required nodes, spawn markers, and interactable targets.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	# --- classroom direct composition
	var classroom_scene: PackedScene = load("res://scenes/locations/classroom/classroom.tscn") as PackedScene
	if classroom_scene == null:
		failures.append("classroom.tscn could not be loaded")
	else:
		var classroom: Node = classroom_scene.instantiate()
		root.add_child(classroom)
		await process_frame
		_expect_node(failures, classroom, "Player", true)
		_expect_node(failures, classroom, "LessonDirector", true)
		_expect_node(failures, classroom, "Q_NPC", true)
		_expect_node(failures, classroom, "N_NPC", true)
		_expect_node(failures, classroom, "NEntryPoint", true)
		_expect_node(failures, classroom, "NDeskPoint", true)
		_expect_node(failures, classroom, "SpawnPlayer", true)
		_expect_node(failures, classroom, "GameUI", true)
		_expect_node(failures, classroom, "ExitDoor", true)
		_expect_node(failures, classroom, "BagInspect", true)
		_expect_node(failures, classroom, "SetSquareInspect", true)
		_expect_node(failures, classroom, "BlackboardInspect", true)
		var n_npc: Node = classroom.get_node_or_null("N_NPC")
		if n_npc != null and n_npc.visible:
			failures.append("N_NPC should start hidden before the substitute beat")
		var interactables: int = classroom.get_tree().get_nodes_in_group("interactables").size()
		if interactables < 8:
			failures.append("classroom expected at least 8 interactables, found %d" % interactables)
		var q_talk: Node = classroom.get_node_or_null("Q_NPC/QTalk")
		if q_talk == null:
			failures.append("Q_NPC/QTalk missing")
		classroom.queue_free()
		await process_frame

	# --- corridor direct composition
	var corridor_scene: PackedScene = load("res://scenes/locations/corridor/corridor.tscn") as PackedScene
	if corridor_scene == null:
		failures.append("corridor.tscn could not be loaded")
	else:
		var corridor: Node = corridor_scene.instantiate()
		root.add_child(corridor)
		await process_frame
		_expect_node(failures, corridor, "Player", true)
		_expect_node(failures, corridor, "GateExit", true)
		_expect_node(failures, corridor, "SpawnFromClassroom", true)
		_expect_node(failures, corridor, "CorridorDirector", true)
		_expect_node(failures, corridor, "GameUI", true)
		_expect_node(failures, corridor, "TrophyCaseInspect", true)
		_expect_node(failures, corridor, "PosterInspect", true)
		corridor.queue_free()
		await process_frame

	# --- street direct composition
	var street_scene: PackedScene = load("res://scenes/locations/street/street.tscn") as PackedScene
	if street_scene == null:
		failures.append("street.tscn could not be loaded")
	else:
		var street: Node = street_scene.instantiate()
		root.add_child(street)
		await process_frame
		_expect_node(failures, street, "Player", true)
		_expect_node(failures, street, "StreetDirector", true)
		_expect_node(failures, street, "GameUI", true)
		_expect_node(failures, street, "SpawnFromGate", true)
		_expect_node(failures, street, "GreenShape", true)
		_expect_node(failures, street, "GreenShapeInspect", true)
		_expect_node(failures, street, "StreetEndExit", true)
		var street_interactables: int = street.get_tree().get_nodes_in_group("interactables").size()
		if street_interactables < 2:
			failures.append("street expected at least 2 interactables, found %d" % street_interactables)
		street.queue_free()
		await process_frame

	# --- main composes the classroom
	var main_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		failures.append("main.tscn could not be loaded")
	else:
		var main: Node = main_scene.instantiate()
		root.add_child(main)
		await process_frame
		if main.get_node_or_null("Classroom") == null:
			failures.append("main.tscn does not instance the classroom")
		main.queue_free()
		await process_frame

	if not failures.is_empty():
		for failure in failures:
			push_error("scene_composition_test failed: %s" % failure)
		quit(1)
		return
	print("scene_composition_test passed")
	quit(0)


func _expect_node(failures: Array[String], root_node: Node, node_name: String, required: bool) -> void:
	if root_node.get_node_or_null(node_name) == null:
		if required:
			failures.append("expected node '%s' under %s" % [node_name, root_node.name])
