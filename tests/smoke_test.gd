extends SceneTree
## Scene smoke test: the project's entry scene instantiates, the classroom loads,
## and every subsystem the opening needs is present and wired.
##
## The opening beats are not started here (autostart is disabled) so this test
## stays fast and deterministic; tests/opening_flow_test.gd drives the beats.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "smoke_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		_failures.append("GameState autoload could not be created.")
	if autoloads["narrative_state"] == null:
		_failures.append("NarrativeState autoload could not be created.")
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		Harness.finish(self, _failures, "")
		return

	var main: Node = packed.instantiate()
	if main == null:
		_failures.append("main.tscn could not be instantiated.")
		Harness.finish(self, _failures, "")
		return

	var sequence: OpeningSequence = main.get_node_or_null("OpeningSequence")
	if sequence == null:
		_failures.append("Main is missing the OpeningSequence node.")
	else:
		sequence.autostart = false

	root.add_child(main)
	await process_frame
	await process_frame

	_check_player(main)
	_check_location(main)
	_check_ui(main)
	_check_content(main)

	main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "main scene, classroom, player, UI, and content loaded.")


func _check_player(main: Node) -> void:
	var player := main.get_node_or_null("Player")
	if not (player is CharacterBody3D):
		_failures.append("Expected a Player CharacterBody3D under Main.")
		return
	var controller := player as PlayerController
	if controller == null:
		_failures.append("Player does not use PlayerController.")
	var camera := player.get_node_or_null("Camera3D")
	if not (camera is Camera3D):
		_failures.append("Expected a Camera3D under Player.")
	elif not (camera as Camera3D).current:
		_failures.append("Player camera is not current.")
	var sensor := player.get_node_or_null("InteractionSensor")
	if not (sensor is Area3D):
		_failures.append("Expected an InteractionSensor Area3D under Player.")
	var interaction := player.get_node_or_null("InteractionController")
	if not (interaction is InteractionController):
		_failures.append("Player is missing its InteractionController.")


func _check_location(main: Node) -> void:
	var host: LocationHost = main.get_node_or_null("LocationHost")
	if host == null:
		_failures.append("Main is missing the LocationHost node.")
		return
	var location := host.get_current()
	if location == null:
		_failures.append("LocationHost did not load a location.")
		return
	if String(location.location_id) != "classroom":
		_failures.append("The game did not start in the classroom (got '%s')." % location.location_id)
	if location.get_spawn(&"PlayerStart") == null:
		_failures.append("The classroom has no PlayerStart spawn marker.")
	var interactables := location.get_interactables()
	if interactables.size() < 8:
		_failures.append(
			"Expected at least 8 interactables in the classroom, found %d." % interactables.size()
		)
	if location.find_actor(&"q") == null:
		_failures.append("The classroom has no Q actor.")
	if location.find_actor(&"n") == null:
		_failures.append("The classroom has no substitute actor.")
	if location.get_waypoint_path(&"NEntryPath").size() < 2:
		_failures.append("The classroom NEntryPath needs at least two markers.")
	if location.get_node_or_null("Ambience") == null:
		_failures.append("The classroom has no ambience player.")
	if location.get_node_or_null("Sun") == null:
		_failures.append("The classroom has no directional light.")


func _check_ui(main: Node) -> void:
	var ui: GameUI = main.get_node_or_null("GameUI")
	if ui == null:
		_failures.append("Main is missing the GameUI canvas layer.")
		return
	if ui.hud == null:
		_failures.append("GameUI is missing the HUD.")
	if ui.fade == null:
		_failures.append("GameUI is missing the fade layer.")
	if ui.overlay == null:
		_failures.append("GameUI is missing the imagination overlay.")
	if ui.end_card == null:
		_failures.append("GameUI is missing the end card.")
	if ui.dialogue_panel == null:
		_failures.append("GameUI is missing the dialogue panel.")
	if ui.backlog == null:
		_failures.append("GameUI is missing the backlog panel.")


func _check_content(main: Node) -> void:
	var controller: DialogueController = main.get_node_or_null("DialogueController")
	if controller == null:
		_failures.append("Main is missing the DialogueController node.")
		return
	var library: DialogueLibrary = controller.get_dialogue_library()
	if library == null:
		_failures.append("Dialogue content failed to load.")
	elif not library.is_valid():
		_failures.append(library.describe_errors())

	var inspections: InspectionLibrary = controller.get_inspection_library()
	if inspections == null:
		_failures.append("Inspection content failed to load.")
	elif not inspections.is_valid():
		_failures.append(inspections.describe_errors())

	# Built from the controller's own registry, so this covers the inner voices' profiles
	# too: a voice with no `data/characters/<speaker>.tres` fails the smoke test.
	var characters := CharacterDirectory.load_all(controller.get_abilities())
	if not characters.errors.is_empty():
		_failures.append("\n".join(characters.errors))
