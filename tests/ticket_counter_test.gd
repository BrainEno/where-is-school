extends SceneTree
## Start outside the 01 door, walk through it and click the faces in the live game.
## With a renderer, -- capture=/tmp/tickets also saves those actual gameplay shots.

const Harness = preload("res://tests/test_harness.gd")
const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const HALL := "res://scenes/locations/corridor/corridor.tscn"
# Just through the threshold and a step right, still outside the 2.4 m use range.
# The live follow camera can see the whole row when the player turns from here.
const ENTRY_INSIDE := Vector3(-17.03, -3.4, 13.06)
const AT_COUNTER := Vector3(-13.74, -3.4, 11.66)

var _check := Harness.Checker.new()
var _world: Node
var _hall: LocationRoot
var _director: OpeningSequence
var _dialogue: DialogueController
var _player: PlayerController
var _rig: CameraRig
var _interaction: InteractionController
var _pointer: PointerNavigator
var _capture := ""
var _frames := 0
var _approached: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 86.0, "ticket_counter_test.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("capture="):
			_capture = arg.trim_prefix("capture=")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	if MobileLayout.enabled:
		Input.emulate_mouse_from_touch = true
	if not _capture.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture)
	var autoloads := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var state: Node = autoloads["game_state"]
	var knowledge: Node = autoloads["narrative_state"]
	state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	if await _enter_hall():
		state.set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
		var flags: Dictionary = state.get_snapshot()
		var journal: Dictionary = knowledge.to_snapshot()
		await _ticket_visit()
		_check.expect(flags == state.get_snapshot() and journal == knowledge.to_snapshot()
			and not autoloads["save"].has_save(), "Looking at a clerk wrote story state, knowledge or a save.")
	if not _capture.is_empty():
		_check.expect(_frames == 4, "Expected the threshold and three real close-ups; got %d frames." % _frames)
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	_world.queue_free()
	await _world.tree_exited
	await process_frame
	Harness.clear_session_state(self)
	Harness.finish(self, _check.failures, "01 glass threshold, three face %s, silent held close-ups "
		% ("taps" if MobileLayout.enabled else "clicks") + "and released controls, with the gallery still walkable.")


func _enter_hall() -> bool:
	Harness.stage = "ticket counter: through the real 01 door"
	_world = MAIN.instantiate()
	_director = _world.get_node(^"OpeningSequence") as OpeningSequence
	_director.autostart = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_player = _world.get_node(^"Player") as PlayerController
	_rig = _player.camera_rig
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_pointer.approach_started.connect(func(target: Interactable) -> void: _approached.append(target.interact_id))
	_director.allow_player_control()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	var host := _world.get_node(^"LocationHost") as LocationHost
	await process_frame # Finish the initial scene's deferred bindings before replacing it.
	if not _check.expect(host.load_location(HALL, &"FromTeachingEntrance", _player, &"corridor"),
			"Could not start outside the teaching entrance."):
		return false
	_hall = host.get_current()
	_player.set_wake_pose(0.0)
	var nav := _hall.get_node(^"Navigation") as LocationNavigation
	return _check.expect(await Harness.wait_until(func() -> bool:
		return nav.is_routable() and _player.is_on_floor() and _player.is_control_enabled(), 8.0),
		"The player and navigation never became ready outside 01.")


func _ticket_visit() -> void:
	if not await _walk(ENTRY_INSIDE):
		return
	if not await _look_at_clerk(0):
		return
	_check.expect(_approached.has(&"ticket_clerk_0"), "A distant face click skipped walking up to the desk.")
	if not await _walk(AT_COUNTER):
		return
	for index in [1, 2]:
		if not await _look_at_clerk(index):
			return
	if _capture.is_empty() and not MobileLayout.enabled:
		await _look_at_clerk(1, true)
	await _walk(Vector3(-9.94, -3.4, 12.54)) # The same gallery still leads to the blue stair.


func _walk(feet: Vector3) -> bool:
	if not _check.expect(_player.request_path_to(feet), "Could not walk to %s around the booth." % feet):
		return false
	return _check.expect(await Harness.wait_until(func() -> bool:
		return _player.is_on_floor() and not _player.is_path_active(), 9.0)
		and _player.global_position.distance_to(feet) < .70,
		"Walk ended at %s, not %s." % [_player.global_position, feet])


func _look_at_clerk(index: int, use_keyboard := false) -> bool:
	var id := StringName("ticket_clerk_%d" % index)
	Harness.stage = "ticket counter: %s" % id
	var subject := _hall.find_interactable(id) as StagedInteractable
	if not _check.expect(subject != null and subject.is_staged() and subject.camera_shot != null,
			"%s has no staged close-up." % id):
		return false
	var head := subject.get_node_or_null(subject.camera_shot.insert_anchor_path) as Node3D
	if not _check.expect(head != null and head.has_node(^"FaceAndHair"), "%s does not aim at her own head." % id):
		return false
	_player.face_toward(subject.global_position - _player.global_position)
	var eye := head.to_global(Vector3(0, .132, .080))
	var pickable := await Harness.wait_until(func() -> bool:
		var pixel := _rig.camera.unproject_position(eye)
		return root.get_visible_rect().has_point(pixel) and _interaction.get_target_at_screen_position(pixel, false) == subject, 3.0)
	if not pickable:
		_check.expect(false, _pick_diagnostic(subject, eye))
		return false
	_check.expect(_rig.get_focus_subject() == null and not _director.is_beat_active(), "Aiming started a shot before the click.")
	if index == 0:
		await _frame("entry")
	var clicks := _pointer.get_world_click_event_count()
	if use_keyboard:
		_interaction.mouse_targeting = false
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return _interaction.get_current_target() == subject, 2.0), "No E prompt for %s." % id):
			return false
		_press_interact()
	else:
		_click(_rig.camera.unproject_position(eye))
	var settled := await Harness.wait_until(func() -> bool:
		return _rig.get_focus_subject() == subject and _rig.get_focus_weight() == 1.0, 8.0)
	var accepted := use_keyboard or (_pointer.get_world_click_event_count() == clicks + 1 and _pointer.was_last_click_accepted())
	if not _check.expect(settled and accepted,
			"%s input did not settle on its face shot (%s)." % [id, _pointer.get_last_rejection()]):
		return false
	_check.expect(_director.is_beat_active() and not _player.is_control_enabled() and not _dialogue.is_busy(),
		"%s should hold movement, not open dialogue." % id)
	_check_framing(head, id)
	await _frame("clerk_%d" % index)
	var released := await Harness.wait_until(func() -> bool:
		return (not _director.is_beat_active() and _player.is_control_enabled()
			and _rig.get_focus_subject() == null and _rig.get_focus_weight() == 0.0), 6.0)
	return _check.expect(released and is_equal_approx(_rig.get_effective_fov(), _rig.fov),
		"%s didn't give gameplay back." % id)


func _pick_diagnostic(subject: Interactable, eye: Vector3) -> String:
	var camera := _rig.camera
	var pixel := camera.unproject_position(eye)
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var space := _player.get_world_3d().direct_space_state
	var area := PhysicsRayQueryParameters3D.create(origin, origin + direction * 60.0, Interactable.INTERACTION_LAYER)
	area.collide_with_areas = true
	area.collide_with_bodies = false
	var body := PhysicsRayQueryParameters3D.create(origin, eye, _interaction.occluder_mask)
	var area_hit := space.intersect_ray(area).get("collider") as Node
	var body_hit := space.intersect_ray(body).get("collider") as Node
	return ("%s isn't pickable at her face: feet %s, camera %s, eye %s at %s in %s, "
		+ "area %s, first body %s, player LOS %s, camera visible %s.") % [
		subject.interact_id, _player.global_position, origin, eye, pixel, root.get_visible_rect(),
		area_hit.get_path() if area_hit != null else "none", body_hit.get_path() if body_hit != null else "none",
		_interaction.has_line_of_sight(subject), _interaction.is_drawn_at_screen_ray(origin, direction, subject),
	]


func _check_framing(head: Node3D, id: StringName) -> void:
	var camera := _rig.camera
	var eye_space := camera.global_position - head.global_position
	var a := head.to_global(Vector3(-.043, .132, .080))
	var b := head.to_global(Vector3(.043, .132, .080))
	var crown := head.to_global(Vector3(0, .268, -.015))
	var ap := camera.unproject_position(a)
	var bp := camera.unproject_position(b)
	# Camera3D projects in viewport coordinates, not Window.size (physical pixels).
	# Require the same share of the picture with or without mobile canvas scaling.
	var view := camera.get_viewport().get_visible_rect()
	var safe := view.grow(-30.0)
	var crown_pixel := camera.unproject_position(crown)
	var eye_ratio := ap.distance_to(bp) / view.size.y
	var angle := eye_space.normalized().dot(head.global_basis.z)
	var in_frame := safe.has_point(ap) and safe.has_point(bp) and safe.has_point(crown_pixel)
	_check.expect(camera == root.get_camera_3d() and angle > .83 and not camera.is_position_behind(a)
		and in_frame and eye_ratio >= .11,
		"%s didn't frame both eyes and hair: eye gap %.1f%%, facing %.3f, eyes %s/%s, crown %s, safe rect %s."
		% [id, eye_ratio * 100.0, angle, ap, bp, crown_pixel, safe])
	print("TICKET SHOT: %s, eye gap %.1f%% of picture, camera %.2f m from chin"
		% [id, eye_ratio * 100.0, eye_space.length()])


func _click(pixel: Vector2) -> void:
	var screen := root.get_final_transform() * pixel
	for pressed: bool in [true, false]:
		if MobileLayout.enabled:
			var tap := InputEventScreenTouch.new()
			tap.position = screen
			tap.pressed = pressed
			Input.parse_input_event(tap)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = screen
			event.global_position = screen
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()


func _press_interact() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _frame(label: String) -> void:
	if _capture.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not _check.expect(image != null and not image.is_empty(), "No renderer image for %s." % label):
		return
	var filename := "ticket_shot_detail_%s.jpg" % label
	if not _check.expect(image.save_jpg(_capture.path_join(filename), .88) == OK, "Could not write %s." % filename):
		return
	_frames += 1
	print("EVIDENCE " + JSON.stringify({
		"frame": filename,
		"size": [image.get_width(), image.get_height()],
		"shows": {"kind": "ticket_counter", "view": label},
	}))
