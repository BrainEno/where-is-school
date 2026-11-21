extends "res://tests/capture_character_art.gd"
## Focused Q migration evidence, not a character-art experiment. Reuses only the
## existing main-game boot/framing helpers. Never changes a Look, shader or mesh.
## Also runs inside an archive of the exact pre-migration base for real before views.
## xvfb-run -a godot --path . --fixed-fps 24 --resolution 1280x720 \
##   --rendering-method gl_compatibility --script res://tests/capture_q_migration.gd

var _phase := "after"
var _output := "res://build/q-model-migration/capture"
var _source_sha := "unrecorded-local-worktree"
var _records: Array[Dictionary] = []
var _previews: Array[Dictionary] = []

const TEXTBOOK_PREVIEWS := ["23_q_reading_game_camera", "24_q_reciting_close", "25_q_replying_close"]
const TEXTBOOK_PREVIEW_PARTS := 6


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		if argument.begins_with("--source-sha="):
			_source_sha = argument.trim_prefix("--source-sha=")
	Harness.arm_watchdog(self, 360.0, "capture_q_migration.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	if not await _boot():
		await _finish_migration()
		return
	if _phase == "after":
		await _textbook_capture()
	# Stand by the real player's existing API; no protagonist asset/material edit.
	_player.set_wake_pose(0.0)
	_protagonist.set_seated(false)
	await _wait(2.5)
	_player.set_physics_process(false)
	await _solo(_q, 0.0)
	_pose(_q, "idle", 0.25)
	await _body_shot("01_front_idle")
	await _solo(_q, 90.0)
	await _body_shot("02_side_idle")
	await _solo(_q, 180.0)
	await _body_shot("03_back_idle")
	await _solo(_q, 0.0)
	_pose(_q, "idle", 0.25)
	await _hand_shot("04_hand_negative_x", "hand.L")
	await _hand_shot("05_hand_positive_x", "hand.R")
	await _neck_shot("06_neck_shoulders_front")
	await _solo(_q, 90.0)
	await _neck_shot("07_neck_shoulders_side")
	await _solo(_q, 0.0)
	await _walk_capture()

	await _solo(_q, 0.0)
	for entry: Array in [["wave", 0.5, "13_wave"], ["sit_idle", 0.0, "14_sit_idle"],
		["get_up", 0.5, "15_get_up"]]:
		_pose(_q, String(entry[0]), float(entry[1]))
		await _body_shot(String(entry[2]))
	if _phase == "after":
		# Diagnose supplied garment/shoulder structure separately from calibration.
		# This rest-only frame is labelled diagnostic, never locomotion evidence.
		_q.get_animation_player().stop()
		_q.get_skeleton().reset_bone_poses()
		await _neck_shot("19_supplied_rest_shoulders")
		await _body_shot("20_supplied_rest_diagnostic")
		_pose(_q, "head_movement", 0.45)
		await _neck_shot("16_authored_head_turn")
		_pose(_q, "talk", 0.45)
		await _hand_shot("17_gesturing_fingers", "hand.L")
		_pose(_q, "pose_preview", 0.0)
		await _body_shot("18_supplied_pose_preview")

	await _place_pair(PAIR_PROTAGONIST, PAIR_Q, 25.0)
	_pose(_protagonist, "idle", 0.25)
	_pose(_q, "idle", 0.25)
	var centre := (_protagonist.global_position + _q.global_position) * 0.5
	await _shot_from("11_pair_close", centre + Vector3(0, 1.2, 3.1), centre + Vector3.UP * 0.88)
	var camera := _main.get_node("CameraRig/Camera3D") as Camera3D
	camera.current = true
	await _wait(0.5)
	_save_image("12_pair_game_camera", root.get_texture().get_image())
	await _dialogue_capture()
	await _companion_capture()
	await _finish_migration()


## Q is still at the real opening landing. Re-present the shipped branch here so
## the opening's camera and placement are unchanged. The close camera is review-only.
func _textbook_capture() -> void:
	var book := _q.get_node_or_null(^"BiologyTextbook") as Node3D
	if book == null or not _dialogue.play_conversation(&"q_wake"):
		_failures.append("Could not start real textbook capture from the classroom's Q.")
		return
	for attempt in 64:
		if not _dialogue.is_busy() or _textbook_line() == &"p_ecosystem_question":
			break
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
	if _textbook_line() != &"p_ecosystem_question":
		_failures.append("The live opening did not reach Q's reading cue.")
		await _close_conversation()
		return
	# Keep the real game camera, but hide the text for these visual review frames.
	var panel_visible := _panel.visible
	_panel.hide()
	await _wait(0.55)
	_save_image("23_q_reading_game_camera", root.get_texture().get_image())
	var gameplay_camera := root.get_camera_3d()
	var focus := _q.global_position + Vector3.UP * 1.37
	var forward := _forward(_q)
	var sideways := Vector3.UP.cross(forward)
	var camera := Camera3D.new()
	camera.fov = 33.0
	_main.add_child(camera)
	camera.global_position = focus + forward * 1.22 + sideways * 0.86 + Vector3.UP * 0.76
	camera.look_at(focus)
	camera.current = true
	var frames_dir := "%s/textbook_frames" % _output
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_dir))
	# This workflow runs at 24 fps: just over one full recitation and a raised reply.
	for frame in 72:
		if frame == 56:
			_dialogue.advance_presentation()
			_panel.hide()  # Presenting the answer reopens the dialogue panel.
			if _textbook_line() != &"q_ecosystem":
				_failures.append("Q's real answer did not follow the reading cue.")
		await process_frame
		if not book.is_visible_in_tree():
			_failures.append("Q lost the book during recitation/reply frame %d." % frame)
			break
		RenderingServer.force_draw(true)
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_jpg("%s/frame_%03d.jpg" % [frames_dir, frame], 0.9) != OK:
			_failures.append("The textbook frame %d was not rendered and saved." % frame)
			break
		if frame == 24:
			_save_image("24_q_reciting_close", image)
		elif frame == 71:
			_save_image("25_q_replying_close", image)
	camera.queue_free()
	gameplay_camera.make_current()
	_panel.visible = panel_visible
	await _close_conversation()


func _textbook_line() -> StringName:
	return StringName(_dialogue.get_current_line().get("node_id", &""))


## The inherited capture spot predates the classroom's 4-column desk grid. Use the
## real centre aisle so foreground furniture does not hide the sole in either phase.
func _solo(subject: CharacterVisualAnimation, facing: float) -> void:
	await super._solo(subject, facing)
	_place(subject, Vector3(0.0, 0.0, -2.55), facing)
	await process_frame


func _body_shot(tag: String) -> void:
	var base := _q.global_position
	var frame := await _frame_from(base + Vector3(0, 1.2, 2.7), base + Vector3.UP * 0.88)
	var image := frame["image"] as Image
	var camera := frame["camera"] as Camera3D
	await _measure_drawn(_q, camera, image, _screen_box(camera, _subtree_aabb(_q)), tag)
	_save_image(tag, image)
	camera.queue_free()


func _hand_shot(tag: String, canonical: String) -> void:
	var skeleton := _q.get_skeleton()
	var resolved: Dictionary = _q.get_bind_report()["resolved"]
	var hand_name := String(resolved[canonical])
	var index := skeleton.find_bone(hand_name)
	var bone := skeleton.get_bone_global_pose(index)
	var wrist := skeleton.global_transform * bone.origin
	var centre := skeleton.global_transform * (bone.origin + bone.basis.y * 0.065)
	var outward := wrist - _q.global_position
	outward.y = 0.0
	outward = outward.normalized()
	var normal := outward
	var suffix := hand_name.trim_prefix("Hand")
	var knuckle_index := skeleton.find_bone("Index_01%s" % suffix)
	var knuckle_little := skeleton.find_bone("Little_01%s" % suffix)
	if knuckle_index >= 0 and knuckle_little >= 0:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(knuckle_index).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(knuckle_little).origin
		normal = ((a + b) * 0.5 - wrist).cross(a - b).normalized()
		if normal.dot(outward) < 0.0:
			normal = -normal
	# Photograph across the actual palm plane. A +Z camera sees these correctly
	# inward-facing hands edge-on and cannot show their four separate long fingers.
	await _shot_from(tag, centre + normal * 0.44, centre)


func _neck_shot(tag: String) -> void:
	var centre := _head_point(_q) - Vector3.UP * 0.17
	await _shot_from(tag, centre + Vector3(0, 0.07, 0.92), centre)


func _shot_from(tag: String, eye: Vector3, target: Vector3) -> void:
	var frame := await _frame_from(eye, target)
	_save_image(tag, frame["image"] as Image)
	(frame["camera"] as Camera3D).queue_free()


func _walk_capture() -> void:
	var actor := _q_holder as NpcActor
	if actor == null:
		_failures.append("Q's actual NpcActor is missing for the walk capture.")
		return
	var start := actor.global_position
	_q.set_process(true)
	actor.walk_along([start + Vector3.RIGHT * 3.0])
	var camera := Camera3D.new()
	camera.fov = 50.0
	_main.add_child(camera)
	camera.current = true
	var frames_dir := "%s/walk_frames" % _output
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_dir))
	var walking := 0
	for frame in 48:
		await process_frame
		var base := _q.global_position
		camera.global_position = base + Vector3(0, 1.2, 2.7)
		camera.look_at(base + Vector3.UP * 0.88)
		RenderingServer.force_draw(true)
		var image := root.get_texture().get_image()
		image.save_jpg("%s/frame_%03d.jpg" % [frames_dir, frame], 0.9)
		if _q.get_current_clip() == "walk":
			walking += 1
		if frame == 14:
			_save_image("08_walking", image)
		if frame == 30:
			_save_image("09_walking_late", image)
	var travelled := actor.global_position.distance_to(start)
	_note("Q migration real walk: %.3f m travelled, %d/48 frames on walk" % [travelled, walking])
	if travelled < 1.0 or walking < 20:
		_failures.append("The walking evidence did not capture a real animated route walk.")
	await _wait(2.2)
	camera.queue_free()
	_pose(_q, "idle", 0.25)


func _dialogue_capture(
	conversation: StringName = &"q_wake", tag: String = "10_live_dialogue"
) -> void:
	# A real speaker in the shipped bilingual conversation; no invented evidence text.
	_q.set_process(true)
	_q.report_velocity(Vector3.RIGHT)
	_q.clear_reported_velocity()
	var camera := _main.get_node("CameraRig/Camera3D") as Camera3D
	camera.current = true
	if not _dialogue.play_conversation(conversation):
		_failures.append("The dialogue evidence could not start '%s'." % conversation)
		return
	for attempt in 32:
		if String(_dialogue.get_current_line().get("speaker_id", "")) == "q":
			break
		_dialogue.advance_presentation()
		await process_frame
	await _wait(0.8)
	_save_image(tag, root.get_texture().get_image())
	_note("Q migration dialogue: speaker %s, actual clip %s" % [
		str(_dialogue.get_current_line().get("speaker_id", "")), _q.get_current_clip()])
	if String(_dialogue.get_current_line().get("speaker_id", "")) != "q":
		_failures.append("The dialogue frame did not reach an actual Q line.")
	if _phase == "after" and _q.get_current_clip() != "talk":
		_failures.append("The dialogue frame did not play Q's actual speech state.")


## Photograph the second production placement, not a second copy in a studio.
## LocationHost and CompanionController still own the spawn, capsule and following.
func _companion_capture() -> void:
	await _close_conversation()
	if not _host.load_location(CORRIDOR, &"FromClassroom", _player):
		_failures.append("The companion evidence could not enter the actual corridor.")
		return
	var companion := _main.get_node("Companion") as CompanionController
	companion.join()
	await _wait(1.0)
	await _close_conversation()
	if not companion.is_with_player():
		_failures.append("The real companion placement did not become visible.")
		return
	_q_holder = companion.get_node("Actor") as NpcActor
	_q = companion.get_character_animator()
	_q_look = _q.get_node("Look") as CharacterLookApplier
	_hide_nameplates()
	_pose(_q, "idle", 0.25)
	var camera := _main.get_node("CameraRig/Camera3D") as Camera3D
	camera.current = true
	await _wait(0.5)
	_save_image("21_companion_game_camera", root.get_texture().get_image())
	_note("Q migration companion: visible %s, source %s, placement %s" % [
		str(companion.is_with_player()), (_q.get_node("Model") as Node3D).scene_file_path,
		str(companion.get_placement_report())])
	await _dialogue_capture(&"q_after_dismissal", "22_companion_live_dialogue")
	await _close_conversation()


func _close_conversation() -> void:
	for attempt in 256:
		if not _dialogue.is_busy():
			return
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
	_failures.append("The evidence conversation did not close within its traversal bound.")


func _save_image(tag: String, image: Image) -> void:
	if image == null or image.is_empty():
		_failures.append("The renderer produced no image for '%s'." % tag)
		return
	var path := "%s/%s.jpg" % [_output, tag]
	var error := image.save_jpg(path, 0.92)
	if error != OK:
		_failures.append("Cannot save capture '%s' (error %d)." % [tag, error])
		return
	_records.append({"file": "%s.jpg" % tag, "width": image.get_width(), "height": image.get_height(),
		"sha256": FileAccess.get_sha256(path), "clip": String(_q.get_animation_player().current_animation)})
	if int(tag.get_slice("_", 0)) <= 12 or tag in ["16_authored_head_turn", "17_gesturing_fingers",
		"18_supplied_pose_preview", "19_supplied_rest_shoulders",
		"21_companion_game_camera", "22_companion_live_dialogue"] or tag in TEXTBOOK_PREVIEWS:
		_previews.append({"name": tag, "image": image})


func _finish_migration() -> void:
	# Original frames are untouched. Reserve whole annotation parts for the book
	# so its small details remain legible without exceeding the 40-part ceiling.
	var book_count := 0
	for entry: Dictionary in _previews:
		if String(entry["name"]) in TEXTBOOK_PREVIEWS:
			book_count += 1
	var other_count := maxi(_previews.size() - book_count, 1)
	var other_share := mini(144000 / other_count,
		((40 - book_count * TEXTBOOK_PREVIEW_PARTS) / other_count) * 4000)
	for entry: Dictionary in _previews:
		var share := TEXTBOOK_PREVIEW_PARTS * 4000 if String(entry["name"]) in TEXTBOOK_PREVIEWS else other_share
		var image := (entry["image"] as Image).duplicate() as Image
		image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		var encoded := ""
		for quality: float in [0.8, 0.65, 0.5, 0.35]:
			encoded = Marshalls.raw_to_base64(image.save_jpg_to_buffer(quality))
			if encoded.length() <= share:
				break
		while encoded.length() > share and image.get_width() > 64:
			var shrink := clampf(sqrt(float(share) / float(encoded.length())) * 0.97, 0.5, 0.85)
			image.resize(int(image.get_width() * shrink), int(image.get_height() * shrink), Image.INTERPOLATE_LANCZOS)
			encoded = Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.4))
		if encoded.is_empty() or encoded.length() > share:
			_failures.append("Cannot relay preview '%s' inside its %d-character budget." % [entry["name"], share])
			continue
		print("QFRAME: %s.jpg %s" % [String(entry["name"]), encoded])
	var metadata := {"phase": _phase, "source_commit": _source_sha,
		"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"frames": _records, "owner_visual_acceptance": "not performed"}
	var file := FileAccess.open("%s/manifest.json" % _output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata, "\t") + "\n")
	for failure: String in _failures:
		print("Q_CAPTURE_FAILURE: %s" % failure)
	print("::notice title=Q capture %s::source %s; engine %s; %d original frames; %s" % [
		_phase, _source_sha, Engine.get_version_info()["string"], _records.size(),
		" | ".join(_failures) if not _failures.is_empty() else "script assertions pass; no owner visual acceptance"])

	print("Q_CAPTURE_RESULT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	if _main != null:
		_main.queue_free()
		await process_frame
		await process_frame
	quit(0 if _failures.is_empty() else 1)
