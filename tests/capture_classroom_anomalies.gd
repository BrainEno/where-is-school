extends SceneTree
## Captures the real curtain, both roof outcomes, resident, ladder and yard shots, and the
## crouched jump off the closed rear with the hiding that follows (round 12).
## HUD hidden for art review. Fixtures place the player near each starting mark;
## the game drives the transition, character motion, camera and impression shader.
## `classroom_anomaly_test` separately exercises both routes with movement input.
## Run under Xvfb as in .github/workflows/classroom-anomaly-capture.yml.

const Harness = preload("res://tests/test_harness.gd")
const RoofEncounter = preload("res://scenes/locations/playground/roof_encounter.gd")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const OUT_DIR := "res://docs/screenshots/classroom_anomalies"
const LOG_PATH := "res://docs/screenshots/classroom_anomalies/CAPTURE.log"
const INLINE_SIZE := Vector2i(480, 270)
## Four 4000-character parts per frame, even with textured walls. The full PNG is
## not affected. The workflow prioritizes the last (yard detail) frames inline.
const INLINE_BYTES := 12000
const EXPECTED_SHOTS := 25
const PLAYGROUND := "res://scenes/locations/playground/playground.tscn"
## The orientation the roof jump's check adds to the dice (the protagonist's).
const ORIENTATION := 3
const COURT_COMPARE := Vector3(5.5, 0.03, -10.0)
## Game time per real second while the braced drop plays (see the drop in `_run`).
const BRACE_TIME_SCALE := 0.1
const RESIDENT_TIME_SCALE := 0.4
const RESIDENT_CAPTURE_SECONDS := 12.0
## The doorway shot is the yard's first draw after the drop: software Forward+ compiles
## the yard's and the resident's pipelines then and game time stalls with it, so that
## one capture gets a longer real-time window (round 21 added four yard materials).
const FIRST_DRAW_CAPTURE_SECONDS := 28.0
## Real seconds a staged beat may take to wind down before the next step. Software
## Forward+ on a shared runner can stall the roof and resident beats past 20 s, and
## the slip route then started on a locked controller (failed three runs in a row on
## 2026-11-24, passed on the same code later).
const STAGE_WAIT_SECONDS := 60.0

var _failures: Array[String] = []
var _shots: Array[String] = []
var _normal_court: Image
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _interaction: InteractionController = null
var _state: Node = null
var _voices: InnerVoiceDirector = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 600.0, "capture_classroom_anomalies.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var renderer := "%s/%s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()]
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] != renderer:
		_finish(["Expected renderer %s, got %s instead." % [args[0], renderer]])
		return
	print("RENDERER: %s" % renderer)
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
	await _activate(&"window")
	await create_timer(1.05).timeout
	await _shot("02-laundry.png")
	await _settle()
	await _stand(Vector3(-5.8, 0.0, 2.22), Vector3.LEFT)
	await _activate(&"curtain")
	if not await _choose(&"draw"):
		_finish(["Couldn't choose to draw the curtain."])
		return
	await _capture_pose("void_lean", 0.97, "03-void-lean.png")
	await _settle()
	if _host.get_current().location_id != &"classroom" or not _state.get_flag(StoryFlags.CURTAIN_EDGE_HELD, false):
		_finish(["A passed check didn't keep the player upstairs."])
		return
	await _shot("04-edge-held.png")
	await _activate(&"curtain")
	# The braced drop is a 0.84 s clip that starts as the yard is first drawn. On software
	# Forward+ that first draw can stall one frame for longer than the clip's remaining
	# window (the tween then jumps to its end), so the drop plays in slow time until the
	# frame is taken. The wait below counts real time, hence the longer limit.
	Engine.time_scale = BRACE_TIME_SCALE
	if not await _choose(&"step"):
		Engine.time_scale = 1.0
		_finish(["Couldn't choose to drop after a passed check."])
		return
	await _capture_pose("roof_brace", 0.34, "05-roof-brace.png", -INF, INF, 60.0)
	# Still the first draw of the resident's doorway shot. Give the renderer more
	# frames over the same threshold crossing, with the same budget in game time.
	Engine.time_scale = RESIDENT_TIME_SCALE
	await _capture_resident("19-collector-unfiltered.png", &"on_threshold",
		FIRST_DRAW_CAPTURE_SECONDS / RESIDENT_TIME_SCALE)
	Engine.time_scale = 1.0
	await _settle()
	await _stand(COURT_COMPARE, Vector3.LEFT)
	await _shot("15-court-normal.png")
	_state.clear()
	_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	if not _seed_balance(false) or not _host.load_location(CLASSROOM, &"FromCorridor", _player):
		_finish(["Couldn't load the classroom for the slip route."])
		return
	await _stand(Vector3(-5.83, 0.0, 2.16), Vector3.LEFT)
	await _activate(&"curtain")
	if not await _choose(&"draw"):
		_finish(["Couldn't choose to draw the curtain on the slip route."])
		return
	await _capture_pose("void_slip", 0.45, "06-slip.png")
	await _capture_pose("roof_impact", 0.27, "07-roof-impact.png")
	await _capture_resident("20-bedding-reaction.png", &"reclined")
	await _capture_resident("17-resident-wakes.png", &"sitting_up")
	await _capture_resident("18-resident-steps-out.png", &"on_threshold")
	await _capture_resident("21-resident-looks-round.png", &"looking_round")
	await _settle()
	var container := _host.get_current().get_node_or_null(^"ContainerBody") as Node3D
	if container == null or not _state.get_flag(StoryFlags.CURTAIN_LANDING_INJURED, false):
		_finish(["The failed check didn't produce an injured landing."])
		return
	await _stand(COURT_COMPARE, Vector3.LEFT)
	await _shot("16-court-misprint.png")
	var mark := container.get_node(^"Ladder/RoofMark") as Marker3D
	await _stand(mark.global_position, Vector3.BACK)
	await _activate(&"pg_container_ladder")
	# The resident is in his doorway, so the ladder asks first (round 8): take the ladder.
	if not await _choose(&"ladder"):
		_finish(["The roof ladder did not offer the ladder while the resident watched."])
		return
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
	await _stand(Vector3(4.8, 0.03, -13.45), Vector3.FORWARD)  # round 20: the shed moved north-east
	await _focus_shot(&"pg_shed_door", "14-equipment-shed.png")
	await _capture_rear_jump()
	_finish(_failures)


## The yard again from the roof, the resident in his doorway: jump. The bent-over creep to
## the closed rear, the drop, and - the landing unheard - the player's own crouched walk
## while he searches.
func _capture_rear_jump() -> void:
	if not _host.load_location(PLAYGROUND, RoofEncounter.ROOF_SPAWN, _player, &"playground"):
		_failures.append("Couldn't load the yard on the roof for the jump.")
		return
	await create_timer(0.3).timeout
	var container := _host.get_current().get_node(^"ContainerBody") as Node3D
	var stage := _host.get_current().get_node(^"RoofEncounter") as RoofEncounter
	await _stand((container.get_node(^"Ladder/RoofMark") as Marker3D).global_position, Vector3.BACK)
	var seeded := false
	for seed_value in 400:
		var resolver := CheckResolver.new(seed_value)
		if resolver.dice_total_for("pg_roof_jump/prj_check") + ORIENTATION >= 10:
			_dialogue.set_check_resolver(resolver)
			seeded = true
			break
	await _activate(&"pg_container_ladder")
	if not seeded or not await _choose(&"jump"):
		_failures.append("The roof ladder did not offer the jump while the resident watched.")
		return
	# Review framing only: the yard camera is far from a figure bent over on the roof.
	var rig := _player.camera_rig
	var close := CameraShot.new()
	close.subject_mix = 1.0
	close.distance_scale = 0.7
	close.height_scale = 0.8
	close.yaw_degrees = 20.0
	close.fov = 40.0
	await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return not _dialogue.is_busy()
	, 10.0)
	rig.focus_on(_player, close)
	await create_timer(0.5).timeout
	await _capture_pose("crouch_walk", 0.0, "22-roof-creep.png", 2.3, 3.2)
	rig.release_focus()
	await _capture_pose("void_step", 0.55, "23-rear-drop.png")
	if not await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return stage.phase == RoofEncounter.Phase.SEARCHING and _player.is_control_enabled()
	, 25.0):
		_failures.append("The resident never searched with the player in control.")
		return
	# Review only: lift the (heavier) dazed look so the crouched walk can be seen.
	ConcussionView.clear(_main)
	rig.focus_on(_player, close)
	await create_timer(ConcussionView.RELIEF_SECONDS + 0.3).timeout
	_player.set_touch_move(Vector2(0.0, -1.0))
	await _capture_pose("crouch_walk", 0.0, "24-hiding-crouch.png", -INF, 0.4)
	_player.set_touch_move(Vector2.ZERO)
	rig.release_focus()
	# End the beat before exit, so nothing is left running: step out in front of him (a
	# software renderer is too slow to sit out the whole search) and let him stop the
	# protagonist.
	Engine.time_scale = 4.0
	var actor := stage.get_node(^"Collector") as NpcActor
	if not await Harness.wait_until(func() -> bool:
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		if stage.phase == RoofEncounter.Phase.SEARCHING and _player.is_control_enabled():
			var ahead := actor.global_position + actor.get_facing_direction() * 2.6
			var local := container.to_local(ahead)
			if absf(local.x) > 3.4 or absf(local.z) > 1.6:
				_player.teleport(Transform3D(Basis(), Vector3(ahead.x, actor.global_position.y, ahead.z)))
		return not _sequence.is_beat_active() and not _dialogue.is_busy()
	, 60.0):
		_failures.append("The jump's beat never ended after the search.")
	Engine.time_scale = 1.0


func _focus_shot(id: StringName, frame: String) -> void:
	# Still dazed from the hurt landing, the tap offers water (round 8): drink, and
	# photograph the clear yard after it (round 12: a mouthful clears the look).
	var dazed := id == &"pg_tap" and int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)) > 0
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
	if dazed and not await _choose(&"drink"):
		_failures.append("The dazed tap did not offer a mouthful.")
		return
	await _settle()
	if dazed:
		await create_timer(ConcussionView.RELIEF_SECONDS + 0.4).timeout
		await _shot("13b-tap-drunk.png")


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
	# A staged beat that is still winding down (on software Forward+ the roof and resident
	# beats run slowly) keeps the controller off, and it then ignores the request outright.
	var wait := STAGE_WAIT_SECONDS
	if not await Harness.wait_until(func() -> bool: return _interaction.is_enabled(), wait):
		_failures.append("The interaction controller was still off when '%s' was used." % id)
	if not target.can_interact():
		_failures.append("'%s' could not be used when the capture activated it." % id)
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


func _capture_pose(
	clip: String, progress: float, name: String, low: float = -INF, high: float = INF, limit: float = 20.0
) -> void:
	var animator := _player.get_character_animator()
	if not await Harness.wait_until(func() -> bool:
		if animator.get_current_clip() == clip and animator.get_action_progress() >= progress \
			and _player.global_position.y >= low and _player.global_position.y <= high:
			return true
		if _dialogue.is_busy() and not _dialogue.has_pending_choices():
			_dialogue.advance_presentation()
		return false
	, limit):
		_failures.append("The game did not reach '%s' for %s." % [clip, name])
		return
	await _shot(name)


func _capture_resident(name: String, moment: StringName, limit: float = RESIDENT_CAPTURE_SECONDS) -> void:
	# Do not match the pose before a draw and then save a later frame: the walk and
	# the camera can advance between the process tick and the render.
	var deadline := Time.get_ticks_msec() + int(limit * 1000.0)
	var last := "no roof encounter"
	var saw_pose := false
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var room := _host.get_current()
		var stage := room.get_node_or_null(^"RoofEncounter") as RoofEncounter if room != null else null
		if stage == null:
			continue
		var actor := stage.get_node(^"Collector") as NpcActor
		var head := actor.get_node(^"Visual/Hip/Trunk/Head") as Node3D
		var rig := _player.camera_rig
		var camera := rig.camera
		var focused := rig.get_focus_subject() == stage.get_node(^"WakeFrame") and rig.get_frame_weight() >= 0.96
		var in_view := camera.is_position_in_frustum(head.global_position) \
			and camera.is_position_in_frustum(actor.global_position)
		last = "phase=%d, local=%s, head_y=%.3f, framed=%s, in_view=%s" % [
			stage.phase, str(actor.position), head.global_position.y, focused, in_view,
		]
		var matches := false
		match moment:
			&"reclined":
				matches = stage.phase == RoofEncounter.Phase.WAKING and head.global_position.y < 0.67
			&"sitting_up":
				matches = stage.phase == RoofEncounter.Phase.WAKING \
					and head.global_position.y > 0.99 and head.global_position.y < 1.39
			&"on_threshold":
				matches = stage.phase == RoofEncounter.Phase.WALKING_OUT \
					and actor.position.x >= 3.18 and actor.position.x <= 3.72
			&"outside":
				matches = stage.phase == RoofEncounter.Phase.OUTSIDE
			&"looking_round":
				matches = stage.phase == RoofEncounter.Phase.WALKING_OUT \
					and actor.position.distance_to((stage.get_node(^"ExitRoute/Doorstep") as Node3D).position) < 0.05 \
					and absf(head.rotation_degrees.y) > 30.0
		saw_pose = saw_pose or matches
		if matches and focused and in_view:
			print("RESIDENT_FRAME: %s | %s" % [name, last])
			_save_shot(name)
			return
	_failures.append("The resident's motion wasn't in frame for %s (pose seen=%s; last %s)." % [
		name, saw_pose, last,
	])


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
	, STAGE_WAIT_SECONDS):
		_failures.append("The capture waited on a busy stage (%s)." % _stage_state())


## What still holds the stage, for the failure line: the artifact log is not always at hand.
func _stage_state() -> String:
	var state := PackedStringArray()
	state.append("dialogue busy" if _dialogue.is_busy() else "dialogue idle")
	if _dialogue.has_pending_choices():
		state.append("choices waiting")
	if _sequence.is_beat_active():
		state.append("beat active")
	state.append("%d voices pending" % _voices.pending_count())
	if _voices.is_firing():
		state.append("voice firing")
	return ", ".join(state)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_save_shot(name)


func _save_shot(name: String) -> void:
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
	if name in ["15-court-normal.png", "16-court-misprint.png"]:
		_compare_court(image, name)
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


## A valid shader resource isn't proof it rendered. Measure the changed pixels
## looking across the same real court, not a synthetic full-screen test pattern.
func _compare_court(image: Image, name: String) -> void:
	var sample := image.duplicate() as Image
	sample.resize(128, 72, Image.INTERPOLATE_BILINEAR)
	if name == "15-court-normal.png":
		_normal_court = sample
		return
	if _normal_court == null:
		_failures.append("No clean court frame for the same-angle comparison.")
		return
	var changed := 0
	var total := 0.0
	for y in sample.get_height():
		for x in sample.get_width():
			var a := _normal_court.get_pixel(x, y)
			var b := sample.get_pixel(x, y)
			var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			total += delta
			if delta > 0.05:
				changed += 1
	var count := float(sample.get_width() * sample.get_height())
	var coverage := changed / count
	var mean := total / count
	print("COURT_PRINT: delta %.3f across frame, %.1f%% affected" % [mean, coverage * 100.0])
	if coverage < 0.50 or mean < 0.07:
		_failures.append("The injury did not change the medium across the live court.")


func _finish(failures: Array) -> void:
	# What went wrong earlier on the route usually explains the step that finally failed.
	if failures != _failures:
		failures = _failures + failures
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
