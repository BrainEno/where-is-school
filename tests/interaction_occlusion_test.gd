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
##  7. the camera's view (issue #115): a drawn canopy the player's eye sees under, but the
##     camera cannot see past, hides the object from the pointer - declared or not - and the
##     same canopy made see-through (faded) does not;
##  8. a partly covered object is pointable on its uncovered part only, the same answer
##     every time it is asked;
##  9. a target that is freed or switched off leaves no target and no highlight behind;
## 10. the real classroom's timetable sheet from four viewpoints - where the #111 capture
##     stood (camera outside the opaque south wall), a spot where the wall is faded, behind
##     the wall, and a sweep across the edge where the wall's fade switches - then switched
##     off and left behind by a scene swap.
##
## "Every interactable in every authored location is visible from somewhere" is
## `tests/interaction_visibility_sweep_test.gd`.
##
## These are physics and script checks: a headless run draws nothing. Where a case says
## "drawn" or "hidden" it means the body the camera ray meets has a visible mesh with no
## transparency - the condition under which the outline mask's depth pass hides what is
## behind it - not that a frame was looked at.

const Harness = preload("res://tests/test_harness.gd")
const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"
## Where the #111 capture stood in the classroom (case 10a); see `_check_classroom_timetable`.
const SHEET_SPOT_111 := Vector3(3.10, 0.0, 3.04)
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"

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
var _silenced: Array[Interactable] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 290.0, "interaction_occlusion_test.gd")
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
	# The room's own props stand exactly where these cases build their geometry, and the
	# pointer answers with the nearest area: the player's desk would take every click
	# before the probe behind it was ever asked. The synthetic cases get the room to
	# themselves, so a miss means the rule and not the furniture.
	_silence_authored(true)

	await _check_wall_far_from_the_target()
	await _check_wall_next_to_the_target()
	await _check_declared_backing_is_seen_through()
	await _check_bag_on_a_desk()
	await _check_eye_heights()
	await _check_approach_spot_refuses_a_blocked_view()
	await _check_canopy_hides_from_the_camera()
	await _check_partial_cover_is_per_pixel()
	await _check_dropped_targets_leave_nothing()
	_clean_up()
	# The real room from here on: its own props answer the pointer again.
	_silence_authored(false)
	await _physics_frames(2)
	await _check_classroom_timetable()

	Harness.finish(
		self, _failures,
		"only declared support structure is looked through; walls block from either side; "
		+ "the pointer picks only where the camera sees the object drawn (#115)."
	)


# --- case 1 and 2: a wall in the way ----------------------------------------


## A wall 1.5 m from the player, the target 1.5 m behind it: no distance can make this
## wall part of the object.
func _check_wall_far_from_the_target() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_far", Vector3(0.0, 0.9, -1.6))
	var wall := _make_wall(Vector3(0.0, 1.2, -0.6), Vector3(4.0, 2.4, 0.2))
	await _physics_frames(4)
	await _assert_blocked(target, "a wall 1.0 m in front of the target", wall)


## The same wall moved to 0.6 m in front of the target: close enough to have been
## excluded by the old distance rule, and just as solid.
func _check_wall_next_to_the_target() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_near", Vector3(0.0, 0.9, -1.7))
	var wall := _make_wall(Vector3(0.0, 1.2, -1.1), Vector3(4.0, 2.4, 0.2))
	await _physics_frames(4)
	await _assert_blocked(target, "a wall 0.6 m in front of the target, well inside the old 1.6 m rule", wall)


## Everything a blocked target must fail, in one place: the visibility probe, the
## pointer, the facing rule with its highlight, and the E key.
func _assert_blocked(target: Interactable, what: String, wall: StaticBody3D) -> void:
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if _interaction.has_line_of_sight_from(eye, target):
		_failures.append("The line of sight went through %s." % what)
	if _interaction.has_line_of_sight(target):
		_failures.append("The controller reports a clear view through %s." % what)
	if _find_target_on_screen(target) != Vector2.ZERO:
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


## A notice on a wall: the part of the wall it is fixed to is the object's own backing
## and declares itself as support, so the notice is readable through it. The same notice
## with nothing declared, in the same place, is hidden by the very same wall — which is
## what makes the first result mean something.
func _check_declared_backing_is_seen_through() -> void:
	await _reset()
	var wall := _make_wall(Vector3(0.0, 1.2, -0.6), Vector3(4.0, 2.4, 0.2))
	var notice := _make_probe(&"occlusion_notice", Vector3(0.0, 1.2, -0.62), 0.5)
	notice.support_paths = PackedStringArray([notice.get_path_to(wall)])
	await _physics_frames(4)
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if not _interaction.has_line_of_sight_from(eye, notice):
		_failures.append("A notice could not be seen through the wall it is mounted on. %s" % _explain(notice))
	var screen := _find_target_on_screen(notice)
	if screen == Vector2.ZERO:
		_failures.append("The pointer never found the notice on screen. %s" % _explain(notice))
	_interaction.set_mouse_override(screen)
	await _physics_frames(4)
	if _interaction.get_current_target() != notice:
		_failures.append(
			"The pointer did not adopt a notice on its own wall (target: %s). %s"
			% [_name_of(_interaction.get_current_target()), _explain(notice)]
		)
	_interaction.clear_mouse_override()
	_activated.clear()
	await _push_e()
	if not _activated.has(&"occlusion_notice"):
		_failures.append("E could not use a notice on its own wall. %s" % _explain(notice))
	await _settle_dialogue()

	# The same notice, the same wall, nothing declared.
	await _free_probe(notice)
	var plain := _make_probe(&"occlusion_notice_undeclared", Vector3(0.0, 1.2, -0.62), 0.5)
	await _physics_frames(4)
	if _interaction.has_line_of_sight_from(eye, plain):
		_failures.append(
			"An undeclared notice was visible through the wall it stands on, so the"
			+ " declared case proves nothing. %s" % _explain(plain)
		)
	_activated.clear()
	await _push_e()
	if _activated.has(&"occlusion_notice_undeclared"):
		_failures.append("E used an undeclared notice through a wall.")


# --- case 4: a bag behind the desk it sits on --------------------------------


## The case the old heuristic existed for, done explicitly. The cupboard stands between
## the player and the schoolbag, so every probe crosses it: the bag that declares the
## cupboard is usable, and the same bag with nothing declared is not.
func _check_bag_on_a_desk() -> void:
	await _reset()
	var desk := _make_wall(Vector3(0.0, 0.7, -1.0), Vector3(1.2, 1.4, 0.6))
	var bag := _make_probe(&"occlusion_bag", Vector3(0.0, 0.55, -1.0), 0.5)
	bag.support_paths = PackedStringArray([bag.get_path_to(desk)])
	await _physics_frames(4)
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if not _interaction.has_line_of_sight_from(eye, bag):
		_failures.append("A schoolbag declared on its own desk could not be seen. %s" % _explain(bag))
	var screen := _find_target_on_screen(bag)
	if screen == Vector2.ZERO:
		_failures.append("The pointer never found the bag on its desk. %s" % _explain(bag))
	_interaction.set_mouse_override(screen)
	await _physics_frames(4)
	if _interaction.get_current_target() != bag:
		_failures.append(
			"The pointer did not adopt a bag sitting on its own desk (target: %s). %s"
			% [_name_of(_interaction.get_current_target()), _explain(bag)]
		)
	_interaction.clear_mouse_override()
	_activated.clear()
	await _push_e()
	if not _activated.has(&"occlusion_bag"):
		_failures.append("E could not use a schoolbag declared on its own desk. %s" % _explain(bag))
	await _settle_dialogue()

	await _free_probe(bag)
	var plain := _make_probe(&"occlusion_bag_undeclared", Vector3(0.0, 0.55, -1.0), 0.5)
	await _physics_frames(4)
	if _interaction.has_line_of_sight_from(eye, plain):
		_failures.append(
			"An undeclared object inside the desk was visible through it: the desk is not"
			+ " blocking, so the declared case proves nothing. %s" % _explain(plain)
		)
	_activated.clear()
	await _push_e()
	if _activated.has(&"occlusion_bag_undeclared"):
		_failures.append("E used an undeclared object through the desk it sits on.")


# --- case 5: heights ---------------------------------------------------------


## The probe is three rays, not one: a low wall must be seen over from a standing eye
## height, and the same wall must block from a crouched one.
func _check_eye_heights() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_height", Vector3(0.0, 1.2, -1.6))
	# 0.9 m tall: above a crouched eye, below a standing one.
	_make_wall(Vector3(0.0, 0.45, -0.6), Vector3(4.0, 0.9, 0.2))
	await _physics_frames(4)
	var from := _player.global_position
	if _interaction.has_line_of_sight_from(from + Vector3.UP * 0.5, target):
		_failures.append("A 0.9 m wall hid nothing from a crouched eye at 0.5 m.")
	if not _interaction.has_line_of_sight_from(from + Vector3.UP * 1.6, target):
		_failures.append("A 0.9 m wall blocked a standing eye at 1.6 m.")
	_clean_up()


# --- case 6: where the character would stand ---------------------------------


## The approach-spot search asks the same question. A wall between the room and the
## object means there is no standing position that can see it, so a click neither walks
## nor activates, and says why.
func _check_approach_spot_refuses_a_blocked_view() -> void:
	await _reset()
	var target := _make_probe(&"occlusion_approach", Vector3(0.0, 0.9, -1.2))
	_make_wall(Vector3(0.0, 1.2, -0.4), Vector3(5.0, 2.4, 0.2))
	await _physics_frames(4)
	# Every spot the approach search would try is behind the wall.
	var seen_from_a_spot := false
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var spot := target.global_position + Vector3(cos(angle) * 1.0, 0.0, sin(angle) * 1.0)
		if _interaction.has_line_of_sight_from(spot + Vector3.UP * _interaction.eye_height, target) \
				and spot.z > -0.4:
			# A spot on the room side of the wall that can see the object would make
			# this case meaningless.
			seen_from_a_spot = true
	if seen_from_a_spot:
		_failures.append("A standing spot on the room side could see the target through the wall.")
	_activated.clear()
	_navigator.click_at_screen_position(_screen_of(target.global_position))
	await _physics_frames(4)
	if _navigator.is_approaching():
		_failures.append("The navigator approached a target it could not see. %s" % _explain(target))
	if _player.is_path_active():
		_failures.append("The character started walking at a target behind a wall. %s" % _explain(target))
	if _navigator.get_last_rejection().is_empty():
		_failures.append("A click on a target behind a wall was refused without saying why.")
	await _push_e()
	if _activated.has(&"occlusion_approach"):
		_failures.append("E used a target behind a wall.")
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


func _free_probe(probe: Interactable) -> void:
	_probes.erase(probe)
	if is_instance_valid(probe):
		probe.queue_free()
	await _physics_frames(2)


## Takes the room's authored interactables out of the pointer's way (or puts them back).
## Collision only: nothing about the props themselves is changed, and the game never
## does this — it exists so a synthetic case is not decided by the classroom's furniture.
func _silence_authored(silence: bool) -> void:
	if silence:
		for node: Node in _location.find_children("*", "Area3D", true, false):
			var item := node as Interactable
			if item == null or _probes.has(item) or _silenced.has(item):
				continue
			item.collision_layer = 0
			_silenced.append(item)
		return
	for item: Interactable in _silenced:
		if is_instance_valid(item):
			item.collision_layer = Interactable.INTERACTION_LAYER
	_silenced.clear()


func _make_probe(interact_id: StringName, position: Vector3, radius: float = 0.7) -> Interactable:
	var packed: PackedScene = load(PROBE_SCENE)
	var probe := packed.instantiate() as Interactable
	probe.name = String(interact_id)
	probe.interact_id = interact_id
	probe.prompt_text = "Probe"
	probe.inspection_id = &"classroom_own_desk"
	probe.radius = radius
	_location.add_child(probe)
	probe.global_position = position
	_probes.append(probe)
	return probe


## A probe with something to draw: a box mesh under it, which its outline traces and its
## pick box is built around (`Interactable._build_pick_shapes`, deferred to the frame's end).
func _make_drawn_probe(interact_id: StringName, position: Vector3, size: Vector3) -> Interactable:
	var probe := _make_probe(interact_id, position, 0.7)
	var mesh := MeshInstance3D.new()
	mesh.name = "Drawn"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	probe.add_child(mesh)
	# Only the box is the object. With `outline_paths` empty the outline (and so the object,
	# for the camera) would fall back to whatever `support_paths` names.
	probe.outline_paths = PackedStringArray(["Drawn"])
	return probe


## `drawn` gives the wall a visible mesh of the same size, so the camera - and the outline
## mask - sees it as an opaque surface. Without it the wall is a collider only: it blocks
## the player's eye and hides nothing from the camera, which is what cases 1-6 are about.
func _make_wall(position: Vector3, size: Vector3, drawn: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TestWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if drawn:
		var mesh := MeshInstance3D.new()
		mesh.name = "MeshInstance3D"
		var visual := BoxMesh.new()
		visual.size = size
		mesh.mesh = visual
		body.add_child(mesh)
	_location.add_child(body)
	body.global_position = position
	_walls.append(body)
	return body


## Where on screen the pointer is over this object, by asking the same question the
## pointer asks. Scanned rather than projected: a projection is a guess about a camera
## transform, and this test should fail about the rule, not about the camera.
func _find_target_on_screen(target: Interactable) -> Vector2:
	var rect := _player.get_viewport().get_visible_rect().size
	for x_step in 20:
		for y_step in 14:
			var screen := Vector2(
				rect.x * (0.02 + 0.96 * float(x_step) / 19.0),
				rect.y * (0.02 + 0.96 * float(y_step) / 13.0)
			)
			if _interaction.get_target_at_screen_position(screen, false) == target:
				return screen
	return Vector2.ZERO


## Everything that would explain a visibility failure, in one line.
func _explain(target: Interactable) -> String:
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	return (
		"[%s at %s: sight=%s, pointer=%s, current=%s, highlight=%s, in_reach=%s,"
		+ " distance=%.2f, centre=%s]"
	) % [
		String(target.interact_id), str(target.global_position),
		str(_interaction.has_line_of_sight_from(eye, target)),
		str(_find_target_on_screen(target)),
		_name_of(_interaction.get_current_target()),
		_name_of(_interaction.get_highlighted()),
		str(_interaction.is_in_reach(target)),
		_flat_distance(_player.global_position, target.global_position),
		_what_the_centre_of_the_screen_hits(),
	]


## What is actually under the crosshair. When a probe cannot be found, this says whether
## the pointer missed everything or was answered by something standing in front.
func _what_the_centre_of_the_screen_hits() -> String:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return "<no camera>"
	var rect := _player.get_viewport().get_visible_rect().size
	var screen := rect * 0.5
	var from := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(screen) * 60.0, Interactable.INTERACTION_LAYER
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "<nothing>"
	var node: Node = hit.get("collider")
	if node == null:
		return "<no collider>"
	var item := node as Interactable
	if item == null:
		return node.name
	return "%s(usable=%s)" % [node.name, str(item.can_interact())]


# --- case 7: what the camera can see -----------------------------------------


## A canopy over the target: the player's eye looks under it, the fixed camera looks down
## through it. The eye-level rule is satisfied, so before #115 the pointer found the object
## through a surface that hides it from the camera - and from the depth-tested outline.
func _check_canopy_hides_from_the_camera() -> void:
	await _reset()
	var target := _make_drawn_probe(&"occlusion_canopy", Vector3(0.0, 0.9, -1.6), Vector3(0.4, 0.4, 0.4))
	var canopy := _make_wall(Vector3(0.6, 2.2, -0.9), Vector3(2.6, 0.1, 2.8), true)
	await _physics_frames(4)
	var eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if not _interaction.has_line_of_sight_from(eye, target):
		_failures.append("Case 7 setup: the canopy hid the target from the eye as well. %s" % _explain(target))
		return
	var centre := _box_centre(target)
	var blocker := _first_drawn_body(centre)
	if blocker != canopy:
		_failures.append(
			"Case 7 setup: the camera ray to the target meets '%s', not the canopy." % _node_name(blocker)
		)
		return
	var picked := _find_target_on_screen(target)
	print("[#115] canopy: eye sees the target, camera ray meets the canopy; pointer pick at %s" % str(picked))
	if picked != Vector2.ZERO:
		_failures.append(
			"The pointer selected a target the camera cannot see past a drawn canopy (at %s)." % str(picked)
		)
	# Facing it, in reach and in the eye's sight: the camera still cannot see it, so it
	# is not the target either - no prompt, no cue, no E for what has no outline.
	# Step up to it first: from the reset spot it is 2.2 m away, beyond the sensor's reach
	# of its anchor, and "not chosen" would prove nothing. The faded-canopy check at the end
	# of this case is the control: from here, once the camera can see it, it is chosen.
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	var here := Vector3(0.9, 0.0, -0.8)
	_player.teleport(Transform3D(_yaw_towards(here, target.global_position), here))
	await _physics_frames(4)
	var near_eye := _player.global_position + Vector3.UP * _interaction.eye_height
	if _first_drawn_body(centre) != canopy or not _interaction.has_line_of_sight_from(near_eye, target):
		_failures.append(
			"Case 7 setup: from the facing spot the camera ray meets '%s' (not the canopy?) or the eye lost it. %s"
			% [_node_name(_first_drawn_body(centre)), _explain(target)]
		)
		_interaction.clear_mouse_override()
		_clean_up()
		return
	print(
		"[#115] canopy, facing: current=%s highlight=%s seen_by_camera=%s"
		% [
			_name_of(_interaction.get_current_target()), _name_of(_interaction.get_highlighted()),
			str(_interaction.is_seen_by_camera(target))
		]
	)
	if _interaction.get_current_target() == target or target.is_highlighted():
		_failures.append("Facing chose a target the camera cannot see past a drawn canopy.")
	_activated.clear()
	await _push_e()
	if _activated.has(&"occlusion_canopy"):
		_failures.append("E used a target the camera cannot see past a drawn canopy.")
	_interaction.clear_mouse_override()
	# Declaring the canopy as support changes the eye's probe, not what the camera sees.
	target.support_paths = PackedStringArray([target.get_path_to(canopy)])
	await _physics_frames(2)
	if _find_target_on_screen(target) != Vector2.ZERO:
		_failures.append("Declaring a canopy as support let the pointer see through it from the camera.")
	target.support_paths = PackedStringArray()
	# `transparency` alone is not drawn on Compatibility (Godot ignores it outside Forward+),
	# so a canopy with only that set is still opaque, and still hides the object.
	var canopy_mesh := canopy.get_node("MeshInstance3D") as MeshInstance3D
	canopy_mesh.transparency = 0.82
	await _physics_frames(2)
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	var instance_pick := _find_target_on_screen(target)
	if forward_plus:
		if instance_pick == Vector2.ZERO or _first_drawn_body(centre) == canopy:
			_failures.append("Forward+ instance fade did not uncover the canopy target.")
	elif instance_pick != Vector2.ZERO or _first_drawn_body(centre) != canopy:
		_failures.append("Instance transparency alone (not drawn on this renderer) let the pointer through.")
	# Negative control: removing the instance fade must hide the target again.
	canopy_mesh.transparency = 0.0
	await _physics_frames(2)
	if _find_target_on_screen(target) != Vector2.ZERO or _first_drawn_body(centre) != canopy:
		_failures.append("Restoring the opaque canopy did not hide the target again.")
	# Independent single-alpha control, and the Compatibility/Mobile fader path:
	# an alpha-blended material alone is see-through on every renderer.
	var faded := StandardMaterial3D.new()
	faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faded.albedo_color = Color(1.0, 1.0, 1.0, 0.18)
	canopy_mesh.material_override = faded
	await _physics_frames(2)
	if _find_target_on_screen(target) == Vector2.ZERO:
		_failures.append("A faded (see-through) canopy still hid the target from the pointer. %s" % _explain(target))
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	await _physics_frames(4)
	if _interaction.get_current_target() != target:
		_failures.append(
			"Facing a target under a faded canopy did not choose it (current %s)."
			% _name_of(_interaction.get_current_target())
		)
	_interaction.clear_mouse_override()
	_clean_up()


# --- case 8: partly covered ---------------------------------------------------


## The rule for an object a surface covers in part is the outline mask's rule, per pixel:
## the object is pointable where its own surface is the nearest drawn one. A canopy over the
## left half of a wide box: a pixel on the right half picks it, a pixel on the left half
## does not, and asking again gives the same answer.
func _check_partial_cover_is_per_pixel() -> void:
	await _reset()
	var target := _make_drawn_probe(&"occlusion_partial", Vector3(0.0, 0.9, -1.4), Vector3(1.2, 0.6, 0.1))
	var canopy := _make_wall(Vector3(-0.2, 2.2, -0.9), Vector3(2.0, 0.1, 2.6), true)
	await _physics_frames(4)
	var left := Vector3(-0.45, 0.9, -1.4)
	var right := Vector3(0.45, 0.9, -1.4)
	if _first_drawn_body(left) != canopy or _first_drawn_body(right) != null:
		_failures.append(
			"Case 8 setup: expected the canopy over the left half only (left meets '%s', right meets '%s')."
			% [_node_name(_first_drawn_body(left)), _node_name(_first_drawn_body(right))]
		)
		return
	var on_left := _pointer_at(left, false)
	var on_right := _pointer_at(right, false)
	print("[#115] partial cover: left (covered) -> %s, right (open) -> %s" % [_name_of(on_left), _name_of(on_right)])
	if on_left == target:
		_failures.append("The pointer picked the covered half of a partly covered object.")
	if on_right != target:
		_failures.append("The pointer missed the open half of a partly covered object (got %s)." % _name_of(on_right))
	for _repeat in 3:
		if _pointer_at(left, false) != on_left or _pointer_at(right, false) != on_right:
			_failures.append("The partial-cover answer changed between identical asks.")
			break
	# Pointing at the open half makes it the target and lights it; pointing at the covered
	# half lets it go: the prompt and the cue follow the same per-pixel answer.
	_interaction.set_mouse_override(_screen_of(right))
	await _physics_frames(4)
	if _interaction.get_current_target() != target or _interaction.get_highlighted() != target:
		_failures.append(
			"The open half was pointed at but not adopted (current %s, highlight %s, hover ask %s). %s"
			% [
				_name_of(_interaction.get_current_target()), _name_of(_interaction.get_highlighted()),
				_name_of(_pointer_at(right, true)), _explain(target)
			]
		)
	# The hover path asks with reach required; the covered half must answer the same there.
	if _pointer_at(left, true) == target:
		_failures.append("The hover question (reach required) picked the covered half.")
	_interaction.clear_mouse_override()
	_clean_up()


# --- case 9: a target that goes away -----------------------------------------


func _check_dropped_targets_leave_nothing() -> void:
	await _reset()
	var target := _make_drawn_probe(&"occlusion_dropped", Vector3(0.0, 0.9, -1.2), Vector3(0.4, 0.4, 0.4))
	await _physics_frames(4)
	_interaction.set_mouse_override(_screen_of(_box_centre(target)))
	await _physics_frames(4)
	if _interaction.get_current_target() != target:
		_failures.append("Case 9 setup: the pointer did not adopt the probe. %s" % _explain(target))
	target.interaction_enabled = false
	await _physics_frames(4)
	if _interaction.get_current_target() == target or _interaction.get_highlighted() == target \
			or target.is_highlighted():
		_failures.append("A switched-off target kept the target or its cue.")
	_activated.clear()
	await _push_e()
	if _activated.has(&"occlusion_dropped"):
		_failures.append("E used a switched-off target.")
	target.interaction_enabled = true
	await _physics_frames(4)
	if _interaction.get_current_target() != target:
		_failures.append("A target switched back on was not adopted again.")
	await _free_probe(target)
	await _physics_frames(2)
	if _interaction.get_current_target() != null or _interaction.get_highlighted() != null:
		_failures.append(
			"A freed target left something behind (current %s, highlight %s)."
			% [_name_of(_interaction.get_current_target()), _name_of(_interaction.get_highlighted())]
		)
	_interaction.clear_mouse_override()


# --- case 10: the real classroom ------------------------------------------------


## The timetable sheet is a thin sheet on the inside of the south wall (`WallSouthLeft`,
## opaque until the camera's fader dims it). The fixed camera sits south of the player, so
## it always looks at that wall from outside: the sheet is on screen only through the wall
## while the wall is faded. The #111 capture stood at SHEET_SPOT_111, where the fader's ray
## passes through the door and the wall stays opaque: the depth-tested outline drew nothing
## (27 of 27 points behind the wall) while the pointer still selected the sheet.


func _check_classroom_timetable() -> void:
	var sheet := _location.find_interactable(&"timetable")
	var wall := _location.get_node_or_null("WallSouthLeft") as StaticBody3D
	if sheet == null or wall == null:
		_failures.append("Case 10: the classroom lost the timetable or WallSouthLeft.")
		return
	var authored := load("res://assets/materials/classroom/wall_section.tres") as BaseMaterial3D
	print(
		"[#115] classroom: sheet anchor %s, outline %s, wall %s"
		% [str(sheet.global_position), str(_box_centre(sheet)), str(wall.global_position)]
	)

	# (a) Where the #111 capture stood. The door is right beside the player, so facing picks
	# the door; the question is what the pointer does on the sheet's pixels.
	var a := await _measure_sheet_view("a #111 spot", sheet, wall, SHEET_SPOT_111, SHEET_SPOT_111 + Vector3.RIGHT)
	if int(a["hidden"]) == 0:
		_failures.append("Case 10a: the sheet was expected to be behind the opaque wall from here. %s" % str(a))
	if int(a["contradictions"]) > 0:
		_failures.append(
			"Case 10a: the pointer selected the sheet at %d of %d points the camera sees only through the opaque wall. %s"
			% [int(a["contradictions"]), int(a["points"]), str(a)]
		)
	if a["current"] == "timetable" or a["highlight"] == "timetable":
		_failures.append("Case 10a: the hidden sheet became the target or was lit. %s" % str(a))
	if bool(a["e_used"]) or bool(a["click_used"]) or bool(a["click_walks"]):
		_failures.append("Case 10a: E or a click reached the hidden sheet. %s" % str(a))

	# (b) The legitimate view: a spot in front of the sheet where the fader has dimmed the
	# wall, so the camera sees the sheet through it.
	var spot := await _find_faded_spot(sheet, wall)
	if spot == Vector3.INF:
		_failures.append("Case 10b: no standing spot in front of the sheet dims WallSouthLeft.")
	else:
		var b := await _measure_sheet_view("b faded wall", sheet, wall, spot, sheet.global_position)
		var drawn := (wall.get_node("MeshInstance3D") as GeometryInstance3D).material_override as BaseMaterial3D
		print("[#115] fader: authored %s, while faded %s" % [str(authored), str(drawn)])
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			# Real pixels in classroom_wall_render_test prove the instance owns this
			# fade. Requiring another alpha copy here would reintroduce 18% * 18%.
			if drawn != authored or drawn == null or drawn.albedo_color.a != 1.0 \
					or _wall_transparency(wall) < 0.5:
				_failures.append("Case 10b: Forward+ did not keep one instance fade and the exact authored material.")
		elif drawn == null or drawn.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or drawn.albedo_color.a > 0.5:
			_failures.append(
				"Case 10b: the faded wall is not drawn with an alpha-blended material, so it would"
				+ " stay opaque on Compatibility (material %s)." % str(drawn)
			)
		if int(b["contradictions"]) > 0 or int(b["picked"]) == 0:
			_failures.append("Case 10b: the visible sheet was not pointable consistently. %s" % str(b))
		if b["current"] != "timetable" or b["highlight"] != "timetable":
			_failures.append("Case 10b: the visible sheet under the pointer was not the lit target. %s" % str(b))
		if not bool(b["e_used"]) or not bool(b["click_used"]):
			_failures.append("Case 10b: E or a click could not use the visible sheet. %s" % str(b))
		await _check_sheet_switched_off(sheet, spot)

	# Away from the wall, the fader gives the authored material back - the same resource.
	var away := Vector3(1.2, 0.0, 1.2)
	_player.teleport(Transform3D(_yaw_towards(away, away + Vector3.FORWARD), away))
	await _physics_frames(12)
	var rest := (wall.get_node("MeshInstance3D") as GeometryInstance3D).material_override
	if _wall_transparency(wall) > 0.0 or rest != authored:
		_failures.append(
			"WallSouthLeft did not get its authored material back after the fade (%s, transparency %.2f)."
			% [str(rest), _wall_transparency(wall)]
		)

	# (c) Behind the wall: the player outside, looking at its back.
	var back := Vector3(1.6, 0.0, 4.3)
	# The classroom floor ends under the wall. A collider-only slab (nothing drawn, so the
	# camera's view is unchanged) keeps the player standing at eye height out there.
	_make_wall(Vector3(1.6, -0.1, 4.6), Vector3(3.0, 0.2, 1.6))
	await _physics_frames(2)
	var c := await _measure_sheet_view("c behind the wall", sheet, wall, back, sheet.global_position)
	if bool(c["eye"]):
		_failures.append("Case 10c: the player's eye saw the sheet through the back of the wall. %s" % str(c))
	if int(c["picked"]) > 0 or c["current"] == "timetable" or bool(c["e_used"]) or bool(c["click_used"]):
		_failures.append("Case 10c: the sheet was reachable from behind its wall. %s" % str(c))
	_clean_up()

	# (d) The edge: a walk along the room past the end of the wall, where the fader's ray
	# leaves WallSouthLeft and the wall turns opaque again. The pointer must follow the
	# wall's drawn state step by step: never a pick through an opaque wall.
	var lines: Array[String] = []
	var flips := 0
	var last := ""
	for step in 9:
		var at := Vector3(0.9 + 0.2 * float(step), 0.0, 2.75)
		var d := await _measure_sheet_view("d edge x=%.1f" % at.x, sheet, wall, at, sheet.global_position, false)
		lines.append("x=%.1f t=%.2f hidden=%d picked=%d" % [at.x, float(d["wall"]), int(d["hidden"]), int(d["picked"])])
		if int(d["contradictions"]) > 0:
			_failures.append("Case 10d: a pick through the opaque wall at x=%.1f. %s" % [at.x, str(d)])
		var state := "seen" if int(d["picked"]) > 0 else "not"
		if not last.is_empty() and state != last:
			flips += 1
		last = state
	print("[#115] edge sweep (z=2.75): %s; flips=%d" % ["; ".join(lines), flips])

	# (e) Facing, with the pointer parked: in front of the sheet, in reach and in the eye's
	# sight, but far enough back that the fader's ray clears the wall top and leaves it
	# opaque - the sheet is not the target. From the faded spot it is.
	var e := await _measure_facing(sheet, wall, Vector3(1.6, 0.0, 1.9))
	if bool(e["eye"]) and bool(e["reach"]) and int(e["hidden"]) == int(e["points"]) \
			and int(e["points"]) > 0:
		if e["current"] == "timetable" or bool(e["e_used"]):
			_failures.append("Case 10e: facing chose the sheet the camera sees only through the opaque wall. %s" % str(e))
	else:
		print("[#115] case 10e precondition not met, facing not judged: %s" % str(e))
	if spot != Vector3.INF:
		var f := await _measure_facing(sheet, wall, spot)
		if f["current"] != "timetable" or not bool(f["e_used"]):
			_failures.append("Case 10e: facing the sheet through the faded wall did not choose and use it. %s" % str(f))

	await _check_scene_swap_leaves_nothing(sheet, spot)


## Facing only (pointer parked off everything): what the controller chooses at `spot`
## facing the sheet, and whether E uses it, next to the camera's view of the sheet.
func _measure_facing(sheet: Interactable, wall: StaticBody3D, spot: Vector3) -> Dictionary:
	_navigator.cancel()
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	_player.teleport(Transform3D(_yaw_towards(spot, sheet.global_position), spot))
	await _physics_frames(8)
	var result := {
		"view": "facing", "player": spot, "wall": _wall_transparency(wall),
		"eye": _interaction.has_line_of_sight(sheet), "reach": _interaction.is_in_reach(sheet),
		"seen": _interaction.is_seen_by_camera(sheet), "points": 0, "hidden": 0,
		"current": _name_of(_interaction.get_current_target()),
		"highlight": _name_of(_interaction.get_highlighted()), "e_used": false,
	}
	for point in _sheet_points(sheet):
		if _behind_camera(point):
			continue
		result["points"] = int(result["points"]) + 1
		if _first_drawn_body(point) != null:
			result["hidden"] = int(result["hidden"]) + 1
	_activated.clear()
	await _push_e()
	result["e_used"] = _activated.has(&"timetable")
	await _settle_dialogue()
	print("[#115] facing %s" % str(result))
	return result


## Stands at `spot` facing `look_at`, lets the camera and its fader settle, then asks every
## question #115 lists: the camera's view of the sheet's points, the pointer on each, and -
## with the pointer on the sheet's middle - the current target, the cue, the prompt, E and a
## click. With `act` false only the per-point view is measured.
func _measure_sheet_view(
	label: String, sheet: Interactable, wall: StaticBody3D, spot: Vector3, look_at: Vector3,
	act: bool = true
) -> Dictionary:
	_navigator.cancel()
	_interaction.set_mouse_override(Vector2(2.0, 2.0))
	_player.teleport(Transform3D(_yaw_towards(spot, look_at), spot))
	await _physics_frames(8)
	var result := {
		"view": label, "player": spot, "camera": _camera_position(),
		"wall": _wall_transparency(wall), "eye": _interaction.has_line_of_sight(sheet),
		"reach": _interaction.is_in_reach(sheet), "points": 0, "hidden": 0, "picked": 0,
		"contradictions": 0, "blocker": "", "current": "", "highlight": "", "prompt": "",
		"e_used": false, "click_used": false, "click_walks": false,
	}
	var points := _sheet_points(sheet)
	for point in points:
		if _behind_camera(point):
			continue
		result["points"] = int(result["points"]) + 1
		var blocker := _first_drawn_body(point)
		var picked := _pointer_at(point, false) == sheet
		if blocker != null:
			result["hidden"] = int(result["hidden"]) + 1
			result["blocker"] = _node_name(blocker)
			if picked:
				result["contradictions"] = int(result["contradictions"]) + 1
		if picked:
			result["picked"] = int(result["picked"]) + 1
	if act and not _behind_camera(_box_centre(sheet)):
		var screen := _screen_of(_box_centre(sheet))
		_interaction.set_mouse_override(screen)
		await _physics_frames(4)
		var current := _interaction.get_current_target()
		result["current"] = _name_of(current)
		result["highlight"] = _name_of(_interaction.get_highlighted())
		result["prompt"] = current.get_prompt() if current != null else ""
		_activated.clear()
		await _push_e()
		result["e_used"] = _activated.has(&"timetable")
		await _settle_dialogue()
		_activated.clear()
		_navigator.click_at_screen_position(screen)
		await _physics_frames(2)
		result["click_used"] = _activated.has(&"timetable")
		result["click_walks"] = _navigator.is_approaching() and _navigator.get_pending_target() == sheet
		_navigator.cancel()
		await _settle_dialogue()
		_interaction.set_mouse_override(Vector2(2.0, 2.0))
	print("[#115] view %s" % str(result))
	return result


## A spot in front of the sheet from which the camera's fader dims WallSouthLeft, and from
## which the sheet is in reach and in the player's sight. Vector3.INF if there is none.
func _find_faded_spot(sheet: Interactable, wall: StaticBody3D) -> Vector3:
	for z in [2.7, 2.5, 2.9]:
		for x in [1.6, 1.2, 0.8, 2.0, 0.4]:
			var at := Vector3(x, 0.0, z)
			_player.teleport(Transform3D(_yaw_towards(at, sheet.global_position), at))
			await _physics_frames(8)
			if _wall_transparency(wall) > 0.0 and _interaction.is_in_reach(sheet) \
					and _interaction.has_line_of_sight(sheet):
				return at
	return Vector3.INF


func _check_sheet_switched_off(sheet: Interactable, spot: Vector3) -> void:
	_player.teleport(Transform3D(_yaw_towards(spot, sheet.global_position), spot))
	_interaction.set_mouse_override(_screen_of(_box_centre(sheet)))
	await _physics_frames(6)
	if _interaction.get_current_target() != sheet:
		_failures.append("Case 10b: the sheet was not the target before it was switched off.")
	sheet.interaction_enabled = false
	await _physics_frames(4)
	if _interaction.get_current_target() == sheet or sheet.is_highlighted():
		_failures.append("Case 10b: the switched-off sheet stayed the target or stayed lit.")
	_activated.clear()
	await _push_e()
	if _activated.has(&"timetable"):
		_failures.append("Case 10b: E used the switched-off sheet.")
	sheet.interaction_enabled = true
	await _physics_frames(2)
	_interaction.set_mouse_override(Vector2(2.0, 2.0))


## With the sheet the lit target, the room is swapped for the corridor: whatever the
## controller holds afterwards is alive and in the new room, never the freed sheet.
func _check_scene_swap_leaves_nothing(sheet: Interactable, spot: Vector3) -> void:
	if spot != Vector3.INF:
		_player.teleport(Transform3D(_yaw_towards(spot, sheet.global_position), spot))
		_interaction.set_mouse_override(_screen_of(_box_centre(sheet)))
		await _physics_frames(6)
	var before := _name_of(_interaction.get_current_target())
	if not _host.load_location(CORRIDOR, &"FromClassroom", _player, &"corridor"):
		_failures.append("Case 10: the corridor did not load for the scene-swap check.")
		return
	await _physics_frames(6)
	var current := _interaction.get_current_target()
	var lit := _interaction.get_highlighted()
	print("[#115] scene swap: before=%s after=%s highlight=%s" % [before, _name_of(current), _name_of(lit)])
	if current != null and (not InteractionController.is_live_target(current) or current == sheet):
		_failures.append("After a scene swap the controller still held the old room's target.")
	if lit != null and (not InteractionController.is_live_target(lit) or lit == sheet):
		_failures.append("After a scene swap the old room's object was still lit.")
	if is_instance_valid(sheet) and sheet.is_inside_tree():
		_failures.append("The scene swap left the classroom's sheet in the tree.")
	_interaction.clear_mouse_override()


# --- camera helpers ----------------------------------------------------------


## The first body the camera ray to `point` meets that the camera draws opaque: a visible
## mesh, on a layer the camera renders, with no transparency. Bodies with nothing drawn and
## faded walls are passed. Measured independently of the controller on purpose.
func _first_drawn_body(point: Vector3) -> Node:
	var camera := _player.get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.global_position
	var space := _player.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	for _attempt in 12:
		var query := PhysicsRayQueryParameters3D.create(from, point, 1)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return null
		var body := hit.get("collider") as CollisionObject3D
		if body == null:
			return null
		if (hit.get("position") as Vector3).distance_to(point) <= 0.06:
			# The object's own surface, or something coplanar with it within the pick padding.
			return null
		if _drawn_opaque(body, camera.cull_mask):
			return body
		excluded.append(body.get_rid())
	return null


## A piece hides what is behind it when it writes depth: it is visible, on a camera layer,
## and drawn with at least one material that is not alpha-blended. Instance transparency
## is drawn only on Forward+ (also measured by classroom_wall_render_test); it must not
## make a Compatibility/Mobile wall disappear from this independent oracle.
func _drawn_opaque(body: Node, cull_mask: int) -> bool:
	var nodes: Array[Node] = [body]
	nodes.append_array(body.find_children("*", "GeometryInstance3D", true, false))
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if geometry == null or not geometry.is_visible_in_tree() or geometry.name == "OutlineKey":
			continue
		if (geometry.layers & cull_mask) == 0:
			continue
		if RenderingServer.get_current_rendering_method() == "forward_plus" \
				and geometry.transparency > 0.0:
			continue
		var materials: Array[Material] = []
		if geometry.material_override != null:
			materials.append(geometry.material_override)
		elif geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
			var mesh := geometry as MeshInstance3D
			for surface in mesh.get_surface_override_material_count():
				materials.append(mesh.get_active_material(surface))
		if materials.is_empty():
			return true
		for material in materials:
			var base := material as BaseMaterial3D
			if base == null or base.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
				return true
	return false


## Points across the sheet's outline meshes: a 3x3 grid over each mesh's box, at its middle.
func _sheet_points(target: Interactable) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for mesh in target.get_outline_meshes():
		var box := mesh.get_aabb()
		for ix in 3:
			for iy in 3:
				var local := box.position + Vector3(
					box.size.x * (0.2 + 0.3 * float(ix)), box.size.y * (0.2 + 0.3 * float(iy)), box.size.z * 0.5
				)
				points.append(mesh.global_transform * local)
	return points


## The middle of everything the object's outline traces, or its anchor when it traces nothing.
func _box_centre(target: Interactable) -> Vector3:
	var meshes := target.get_outline_meshes()
	if meshes.is_empty():
		return target.global_position
	var bounds := meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes:
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	return bounds.get_center()


func _pointer_at(point: Vector3, require_reach: bool) -> Interactable:
	return _interaction.get_target_at_screen_position(_screen_of(point), require_reach)


func _behind_camera(point: Vector3) -> bool:
	var camera := _player.get_viewport().get_camera_3d()
	return camera == null or camera.is_position_behind(point)


func _camera_position() -> Vector3:
	var camera := _player.get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


func _wall_material(wall: StaticBody3D) -> Material:
	var mesh := wall.get_node_or_null("MeshInstance3D") as GeometryInstance3D
	return mesh.material_override if mesh != null else null


func _wall_transparency(wall: StaticBody3D) -> float:
	var mesh := wall.get_node_or_null("MeshInstance3D") as GeometryInstance3D
	return mesh.transparency if mesh != null else -1.0


## A basis that faces the player from `from` towards `to` (never the identity, which
## `PlayerController.teleport` reads as "keep the current facing").
func _yaw_towards(from: Vector3, to: Vector3) -> Basis:
	var offset := to - from
	var yaw := atan2(-offset.x, -offset.z)
	if is_zero_approx(yaw):
		yaw = 0.0001
	return Basis(Vector3.UP, yaw)


func _node_name(node: Node) -> String:
	return String(node.name) if node != null else "<nothing>"


func _name_of(interactable: Interactable) -> String:
	return String(interactable.interact_id) if interactable != null else "<nothing>"


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
