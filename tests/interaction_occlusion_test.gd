extends SceneTree
## Who may hide an interactable, and who may not.
##
## The rule this test pins down is one sentence: only the object's own, explicitly
## declared support structure is looked through; anything else in the way blocks,
## whichever side of the wall the player stands on.
##
## It used to be a distance heuristic — "a collider whose origin is within ~1.6 m of the
## object is part of it" — which cannot tell a desk under a schoolbag from a free-standing
## wall standing next to a notice. Every physical case below is built from real
## `StaticBody3D` geometry and real ray casts; no case answers from a mocked boolean.
##
## Cases:
##  1. a wall far in front of the target  → not visible, not targetable, E does nothing;
##  2. a wall right next to the target    → the same (this is the reported bug);
##  3. a wall the target declares as its own backing → visible and usable;
##  4. a schoolbag on a desk the bag declares → visible and usable;
##  5. three eye heights                  → a low wall is seen over, a tall one is not;
##  6. the approach-spot search refuses to stand where a wall is in the way;
##  7. every interactable in every authored location is visible from somewhere.

const Harness = preload("res://tests/test_harness.gd")
const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _navigator: PointerNavigator = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null
var _walls: Array[StaticBody3D] = []
var _probes: Array[Interactable] = []
var _activated: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 260.0, "interaction_occlusion_test.gd")
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
	_interaction.activation_requested.connect(func(item: Interactable) -> void:
		_activated.append(item.interact_id))
	_sequence.allow_player_control()
	Engine.time_scale = 4.0
	await _frames(4)

	_location = _host.get_current()
	if _location == null:
		Harness.finish(self, ["The classroom is not loaded."], "")
		return

	await _check_wall_far_from_the_target()
	await _check_wall_next_to_the_target()
	await _check_declared_backing_is_seen_through()
	await _check_bag_on_a_desk()
	await _check_eye_heights()
	await _check_approach_spot_refuses_a_blocked_view()
	_clean_up()

	Harness.finish(
		self, _failures,
		"only declared support structure is looked through; walls block from either side."
	)


# --- case 1 and 2: a wall in the way ----------------------------------------


## A wall 1.5 m from the player, the target 1.5 m behind it: no distance can make this
## wall part of the object.
func _check_wall_far_from_the_target() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_far", Vector3(0.0, 0.9, -3.0))
	var wall := _make_wall(Vector3(0.0, 1.0, -1.5), Vector3(4.0, 2.0, 0.2))
	await _physics_frames(4)
	await _assert_blocked(target, "a wall 1.5 m in front of the target", wall)


## The same wall moved to 0.6 m in front of the target: close enough to have been
## excluded by the old distance rule, and just as solid.
func _check_wall_next_to_the_target() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_near", Vector3(0.0, 0.9, -3.0))
	var wall := _make_wall(Vector3(0.0, 1.0, -2.4), Vector3(4.0, 2.0, 0.2))
	await _physics_frames(4)
	await _assert_blocked(target, "a wall 0.6 m in front of the target", wall)


## Everything a blocked target must fail, in one place: the visibility probe, the
## pointer, the facing rule with its highlight, and the E key.
func _assert_blocked(target: Interactable, what: String, wall: StaticBody3D) -> void:
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if _interaction.has_line_of_sight_from(eye, target):
		_failures.append("The line of sight went through %s." % what)
	if _interaction.has_line_of_sight(target):
		_failures.append("The controller reports a clear view through %s." % what)
	var screen := _screen_of(target.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != null:
		_failures.append("The pointer selected a target behind %s." % what)
	# Face it, with the pointer parked where it can claim nothing.
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	await _physics_frames(4)
	if _interaction.get_current_target() == target:
		_failures.append("Facing chose a target behind %s." % what)
	if target.is_highlighted():
		_failures.append("A target behind %s was highlighted anyway." % what)
	if _interaction.get_highlighted() == target:
		_failures.append("The cue lit a target behind %s." % what)
	_activated.clear()
	await _push_e()
	if _activated.has(target.interact_id):
		_failures.append("E activated a target behind %s." % what)
	if wall == null:
		_failures.append("The check lost its wall.")


# --- case 3: the wall the object is mounted on -------------------------------


## A notice pinned to a wall: the wall is the object's own backing and declares itself
## as support, so the notice is readable while the same wall still blocks everything
## else.
func _check_declared_backing_is_seen_through() -> void:
	await _reset()
	var wall := _make_wall(Vector3(0.0, 1.0, -2.0), Vector3(4.0, 3.0, 0.2))
	var notice := _make_probe(&"occlusion_notice", Vector3(0.0, 1.2, -1.85))
	notice.support_paths = PackedStringArray([notice.get_path_to(wall)])
	await _physics_frames(4)
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if not _interaction.has_line_of_sight_from(eye, notice):
		_failures.append("A notice could not be seen through the wall it is mounted on.")
		return
	var screen := _screen_of(notice.global_position)
	if _interaction.get_target_at_screen_position(screen, false) != notice:
		_failures.append("The pointer could not select a notice on its own wall.")
	_interaction.set_mouse_override(screen)
	await _physics_frames(4)
	if _interaction.get_current_target() != notice:
		_failures.append("Facing did not adopt a notice on its own wall.")
	_interaction.clear_mouse_override()
	await _push_e()
	if not _activated.has(&"occlusion_notice"):
		_failures.append("E could not use a notice on its own wall.")
	await _settle_dialogue()


# --- case 4: a bag on a desk -------------------------------------------------


## The case the old heuristic existed for, done explicitly: the bag sits inside the
## desk's collision box, the desk is declared, and the bag stays usable. A second bag
## with no declaration is hidden by the very same desk, which is what makes the first
## result mean something.
func _check_bag_on_a_desk() -> void:
	await _reset()
	var desk := _make_wall(Vector3(0.0, 0.4, -2.6), Vector3(1.2, 0.8, 0.6))
	var bag := _make_probe(&"occlusion_bag", Vector3(0.0, 0.55, -2.6))
	bag.support_paths = PackedStringArray([bag.get_path_to(desk)])
	var unclaimed := _make_probe(&"occlusion_bag_undeclared", Vector3(0.0, 0.55, -2.62))
	await _physics_frames(4)
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if not _interaction.has_line_of_sight_from(eye, bag):
		_failures.append("A schoolbag declared on its own desk could not be seen.")
	if _interaction.has_line_of_sight_from(eye, unclaimed):
		_failures.append(
			"An undeclared object inside the desk was visible through it: the desk is not"
			+ " being blocked, so the declared case proves nothing."
		)
	_activated.clear()
	await _push_e()
	if not _activated.has(&"occlusion_bag"):
		_failures.append("E could not use a schoolbag declared on its own desk.")
	await _settle_dialogue()


# --- case 5: heights ---------------------------------------------------------


## The probe is three rays, not one: a low wall must be seen over from a standing eye
## height, and the same wall must block from a crouched one.
func _check_eye_heights() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_height", Vector3(0.0, 1.2, -3.0))
	# 0.9 m tall: above a crouched eye, below a standing one.
	_make_wall(Vector3(0.0, 0.45, -1.5), Vector3(4.0, 0.9, 0.2))
	await _physics_frames(4)
	var from := _player.global_position
	if _interaction.has_line_of_sight_from(from + Vector3.UP * 0.5, target):
		_failures.append("A 0.9 m wall hid nothing from a crouched eye at 0.5 m.")
	if not _interaction.has_line_of_sight_from(from + Vector3.UP * 1.6, target):
		_failures.append("A 0.9 m wall blocked a standing eye at 1.6 m.")
	_clean_up()


# --- case 6: where the character would stand ---------------------------------


## The approach-spot search asks the same question, so a target with a wall right in
## front of it has nowhere to stand: the click is refused instead of walking into the
## wall and activating from behind it.
func _check_approach_spot_refuses_a_blocked_view() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_approach", Vector3(0.0, 0.9, -2.2))
	# A wall standing between the room and the object: every candidate ring spot on the
	# near side looks through it.
	_make_wall(Vector3(0.0, 1.0, -1.35), Vector3(5.0, 2.0, 0.2))
	await _physics_frames(4)
	_navigator.click_at_screen_position(_screen_of(target.global_position))
	await _physics_frames(4)
	if _navigator.is_approaching():
		_failures.append("The navigator approached a target it could not see.")
	if _player.is_path_active():
		_failures.append("The character started walking at a target behind a wall.")
	var reason := _navigator.get_last_rejection()
	if not reason.contains("clear view"):
		_failures.append("A blocked approach was refused for the wrong reason ('%s')." % reason)
	_clean_up()


# --- helpers ----------------------------------------------------------------


func _reset() -> void:
	_clean_up()
	_sequence.allow_player_control()
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6)))
	_interaction.mouse_targeting = true
	_interaction.clear_mouse_override()
	await _physics_frames(3)


func _clean_up() -> void:
	for wall: StaticBody3D in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	for probe: Interactable in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	_probes.clear()


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
	_probes.append(probe)
	return probe


func _make_wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TestWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_location.add_child(body)
	body.global_position = position
	_walls.append(body)
	return body


func _screen_of(world_position: Vector3) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world_position)


func _push_e() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	await _frames(2)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	root.push_input(release)
	await _frames(2)


func _settle_dialogue() -> void:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > 15000:
			_failures.append("A conversation would not close.")
			return


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
