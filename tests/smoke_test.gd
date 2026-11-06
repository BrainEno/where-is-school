extends SceneTree
## Headless scene smoke test: instantiate the prologue's composition and check the
## nodes, content data, and wiring the prologue depends on actually exist.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_smoke_test")


func _run_smoke_test() -> void:
	var packed_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("main scene could not be loaded")
		return

	var game_root: Node = packed_scene.instantiate()
	if game_root == null:
		_fail("main scene could not be instantiated")
		return

	root.add_child(game_root)
	# Let _ready() run and let the director place the player at the desk spawn.
	await process_frame
	await process_frame
	await process_frame

	var player: Node = game_root.get_node_or_null("Player")
	if not (player is CharacterBody3D):
		_fail("expected a Player CharacterBody3D under Main")
	if player is CharacterBody3D:
		var body := player as CharacterBody3D
		if body.get_node_or_null("Camera3D") == null:
			_fail("expected a Camera3D under Player")
		if body.get_node_or_null("InteractionSensor") == null:
			_fail("expected an InteractionSensor under Player")

	var flow: Node = game_root.get_node_or_null("Flow")
	if flow == null or not (flow is PrologueFlow):
		_fail("expected a PrologueFlow under Main")
	elif (flow as PrologueFlow).ledger == null:
		_fail("PrologueFlow has no narrative ledger")

	var director: Node = game_root.get_node_or_null("Director")
	if director == null or not (director is PrologueDirector):
		_fail("expected a PrologueDirector under Main")

	var location_container: Node = game_root.get_node_or_null("LocationContainer")
	if location_container == null or location_container.get_child_count() == 0:
		_fail("expected the director to have loaded a location")
	else:
		_check_location(location_container.get_child(0))

	# The UI surfaces must exist and be wired, not merely present in the tree.
	if game_root.get_node_or_null("Hud") == null:
		_fail("expected a Hud CanvasLayer under Main")
	if game_root.get_node_or_null("DialoguePanel") == null:
		_fail("expected a DialoguePanel under Main")
	if game_root.get_node_or_null("NoteBook") == null:
		_fail("expected a NoteBook under Main")

	_check_all_locations_load()
	_check_dialogue_content()

	game_root.queue_free()
	await process_frame

	if _failures.is_empty():
		print("Smoke test passed: prologue composition, locations, props, and dialogue content instantiated.")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("Smoke test failed with %d problem(s)." % _failures.size())
		quit(1)


## The classroom must contain the interactables and spawn markers that the prologue
## relies on. This is what stops a scene edit from silently removing the bag.
func _check_location(location: Node) -> void:
	var interactables: Array[Node] = _collect_group(location, &"interactable")
	if interactables.size() < 6:
		_fail("expected at least 6 interactables in the classroom, found %d" % interactables.size())

	var required: Dictionary = {}
	for node: Node in interactables:
		if node is Interactable3D:
			required[String((node as Interactable3D).interact_id)] = true
	for expected: String in ["bag", "set_square", "teacher_desk", "timetable", "chair", "window", "q", "n"]:
		if not required.has(expected):
			_fail("classroom is missing interactable '%s'" % expected)

	if location.get_node_or_null("SpawnPoints/Desk") == null:
		_fail("classroom is missing the SpawnPoints/Desk marker")


func _collect_group(node: Node, group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_in_group(group):
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_collect_group(child, group))
	return found


## Loads every location scene, including the ones the opening does not reach
## immediately, so a broken corridor or street scene cannot ship unnoticed.
func _check_all_locations_load() -> void:
	for path: String in [
		"res://scenes/locations/classroom/classroom.tscn",
		"res://scenes/locations/corridor/corridor.tscn",
		"res://scenes/locations/street/street_threshold.tscn",
	]:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("location scene failed to load: %s" % path)
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			_fail("location scene failed to instantiate: %s" % path)
			continue
		# A location with no spawn marker would strand the player after a transition.
		if instance.get_node_or_null("SpawnPoints") == null:
			_fail("location has no SpawnPoints node: %s" % path)
		instance.free()


func _check_dialogue_content() -> void:
	var scripts: Array[DialogueScript] = [
		PrologueQConversation.build(),
		PrologueNConversation.build(),
		PrologueAnticipation.build(),
	]
	for script: DialogueScript in scripts:
		for problem: String in script.validate():
			_fail(problem)


func _fail(message: String) -> void:
	_failures.append(message)
