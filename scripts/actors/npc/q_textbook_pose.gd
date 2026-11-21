extends SkeletonModifier3D
## A held prop and its two contacts are one performance, on top of Q's sampled FK.
## Off the page, his ordinary animation still owns the legs and all actor transforms.

enum Cue { STOWED, RECITE, REPLY, SHOW_PAGE, GRIN }

const CADENCE_SECONDS := 2.24
const GRIP_READY := 0.42
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const FOLD := [8.0, 14.0, 9.0]

var cue: Cue = Cue.STOWED

var _animator: CharacterVisualAnimation
var _book: Node3D
var _chest: int
var _neck: int
var _head: int
var _rest_chest: Basis
var _rest_head: Basis
var _arms: Array[CharacterLimbContact] = []
var _grips: Array[Transform3D] = []
var _digits := PackedInt32Array()
var _curls: Array[Quaternion] = []
var _face: MeshInstance3D
var _mouth := -1
var _smile := -1
var _face_written := false
var _lift := 0.0
var _reading := 0.0
var _showing := 0.0
var _grinning := 0.0
var _phase := 0.7
var _book_offset: Transform3D


func install(animator: CharacterVisualAnimation, textbook: PackedScene) -> bool:
	var rig := animator.get_skeleton()
	if rig == null or textbook == null:
		push_error("Classroom Q needs a skeleton and a biology textbook scene.")
		return false
	var contacts := CharacterLimbContact.bind(animator)
	_chest = rig.find_bone("Chest")
	_neck = rig.find_bone("Neck")
	_head = rig.find_bone("Head")
	if not contacts.has("hand.L") or not contacts.has("hand.R") or mini(_chest, mini(_neck, _head)) < 0:
		push_error("Classroom Q's textbook pose needs both wrists and the Chest/Neck/Head chain.")
		return false
	_book = textbook.instantiate() as Node3D
	var left := _grip_relative_to_book(^"LeftLeaf/Wrist")
	var right := _grip_relative_to_book(^"RightLeaf/Wrist")
	if left == Transform3D.IDENTITY or right == Transform3D.IDENTITY:
		push_error("The biology textbook needs a wrist marker on each half of its cover.")
		if _book != null:
			_book.free()
		return false
	_animator = animator
	_arms.assign([contacts["hand.L"], contacts["hand.R"]])
	_grips.assign([left, right])
	_rest_chest = rig.get_bone_global_rest(_chest).basis.orthonormalized()
	_rest_head = rig.get_bone_global_rest(_head).basis.orthonormalized()
	_bind_hands_and_face(rig)
	_book.hide()
	animator.add_child(_book)
	name = "TextbookPose"
	rig.add_child(self)
	# Follow the rendered chest, including any later gaze modifier on the rig.
	rig.skeleton_updated.connect(_place_book)
	return true


func _grip_relative_to_book(path: NodePath) -> Transform3D:
	var wrist := _book.get_node_or_null(path) as Marker3D if _book != null else null
	if wrist == null:
		return Transform3D.IDENTITY
	return (wrist.get_parent() as Node3D).transform * wrist.transform


func _bind_hands_and_face(rig: Skeleton3D) -> void:
	# The imported Q names his anatomical left as +X; the contact binding uses position.
	for side: String in ["R", "L"]:
		var sign_x := 1.0 if side == "L" else -1.0
		for finger: String in FINGERS:
			for segment in range(1, 4):
				var index := rig.find_bone("%s_%02d_%s" % [finger, segment, side])
				if index < 0:
					continue
				_digits.append(index)
				var curl := Quaternion(Vector3.BACK, deg_to_rad(FOLD[segment - 1] * sign_x))
				_curls.append(rig.get_bone_rest(index).basis.get_rotation_quaternion() * curl)
	_face = _animator.find_child("Q_Head", true, false) as MeshInstance3D
	if _face != null:
		_mouth = _face.find_blend_shape_by_name(&"Mouth_Open")
		_smile = _face.find_blend_shape_by_name(&"Smile")


func _process_modification_with_delta(delta: float) -> void:
	# Staged actions, walking, and manually sampled poses keep their own hands. No
	# book trails behind the wrists when a controller takes over and starts a walk.
	if (not _animator.is_visible_in_tree() or not _animator.is_processing()
		or _animator.is_playing_action()
		or _animator.get_locomotion_state() != CharacterVisualAnimation.STATE_IDLE):
		_put_down()
		return
	_lift = move_toward(_lift, float(cue != Cue.STOWED), delta / 0.48)
	if _lift <= 0.0:
		_put_down()
		return
	_reading = move_toward(_reading, float(cue == Cue.RECITE), delta / 0.30)
	_showing = move_toward(_showing, float(cue == Cue.SHOW_PAGE), delta / 0.38)
	_grinning = move_toward(_grinning, float(cue == Cue.GRIN), delta / 0.20)
	_phase = fposmod(_phase + delta * TAU / CADENCE_SECONDS, TAU)
	var study := smoothstep(0.0, 1.0, _reading)
	var show_page := smoothstep(0.0, 1.0, _showing)
	# Unequal beats: one broad sweep, two smaller nods as he sounds out a phrase.
	var sway := sin(_phase) * 0.78 + sin(2.0 * _phase + 0.6) * 0.22
	var nod := sin(2.0 * _phase - 0.7) * 0.68 + sin(3.0 * _phase + 0.4) * 0.32
	var weight := smoothstep(0.0, GRIP_READY, _lift)
	var rig := get_skeleton()
	var chest := rig.get_bone_global_pose(_chest)
	chest.basis = Basis(Vector3.RIGHT, deg_to_rad(weight * study * (4.0 + 1.8 * nod))) * chest.basis
	rig.set_bone_global_pose(_chest, chest)
	var frame := _chest_frame(rig)
	var angles := Vector3(4.0 + 2.0 * nod, 3.0 * sway, 2.0 * sway).lerp(
		Vector3(37.0 + 7.0 * nod, 9.0 * sway, 14.0 * sway), study)
	_pose_head(rig, frame.basis, angles, weight)
	var up := smoothstep(0.24, 1.0, _lift)
	var book_position := Vector3(0.026 * sway * study, lerpf(-0.27, -0.042, up), 0.37)
	book_position.y += up * (0.018 * nod * study - 0.047 * (1.0 - study))
	book_position.z += show_page * 0.046 + 0.014 * nod * study
	var book_angles := Vector3(lerpf(-15.0, -32.0, study), 4.0 * sway * study, -8.0 * sway * study)
	book_angles.x = lerpf(book_angles.x, 42.0, show_page)
	_book_offset = Transform3D(_rotation(book_angles), book_position)
	var book_pose := frame * _book_offset
	for arm_index in _arms.size():
		_hold(rig, arm_index, book_pose * _grips[arm_index], weight)
	for i in _digits.size():
		var start := rig.get_bone_pose_rotation(_digits[i])
		rig.set_bone_pose_rotation(_digits[i], start.slerp(_curls[i], weight))
	var syllables := pow(maxf(0.0, sin(5.0 * _phase + 0.5 * nod)), 2.0)
	_set_face(study * weight * (0.025 + 0.16 * syllables), _grinning * weight * 0.52)


func _pose_head(rig: Skeleton3D, frame: Basis, angles: Vector3, weight: float) -> void:
	var neck := rig.get_bone_global_pose(_neck)
	neck.basis = frame * _rotation(angles * (0.30 * weight)) * frame.inverse() * neck.basis
	rig.set_bone_global_pose(_neck, neck)
	var head := rig.get_bone_global_pose(_head)
	var aim := frame * _rotation(angles) * _rest_head
	head.basis = head.basis.orthonormalized().slerp(aim, weight)
	rig.set_bone_global_pose(_head, head)


func _hold(rig: Skeleton3D, arm_index: int, mark: Transform3D, weight: float) -> void:
	var side := -1.0 if arm_index == 0 else 1.0
	var pole := rig.global_basis * Vector3(0.53 * side, -1.0, -0.20)
	# +Y points down Q's fingers. The inner normal is -X on Hand_L, +X on Hand_R.
	var fingers := Vector3(0.0, -0.09, 1.0).normalized()
	var palm := (-side * Vector3.UP).slide(fingers).normalized()
	var aim := mark.basis * Basis(palm, fingers, palm.cross(fingers))
	_arms[arm_index].hold_at(rig.to_global(mark.origin), pole, weight, true, aim)


func _chest_frame(rig: Skeleton3D) -> Transform3D:
	var chest := rig.get_bone_global_pose(_chest)
	return Transform3D(chest.basis.orthonormalized() * _rest_chest.inverse(), chest.origin)


func _place_book() -> void:
	# A deferred skeleton update can arrive while LocationHost detaches the room.
	if not is_inside_tree() or not is_instance_valid(_book) or not _book.is_inside_tree():
		return
	var rig := get_skeleton()
	if rig == null or not rig.is_inside_tree():
		return
	if _lift < GRIP_READY:
		_book.hide()
		return
	_book.global_transform = rig.global_transform * _chest_frame(rig) * _book_offset
	_book.show()


func _put_down() -> void:
	_lift = 0.0
	_reading = 0.0
	_showing = 0.0
	_grinning = 0.0
	_book.hide()
	if _face_written:
		_set_face(0.0, 0.0)
		_face_written = false


func _set_face(mouth: float, smile: float) -> void:
	if _mouth >= 0:
		_face.set_blend_shape_value(_mouth, mouth)
	if _smile >= 0:
		_face.set_blend_shape_value(_smile, smile)
	_face_written = true


func _rotation(degrees: Vector3) -> Basis:
	return Basis.from_euler(degrees * (PI / 180.0))
