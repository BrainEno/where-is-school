extends SceneTree
## The real 01 exterior: select the paint, walk up, hold an insert, then walk again.
## Pass --mobile-preview for touch, or capture=<directory> under a windowed renderer
## to save both the approach and the settled close-up from this same interaction.

const Harness = preload("res://tests/test_harness.gd")
const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
const Tour = preload("res://scripts/dev/school_room_tour.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const HALL := "res://scenes/locations/corridor/corridor.tscn"
const WALL_PATH := ^"TeachingBlock/GroundFloor/EntranceWallWest"
const ID := &"teaching_entrance_graffiti"
## Round 25: the glass doors became a click exit and the apron is not walked any more; the
## sprayed wall faces the stable lane, reached from 01 through the gallery's side door.
const LANE_STANCE := Vector3(-21.8, -3.4, 16.6)

# Keep the normal autosave contract under test without letting a screenshot run
# read or clear a player's real save. A surprise write must still fail the test.
class SaveProbe extends Tour.NoStoryFiles:
	var write_attempts := 0

	func write_bytes(_path: String, _data: PackedByteArray) -> int:
		write_attempts += 1
		return ERR_UNAVAILABLE

var _check := Harness.Checker.new()
var _world: Node
var _director: OpeningSequence
var _player: PlayerController
var _rig: CameraRig
var _interaction: InteractionController
var _pointer: PointerNavigator
var _capture := ""
var _approached := false


func _initialize() -> void:
	Harness.arm_watchdog(self, 65.0, "wall_graffiti_test.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("capture="):
			_capture = arg.trim_prefix("capture=")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "01 exterior spawn"
	var touch_requested := "--mobile-preview" in OS.get_cmdline_user_args()
	if not _check.expect(not touch_requested or MobileLayout.enabled,
			"Use an editor build for the mobile-preview test; desktop input is not a substitute."):
		Harness.finish(self, _check.failures, "")
		return
	root.size = Vector2i(1600, 900)
	if MobileLayout.enabled:
		Input.emulate_mouse_from_touch = true
	if not _capture.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture)
	var save := Harness.ensure_autoload(self, "Save", Harness.SAVE_SCRIPT)
	var file_probe := SaveProbe.new()
	save.io = file_probe
	var autoloads := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var state: Node = autoloads["game_state"]
	var knowledge: Node = autoloads["narrative_state"]
	state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	var hall := await _enter_hall()
	if hall != null:
		state.set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
		var flags: Dictionary = state.get_snapshot()
		var journal: Dictionary = knowledge.to_snapshot()
		await _visit(hall)
		_check.expect(state.get_snapshot() == flags and knowledge.to_snapshot() == journal
			and file_probe.write_attempts == 0 and not save.has_save(),
			"Looking at the graffiti changed flags, knowledge or attempted a save.")
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	_world.queue_free()
	await _world.tree_exited
	await process_frame
	Harness.clear_session_state(self)
	Harness.finish(self, _check.failures, "01 exterior pigment, navigation and framed %s, no story writes."
		% ("tap" if MobileLayout.enabled else "click and E"))


func _enter_hall() -> LocationRoot:
	_world = MAIN.instantiate()
	_director = _world.get_node(^"OpeningSequence") as OpeningSequence
	_director.autostart = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_player = _director.get_player()
	_rig = _player.camera_rig
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_pointer = _player.get_node(^"PointerNavigator") as PointerNavigator
	_pointer.approach_started.connect(func(target: Interactable) -> void:
		if target.interact_id == ID:
			_approached = true)
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	_director.allow_player_control()
	var host := _world.get_node(^"LocationHost") as LocationHost
	await process_frame # Let main finish its deferred bindings before replacing the classroom.
	if not _check.expect(host.load_location(HALL, &"FromTeachingEntrance", _player, &"corridor"),
			"The 01 exterior did not load."):
		return null
	_player.set_wake_pose(0.0)
	var hall := host.get_current()
	var nav := hall.get_node(^"Navigation") as LocationNavigation
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return nav.is_routable() and _player.is_on_floor() and _player.is_control_enabled(), 8.0),
		"01 inside the glass doors isn't walkable."):
		return null
	var map := nav.get_navigation_map()
	var lane := NavigationServer3D.map_get_closest_point(map, LANE_STANCE)
	var route := NavigationServer3D.map_get_path(map, _player.global_position, lane, true)
	if not _check.expect(Vector2(lane.x - LANE_STANCE.x, lane.z - LANE_STANCE.z).length() < 0.35
		and route.size() >= 2 and route[route.size() - 1].distance_to(lane) < 0.3,
		"The stable lane outside the sprayed wall can't be reached from 01 (nearest %s)." % lane):
		return null
	_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), lane + Vector3.UP * 0.05))
	if not _check.expect(await Harness.wait_until(func() -> bool: return _player.is_on_floor(), 4.0),
		"The player did not settle in the stable lane."):
		return null
	return hall


func _visit(hall: LocationRoot) -> void:
	Harness.stage = "paint and pick from the entrance"
	var wall := hall.get_node_or_null(WALL_PATH) as StaticBody3D
	var subject := hall.find_interactable(ID) as StagedInteractable
	if not _check.expect(wall != null and subject != null and subject.get_parent() == wall,
			"The pigment must be attached to the west exterior wall."):
		return
	var paint := subject.get_node_or_null(^"Paint") as MeshInstance3D
	if not _check.expect(paint != null and subject.camera_shot != null and subject.is_staged(),
			"The wall has no visible art or staged camera shot."):
		return
	_check_wall(wall, subject, paint)
	# An actual dark stroke in the big eye, not an arbitrary empty background pixel.
	var ink := paint.to_global(Vector3(-0.28, 0.53, 0.0))
	var pixel := _rig.camera.unproject_position(ink)
	if not _check.expect(root.get_visible_rect().has_point(pixel)
			and _interaction.get_target_at_screen_position(pixel, false) == subject,
			"No pointer pick at the drawing from the stable lane: %s." % pixel):
		return
	_check.expect(not _interaction.is_in_reach(subject) and _rig.get_focus_subject() == null,
		"The camera started before a real approach and use.")
	await _frame("01_entrance")
	_click(pixel)
	if not await _assert_look(subject, paint):
		return
	_check.expect(_approached and _pointer.was_last_click_accepted(),
		"The paint click didn't walk up and arrive (%s)." % _pointer.get_last_rejection())
	await _frame("02_graffiti_closeup")
	if not await _assert_release():
		return
	if not MobileLayout.enabled:
		_player.face_toward(subject.global_position - _player.global_position)
		_interaction.mouse_targeting = false
		if not _check.expect(await Harness.wait_until(func() -> bool:
			return _interaction.get_current_target() == subject, 2.0), "No E prompt at the exterior paint."):
			return
		_press_interact()
		if await _assert_look(subject, paint):
			await _assert_release()


func _check_wall(wall: StaticBody3D, subject: StagedInteractable, paint: MeshInstance3D) -> void:
	_check.expect(wall.is_in_group("camera_occluder") and paint.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Pigment should fade with the wall and cast no shadow.")
	var plaster := wall.get_node(^"Plaster") as MeshInstance3D
	var coat := plaster.material_override as StandardMaterial3D
	_check.expect(coat != null and coat.albedo_texture != null and coat.normal_enabled
		and coat.normal_texture != null and coat.normal_scale > 0.0 and coat.roughness >= .9,
		"The sprayed wall needs matte, textured plaster with real normal relief.")
	var centre := plaster.to_local(paint.global_position)
	_check.expect(coat != null and coat.uv1_triplanar and not coat.uv1_world_triplanar
		and coat.uv1_scale.is_equal_approx(Vector3(0.5, 0.5, 0.5)) and coat.uv1_offset.is_zero_approx()
		and is_zero_approx(centre.x) and is_zero_approx(centre.y),
		"The pigment's baked pores must align to the plaster's local 2 m projection.")
	var paint_box := (wall.global_transform.affine_inverse() * paint.global_transform) * paint.get_aabb()
	var band := plaster.transform * plaster.get_aabb()
	var gap := paint_box.position.z - band.end.z
	_check.expect(gap > .002 and gap < .012 and paint_box.position.y > band.position.y
		and paint_box.end.y < band.end.y and paint_box.position.x > band.position.x and paint_box.end.x < band.end.x,
		"The drawing intersects a wall course or floats away from the plaster.")
	var material := paint.material_override as StandardMaterial3D
	_check.expect(material != null and material.albedo_texture != null
		and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		and paint.mesh.get_surface_count() == 1 and paint.mesh.get_faces().size() > 6,
		"Expected one contour-shaped surface with the imported clear-background paint.")
	_check.expect(material != null and material.albedo_texture != null
		and material.albedo_texture.get_width() >= 336 and material.albedo_texture.get_height() >= 387
		and coat != null and coat.albedo_texture != null and coat.normal_texture != null
		and coat.albedo_texture.get_width() >= 256 and coat.normal_texture.get_width() >= 128,
		"Budgeted paint and plaster textures must retain the close-up's minimum detail.")
	_check.expect(subject.get_outline_meshes() == [paint] and subject.get_pick_shapes().size() == 1
		and subject.collision_layer == Interactable.INTERACTION_LAYER and subject.collision_mask == 0,
		"The pick/outline should cover just the paint, without adding physical collision.")
	var from_inside := wall.to_global(Vector3(0.0, _interaction.eye_height, -1.0))
	_check.expect(not _interaction.has_line_of_sight_from(from_inside, subject), "The paint is usable through the wall.")


func _assert_look(subject: StagedInteractable, paint: MeshInstance3D) -> bool:
	Harness.stage = "arrive and hold the insert"
	var settled := await Harness.wait_until(func() -> bool:
		return _rig.get_focus_subject() == subject and _rig.get_focus_weight() == 1.0, 12.0)
	if not _check.expect(settled, "The camera never settled on the paint (%s)." % _pointer.get_last_rejection()):
		return false
	var dialogue := _world.get_node(^"DialogueController") as DialogueController
	_check.expect(_director.is_beat_active() and not _player.is_control_enabled() and not dialogue.is_busy(),
		"A graffiti look should hold movement without opening a text panel.")
	var plaster := subject.get_parent().get_node(^"Plaster") as MeshInstance3D
	_check.expect(_rig.get_insert_backdrop() == subject.get_parent()
		and is_zero_approx(plaster.transparency) and is_zero_approx(paint.transparency),
		"The close-up faded the plaster or the pigment it was meant to show.")
	var camera := _rig.camera
	var view := root.get_visible_rect()
	var box := paint.get_aabb()
	var min_y := INF
	var max_y := -INF
	for x: float in [box.position.x, box.end.x]:
		for y: float in [box.position.y, box.end.y]:
			var point := paint.to_global(Vector3(x, y, 0.0))
			var pixel := camera.unproject_position(point)
			_check.expect(not camera.is_position_behind(point) and view.grow(-28.0).has_point(pixel),
				"The insert cropped a corner of the drawing: %s in %s." % [pixel, view])
			min_y = minf(min_y, pixel.y)
			max_y = maxf(max_y, pixel.y)
	var forward := (camera.global_position - paint.global_position).normalized()
	var frame_share := (max_y - min_y) / view.size.y
	_check.expect(forward.dot(paint.global_basis.z) > .85 and frame_share > .65,
		"The art is not a close-up from the painted side: %.0f%% of frame." % (frame_share * 100))
	print("GRAFFITI SHOT: %.1f%% of the picture height, player at %s" % [100 * frame_share, _player.global_position])
	return true


func _assert_release() -> bool:
	Harness.stage = "release and restore gameplay"
	var released := await Harness.wait_until(func() -> bool:
		return not _director.is_beat_active() and _player.is_control_enabled() \
			and _rig.get_focus_subject() == null and _rig.get_focus_weight() == 0.0, 8.0)
	return _check.expect(released and is_equal_approx(_rig.get_effective_fov(), _rig.fov)
		and _rig.get_insert_backdrop() == null, "The look didn't restore steering, occluder fading and the follow lens.")


func _click(pixel: Vector2) -> void:
	var screen := root.get_final_transform() * pixel
	for pressed: bool in [true, false]:
		if MobileLayout.enabled:
			var tap := InputEventScreenTouch.new()
			tap.position = screen
			tap.pressed = pressed
			Input.parse_input_event(tap)
		else:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = screen
			mouse.global_position = screen
			mouse.pressed = pressed
			Input.parse_input_event(mouse)
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
	_check.expect(image != null and not image.is_empty()
		and image.save_jpg(_capture.path_join(label + ".jpg"), .92) == OK,
		"Couldn't save the real render of %s." % label)
