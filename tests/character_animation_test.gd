extends SceneTree
## The seven clips in `CharacterAnimation` drive every rigged character in the repository,
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
##   4. both rigs get the same seven clip names despite naming their bones differently;
##   5. both production models have skeletons and bind;
##   6. a transition does not loop: `get_up` is built with `LOOP_NONE`, ends on the rest pose,
##      and starts from *exactly* the pose `sit_idle` holds, so the two cannot drift apart;
##   7. the actual protagonist and Q wrapper scenes create their runtime AnimationPlayers and
##      switch between idle, walk and jog by the body's speed, hold `sit_idle` while seated,
##      and hand back to locomotion when a one-shot action finishes;
##   8. the poses are the poses those clips are *about*: the walk holds its knees straight in
##      front and folds them behind, the seated clip puts the thighs forward and the shins
##      down instead of folding both legs backwards, and no clip lifts an ankle above a hip.
##
## Check 8 exists because check 3 was not enough. A rotation about a bone's local axis turns
## by the same number of degrees whichever way it is signed, so every clip in this file passed
## while the walk sent its knees the wrong way round: the character walked in a seated pose,
## with the thigh forward and the shin hanging under it, and `sit_idle` folded both legs
## behind its hips so the ankles ended up above the hips. Angles cannot see that; the geometry
## of the resulting pose can, so these checks are in metres, in the rig's own frame.

const Harness = preload("res://tests/test_harness.gd")

const RIGGED_Q := "res://scenes/dev/animation_retarget_test/q_rigged.glb"
const RETARGETED_PROTAGONIST := "res://scenes/dev/animation_retarget_test/protagonist_retarget_ready.glb"
const PRODUCTION_PROTAGONIST := "res://assets/models/protagonist/protagonist.glb"
const PRODUCTION_Q := "res://assets/models/q/q.glb"

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
	"wave": "upper_arm.R",
	"talk": "head",
	"get_up": "thigh.L",
}

## The one clip that is a transition rather than a state. It is checked differently: it ends
## on the rest pose instead of returning to its first key.
const TRANSITIONS := ["get_up"]

## Degrees two keys of the same bone may differ by and still count as the same pose.
const POSE_TOLERANCE_DEGREES := 0.5

## How many times each clip is sampled when its pose is measured in the world. Fine enough
## that the knee is caught near the moment it is most folded.
const POSE_SAMPLES := 24
## How far a hip may flex in a step before the clip is sitting rather than walking. A seated
## thigh is ~82°; a walking one is under 20° at the extremes and 30° in a jog.
const STEP_HIP_FLEX_LIMIT := {"walk": 40.0, "jog": 46.0}
## When a knee is at its most closed, the thigh may be at most this far forward. A knee that
## folds while the thigh is swung forward is a leg held out from a seat — the shape the
## shipped walk had, in both legs, at every instant.
const SEATED_THIGH_LIMIT_DEGREES := 12.0
## A knee has to close at least this much somewhere in a step, or it never bends at all.
const MIN_KNEE_CLOSURE_DEGREES := 25.0
## How far a foot has to leave its rest height during a step, in metres.
const MIN_FOOT_LIFT := 0.03
## How far apart the two ankles have to be along forward at the start of a step, in metres.
const MIN_STRIDE := 0.15
## A knee may not extend past the straight line its rest pose defines by more than this much
## of the shin's own direction. Measured against the rest pose, because two of the rigs stand
## with a knee that is already a few hundredths bent.
const MAX_HYPEREXTENSION := 0.03
## A seated pose, measured the same way: thighs forward, shins down under the knees.
const SEATED_HIP_FLEX_MIN := 60.0
const SEATED_KNEE_CLOSURE_MIN := 60.0
const SEATED_KNEE_AHEAD_MIN := 0.18
const SEATED_ANKLE_DROP_MIN := 0.20

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
	await _check_model("Q (production)", PRODUCTION_Q, true)

	Harness.stage = "the sprint the jog clip exists for"
	_check_jog_threshold()

	Harness.stage = "the production wrapper scenes"
	await _check_runtime_wrapper("protagonist", "res://scenes/environment/characters/protagonist.tscn")
	await _check_runtime_wrapper("Q", "res://scenes/environment/characters/q.tscn")

	_report()
	Harness.finish(
		self, _failures,
		"both rigged characters play the same seven clips, every track points at a bone that "
		+ "exists, the transition does not loop, and the seats and speeds are wired."
	)


## Binds one model and runs the clip checks. `should_bind` false means the model is expected
## to have no skeleton, and the report has to say so instead of half-working.
func _check_model(label: String, path: String, should_bind: bool) -> Variant:
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
	var report := CharacterAnimation.bind(model, player)
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
		_check_clip(label, player, skeleton, resolved, clip_name, not TRANSITIONS.has(clip_name))
	_check_transition_poses(label, player, skeleton, resolved)
	_check_pose_geometry(label, player, skeleton, resolved)
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
	loops: bool
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
	if widest < MOVED_DEGREES:
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
	if not loops:
		# Bone poses are relative to the rest pose, so "standing up" is the identity
		# quaternion, not the bone's rest rotation.
		var last_pose: Quaternion = samples[samples.size() - 1]
		var away_from_rest := rad_to_deg(last_pose.angle_to(Quaternion.IDENTITY))
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
		var hip := rad_to_deg((sitting["thigh.L"] as Quaternion).angle_to(Quaternion.IDENTITY))
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


## Measures the pose each clip produces, in metres, in the rig's own frame.
##
## The other checks ask whether a bone turned; this one asks what the body did with it. It is
## the check that would have caught the shipped walk, which folded every knee while its thigh
## was swung forward — a walk performed in a seat — and a `sit_idle` that folded both legs
## behind the hips, leaving the ankles above them. None of that is visible in an angle, because
## a rotation signed the wrong way is the same number of degrees.
func _check_pose_geometry(
	label: String, player: AnimationPlayer, skeleton: Skeleton3D, resolved: Dictionary
) -> void:
	var frame := CharacterAnimation.pose_frame(skeleton, {"resolved": resolved})
	var forward: Vector3 = frame["forward"]
	_notes.append("%s: the body faces (%.2f, %.2f, %.2f)" % [label, forward.x, forward.y, forward.z])
	var rest := _global_poses(skeleton, {})
	var rest_ankle := {}
	var rest_flex := {}
	var rest_closure := {}
	var rest_overhang := {}
	for side in ["L", "R"]:
		var hip := _origin(rest, skeleton, resolved, "thigh." + side)
		var knee := _origin(rest, skeleton, resolved, "shin." + side)
		var ankle := _origin(rest, skeleton, resolved, "foot." + side)
		# The height only: `float()` on a Vector3 is an invalid call, and the check it feeds
		# would then measure nothing and pass.
		rest_ankle[side] = ankle.y
		rest_flex[side] = _forward_tilt(hip, knee, forward)
		rest_closure[side] = _knee_closure(hip, knee, ankle)
		rest_overhang[side] = _shin_overhang(hip, knee, ankle, forward)

	for clip_name in ["walk", "jog", "sit_idle", "get_up"]:
		var animation: Animation = player.get_animation(
			"%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]
		)
		if animation == null:
			continue
		var flex_max := {"L": 0.0, "R": 0.0}
		var closure_max := {"L": 0.0, "R": 0.0}
		# The thigh tilt at the instant the knee is most folded: this is the number that says
		# "seated" rather than "stepping".
		var thigh_at_closure := {"L": 0.0, "R": 0.0}
		var closure_there := {"L": 0.0, "R": 0.0}
		var lift := {"L": -1.0, "R": -1.0}
		var posed := false
		for step in POSE_SAMPLES:
			var time := animation.length * float(step) / float(POSE_SAMPLES)
			var glob := _global_poses(skeleton, _pose_at(skeleton, animation, time))
			if glob.is_empty():
				continue
			posed = true
			var hip_height := _origin(glob, skeleton, resolved, "thigh.L").y
			for side in ["L", "R"]:
				var hip := _origin(glob, skeleton, resolved, "thigh." + side)
				var knee := _origin(glob, skeleton, resolved, "shin." + side)
				var ankle := _origin(glob, skeleton, resolved, "foot." + side)
				if ankle == Vector3.ZERO:
					continue
				if ankle.y > hip_height + 0.02:
					_failures.append(
						"%s: at %.2f s in '%s' the %s ankle is at %.2f m, above the hip at %.2f m;"
						% [label, time, clip_name, side, ankle.y, hip_height]
						+ " the clip folds the leg up over the body instead of under it."
					)
				var overhang: float = _shin_overhang(hip, knee, ankle, forward) - float(rest_overhang[side])
				if overhang > MAX_HYPEREXTENSION:
					_failures.append(
						"%s: at %.2f s in '%s' the %s knee is %.2f bent the wrong way; a knee only"
						% [label, time, clip_name, side, overhang]
						+ " folds one way."
					)
				var flex: float = _forward_tilt(hip, knee, forward) - float(rest_flex[side])
				var closure: float = _knee_closure(hip, knee, ankle) - float(rest_closure[side])
				flex_max[side] = maxf(float(flex_max[side]), flex)
				if closure >= float(closure_max[side]):
					closure_max[side] = closure
					thigh_at_closure[side] = flex
					closure_there[side] = closure
				lift[side] = maxf(float(lift[side]), ankle.y - float(rest_ankle[side]))
		if not posed:
			continue
		_notes.append(
			"%s/%s: hip %.0f° forward, knee %.0f° closed, foot %.3f m off the ground"
			% [label, clip_name, float(flex_max["L"]), float(closure_max["L"]), float(lift["L"])]
		)
		if STEP_HIP_FLEX_LIMIT.has(clip_name):
			var limit := float(STEP_HIP_FLEX_LIMIT[clip_name])
			for side in ["L", "R"]:
				if float(flex_max[side]) > limit:
					_failures.append(
						"%s: '%s' flexes the %s hip %.0f° at most, past the %.0f° a step gets; that"
						% [label, clip_name, side, float(flex_max[side]), limit]
						+ " is a thigh held out in front of a seated body."
					)
				if float(closure_max[side]) < MIN_KNEE_CLOSURE_DEGREES:
					_failures.append(
						"%s: '%s' never closes the %s knee past %.0f°, so the leg swings stiff."
						% [label, clip_name, side, float(closure_max[side])]
					)
				if float(lift[side]) < MIN_FOOT_LIFT:
					_failures.append(
						"%s: '%s' lifts the %s foot %.3f m at most; the leg never leaves the floor."
						% [label, clip_name, side, float(lift[side])]
					)
				if float(thigh_at_closure[side]) > SEATED_THIGH_LIMIT_DEGREES:
					_failures.append(
						"%s: '%s' folds the %s knee to %.0f° while the thigh is %.0f° forward — the"
						% [label, clip_name, side, float(closure_there[side]), float(thigh_at_closure[side])]
						+ " shin hangs under a seat, which is what the walk looked like."
					)
			_check_step_pose(label, clip_name, skeleton, resolved, animation, forward)
		elif clip_name == "sit_idle":
			_check_seated_pose(label, skeleton, resolved, animation, forward, flex_max, closure_max)


## A seated pose, measured where it matters: the knees are out in front of the body and the
## shins hang under them. Folding both legs backwards folds the character into itself.
func _check_seated_pose(
	label: String,
	skeleton: Skeleton3D,
	resolved: Dictionary,
	animation: Animation,
	forward: Vector3,
	flex_max: Dictionary,
	closure_max: Dictionary
) -> void:
	if float(flex_max["L"]) < SEATED_HIP_FLEX_MIN or float(closure_max["L"]) < SEATED_KNEE_CLOSURE_MIN:
		_failures.append(
			"%s: sit_idle flexes the hip %.0f° and closes the knee %.0f°; sitting is 60° of each."
			% [label, float(flex_max["L"]), float(closure_max["L"])]
		)
		return
	var glob := _global_poses(skeleton, _pose_at(skeleton, animation, 0.0))
	var hip := _origin(glob, skeleton, resolved, "thigh.L")
	var knee := _origin(glob, skeleton, resolved, "shin.L")
	var ankle := _origin(glob, skeleton, resolved, "foot.L")
	var ahead := (knee - hip).dot(forward)
	var drop := knee.y - ankle.y
	_notes.append(
		"%s/sit_idle: knees %.2f m in front of the hips, ankles %.2f m under them"
		% [label, ahead, drop]
	)
	if ahead < SEATED_KNEE_AHEAD_MIN:
		_failures.append(
			"%s: sit_idle puts the knees %.2f m in front of the hips; a seated thigh is forward of"
			% [label, ahead]
			+ " the body, not behind it."
		)
	if drop < SEATED_ANKLE_DROP_MIN:
		_failures.append(
			"%s: sit_idle holds the ankles %.2f m below the knees; the shins are not hanging down."
			% [label, drop]
		)


## The two things a step has that a single pose does not: the feet are apart, and the arm on one
## side swings with the leg on the other.
func _check_step_pose(
	label: String,
	clip_name: String,
	skeleton: Skeleton3D,
	resolved: Dictionary,
	animation: Animation,
	forward: Vector3
) -> void:
	var glob := _global_poses(skeleton, _pose_at(skeleton, animation, 0.0))
	var hips := _origin(glob, skeleton, resolved, "hips")
	var left_foot := _origin(glob, skeleton, resolved, "foot.L")
	var right_foot := _origin(glob, skeleton, resolved, "foot.R")
	var left_hand := _origin(glob, skeleton, resolved, "hand.L")
	var stride := (left_foot - right_foot).dot(forward)
	var hand_side := (left_hand - hips).dot(forward)
	var foot_side := (left_foot - hips).dot(forward)
	_notes.append(
		"%s/%s: ankles %.2f m apart, left hand %+.2f m, left foot %+.2f m"
		% [label, clip_name, stride, hand_side, foot_side]
	)
	if absf(stride) < MIN_STRIDE:
		_failures.append(
			"%s: '%s' starts with the ankles %.3f m apart along forward; a step needs %.2f m."
			% [label, clip_name, stride, MIN_STRIDE]
		)
	if hand_side * foot_side > 0.0:
		_failures.append(
			"%s: '%s' swings the left arm with the left leg (hand %+.2f m, foot %+.2f m); arms"
			% [label, clip_name, hand_side, foot_side]
			+ " counterbalance the opposite leg."
		)


## The bone poses of a clip at one moment, keyed by bone index.
func _pose_at(skeleton: Skeleton3D, animation: Animation, time: float) -> Dictionary:
	var poses := {}
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(animation.track_get_path(track).get_concatenated_subnames())
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		poses[index] = _rotation_at(animation, track, time)
	return poses


## Linear between keys, which is what a rotation track with the default interpolation does.
func _rotation_at(animation: Animation, track: int, time: float) -> Quaternion:
	var count := animation.track_get_key_count(track)
	if count == 0:
		return Quaternion.IDENTITY
	if time <= animation.track_get_key_time(track, 0):
		return animation.track_get_key_value(track, 0) as Quaternion
	if time >= animation.track_get_key_time(track, count - 1):
		return animation.track_get_key_value(track, count - 1) as Quaternion
	for key in range(count - 1):
		var start := animation.track_get_key_time(track, key)
		var end := animation.track_get_key_time(track, key + 1)
		if time >= start and time <= end:
			var span := end - start
			var blend := 0.0 if is_zero_approx(span) else (time - start) / span
			var before: Quaternion = animation.track_get_key_value(track, key)
			var after: Quaternion = animation.track_get_key_value(track, key + 1)
			return before.slerp(after, blend)
	return animation.track_get_key_value(track, count - 1) as Quaternion


## Every bone's transform in the skeleton's own space, from a set of pose rotations.
## A Skeleton3D composes them as `global = parent_global * rest_local * pose`.
func _global_poses(skeleton: Skeleton3D, poses: Dictionary) -> Dictionary:
	var memo := {}
	for index in skeleton.get_bone_count():
		_global_pose(skeleton, index, poses, memo)
	return memo


func _global_pose(
	skeleton: Skeleton3D, index: int, poses: Dictionary, memo: Dictionary
) -> Transform3D:
	if memo.has(index):
		return memo[index]
	var local := skeleton.get_bone_rest(index)
	if poses.has(index):
		local = local * Transform3D(Basis(poses[index] as Quaternion), Vector3.ZERO)
	var parent := skeleton.get_bone_parent(index)
	if parent >= 0:
		local = _global_pose(skeleton, parent, poses, memo) * local
	memo[index] = local
	return local


## Where a canonical bone's origin ended up. Zero when the rig does not have the bone.
func _origin(
	poses: Dictionary, skeleton: Skeleton3D, resolved: Dictionary, canonical: String
) -> Vector3:
	var name: Variant = resolved.get(canonical)
	if name == null:
		return Vector3.ZERO
	var index := skeleton.find_bone(String(name))
	if index < 0 or not poses.has(index):
		return Vector3.ZERO
	var placed: Transform3D = poses[index]
	return placed.origin


## How far a limb is swung towards the front of the body, in degrees.
func _forward_tilt(hip: Vector3, knee: Vector3, forward: Vector3) -> float:
	var along := knee - hip
	if along.length() < 0.0001:
		return 0.0
	return rad_to_deg(asin(clampf(along.normalized().dot(forward), -1.0, 1.0)))


## How far a knee is folded, in degrees; zero is a straight leg.
func _knee_closure(hip: Vector3, knee: Vector3, ankle: Vector3) -> float:
	var thigh_dir := knee - hip
	var shin_dir := ankle - knee
	if thigh_dir.length() < 0.0001 or shin_dir.length() < 0.0001:
		return 0.0
	return rad_to_deg(thigh_dir.normalized().angle_to(shin_dir.normalized()))


## Positive when the shin points further forward than the thigh, which is a knee bending the
## wrong way. Subtracted from the rest pose, because two of the rigs stand slightly bent.
func _shin_overhang(hip: Vector3, knee: Vector3, ankle: Vector3, forward: Vector3) -> float:
	var thigh_dir := knee - hip
	var shin_dir := ankle - knee
	if thigh_dir.length() < 0.0001 or shin_dir.length() < 0.0001:
		return 0.0
	return shin_dir.normalized().dot(forward) - thigh_dir.normalized().dot(forward)


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


## The real wrapper scene must bind its own visual and switch clips, not just the
## standalone GLB preview used during rig development.
func _check_runtime_wrapper(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_failures.append("%s wrapper could not be loaded at %s." % [label, path])
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		_failures.append("%s wrapper is not a Node3D." % label)
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
	_notes.append(
		"%s runtime wrapper plays seven clips: locomotion by speed, seated, and a one-shot "
		% label
		+ "get-up that hands back."
	)
	body.queue_free()
	await process_frame


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
