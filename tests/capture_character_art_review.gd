extends "res://tests/capture_character_art.gd"
## Photographs the character art review directions (issue #188) in the running game.
##
##   xvfb-run godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_character_art_review.gd -- --group=review_bodies
##
## Everything about booting and photographing is the production character art capture's
## (`capture_character_art.gd`, inherited and not changed): `main.tscn` played to the end of
## the opening conversation, the real classroom / corridor / street with their own lights,
## the real wrappers and animation driver, and the game's own camera rig for the gameplay
## frames. What this adds is *what* is on the characters, put on and taken off at run time by
## `scenes/dev/character_art_review/review_stage.gd`:
##
##   C      the shipped look and the production pose, untouched (the baseline)
##   C+A    the shipped look with experiment A: the review pose overlay and softened hair
##   D1     experiment A + "stage light"
##   D2     experiment A + "charcoal and oil pastel"
##   D3     experiment A + "expressionist colour planes"
##
## Every sheet has these five in this order, left to right (a sheet with fewer columns says so
## in its name). Groups, one per CI job:
##   review_bodies    head to feet, three-quarter, both characters; and C vs C+A from the
##                    front and the side (the pose on its own)
##   review_faces     face close-ups; and a dialogue two-shot, Q close, both talking
##   review_gameplay  the game camera with both standing, and with both mid-walk
##   review_light     the game camera and a close two-shot in the corridor and the street
##
## The sheets are printed as `ARTSHEET:` lines and the measurements as `ARTNOTE:` lines, as in
## the production capture; files go to the same (uncommitted) artifact directory.

const ReviewStage = preload("res://scenes/dev/character_art_review/review_stage.gd")

const VARIANTS: Array[String] = ["C", "C+A", "D1", "D2", "D3"]
## Q at conversation distance: about 0.84 m from the protagonist, both in front of the board
## (the clear floor the production capture's own spots use), turned towards each other so the
## camera down the aisle sees them close to profile. The production capture keeps them apart;
## a conversation does not.
const TALK_PROTAGONIST := Vector3(-1.25, 0.0, -2.6)
const TALK_Q := Vector3(-0.43, 0.0, -2.8)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			_group = argument.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_note("review group %s, started %s" % [_group, Time.get_datetime_string_from_system()])
	if not await _boot():
		await _finish()
		return
	await _stand_up()
	match _group:
		"review_bodies":
			await _review_bodies()
		"review_faces":
			await _review_faces()
		"review_gameplay":
			await _review_gameplay()
		"review_light":
			await _review_light()
		_:
			_failures.append("Unknown group '%s'." % _group)
	_variant("C")
	await _finish()


# --- variants -----------------------------------------------------------------


## Puts one of `VARIANTS` on both characters and checks that it took.
func _variant(variant: String) -> void:
	var direction := "c" if variant.begins_with("C") else variant.to_lower()
	var posed := variant != "C"
	var report := ReviewStage.apply(_protagonist, _q, direction, posed, posed)
	for who: String in ["protagonist", "q"]:
		var look: Dictionary = report[who]
		if look.has("error"):
			_failures.append("%s %s: %s" % [variant, who, String(look["error"])])
			continue
		var kept: Array = look.get("kept", [])
		if not kept.is_empty():
			_failures.append("%s kept GLB materials on %s: %s" % [variant, who, str(kept)])
	if posed and int(report["hair_vertices_moved"]) == 0:
		_failures.append("%s: the protagonist's hair was not softened." % variant)
	await _wait(0.5)
	_hide_nameplates()


func _note_variant(variant: String) -> void:
	var parts: PackedStringArray = []
	for pair: Array in [["protagonist", _protagonist], ["q", _q]]:
		var pose := ReviewStage.get_pose(pair[1])
		var applied: Dictionary = pose.call("get_last_applied") if pose != null else {}
		var biggest := ""
		var most := 0.0
		for bone: String in applied:
			if float(applied[bone]) > most:
				most = float(applied[bone])
				biggest = bone
		parts.append("%s %d bones turned (largest %s %.1f°)" % [pair[0], applied.size(), biggest, most])
	_note("%s: %s" % [variant, ", ".join(parts)])


func _set_partners(talking: bool) -> void:
	for pair: Array in [[_protagonist, _q], [_q, _protagonist]]:
		var pose := ReviewStage.get_pose(pair[0])
		if pose != null:
			pose.set("partner", (pair[1] as Node3D) if talking else null)


# --- groups -------------------------------------------------------------------


func _review_bodies() -> void:
	await _stage_classroom()
	var protagonist_panels: Array[Image] = []
	var q_panels: Array[Image] = []
	for variant in VARIANTS:
		await _variant(variant)
		await _solo(_protagonist, 25.0)
		await _wait(0.6)
		protagonist_panels.append(await _body_panel(_protagonist, _tag("protagonist_body", variant), Vector2i(220, 360)))
		await _solo(_q, -25.0)
		await _wait(0.6)
		q_panels.append(await _body_panel(_q, _tag("q_body", variant), Vector2i(220, 360)))
		_note_variant(variant)
	protagonist_panels.append_array(q_panels)
	_sheet("review_bodies_C_CA_D1_D2_D3_protagonist_then_q", protagonist_panels, 5)
	# The pose alone: C against C+A, front and side, idle.
	var pose_panels: Array[Image] = []
	for pair: Array in [["protagonist", _protagonist], ["q", _q]]:
		var animator: CharacterVisualAnimation = pair[1]
		for facing in [0.0, 90.0]:
			for variant: String in ["C", "C+A"]:
				await _variant(variant)
				await _solo(animator, facing)
				await _wait(0.6)
				var tag := "%s_%d" % [_tag(String(pair[0]) + "_pose", variant), int(facing)]
				pose_panels.append(await _body_panel(animator, tag, Vector2i(170, 290)))
				_note_posture(tag, animator)
	_sheet("review_pose_front_C_CA_side_C_CA_protagonist_then_q", pose_panels, 4)


func _review_faces() -> void:
	await _stage_classroom()
	var faces: Array[Image] = []
	var q_faces: Array[Image] = []
	for variant in VARIANTS:
		await _variant(variant)
		await _solo(_protagonist, 18.0)
		await _wait(0.5)
		faces.append(await _low_face_panel(_protagonist, _tag("protagonist_face", variant)))
		await _solo(_q, -18.0)
		await _wait(0.5)
		q_faces.append(await _low_face_panel(_q, _tag("q_face", variant)))
	faces.append_array(q_faces)
	_sheet("review_faces_C_CA_D1_D2_D3_protagonist_then_q", faces, 5)
	# A conversation: the two close and turned to each other, the pose's `converse` on.
	var talk: Array[Image] = []
	for variant in VARIANTS:
		await _variant(variant)
		await _stage_talk()
		_set_partners(variant != "C")
		await _wait(1.2)
		talk.append(await _talk_panel(_tag("talk", variant)))
		await _measure_close_cost(variant)
		_note_variant(variant)
		_set_partners(false)
	_sheet("review_talk_C_CA_D1_D2_D3", talk, 5)


func _review_gameplay() -> void:
	await _stage_classroom()
	var standing: Array[Image] = []
	for variant in VARIANTS:
		await _variant(variant)
		await _place_pair(PAIR_PROTAGONIST, PAIR_Q, 30.0)
		standing.append(await _gameplay_panel(_tag("gameplay_idle", variant), Vector2i(300, 260)))
		_measure_cost("gameplay camera, %s" % variant)
	_sheet("review_gameplay_idle_C_CA_D1_D2_D3", standing, 5)
	# Mid-walk: both report a walking velocity (the clip plays in place; the camera holds).
	var walking: Array[Image] = []
	for variant in VARIANTS:
		await _variant(variant)
		await _place_pair(PAIR_PROTAGONIST, PAIR_Q, 30.0)
		for animator: CharacterVisualAnimation in [_protagonist, _q]:
			animator.report_velocity(_forward(animator) * 1.1)
		await _wait(1.6)
		walking.append(await _gameplay_panel(_tag("gameplay_walk", variant), Vector2i(300, 260)))
		for animator: CharacterVisualAnimation in [_protagonist, _q]:
			_note("%s %s: state %s, clip %s" % [variant, animator.name, animator.get_locomotion_state(), animator.get_current_clip()])
			animator.clear_reported_velocity()
		await _wait(0.4)
	_sheet("review_gameplay_walk_C_CA_D1_D2_D3", walking, 5)


func _review_light() -> void:
	var gameplay: Array[Image] = []
	var close: Array[Image] = []
	for stop: Array in [[CORRIDOR, &"FromClassroom", "corridor"], [STREET, &"FromCorridor", "street"]]:
		ReviewStage.restore(_protagonist, "protagonist")
		if not _host.load_location(String(stop[0]), StringName(stop[1]), _player):
			_failures.append("Could not load %s." % String(stop[0]))
			continue
		await _wait(1.0)
		_place_q_beside_player()
		await _wait(0.8)
		for variant in VARIANTS:
			await _variant(variant)
			gameplay.append(await _gameplay_panel(_tag("light_%s" % stop[2], variant), Vector2i(260, 220)))
			close.append(await _pair_panel(_tag("light_%s_close" % stop[2], variant)))
	_sheet("review_light_gameplay_C_CA_D1_D2_D3_corridor_then_street", gameplay, 5)
	_sheet("review_light_close_C_CA_D1_D2_D3_corridor_then_street", close, 5)


# --- staging ------------------------------------------------------------------


## The opening leaves the protagonist seated at his desk until the player's first deliberate
## move (`PlayerController._wake_seated`); the production capture teleports him without that
## move, so he holds `sit_idle` wherever he is placed. Here he is stood up through the
## player's own public `settle_wake_pose()` (the get-up action, then upright), as the game
## does on the first move.
func _stand_up() -> void:
	var before := _protagonist.get_current_clip()
	await _player.settle_wake_pose(0.2)
	await _poll(func() -> bool: return not _protagonist.is_playing_action(), 6.0)
	await _wait(0.5)
	_note("protagonist stood up: clip %s -> %s, seated %s" % [before, _protagonist.get_current_clip(), str(_protagonist.is_seated())])
	if _protagonist.is_seated():
		_failures.append("The protagonist is still seated after settle_wake_pose().")


## The two at conversation distance, turned towards each other.
func _stage_talk() -> void:
	_protagonist.visible = true
	_q.visible = true
	var to_q := TALK_Q - TALK_PROTAGONIST
	var facing_q := rad_to_deg(atan2(to_q.x, to_q.z))
	_place(_protagonist, TALK_PROTAGONIST, facing_q)
	_place(_q, TALK_Q, facing_q + 180.0)
	await _wait(0.4)
	_hide_nameplates()


## The face at about 0.8 m from a little below the eyes, as a dialogue close-up frames a
## lowered head (the production capture's face panel looks down at it from above and, with
## the protagonist's head bowed, sees mostly hair).
func _low_face_panel(subject: CharacterVisualAnimation, shot_name: String) -> Image:
	var head := _head_point(subject) - Vector3.UP * 0.1
	var frame := await _frame_from(head + Vector3.BACK * 0.8 - Vector3.UP * 0.08, head)
	var camera := frame["camera"] as Camera3D
	var image := frame["image"] as Image
	camera.queue_free()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var side := int(image.get_height() * 0.62)
	var rect := Rect2i(image.get_size() / 2 - Vector2i(side, side) / 2, Vector2i(side, side))
	return _fit(image, rect, Vector2i(240, 240))


## Both, from down the aisle at dialogue distance, cropped to the heads and shoulders.
func _talk_panel(shot_name: String) -> Image:
	var centre := (_protagonist.global_position + _q.global_position) * 0.5
	var frame := await _frame_from(centre + Vector3(0.35, 1.45, 2.1), centre + Vector3.UP * 1.22)
	var camera := frame["camera"] as Camera3D
	var image := frame["image"] as Image
	var box := _screen_box(camera, _subtree_aabb(_protagonist).merge(_subtree_aabb(_q)))
	camera.queue_free()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var upper := Rect2i(box.position, Vector2i(box.size.x, int(box.size.y * 0.6)))
	return _fit(image, upper.grow(int(box.size.y * 0.04)), Vector2i(300, 260))


# --- cost ---------------------------------------------------------------------


## The time to draw and read back one frame, repeated: median and 90th percentile, with the
## frame's draw calls and primitives. On the CI runner this is Mesa's software rasteriser
## (llvmpipe) under Xvfb, so the absolute numbers say nothing about a player's GPU; only the
## differences between variants in the same run mean anything, and only roughly.
func _measure_cost(label: String) -> void:
	RenderingServer.force_draw(true)
	root.get_texture().get_image()
	var samples: Array[float] = []
	for attempt in 24:
		var started := Time.get_ticks_usec()
		RenderingServer.force_draw(true)
		root.get_texture().get_image()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_note(
		"cost %s: median %.1f ms, p90 %.1f ms per forced frame + readback (software GL), %d draw calls, %d primitives"
		% [label, samples[12], samples[21], draws, primitives]
	)


## The same, from the dialogue camera, where the characters fill most of the frame.
func _measure_close_cost(variant: String) -> void:
	var centre := (_protagonist.global_position + _q.global_position) * 0.5
	var camera := Camera3D.new()
	camera.fov = 50.0
	_main.add_child(camera)
	camera.global_position = centre + Vector3(0.2, 1.4, 1.0)
	camera.look_at(centre + Vector3.UP * 1.25, Vector3.UP)
	camera.current = true
	await process_frame
	_measure_cost("dialogue close-up, %s" % variant)
	camera.queue_free()
	await process_frame


func _tag(stem: String, variant: String) -> String:
	return "review_%s_%s" % [stem, variant.to_lower().replace("+", "")]
