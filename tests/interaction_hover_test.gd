extends SceneTree
## Pointer targeting, the hover cue, and the promise that E uses what the cue
## shows.
##
## Two ways of choosing a target now exist, so the interesting question is not
## "does the mouse work" but "what wins, and does the highlight agree". The rules
## this test pins down:
##
## 1. the pointer wins over facing when it is over something in reach;
## 2. when the pointer is over nothing, facing decides, immediately;
## 3. a pointer pick that would replace a different target must hold still for a
##    frame first, which is what stops the prompt blinking at a prop's edge;
## 4. exactly one interactable is highlighted at any time, and it is the one
##    `get_current_target()` returns;
## 5. activating that target reports the same object — the cue cannot show one
##    thing and the key use another.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 4.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _dialogue: DialogueController = null
var _activated: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "interaction_hover_test.gd")
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
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _host == null or _player == null or _interaction == null or _dialogue == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_interaction.activation_requested.connect(_on_activation)
	Engine.time_scale = TIME_SCALE
	await _frames(4)

	var location := _host.get_current()
	if location == null:
		Harness.finish(self, ["The classroom is not loaded."], "")
		return

	await _check_pointer_beats_facing(location)
	await _check_pointer_leaves_and_facing_returns(location)
	await _check_activation_matches_the_cue(location)
	await _check_out_of_reach_is_not_a_target(location)
	await _check_flicker_hold(location)

	Harness.finish(
		self, _failures,
		"the pointer, the facing fallback, the cue, and E all name the same object."
	)


# --- cases ------------------------------------------------------------------


func _check_pointer_beats_facing(location: LocationRoot) -> void:
	# Face the desk, then point at the schoolbag on the other side of the player.
	var facing := await _face(&"own_desk", Vector3(0.0, 0.0, 1.2), 0.0)
	if facing == null:
		return
	var bag := location.find_interactable(&"schoolbag")
	if bag == null:
		_failures.append("The classroom has no schoolbag to point at.")
		return
	_interaction.set_mouse_override(_screen_position_of(bag))
	await _physics_frames(4)
	var target := _interaction.get_current_target()
	if target != bag:
		_failures.append(
			"With the pointer on the schoolbag the target was '%s', not the bag."
			% _name_of(target)
		)
		return
	var highlighted := _interaction.get_highlighted()
	if highlighted != bag:
		_failures.append("The highlighted object is not the pointer's target.")
	if not bag.is_highlighted():
		_failures.append("The pointer's target did not light up.")
	if facing.is_highlighted():
		_failures.append("The object the player faces stayed lit while the pointer was elsewhere.")
	if _count_highlighted(location) != 1:
		_failures.append("%d objects are highlighted at once." % _count_highlighted(location))


func _check_pointer_leaves_and_facing_returns(location: LocationRoot) -> void:
	var desk := location.find_interactable(&"own_desk")
	if desk == null:
		return
	await _face(&"own_desk", Vector3(0.0, 0.0, 1.2), 0.0)
	# A corner of the screen with nothing in it: the pointer releases its claim at
	# once, and facing decides again without a second frame of hesitation.
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	await _physics_frames(3)
	var target := _interaction.get_current_target()
	if target != desk:
		_failures.append(
			"With the pointer off everything, facing did not decide again (got '%s')."
			% _name_of(target)
		)
	if _count_highlighted(location) != 1:
		_failures.append("After releasing the pointer, %d objects are lit." % _count_highlighted(location))
	_interaction.clear_mouse_override()


func _check_activation_matches_the_cue(location: LocationRoot) -> void:
	var bag := location.find_interactable(&"schoolbag")
	if bag == null:
		return
	await _face(&"own_desk", Vector3(0.0, 0.0, 1.2), 0.0)
	_interaction.set_mouse_override(_screen_position_of(bag))
	await _physics_frames(4)
	var target := _interaction.get_current_target()
	var highlighted := _interaction.get_highlighted()
	if target == null:
		_failures.append("There was nothing to activate in the pointer test.")
		return
	_activated.clear()
	_interaction.request_activation(target)
	await _frames(1)
	if _activated.is_empty():
		_failures.append("Activating the current target emitted nothing.")
		return
	if _activated[0] != target.interact_id:
		_failures.append("E activated '%s' while the cue showed '%s'." % [
			String(_activated[0]), String(target.interact_id)
		])
	if highlighted != target:
		_failures.append("Activation used a different object than the highlighted one.")
	_interaction.clear_mouse_override()
	await _settle(20.0)


func _check_out_of_reach_is_not_a_target(location: LocationRoot) -> void:
	# The pointer must obey the same reach limit as facing. Stand at the far end of
	# the room and point at the blackboard.
	var board := location.find_interactable(&"blackboard")
	if board == null:
		return
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 1.6)))
	await _physics_frames(3)
	var hit := _interaction.get_target_at_screen_position(_screen_position_of(board))
	if hit != null and hit.global_position.distance_to(_player.global_position) > _interaction.max_distance:
		_failures.append("The pointer selected an object beyond the interaction range.")


## A pointer pick that would replace a different target is held for one frame. The
## test asserts both halves: not adopted immediately, adopted after the hold.
func _check_flicker_hold(location: LocationRoot) -> void:
	var bag := location.find_interactable(&"schoolbag")
	var desk := location.find_interactable(&"own_desk")
	if bag == null or desk == null:
		return
	await _face(&"own_desk", Vector3(0.0, 0.0, 1.2), 0.0)
	if _interaction.get_current_target() != desk:
		_failures.append("The flicker test did not start from the desk.")
		return
	_interaction.set_mouse_override(_screen_position_of(bag))
	# One physics frame: still the desk, because a new pointer pick has to hold.
	await _physics_frames(1)
	if _interaction.get_current_target() != desk:
		_failures.append("A pointer pick was adopted without its one-frame hold.")
	await _physics_frames(3)
	if _interaction.get_current_target() != bag:
		_failures.append("A pointer pick was never adopted after its hold.")
	_interaction.clear_mouse_override()


# --- helpers ----------------------------------------------------------------


func _face(expected_id: StringName, position: Vector3, yaw_degrees: float) -> Interactable:
	_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position))
	await _physics_frames(4)
	var target := _interaction.get_current_target()
	if target == null or target.interact_id != expected_id:
		_failures.append("Standing at %s facing %s targeted '%s' instead of '%s'." % [
			position, yaw_degrees, _name_of(target), String(expected_id)
		])
		return null
	return target


func _screen_position_of(interactable: Interactable) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		_failures.append("There is no current camera to project through.")
		return Vector2.ZERO
	return camera.unproject_position(interactable.global_position)


func _count_highlighted(location: LocationRoot) -> int:
	var count := 0
	for interactable: Interactable in location.get_interactables():
		if interactable.is_highlighted():
			count += 1
	return count


func _name_of(interactable: Interactable) -> String:
	return String(interactable.interact_id) if interactable != null else "<nothing>"


func _on_activation(interactable: Interactable) -> void:
	_activated.append(interactable.interact_id)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _settle(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			return false
	return true
