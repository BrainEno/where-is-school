extends SceneTree
## Pointer targeting, the hover cue, and the promise that E uses what the cue shows.
##
## Two ways of choosing a target now exist, so the interesting question is not "does
## the pointer work" but "what wins, and does the highlight agree". The rules this
## test pins down:
##
## 1. the pointer wins over facing when it is over something in reach;
## 2. when the pointer is over nothing, facing decides again immediately;
## 3. a pointer pick that would replace a different target must hold still for a
##    frame first, which is what stops the prompt blinking at a prop's edge;
## 4. exactly one interactable is highlighted, and it is the one
##    `get_current_target()` returns;
## 5. activating that target reports the same object — the cue cannot show one thing
##    and the key use another;
## 6. the pointer obeys the same reach limit as facing.
##
## Most of the geometry is done with two probe interactables built in code and placed
## at known offsets from the player, because a room's real props are wherever the
## level designer put them and screen-space assertions against them are guesses. One
## case uses real classroom props, so the rule is also checked against content.

const Harness = preload("res://tests/test_harness.gd")

const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"
const TIMEOUT_SECONDS := 6.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null
var _activated: Array[StringName] = []
var _probe_front: Interactable = null
var _probe_side: Interactable = null
var _probe_far: Interactable = null
var _facing_target: Interactable = null


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
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _host == null or _player == null or _interaction == null or _dialogue == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_interaction.activation_requested.connect(_on_activation)
	if _sequence != null:
		# No authored beats run in this test, so control is handed over by hand.
		_sequence.allow_player_control()
	Engine.time_scale = 4.0
	await _frames(4)

	_location = _host.get_current()
	if _location == null:
		Harness.finish(self, ["The classroom is not loaded."], "")
		return

	await _place_probes()
	await _check_facing_without_a_pointer()
	await _check_pointer_beats_facing()
	await _check_pointer_leaves_and_facing_returns()
	await _check_flicker_hold()
	await _check_activation_matches_the_cue()
	await _check_out_of_reach_is_not_a_target()
	await _check_real_prop()
	_free_probes()

	Harness.finish(
		self, _failures,
		"the pointer, the facing fallback, the cue, and E all name the same object."
	)


# --- setup ------------------------------------------------------------------


## Three probes at known offsets: one straight ahead, one to the right, one out of
## reach. They use a real inspection id only so that activating them is a legal
## request; this test never reads what they say.
func _place_probes() -> void:
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6)))
	await _physics_frames(2)
	var origin := _player.global_position
	_probe_front = _make_probe(&"test_probe_front", origin + Vector3(0.0, 0.9, -1.2))
	_probe_side = _make_probe(&"test_probe_side", origin + Vector3(1.2, 0.9, 0.1))
	_probe_far = _make_probe(&"test_probe_far", origin + Vector3(3.6, 0.9, -3.8))
	await _physics_frames(4)


func _make_probe(interact_id: StringName, position: Vector3) -> Interactable:
	var packed: PackedScene = load(PROBE_SCENE)
	var probe := packed.instantiate() as Interactable
	probe.name = String(interact_id)
	probe.interact_id = interact_id
	probe.prompt_text = "Probe"
	probe.inspection_id = &"classroom_own_desk"
	probe.radius = 0.6
	_location.add_child(probe)
	probe.global_position = position
	return probe


func _free_probes() -> void:
	for probe: Interactable in [_probe_front, _probe_side, _probe_far]:
		if probe != null and is_instance_valid(probe):
			probe.queue_free()


# --- cases ------------------------------------------------------------------


## With the pointer out of the picture, the old rule still decides. This test does
## not try to predict which prop the room offers — it records what facing chose, and
## every later assertion is relative to that. Predicting it would be a guess about
## the level layout, not a statement about the rule.
func _check_facing_without_a_pointer() -> void:
	_interaction.mouse_targeting = false
	await _physics_frames(4)
	_facing_target = _interaction.get_current_target()
	if _facing_target == null:
		_failures.append("Facing alone chose nothing in an occupied room.")
		return
	if _interaction.get_highlighted() != _facing_target:
		_failures.append("The facing target is not the highlighted object.")
	if _facing_target == _probe_side:
		_failures.append("The side probe was chosen by facing; the test cannot tell the two rules apart.")
	_interaction.mouse_targeting = true
	await _physics_frames(2)


func _check_pointer_beats_facing() -> void:
	_interaction.set_mouse_override(_screen_position_of(_probe_side))
	await _physics_frames(4)
	var target := _interaction.get_current_target()
	if target != _probe_side:
		_failures.append(
			"With the pointer on the side probe the target was '%s', not the probe." % _name_of(target)
		)
		return
	if _interaction.get_highlighted() != _probe_side:
		_failures.append("The highlighted object is not the pointer's target.")
	if not _probe_side.is_highlighted():
		_failures.append("The pointer's target did not light up.")
	if _probe_front.is_highlighted():
		_failures.append("The object the player faces stayed lit while the pointer was elsewhere.")
	if _count_highlighted() != 1:
		_failures.append("%d objects are highlighted at once." % _count_highlighted())


func _check_pointer_leaves_and_facing_returns() -> void:
	# A corner of the screen with nothing in it: the pointer releases its claim at
	# once, and facing decides again without another frame of hesitation.
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	await _physics_frames(3)
	var target := _interaction.get_current_target()
	if target != _facing_target:
		_failures.append("With the pointer off everything, facing did not decide (got '%s')." % _name_of(target))
	if _count_highlighted() != 1:
		_failures.append("After releasing the pointer, %d objects are lit." % _count_highlighted())


## A pointer pick that would replace a different target is held for one frame. Both
## halves matter: not adopted immediately, adopted once the hold is over.
func _check_flicker_hold() -> void:
	if _interaction.get_current_target() != _facing_target:
		_failures.append("The flicker check did not start from the facing target.")
		return
	_interaction.set_mouse_override(_screen_position_of(_probe_side))
	await _physics_frames(1)
	if _interaction.get_current_target() != _facing_target:
		_failures.append("A pointer pick was adopted without its one-frame hold.")
	await _physics_frames(3)
	if _interaction.get_current_target() != _probe_side:
		_failures.append("A pointer pick was never adopted after its hold.")


func _check_activation_matches_the_cue() -> void:
	var target := _interaction.get_current_target()
	var highlighted := _interaction.get_highlighted()
	if target == null:
		_failures.append("There was nothing to activate in the pointer check.")
		return
	_activated.clear()
	_interaction.request_activation(target)
	await _frames(2)
	if _activated.is_empty():
		_failures.append("Activating the current target emitted nothing.")
	elif _activated[0] != target.interact_id:
		_failures.append("E activated '%s' while the cue showed '%s'." % [
			String(_activated[0]), String(target.interact_id)
		])
	if highlighted != target:
		_failures.append("Activation used a different object than the highlighted one.")
	await _settle()


func _check_out_of_reach_is_not_a_target() -> void:
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	await _physics_frames(3)
	var hit := _interaction.get_target_at_screen_position(_screen_position_of(_probe_far))
	if hit == _probe_far:
		_failures.append("The pointer selected a probe %.1f m away, beyond the reach limit." % _probe_far.global_position.distance_to(_player.global_position))


## The same rule against real content: face the actual classroom door from within reach,
## then move to the timetable's south-wall viewpoint and point at the paper. The room grew
## around the original test coordinates, so the door and sheet are now checked from their
## authored locations rather than from the old, out-of-reach door position.
func _check_real_prop() -> void:
	var mouse_targeting := _interaction.mouse_targeting
	_interaction.mouse_targeting = false
	var door := _location.find_interactable(&"classroom_door")
	var sheet := _location.find_interactable(&"timetable")
	if door == null or sheet == null:
		_failures.append("The classroom lost the door or the timetable.")
		_interaction.mouse_targeting = mouse_targeting
		return
	_player.teleport(
		Transform3D(Basis(Vector3.UP, deg_to_rad(0.01)), Vector3(3.0, 0, -3.0))
	)
	await _physics_frames(4)
	if _interaction.get_current_target() != door:
		_failures.append(
			"Facing the door did not target it (got '%s'; player at %s, door seen by the camera: %s)."
			% [
				_name_of(_interaction.get_current_target()), str(_player.global_position),
				str(_interaction.is_seen_by_camera(door))
			]
		)
		_interaction.mouse_targeting = mouse_targeting
		return
	_interaction.mouse_targeting = mouse_targeting
	# The south wall is closest to the camera's diagonal view from this side of the sheet;
	# the facing ray fades it while the player's eye and the cursor both look at the paper.
	var sheet_spot := Vector3(1.6, 0, 4.0)
	var to_sheet := sheet.global_position - sheet_spot
	var sheet_yaw := atan2(-to_sheet.x, -to_sheet.z)
	_player.teleport(Transform3D(Basis(Vector3.UP, sheet_yaw), sheet_spot))
	await _physics_frames(8)
	_interaction.set_mouse_override(_screen_position_of_drawn(sheet))
	await _physics_frames(4)
	var target := _interaction.get_current_target()
	if target != sheet:
		_failures.append("Pointing at the timetable did not target it (got '%s')." % _name_of(target))
	if _count_highlighted() != 1:
		_failures.append("With a real prop under the pointer, %d objects are lit." % _count_highlighted())
	_interaction.clear_mouse_override()


# --- helpers ----------------------------------------------------------------


func _screen_position_of(interactable: Interactable) -> Vector2:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		_failures.append("There is no current camera to project through.")
		return Vector2.ZERO
	return camera.unproject_position(interactable.global_position)


## The middle of what the object's outline traces, on screen: where a player points.
func _screen_position_of_drawn(interactable: Interactable) -> Vector2:
	var meshes := interactable.get_outline_meshes()
	if meshes.is_empty():
		return _screen_position_of(interactable)
	var bounds := meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes:
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		_failures.append("There is no current camera to project through.")
		return Vector2.ZERO
	return camera.unproject_position(bounds.get_center())


func _count_highlighted() -> int:
	var count := 0
	for interactable: Interactable in _location.get_interactables():
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


func _settle() -> void:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(TIMEOUT_SECONDS * 1000.0):
			return
