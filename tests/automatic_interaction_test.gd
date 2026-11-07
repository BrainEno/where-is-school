extends SceneTree
## Clicking an object: walk to it, then use it — the same way E does.
##
## What this pins down:
##
## 1. clicking a person out of reach walks the character over and then starts the
##    conversation, once, through `InteractionController.activation_requested`;
## 2. clicking something already within reach activates it at once, without a step;
## 3. clicking an inspectable prop opens its inspection and nothing else;
## 4. clicking an exit performs the normal transition, story routing included;
## 5. a target that is disabled or freed while the character walks is *not* activated,
##    and the walk ends instead of continuing forever;
## 6. E still works and reaches the same activation path;
## 7. a ground click moves and never activates anything;
## 8. activating once means once: no repeat on the frames after arrival.
##
## The classroom is used for the person and the props, because it is the room with a
## talk target, an inspectable sheet, and a door in one place.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const STREET := "res://scenes/locations/street/street.tscn"
const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"
const EXIT_SCENE := "res://scenes/interaction/location_exit.tscn"

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _navigator: PointerNavigator = null
var _location: LocationRoot = null
var _activations: Array[StringName] = []
var _approaches_activated: Array[StringName] = []
var _approaches_abandoned: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 260.0, "automatic_interaction_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(2)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
		_navigator = _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if _host == null or _player == null or _interaction == null or _dialogue == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	if _navigator == null:
		Harness.finish(self, ["The player has no pointer navigator."], "")
		return
	if _sequence != null:
		_sequence.allow_player_control()

	# The passive inner voice can open its own conversation at any time, which would
	# lock the player mid-walk and make these timings a race. It is switched off here;
	# it has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	_interaction.activation_requested.connect(_on_activation)
	_navigator.approach_activated.connect(_on_approach_activated)
	_navigator.approach_abandoned.connect(_on_approach_abandoned)
	Engine.time_scale = 4.0
	await _frames(2)

	await _check_click_distant_person()
	await _check_click_in_reach_is_immediate()
	await _check_click_inspectable()
	await _check_click_exit_transitions()
	await _check_disabled_target_is_not_activated()
	await _check_freed_target_is_not_activated()
	await _check_e_still_works()
	await _check_ground_click_does_not_activate()

	Harness.finish(
		self, _failures,
		"a click on a person, a prop or an exit walks there and uses it exactly once, through the same path as E."
	)


# --- cases ------------------------------------------------------------------


## The headline case: the person is across the room, the character walks over, and the
## conversation starts on arrival — once.
func _check_click_distant_person() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var q := _find_interactable(location, &"q_talk")
	if q == null:
		_failures.append("The classroom lost the person to talk to.")
		return
	if not await _stand_far_from(q, 3.2, 4.6):
		_failures.append("Could not find a spot 3-4.6 m from the person with a clear view of it.")
		return
	_activations.clear()
	_approaches_activated.clear()
	var screen := _screen_of(q.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != q:
		_failures.append("Pointing at the person did not resolve to them before the click.")
		return
	_navigator.click_at_screen_position(screen)
	if not _navigator.was_last_click_accepted():
		_failures.append("Clicking the person was refused.")
		return
	if _navigator.get_pending_target() != q:
		_failures.append("Clicking the person did not make them the pending target.")
		return
	if not await _wait_until(func() -> bool: return not _activations.is_empty(), 16.0):
		_failures.append("The character never reached the person to talk to.")
		return
	if _activations.size() != 1:
		_failures.append("The person was activated %d times for one click." % _activations.size())
	if not _activations.is_empty() and _activations[0] != &"q_talk":
		_failures.append("The click activated '%s' instead of the person." % String(_activations[0]))
	if _approaches_activated.size() != 1:
		_failures.append("The approach reported %d activations." % _approaches_activated.size())
	if not _dialogue.is_busy():
		_failures.append("Activating the person did not start a conversation.")
	# Standing still afterwards must not re-trigger the conversation.
	var after := _activations.size()
	await _frames(40)
	if _activations.size() != after:
		_failures.append("The person was activated again while the conversation was open.")
	await _settle_dialogue()
	await _frames(3)


func _check_click_in_reach_is_immediate() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var probe := _make_probe(location, &"probe_near", &"classroom_own_desk")
	probe.radius = 0.6
	if not await _place_clear_of_props(probe, 1.0, 1.8):
		_failures.append("Could not place an in-reach probe with a clear view.")
		_free(probe)
		return
	await _physics_frames(3)
	_activations.clear()
	var screen := _screen_of(probe.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != probe:
		_failures.append("The close probe was not under the click position.")
		_free(probe)
		return
	_navigator.click_at_screen_position(screen)
	if _player.is_path_active():
		_failures.append("Clicking something within reach started a walk instead of using it.")
	if _activations.size() != 1:
		_failures.append("An in-reach click activated %d times." % _activations.size())
	if _navigator.get_pending_target() != null:
		_failures.append("An in-reach click left a pending target behind.")
	_free(probe)
	await _frames(2)
	await _settle_dialogue()


func _check_click_inspectable() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var sheet := _find_interactable(location, &"timetable")
	if sheet == null:
		_failures.append("The classroom lost the timetable sheet.")
		return
	if not await _stand_near(sheet, 1.0, 1.6):
		_failures.append("Could not stand in front of the timetable sheet.")
		return
	_activations.clear()
	var screen := _screen_of(sheet.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != sheet:
		_failures.append("The timetable sheet was not under the click position.")
		return
	_navigator.click_at_screen_position(screen)
	if _activations.size() != 1:
		_failures.append("Clicking the sheet activated %d times." % _activations.size())
	if not await _wait_until(func() -> bool: return _dialogue.is_busy(), 4.0):
		_failures.append("Clicking the sheet opened nothing.")
	await _settle_dialogue()
	await _frames(2)


## A probe exit in the classroom that leads to the corridor: the click has to perform
## the normal transition, by going through the sequence director rather than around it.
func _check_click_exit_transitions() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var packed: PackedScene = load(EXIT_SCENE)
	if packed == null:
		_failures.append("The exit scene could not be loaded.")
		return
	var exit := packed.instantiate() as LocationExit
	exit.name = "ProbeExit"
	exit.interact_id = &"probe_exit"
	exit.prompt_text = "Leave"
	exit.radius = 0.8
	exit.destination_scene = "res://scenes/locations/corridor/corridor.tscn"
	exit.destination_spawn = &"FromClassroom"
	exit.destination_id = &"corridor"
	location.add_child(exit)
	# Somewhere the character can stand next to: reuse the spot search around the exit.
	var placed := await _place_clear_of_props(exit, 1.4, 2.0)
	if not placed:
		_failures.append("Could not place a probe exit with room in front of it.")
		_free(exit)
		return
	await _physics_frames(3)
	_activations.clear()
	var screen := _screen_of(exit.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != exit:
		_failures.append("The probe exit was not under the click position.")
		_free(exit)
		return
	_navigator.click_at_screen_position(screen)
	var entered := await _wait_until(
		func() -> bool:
			var current := _host.get_current()
			return current != null and current.location_id == &"corridor",
		18.0
	)
	if not entered:
		_failures.append("Clicking an exit did not move the player to its destination.")
		return
	if _activations.size() != 1:
		_failures.append("The exit was activated %d times for one click." % _activations.size())
	if _player.global_position.y < -1.0:
		_failures.append("The transition dropped the character through the floor.")
	await _frames(3)


func _check_disabled_target_is_not_activated() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var probe := _make_probe(location, &"probe_disabled", &"classroom_own_desk")
	var placed := await _place_clear_of_props(probe, 3.0, 4.5)
	if not placed:
		_failures.append("Could not place a reachable probe 3-4.5 m away.")
		_free(probe)
		return
	await _physics_frames(3)
	_activations.clear()
	_approaches_abandoned.clear()
	var screen := _screen_of(probe.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != probe:
		_failures.append("The disabled-target probe was not under the click position.")
		_free(probe)
		return
	_navigator.click_at_screen_position(screen)
	if not _player.is_path_active():
		_failures.append(
			"Clicking a distant probe did not start a walk (accepted=%s, pending=%s)."
			% [str(_navigator.was_last_click_accepted()), _name_of(_navigator.get_pending_target())]
		)
		_free(probe)
		return
	await _physics_frames(2)
	probe.interaction_enabled = false
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), 16.0):
		_failures.append("The walk towards a disabled target never ended.")
		_player.cancel_path()
	await _frames(4)
	if not _activations.is_empty():
		_failures.append("A target disabled mid-walk was still activated.")
	if _approaches_abandoned.is_empty():
		_failures.append("Abandoning a disabled target was not reported.")
	_free(probe)
	await _frames(2)


func _check_freed_target_is_not_activated() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var probe := _make_probe(location, &"probe_freed", &"classroom_own_desk")
	var placed := await _place_clear_of_props(probe, 3.0, 4.5)
	if not placed:
		_failures.append("Could not place the vanishing probe.")
		_free(probe)
		return
	await _physics_frames(3)
	_activations.clear()
	_approaches_abandoned.clear()
	var screen := _screen_of(probe.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != probe:
		_failures.append("The vanishing probe was not under the click position.")
		_free(probe)
		return
	_navigator.click_at_screen_position(screen)
	await _physics_frames(2)
	_free(probe)
	if not await _wait_until(
		func() -> bool: return not _player.is_path_active() and _navigator.get_pending_target() == null,
		16.0
	):
		_failures.append("The walk towards a freed target never ended.")
		_player.cancel_path()
	await _frames(4)
	if not _activations.is_empty():
		_failures.append("A target freed mid-walk was still activated.")
	if _approaches_abandoned.is_empty():
		_failures.append(
			"A vanished target was not reported as abandoned (pending=%s, walk=%s)."
			% [str(_navigator.get_pending_target()), str(_player.is_path_active())]
		)


## The keyboard has to keep working, and it has to reach the same activation path.
func _check_e_still_works() -> void:
	var location := await _enter(CLASSROOM, &"PlayerStart")
	if location == null:
		return
	var probe := _make_probe(location, &"probe_key", &"classroom_own_desk")
	probe.radius = 0.6
	if not await _place_clear_of_props(probe, 1.0, 1.8):
		_failures.append("Could not place the probe for the E check.")
		_free(probe)
		return
	await _physics_frames(4)
	_activations.clear()
	# Pin the pointer on the probe so the target is decided, not guessed: this case is
	# about the key, not about what the player happens to be facing.
	_interaction.set_mouse_override(_screen_of(probe.global_position))
	await _physics_frames(4)
	if _interaction.get_current_target() != probe:
		_failures.append(
			"The probe was not the current target before pressing E (got '%s')."
			% _name_of(_interaction.get_current_target())
		)
	_interaction.clear_mouse_override()
	await _physics_frames(2)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	await _frames(3)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	root.push_input(release)
	var pressed_activation := not _activations.is_empty()
	if not pressed_activation:
		_failures.append("Pressing E activated nothing with a probe in reach.")
	elif _activations[0] != &"probe_key":
		_failures.append("E activated '%s' instead of the probe in front of the player." % String(_activations[0]))
	_free(probe)
	await _frames(2)
	await _settle_dialogue()


func _check_ground_click_does_not_activate() -> void:
	var location := await _enter(STREET, &"FromCorridor")
	if location == null:
		return
	_activations.clear()
	var destination: Variant = _reachable_ground_point(4.5)
	if destination == null:
		_failures.append("The street offered no walkable ground point for the ground click.")
		return
	var screen := _screen_of(destination)
	# Make sure nothing is in the way of the click: this case is about the floor.
	if _interaction.get_target_at_screen_position(screen, false) != null:
		_failures.append("The chosen ground click position was over an interactable.")
		return
	_navigator.click_at_screen_position(screen)
	if not _navigator.was_last_click_accepted():
		_failures.append("A walkable ground click was refused.")
		return
	if not _player.is_path_active():
		_failures.append("A ground click did not start a walk.")
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), 16.0):
		_failures.append("The ground walk never finished.")
		_player.cancel_path()
	if not _activations.is_empty():
		_failures.append("A ground click activated something.")
	var gap := Vector2(
		_player.global_position.x - destination.x, _player.global_position.z - destination.z
	).length()
	if gap > 1.2:
		_failures.append("The ground walk stopped %.2f m from the clicked point." % gap)
	# A click on the school wall is not a destination.
	var wall_click := await _find_wall_screen_position()
	if wall_click != Vector2.ZERO:
		var before := _player.global_position
		_navigator.click_at_screen_position(wall_click)
		await _physics_frames(3)
		if _navigator.was_last_click_accepted():
			_failures.append("A click on a wall was accepted as a destination.")
		if _player.is_path_active():
			_player.cancel_path()
		if _player.global_position.distance_to(before) > 0.3:
			_failures.append("A refused wall click moved the character.")


# --- helpers ----------------------------------------------------------------


func _enter(scene: String, spawn: StringName) -> LocationRoot:
	if not _host.load_location(scene, spawn, _player):
		return null
	await _frames(3)
	await _physics_frames(2)
	# Wait for a *routable* map, not just a baked mesh: the region's polygons reach
	# the navigation server a frame or two after the bake, and a query in that window
	# answers with nothing at all.
	var guard := 0
	while guard < 120:
		var current := _host.get_current()
		var nav: LocationNavigation = null
		if current != null:
			nav = current.get_node_or_null("Navigation") as LocationNavigation
		if nav != null and nav.is_baked() and nav.is_routable():
			break
		await physics_frame
		guard += 1
	_location = _host.get_current()
	_navigator.cancel()
	return _location


func _find_interactable(location: LocationRoot, interact_id: StringName) -> Interactable:
	return location.find_interactable(interact_id)


func _make_probe(location: LocationRoot, interact_id: StringName, inspection_id: StringName) -> Interactable:
	var packed: PackedScene = load(PROBE_SCENE)
	var probe := packed.instantiate() as Interactable
	probe.name = String(interact_id)
	probe.interact_id = interact_id
	probe.prompt_text = "Probe"
	probe.inspection_id = inspection_id
	probe.radius = 0.6
	location.add_child(probe)
	return probe


func _free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


## Stands the player at a navmesh point 3-4.6 m from `target` that both has a clear
## line of sight and a screen position that resolves to it.
func _stand_far_from(target: Interactable, min_distance: float, max_distance: float) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	var origin := target.global_position
	for radius in [max_distance, (min_distance + max_distance) * 0.5, min_distance + 0.3]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.5:
				continue
			if _interaction.is_in_reach_at(snapped, target):
				continue
			_player.teleport(Transform3D(Basis.IDENTITY, Vector3(snapped.x, snapped.y + 0.05, snapped.z)))
			await _physics_frames(3)
			var screen := _screen_of(target.global_position)
			if _interaction.get_target_at_screen_position(screen, false) == target:
				return true
	return false


## Stands the player `distance` from `target`, on the mesh, with the target under the
## cursor.
func _stand_near(target: Interactable, min_distance: float, max_distance: float) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	var origin := target.global_position
	for radius in [min_distance + 0.2, max_distance - 0.2]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.5:
				continue
			_player.teleport(Transform3D(Basis.IDENTITY, Vector3(snapped.x, snapped.y + 0.05, snapped.z)))
			await _physics_frames(3)
			if _interaction.get_target_at_screen_position(_screen_of(target.global_position), false) == target:
				return true
	return false


## Moves a freshly added probe/exit to a spot the player can see and reach from where
## they stand, and leaves the player in front of it.
func _place_clear_of_props(target: Interactable, min_distance: float, max_distance: float) -> bool:
	var map := _player.navigation_agent.get_navigation_map()
	var origin := _player.global_position
	for radius in [max_distance - 0.3, (min_distance + max_distance) * 0.5, min_distance + 0.3]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.5:
				continue
			target.global_position = Vector3(snapped.x, origin.y + 0.9, snapped.z)
			await _physics_frames(2)
			var path := NavigationServer3D.map_get_path(map, origin, snapped, true)
			if path.size() < 2:
				continue
			if _interaction.get_target_at_screen_position(_screen_of(target.global_position), false) == target:
				return true
	return false


func _reachable_ground_point(distance: float) -> Variant:
	var map := _player.navigation_agent.get_navigation_map()
	var origin := _player.global_position
	for radius in [distance, distance * 0.75]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.4:
				continue
			if NavigationServer3D.map_get_path(map, origin, snapped, true).size() < 2:
				continue
			return snapped
	return null


## Some screen position over a wall, found by trial: the capture run asks the same
## question with a real cursor.
func _find_wall_screen_position() -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	var size := _player.get_viewport().get_visible_rect().size
	for x in [0.2, 0.5, 0.8]:
		for y in [0.25, 0.5, 0.75]:
			var screen := Vector2(size.x * x, size.y * y)
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			if _navigator.is_enabled() and _navigator.can_walk_to_screen_position(screen):
				continue
			return screen
	return Vector2.ZERO


func _screen_of(world_position: Vector3) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world_position)


func _name_of(interactable: Interactable) -> String:
	return String(interactable.interact_id) if interactable != null else "<nothing>"


func _on_activation(interactable: Interactable) -> void:
	_activations.append(interactable.interact_id)


func _on_approach_activated(interactable: Interactable) -> void:
	_approaches_activated.append(interactable.interact_id)


func _on_approach_abandoned(interactable: Interactable) -> void:
	_approaches_abandoned.append(interactable.interact_id)


func _wait_until(condition: Callable, limit_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while not condition.call():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			return false
	return true


func _settle_dialogue() -> void:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > 20000:
			_failures.append("A conversation would not close.")
			return


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
