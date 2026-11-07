extends SceneTree
## What happens to an automatic walk when the player changes their mind.
##
## The bug this test was written for: `PointerNavigator._walk_to()` cleared `_pending`
## without clearing `_has_pending`, so the next `_physics_process()` saw "a pending target
## that is no longer valid" and cancelled the ground path it had just started. Click Q,
## change your mind, click the floor, and the character stood still.
##
## Four cases, all through the same click path the mouse uses:
##
## 1. an NPC in flight, then a ground click: the NPC is abandoned once, never activated,
##    and the walk to the floor really happens;
## 2. one object replaced by another: only the second one is activated;
## 3. one ground point replaced by another: the second one wins;
## 4. the target freed, and the target switched off, mid-walk: no activation, and no
##    state left behind for whatever happens next.
##
## The clicks are screen positions, because that is the interface. The geometry is made
## of probes placed at known offsets rather than real props, unless the case is about Q.

const Harness = preload("res://tests/test_harness.gd")
const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"
const TIMEOUT_SECONDS := 12.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _navigator: PointerNavigator = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null

var _activated: Array[StringName] = []
var _approaches_started: Array[StringName] = []
var _approaches_activated: Array[StringName] = []
var _approaches_abandoned: Array[StringName] = []

var _probe_a: Interactable = null
var _probe_b: Interactable = null
var _probe_c: Interactable = null
var _probe_d: Interactable = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "pointer_target_switch_test.gd")
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
	await process_frame
	await process_frame

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
		_navigator = _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if _host == null or _player == null or _interaction == null or _navigator == null \
			or _dialogue == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return

	_navigator.approach_started.connect(_on_approach_started)
	_navigator.approach_activated.connect(_on_approach_activated)
	_navigator.approach_abandoned.connect(_on_approach_abandoned)
	_interaction.activation_requested.connect(_on_activation)
	_sequence.allow_player_control()
	Engine.time_scale = 4.0
	await _frames(4)

	_location = _host.get_current()
	if _location == null:
		Harness.finish(self, ["The classroom is not loaded."], "")
		return

	await _place_probes()
	await _check_npc_then_ground()
	await _check_object_replaces_object()
	await _check_ground_replaces_ground()
	await _check_target_freed_and_disabled()
	_free_probes()

	Harness.finish(
		self, _failures,
		"a new click replaces the old target once, and the walk it asks for survives."
	)


# --- setup ------------------------------------------------------------------


## Two probes in the open aisle beside the player, far enough away that reaching one is
## a walk rather than an instant activation. Their ids are legal inspections so that an
## activation is a normal request; this test never reads what they say.
func _place_probes() -> void:
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6)))
	await _physics_frames(2)
	var origin := _player.global_position
	_probe_a = _make_probe(&"switch_probe_a", origin + Vector3(-1.1, 0.9, -1.4))
	_probe_b = _make_probe(&"switch_probe_b", origin + Vector3(1.1, 0.9, -1.4))
	_probe_c = _make_probe(&"switch_probe_c", origin + Vector3(-1.1, 0.9, 1.4))
	_probe_d = _make_probe(&"switch_probe_d", origin + Vector3(1.1, 0.9, 1.4))
	await _physics_frames(4)


func _make_probe(interact_id: StringName, position: Vector3) -> Interactable:
	var packed: PackedScene = load(PROBE_SCENE)
	var probe := packed.instantiate() as Interactable
	probe.name = String(interact_id)
	probe.interact_id = interact_id
	probe.prompt_text = "Probe"
	probe.inspection_id = &"classroom_own_desk"
	probe.radius = 0.7
	_location.add_child(probe)
	probe.global_position = position
	return probe


func _free_probes() -> void:
	for probe: Interactable in [_probe_a, _probe_b, _probe_c, _probe_d]:
		if probe != null and is_instance_valid(probe):
			probe.queue_free()


# --- case 1: NPC, then the floor --------------------------------------------


func _check_npc_then_ground() -> void:
	await _reset_to_start()
	var q := _location.find_interactable(&"q_talk") as Interactable
	if q == null:
		_failures.append("The classroom has no Q to click in the first case.")
		return
	_clear_events()
	if not _click(q.global_position):
		_failures.append("Clicking Q was refused before the switch could be tested (%s)." % _navigator.get_last_rejection())
		return
	await _physics_frames(3)
	if not _navigator.is_approaching():
		_failures.append("Clicking Q from across the room did not start an approach.")
		return
	if _navigator.get_pending_target() != q:
		_failures.append("The approach did not hold Q as its target.")

	var ground := _reachable_ground_screen(2.0, 4.5)
	if ground == null:
		_failures.append("No walkable floor point was clickable for the switch case.")
		return
	var point: Vector3 = _navigator.get_ground_point_at(ground)
	_navigator.click_at_screen_position(ground)

	# The bug: this state was "pending but invalid", and the next physics frame
	# cancelled the walk that had just been accepted.
	if _navigator.get_pending_target() != null:
		_failures.append("The abandoned Q target is still held as pending after a ground click.")
	if _navigator.is_approaching():
		_failures.append("The navigator still reports an approach after a ground click.")
	if not _player.is_path_active():
		_failures.append(
			"A ground click during an approach did not start a walk (%s)."
			% _navigator.get_last_rejection()
		)
		return
	await _physics_frames(3)
	if not _player.is_path_active():
		_failures.append("The walk to the ground was cancelled by its own target clean-up.")
		return
	if _count(_approaches_abandoned, &"q_talk") != 1:
		_failures.append(
			"Q was abandoned %d time(s) by one ground click, not once."
			% _count(_approaches_abandoned, &"q_talk")
		)
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), 8.0):
		_failures.append("The character never finished walking to the clicked floor.")
		return
	var travelled := _flat_distance(_player.global_position, point)
	if travelled > 1.0:
		_failures.append("The character stopped %.2f m from the clicked floor point." % travelled)
	await _physics_frames(6)
	if _count(_approaches_activated, &"q_talk") > 0 or _count(_activated, &"q_talk") > 0:
		_failures.append("An abandoned target was activated later anyway.")
	if _navigator.get_pending_target() != null:
		_failures.append("A pending target survived the completed ground walk.")
	await _settle_dialogue()


# --- case 2: object replaced by object ---------------------------------------


func _check_object_replaces_object() -> void:
	await _reset_to_start()
	_clear_events()
	if not _click(_probe_a.global_position):
		_failures.append("Clicking the first probe was refused (%s)." % _navigator.get_last_rejection())
		return
	await _physics_frames(3)
	if not _navigator.is_approaching():
		_failures.append("Clicking the first probe did not start an approach.")
		return
	if not _click(_probe_b.global_position):
		_failures.append("Clicking the second probe was refused (%s)." % _navigator.get_last_rejection())
		return
	if _count(_approaches_abandoned, &"switch_probe_a") != 1:
		_failures.append(
			"The first object was abandoned %d time(s) when the second was clicked."
			% _count(_approaches_abandoned, &"switch_probe_a")
		)
	if _navigator.get_pending_target() != _probe_b:
		_failures.append("The second object did not become the target.")
	if not await _wait_until(
		func() -> bool: return not _approaches_activated.is_empty(), 10.0
	):
		_failures.append("Neither object was reached after the switch.")
		return
	if _approaches_activated != ([&"switch_probe_b"] as Array[StringName]):
		_failures.append(
			"Waiting on the second object activated %s instead." % str(_approaches_activated)
		)
	if _activated.has(&"switch_probe_a"):
		_failures.append("The replaced object was activated as well.")
	if _navigator.get_pending_target() != null or _navigator.is_approaching():
		_failures.append("State was left over after the second object was used.")
	await _settle_dialogue()


# --- case 3: ground replaced by ground --------------------------------------


func _check_ground_replaces_ground() -> void:
	await _reset_to_start()
	_clear_events()
	var first := _reachable_ground_screen(2.0, 4.0)
	if first == null:
		_failures.append("No first floor point was clickable.")
		return
	var first_point: Vector3 = _navigator.get_ground_point_at(first)
	_navigator.click_at_screen_position(first)
	await _physics_frames(2)
	if not _player.is_path_active():
		_failures.append("A plain floor click did not start a walk (%s)." % _navigator.get_last_rejection())
		return
	var second := _reachable_ground_screen(2.0, 4.0)
	if second == null:
		_failures.append("No second floor point was clickable.")
		return
	var second_point: Vector3 = _navigator.get_ground_point_at(second)
	if _flat_distance(first_point, second_point) < 1.0:
		_failures.append("The two floor points were too close to tell apart.")
		return
	_navigator.click_at_screen_position(second)
	await _physics_frames(2)
	if not _player.is_path_active():
		_failures.append("The second floor click did not leave a walk running.")
		return
	if _flat_distance(_player.get_path_target(), second_point) > 0.6:
		_failures.append(
			"The character is still walking to the first floor point (%.2f m from the second)."
			% _flat_distance(_player.get_path_target(), second_point)
		)
	if not _approaches_abandoned.is_empty():
		_failures.append("A floor-to-floor click abandoned an interaction target that never existed.")
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), 8.0):
		_failures.append("The character never arrived after the second floor click.")
		return
	if _flat_distance(_player.global_position, second_point) > 1.0:
		_failures.append("The character did not end up at the second floor point.")


# --- case 4: the target goes away while walking ------------------------------


func _check_target_freed_and_disabled() -> void:
	await _reset_to_start()
	_clear_events()
	if not _click(_probe_c.global_position):
		_failures.append("Clicking the probe that gets freed was refused.")
		return
	await _physics_frames(3)
	if not _navigator.is_approaching():
		_failures.append("The probe that gets freed was never approached.")
		return
	_probe_c.queue_free()
	await _physics_frames(4)
	if _navigator.get_pending_target() != null:
		_failures.append("A freed target is still reported as pending.")
	if _navigator.is_approaching():
		_failures.append("The navigator still reports an approach to a freed target.")
	if _player.is_path_active():
		_failures.append("The walk to a freed target was not cancelled.")
	if not _approaches_abandoned.has(&"<gone>"):
		_failures.append("A freed target was not reported as abandoned.")

	# The same, for a target that is switched off rather than deleted.
	await _reset_to_start()
	_clear_events()
	if not _click(_probe_d.global_position):
		_failures.append("Clicking the probe that gets disabled was refused.")
		return
	await _physics_frames(3)
	if not _navigator.is_approaching():
		_failures.append("The probe that gets disabled was never approached.")
		return
	_probe_d.interaction_enabled = false
	await _physics_frames(4)
	if _navigator.get_pending_target() != null:
		_failures.append("A disabled target is still reported as pending.")
	if _player.is_path_active():
		_failures.append("The walk to a disabled target was not cancelled.")

	# Whatever happens next — another room, another click — must not inherit the state.
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6)))
	await _physics_frames(4)
	if _navigator.get_pending_target() != null or _navigator.is_approaching():
		_failures.append("Interaction state survived a location-style teleport.")
	if _player.is_path_active():
		_failures.append("A walk survived a location-style teleport.")
	await _physics_frames(20)
	if not _activated.is_empty():
		_failures.append("Something was activated after the targets went away: %s." % str(_activated))


# --- helpers ----------------------------------------------------------------


func _reset_to_start() -> void:
	await _settle_dialogue()
	_sequence.allow_player_control()
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6)))
	await _physics_frames(3)


## A click at the screen position of a world point, through the same call the mouse uses.
func _click(world_position: Vector3) -> bool:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return false
	_navigator.click_at_screen_position(camera.unproject_position(world_position))
	return _navigator.was_last_click_accepted()


## A screen position whose click would land on walkable floor between these distances,
## with a route to it. Scanned rather than guessed: the camera is fixed and the room is
## not symmetrical.
func _reachable_ground_screen(min_distance: float, max_distance: float) -> Variant:
	var rect := _player.get_viewport().get_visible_rect().size
	var map := _player.navigation_agent.get_navigation_map()
	for x_step in 14:
		for y_step in 10:
			var screen := Vector2(
				rect.x * (0.1 + 0.8 * float(x_step) / 13.0),
				rect.y * (0.2 + 0.6 * float(y_step) / 9.0)
			)
			var point: Variant = _navigator.get_ground_point_at(screen)
			if point == null:
				continue
			var world: Vector3 = point
			var distance := _flat_distance(_player.global_position, world)
			if distance < min_distance or distance > max_distance:
				continue
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			if NavigationServer3D.map_get_path(map, _player.global_position, world, true).size() < 2:
				continue
			return screen
	return null


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _count(names: Array[StringName], wanted: StringName) -> int:
	var total := 0
	for name: StringName in names:
		if name == wanted:
			total += 1
	return total


func _clear_events() -> void:
	_activated.clear()
	_approaches_started.clear()
	_approaches_activated.clear()
	_approaches_abandoned.clear()


func _on_activation(interactable: Interactable) -> void:
	_activated.append(interactable.interact_id)


func _on_approach_started(interactable: Interactable) -> void:
	_approaches_started.append(interactable.interact_id)


func _on_approach_activated(interactable: Interactable) -> void:
	_approaches_activated.append(interactable.interact_id)


func _on_approach_abandoned(interactable: Interactable) -> void:
	_approaches_abandoned.append(
		String(interactable.interact_id) if is_instance_valid(interactable) else &"<gone>"
	)


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
		if Time.get_ticks_msec() - started > int(TIMEOUT_SECONDS * 1000.0):
			_failures.append("A conversation would not close.")
			return


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
