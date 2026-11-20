extends SceneTree
## The shared clips in `CharacterAnimation` drive every rigged character in the repository,
## and each one is authored against canonical bone names rather than a rig's own.
##
## That is the claim this file checks, and it is the claim the retarget experiment failed:
## the two rigs name their bones differently (the rigged Q says `UpperArm.L`, the retargeted
## protagonist says `LeftUpperArm`), so a clip has to be resolved per rig at bind time. A
## mistake here is silent — an `Animation` whose track path names a bone that does not exist
## simply plays nothing — so the checks are:
##
##   1. every rig resolves the bones the clips need, and the ones it cannot express are
##      reported rather than dropped;
##   2. every track in every built clip points at a bone that exists on that rig;
##   3. each clip actually moves the bones it claims to move, measured by seeking the
##      animation and reading the skeleton's bone poses;
##   4. both rigs get the same shared clip names despite naming their bones differently;
##   5. both production models have skeletons and bind;
##   6. a transition does not loop: `get_up` is built with `LOOP_NONE`, ends on the rest pose,
##      and starts from *exactly* the pose `sit_idle` holds, so the two cannot drift apart;
##   7. the actual protagonist and Q wrapper scenes create their runtime AnimationPlayers and
##      switch between idle, walk and jog by the body's speed, hold `sit_idle` while seated,
##      and hand back to locomotion when a one-shot action finishes.

const Harness = preload("res://tests/test_harness.gd")

const RIGGED_Q := "res://assets/models/q/new-Q.glb"
const RETARGETED_PROTAGONIST := "res://scenes/dev/animation_retarget_test/protagonist_retarget_ready.glb"
const PRODUCTION_PROTAGONIST := "res://assets/models/protagonist/Protagonist_Character.glb"
## The first protagonist model, now a classroom student (`classroom_student.tscn`).
const FORMER_PROTAGONIST := "res://assets/models/protagonist/protagonist.glb"
const PRODUCTION_Q := "res://assets/models/q/new-Q.glb"
## Substitute teacher N: the one character exported facing −Z.
const PRODUCTION_N := "res://assets/models/teacher-n/teacher-n.glb"
## How far, in metres, a thigh raised for sitting has to carry the knee along the facing axis.
const SEATED_KNEE_TRAVEL := 0.2
## The four loops N's author made, the same list `teacher_n.tscn` hands its animator.
const N_IDLE_LAYERS: Array[String] = [
	"ST_Idle_Breathing", "ST_Nervous_Posture_Shift", "ST_Slight_Hand_Movement",
	"ST_Subtle_Head_Movement",
]

## Degrees a bone has to turn between two samples of a clip before the clip counts as moving
## it. Small enough for the idle sway, large enough that floating point noise cannot pass.
const MOVED_DEGREES := 0.5
## Canonical bones a rig has to resolve before it can play the whole set. The clips use 19;
## Q has 17 of them (it has no shoulder bones, which no clip needs).
const MIN_RESOLVED := 16
## The clips, and a canonical bone each one has to move.
const CLIPS := {
	"idle": "spine",
	"walk": "thigh.L",
	"jog": "thigh.L",
	"sit_idle": "thigh.L",
	"sit_talk": "head",
	"wave": "upper_arm.R",
	"talk": "head",
	"get_up": "thigh.L",
}

## The transition reaches the standing pose; seated speech holds its last key.
const NON_LOOPING_CLIPS := ["get_up", "sit_talk"]

## Degrees two keys of the same bone may differ by and still count as the same pose.
const POSE_TOLERANCE_DEGREES := 0.5
## The production motion resources (docs/CHARACTER_ANIMATION.md).
const PROTAGONIST_MOTION := "res://assets/characters/protagonist/protagonist_motion.tres"
const Q_MOTION := "res://assets/characters/q/q_motion.tres"
const N_MOTION := "res://assets/characters/teacher_n/teacher_n_motion.tres"
const STUDENT_MOTION := "res://assets/characters/classroom_student/student_motion.tres"

var _failures: Array[String] = []
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "character_animation_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "the rigged characters"
	# Typed by hand: `_check_model` returns Variant (a report, or null when a model will not
	# load), and this project treats inferring a type from a Variant as an error.
	var q_report: Variant = await _check_model("Q (rigged)", RIGGED_Q, true)
	var protagonist_report: Variant = await _check_model(
		"protagonist (retargeted)", RETARGETED_PROTAGONIST, true
	)

	Harness.stage = "the clips are the same set on both rigs"
	if q_report is Dictionary and protagonist_report is Dictionary:
		var q_clips: Dictionary = q_report.get("clips", {})
		var p_clips: Dictionary = protagonist_report.get("clips", {})
		if q_clips.keys() != p_clips.keys():
			_failures.append(
				"the two rigs did not end up with the same clips: %s vs %s"
				% [str(q_clips.keys()), str(p_clips.keys())]
			)
		# And the bones they solved to must actually differ, or "both rigs" would be a
		# coincidence of one rig being loaded twice.
		var q_resolved: Dictionary = q_report.get("resolved", {})
		var p_resolved: Dictionary = protagonist_report.get("resolved", {})
		var differing := 0
		for canonical in q_resolved:
			if p_resolved.has(canonical) and String(q_resolved[canonical]) != String(p_resolved[canonical]):
				differing += 1
		_notes.append("%d bone(s) resolved to different names on the two rigs" % differing)
		if differing < 8:
			_failures.append(
				"only %d bones resolved to different names; the two rigs are not as different as "
				% differing
				+ "they should be, so the name mapping is not being exercised."
			)

	Harness.stage = "the production models"
	await _check_model("protagonist (production)", PRODUCTION_PROTAGONIST, true)
	await _check_model("former protagonist (classroom student)", FORMER_PROTAGONIST, true)
	await _check_model("Q (production)", PRODUCTION_Q, true)
	await _check_model("N (production)", PRODUCTION_N, true, true)

	Harness.stage = "a model that faces -Z"
	await _check_negative_z_binding()

	Harness.stage = "a model's own clips as the idle"
	await _check_authored_idle()

	Harness.stage = "the sprint the jog clip exists for"
	_check_jog_threshold()

	Harness.stage = "the production wrapper scenes"
	await _check_runtime_wrapper("protagonist", "res://scenes/environment/characters/protagonist.tscn")
	await _check_runtime_wrapper("Q", "res://scenes/environment/characters/q.tscn")
	await _check_runtime_wrapper("N", "res://scenes/environment/characters/teacher_n.tscn")
	await _check_seated_student("res://scenes/environment/characters/classroom_student.tscn")

	Harness.stage = "the four characters' motion profiles"
	_check_authored_track_validation()
	await _check_motion_profiles()

	_report()
	Harness.finish(
		self, _failures,
		"every rigged character (+Z and -Z) plays the same shared clips, every track points at a bone that "
		+ "exists, the transition does not loop, and the seats and speeds are wired."
	)


## Binds one model and runs the clip checks. `should_bind` false means the model is expected
## to have no skeleton, and the report has to say so instead of half-working.
func _check_model(
	label: String, path: String, should_bind: bool, faces_negative_z: bool = false
) -> Variant:
	var packed: PackedScene = load(path)
	if packed == null:
		_failures.append("%s: %s could not be loaded." % [label, path])
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		_failures.append("%s: %s is not a 3D scene." % [label, path])
		return null
	root.add_child(model)
	await process_frame

	var skeletons := CharacterAnimation.skeletons_in(model)
	if not should_bind:
		if not skeletons.is_empty():
			_failures.append(
				"%s: the production model now has a skeleton; this test says it does not, so "
				% label
				+ "the notes about it and the model disagree and one of them has to change."
			)
		var refused := CharacterAnimation.bind(model, _player_for(model))
		if bool(refused.get("ok", true)):
			_failures.append("%s: binding a model with no skeleton reported success." % label)
		_notes.append("%s: %s" % [label, CharacterAnimation.describe(refused)])
		model.queue_free()
		return refused

	if skeletons.is_empty():
		_failures.append("%s: no Skeleton3D in %s, so nothing can be bound." % [label, path])
		model.queue_free()
		return null
	var player := _player_for(model)
	var report := CharacterAnimation.bind(model, player, faces_negative_z)
	if not bool(report.get("ok", false)):
		_failures.append("%s: bind failed: %s" % [label, String(report.get("reason", "?"))])
		model.queue_free()
		return null
	_notes.append("%s: %s" % [label, CharacterAnimation.describe(report)])

	var resolved: Dictionary = report.get("resolved", {})
	if resolved.size() < MIN_RESOLVED:
		_failures.append(
			"%s: only %d canonical bones resolved (need %d); the clips would play as a "
			% [label, resolved.size(), MIN_RESOLVED]
			+ "fraction of a character."
		)
	# The blockout rigs have no chest and no clavicles. Any *other* canonical bone a rig cannot
	# resolve is a clip that will quietly do less than it says, so the set is named rather than
	# counted: a rig that loses, say, `shin.L` fails here instead of walking with one leg.
	var missing: Array = report.get("missing", [])
	var allowed_missing := ["chest", "shoulder.L", "shoulder.R"]
	for canonical in missing:
		if not allowed_missing.has(String(canonical)):
			_failures.append(
				"%s: '%s' is not a bone on this rig, and the clips expect it to be. Bones: %s"
				% [label, String(canonical), str(report.get("bones", []))]
			)

	var skeleton := skeletons[0]
	_check_track_paths(label, player, skeleton)
	for clip_name in CLIPS:
		_check_clip(
			label, player, skeleton, resolved, clip_name, not NON_LOOPING_CLIPS.has(clip_name),
			report.get("posed", [])
		)
	_check_transition_poses(label, player, skeleton, resolved)
	model.queue_free()
	return report


## A track whose path does not resolve to a real bone is invisible at run time: the animation
## plays, the character does not move, and nothing is printed.
func _check_track_paths(label: String, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	for clip_name in CLIPS:
		var animation: Animation = player.get_animation(
			"%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]
		)
		if animation == null:
			_failures.append("%s: clip '%s' was not built." % [label, clip_name])
			continue
		if animation.get_track_count() < 4:
			_failures.append(
				"%s: clip '%s' has only %d track(s)." % [label, clip_name, animation.get_track_count()]
			)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			# "Skeleton3D:UpperArm.L" - the part after the colon is the bone.
			var bone := path.get_concatenated_subnames()
			if bone.is_empty():
				bone = String(path).get_slice(":", -1)
			if skeleton.find_bone(bone) < 0:
				_failures.append(
					"%s: clip '%s' track %d points at '%s', which is not a bone on this rig."
					% [label, clip_name, track, bone]
				)


## Seeks the clip and reads the bone poses: the clip has to move the bone it is about, and
## it has to move it back before it loops.
func _check_clip(
	label: String,
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	resolved: Dictionary,
	clip_name: String,
	loops: bool,
	posed: Array = []
) -> void:
	var canonical: String = CLIPS[clip_name]
	if not resolved.has(canonical):
		_failures.append("%s: '%s' cannot move '%s', which this rig does not have." % [label, clip_name, canonical])
		return
	var bone := String(resolved[canonical])
	var index := skeleton.find_bone(bone)
	if index < 0:
		_failures.append("%s: '%s' resolved to '%s', which find_bone() cannot find." % [label, canonical, bone])
		return
	var full := "%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]
	if not CharacterAnimation.play(player, clip_name):
		_failures.append("%s: '%s' would not play." % [label, clip_name])
		return
	var animation := player.get_animation(full)
	var length := animation.length
	var samples: Array[Quaternion] = []
	for step in 5:
		player.seek(length * float(step) / 4.0, true)
		samples.append(skeleton.get_bone_pose_rotation(index))
	var widest := 0.0
	for step in range(1, samples.size()):
		var angle := rad_to_deg(samples[0].angle_to(samples[step]))
		widest = maxf(widest, angle)
	# A looping clip has to return to where it started, or the loop limps. A transition is
	# supposed to *arrive*: it ends on the rest pose, so the check is that it ends at zero.
	var returned := rad_to_deg(samples[0].angle_to(samples[samples.size() - 1]))
	_notes.append(
		"%s/%s: %s turns %.1f° and returns to within %.2f°" % [label, clip_name, bone, widest, returned]
	)
	# A limb this rig does not model hanging down is held at its modelled pose on purpose
	# (`CharacterAnimation.posed_limbs`): its axes are not the ones the clip was written for.
	# Then the check is the opposite one: the hold has to actually hold.
	if posed.has(canonical):
		_notes.append("%s/%s: '%s' is held at its modelled pose on this rig" % [label, clip_name, bone])
		if widest > MOVED_DEGREES:
			_failures.append(
				"%s: '%s' is listed as held at its modelled pose, but clip '%s' turned it %.2f°."
				% [label, canonical, clip_name, widest]
			)
	elif widest < MOVED_DEGREES:
		_failures.append(
			"%s: clip '%s' moved '%s' by %.2f° at most; the track is not reaching the bone."
			% [label, clip_name, bone, widest]
		)
	var expected_loop_mode := Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	if animation.loop_mode != expected_loop_mode:
		_failures.append(
			"%s: clip '%s' has loop mode %d; %s"
			% [label, clip_name, animation.loop_mode, "it loops" if loops else "it is a transition"]
		)
	if loops and returned > MOVED_DEGREES:
		_failures.append(
			"%s: clip '%s' ends %.2f° away from where it starts, so the loop jumps."
			% [label, clip_name, returned]
		)
	if clip_name == "get_up":
		# A bone's pose rotation is its whole local rotation, so "standing up" is the bone's
		# rest rotation. (It is not the identity: every limb on these rigs rests ~170–180°
		# from its parent, and a clip that ended on the identity would end with the legs and
		# arms thrown upwards, which is the bug rest-relative keys fixed.)
		var last_pose: Quaternion = samples[samples.size() - 1]
		var rest_pose := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var away_from_rest := rad_to_deg(last_pose.angle_to(rest_pose))
		_notes.append("%s/%s ends %.2f° from the rest pose" % [label, clip_name, away_from_rest])
		if away_from_rest > 1.0:
			_failures.append(
				"%s: clip '%s' ends %.2f° away from the rest pose, so the body would snap when "
				% [label, clip_name, away_from_rest]
				+ "the next clip starts."
			)
	player.stop()


## A jog clip nobody can reach is a clip that will rot. The controller has two speeds and the
## driver has one threshold, and the threshold has to sit between them or the jog either never
## plays or plays while the body is still walking.
func _check_jog_threshold() -> void:
	var controller := PlayerController.new()
	# Untyped on purpose: the driver is reached through its script, and a statically typed
	# `Node` would make `jog_speed_threshold` a compile error rather than a property read.
	var wrapper: Node = preload("res://scripts/actors/character_visual_animation.gd").new()
	var walk := controller.move_speed
	var jog := controller.jog_speed
	var threshold := float(wrapper.get("jog_speed_threshold"))
	_notes.append(
		"speeds: walk %.1f, jog %.1f, clip threshold %.1f m/s" % [walk, jog, threshold]
	)
	if jog <= walk:
		_failures.append(
			"jog_speed (%.1f) is not faster than move_speed (%.1f), so the jog clip has no speed "
			% [jog, walk]
			+ "that reaches it."
		)
	elif threshold <= walk or threshold >= jog:
		_failures.append(
			"the jog threshold (%.1f) is not between move_speed (%.1f) and jog_speed (%.1f)."
			% [threshold, walk, jog]
		)
	# The sprint input has to exist and has to move `target_speed()`, or `jog_speed` is dead.
	if not InputMap.has_action(PlayerController.SPRINT_ACTION):
		_failures.append("the '%s' input action is not defined." % String(PlayerController.SPRINT_ACTION))
		wrapper.free()
		controller.free()
		return
	Input.action_press(PlayerController.SPRINT_ACTION)
	var sprinting := controller.target_speed()
	Input.action_release(PlayerController.SPRINT_ACTION)
	var standing := controller.target_speed()
	_expect_hold("sprint", sprinting, jog, standing, walk)
	wrapper.free()
	controller.free()


func _expect_hold(label: String, sprinting: float, jog: float, standing: float, walk: float) -> void:
	if not is_equal_approx(sprinting, jog):
		_failures.append(
			"%s: holding the action aims for %.1f m/s, not the jog speed %.1f." % [label, sprinting, jog]
		)
	if not is_equal_approx(standing, walk):
		_failures.append(
			"%s: releasing the action still aims for %.1f m/s, not the walk speed %.1f."
			% [label, standing, walk]
		)


## `sit_idle` and `get_up` are two halves of one movement: the clip the protagonist holds at
## the desk and the clip that stands them up. If the first key of one stops matching the first
## key of the other, the body jumps at the moment the wake beat starts, which is exactly the
## frame nobody is looking at because black is still fading.
func _check_transition_poses(
	label: String, player: AnimationPlayer, skeleton: Skeleton3D, resolved: Dictionary
) -> void:
	var sitting := _first_pose(label, player, skeleton, resolved, "sit_idle")
	var rising := _first_pose(label, player, skeleton, resolved, "get_up")
	if sitting.is_empty() or rising.is_empty():
		return
	var worst := 0.0
	var worst_bone := ""
	for canonical in sitting:
		if not rising.has(canonical):
			continue
		var difference: float = rad_to_deg((sitting[canonical] as Quaternion).angle_to(rising[canonical]))
		if difference > worst:
			worst = difference
			worst_bone = String(canonical)
	_notes.append(
		"%s: sit_idle and get_up agree on the seated pose to within %.2f° (worst: %s)"
		% [label, worst, worst_bone]
	)
	# And the seated pose has to actually be seated: folding the legs is the whole clip, so a
	# hip that barely leaves the rest pose would make `sit_idle` an idle with a different name.
	if sitting.has("thigh.L"):
		var thigh_rest := skeleton.get_bone_rest(skeleton.find_bone(String(resolved["thigh.L"])))
		var hip := rad_to_deg(
			(sitting["thigh.L"] as Quaternion).angle_to(thigh_rest.basis.get_rotation_quaternion())
		)
		_notes.append("%s: the seated hip is %.1f° from rest" % [label, hip])
		if hip < 30.0:
			_failures.append(
				"%s: sit_idle bends the hip only %.1f°, so the character is standing."
				% [label, hip]
			)
	if worst > POSE_TOLERANCE_DEGREES:
		_failures.append(
			"%s: sit_idle and get_up disagree about the seated pose by %.2f° on '%s'; the wake "
			% [label, worst, worst_bone]
			+ "beat would jump when the get-up starts."
		)


## N looks down −Z; the clips are written for a character looking down +Z. Bound with
## `faces_negative_z`, sitting has to bring N's knees out in front of it (−Z), which is the
## check that the side axis was turned with the character. Bound without it — the control —
## the same keys fold N's legs backwards, which is what the flag exists to prevent; if that
## ever stops happening, the flag no longer does anything and this test says so.
func _check_negative_z_binding() -> void:
	var packed := load(PRODUCTION_N) as PackedScene
	if packed == null:
		_failures.append("N: %s could not be loaded." % PRODUCTION_N)
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var skeletons := CharacterAnimation.skeletons_in(model)
	if skeletons.is_empty():
		_failures.append("N: no skeleton to bind.")
		model.queue_free()
		return
	var skeleton := skeletons[0]
	for faces_negative_z: bool in [true, false]:
		var player := _player_for(model)
		var report := CharacterAnimation.bind(model, player, faces_negative_z)
		var resolved: Dictionary = report.get("resolved", {})
		if not bool(report.get("ok", false)) or not resolved.has("shin.L") or not resolved.has("shin.R"):
			_failures.append("N: binding (faces −Z %s) did not resolve both shins." % faces_negative_z)
			player.queue_free()
			continue
		CharacterAnimation.play(player, "sit_idle")
		player.seek(0.0, true)
		var travel := 0.0
		for side in ["L", "R"]:
			var knee := skeleton.find_bone(String(resolved["shin.%s" % side]))
			var moved := skeleton.get_bone_global_pose(knee).origin - skeleton.get_bone_global_rest(knee).origin
			# Along N's facing (−Z), so positive is "in front of N".
			travel += -moved.z * 0.5
		player.stop()
		var label := "with faces_negative_z" if faces_negative_z else "without faces_negative_z (control)"
		_notes.append("N sit_idle %s: knees move %+.3f m along N's facing" % [label, travel])
		if faces_negative_z and travel < SEATED_KNEE_TRAVEL:
			_failures.append(
				"N, bound facing −Z, sits with its knees %+.3f m along its facing; they have to come forward."
				% travel
			)
		if not faces_negative_z and travel > -SEATED_KNEE_TRAVEL:
			_failures.append(
				"N bound as a +Z model no longer folds its knees backwards (%+.3f m); "
				% travel
				+ "faces_negative_z would then be doing nothing, so this check is out of date."
			)
		model.remove_child(player)
		player.free()
	model.queue_free()
	await process_frame


## `adopt_authored_layers()` either replaces the idle with the model's own loops or leaves the
## procedural idle exactly as it was. Three cases: N's four loops (replaced, looping, every
## track applied); a list naming a clip N does not have (refused, idle untouched); the classroom student, which
## carries no clips of its own (refused, idle untouched). A half-built idle is the failure
## this guards against.
func _check_authored_idle() -> void:
	var cases := [
		["N, its four loops", PRODUCTION_N, true, PackedStringArray(N_IDLE_LAYERS), true],
		["N, a clip it does not have", PRODUCTION_N, true,
			PackedStringArray(["ST_Idle_Breathing", "No_Such_Clip"]), false],
		["classroom student, no clips of its own", FORMER_PROTAGONIST, false, PackedStringArray(N_IDLE_LAYERS), false],
	]
	for case: Array in cases:
		var label := String(case[0])
		var packed := load(String(case[1])) as PackedScene
		if packed == null:
			_failures.append("%s: %s could not be loaded." % [label, case[1]])
			continue
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		await process_frame
		var player := _player_for(model)
		var report := CharacterAnimation.bind(model, player, bool(case[2]))
		if not bool(report.get("ok", false)):
			_failures.append("%s: bind failed: %s" % [label, report.get("reason", "?")])
			model.queue_free()
			await process_frame
			continue
		var library := player.get_animation_library(CharacterAnimation.LIBRARY_NAME)
		var before := library.get_animation("idle")
		var adopted := CharacterAnimation.adopt_authored_layers(
			model, player, "idle", case[3] as PackedStringArray
		)
		var after := library.get_animation("idle")
		var expect_ok := bool(case[4])
		_notes.append("%s: adopt ok %s (%s)" % [label, adopted.get("ok"), adopted.get("reason", "replaced")])
		if bool(adopted.get("ok", false)) != expect_ok:
			_failures.append(
				"%s: adopt_authored_layers returned ok %s, expected %s (%s)."
				% [label, adopted.get("ok"), expect_ok, adopted.get("reason", "")]
			)
		elif expect_ok:
			if after == before:
				_failures.append("%s: the idle was reported replaced but is the same clip." % label)
			elif after.loop_mode != Animation.LOOP_LINEAR:
				_failures.append("%s: the adopted idle does not loop." % label)
			if int(adopted.get("ignored_tracks", -1)) != 0:
				_failures.append("%s: %s track(s) of the model's clips were not applied." % [label, adopted.get("ignored_tracks")])
			if (adopted.get("layers", PackedStringArray()) as PackedStringArray).size() != 4:
				_failures.append("%s: the adopted idle does not combine all four loops." % label)
			for track in after.get_track_count():
				if after.track_get_type(track) != Animation.TYPE_ROTATION_3D:
					_failures.append("%s: the adopted idle has a non-rotation track." % label)
					break
		else:
			if after != before:
				_failures.append("%s: a refused adopt still replaced the procedural idle." % label)
			if String(adopted.get("reason", "")).is_empty():
				_failures.append("%s: a refused adopt gave no reason." % label)
		model.queue_free()
		await process_frame


## The pose a clip is in at time zero, per canonical bone, as the skeleton ends up holding it.
## Keyed canonically so two clips and two differently-named rigs can be compared.
func _first_pose(
	label: String, player: AnimationPlayer, skeleton: Skeleton3D, resolved: Dictionary, clip_name: String
) -> Dictionary:
	if not CharacterAnimation.play(player, clip_name):
		_failures.append("%s: '%s' would not play." % [label, clip_name])
		return {}
	player.seek(0.0, true)
	var poses := {}
	for canonical in resolved:
		var index := skeleton.find_bone(String(resolved[canonical]))
		if index < 0:
			continue
		poses[canonical] = skeleton.get_bone_pose_rotation(index)
	player.stop()
	return poses


## The protagonist and Q each carry the shared clips their own way. A profile is written into
## the keys at bind time, so the checks are on what `bind()` builds:
##
## - the same shared clips, the same tracks on the same bones as without it — a profile never
##   widens the set of joints that move — and nothing it names is ignored;
## - every clip as long as `CLIPS` says times the profile's tempo, `get_up` still once;
## - `get_up` still starts on exactly the pose `sit_idle` holds (posture included), and the
##   seated hip is still seated;
## - the standing pose actually differs from the bare clips (the posture is applied), and by
##   the amount the profile asks for;
## - the two profiles are not one rhythm: idle, walk and talk differ in length between the
##   protagonist and Q, and the protagonist's idle is the slower one.
func _check_motion_profiles() -> void:
	var lengths := {}
	var walk_arm := {}
	for entry: Array in [
		["protagonist", PRODUCTION_PROTAGONIST, PROTAGONIST_MOTION, false],
		["Q", PRODUCTION_Q, Q_MOTION, false],
		["N", PRODUCTION_N, N_MOTION, true],
		["student", FORMER_PROTAGONIST, STUDENT_MOTION, false],
	]:
		var label := "%s with its motion profile" % String(entry[0])
		var profile := load(String(entry[2])) as CharacterMotionProfile
		if profile == null:
			_failures.append("%s: could not load %s." % [label, entry[2]])
			continue
		var negative_z := bool(entry[3])
		var packed := load(String(entry[1])) as PackedScene
		var bare_model := packed.instantiate() as Node3D
		var model := packed.instantiate() as Node3D
		root.add_child(bare_model)
		root.add_child(model)
		await process_frame
		var bare_player := _player_for(bare_model)
		var player := _player_for(model)
		var bare := CharacterAnimation.bind(bare_model, bare_player, negative_z)
		var report := CharacterAnimation.bind(model, player, negative_z, profile)
		if not bool(report.get("ok", false)) or not bool(bare.get("ok", false)):
			_failures.append("%s: bind failed: %s" % [label, String(report.get("reason", "?"))])
			bare_model.queue_free()
			model.queue_free()
			continue
		_notes.append("%s: %s" % [label, CharacterAnimation.describe(report)])
		if String(report.get("profile", "")).is_empty():
			_failures.append("%s: the bind report does not name the profile." % label)
		var ignored: Array = report.get("profile_ignored", [])
		if not ignored.is_empty():
			_failures.append("%s: the profile names bones this rig does not animate: %s" % [label, str(ignored)])
		var bare_clips: Dictionary = bare.get("clips", {})
		var clips: Dictionary = report.get("clips", {})
		if bare_clips.keys() != clips.keys():
			_failures.append("%s: the clips changed: %s vs %s" % [label, str(clips.keys()), str(bare_clips.keys())])
		var skeleton := CharacterAnimation.skeletons_in(model)[0]
		var clip_lengths := {}
		for clip_name: String in CLIPS:
			var animation := player.get_animation("%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name])
			var bare_animation := bare_player.get_animation(
				"%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]
			)
			if animation == null or bare_animation == null:
				_failures.append("%s: '%s' was not built." % [label, clip_name])
				continue
			clip_lengths[clip_name] = animation.length
			var expected := float(CharacterAnimation.CLIPS[clip_name]["length"]) * profile.tempo_for(clip_name)
			if not is_equal_approx(animation.length, expected):
				_failures.append(
					"%s: '%s' is %.3f s long, the profile asks for %.3f s." % [label, clip_name, animation.length, expected]
				)
			if animation.get_track_count() != bare_animation.get_track_count():
				_failures.append(
					"%s: '%s' has %d tracks, %d without the profile; a profile must not add joints."
					% [label, clip_name, animation.get_track_count(), bare_animation.get_track_count()]
				)
			else:
				for track in animation.get_track_count():
					if animation.track_get_path(track) != bare_animation.track_get_path(track):
						_failures.append("%s: '%s' track %d moved to another bone." % [label, clip_name, track])
						break
			var loops := not NON_LOOPING_CLIPS.has(clip_name)
			if (animation.loop_mode == Animation.LOOP_LINEAR) != loops:
				_failures.append("%s: '%s' changed its loop mode." % [label, clip_name])
			if loops:
				_check_bound_loop(label, clip_name, animation)
		lengths[String(entry[0])] = clip_lengths
		_check_transition_poses(label, player, skeleton, report.get("resolved", {}))
		# The posture is in the standing pose: the chest (or spine) sits where the profile says.
		var resolved: Dictionary = report.get("resolved", {})
		if entry[0] != "student":
			walk_arm[entry[0]] = _track_swing(player, model, skeleton, resolved, "walk", "upper_arm.L")
		if entry[0] == "N":
			var prompt := _track_swing(player, model, skeleton, resolved, "talk", "fore_arm.R")
			_notes.append("N's lesson: prompt forearm swings %.1f°" % prompt)
			if prompt < 25.0:
				_failures.append("N's lectern prompt was not bound on its forearm.")
		var standing := _first_pose(label, player, skeleton, resolved, "idle")
		var bare_standing := _first_pose(label, bare_player, CharacterAnimation.skeletons_in(bare_model)[0], resolved, "idle")
		var moved := 0
		for canonical: String in profile.posture:
			if not standing.has(canonical) or not bare_standing.has(canonical):
				continue
			var wanted := (profile.posture[canonical] as Vector3).length()
			var difference := rad_to_deg((standing[canonical] as Quaternion).angle_to(bare_standing[canonical]))
			if wanted >= 2.0 and difference >= wanted * 0.5:
				moved += 1
			_notes.append(
				"%s: idle starts with %s %.1f° from the bare clip (posture %.1f°)" % [label, canonical, difference, wanted]
			)
		if (entry[0] == "protagonist" or entry[0] == "Q") and moved < 3:
			_failures.append("%s: only %d bones carry the profile's posture in the standing pose." % [label, moved])
		if entry[0] == "protagonist":
			_check_protagonist_walk_reach(player, bare_model, bare_player, profile, resolved)
		bare_model.queue_free()
		model.queue_free()
		await process_frame
	if lengths.has("protagonist") and lengths.has("Q"):
		var protagonist_lengths: Dictionary = lengths["protagonist"]
		var q_lengths: Dictionary = lengths["Q"]
		for clip_name: String in ["idle", "walk", "talk"]:
			if is_equal_approx(float(protagonist_lengths.get(clip_name, 0.0)), float(q_lengths.get(clip_name, 0.0))):
				_failures.append("the protagonist and Q play '%s' at the same length: one body rhythm." % clip_name)
		if float(protagonist_lengths.get("idle", 0.0)) <= float(q_lengths.get("idle", 0.0)):
			_failures.append("the protagonist's idle is not slower than Q's; he is the tired one.")
		var parts: PackedStringArray = []
		for clip_name: String in CLIPS:
			parts.append(
				"%s %.2f/%.2f s"
				% [clip_name, float(protagonist_lengths.get(clip_name, 0.0)), float(q_lengths.get(clip_name, 0.0))]
			)
		_notes.append("clip lengths, protagonist / Q: %s" % ", ".join(parts))
	if walk_arm.size() == 3:
		var player_swing := float(walk_arm["protagonist"])
		var q_swing := float(walk_arm["Q"])
		var n_swing := float(walk_arm["N"])
		_notes.append("bound walk arm excursion, protagonist / Q / N: %.1f° / %.1f° / %.1f°"
			% [player_swing, q_swing, n_swing])
		if q_swing < player_swing + 10.0 or player_swing < n_swing + 3.0 or n_swing < 8.0:
			_failures.append("The walk curves lost Q's loose swing, the player's held elbows or N's small steps.")


## Undo only the walk amplitude in a separate bind of the same player rig. Measure
## the hands' actual forward/back travel, not just the upper-arm key angles.
func _check_protagonist_walk_reach(
	player: AnimationPlayer, reference_model: Node3D, reference_player: AnimationPlayer,
	profile: CharacterMotionProfile, resolved: Dictionary
) -> void:
	var reference := profile.duplicate(true) as CharacterMotionProfile
	reference.amplitude.erase("walk")
	var report := CharacterAnimation.bind(reference_model, reference_player, false, reference)
	if not bool(report.get("ok", false)):
		_failures.append("Could not bind the protagonist's unscaled walk for comparison.")
		return
	var before := _walk_reach(reference_player, resolved)
	var after := _walk_reach(player, resolved)
	_notes.append("Protagonist walk wrist travel L/R: %.3f/%.3f m -> %.3f/%.3f m"
		% [before.x, before.y, after.x, after.y])
	for side in 2:
		if before[side] < 0.04 or after[side] < 0.70 * before[side] or after[side] > 0.92 * before[side]:
			_failures.append("The protagonist's walk must modestly reduce wrist travel on both sides.")
	if not is_equal_approx(before.z, after.z) or not is_equal_approx(before.w, after.w) \
			or not is_equal_approx(player.get_animation("char/walk").length,
				reference_player.get_animation("char/walk").length):
		_failures.append("Reducing the protagonist's arm swing changed his stride or cadence.")


## Travel along character-forward of left/right hands and then left/right feet.
func _walk_reach(player: AnimationPlayer, resolved: Dictionary) -> Vector4:
	var model := player.get_parent() as Node3D
	var rig := CharacterAnimation.skeletons_in(model)[0]
	var bones := PackedInt32Array()
	for key: String in ["hand.L", "hand.R", "foot.L", "foot.R"]:
		var bone := rig.find_bone(String(resolved.get(key, "")))
		if bone < 0:
			_failures.append("Protagonist walk reach has no bone for %s." % key)
			return Vector4.ZERO
		bones.append(bone)
	if not CharacterAnimation.play(player, "walk"):
		_failures.append("Cannot play the protagonist walk reach sample.")
		return Vector4.ZERO
	var length := player.get_animation("char/walk").length
	var low := Vector4(INF, INF, INF, INF)
	var high := -low
	for step in 49:
		player.seek(length * step / 48.0, true)
		for i in bones.size():
			var depth := model.to_local(rig.to_global(rig.get_bone_global_pose(bones[i]).origin)).z
			low[i] = minf(low[i], depth)
			high[i] = maxf(high[i], depth)
	player.stop()
	return high - low


func _check_bound_loop(label: String, clip_name: String, animation: Animation) -> void:
	for track in animation.get_track_count():
		var first: Quaternion = animation.track_get_key_value(track, 0)
		var last: Quaternion = animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)
		if rad_to_deg(first.angle_to(last)) > POSE_TOLERANCE_DEGREES:
			_failures.append("%s/%s does not close on %s." % [label, clip_name, animation.track_get_path(track)])


## Measure the bound quaternion range, independent of clip duration and the rig's rest twist.
func _track_swing(
	player: AnimationPlayer, model: Node3D, skeleton: Skeleton3D, resolved: Dictionary,
	clip_name: String, canonical: String
) -> float:
	var animation := player.get_animation("char/" + clip_name)
	var path := NodePath("%s:%s" % [model.get_path_to(skeleton), resolved.get(canonical, "?")])
	var track := animation.find_track(path, Animation.TYPE_ROTATION_3D) if animation != null else -1
	var widest := 0.0
	if track >= 0:
		var count := animation.track_get_key_count(track)
		for index in count:
			var a: Quaternion = animation.track_get_key_value(track, index)
			for other in range(index + 1, count):
				widest = maxf(widest, rad_to_deg(a.angle_to(animation.track_get_key_value(track, other))))
	return widest


func _check_authored_track_validation() -> void:
	var profile := CharacterMotionProfile.new()
	var zero := Vector3.ZERO
	for entry: Array in [
		["walke", [[0.0, zero], [1.0, zero]], "unknown clip"],
		["walk", [[0.1, zero], [1.0, zero]], "endpoints"],
		["walk", [[0.0, zero], [0.0, zero], [1.0, zero]], "ordered"],
		["walk", [[0.0, zero], [1.0, Vector3.UP]], "close its loop"],
	]:
		profile.clip_tracks = {entry[0]: {"thigh.L": entry[1]}}
		if not profile.track_error(CharacterAnimation.CLIPS).contains(String(entry[2])):
			_failures.append("Invalid replacement track '%s' was not rejected (%s)." % [entry[0], entry[2]])


## The real wrapper scene must bind its own visual and switch clips, not just the
## standalone GLB preview used during rig development.
func _check_runtime_wrapper(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("%s wrapper could not be loaded at %s." % [label, path])
		return
	var visual := packed.instantiate() as CharacterVisualAnimation
	if visual == null:
		_failures.append("%s wrapper is not a CharacterVisualAnimation." % label)
		return
	var body := CharacterBody3D.new()
	root.add_child(body)
	body.add_child(visual)
	await process_frame

	if not visual.has_method("is_bound") or not bool(visual.call("is_bound")):
		_failures.append("%s wrapper did not bind its runtime animation driver." % label)
		body.queue_free()
		return
	var player := visual.get_node_or_null(^"BoundAnimationPlayer") as AnimationPlayer
	if player == null:
		_failures.append("%s wrapper has no runtime AnimationPlayer." % label)
		body.queue_free()
		return
	for clip_name in CLIPS:
		if not player.has_animation("%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]):
			_failures.append("%s wrapper is missing the '%s' clip." % [label, clip_name])

	body.velocity = Vector3(0.0, 0.0, 1.0)
	await process_frame
	if String(visual.call("get_current_clip")) != "walk":
		_failures.append("%s wrapper did not switch to walk from ancestor movement velocity." % label)
	body.velocity = Vector3(0.0, 0.0, 5.0)
	await process_frame
	if String(visual.call("get_current_clip")) != "jog":
		_failures.append(
			"%s wrapper stayed on '%s' at 5.0 m/s; above the jog threshold it has to jog."
			% [label, String(visual.call("get_current_clip"))]
		)
	body.velocity = Vector3.ZERO
	await process_frame
	if String(visual.call("get_current_clip")) != "idle":
		_failures.append("%s wrapper did not return to idle when ancestor movement stopped." % label)

	# Tween-driven location NPCs have no CharacterBody3D velocity; verify their explicit
	# movement signal uses the same state machine.
	visual.call("set_walking", true)
	if String(visual.call("get_current_clip")) != "walk":
		_failures.append("%s wrapper did not switch to walk when set_walking(true) was called." % label)
	visual.call("set_walking", false)
	if String(visual.call("get_current_clip")) != "idle":
		_failures.append("%s wrapper did not return to idle after set_walking(false)." % label)

	# Seated holds the seated clip and outranks the body: a character at a desk is not walking
	# whatever its capsule is doing.
	visual.call("set_seated", true)
	body.velocity = Vector3(0.0, 0.0, 2.0)
	await process_frame
	if String(visual.call("get_current_clip")) != "sit_idle":
		_failures.append(
			"%s wrapper played '%s' while seated; the body's velocity must not outrank sitting."
			% [label, String(visual.call("get_current_clip"))]
		)
	visual.call("set_seated", false)
	await process_frame
	if String(visual.call("get_current_clip")) != "walk":
		_failures.append("%s wrapper did not go back to locomotion when it stood up." % label)

	# The transition: it plays once, it is not a loop, and it hands back by itself.
	body.velocity = Vector3.ZERO
	await process_frame
	if not bool(visual.call("play_action", "get_up")):
		_failures.append("%s wrapper would not play the get-up transition." % label)
	elif String(visual.call("get_current_clip")) != "get_up":
		_failures.append(
			"%s wrapper reports '%s' during the get-up." % [label, String(visual.call("get_current_clip"))]
		)
	if not bool(visual.call("is_playing_action")):
		_failures.append("%s wrapper does not admit it is playing a transition." % label)
	var action_length := player.get_animation("char/get_up").length
	await _wait_seconds(action_length + 0.4)
	if bool(visual.call("is_playing_action")):
		_failures.append("%s wrapper never finished the get-up; it is stuck in the transition." % label)
	if String(visual.call("get_current_clip")) != "idle":
		_failures.append(
			"%s wrapper ended the get-up on '%s' instead of idle."
			% [label, String(visual.call("get_current_clip"))]
		)
	# A caller may fit the whole profiled action to a shorter duration without
	# changing the shared clip resource or leaving locomotion at that playback speed.
	if not bool(visual.call("play_action", "get_up", 0.35)):
		_failures.append("%s wrapper refused a duration-controlled get-up." % label)
	elif not is_equal_approx(player.speed_scale, action_length / 0.35):
		_failures.append("%s action playback ignored the profiled clip's actual length." % label)
	await _wait_seconds(0.6)
	if bool(visual.call("is_playing_action")) or String(visual.call("get_current_clip")) != "idle":
		_failures.append("%s duration-controlled action did not hand back to idle." % label)
	if not is_equal_approx(player.speed_scale, 1.0) \
			or not is_equal_approx(player.get_animation("char/get_up").length, action_length):
		_failures.append("%s action changed a shared resource or leaked its playback speed." % label)
	if not visual.dialogue_clip.is_empty():
		_check_speech_precedence(label, visual)
	_notes.append(
		"%s runtime wrapper supports: locomotion by speed, seated, and a one-shot "
		% label
		+ "get-up that hands back."
	)
	body.queue_free()
	await process_frame


## A speech request is a fallback for a stationary speaker, never an action lock.
func _check_speech_precedence(label: String, visual: CharacterVisualAnimation) -> void:
	visual.set_talking(true)
	if visual.get_current_clip() != "talk":
		_failures.append("%s did not start talking while still." % label)
	visual.report_velocity(Vector3.RIGHT * 1.6)
	if visual.get_current_clip() != "walk":
		_failures.append("%s's talk interrupted locomotion." % label)
	visual.set_seated(true)
	if visual.get_current_clip() != "sit_idle":
		_failures.append("%s's talk or locomotion interrupted the seat." % label)
	visual.sample_action("get_up", 0.5)
	if visual.get_current_clip() != "get_up":
		_failures.append("%s's seat interrupted a staged one-shot." % label)
	visual.clear_reported_velocity()
	visual.set_seated(false)
	visual.release_sampled_action()
	if visual.get_current_clip() != "talk":
		_failures.append("%s did not resume the current line after the action." % label)
	visual.set_talking(false)


## The A1 visual has no body or movement controller. Its speech, like its idle,
## must preserve the chair contacts and cannot take over as a staged action.
func _check_seated_student(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("classroom student wrapper could not be loaded at %s." % path)
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var visual := packed.instantiate() as CharacterVisualAnimation
	if visual == null:
		_failures.append("classroom student wrapper is not a CharacterVisualAnimation.")
		holder.queue_free()
		return
	holder.add_child(visual)
	await process_frame
	await process_frame
	if not visual.is_bound():
		_failures.append("classroom student did not bind: %s" % str(visual.get_bind_report()))
	elif visual.get_current_clip() != "sit_idle" or not visual.is_seated():
		_failures.append(
			"classroom student opened on '%s' (seated %s); it has to sit."
			% [visual.get_current_clip(), visual.is_seated()]
		)
	if visual.get_locomotion_body() != null:
		_failures.append("classroom student found a body to follow; it has none.")
	await _wait_seconds(0.5)
	if visual.get_current_clip() != "sit_idle":
		_failures.append("classroom student got up by itself ('%s')." % visual.get_current_clip())
	if visual.is_bound():
		_check_seated_speech(visual)
	holder.queue_free()
	await process_frame


func _check_seated_speech(visual: CharacterVisualAnimation) -> void:
	var player := visual.get_animation_player()
	var rig := visual.get_skeleton()
	var resolved: Dictionary = visual.get_bind_report()["resolved"]
	var contacts := {}
	player.seek(0.0, true)
	for key: String in ["thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]:
		var bone := rig.find_bone(String(resolved[key]))
		contacts[bone] = rig.get_bone_global_pose(bone)
	visual.set_talking(true)
	visual.report_velocity(Vector3.RIGHT * 1.6)
	if visual.get_current_clip() != "sit_talk" or visual.is_playing_action() or not visual.is_seated():
		_failures.append("A1 speech did not stay in the seated state, independent of motion and actions.")
		return
	var clip := player.get_animation("char/sit_talk")
	var worst := 0.0
	for index in range(25):
		player.seek(clip.length * index / 24.0, true)
		for bone: int in contacts:
			var rest: Transform3D = contacts[bone]
			var pose := rig.get_bone_global_pose(bone)
			worst = maxf(worst, rest.origin.distance_to(pose.origin))
			if not pose.basis.is_equal_approx(rest.basis):
				_failures.append("A1 speech rotated a loaded joint: %s." % rig.get_bone_name(bone))
				return
	if worst > 0.002:
		_failures.append("A1 speech shifted a loaded joint %.4f m." % worst)
	visual.hide()
	if visual.is_talking() or visual.get_current_clip() != "sit_idle":
		_failures.append("A1 speech survived hiding the student.")
	visual.show()
	visual.clear_reported_velocity()
	_notes.append("classroom student: seated talk keeps all six loaded joints (%.4f m drift)." % worst)


## An AnimationPlayer that is a child of the model, which is what makes a track path of
## "Skeleton3D:Spine" mean this model's skeleton.
func _player_for(model: Node3D) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "BoundAnimationPlayer"
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	return player


## Real seconds, not frames: the animation player advances on the clock, and a transition has
## to be seen to finish rather than be assumed to.
func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


## GitHub cuts one annotation off at about 4 KB. Seven clips on four rigs is past that, and the
## cut lands at the end — exactly where the speeds and the seated-hip numbers are. So the notes
## go out in chunks: a notice that drops half the evidence is worse than two notices.
const NOTICE_CHUNK_CHARS := 3000


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	var chunks: PackedStringArray = PackedStringArray()
	var current := ""
	for line in _notes:
		if current != "" and current.length() + line.length() + 1 > NOTICE_CHUNK_CHARS:
			chunks.append(current)
			current = ""
		current = line if current == "" else "%s|%s" % [current, line]
	if current != "":
		chunks.append(current)
	for index in chunks.size():
		print(
			"::notice title=character animation (%d/%d)::%s"
			% [index + 1, chunks.size(), chunks[index]]
		)
