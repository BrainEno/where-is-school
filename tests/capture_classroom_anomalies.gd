extends SceneTree
## Captures the real curtain, drop, impact, ladder and yard inspection shots, with
## the HUD hidden for art review. The fixture places the player near each route's start;
## the game drives character travel, body poses, lighting and camera. `classroom_anomaly_test`
## separately exercises both routes with ground/roof movement input and checks state.
## Run with Xvfb/OpenGL as in .github/workflows/classroom-anomaly-capture.yml.

const Harness = preload("res://tests/test_harness.gd")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const OUT_DIR := "res://docs/screenshots/classroom_anomalies"
const LOG_PATH := "res://docs/screenshots/classroom_anomalies/CAPTURE.log"
const INLINE_SIZE := Vector2i(480, 270)
## Four 4000-character parts per frame, even with textured walls. The full PNG is
## not affected. The workflow prioritizes the last (yard detail) frames inline.
const INLINE_BYTES := 12000
const EXPECTED_SHOTS := 14

var _failures: Array[String] = []
var _shots: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _interaction: InteractionController = null
var _state: Node = null
var _voices: InnerVoiceDirector = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_classroom_anomalies.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	_main = packed.instantiate()
	_sequence = _main.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(_main)
	_host = _main.get_node(^"LocationHost") as LocationHost
	_player = _main.get_node(^"Player") as PlayerController
	_dialogue = _main.get_node(^"DialogueController") as DialogueController
	_voices = _main.get_node(^"InnerVoiceDirector") as InnerVoiceDirector
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	(_main.get_node(^"GameUI") as CanvasLayer).hide()
	_player.set_wake_pose(0.0)
	_player.set_camera_roll(0.0)
	_sequence.allow_player_control()
	if _host.get_current() == null or _host.get_current().location_id != &"classroom" or not _seed_balance(true):
		_finish(["Couldn't set up the safe classroom route."])
		return

	await _stand(Vector3(-5.8, 0.0, -0.8), Vector3.LEFT)
	await _shot("01-windows.png")
	await _stand(Vector3(-5.95, 0.0, -2.35), Vector3.LEFT)
	_activate(&"window")
	await create_timer(1.05).timeout
	await _shot("02-laundry.png")
	await _settle()
	await _stand(Vector3(-5.8, 0.0, 2.22), Vector3.LEFT)
	_activate(&"curtain")
	if not await _choose(&"draw"):
		_finish(["Couldn't choose to draw the curtain."])
		return
	await _capture_pose("void_lean", 0.97, "03-void-lean.png")
	await _settle()
	if _host.get_current().location_id != &"classroom" or not _state.get_flag(StoryFlags.CURTAIN_EDGE_HELD, false):
		_finish(["A passed check didn't keep the player upstairs."])
		return
	await _shot("04-edge-held.png")
	_activate(&"curtain")
	if not await _choose(&"step"):
		_finish(["Couldn't choose to drop after a passed check."])
		return
	await _capture_pose("roof_brace", 0.34, "05-roof-brace.png")
	await _settle()
	_state.clear()
	_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	if not _seed_balance(false) or not _host.load_location(CLASSROOM, &"FromCorridor", _player):
		_finish(["Couldn't load the classroom for the slip route."])
		return
	await _stand(Vector3(-5.83, 0.0, 2.16), Vector3.LEFT)
	_activate(&"curtain")
	if not await _choose(&"draw"):
		_finish(["Couldn't choose to draw the curtain on the slip route."])
		return
	await _capture_pose("void_slip", 0.45, "06-slip.png")
	await _capture_pose("roof_impact", 0.27, "07-roof-impact.png")
	await _settle()
	var container := _host.get_current().get_node_or_null(^"ContainerBody") as Node3D
	if container == null or not _state.get_flag(StoryFlags.CURTAIN_LANDING_INJURED, false):
		_finish(["The failed check didn't produce an injured landing."])
		return
	var mark := container.get_node(^"Ladder/RoofMark") as Marker3D
	await _stand(mark.global_position, Vector3.BACK)
	_activate(&"pg_container_ladder")
	await _capture_pose("ladder_left", 0.72, "08-ladder.png", 1.35, 1.88)
	await _settle()
	if _player.global_position.y > 0.10:
		_finish(["The protagonist is still above the yard after using the ladder."])
		return
	# Same review convention as hiding GameUI: do not let a billboard label hide a fitting.
	(_player.get_node(^"Nameplate") as Label3D).hide()
	await _stand(container.to_global(Vector3(4.15, 0.02, 0.12)), Vector3.LEFT)
	await _shot("09-open-cabin.png")
	await _focus_shot(&"pg_container_look", "10-cabin-focus.png")
	await _stand(container.to_global(Vector3(2.67, 0.23, -0.21)), Vector3.LEFT)
	await _focus_shot(&"pg_cabin_papers_look", "11-cabin-papers.png")
	await _stand(Vector3(10.03, 0.03, 3.66), Vector3.RIGHT)
	await _focus_shot(&"pg_bench_look", "12-noodle-wrapper.png")
	await _stand(Vector3(-4.67, 0.03, 14.42), Vector3.LEFT)
	await _focus_shot(&"pg_tap", "13-tap-and-drain.png")
	await _stand(Vector3(-12.5, 0.03, -4.4), Vector3.LEFT)
	await _focus_shot(&"pg_shed_door", "14-equipment-shed.png")
	_finish(_failures)


func _focus_shot(id: StringName, frame: String) -> void:
	_activate(id)
	var rig := _player.camera_rig
	if not await Harness.wait_until(func() -> bool:
		var focus := rig.get_focus_subject()
		return focus != null and focus.interact_id == id and rig.get_focus_weight() > 0.97
	, 6.0):
		_failures.append("%s never reached its live focus shot." % id)
	else:
		await _shot(frame)
	# Only photograph the shut facade. Do not start a visible roll with the HUD hidden.
	if id == &"pg_shed_door" and not await _choose(&"leave"):
		_failures.append("The shed inspection did not offer its unchanged leave choice.")
		return
	await _settle()


func _seed_balance(passed: bool) -> bool:
	for seed_value in 100:
		var resolver := CheckResolver.new(seed_value)
		if (resolver.dice_total_for("classroom_curtain_void/cv_balance_check") + 3 >= 10) == passed:
			_dialogue.set_check_resolver(resolver)
			return true
	return false


func _activate(id: StringName) -> void:
	var target := _host.get_current().find_interactable(id)
	if target == null:
		_failures.append("The capture couldn't find '%s'." % id)
		return
	_interaction.request_activation(target)


func _choose(id: StringName) -> bool:
	if not await Harness.wait_until(func() -> bool:
		if _dialogue.has_pending_choices():
			return true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		return false
	, 16.0):
		return false
	var index := _dialogue.get_runtime().get_available_choice_ids().find(id)
	if index < 0:
		return false
	_dialogue.select_choice(index)
	return true


func _capture_pose(clip: String, progress: float, name: String, low: float = -INF, high: float = INF) -> void:
	var animator := _player.get_character_animator()
	if not await Harness.wait_until(func() -> bool:
		if animator.get_current_clip() == clip and animator.get_action_progress() >= progress \
			and _player.global_position.y >= low and _player.global_position.y <= high:
			return true
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return false
	, 20.0):
		_failures.append("The game did not reach '%s' for %s." % [clip, name])
		return
	await _shot(name)


func _stand(where: Vector3, facing: Vector3) -> void:
	_player.teleport(Transform3D(Basis(), where))
	_player.face_toward(facing)
	await create_timer(0.65).timeout # camera/occluder settling at normal story speed


func _settle() -> void:
	if not await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy() and not _sequence.is_beat_active() \
			and _voices.pending_count() == 0 and not _voices.is_firing()
	, 20.0):
		_failures.append("The capture waited on a busy stage.")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("The %s frame came back empty." % name)
		return
	var path := "%s/%s" % [OUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [path, error])
		return
	_shots.append(name)
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(INLINE_SIZE.x, INLINE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	# A frame that is almost all one dark value is a cover, not the room: fail it, so a
	# black capture cannot pass as evidence.
	var total := 0.0
	var samples := 0
	for y in range(0, small.get_height(), 9):
		for x in range(0, small.get_width(), 9):
			total += small.get_pixel(x, y).get_luminance()
			samples += 1
	var mean := total / maxf(1.0, float(samples))
	if mean < 0.06:
		_failures.append("The %s frame is black (mean luminance %.3f)." % [name, mean])
	var quality := 0.62
	var jpeg := small.save_jpg_to_buffer(quality)
	while jpeg.size() > INLINE_BYTES:
		quality -= 0.08
		if quality < 0.27:
			small.resize(small.get_width() * 3 / 4, small.get_height() * 3 / 4, Image.INTERPOLATE_BILINEAR)
			quality = 0.62
		jpeg = small.save_jpg_to_buffer(quality)
	var encoded := Marshalls.raw_to_base64(jpeg)
	print("CROP: %s %s" % [name.get_basename() + ".jpg", encoded])
	print("SHOT %s %dx%d" % [name, image.get_width(), image.get_height()])


func _finish(failures: Array) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		for name in _shots:
			file.store_line("SHOT: %s" % name)
		for failure in failures:
			file.store_line("FAILURE: %s" % failure)
		if failures.is_empty():
			file.store_line("RESULT: %d anomaly frames captured." % _shots.size())
		file.close()
	if failures.is_empty() and _shots.size() == EXPECTED_SHOTS:
		print("PASS: captured %d anomaly frames." % _shots.size())
		quit(0)
		return
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
