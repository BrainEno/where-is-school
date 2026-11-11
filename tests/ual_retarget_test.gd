extends SceneTree
## The Universal Animation Library's clips, retargeted onto the protagonist.
##
## `AnimationRetarget.bake()` claims three things, and each of them is a way to be silently
## wrong, so each is measured here:
##
##   1. the two rigs are paired bone by bone — the library says `upperarm_l`, the character
##      says `LeftUpperArm`, and the mapping is the humanoid profile in between;
##   2. what comes out actually moves the character, measured by playing the baked clip and
##      reading the skeleton's bone poses, not by looking at the track count;
##   3. the retarget really is rest-relative: at every sampled instant, the *change* in the
##      source bone's global rotation and the change in the target's are the same rotation,
##      which is only true if the hierarchy was recomposed correctly. A rename-only "retarget"
##      passes 1 and 2 and fails this one.
##
## The committed library is then checked the same way, because that is the file the dev scene
## loads: 42 clips, and every track path has to name a bone that exists on the character.

const Harness = preload("res://tests/test_harness.gd")

const UAL := "res://scenes/dev/animation_retarget_test/UAL1_Standard.glb"
const PROTAGONIST := "res://scenes/dev/animation_retarget_test/protagonist_retarget_ready.glb"
const BAKED := "res://scenes/dev/animation_retarget_test/protagonist_ual.res"

## Canonical bones both rigs have: 19, all of them.
const MIN_PAIRS := 18
## Degrees the character has to move before a clip counts as having arrived.
const MOVED_DEGREES := 3.0
## How far the source and the target may disagree about the *same* rotation change.
const REST_TOLERANCE_DEGREES := 0.5
## Clips the committed library must have (43 in the library, minus the T-pose reference).
const MIN_COMMITTED_CLIPS := 40

## Three pairs worth naming: one the library spells in UE style, one that has no prefix at
## all, and one where the character's own bone carries Godot's `_2` suffix.
const SPOT_CHECKS := {
	"upper_arm.L": ["upperarm_l", "LeftUpperArm"],
	"shin.R": ["calf_r", "RightLowerLeg"],
	"hips": ["pelvis", "Hips"],
}

var _failures: Array[String] = []
var _notes: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 420.0, "ual_retarget_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "the library and the character"
	var ual := (load(UAL) as PackedScene).instantiate()
	root.add_child(ual)
	var protagonist := (load(PROTAGONIST) as PackedScene).instantiate()
	root.add_child(protagonist)
	await process_frame

	var source_player := _first(ual, "AnimationPlayer") as AnimationPlayer
	var source_skeleton := _first(ual, "Skeleton3D") as Skeleton3D
	var target_skeleton := _first(protagonist, "Skeleton3D") as Skeleton3D
	if source_player == null or source_skeleton == null or target_skeleton == null:
		_failures.append("the library or the character is missing its skeleton or its player")
		_finish()
		return

	Harness.stage = "the bones pair up"
	var mapping := AnimationRetarget.map_bones(source_skeleton, target_skeleton)
	var pairs: Array = mapping["pairs"]
	var resolved: Dictionary = mapping["resolved"]
	var sample: Array[String] = []
	for canonical in ["hips", "spine", "upper_arm.L", "fore_arm.R", "thigh.L", "foot.R"]:
		if resolved.has(canonical):
			sample.append(
				"%s=%s→%s" % [canonical, resolved[canonical]["source"], resolved[canonical]["target"]]
			)
	_notes.append("paired %d bone(s): %s" % [pairs.size(), ", ".join(sample)])
	if pairs.size() < MIN_PAIRS:
		_failures.append(
			"only %d bones paired; the character would move as a fraction of itself." % pairs.size()
		)
	for canonical in SPOT_CHECKS:
		var expected: Array = SPOT_CHECKS[canonical]
		if not resolved.has(canonical):
			_failures.append("'%s' did not pair; the library or the character lost it." % canonical)
			continue
		var pair: Dictionary = resolved[canonical]
		if String(pair["source"]) != String(expected[0]) or String(pair["target"]) != String(expected[1]):
			_failures.append(
				"'%s' paired %s→%s, expected %s→%s."
				% [canonical, pair["source"], pair["target"], expected[0], expected[1]]
			)

	Harness.stage = "a clip bakes and moves the character"
	var clip_name := _clip_containing(source_player, "walk")
	if clip_name.is_empty():
		_failures.append("the library has no walk clip; the bake would have nothing to show.")
		_finish()
		return
	var skeleton_path := protagonist.get_path_to(target_skeleton)
	var report := AnimationRetarget.bake(
		source_skeleton, source_player, target_skeleton, [clip_name], 30.0, skeleton_path
	)
	var library: AnimationLibrary = report["library"]
	if library == null:
		_failures.append("the bake produced no library: %s" % String(report.get("reason", "?")))
		_finish()
		return
	_notes.append(AnimationRetarget.describe(report))
	_check_track_paths(library, clip_name, target_skeleton)

	var player := AnimationPlayer.new()
	player.name = "BakedPlayer"
	protagonist.add_child(player)
	player.root_node = player.get_path_to(protagonist)
	player.add_animation_library(&"baked", library)
	_check_motion(player, "%s/%s" % ["baked", clip_name], target_skeleton, clip_name)
	_check_rest_relative(
		source_player, source_skeleton, target_skeleton, player, clip_name, pairs
	)

	Harness.stage = "the committed library"
	_check_committed()

	_finish()


## Every track path has to name a bone that exists, or the clip plays in silence.
func _check_track_paths(library: AnimationLibrary, clip_name: String, skeleton: Skeleton3D) -> void:
	var animation := library.get_animation(clip_name)
	if animation == null:
		_failures.append("the baked library has no clip called '%s'." % clip_name)
		return
	var unknown: Array[String] = []
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var bone := path.get_concatenated_subnames()
		if bone.is_empty() or skeleton.find_bone(bone) < 0:
			unknown.append("%s (%s)" % [String(bone), String(path)])
	if not unknown.is_empty():
		_failures.append(
			"the baked clip '%s' has %d track(s) naming bones the character does not have: %s"
			% [clip_name, unknown.size(), ", ".join(unknown)]
		)


## The clip has to move the character: seek it and read the bones back.
func _check_motion(
	player: AnimationPlayer, full_name: String, skeleton: Skeleton3D, label: String
) -> void:
	var animation := player.get_animation(full_name)
	if animation == null:
		_failures.append("'%s' did not reach the player." % full_name)
		return
	var widest := 0.0
	var widest_bone := ""
	var moved := 0
	player.play(full_name)
	for track in animation.get_track_count():
		var bone := animation.track_get_path(track).get_concatenated_subnames()
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var lowest := INF
		var highest := -INF
		for step in 5:
			player.seek(animation.length * float(step) / 4.0, true)
			var angle := rad_to_deg(skeleton.get_bone_pose_rotation(index).get_angle())
			lowest = minf(lowest, angle)
			highest = maxf(highest, angle)
		if highest - lowest > 0.001:
			moved += 1
		if highest - lowest > widest:
			widest = highest - lowest
			widest_bone = String(bone)
	player.stop()
	_notes.append(
		"%s: %d of %d bone(s) move, %s by %.1°" % [label, moved, animation.get_track_count(), widest_bone, widest]
	)
	if widest < MOVED_DEGREES:
		_failures.append(
			"'%s' moves '%s' by %.2f° at most; the retarget is not reaching the bones."
			% [label, widest_bone, widest]
		)


## The change in the source bone's global rotation and the change in the target's must be the
## same rotation. That is what "rest-relative" means, and it is the check that catches a bake
## which renamed the tracks without recomposing the hierarchy.
func _check_rest_relative(
	source_player: AnimationPlayer,
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	target_player: AnimationPlayer,
	clip_name: String,
	pairs: Array
) -> void:
	var source_animation := source_player.get_animation(clip_name)
	var target_animation := target_player.get_animation("%s/%s" % ["baked", clip_name])
	if source_animation == null or target_animation == null:
		return
	var worst := 0.0
	var worst_bone := ""
	for step in 4:
		var moment := source_animation.length * float(step) / 3.0
		source_player.play(clip_name)
		source_player.seek(moment, true)
		target_player.play("%s/%s" % ["baked", clip_name])
		target_player.seek(moment, true)
		for pair: Dictionary in pairs:
			var source_index := int(pair["source"])
			var target_index := int(pair["target"])
			var source_change: Quaternion = (
				source_skeleton.get_bone_global_rest(source_index).basis.get_rotation_quaternion().inverse()
				* source_skeleton.get_bone_global_pose(source_index).basis.get_rotation_quaternion()
			)
			var target_change: Quaternion = (
				target_skeleton.get_bone_global_rest(target_index).basis.get_rotation_quaternion().inverse()
				* target_skeleton.get_bone_global_pose(target_index).basis.get_rotation_quaternion()
			)
			var difference := absf(
				rad_to_deg(source_change.normalized().angle_to(target_change.normalized()))
			)
			if difference > worst:
				worst = difference
				worst_bone = String(pair["canonical"])
	source_player.stop()
	target_player.stop()
	_notes.append(
		"rest-relative check: worst disagreement %.2f° on '%s'" % [worst, worst_bone]
	)
	if worst > REST_TOLERANCE_DEGREES:
		_failures.append(
			"the retargeted pose is %.2f° away from the library's rotation on '%s'; the bones are "
			% [worst, worst_bone]
			+ "renamed rather than retargeted, or the parent chain was not recomposed."
		)


## The file the dev scene loads: it has to exist, hold the clips, and address bones that this
## character has.
func _check_committed() -> void:
	var resource := load(BAKED)
	if resource == null:
		_failures.append(
			"%s is missing. Run `godot --headless --path . --script "
			% BAKED
			+ "res://tools/bake_animation_retarget.gd`, or dispatch the bake-animation-retarget "
			+ "workflow, and commit the result."
		)
		return
	var library := resource as AnimationLibrary
	if library == null:
		_failures.append("%s is a %s, not an AnimationLibrary." % [BAKED, resource.get_class()])
		return
	var names := library.get_animation_list()
	_notes.append("committed library: %d clip(s)" % names.size())
	if names.size() < MIN_COMMITTED_CLIPS:
		_failures.append(
			"the committed library has %d clip(s), fewer than the %d the library provides."
			% [names.size(), MIN_COMMITTED_CLIPS]
		)
	var protagonist := (load(PROTAGONIST) as PackedScene).instantiate()
	root.add_child(protagonist)
	var skeleton := _first(protagonist, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		_failures.append("the committed library cannot be checked: no skeleton to address.")
		return
	var player := AnimationPlayer.new()
	player.name = "CommittedPlayer"
	protagonist.add_child(player)
	player.root_node = player.get_path_to(protagonist)
	player.add_animation_library(&"ual", library)
	var empty: Array[String] = []
	for clip_name in names:
		var animation := library.get_animation(clip_name)
		if animation.get_track_count() == 0:
			empty.append(String(clip_name))
			continue
		for track in animation.get_track_count():
			var bone := animation.track_get_path(track).get_concatenated_subnames()
			if skeleton.find_bone(bone) < 0:
				_failures.append(
					"committed clip '%s' addresses bone '%s', which the character does not have."
					% [clip_name, String(bone)]
				)
				break
	if not empty.is_empty():
		_failures.append(
			"%d committed clip(s) have no tracks at all: %s"
			% [empty.size(), ", ".join(empty)]
		)
	var walk := ""
	for clip_name in names:
		if String(clip_name).to_lower().contains("walk"):
			walk = String(clip_name)
			break
	if walk.is_empty():
		_failures.append("the committed library has no walk clip.")
		return
	_check_motion(player, "ual/%s" % walk, skeleton, "committed %s" % walk)


func _clip_containing(player: AnimationPlayer, fragment: String) -> String:
	var names := player.get_animation_list()
	var found: Array[String] = []
	for clip_name in names:
		if String(clip_name).to_lower().contains(fragment):
			found.append(String(clip_name))
	found.sort()
	return found[0] if not found.is_empty() else ""


func _first(node: Node, type_name: String) -> Node:
	var found := node.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


func _finish() -> void:
	for line in _notes:
		print("note: %s" % line)
	print("::notice title=animation retarget::%s" % "|".join(_notes))
	Harness.finish(
		self, _failures, "the animation library's clips retarget onto the protagonist's bones."
	)
