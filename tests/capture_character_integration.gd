extends SceneTree
## Photographs the protagonist, Q and substitute teacher N together in the running game,
## for the character integration work (docs/CHARACTER_INTEGRATION.md): the same frames with
## the looks the characters had before it, with each visual experiment, and with the looks
## the wrappers ship now.
##
##   xvfb-run godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_character_integration.gd -- --group=q --variants=before,q_oil
##
## Boots `main.tscn` without its opening (as `capture_prologue_art.gd` does), enters the real
## classroom with its own sun, environment and tonemapping, and photographs the three real
## wrapper scenes (`protagonist.tscn` on the player, `q.tscn` and `teacher_n.tscn` on the
## room's own actors) with their real animation drivers. A *variant* only changes which
## `CharacterLook` each character's `CharacterLookApplier` carries (or, for `ORIGINAL`, which
## treatment): nothing else in the scene differs between the columns of a sheet.
##
## Variants (see VARIANTS): `before` is main before this work - the protagonist's and Q's
## painted looks as they were (frozen copies under scenes/dev/character_lab/looks/before/) and
## N in her GLB's own materials, which is what she shipped with. `after` is whatever the
## wrappers carry (the protagonist's charcoal, Q's oil, N's chalk). `q_paper` and
## `n_woodcut` are the second schemes, tried and not shipped, under
## scenes/dev/character_lab/looks/.
##
## Groups (one CI job each, so each has its own annotation budget):
##   protagonist  head to feet in the sun and in the west wall's shade, the face, and the
##                game's own camera
##   q            head to feet lit and back-lit, the face front and three-quarter, and a
##                talk and a walk still
##   n            head to feet in the sun and in the shade, the face, and N at the lectern
##   lineup       the three side by side in the sun and in the shade, and the game camera
##                with all three in the room
##   dialogue     talking to Q (the camera's focus, the dialogue panel up) and N's class
##                conversation, from the game's own camera
##   student      the seated classroom student: face, clothing, own chair and game camera
##   motion       fixed game camera/crop across walk, lesson and A1 pose phases (`after`)
## `--frames=a,b` limits a group to some of its frame kinds. `--freeze-pose` holds the same
## idle/sit pose in each variant (not for motion/dialogue captures). For a new material
## change, `--variants=baseline,after --baseline-dir=<dir>` loads n.tres and student.tres
## saved from that change's base; the historical `before` is NOT a current-look baseline.
## That switch alone DOES NOT replace geometry. tools/capture_character_geometry.sh runs
## two separate engine sessions with the base/current GLBs and looks and joins only their
## genuine panels. It records their hashes, code head and base SHA in the artifact.
##
## Every frame kind becomes one sheet, one column per variant, printed as
## `ARTSHEET: <name>.jpg <base64>` for the workflow to publish as annotations; full-size
## frames go to docs/screenshots/character_integration/ (an artifact, never committed by
## Actions). Measurements are `ARTNOTE:` lines. It fails - `RESULT: FAILURE`, exit 1 - when a
## character is missing, a look did not load or apply, a painted look kept a GLB material,
## or a character draws nothing where it stands.

const Harness = preload("res://tests/test_harness.gd")
const SHOT_DIR := "res://docs/screenshots/character_integration"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const LAB := "res://scenes/dev/character_lab/looks/"
const BACKGROUND := Color(0.1, 0.09, 0.12)
## A character not named in a variant keeps the look its wrapper ships ("wrapper").
## "original" is the GLB's own materials (the ORIGINAL treatment).
const VARIANTS := {
	"before": {
		"protagonist": LAB + "before/protagonist_look.tres",
		"q": LAB + "before/q_look.tres",
		"n": "original",
	},
	"after": {},
	"baseline": {}, # Filled from --baseline-dir; never silently falls back to historical paint.
	"q_paper": {"q": LAB + "q_paper.tres"},
	"n_woodcut": {"n": LAB + "n_woodcut.tres"},
}
const GROUP_FRAMES := {
	"protagonist": ["body_sun", "body_shade", "face", "gameplay"],
	"q": ["body_sun", "body_backlit", "face", "face_three_quarter", "talk", "walk"],
	"n": ["body_sun", "body_shade", "face", "face_three_quarter", "hands", "cloth", "lectern", "walk"],
	"student": ["face", "face_three_quarter", "hands", "cloth", "seated", "gameplay"],
	"lineup": ["lineup_sun", "lineup_shade", "lineup_game"],
	"motion": ["cast_stride", "lectern_motion", "seat_motion"],
	"dialogue": ["dialogue_q", "dialogue_n"],
}
## In front of the board, west aisle: the sun comes in low from the west windows (the
## classroom's `Sun`, -42 deg pitch, travelling +X), so this spot is in full light, and the
## board behind is the darkest backdrop in the room.
const SUN_SPOT := Vector3(-1.25, 0.0, -2.6)
## Against the west wall between the first two rows of desks: below the line the 3.2 m wall
## casts at this sun angle, so the whole figure stands in the room's ambient shade.
const SHADE_SPOT := Vector3(-5.75, 0.0, 0.2)
## Three in a row for the shared-light frames (protagonist, Q, N, left to right as seen).
const LINEUP_SUN := [Vector3(-2.15, 0.0, -2.75), Vector3(-1.25, 0.0, -2.55), Vector3(-0.35, 0.0, -2.75)]
## Behind the second row, against the west wall: clear of the seated classmate (z -0.22)
## and of desks B1 and C1, so the camera in the aisle sees all three head to foot.
const LINEUP_SHADE := [Vector3(-5.85, 0.0, 2.0), Vector3(-5.85, 0.0, 2.45), Vector3(-5.85, 0.0, 2.9)]
## The protagonist's desk (the prologue's start), Q at his own, N at the lectern.
const GAME_PLAYER := Vector3(-1.6, 0.0, 1.95)
const LECTERN := Vector3(0.7, 0.12, -4.19)
## The budget for one job's sheets, in base64 characters: 46 annotation parts of 4000 (a job
## keeps 50 notices; the rest are the measurements and a possible error).
const GROUP_BUDGET := 184000
const BODY_PANEL := Vector2i(240, 400)
const FACE_PANEL := Vector2i(300, 300)
const WIDE_PANEL := Vector2i(480, 300)

var _group := "lineup"
var _variants: Array[String] = ["before", "after"]
var _frames_only: Array[String] = []
var _baseline_dir := ""
var _freeze_pose := false
var _student_authored := Transform3D()
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _room: Node = null
var _ui: CanvasLayer = null
## label -> {"animator": CharacterVisualAnimation, "holder": Node3D, "applier": CharacterLookApplier}
var _cast: Dictionary = {}
## label -> the CharacterLook its wrapper ships (null for none).
var _shipped: Dictionary = {}
## frame kind -> Array[Image], one per variant in order.
var _panels: Dictionary = {}
var _sheets: Array[Dictionary] = []
var _failures: Array[String] = []
var _log: Array[String] = []
var _temporary_camera: Camera3D = null
## Q's transform as the room authors it, for the frames that show the room as played.
var _q_authored := Transform3D()


func _initialize() -> void:
	Harness.arm_watchdog(self, 1200.0, "capture_character_integration.gd")
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			_group = argument.get_slice("=", 1)
		elif argument.begins_with("--variants="):
			_variants.clear()
			for name in argument.get_slice("=", 1).split(",", false):
				_variants.append(name.strip_edges())
		elif argument.begins_with("--frames="):
			for name in argument.get_slice("=", 1).split(",", false):
				_frames_only.append(name.strip_edges())
		elif argument.begins_with("--baseline-dir="):
			_baseline_dir = argument.trim_prefix("--baseline-dir=")
		elif argument == "--freeze-pose":
			_freeze_pose = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_note("group %s, variants %s, started %s" % [_group, ",".join(_variants), Time.get_datetime_string_from_system()])
	if not GROUP_FRAMES.has(_group):
		_failures.append("Unknown group '%s'." % _group)
		await _finish()
		return
	for variant in _variants:
		if not VARIANTS.has(variant):
			_failures.append("Unknown variant '%s'." % variant)
	if _variants.has("baseline") and _baseline_dir.is_empty():
		_failures.append("The baseline variant requires --baseline-dir with n.tres and student.tres from the base revision.")
	if not _failures.is_empty() or not await _boot():
		await _finish()
		return
	var kinds: Array = GROUP_FRAMES[_group]
	for variant in _variants:
		if not await _apply_variant(variant):
			continue
		for kind: String in kinds:
			if not _frames_only.is_empty() and not _frames_only.has(kind):
				continue
			var panel: Image = await Callable(self, "_frame_" + kind).call(variant)
			if panel == null:
				_failures.append("Frame %s for %s came back empty." % [kind, variant])
				continue
			if not _panels.has(kind):
				_panels[kind] = []
			(_panels[kind] as Array).append(panel)
	for kind: String in kinds:
		if _panels.has(kind):
			_sheet("%s_%s__%s" % [_group, kind, "_".join(_variants)], _panels[kind], _variants.size())
	await _finish()


# --- boot ---------------------------------------------------------------------


func _boot() -> bool:
	var autoloads := Harness.ensure_state_autoloads(self)
	var game_state: Node = autoloads["game_state"]
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if loc != null:
		loc.set_locale("zh-CN")
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn did not load.")
		return false
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _frames(3)
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_ui = _main.get_node_or_null("GameUI") as CanvasLayer
	if _host == null or _player == null or _dialogue == null or game_state == null:
		_failures.append("main.tscn did not expose its location host, player and dialogue controller.")
		return false
	if root.get_texture() == null or root.get_texture().get_image() == null:
		_failures.append("The viewport has no image: this is not a real window.")
		return false
	if _host.get_current_path() != CLASSROOM or _host.get_current() == null:
		if not _host.load_location(CLASSROOM, &"PlayerStart", _player):
			_failures.append("The classroom could not be entered.")
			return false
	game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	await _quiet(20.0)
	_room = _host.get_current()
	_set_ui(false)
	# No hover highlight in the frames (its warm line reads as a rim on whoever is in
	# reach); the Q dialogue frame turns interaction back on for its click.
	_set_interaction(false)
	var protagonist := _player.get_node_or_null(^"VisualPivot/Visual/Model") as CharacterVisualAnimation
	var q_actor := _room.get_node_or_null(^"Actors/Q") as NpcActor
	var n_actor := _room.get_node_or_null(^"Actors/N") as NpcActor
	var student := _room.get_node_or_null(^"Actors/SeatedStudent") as CharacterVisualAnimation
	if protagonist == null or q_actor == null or n_actor == null or student == null:
		_failures.append("The protagonist wrapper, Actors/Q, Actors/N or Actors/SeatedStudent is missing.")
		return false
	n_actor.visible = true
	_q_authored = q_actor.global_transform
	var q := q_actor.get_visual() as CharacterVisualAnimation
	var n := n_actor.get_visual() as CharacterVisualAnimation
	if q == null or n == null:
		_failures.append("Q or N has no CharacterVisualAnimation visual.")
		return false
	_cast = {
		"protagonist": {"animator": protagonist, "holder": _player},
		"q": {"animator": q, "holder": q_actor},
		"n": {"animator": n, "holder": n_actor},
		"student": {"animator": student, "holder": student},
	}
	_student_authored = student.global_transform
	for label: String in _cast:
		var animator: CharacterVisualAnimation = _cast[label]["animator"]
		var applier := animator.get_node_or_null(^"Look") as CharacterLookApplier
		_shipped[label] = applier.look if applier != null else null
		if applier == null:
			# N shipped without an applier before this work; the experiments need one. It
			# starts in ORIGINAL, which is exactly what she looked like without it.
			applier = CharacterLookApplier.new()
			applier.name = "Look"
			applier.treatment = CharacterLookApplier.Treatment.ORIGINAL
			animator.add_child(applier)
			await _frames(1)
		_cast[label]["applier"] = applier
		if animator.is_seated() and label != "student":
			animator.set_seated(false)
	await _wait(3.0)
	_hide_nameplates()
	print(
		"CHARACTER_INTEGRATION renderer=%s driver=%s size=%s"
		% [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), str(root.size)]
	)
	return true


func _apply_variant(variant: String) -> bool:
	var spec: Dictionary = VARIANTS[variant].duplicate()
	if variant == "baseline":
		for label: String in ["n", "student"]:
			spec[label] = _baseline_dir.path_join(label + ".tres")
	var ok := true
	for label: String in _cast:
		var applier: CharacterLookApplier = _cast[label]["applier"]
		var choice := String(spec.get(label, "wrapper"))
		var look: CharacterLook = null
		var treatment := CharacterLookApplier.Treatment.PAINTED
		if choice == "original":
			treatment = CharacterLookApplier.Treatment.ORIGINAL
		elif choice == "wrapper":
			look = _shipped[label]
			if look == null:
				treatment = CharacterLookApplier.Treatment.ORIGINAL
		else:
			look = load(choice) as CharacterLook
			if look == null:
				_failures.append("Variant %s: %s's look %s did not load." % [variant, label, choice])
				ok = false
				continue
		applier.look = look
		var report := applier.apply_treatment(treatment)
		_note(
			"%s / %s: %s %s, %d of %d surfaces replaced, outlined %d, %d meshes rebuilt, %d kept"
			% [
				variant, label, String(report.get("treatment", "?")), String(report.get("look", "")),
				int(report.get("replaced", 0)), int(report.get("surfaces", 0)),
				(report.get("outlined", []) as Array).size(), (report.get("rebuilt_meshes", []) as Array).size(),
				(report.get("kept", []) as Array).size(),
			]
		)
		if treatment == CharacterLookApplier.Treatment.PAINTED and not (report.get("kept", []) as Array).is_empty():
			_failures.append("Variant %s: %s kept GLB materials under a painted look: %s" % [variant, label, str(report["kept"])])
			ok = false
		if _freeze_pose:
			var animator: CharacterVisualAnimation = _cast[label]["animator"]
			_pose(animator, "sit_idle" if animator.is_seated() else "idle", 0.31)
			applier.set_process(false) # Hold the blink too, not just the skeleton.
	await _wait(0.4)
	return ok


# --- frames -------------------------------------------------------------------


func _frame_body_sun(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 22.0)
	return await _body_panel(subject, Vector3.BACK, "%s_body_sun_%s" % [_group, variant])


func _frame_body_shade(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SHADE_SPOT, 90.0 - 22.0)
	return await _body_panel(subject, Vector3.RIGHT, "%s_body_shade_%s" % [_group, variant])


## Facing away from the windows, seen from the window side: the sun behind the figure, its
## shadow side to the camera.
func _frame_body_backlit(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, -90.0 + 25.0)
	return await _body_panel(subject, Vector3.LEFT, "%s_body_backlit_%s" % [_group, variant])


func _frame_face(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 15.0)
	return await _face_panel(subject, Vector3.BACK, "%s_face_%s" % [_group, variant])


func _frame_face_three_quarter(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, -40.0)
	return await _face_panel(subject, Vector3.BACK, "%s_face_three_quarter_%s" % [_group, variant])


func _frame_talk(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 30.0)
	_pose(subject, "talk", 0.33)
	await _wait(0.1)
	var panel := await _body_panel(subject, Vector3.BACK, "%s_talk_%s" % [_group, variant])
	_release(subject)
	return panel


func _frame_walk(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 70.0)
	_pose(subject, "walk", 0.0)
	await _wait(0.1)
	var panel := await _body_panel(subject, Vector3.BACK, "%s_walk_%s" % [_group, variant])
	_release(subject)
	return panel


## The game's own camera rig, the player at the start desk.
func _frame_gameplay(variant: String) -> Image:
	_show_all()
	await _stage_room()
	var label := "student" if _group == "student" else "protagonist"
	return await _rig_panel("%s_gameplay_%s" % [_group, variant], [label], WIDE_PANEL, 1.4)


## The student's real chair and desk, not an unseated clone in an empty preview scene.
func _frame_seated(variant: String) -> Image:
	_show_all()
	await _stage_room()
	var student: CharacterVisualAnimation = _cast["student"]["animator"]
	var base := student.global_position
	var side := _forward(student).rotated(Vector3.UP, deg_to_rad(-35.0))
	var shot_name := "%s_seated_%s" % [_group, variant]
	var frame := await _frame_from(base + side * 2.2 + Vector3.UP * 1.3, base + Vector3.UP * 0.75, 45.0)
	var image: Image = frame["image"]
	var box := _screen_box(frame["camera"], _subtree_aabb(student))
	await _measure_drawn(student, frame["camera"], image, box, shot_name)
	_drop_camera()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return _fit(image, box.grow(int(box.size.y * 0.25)), WIDE_PANEL)


## A hand in the wrapper's actual held idle/seated pose. Look along its palm plane,
## choosing the outward side so the body cannot cover it. The camera is identical for
## the two geometry legs because it is derived only from the unchanged Hand rest/pose.
func _frame_hands(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 15.0)
	var skeleton := subject.get_skeleton()
	var resolved: Dictionary = subject.get_bind_report().get("resolved", {})
	if skeleton == null or not resolved.has("hand.R"):
		_failures.append("Hand close-up: the wrapper did not resolve hand.R.")
		return null
	var bone := skeleton.find_bone(String(resolved["hand.R"]))
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var centre := hand.origin + hand.basis.y.normalized() * 0.065
	var normal := (-hand.basis.x if _group == "n" else hand.basis.z).normalized()
	if normal.dot(centre - subject.global_position) < 0.0:
		normal = -normal
	var frame := await _frame_from(centre + normal * 0.45 + Vector3.UP * 0.04, centre, 38.0)
	var image: Image = frame["image"]
	_drop_camera()
	image.save_png("%s/%s_hands_%s.png" % [SHOT_DIR, _group, variant])
	var size := int(image.get_height() * 0.82)
	return _fit(image, Rect2i(image.get_size() / 2 - Vector2i(size, size) / 2, Vector2i(size, size)), FACE_PANEL)


## A closer look at the upper clothing under the same real classroom light.
func _frame_cloth(variant: String) -> Image:
	var subject := _subject_for_group()
	await _solo(subject, SUN_SPOT, 15.0)
	var centre := subject.global_position + Vector3.UP * (0.85 if subject.is_seated() else 1.12)
	var frame := await _frame_from(centre + Vector3(0.0, 0.04, 0.8), centre, 45.0)
	var image: Image = frame["image"]
	_drop_camera()
	image.save_png("%s/%s_cloth_%s.png" % [SHOT_DIR, _group, variant])
	var size := int(image.get_height() * 0.8)
	return _fit(image, Rect2i(image.get_size() / 2 - Vector2i(size, size) / 2, Vector2i(size, size)), FACE_PANEL)


## N at the lectern, from the room: a little above eye height, from the front desks.
func _frame_lectern(variant: String) -> Image:
	_show_all()
	await _stage_room()
	var n: CharacterVisualAnimation = _cast["n"]["animator"]
	var head := _head_point(n)
	var frame := await _frame_from(head + Vector3(0.9, 0.15, 2.2), head + Vector3(-0.1, -0.4, 0.0), 42.0)
	var image: Image = frame["image"]
	var box := _screen_box(frame["camera"], _subtree_aabb(n))
	await _measure_drawn(n, frame["camera"], image, box, "%s_lectern_%s" % [_group, variant])
	_drop_camera()
	image.save_png("%s/%s_lectern_%s.png" % [SHOT_DIR, _group, variant])
	return _fit(image, box.grow(int(box.size.y * 0.3)), WIDE_PANEL)


func _frame_lineup_sun(variant: String) -> Image:
	return await _lineup(LINEUP_SUN, 25.0, Vector3.BACK, "%s_lineup_sun_%s" % [_group, variant])


func _frame_lineup_shade(variant: String) -> Image:
	return await _lineup(LINEUP_SHADE, 90.0 - 15.0, Vector3.RIGHT, "%s_lineup_shade_%s" % [_group, variant])


func _frame_lineup_game(variant: String) -> Image:
	_show_all()
	await _stage_room()
	return await _rig_panel("%s_lineup_game_%s" % [_group, variant], ["protagonist", "q", "n"], WIDE_PANEL, 0.25)


## Talking to Q: the click's own path, held on the first line while the focus settles.
func _frame_dialogue_q(variant: String) -> Image:
	_show_all()
	await _stage_room()
	_player.teleport(Transform3D(Basis(), Vector3(-3.3, 0.0, 4.2)))
	_player.face_toward(Vector3.FORWARD)
	await _frames(30)
	var interaction := _player.get_node_or_null(^"InteractionController") as InteractionController
	var target: Interactable = (_room as LocationRoot).find_interactable(&"q_talk") if _room is LocationRoot else null
	if interaction == null or target == null:
		_failures.append("Could not talk to Q for the dialogue frame.")
		return null
	_set_ui(true)
	interaction.set_enabled(true)
	interaction.request_activation(target)
	await _wait(2.4)
	var image := await _grab("%s_dialogue_q_%s" % [_group, variant])
	await _quiet(20.0)
	_set_ui(false)
	_set_interaction(false)
	return _fit(image, Rect2i(Vector2i.ZERO, image.get_size()), WIDE_PANEL)


## N's class conversation with N at the lectern, from the game camera.
func _frame_dialogue_n(variant: String) -> Image:
	_show_all()
	await _stage_room()
	_player.teleport(Transform3D(Basis(), Vector3(0.3, 0.0, -1.6)))
	_player.face_toward(Vector3.FORWARD)
	await _frames(45)
	_set_ui(true)
	_dialogue.play_conversation(&"n_class")
	await _wait(2.0)
	var image := await _grab("%s_dialogue_n_%s" % [_group, variant])
	await _quiet(30.0)
	_set_ui(false)
	return _fit(image, Rect2i(Vector2i.ZERO, image.get_size()), WIDE_PANEL)


# --- motion evidence ----------------------------------------------------------


## No alternate rig or clip: scrub the three real walk libraries in a staged lineup,
## without advancing the actors through space. Runtime tests cover actual foot travel.
func _frame_cast_stride(variant: String) -> Image:
	_show_all()
	var labels: Array[String] = ["protagonist", "q", "n"]
	for index in labels.size():
		_place(_cast[labels[index]]["animator"], LINEUP_SUN[index], -20.0)
	await _player.camera_rig.frame_point(LINEUP_SUN[1], 0.0)
	await _wait(0.4)
	var sheet := await _motion_strip("stride_" + variant, labels, "walk", [0.0, 0.23, 0.48, 0.74], Vector2i(312, 268))
	await _player.camera_rig.release_frame(0.0)
	return sheet


## Keep the real scene presentation on an N line before sampling the active clip.
func _frame_lectern_motion(variant: String) -> Image:
	_show_all()
	await _stage_room()
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0.3, 0.0, -1.6)))
	_player.face_toward(Vector3.FORWARD)
	_set_ui(true)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("The lesson motion fixture could not open n_class.")
		return null
	var n: CharacterVisualAnimation = _cast["n"]["animator"]
	if not await Harness.wait_until(func() -> bool: return n.get_current_clip() == "talk", 5.0):
		_failures.append("N did not enter talk from the lesson's first visible line.")
		return null
	await _wait(0.45)
	var sheet := await _motion_strip("lesson_" + variant, ["n"], "talk", [0.0, 0.31, 0.51, 0.86], Vector2i(200, 214))
	await _quiet(30.0)
	_set_ui(false)
	return sheet


func _frame_seat_motion(variant: String) -> Image:
	_show_all()
	await _stage_room()
	var student: CharacterVisualAnimation = _cast["student"]["animator"]
	await _player.camera_rig.frame_point(student.global_position, 0.0)
	await _wait(0.4)
	var sheet := await _motion_strip("seat_" + variant, ["student"], "sit_idle", [0.0, 0.36, 0.55, 0.92], Vector2i(200, 214))
	await _player.camera_rig.release_frame(0.0)
	return sheet


## Keep the production lens, angle and crop fixed within each strip. Original full
## viewport frames go in the artifact too. Restore each animator's held state afterwards.
func _motion_strip(
	shot_name: String, labels: Array[String], clip: String, phases: Array[float], cell: Vector2i
) -> Image:
	var camera := _player.camera_rig.camera
	camera.current = true
	var box := Rect2i()
	for label in labels:
		var own := _screen_box(camera, _subtree_aabb(_cast[label]["animator"]))
		if own.intersection(Rect2i(Vector2i.ZERO, root.size)).size.y < 10:
			_failures.append("%s is out of the game camera in %s." % [label, shot_name])
			return null
		box = own if box.size == Vector2i.ZERO else box.merge(own)
	box = box.grow(int(box.size.y * 0.15))
	var rig := _player.camera_rig
	rig.set_physics_process(false)
	const GAP := 4
	var width := (cell.x + GAP) * phases.size() - GAP
	var strip := Image.create(width, cell.y, false, Image.FORMAT_RGB8)
	strip.fill(BACKGROUND)
	for index in phases.size():
		for label in labels:
			_pose(_cast[label]["animator"], clip, phases[index])
		var frame_name := "motion_%s_%02d" % [shot_name, roundi(phases[index] * 100.0)]
		var image := await _grab(frame_name)
		if index == 0:
			for label in labels:
				var subject: CharacterVisualAnimation = _cast[label]["animator"]
				await _measure_drawn(subject, camera, image, _screen_box(camera, _subtree_aabb(subject)), frame_name)
		var panel := _fit(image, box, cell)
		strip.blit_rect(panel, Rect2i(Vector2i.ZERO, cell), Vector2i(index * (cell.x + GAP), 0))
	for label in labels:
		var animator: CharacterVisualAnimation = _cast[label]["animator"]
		CharacterAnimation.play(animator.get_animation_player(), animator.get_current_clip(), 0.0)
		animator.set_process(true)
	rig.set_physics_process(true)
	_note("%s: char/%s at phases %s; game fov %.1f°, fixed crop %s" % [shot_name, clip, str(phases), camera.fov, str(box)])
	return strip


# --- staging ------------------------------------------------------------------


func _subject_for_group() -> CharacterVisualAnimation:
	var label := _group if _cast.has(_group) else "protagonist"
	return _cast[label]["animator"]


func _hide_nameplates() -> void:
	for label: String in _cast:
		var holder: Node = _cast[label]["holder"]
		var plate := holder.get_node_or_null(^"Nameplate") as Node3D
		if plate != null:
			plate.visible = false


func _show_all() -> void:
	for label: String in _cast:
		(_cast[label]["animator"] as Node3D).visible = true
		(_cast[label]["holder"] as Node3D).visible = true


## One character alone at `at`, facing `facing` degrees round from +Z; the others hidden.
func _solo(subject: CharacterVisualAnimation, at: Vector3, facing: float) -> void:
	for label: String in _cast:
		var animator: CharacterVisualAnimation = _cast[label]["animator"]
		animator.visible = animator == subject
	_place(subject, at, facing)
	await _wait(0.4)
	_hide_nameplates()


## Everyone where the room puts them: the player at the start desk, Q at his desk, N at
## the lectern facing the room.
func _stage_room() -> void:
	_place(_cast["protagonist"]["animator"], GAME_PLAYER, 200.0)
	(_cast["q"]["holder"] as Node3D).global_transform = _q_authored
	_place(_cast["n"]["animator"], LECTERN, 0.0)
	(_cast["student"]["holder"] as Node3D).global_transform = _student_authored
	await _wait(1.4)
	_hide_nameplates()


func _lineup(spots: Array, facing: float, side: Vector3, shot_name: String) -> Image:
	_show_all()
	var labels := ["protagonist", "q", "n"]
	for index in labels.size():
		_place(_cast[labels[index]]["animator"], spots[index], facing)
	await _wait(0.6)
	_hide_nameplates()
	var centre: Vector3 = (spots[0] + spots[1] + spots[2]) / 3.0
	var frame := await _frame_from(centre + side * 3.6 + Vector3.UP * 1.25, centre + Vector3.UP * 0.92, 45.0)
	var camera: Camera3D = frame["camera"]
	var image: Image = frame["image"]
	var box := Rect2i()
	for label: String in labels:
		var animator: CharacterVisualAnimation = _cast[label]["animator"]
		var own := _screen_box(camera, _subtree_aabb(animator))
		await _measure_drawn(animator, camera, image, own, "%s (%s)" % [shot_name, label])
		box = own if box.size == Vector2i.ZERO else box.merge(own)
	_drop_camera()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return _fit(image, box.grow(int(box.size.y * 0.08)), WIDE_PANEL)


## Puts the body carrying `subject` at `at` and turns it until the model faces `facing`
## degrees round from +Z (measured on the model, so pivots and visual yaws need no knowing).
func _place(subject: CharacterVisualAnimation, at: Vector3, facing: float) -> void:
	var wanted := deg_to_rad(facing)
	if subject == _cast["protagonist"]["animator"]:
		var yaw := wanted
		for attempt in 3:
			_player.teleport(Transform3D(Basis(Vector3.UP, yaw + PI + 0.0001), at))
			_player.visual_pivot.rotation.y = yaw
			var error := wrapf(wanted - _yaw_of(subject), -PI, PI)
			if absf(error) < 0.01:
				break
			yaw += error
		return
	for label: String in _cast:
		if _cast[label]["animator"] != subject:
			continue
		var holder: Node3D = _cast[label]["holder"]
		holder.global_position = at
		for attempt in 3:
			var error := wrapf(wanted - _yaw_of(subject), -PI, PI)
			if absf(error) < 0.01:
				break
			holder.rotation.y += error
		return


func _yaw_of(subject: CharacterVisualAnimation) -> float:
	var forward := _forward(subject)
	return atan2(forward.x, forward.z)


func _forward(subject: CharacterVisualAnimation) -> Vector3:
	var forward := subject.global_basis.z
	if subject.faces_negative_z:
		forward = -forward
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.01 else Vector3.BACK


func _pose(animator: CharacterVisualAnimation, clip: String, fraction: float) -> void:
	animator.set_process(false)
	var player := animator.get_animation_player()
	var full := "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip]
	if player == null or not player.has_animation(full):
		_failures.append("%s has no clip %s." % [animator.name, full])
		return
	player.play(full, 0.0)
	player.seek(player.get_animation(full).length * fraction, true)
	player.pause()


func _release(animator: CharacterVisualAnimation) -> void:
	var player := animator.get_animation_player()
	if player != null:
		player.play("%s/idle" % String(CharacterAnimation.LIBRARY_NAME), 0.0)
	animator.set_process(true)


func _set_interaction(enabled: bool) -> void:
	var interaction := _player.get_node_or_null(^"InteractionController") as InteractionController
	if interaction != null:
		interaction.set_enabled(enabled)


func _set_ui(shown: bool) -> void:
	if _ui == null:
		return
	_ui.visible = shown
	if shown:
		# Without the opening, the wake-up fade is never lifted and the end card never
		# hidden by the story: clear both, or the dialogue frames are a black screen.
		var fade := _ui.get_node_or_null(^"FadeLayer") as FadeLayer
		if fade != null:
			fade.set_clear()
			fade.visible = false
		var end_card := _ui.get_node_or_null(^"EndCard") as Control
		if end_card != null:
			end_card.visible = false


# --- cameras and panels ---------------------------------------------------------


func _head_point(animator: CharacterVisualAnimation) -> Vector3:
	var skeleton := animator.get_skeleton()
	var resolved: Dictionary = animator.get_bind_report().get("resolved", {})
	if skeleton == null or not resolved.has("head"):
		return animator.global_position + Vector3.UP * 1.5
	var index := skeleton.find_bone(String(resolved["head"]))
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin + Vector3.UP * 0.08


## Head to feet from 2.7 m along `side` from the character.
func _body_panel(subject: CharacterVisualAnimation, side: Vector3, shot_name: String) -> Image:
	var base := subject.global_position
	var frame := await _frame_from(base + side * 2.7 + Vector3.UP * 1.2, base + Vector3.UP * 0.88, 50.0)
	var camera: Camera3D = frame["camera"]
	var image: Image = frame["image"]
	var box := _screen_box(camera, _subtree_aabb(subject))
	await _measure_drawn(subject, camera, image, box, shot_name)
	_drop_camera()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	return _fit(image, box.grow(int(box.size.y * 0.06)), BODY_PANEL)


## The face at about 0.75 m along `side`.
func _face_panel(subject: CharacterVisualAnimation, side: Vector3, shot_name: String) -> Image:
	var head := _head_point(subject)
	var frame := await _frame_from(head + side * 0.75 + Vector3.UP * 0.02, head - Vector3.UP * 0.05, 45.0)
	var image: Image = frame["image"]
	_drop_camera()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var size := int(image.get_height() * 0.66)
	return _fit(image, Rect2i(image.get_size() / 2 - Vector2i(size, size) / 2, Vector2i(size, size)), FACE_PANEL)


## Whatever the game's camera rig shows now, cropped round `labels` (`margin` of their
## height around them).
func _rig_panel(shot_name: String, labels: Array, size: Vector2i, margin: float) -> Image:
	var rig_camera := _main.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
	if rig_camera == null and _player.camera_rig != null:
		rig_camera = _player.camera_rig.camera
	if rig_camera != null:
		rig_camera.current = true
	await _frames(45)
	await _wait(0.8)
	var image := await _grab(shot_name)
	var camera := root.get_camera_3d()
	var box := Rect2i()
	for label: String in labels:
		var own := _screen_box(camera, _subtree_aabb(_cast[label]["animator"]))
		box = own if box.size == Vector2i.ZERO else box.merge(own)
	_note("%s: %s cover %s of the %dx%d frame" % [shot_name, ",".join(labels), str(box), image.get_width(), image.get_height()])
	if box.size.x < 6 or box.size.y < 6:
		_failures.append("The game camera does not see %s in %s." % [",".join(labels), shot_name])
		return _fit(image, Rect2i(Vector2i.ZERO, image.get_size()), size)
	return _fit(image, box.grow(int(box.size.y * margin)), size)


func _frame_from(eye: Vector3, target: Vector3, fov: float) -> Dictionary:
	_drop_camera()
	var camera := Camera3D.new()
	camera.fov = fov
	camera.far = 120.0
	camera.near = 0.03
	_room.add_child(camera)
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
	camera.current = true
	_temporary_camera = camera
	await _frames(12)
	await RenderingServer.frame_post_draw
	return {"camera": camera, "image": root.get_texture().get_image()}


func _drop_camera() -> void:
	if _temporary_camera != null and is_instance_valid(_temporary_camera):
		_temporary_camera.current = false
		_temporary_camera.queue_free()
	_temporary_camera = null
	var rig_camera: Camera3D = _player.camera_rig.camera if _player.camera_rig != null else null
	if rig_camera != null:
		rig_camera.current = true


func _grab(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	var total := 0.0
	var count := 0
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	var mean := total / float(maxi(count, 1))
	_note("%s: mean luminance %.3f" % [shot_name, mean])
	if mean < 0.04:
		_failures.append("%s is black (mean luminance %.3f): something covers the view." % [shot_name, mean])
	return image


## The share of a character's screen box its model draws (the frame rendered once more
## without it; the pixels that change are the model), and their mean luminance.
func _measure_drawn(subject: Node3D, camera: Camera3D, frame: Image, box: Rect2i, shot_name: String) -> void:
	var area := box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if area.size.x < 8 or area.size.y < 8:
		_failures.append("%s is not in frame for %s." % [subject.name, shot_name])
		return
	camera.current = true
	subject.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var without := root.get_texture().get_image()
	subject.visible = true
	await _frames(1)
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
	_note("%s: model draws %.0f%% of its box, mean luminance %.3f" % [shot_name, share * 100.0, lum_sum / float(maxi(changed, 1))])
	# The skinned AABB keeps the bind pose's arm span (the protagonist's is 0.98 m wide),
	# so a correctly drawn figure fills only a tenth of it; this catches a model that is
	# missing or transparent, not a thin one.
	if share < 0.05:
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


func _sheet(sheet_name: String, panels: Array, columns: int) -> void:
	if panels.is_empty():
		return
	var cell: Vector2i = (panels[0] as Image).get_size()
	var gap := 4
	var rows := int(ceil(float(panels.size()) / float(columns)))
	var sheet := Image.create(columns * cell.x + (columns - 1) * gap, rows * cell.y + (rows - 1) * gap, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.04, 0.04, 0.04))
	for index in panels.size():
		var panel: Image = panels[index]
		var at := Vector2i((index % columns) * (cell.x + gap), (index / columns) * (cell.y + gap))
		sheet.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), at)
	sheet.save_png("%s/%s.png" % [SHOT_DIR, sheet_name])
	_sheets.append({"name": sheet_name, "image": sheet})
	_note("sheet %s: %d panels, %dx%d" % [sheet_name, panels.size(), sheet.get_width(), sheet.get_height()])


## Every sheet as a JPEG small enough that the job's sheets together fit its budget.
func _print_sheets() -> void:
	if _sheets.is_empty():
		return
	var share := GROUP_BUDGET / _sheets.size()
	for entry: Dictionary in _sheets:
		var image := (entry["image"] as Image).duplicate() as Image
		var encoded := ""
		for attempt in 9:
			var quality: float = [0.8, 0.72, 0.64, 0.56, 0.5, 0.5, 0.45, 0.45, 0.4][attempt]
			if attempt >= 5:
				image.resize(int(image.get_width() * 0.85), int(image.get_height() * 0.85), Image.INTERPOLATE_LANCZOS)
			encoded = Marshalls.raw_to_base64(image.save_jpg_to_buffer(quality))
			if encoded.length() <= share:
				break
		print("ARTSHEET: %s.jpg %s" % [String(entry["name"]), encoded])
		_note("published %s: %d base64 characters" % [String(entry["name"]), encoded.length()])


# --- driving ------------------------------------------------------------------


func _quiet(timeout_seconds: float) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout_seconds * 1000.0):
		if not _dialogue.is_busy():
			return
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(2)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


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
	var file := FileAccess.open("%s/CHARACTER_INTEGRATION_%s.log" % [SHOT_DIR, _group], FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log) + "\n")
		file.close()
	quit(1 if not _failures.is_empty() else 0)
