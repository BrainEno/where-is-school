extends SceneTree
## Photographs the protagonist and Q in the running game for the character art review.
##
##   xvfb-run godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_character_art.gd -- --group=bodies
##
## Boots `main.tscn`, plays the opening conversation through with the keyboard (as
## `capture_playthrough.gd` does), and once the player has control, photographs both
## characters *in the game*: the real classroom (or corridor, street) with its own lights,
## environment and tonemapping, the real wrapper scenes with their real animation driver,
## and — for the `gameplay` frames — the game's own camera rig. No preview scene, no studio
## light. The nameplates (a development aid, not character art) are hidden for the frames.
##
## Groups, one per CI job so each has its own annotation budget:
##   bodies   head to feet, original (A) / pigment (B) / painted (C), both characters
##   faces    face close-ups A/B/C, and the gameplay camera with A and with C
##   clips    the seven clips on each character (painted), one still per clip
##   posture  idle and walk without and with each character's motion profile, and the
##            painted silhouettes from the front, side, back and three-quarter
##   light    the painted characters in the classroom, the corridor and the street, from
##            the gameplay camera and close
##
## Each group saves its frames and contact sheets under docs/screenshots/character_art/
## (an artifact, never committed) and prints every sheet as `ARTSHEET: <name>.jpg <base64>`
## for the workflow to publish as annotations. The measurements it takes on the way (clip
## lengths, swing amplitudes, posture angles, the look reports) are `ARTNOTE:` lines.
## It fails — `RESULT: FAILURE` and exit 1 — when a character is missing, did not bind,
## kept a GLB material where the painted look names one, or draws nothing on screen.

const Harness = preload("res://tests/test_harness.gd")
const SHOT_DIR := "res://docs/screenshots/character_art"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const STREET := "res://scenes/locations/street/street.tscn"
const Q_WRAPPER := "res://scenes/environment/characters/q.tscn"
const BACKGROUND := Color(0.12, 0.11, 0.10)
## Where a character stands for its own frames: the west aisle, just in front of the board
## (the darkest backdrop in the room, and so the hardest to read on). The camera stands
## 2.7 m down the same aisle, so no desk cuts the legs; a side or back view turns the
## character, not the camera.
const SOLO_SPOT := Vector3(-1.25, 0.0, -2.55)
## Where the two stand together for the game camera's frames (it looks from +X +Z, above):
## the protagonist in front of the board, Q a step behind him in the aisle, so neither
## covers the other.
const PAIR_PROTAGONIST := Vector3(-0.2, 0.0, -2.9)
const PAIR_Q := Vector3(-1.25, 0.0, -2.0)
const PAIR_BACK_PROTAGONIST := Vector3(-0.4, 0.0, 2.2)
const PAIR_BACK_Q := Vector3(-1.4, 0.0, 3.0)
## The budget for one group's sheets, in base64 characters: 39 parts of 4000 (the workflow
## publishes 40 per job).
const GROUP_BUDGET := 156000

var _group := "bodies"
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null
var _game_state: Node = null
var _protagonist: CharacterVisualAnimation = null
var _protagonist_look: CharacterLookApplier = null
var _q_holder: Node3D = null
var _q: CharacterVisualAnimation = null
var _q_look: CharacterLookApplier = null
var _sheets: Array[Dictionary] = []
var _failures: Array[String] = []
var _log: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			_group = argument.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_note("group %s, started %s" % [_group, Time.get_datetime_string_from_system()])
	if not await _boot():
		await _finish()
		return
	match _group:
		"bodies":
			await _capture_bodies()
		"faces":
			await _capture_faces()
		"clips":
			await _capture_clips()
		"posture":
			await _capture_posture()
		"light":
			await _capture_light()
		_:
			_failures.append("Unknown group '%s'." % _group)
	await _finish()


# --- boot ---------------------------------------------------------------------


func _boot() -> bool:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if loc != null:
		loc.set_locale("en")
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn did not load.")
		return false
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	var ui := _main.get_node_or_null("GameUI") as GameUI
	if ui != null:
		_panel = ui.get_node_or_null("DialoguePanel") as DialoguePanel
	if _dialogue == null or _host == null or _player == null:
		_failures.append("main.tscn did not expose its dialogue controller, location host and player.")
		return false
	if root.get_texture() == null or root.get_texture().get_image() == null:
		_failures.append("The viewport has no image: this is not a real window.")
		return false
	# The opening conversation, driven to its end with the keyboard.
	if not await _poll(func() -> bool: return _dialogue.is_busy(), 60.0):
		_failures.append("The opening conversation never started.")
		return false
	if not await _drive_until(
		func() -> bool:
			return bool(_game_state.get_flag(StoryFlags.MET_Q, false)) and not _dialogue.is_busy(),
		120.0
	):
		_failures.append("The opening conversation could not be driven to its end.")
		return false
	if not await _drive_until(
		func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(), 30.0
	):
		_failures.append("The player never got control back.")
		return false
	await _wait(0.5)
	_protagonist = _player.get_node_or_null(^"VisualPivot/Visual/Model") as CharacterVisualAnimation
	if _protagonist == null:
		_failures.append("The player has no protagonist wrapper at VisualPivot/Visual/Model.")
		return false
	_protagonist_look = _protagonist.get_node_or_null(^"Look") as CharacterLookApplier
	var classroom := _host.get_current()
	var q_actor: NpcActor = null
	if classroom != null:
		q_actor = classroom.get_node_or_null(^"Actors/Q") as NpcActor
	if q_actor == null or q_actor.get_visual() == null:
		_failures.append("The classroom has no Q with a visual.")
		return false
	_q_holder = q_actor
	_q = q_actor.get_visual() as CharacterVisualAnimation
	_q_look = _q.get_node_or_null(^"Look") as CharacterLookApplier if _q != null else null
	if _protagonist_look == null or _q == null or _q_look == null:
		_failures.append("A character wrapper has no Look applier or no animation driver.")
		return false
	_hide_nameplates()
	_report_looks()
	return true


func _report_looks() -> void:
	for pair: Array in [["protagonist", _protagonist_look], ["Q", _q_look]]:
		var applier: CharacterLookApplier = pair[1]
		var report := applier.get_report()
		_note(
			"%s look: %s, %d of %d surfaces replaced, outlined %s, kept %s, rebuilt %s, expression %s"
			% [
				pair[0], String(report.get("treatment", "?")), int(report.get("replaced", 0)),
				int(report.get("surfaces", 0)), str(report.get("outlined", [])),
				str(report.get("kept", [])), str(report.get("rebuilt_meshes", [])),
				str(report.get("expression", {})),
			]
		)
		if String(report.get("treatment", "")) == "PAINTED" and not (report.get("kept", []) as Array).is_empty():
			_failures.append("%s kept GLB materials under the painted look: %s" % [pair[0], str(report["kept"])])
	for pair: Array in [["protagonist", _protagonist], ["Q", _q]]:
		var animator: CharacterVisualAnimation = pair[1]
		_note("%s animation: %s" % [pair[0], CharacterAnimation.describe(animator.get_bind_report())])


func _hide_nameplates() -> void:
	for holder: Node in [_player, _q_holder]:
		if holder == null or not is_instance_valid(holder):
			continue
		var plate := holder.get_node_or_null(^"Nameplate") as Node3D
		if plate != null:
			plate.visible = false


## Q stands up (the classroom Q may be sitting) and both characters are visible.
func _stage_classroom() -> void:
	if _q.is_seated():
		_q.set_seated(false)
		await _wait(3.0)
	_protagonist.visible = true
	_q.visible = true
	await _place_pair(PAIR_PROTAGONIST, PAIR_Q, 30.0)


## The two together, both facing `facing` degrees round from +Z.
func _place_pair(protagonist_at: Vector3, q_at: Vector3, facing: float) -> void:
	_protagonist.visible = true
	_q.visible = true
	_place(_protagonist, protagonist_at, facing)
	_place(_q, q_at, facing)
	await _wait(0.6)
	_hide_nameplates()


## One character alone at `SOLO_SPOT`, facing `facing` degrees round from +Z (0 faces the
## camera down the aisle, 90 shows its left side, 180 its back). The other is hidden.
func _solo(subject: CharacterVisualAnimation, facing: float) -> void:
	var other := _q if subject == _protagonist else _protagonist
	other.visible = false
	subject.visible = true
	_place(subject, SOLO_SPOT, facing)
	await _wait(0.35)
	_hide_nameplates()


## Puts the body carrying `subject` at `at` and turns it until the model itself faces
## `facing` degrees round from +Z: measured on the wrapper, so the player's pivot and the
## NPC's 180° visual yaw do not have to be known here.
func _place(subject: CharacterVisualAnimation, at: Vector3, facing: float) -> void:
	var wanted := deg_to_rad(facing)
	if subject == _protagonist:
		# `teleport` faces -basis.z (and ignores an identity basis); the pivot is turned too,
		# so the frame does not wait for the turn. A second pass takes out whatever yaw the
		# model has inside the pivot.
		var yaw := wanted
		for attempt in 2:
			_player.teleport(Transform3D(Basis(Vector3.UP, yaw + PI + 0.0001), at))
			_player.visual_pivot.rotation.y = yaw
			var forward := _forward(subject)
			var error := wrapf(wanted - atan2(forward.x, forward.z), -PI, PI)
			if absf(error) < 0.01:
				break
			yaw += error
		return
	_q_holder.global_position = at
	for attempt in 2:
		var forward := _forward(subject)
		var error := wrapf(wanted - atan2(forward.x, forward.z), -PI, PI)
		if absf(error) < 0.01:
			break
		_q_holder.rotation.y += error


func _treat(treatment: CharacterLookApplier.Treatment) -> void:
	_protagonist_look.apply_treatment(treatment)
	_q_look.apply_treatment(treatment)
	await _wait(0.4)


# --- groups -------------------------------------------------------------------


func _capture_bodies() -> void:
	await _stage_classroom()
	var protagonist_panels: Array[Image] = []
	var q_panels: Array[Image] = []
	for treatment in [
		CharacterLookApplier.Treatment.ORIGINAL,
		CharacterLookApplier.Treatment.PIGMENT,
		CharacterLookApplier.Treatment.PAINTED,
	]:
		await _treat(treatment)
		var suffix := String(CharacterLookApplier.Treatment.keys()[treatment]).to_lower()
		await _solo(_protagonist, 25.0)
		protagonist_panels.append(await _body_panel(_protagonist, "protagonist_body_%s" % suffix))
		await _solo(_q, -25.0)
		q_panels.append(await _body_panel(_q, "q_body_%s" % suffix))
	_sheet("bodies_protagonist_A_B_C", protagonist_panels, 3)
	_sheet("bodies_q_A_B_C", q_panels, 3)


func _capture_faces() -> void:
	await _stage_classroom()
	var panels: Array[Image] = []
	var treatments := [
		CharacterLookApplier.Treatment.ORIGINAL,
		CharacterLookApplier.Treatment.PIGMENT,
		CharacterLookApplier.Treatment.PAINTED,
	]
	var q_faces: Array[Image] = []
	for treatment in treatments:
		await _treat(treatment)
		var suffix := String(CharacterLookApplier.Treatment.keys()[treatment]).to_lower()
		await _solo(_protagonist, 18.0)
		panels.append(await _face_panel(_protagonist, "protagonist_face_%s" % suffix))
		await _solo(_q, -18.0)
		q_faces.append(await _face_panel(_q, "q_face_%s" % suffix))
	panels.append_array(q_faces)
	_sheet("faces_A_B_C_protagonist_then_q", panels, 3)
	# The game's own camera, with the original materials and with the painted ones.
	await _place_pair(PAIR_PROTAGONIST, PAIR_Q, 30.0)
	var gameplay: Array[Image] = []
	for treatment in [CharacterLookApplier.Treatment.ORIGINAL, CharacterLookApplier.Treatment.PAINTED]:
		await _treat(treatment)
		var suffix := String(CharacterLookApplier.Treatment.keys()[treatment]).to_lower()
		gameplay.append(await _gameplay_panel("gameplay_classroom_%s" % suffix, Vector2i(560, 380)))
	_sheet("gameplay_camera_A_then_C", gameplay, 2)


func _capture_clips() -> void:
	await _stage_classroom()
	await _treat(CharacterLookApplier.Treatment.PAINTED)
	# One still per clip, at a moment that shows what the clip is: walk and jog at the
	# passing stride, get_up half way, wave at the top of the arc, talk mid-gesture.
	var moments := {
		"idle": 0.5, "walk": 0.0, "jog": 0.0, "sit_idle": 0.3, "get_up": 0.45,
		"wave": 0.5, "talk": 0.33,
	}
	for pair: Array in [["protagonist", _protagonist], ["q", _q]]:
		var animator: CharacterVisualAnimation = pair[1]
		var panels: Array[Image] = []
		_note_clip_measurements(String(pair[0]), animator)
		await _solo(animator, 62.0)
		for clip: String in moments:
			_pose(animator, clip, float(moments[clip]))
			await _wait(0.1)
			panels.append(
				await _body_panel(animator, "%s_clip_%s" % [pair[0], clip], Vector2i(180, 300))
			)
		_release(animator)
		_sheet("clips_%s_idle_walk_jog_sit_getup_wave_talk" % pair[0], panels, 7)


func _capture_posture() -> void:
	await _stage_classroom()
	await _treat(CharacterLookApplier.Treatment.PAINTED)
	# Without the profile (the shared rhythm both characters had) and with it, side on.
	var panels: Array[Image] = []
	for pair: Array in [["protagonist", _protagonist], ["q", _q]]:
		var animator: CharacterVisualAnimation = pair[1]
		var profile := animator.motion_profile
		await _solo(animator, 90.0)
		for with_profile in [false, true]:
			CharacterAnimation.bind(
				animator, animator.get_animation_player(), animator.faces_negative_z,
				profile if with_profile else null
			)
			for clip: String in ["idle", "walk"]:
				_pose(animator, clip, 0.0 if clip == "walk" else 0.5)
				await _wait(0.1)
				var tag := "%s_%s_%s" % [pair[0], clip, "profile" if with_profile else "shared"]
				panels.append(await _body_panel(animator, tag, Vector2i(170, 290)))
				_note_posture(tag, animator)
		_release(animator)
	_sheet("posture_shared_then_profile_idle_walk_protagonist_then_q", panels, 4)
	# Silhouettes, painted: front, three-quarter, side, back.
	var silhouettes: Array[Image] = []
	for pair: Array in [["protagonist", _protagonist], ["q", _q]]:
		var animator: CharacterVisualAnimation = pair[1]
		for facing in [0.0, 35.0, 90.0, 180.0]:
			await _solo(animator, facing)
			silhouettes.append(
				await _body_panel(animator, "%s_angle_%d" % [pair[0], int(facing)], Vector2i(170, 290))
			)
	_sheet("silhouettes_front_34_side_back_protagonist_then_q", silhouettes, 4)


func _capture_light() -> void:
	await _treat(CharacterLookApplier.Treatment.PAINTED)
	var gameplay: Array[Image] = []
	var close: Array[Image] = []
	# The classroom: the front of the room, then the back under the fittings.
	await _stage_classroom()
	gameplay.append(await _gameplay_panel("light_classroom_front", Vector2i(420, 300)))
	close.append(await _pair_panel("light_classroom_front_close"))
	await _place_pair(PAIR_BACK_PROTAGONIST, PAIR_BACK_Q, 30.0)
	await _wait(0.4)
	gameplay.append(await _gameplay_panel("light_classroom_back", Vector2i(420, 300)))
	# The corridor and the street: Q's own wrapper, placed beside the player there.
	for stop: Array in [[CORRIDOR, &"FromClassroom", "corridor"], [STREET, &"FromCorridor", "street"]]:
		if not _host.load_location(String(stop[0]), StringName(stop[1]), _player):
			_failures.append("Could not load %s." % String(stop[0]))
			continue
		await _wait(1.0)
		_place_q_beside_player()
		await _wait(0.8)
		gameplay.append(await _gameplay_panel("light_%s" % stop[2], Vector2i(420, 300)))
		close.append(await _pair_panel("light_%s_close" % stop[2]))
	_sheet("light_gameplay_classroom_front_back_corridor_street", gameplay, 4)
	_sheet("light_close_classroom_corridor_street", close, 3)


## A fresh `q.tscn` next to the player in a location the classroom Q does not visit.
func _place_q_beside_player() -> void:
	var packed := load(Q_WRAPPER) as PackedScene
	var holder := Node3D.new()
	holder.name = "CaptureQ"
	_host.get_current().add_child(holder)
	var visual := packed.instantiate() as CharacterVisualAnimation
	holder.add_child(visual)
	_q_holder = holder
	_q = visual
	_q_look = visual.get_node_or_null(^"Look") as CharacterLookApplier
	# Across the game camera's view (it looks along -X -Z), on whichever side has floor.
	var at := _player.global_position + Vector3(-0.8, 0.0, 0.8)
	var space := _player.get_world_3d().direct_space_state
	for side: Vector3 in [Vector3(-0.8, 0.0, 0.8), Vector3(0.8, 0.0, -0.8), Vector3(1.1, 0.0, 0.0), Vector3(0.0, 0.0, 1.1)]:
		var from := _player.global_position + Vector3.UP * 1.0
		var query := PhysicsRayQueryParameters3D.create(from, from + side * 1.4)
		query.exclude = [_player.get_rid()]
		if space.intersect_ray(query).is_empty():
			at = _player.global_position + side
			break
	_place(_q, at, 30.0)
	_place(_protagonist, _player.global_position, 30.0)
	_note("Q placed at %s beside the player at %s" % [str(at), str(_player.global_position)])


# --- posing -------------------------------------------------------------------


## Holds `clip` at `fraction` of its length, with the driver's own decisions paused.
func _pose(animator: CharacterVisualAnimation, clip: String, fraction: float) -> void:
	animator.set_process(false)
	var player := animator.get_animation_player()
	var full := "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip]
	if not player.has_animation(full):
		_failures.append("%s has no clip %s." % [animator.name, full])
		return
	player.play(full, 0.0)
	player.seek(player.get_animation(full).length * fraction, true)
	player.pause()


func _release(animator: CharacterVisualAnimation) -> void:
	var player := animator.get_animation_player()
	player.play("%s/idle" % String(CharacterAnimation.LIBRARY_NAME), 0.0)
	animator.set_process(true)


func _note_clip_measurements(label: String, animator: CharacterVisualAnimation) -> void:
	var player := animator.get_animation_player()
	var parts: PackedStringArray = []
	for clip in ["idle", "walk", "jog", "sit_idle", "get_up", "wave", "talk"]:
		var full := "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip]
		if player.has_animation(full):
			parts.append("%s %.2fs" % [clip, player.get_animation(full).length])
	_note("%s clip lengths: %s" % [label, ", ".join(parts)])


## How far the chest, head and arms sit from rest in the held pose, in degrees.
func _note_posture(tag: String, animator: CharacterVisualAnimation) -> void:
	var skeleton := animator.get_skeleton()
	var resolved: Dictionary = animator.get_bind_report().get("resolved", {})
	var parts: PackedStringArray = []
	for canonical in ["spine", "chest", "neck", "head", "upper_arm.L", "upper_arm.R", "thigh.L"]:
		if not resolved.has(canonical):
			continue
		var index := skeleton.find_bone(String(resolved[canonical]))
		var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		parts.append("%s %.1f°" % [canonical, rad_to_deg(skeleton.get_bone_pose_rotation(index).angle_to(rest))])
	var head := _head_point(animator)
	var hips := animator.global_position
	var lean := (head - hips)
	var forward := _forward(animator)
	_note("%s: %s, head %.3f m ahead of the feet, %.3f m up" % [tag, ", ".join(parts), lean.dot(forward), lean.y])


# --- frames -------------------------------------------------------------------


func _forward(subject: Node3D) -> Vector3:
	# Both models face +Z in their wrapper's frame.
	var forward := subject.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD


func _head_point(animator: CharacterVisualAnimation) -> Vector3:
	var skeleton := animator.get_skeleton()
	var resolved: Dictionary = animator.get_bind_report().get("resolved", {})
	if skeleton == null or not resolved.has("head"):
		return animator.global_position + Vector3.UP * 1.5
	var index := skeleton.find_bone(String(resolved["head"]))
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin + Vector3.UP * 0.08


## Head to feet, from 2.7 m down the aisle (+Z of the character, see `_solo`).
func _body_panel(
	subject: CharacterVisualAnimation, shot_name: String, size: Vector2i = Vector2i(260, 420)
) -> Image:
	var base := subject.global_position
	var eye := base + Vector3.BACK * 2.7 + Vector3.UP * 1.2
	var frame := await _frame_from(eye, base + Vector3.UP * 0.88)
	var camera := frame["camera"] as Camera3D
	var box := _screen_box(camera, _subtree_aabb(subject))
	var image := frame["image"] as Image
	await _measure_drawn(subject, camera, image, box, shot_name)
	camera.queue_free()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return _fit(image, box.grow(int(box.size.y * 0.06)), size)


## The face at about 0.8 m, from down the aisle.
func _face_panel(subject: CharacterVisualAnimation, shot_name: String) -> Image:
	var head := _head_point(subject)
	var frame := await _frame_from(head + Vector3.BACK * 0.8 + Vector3.UP * 0.03, head - Vector3.UP * 0.03)
	var camera := frame["camera"] as Camera3D
	var image := frame["image"] as Image
	camera.queue_free()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var side := int(image.get_height() * 0.62)
	var rect := Rect2i(image.get_size() / 2 - Vector2i(side, side) / 2, Vector2i(side, side))
	return _fit(image, rect, Vector2i(240, 240))


## Both characters from a little in front of them, side by side.
func _pair_panel(shot_name: String) -> Image:
	var centre := (_protagonist.global_position + _q.global_position) * 0.5
	var forward := (_forward(_protagonist) + _forward(_q)).normalized()
	if forward.length() < 0.1:
		forward = _forward(_protagonist)
	var frame := await _frame_from(centre + forward * 3.4 + Vector3.UP * 1.35, centre + Vector3.UP * 0.9)
	var camera := frame["camera"] as Camera3D
	var image := frame["image"] as Image
	var box := _screen_box(camera, _subtree_aabb(_protagonist).merge(_subtree_aabb(_q)))
	camera.queue_free()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return _fit(image, box.grow(int(box.size.y * 0.08)), Vector2i(360, 300))


## The game's own camera: whatever the camera rig shows with the player standing here,
## cropped to the two characters with room around them.
func _gameplay_panel(shot_name: String, size: Vector2i) -> Image:
	var rig_camera := _main.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
	if rig_camera != null:
		rig_camera.current = true
	await _wait(1.2)
	RenderingServer.force_draw(true)
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var camera := root.get_camera_3d()
	var box := _screen_box(camera, _subtree_aabb(_protagonist).merge(_subtree_aabb(_q)))
	_note("%s: the two characters cover %s of the %dx%d frame" % [shot_name, str(box), image.get_width(), image.get_height()])
	if box.size.x < 8 or box.size.y < 8:
		_failures.append("The gameplay camera does not see the characters in %s." % shot_name)
		return _fit(image, Rect2i(Vector2i.ZERO, image.get_size()), size)
	var rect := box.grow(int(box.size.y * 0.45))
	return _fit(image, rect, size)


func _frame_from(eye: Vector3, target: Vector3) -> Dictionary:
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.far = 120.0
	_main.add_child(camera)
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
	camera.current = true
	await process_frame
	RenderingServer.force_draw(true)
	await process_frame
	await process_frame
	return {"camera": camera, "image": root.get_texture().get_image()}


## The share of a character's screen box its model draws: rendered once more with the
## model hidden, the pixels that change are the model. A model that draws nothing fails.
func _measure_drawn(subject: Node3D, camera: Camera3D, frame: Image, box: Rect2i, shot_name: String) -> void:
	var area := box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if area.size.x < 8 or area.size.y < 8:
		_failures.append("%s is not in frame for %s." % [subject.name, shot_name])
		return
	camera.current = true
	subject.visible = false
	RenderingServer.force_draw(true)
	await process_frame
	await process_frame
	var without := root.get_texture().get_image()
	subject.visible = true
	await process_frame
	var changed := 0
	var total := 0
	var lum_sum := 0.0
	for y in range(area.position.y, area.end.y, 3):
		for x in range(area.position.x, area.end.x, 3):
			total += 1
			var a := frame.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				changed += 1
				lum_sum += a.get_luminance()
	var share := float(changed) / float(maxi(total, 1))
	var mean := lum_sum / float(maxi(changed, 1))
	_note("%s: model draws %.0f%% of its box, mean luminance of its pixels %.2f" % [shot_name, share * 100.0, mean])
	if share < 0.12:
		_failures.append("%s draws only %.0f%% of its screen box in %s." % [subject.name, share * 100.0, shot_name])


func _screen_box(camera: Camera3D, box: AABB) -> Rect2i:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for index in 8:
		var corner := box.get_endpoint(index)
		if camera.is_position_behind(corner):
			continue
		var screen := camera.unproject_position(corner)
		low = low.min(screen)
		high = high.max(screen)
	if low.x == INF:
		return Rect2i()
	return Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()))


func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## `rect` of `image`, widened to the panel's aspect around its centre, scaled to `size`.
func _fit(image: Image, rect: Rect2i, size: Vector2i) -> Image:
	var aspect := float(size.x) / float(size.y)
	var centre := rect.get_center()
	var height := float(rect.size.y)
	var width := float(rect.size.x)
	if width / maxf(height, 1.0) < aspect:
		width = height * aspect
	else:
		height = width / aspect
	var wanted := Rect2i(
		Vector2i(int(centre.x - width * 0.5), int(centre.y - height * 0.5)),
		Vector2i(maxi(int(width), 4), maxi(int(height), 4))
	)
	var canvas := Image.create(wanted.size.x, wanted.size.y, false, Image.FORMAT_RGB8)
	canvas.fill(BACKGROUND)
	var source := image.duplicate() as Image
	source.convert(Image.FORMAT_RGB8)
	var inside := wanted.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	if inside.size.x > 0 and inside.size.y > 0:
		canvas.blit_rect(source, inside, inside.position - wanted.position)
	canvas.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return canvas


func _sheet(sheet_name: String, panels: Array[Image], columns: int) -> void:
	if panels.is_empty():
		_failures.append("Sheet %s has no panels." % sheet_name)
		return
	var cell := panels[0].get_size()
	var gap := 4
	var rows := int(ceil(float(panels.size()) / float(columns)))
	var sheet := Image.create(
		columns * cell.x + (columns - 1) * gap, rows * cell.y + (rows - 1) * gap, false, Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.05, 0.05, 0.05))
	for index in panels.size():
		var panel := panels[index]
		var at := Vector2i((index % columns) * (cell.x + gap), (index / columns) * (cell.y + gap))
		sheet.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), at)
	sheet.save_png("%s/%s.png" % [SHOT_DIR, sheet_name])
	_sheets.append({"name": sheet_name, "image": sheet})
	_note("sheet %s: %d panels, %dx%d" % [sheet_name, panels.size(), sheet.get_width(), sheet.get_height()])


## Every sheet as a JPEG small enough that the group's sheets together fit its budget.
func _print_sheets() -> void:
	if _sheets.is_empty():
		return
	var share := GROUP_BUDGET / _sheets.size()
	for entry: Dictionary in _sheets:
		var image := (entry["image"] as Image).duplicate() as Image
		var encoded := ""
		for attempt in 8:
			var quality: float = [0.72, 0.62, 0.52, 0.45, 0.45, 0.4, 0.4, 0.35][attempt]
			if attempt >= 4:
				image.resize(int(image.get_width() * 0.85), int(image.get_height() * 0.85), Image.INTERPOLATE_LANCZOS)
			encoded = Marshalls.raw_to_base64(image.save_jpg_to_buffer(quality))
			if encoded.length() <= share:
				break
		print("ARTSHEET: %s.jpg %s" % [String(entry["name"]), encoded])
		_note("published %s: %d base64 characters" % [String(entry["name"]), encoded.length()])


# --- driving ------------------------------------------------------------------


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _drive_until(predicate: Callable, timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	var last_key := 0
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if bool(predicate.call()):
			return true
		if _dialogue.is_busy() and Time.get_ticks_msec() - last_key > 250:
			last_key = Time.get_ticks_msec()
			if _dialogue.has_pending_choices():
				await _press(KEY_1)
			else:
				await _press(KEY_SPACE)
		else:
			await process_frame
	return false


func _poll(predicate: Callable, timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if bool(predicate.call()):
			return true
		await process_frame
	return false


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout
	await process_frame


# --- result -------------------------------------------------------------------


func _note(message: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), message]
	_log.append(line)
	print("ARTNOTE: %s" % line)


func _finish() -> void:
	_print_sheets()
	for failure: String in _failures:
		_note("FAILURE: %s" % failure)
	_note("RESULT: %s" % ("FAILURE" if not _failures.is_empty() else "SUCCESS"))
	var file := FileAccess.open("%s/CHARACTER_ART_%s.log" % [SHOT_DIR, _group], FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log) + "\n")
		file.close()
	quit(1 if not _failures.is_empty() else 0)
