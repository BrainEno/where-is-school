extends SceneTree
## The four clips in `CharacterAnimation` drive every rigged character in the repository, and
## each one is authored against canonical bone names rather than a rig's own.
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
##   4. both rigs get the same four clip names despite naming their bones differently;
##   5. both production models have skeletons and bind;
##   6. the actual protagonist and Q wrapper scenes create their runtime AnimationPlayers
##      and switch between idle and walk when their movement state changes.

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
	"wave": "upper_arm.R",
	"talk": "head",
}

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

	Harness.stage = "the production wrapper scenes"
	await _check_runtime_wrapper("protagonist", "res://scenes/environment/characters/protagonist.tscn")
	await _check_runtime_wrapper("Q", "res://scenes/environment/characters/q.tscn")

	_report()
	Harness.finish(
		self, _failures,
		"both rigged characters play the same four clips, and every track points at a bone "
		+ "that exists."
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
		_check_clip(label, player, skeleton, resolved, clip_name)
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
	label: String, player: AnimationPlayer, skeleton: Skeleton3D, resolved: Dictionary, clip_name: String
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
	# The bone has to return to where it started, or a looping clip limps.
	var returned := rad_to_deg(samples[0].angle_to(samples[samples.size() - 1]))
	_notes.append(
		"%s/%s: %s turns %.1f° and returns to within %.2f°" % [label, clip_name, bone, widest, returned]
	)
	if widest < MOVED_DEGREES:
		_failures.append(
			"%s: clip '%s' moved '%s' by %.2f° at most; the track is not reaching the bone."
			% [label, clip_name, bone, widest]
		)
	if returned > MOVED_DEGREES:
		_failures.append(
			"%s: clip '%s' ends %.2f° away from where it starts, so the loop jumps."
			% [label, clip_name, returned]
		)
	player.stop()


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
	root.add_child(visual)
	await process_frame

	if not visual.has_method("is_bound") or not bool(visual.call("is_bound")):
		_failures.append("%s wrapper did not bind its runtime animation driver." % label)
		visual.queue_free()
		return
	var player := visual.get_node_or_null(^"BoundAnimationPlayer") as AnimationPlayer
	if player == null:
		_failures.append("%s wrapper has no runtime AnimationPlayer." % label)
		visual.queue_free()
		return
	for clip_name in CLIPS:
		if not player.has_animation("%s/%s" % [String(CharacterAnimation.LIBRARY_NAME), clip_name]):
			_failures.append("%s wrapper is missing the '%s' clip." % [label, clip_name])

	visual.call("set_walking", true)
	if String(visual.call("get_current_clip")) != "walk":
		_failures.append("%s wrapper did not switch to walk when movement began." % label)
	visual.call("set_walking", false)
	if String(visual.call("get_current_clip")) != "idle":
		_failures.append("%s wrapper did not return to idle when movement stopped." % label)
	_notes.append("%s runtime wrapper binds idle/walk/wave/talk and switches locomotion." % label)
	visual.queue_free()
	await process_frame


## An AnimationPlayer that is a child of the model, which is what makes a track path of
## "Skeleton3D:Spine" mean this model's skeleton.
func _player_for(model: Node3D) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "BoundAnimationPlayer"
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	return player


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	print("::notice title=character animation::%s" % "|".join(_notes))
