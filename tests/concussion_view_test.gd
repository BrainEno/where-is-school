extends SceneTree
## The dazed look after a hurt landing (docs/CONCUSSION_VIEW.md): a static postmodern
## paste-up of the world that is strongest at the landing and gone after four minutes of play,
## heavier after a second fall, and cleared by water from the yard tap.
##
## On the real main scene:
##
## 1. **Off by default.** A new game has no `concussion_seconds_left`; the view's layer and
##    sheet are hidden. It is a world filter: group `world_filter`, layer under the outline
##    overlay (and so under the UI), and it never takes the mouse.
## 2. **The landing starts it.** `ConcussionView.begin()` (called by the hurt landing at roof
##    contact) writes `DURATION` (240); the look arrives within a fraction of a second at full
##    strength. It falls fast, then slowly: about half of it is gone after the first minute.
## 3. **Counted in play time.** The remaining time falls with the game clock, the flag holds
##    the whole seconds, and the strength falls with it - never rises.
## 4. **A paused game does not heal.** While the tree is paused nothing changes.
## 5. **Saved like any flag.** Save, clear, load: the same remaining time and the same look.
## 6. **It ends.** At 0 the flag is 0 and nothing is drawn or processed.
## 7. **An art style, not motion.** The shader reads the screen texture (every renderer has
##    it for a canvas item) and has no `TIME`: nothing in it moves.
## 8. **Each room its own paste-up**, changed on entry (behind the black of the change).
## 9. **A second fall is heavier.** `begin(from, true)` writes `HEAVY_SECONDS` and the strength
##    drawn goes above the landing's.
## 10. **Water.** `clear()` (a mouthful or a wash at the yard tap) ends the look at once:
##    the flag is 0 and the view eases out rather than cutting, and stops.
##
## With `-- --capture` (a rendered window; `.github/workflows/concussion-view-capture.yml`)
## it photographs the yard and the alley from the game camera, clear and at several points of
## the fade, into `builds/concussion-view/`, and checks the look changes the picture and
## thins out as it fades.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SHADER := "res://assets/shaders/injury/concussion_collage.gdshader"
const YARD := "res://scenes/locations/playground/playground.tscn"
const ALLEY := "res://scenes/locations/alley/alley.tscn"
const OUT := "res://builds/concussion-view"
## The frames taken per room: after a second fall, at the landing, a minute later, and a
## minute before the end.
const CAPTURE_SECONDS: Array[int] = [300, 240, 180, 60]

var _check := Harness.Checker.new()
var _state: Node = null
var _world: Node = null
var _view: ConcussionView = null
var _host: LocationHost = null
var _player: PlayerController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 200.0, "concussion_view_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	if _state == null or autoloads["save"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	_world = (load(MAIN) as PackedScene).instantiate()
	var sequence := _world.get_node(^"OpeningSequence") as OpeningSequence
	sequence.autostart = false
	root.add_child(_world)
	await _frames(3)
	_view = _world.get_node_or_null(^"ConcussionView") as ConcussionView
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	if not _check.expect(_view != null, "main has no ConcussionView."):
		Harness.finish(self, _check.failures, "")
		return

	Harness.stage = "off by default"
	_check_off("in a new game")
	_check_layering()
	_check_curve()
	_check_shader()
	_check_quiet_flag()

	if "--capture" in OS.get_cmdline_user_args():
		await _capture()
	else:
		await _check_landing_and_countdown()
		await _check_pause()
		await _check_save()
		await _check_end()
		await _check_heavier_and_water()
		await _check_reseed()

	Engine.time_scale = 1.0
	paused = false
	_world.queue_free()
	await _frames(2)
	Harness.clear_session_state(self)
	Harness.finish(
		self,
		_check.failures,
		(
			"the hurt landing's paste-up starts at the contact, fades with play time, stops"
			+ " while paused, survives a save and ends; it is a static world filter."
		)
	)


func _check_off(when: String) -> void:
	var sheet := _view.get_node(^"Sheet") as ColorRect
	_check.expect(
		not _view.visible and not sheet.visible and is_zero_approx(_view.get_daze()),
		"The concussion view is drawn %s." % when
	)
	_check.expect(
		int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)) == 0,
		"concussion_seconds_left is set %s." % when
	)


func _check_layering() -> void:
	var overlay := _world.get_node(^"OutlineOverlay") as CanvasLayer
	var sheet := _view.get_node(^"Sheet") as ColorRect
	_check.expect(_view.is_in_group(&"world_filter"), "The view is not in the world_filter group.")
	_check.expect(
		_view.layer < overlay.layer and _view.layer < 0,
		(
			"The view (layer %d) is not under the outline overlay (layer %d)."
			% [_view.layer, overlay.layer]
		)
	)
	_check.expect(
		sheet.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The concussion sheet takes the mouse."
	)


func _check_curve() -> void:
	_check.expect(
		is_equal_approx(ConcussionView.daze_for(ConcussionView.DURATION), 1.0),
		"The look is not at full strength at the landing."
	)
	_check.expect(is_zero_approx(ConcussionView.daze_for(0.0)), "The look does not end at 0.")
	var last := 2.0
	for step in range(ConcussionView.DURATION, -1, -30):
		var daze := ConcussionView.daze_for(float(step))
		_check.expect(daze <= last, "The look gets stronger as it heals (%d s left)." % step)
		last = daze
	var minute := ConcussionView.daze_for(ConcussionView.DURATION - 60.0)
	_check.expect(
		minute > 0.4 and minute < 0.6, "A minute after the landing the look is at %.2f." % minute
	)
	var halfway := ConcussionView.daze_for(ConcussionView.DURATION / 2.0)
	_check.expect(halfway < 0.35, "Halfway through the look is still at %.2f." % halfway)
	_check.expect(
		(
			is_equal_approx(
				ConcussionView.daze_for(ConcussionView.HEAVY_SECONDS), ConcussionView.HEAVY_DAZE
			)
			and ConcussionView.HEAVY_DAZE > 1.0
		),
		"A second fall is not drawn heavier than the landing."
	)
	for seconds: float in [12.0, 60.0, 150.0, 239.0, 270.0]:
		var back := ConcussionView.seconds_for(ConcussionView.daze_for(seconds))
		_check.expect(
			absf(back - seconds) < 0.5,
			"seconds_for() is not daze_for() reversed at %.0f s." % seconds
		)


func _check_shader() -> void:
	var material := (_view.get_node(^"Sheet") as ColorRect).material as ShaderMaterial
	if not _check.expect(
		material != null and material.shader != null, "The concussion sheet has no shader."
	):
		return
	_check.expect(material.shader.resource_path == SHADER, "The sheet does not use %s." % SHADER)
	var code := material.shader.code
	_check.expect(code.contains("hint_screen_texture"), "The filter does not read the screen.")
	_check.expect(
		code.contains("shader_type canvas_item"), "The filter is not a canvas item shader."
	)
	# Comments may say "no TIME"; only the code counts.
	var bare := RegEx.create_from_string("//[^\\n]*").sub(code, "", true)
	var uses_time := RegEx.create_from_string("\\bTIME\\b").search(bare) != null
	_check.expect(not uses_time, "The filter uses TIME: something in it moves.")


func _check_landing_and_countdown() -> void:
	Harness.stage = "the landing and the countdown"
	# Every announced change of the flag, whatever wrote it. The landing announces once; the
	# countdown's per-second ticks must not announce at all (#348).
	var announced: Array[int] = []
	var listen := func(flag: StringName, _previous: Variant, _value: Variant) -> void:
		if flag == StoryFlags.CONCUSSION_SECONDS_LEFT:
			announced.append(1)
	_state.story_flag_changed.connect(listen)
	ConcussionView.begin(_world)
	_check.expect(
		int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)) == ConcussionView.DURATION,
		"begin() did not write %d seconds." % ConcussionView.DURATION
	)
	await process_frame
	_check.expect(_view.visible, "The look is not drawn after the landing.")
	var arrived := await Harness.wait_until(func() -> bool: return _view.get_daze() > 0.97, 3.0)
	_check.expect(arrived, "The look did not arrive at full strength (%.2f)." % _view.get_daze())
	var before := _view.get_seconds_left()
	var daze_before := _view.get_daze()
	Engine.time_scale = 40.0
	await create_timer(1.5, true, false, true).timeout
	Engine.time_scale = 1.0
	var after := _view.get_seconds_left()
	_check.expect(
		after < before - 20.0,
		"Play time did not count the look down (%.1f -> %.1f)." % [before, after]
	)
	var saved := int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0))
	_check.expect(
		absi(saved - ceili(after)) <= 1,
		"The flag holds %d s while %.1f s are left." % [saved, after]
	)
	_check.expect(_view.get_daze() < daze_before, "The look did not thin out as it was counted.")
	_state.story_flag_changed.disconnect(listen)
	_check.expect(
		announced.size() == 1,
		"The landing announced the flag %d times; only the landing's write should, the countdown's per-second ticks must not (#348)."
			% announced.size()
	)


## `GameState.set_flag_quiet` stores and reads like `set_flag`, and only the announcing
## setter emits. The next announced change reports the quiet value as its previous one, so
## a listener that wakes later still sees what was really there.
func _check_quiet_flag() -> void:
	Harness.stage = "quiet flag writes"
	var probe := &"concussion_quiet_probe"
	var heard: Array[Array] = []
	var listen := func(flag: StringName, previous: Variant, value: Variant) -> void:
		if flag == probe:
			heard.append([previous, value])
	_state.story_flag_changed.connect(listen)
	_state.set_flag_quiet(probe, 5)
	_check.expect(int(_state.get_flag(probe, -1)) == 5, "A quiet write did not store its value.")
	_state.set_flag_quiet(probe, 5)
	_state.set_flag_quiet(probe, 4)
	_check.expect(heard.is_empty(), "A quiet write announced itself: %s" % str(heard))
	_state.set_flag(probe, 9)
	_state.story_flag_changed.disconnect(listen)
	_check.expect(
		heard.size() == 1 and int(heard[0][0]) == 4 and int(heard[0][1]) == 9,
		"The announced write did not report the quiet value as its previous one: %s" % str(heard)
	)
	_check.expect(int(_state.get_flag(probe, -1)) == 9, "The announced write did not store its value.")


func _check_pause() -> void:
	Harness.stage = "paused"
	var before := _view.get_seconds_left()
	paused = true
	await create_timer(0.8, true, false, true).timeout
	var during := _view.get_seconds_left()
	paused = false
	_check.expect(
		is_equal_approx(before, during),
		"The look healed while paused (%.2f -> %.2f)." % [before, during]
	)


func _check_save() -> void:
	Harness.stage = "saved and loaded"
	var save := root.get_node(^"Save")
	var written: Dictionary = save.save_game()
	if not _check.expect(bool(written.get("ok", false)), "Could not save: %s" % str(written)):
		return
	var saved := int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0))
	_state.clear()
	await process_frame
	_check_off("after the story was cleared")
	var loaded: Dictionary = save.load_game()
	_check.expect(bool(loaded.get("ok", false)), "Could not load: %s" % str(loaded))
	await process_frame
	_check.expect(
		absi(ceili(_view.get_seconds_left()) - saved) <= 1 and _view.visible,
		(
			"Loading did not bring back the look (%d s saved, %.1f s now)."
			% [saved, _view.get_seconds_left()]
		)
	)
	_check.expect(
		is_equal_approx(_view.get_daze(), ConcussionView.daze_for(_view.get_seconds_left())),
		"A loaded look arrived again as if it were a landing."
	)
	save.forget_all()


func _check_end() -> void:
	Harness.stage = "the end of the look"
	_state.replace_snapshot({StoryFlags.CONCUSSION_SECONDS_LEFT: 2})
	await process_frame
	_check.expect(_view.visible, "Two seconds before the end the look is gone already.")
	Engine.time_scale = 8.0
	var ended := await Harness.wait_until(
		func() -> bool: return int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, -1)) == 0,
		5.0
	)
	Engine.time_scale = 1.0
	await process_frame
	_check.expect(ended, "The look never reached 0.")
	_check_off("after it ended")
	_check.expect(not _view.is_processing(), "The view still processes with nothing to count.")


func _check_heavier_and_water() -> void:
	Harness.stage = "a second fall, then water"
	ConcussionView.begin(_world)
	await Harness.wait_until(func() -> bool: return _view.get_daze() > 0.97, 3.0)
	ConcussionView.begin(_world, true)
	_check.expect(
		int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)) == ConcussionView.HEAVY_SECONDS,
		"A second fall did not write %d seconds." % ConcussionView.HEAVY_SECONDS
	)
	var heavier := await Harness.wait_until(func() -> bool: return _view.get_daze() > 1.2, 3.0)
	_check.expect(heavier, "The second fall is not heavier (%.2f)." % _view.get_daze())

	var before := _view.get_daze()
	ConcussionView.clear(_world)
	_check.expect(
		int(_state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, -1)) == 0,
		"Water did not clear the flag."
	)
	await process_frame
	_check.expect(
		_view.visible and _view.get_daze() > before * 0.8,
		"The water was a cut: the view vanished on the same frame."
	)
	var washed := await Harness.wait_until(
		func() -> bool: return not _view.visible, ConcussionView.RELIEF_SECONDS + 2.0
	)
	_check.expect(washed, "The view never eased out after the water.")
	_check_off("after the water")
	_check.expect(not _view.is_processing(), "The view still processes after the water.")


func _check_reseed() -> void:
	Harness.stage = "a room change"
	var material := (_view.get_node(^"Sheet") as ColorRect).material as ShaderMaterial
	var before: Variant = material.get_shader_parameter(&"seed")
	_check.expect(
		_host.load_location(YARD, &"FromCorridor", _player, &"playground"), "The yard did not load."
	)
	await process_frame
	var after: Variant = material.get_shader_parameter(&"seed")
	_check.expect(
		before != null and after != null and not is_equal_approx(float(before), float(after)),
		"Entering another room kept the same paste-up (%s -> %s)." % [str(before), str(after)]
	)


# --- Capture ------------------------------------------------------------------


func _capture() -> void:
	Harness.stage = "capture"
	if not _check.expect(
		DisplayServer.get_name() != "headless", "--capture needs a rendered window."
	):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for room: Array in [
		[YARD, &"FromCorridor", &"playground", "yard"],
		[ALLEY, &"FromPlayground", &"alley", "alley"]
	]:
		_state.replace_snapshot({})
		if not _check.expect(
			_host.load_location(room[0], room[1], _player, room[2]), "%s did not load." % room[3]
		):
			continue
		await _frames(30)
		var clear := await _photograph("%s_clear" % room[3])
		var shots: Dictionary = {}
		for seconds: int in CAPTURE_SECONDS:
			_state.replace_snapshot({StoryFlags.CONCUSSION_SECONDS_LEFT: seconds})
			# Hold the clock so each picture is the moment it is named for.
			_view.set_process(false)
			await _frames(6)
			shots[seconds] = await _photograph("%s_%03d" % [room[3], seconds])
		var full := _changed(clear, shots[ConcussionView.DURATION])
		var late := _changed(clear, shots[60])
		print(
			"%s: changed %.2f at the landing, %.2f a minute before the end" % [room[3], full, late]
		)
		_check.expect(
			full > 0.25, "%s: the look barely changes the picture (%.2f)." % [room[3], full]
		)
		_check.expect(
			late < full, "%s: the look did not thin out (%.2f vs %.2f)." % [room[3], late, full]
		)
	_state.replace_snapshot({})


func _photograph(id: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT).path_join(id + ".png")
	_check.expect(image.save_png(path) == OK, "Could not save %s." % path)
	var small := image.duplicate() as Image
	small.resize(
		800, roundi(800.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_LANCZOS
	)
	_check.expect(
		small.save_jpg(path.get_basename() + ".jpg", 0.8) == OK, "Could not save %s's JPEG." % id
	)
	print("%s: %dx%d" % [id, image.get_width(), image.get_height()])
	return image


## The share of sampled pixels that differ noticeably between two frames.
func _changed(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0.0
	var changed := 0
	var total := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += 1
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.09:
				changed += 1
	return float(changed) / float(maxi(total, 1))


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
