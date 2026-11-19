extends SceneTree
## Approved Q: real imported rig, native motion, reset completeness and live dialogue.
## Run with the pinned standard engine, not a file-format-only substitute:
## godot --headless --path . --script res://tests/q_model_test.gd

const Harness = preload("res://tests/test_harness.gd")
const MODEL := "res://assets/models/q/new-Q.glb"
const WRAPPER := "res://scenes/environment/characters/q.tscn"
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const SOURCE_CLIPS := ["Q_Casual_Hand_Gesture", "Q_Head_Movement", "Q_Idle_Breathing",
	"Q_Pose_Preview", "Q_Slight_Body_Lean", "Q_Face_Test"]
const BOUND_CLIPS := ["idle", "walk", "jog", "sit_idle", "get_up", "wave", "talk",
	"head_movement", "hand_gesture", "body_lean", "pose_preview"]

var _failures: Array[String] = []
var _notes: PackedStringArray = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "q_model_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	Harness.stage = "Q production wrapper"
	var packed := load(WRAPPER) as PackedScene
	var q := packed.instantiate() as CharacterVisualAnimation if packed != null else null
	if q == null:
		Harness.finish(self, ["Q wrapper cannot be instantiated."], "")
		return
	root.add_child(q)
	await process_frame
	if not q.is_bound() or q.get_skeleton() == null:
		Harness.finish(self, ["New Q failed to bind its production animator."], "")
		return
	q.set_process(false)
	_check_import(q)
	_check_bound_library(q)
	_check_motion_and_resets(q)
	q.queue_free()
	await process_frame

	Harness.stage = "Q native diagnostics in the existing preview"
	await _check_preview()
	Harness.stage = "Q in main.tscn"
	await _check_game_integration()
	for note in _notes:
		print("Q_MODEL_NOTE: %s" % note)
	Harness.clear_session_state(self)
	Harness.finish(self, _failures, "new Q has a complete 60-bone rig, live native hands/head, "
		+ "complete cross-state resets and speaker-driven dialogue in the real game.")


func _check_import(q: CharacterVisualAnimation) -> void:
	var model := q.get_node("Model") as Node3D
	_expect(model.scene_file_path == MODEL, "Q/Model does not instance the sole production GLB.")
	_expect(model.transform.is_equal_approx(Transform3D.IDENTITY), "Q has a hidden scale/yaw/ground correction.")
	var skeleton := q.get_skeleton()
	_expect(skeleton.get_bone_count() == 60, "New Q must import all 60 joints.")
	_expect(String(q.get_path_to(skeleton)) == "Model/Q_Armature/Skeleton3D", "Imported Q skeleton path changed.")
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() == 9, "New Q must have nine skinned meshes, not its bone display.")
	for node in meshes:
		var mesh := node as MeshInstance3D
		_expect(not String(mesh.name).contains("Preview"), "Q's skeleton display reached production.")
		_expect(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) == skeleton,
			"Q mesh '%s' lost its skin/skeleton binding." % mesh.name)
		if mesh.skin != null:
			for bind in mesh.skin.get_bind_count():
				var bone := skeleton.find_bone(String(mesh.skin.get_bind_name(bind)))
				_expect(bone >= 0, "A named Q skin bind points at a missing bone.")
		if mesh.name == &"Q_Head":
			_expect(mesh.mesh.get_blend_shape_count() == 13, "Q's 13 supplied face morphs were lost.")
	for side: String in ["L", "R"]:
		for finger: String in FINGERS:
			var parent := "Hand_%s" % side
			for segment in range(1, 4):
				var bone := "%s_%02d_%s" % [finger, segment, side]
				var index := skeleton.find_bone(bone)
				_expect(index >= 0, "Q is missing finger joint '%s'." % bone)
				if index >= 0:
					var parent_index := skeleton.get_bone_parent(index)
					_expect(parent_index >= 0 and skeleton.get_bone_name(parent_index) == parent,
						"Q finger hierarchy is invalid at '%s'." % bone)
				parent = bone
	var source := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(source != null, "The six supplied Q actions did not import.")
	if source != null:
		_expect(source.autoplay.is_empty() and not source.is_playing(), "Imported and bound Q players would fight.")
		for clip: String in SOURCE_CLIPS:
			_expect(source.has_animation(clip), "Q lost the supplied action '%s'." % clip)
			if source.has_animation(clip):
				_check_paths(source, source.get_animation(clip), true)
	var look := q.get_node("Look") as CharacterLookApplier
	var report := look.get_report()
	_expect(int(report.get("replaced", 0)) == 16 and (report.get("kept", []) as Array).is_empty(),
		"Q's material mapping must paint all 16 new surfaces without a white fallback.")
	_expect(q.get_node("InteractionAnchor").position.is_equal_approx(Vector3(0, 1.2, 0)),
		"Q's interaction anchor contract changed.")
	_notes.append("import: 60 bones / 9 skins / 16 painted surfaces / 13 face morphs / 6 original actions")


func _check_bound_library(q: CharacterVisualAnimation) -> void:
	var report := q.get_bind_report()
	_expect((report.get("missing", []) as Array).is_empty(), "New Q must resolve every semantic bone.")
	_expect((report.get("posed", []) as Array).is_empty(), "A new Q limb was frozen by the posed-limb guard.")
	_expect((report.get("mirrored", []) as Array).size() == 7, "Q's anatomical sides were not resolved by rest position.")
	var adopted: Dictionary = report.get("authored_clips", {})
	_expect(adopted.size() == 6, "Q did not adopt its idle, talk and four named rotation actions.")
	for clip: String in adopted:
		var info: Dictionary = adopted[clip]
		_expect(bool(info.get("ok", false)) and int(info.get("ignored_tracks", -1)) == 0,
			"Q native clip '%s' dropped a track: %s" % [clip, str(info)])
	var player := q.get_animation_player()
	var expected_paths: Array[String] = []
	for clip: String in BOUND_CLIPS:
		var full := "char/%s" % clip
		_expect(player.has_animation(full), "Q lost runtime action '%s'." % full)
		if not player.has_animation(full):
			continue
		var animation := player.get_animation(full)
		_check_paths(player, animation, false)
		var paths: Array[String] = []
		for track in animation.get_track_count():
			paths.append(String(animation.track_get_path(track)))
		paths.sort()
		if expected_paths.is_empty():
			expected_paths = paths
		_expect(paths == expected_paths, "Q '%s' does not reset the full animated bone set." % clip)
	_notes.append("bound: %d clips, %d reset-complete bone tracks each; no frozen limbs" % [
		BOUND_CLIPS.size(), expected_paths.size()])


func _check_paths(player: AnimationPlayer, animation: Animation, allow_face: bool) -> void:
	var anim_root := player.get_node(player.root_node)
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var node := anim_root.get_node_or_null(NodePath(path.get_concatenated_names()))
		var sub := String(path.get_concatenated_subnames())
		var valid := false
		if node is Skeleton3D and animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			valid = (node as Skeleton3D).find_bone(sub) >= 0
		elif allow_face and node is MeshInstance3D and animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
			valid = (node as MeshInstance3D).find_blend_shape_by_name(StringName(sub)) >= 0
		_expect(valid, "Invalid/non-bone Q track '%s' in '%s'." % [path, animation.resource_name])


func _check_motion_and_resets(q: CharacterVisualAnimation) -> void:
	var skeleton := q.get_skeleton()
	var player := q.get_animation_player()
	var transform_before := q.transform
	for clip: String in BOUND_CLIPS:
		if not player.has_animation("char/%s" % clip):
			continue
		player.play("char/%s" % clip, 0.0)
		var animation := player.get_animation("char/%s" % clip)
		for sample in 17:
			player.seek(animation.length * float(sample) / 16.0, true)
			for index in skeleton.get_bone_count():
				var pose := skeleton.get_bone_pose(index)
				_expect(pose.is_finite(), "Q '%s' produces a non-finite bone pose." % clip)
				_expect(pose.origin.distance_to(skeleton.get_bone_rest(index).origin) < 0.001,
					"Q '%s' stretches/translates a bone." % clip)
				_expect(pose.basis.get_scale().is_equal_approx(Vector3.ONE), "Q motion scales a bone.")
		_expect(q.transform.is_equal_approx(transform_before), "Q animation moved the controller's visual transform.")
	for side: String in ["L", "R"]:
		_expect(_rotation_span(q, "walk", "Forearm_%s" % side) > 4.0,
			"Q's %s forearm no longer swings during locomotion." % side)
	for finger: String in FINGERS:
		for segment in range(1, 4):
			var bone := "%s_%02d_R" % [finger, segment]
			_expect(_rotation_span(q, "talk", bone) > (2.0 if finger == "Thumb" else 5.0),
				"Q talk freezes finger '%s'." % bone)
	_expect(_rotation_span(q, "head_movement", "Head") > 15.0, "Q's authored head turn was lost.")
	_expect(_rotation_span(q, "idle", "Chest") > 0.5, "Q's breathing is a static pose.")
	# Enter a pose that curls BOTH hands, then walk: every finger must return to
	# rest. Checking the actual player/skeleton catches a stale pose after a fade.
	player.play("char/pose_preview", 0.0)
	player.seek(0.0, true)
	var finger_index := skeleton.find_bone("Index_02_L")
	var rest := skeleton.get_bone_rest(finger_index).basis.get_rotation_quaternion()
	_expect(rad_to_deg(skeleton.get_bone_pose_rotation(finger_index).angle_to(rest)) > 5.0,
		"Q's supplied pose preview was replaced with rest.")
	player.play("char/walk", 0.0)
	player.seek(0.3, true)
	for side: String in ["L", "R"]:
		for finger: String in FINGERS:
			for segment in range(1, 4):
				var index := skeleton.find_bone("%s_%02d_%s" % [finger, segment, side])
				var resting := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
				_expect(rad_to_deg(skeleton.get_bone_pose_rotation(index).angle_to(resting)) < 0.1,
					"Q kept a curled finger after switching to walk.")
	player.pause()
	_notes.append("motion: both forearms, 15 right-hand finger joints, breathing and head turn move; all 30 fingers reset")


func _rotation_span(q: CharacterVisualAnimation, clip: String, bone: String) -> float:
	var player := q.get_animation_player()
	var skeleton := q.get_skeleton()
	var index := skeleton.find_bone(bone)
	if index < 0 or not player.has_animation("char/%s" % clip):
		return 0.0
	player.play("char/%s" % clip, 0.0)
	var length := player.get_animation("char/%s" % clip).length
	player.seek(0.0, true)
	var first := skeleton.get_bone_pose_rotation(index)
	var span := 0.0
	for sample in 17:
		player.seek(length * float(sample) / 16.0, true)
		span = maxf(span, rad_to_deg(first.angle_to(skeleton.get_bone_pose_rotation(index))))
	return span


## Exercise the actual existing preview, including face ownership and safe rebind.
func _check_preview() -> void:
	var packed := load("res://scenes/dev/animation_retarget_test/animation_preview.tscn") as PackedScene
	var preview := packed.instantiate()
	root.add_child(preview)
	await _frames(2)
	var q := preview.get_node("Q") as CharacterVisualAnimation
	var bound := q.get_animation_player()
	var source := q.get_node("Model").find_child("AnimationPlayer", true, false) as AnimationPlayer
	var head := q.get_node("Model").find_child("Q_Head", true, false) as MeshInstance3D
	var look := q.get_node("Look") as CharacterLookApplier
	var values := PackedFloat32Array()
	for index in head.mesh.get_blend_shape_count():
		values.append(head.get_blend_shape_value(index))
	preview.call("_play", "face_test")
	_expect(source.is_playing() and source.current_animation == "Q_Face_Test",
		"The preview did not play Q's supplied facial diagnostic.")
	_expect(not look.is_processing(), "Q's blink writer competes with the explicit facial diagnostic.")
	var face := source.get_animation("Q_Face_Test")
	var moved := 0.0
	for sample in 17:
		source.seek(face.length * float(sample) / 16.0, true)
		for index in values.size():
			moved = maxf(moved, absf(head.get_blend_shape_value(index) - values[index]))
	_expect(moved > 0.2, "Q's preserved face diagnostic does not move its real imported morphs.")
	preview.call("_play", "walk")
	_expect(not source.is_playing() and look.is_processing(), "Leaving the face diagnostic did not restore writer ownership.")
	for index in values.size():
		_expect(is_equal_approx(head.get_blend_shape_value(index), values[index]),
			"Leaving the face diagnostic stranded a Q facial morph.")
	for clip: String in ["head_movement", "hand_gesture", "body_lean", "pose_preview"]:
		preview.call("_play", clip)
		_expect(bound.current_animation == "char/%s" % clip, "The preview cannot select Q's '%s'." % clip)
	preview.call("_bind_all")
	preview.call("_bind_all")
	preview.call("_play", "idle")
	_expect(is_instance_valid(bound) and bound == q.get_animation_player(), "Preview rebind destroyed Q's production-owned player.")
	_expect(bound.get_animation_library(&"char").get_animation_list().size() == BOUND_CLIPS.size(),
		"Preview rebind lost a native Q action.")
	_notes.append("preview: four native diagnostics and real face morphs play; blink/values restored and Q player survives repeated rebind")
	preview.queue_free()
	await _frames(2)


func _check_game_integration() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	var main := packed.instantiate()
	main.get_node("OpeningSequence").set("autostart", false)
	root.add_child(main)
	main.get_node("InnerVoiceDirector").set_process(false)
	await _frames(4)
	var host := main.get_node("LocationHost") as LocationHost
	var actor := host.get_current().find_actor(&"q")
	var q := actor.get_character_animator() if actor != null else null
	if q == null:
		_failures.append("The real classroom did not instantiate Q.")
		main.queue_free()
		return
	_expect((q.get_node("Model") as Node3D).scene_file_path == MODEL, "Classroom uses an obsolete Q model.")
	var controller := main.get_node("DialogueController") as DialogueController
	var bridge := main.get_node_or_null("CharacterDialogueAnimation") as CharacterDialogueAnimation
	_expect(bridge != null, "main.tscn has no dialogue animation bridge.")
	# Real dialogue, not a fabricated line dictionary: drive the same presentation
	# API as the director/UI, then observe who is actually speaking on each line.
	_expect(controller.play_conversation(&"q_wake"), "The real Q opening conversation did not start.")
	await _frames(2)
	var observed_q := false
	var observed_other := false
	for line in 128:
		if not controller.is_busy():
			break
		var current := controller.get_current_line()
		var speaking := String(current.get("speaker_id", "")) == "q" and not bool(current.get("subjective", false))
		await _frames(2)
		_expect(q.is_talking() == speaking, "The Q speech request disagrees with the visible dialogue speaker.")
		if speaking:
			observed_q = true
			_expect(q.get_current_clip() == "talk", "Q's visible dialogue did not enter its native talk clip.")
			q.report_velocity(Vector3.RIGHT * 1.5)
			_expect(q.get_current_clip() == "walk", "Talking prevented Q from walking.")
			q.clear_reported_velocity()
			_expect(q.get_current_clip() == "talk", "Stopping did not resume the current speech state.")
		else:
			observed_other = true
			_expect(q.get_current_clip() == "idle", "Q keeps gesturing through another speaker's line.")
		if controller.has_pending_choices():
			controller.select_choice(0)
		else:
			controller.advance_presentation()
	_expect(observed_q and observed_other, "The dialogue fixture did not exercise both Q and another speaker.")
	_expect(not controller.is_busy(), "The Q conversation did not finish within its traversal bound.")
	await _frames(2)
	_expect(not q.is_talking() and q.get_current_clip() == "idle", "Closing dialogue stranded Q in talk.")
	var companion := main.get_node("Companion") as CompanionController
	var capsule := companion.get_node("CollisionShape3D") as CollisionShape3D
	_expect(is_equal_approx((capsule.shape as CapsuleShape3D).height, 1.8)
		and is_equal_approx(capsule.position.y, 0.9), "Q companion collider no longer fits the new standing height.")
	var companion_q := companion.get_character_animator()
	_expect(companion_q != null and (companion_q.get_node("Model") as Node3D).scene_file_path == MODEL,
		"The companion does not use the same new Q wrapper.")
	if companion_q == null:
		main.queue_free()
		return
	_expect(companion_q.motion_profile != null and companion_q.motion_profile == q.motion_profile,
		"Classroom and companion Q do not share the same authored motion resource.")
	_expect(not companion_q.is_talking(), "The hidden companion animated during classroom dialogue.")
	var player := main.get_node("Player") as PlayerController
	_expect(host.load_location("res://scenes/locations/corridor/corridor.tscn", &"FromClassroom", player),
		"Q speech test could not enter the actual companion location.")
	await _frames(6)
	companion.join()
	await _frames(6)
	_expect(companion.is_with_player(), "Q's real companion placement did not become visible.")
	_expect(controller.play_conversation(&"q_after_dismissal"), "The companion conversation did not start.")
	var companion_speaks := false
	for line in 128:
		if not controller.is_busy():
			break
		await _frames(2)
		var current := controller.get_current_line()
		var speaking := String(current.get("speaker_id", "")) == "q" and not bool(current.get("subjective", false))
		_expect(companion_q.is_talking() == speaking, "Visible companion speech does not follow its real dialogue speaker.")
		if speaking:
			companion_speaks = true
			_expect(companion_q.get_current_clip() == "talk", "Visible companion did not play native talk.")
		if controller.has_pending_choices():
			controller.select_choice(0)
		else:
			controller.advance_presentation()
	_expect(companion_speaks and not controller.is_busy(), "Companion speech was not exercised to completion.")
	await _frames(2)
	_expect(not companion_q.is_talking(), "Companion kept a speech request after dialogue closed.")
	_notes.append("main: q_wake and companion dialogue follow real speakers, hidden Q stays silent, talk yields to walk and resumes")
	main.queue_free()
	await _frames(3)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
