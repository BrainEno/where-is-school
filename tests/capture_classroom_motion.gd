extends SceneTree
## Photograph the live classroom and its real interaction route. The fixed side camera
## is only for comparison/evidence: no pose, furniture, light or story data is edited.

const Harness = preload("res://tests/test_harness.gd")
const APPROACH := Vector3(-0.75, 0, 2.15)
const CAMERA_AT := Vector3(0.65, 1.46, 2.48)
const LOOK_AT := Vector3(-1.53, 0.84, 1.95)

var _out := "build/classroom-motion"
var _failures: Array[String] = []
var _main: Node3D
var _player: PlayerController
var _sequence: OpeningSequence
var _interaction: InteractionController
var _room: LocationRoot
var _chair: Node3D
var _review: Camera3D


func _initialize() -> void:
	Harness.arm_watchdog(self, 110.0, "capture_classroom_motion.gd")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless" \
			or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		Harness.finish(self, ["Classroom motion evidence requires a live Compatibility renderer."], "")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out)) != OK:
		Harness.finish(self, ["Cannot create the evidence directory."], "")
		return
	print("MOTION_DISPLAY engine=%s display=%s renderer=%s adapter=%s" % [
		Engine.get_version_info().string, DisplayServer.get_name(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
	])
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var loc := root.get_node_or_null("Loc")
	if loc != null:
		loc.set_locale("zh-CN")
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_main)
	_player = _sequence.get_player()
	_room = (_main.get_node(^"LocationHost") as LocationHost).get_current()
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_chair = _room.get_node(^"Furniture/DeskB2/Chair") as Node3D
	var seat := _room.find_interactable(&"chair_sit")
	var bag := _room.find_interactable(&"schoolbag")
	if seat == null or bag == null:
		Harness.finish(self, ["The real chair or schoolbag interaction is missing."], "")
		return
	_main.get_node(^"InnerVoiceDirector").set_process(false)
	(_main.get_node(^"GameUI") as GameUI).fade.set_clear()
	_player.settle_wake_seated_pose(0.0)
	_player.set_camera_roll(0.0)
	_sequence.allow_player_control()
	await create_timer(0.26).timeout

	_review = Camera3D.new()
	_main.add_child(_review)
	_review.position = CAMERA_AT
	_review.look_at(LOOK_AT)
	_review.fov = 53.0
	_review.current = true
	_pose("wake")
	await _shot("01_wake")

	_interaction.request_activation(seat)
	if await _wait(_player.is_getting_up, "standing to begin"):
		# This opportunity is measured on the action, not after an arbitrary number of renders.
		var animator := _player.get_character_animator()
		if await _wait(func() -> bool: return animator.get_action_progress() >= 0.42, "rise"):
			await _shot("02_rising")
	await _wait(func() -> bool: return not _sequence.is_beat_active(), "stand-up to finish")
	_pose("standing")

	# Place the body at a legitimate approach position, NOT on the seat. Both variants
	# activate the same input endpoint that mouse, touch and E finish through.
	_player.teleport(Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), APPROACH))
	_player.face_toward(Vector3.LEFT)
	await physics_frame
	await physics_frame
	_interaction.request_activation(seat)
	await _wait(_sequence.is_beat_active, "sit request to be accepted")
	await _wait(func() -> bool: return not _sequence.is_beat_active(), "sit request to finish")
	_pose("returned from aisle")
	await _shot("03_returned_from_aisle")

	_main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "captured the live classroom wake, rise and return from the aisle.")


func _pose(label: String) -> void:
	var animator := _player.get_character_animator()
	var skeleton := animator.get_skeleton()
	var resolved: Dictionary = animator.get_bind_report()["resolved"]
	var points := []
	for key: String in ["hips", "thigh.L", "shin.L", "foot.L", "foot.R"]:
		var id := skeleton.find_bone(String(resolved.get(key, "")))
		if id >= 0:
			points.append("%s=%s" % [key, skeleton.to_global(skeleton.get_bone_global_pose(id).origin)])
	var offset := _chair.to_local(_player.global_position)
	print("MOTION_POSE %s body=%s facing=%s chair_offset=%s %s" % [
		label, _player.global_position, _player.get_facing_direction(), offset, " ".join(points),
	])


func _wait(predicate: Callable, what: String) -> bool:
	if await Harness.wait_until(predicate, 8.0):
		return true
	_failures.append("Timed out waiting for %s." % what)
	return false


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size().x < 640:
		_failures.append("No rendered pixels for %s." % file_name)
		return
	if image.save_png(_out.path_join(file_name + ".png")) != OK:
		_failures.append("Could not save %s." % file_name)
	# A small, lossily encoded preview of this exact viewport lets the bot review the
	# original PNG without a browser signed in to the artifact store.
	image.resize(520, 293, Image.INTERPOLATE_LANCZOS)
	if image.save_jpg(_out.path_join(file_name + ".jpg"), 0.62) != OK:
		_failures.append("Could not save a preview of %s." % file_name)
