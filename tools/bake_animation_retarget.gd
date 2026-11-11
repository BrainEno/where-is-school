extends SceneTree
## Bakes the Universal Animation Library onto the retargeted protagonist.
##
##     godot --headless --path . --script res://tools/bake_animation_retarget.gd
##
## Writes `scenes/dev/animation_retarget_test/protagonist_ual.res`: one `Animation` per UAL
## clip, with this character's bone names in the track paths, sampled at 30 fps. The dev scene
## `protagonist_ual_preview.tscn` loads it into an `AnimationPlayer`, so the clips can be
## scrubbed in the editor's animation panel — that is the point of baking instead of
## retargeting at runtime, and it is also why the result is committed: it is a derived asset,
## and regenerating it needs an engine.
##
## The library is development material (it is excluded from the export with `scenes/dev/`),
## because the third-party clips are not this game's animation.

const UAL_PATH := "res://scenes/dev/animation_retarget_test/UAL1_Standard.glb"
const PROTAGONIST_PATH := "res://scenes/dev/animation_retarget_test/protagonist_retarget_ready.glb"
const OUT_PATH := "res://scenes/dev/animation_retarget_test/protagonist_ual.res"
const FPS := 30.0
## Clips whose name says what it is not worth baking: the T-pose is a rest reference, and a
## 43-clip library with a dead frame in it is a worse library.
const SKIP := ["A_TPose"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var version := Engine.get_version_info()
	print("engine: %s" % String(version["string"]))
	_probe_retarget_api()

	var ual := (load(UAL_PATH) as PackedScene).instantiate()
	root.add_child(ual)
	var protagonist := (load(PROTAGONIST_PATH) as PackedScene).instantiate()
	root.add_child(protagonist)
	await process_frame

	var source_player := _first(ual, "AnimationPlayer") as AnimationPlayer
	var source_skeleton := _first(ual, "Skeleton3D") as Skeleton3D
	var target_skeleton := _first(protagonist, "Skeleton3D") as Skeleton3D
	if source_player == null or source_skeleton == null or target_skeleton == null:
		printerr("bake: the source or the target scene has no skeleton/player")
		quit(1)
		return
	print(
		"source: %s, %d clip(s), skeleton '%s' with %d bone(s)"
		% [source_player.get_path(), source_player.get_animation_list().size(), source_skeleton.name, source_skeleton.get_bone_count()]
	)
	print("target: skeleton '%s' with %d bone(s)" % [target_skeleton.name, target_skeleton.get_bone_count()])

	var clip_names: Array = []
	for clip_name in source_player.get_animation_list():
		if SKIP.has(String(clip_name)):
			continue
		clip_names.append(String(clip_name))
	clip_names.sort()

	# The player that will hold the result sits under the model root, so track paths are
	# relative to that root.
	var skeleton_path := protagonist.get_path_to(target_skeleton)
	var report := AnimationRetarget.bake(
		source_skeleton, source_player, target_skeleton, clip_names, FPS, skeleton_path
	)
	var library: AnimationLibrary = report["library"]
	if library == null:
		printerr("bake: %s" % String(report.get("reason", "nothing to bake")))
		quit(1)
		return

	var err := ResourceSaver.save(library, OUT_PATH)
	if err != OK:
		printerr("bake: could not write %s (%d)" % [OUT_PATH, err])
		quit(1)
		return

	var pairs: Array = report["pairs"]
	var mapping: PackedStringArray = []
	for pair: Dictionary in pairs:
		mapping.append(
			"%s ← %s"
			% [
				String(pair["canonical"]),
				String(source_skeleton.get_bone_name(int(pair["source"]))),
			]
		)
	print("mapped %d bone(s): %s" % [pairs.size(), ", ".join(mapping)])
	print("target bones that share no name with the source: %s" % str(report["missing"]["target"]))
	print("clips: %s" % AnimationRetarget.describe(report))
	print("wrote %s (%d clip(s))" % [OUT_PATH, library.get_animation_list().size()])
	print("PASS: baked %d UAL clip(s) onto %s" % [library.get_animation_list().size(), skeleton_path])

	var clips: Dictionary = report["clips"]
	var sample: PackedStringArray = []
	var names: Array = clips.keys()
	names.sort()
	for index in mini(6, names.size()):
		var info: Dictionary = clips[names[index]]
		sample.append("%s %.2fs" % [String(names[index]), float(info["length"])])
	print(
		"::notice title=animation retarget::%d clips, %d bones, %s … (%s)"
		% [library.get_animation_list().size(), pairs.size(), ", ".join(sample), str(clip_names[0])]
	)
	quit(0)


## Reports whether this engine has the built-in retargeting the `.import` sidecars configure,
## and what it is called. Written to the log so the answer does not have to be guessed at.
func _probe_retarget_api() -> void:
	var wanted := [
		"Skeleton3D",
		"SkeletonModifier3D",
		"RetargetModifier3D",
		"BoneMap",
		"SkeletonProfileHumanoid",
		"BoneTwistDispenser3D",
		"LookAtModifier3D",
	]
	var present: PackedStringArray = []
	for candidate: String in wanted:
		if ClassDB.class_exists(candidate):
			present.append(
				"%s(%d prop)" % [candidate, ClassDB.class_get_property_list(candidate).size()]
			)
	print("engine classes: %s" % ", ".join(present))


func _first(node: Node, type_name: String) -> Node:
	var found := node.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null
