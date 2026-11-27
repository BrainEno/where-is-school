extends SceneTree
## Owner-review evidence for the brow work (#385 / PR #433): the three characters'
## brow region photographed by the engine, in the classroom's own light, at 1920x1080.
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --resolution 1920x1080 --rendering-driver opengl3 \
##     --script res://tests/capture_brow_review.gd -- --output=build/brow-review
##
## Boots the real main scene (the opening presentation cleared, player control allowed),
## stages Q and N the way the classroom holds them, stands the player in the centre aisle,
## and photographs each character's head from a fixed review camera: front, quarter and
## profile on both sides, plus two half-body views. The PNGs are the evidence of record;
## a quality-92 JPEG beside each is the review copy the owner flips through. The camera is
## a fixture (a fixed review framing like capture_classroom_art.gd's), not the gameplay
## rig; the light, the room and the characters are the game's own.
##
## Notes print as ARTNOTE lines (renderer, adapter, per-shot sha256 and mean luminance)
## and the run ends with RESULT: SUCCESS or RESULT: FAILURE, like the other captures.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const DEFAULT_OUT := "res://docs/screenshots/character_brow"
const SIZE := Vector2i(1920, 1080)
const CLOSE_FOV := 38.0
const CLOSE_DISTANCE := 0.62
const WIDE_FOV := 55.0
const WIDE_DISTANCE := 1.55
## Orbit angles in degrees. Zero is the character's own facing; positive angles stand on
## the character's left. The close shots frame the brows, the wide ones frame the head.
const CLOSE_YAWS := [0.0, 45.0, -45.0, 90.0, -90.0]
const WIDE_YAWS := [0.0, 45.0]
const YAW_LABELS := {
	0.0: "front",
	45.0: "left45",
	-45.0: "right45",
	90.0: "left90",
	-90.0: "right90",
}
## Where each character stands for its own orbit. The player teleports to the centre
## aisle (the proven clear spot) facing the stage like a student; Q keeps its classroom
## desk seat facing the stage; N keeps the #172 front-of-lectern marker facing the room.
## Facing is the direction the character's face points, used only to orbit the camera.
const AISLE_SPOT := Vector3(0.0, 0.0, 0.25)
const AISLE_FACING := Vector3.FORWARD

var _out := DEFAULT_OUT
var _failures: Array[String] = []
var _camera: Camera3D = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "capture_brow_review.gd")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		Harness.finish(self, ["A real display/renderer is required; headless is not evidence."], "")
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_out = argument.trim_prefix("--output=")
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if error != OK:
		Harness.finish(self, ["Cannot create the output directory: %s" % error_string(error)], "")
		return
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	var packed := load(MAIN) as PackedScene
	var main := packed.instantiate() as Node3D
	main.get_node("OpeningSequence").set("autostart", false)
	root.add_child(main)
	await _frames(5)
	var host := main.get_node("LocationHost") as LocationHost
	var room := host.get_current()
	main.get_node("OpeningSequence").allow_player_control()
	(main.get_node("GameUI") as GameUI).fade.set_clear()
	# The objective line, the "[E] ..." prompt and the language hint are interface,
	# not character art; the review stills carry none of them.
	(main.get_node("GameUI/HUD") as Control).visible = false
	_note(
		(
			"engine=%s renderer=%s adapter=%s viewport=%s"
			% [
				Engine.get_version_info().string,
				RenderingServer.get_current_rendering_method(),
				RenderingServer.get_video_adapter_name(),
				str(root.size),
			]
		)
	)
	if root.size != SIZE:
		_failures.append("The viewport is %s, not %s." % [str(root.size), str(SIZE)])

	var staged := await _stage(room, main)
	if not _failures.is_empty():
		Harness.finish(self, _failures, "")
		return
	_camera = Camera3D.new()
	_camera.name = "BrowReviewCamera"
	main.add_child(_camera)

	for entry: Dictionary in staged:
		await _orbit(entry)
	await _frames(5)
	if _failures.is_empty():
		print("RESULT: SUCCESS")
		Harness.finish(self, [], "brow review stills written to %s" % _out)
	else:
		print("RESULT: FAILURE")
		Harness.finish(self, _failures, "")


func _stage(room: LocationRoot, main: Node3D) -> Array[Dictionary]:
	var player := main.get_node("Player") as PlayerController
	var yaw := atan2(-AISLE_FACING.x, -AISLE_FACING.z)
	if is_zero_approx(yaw):
		yaw = 0.0001
	player.teleport(Transform3D(Basis(Vector3.UP, yaw), AISLE_SPOT))
	await _frames(35)
	var teacher := room.find_actor(&"n")
	if teacher == null:
		_failures.append("The classroom holds no N actor to photograph.")
		return []
	teacher.visible = true
	teacher.global_position = room.get_node("NEntryPath/AtFront").global_position
	teacher.face_towards(teacher.global_position + Vector3.BACK)
	var staged: Array[Dictionary] = [
		{"label": "protagonist", "node": player, "facing": AISLE_FACING},
		{"label": "n", "node": teacher, "facing": teacher.get_facing_direction()},
	]
	var q_actor := room.find_actor(&"q")
	if q_actor == null:
		_failures.append("The classroom holds no Q actor to photograph.")
	else:
		# Q keeps its desk seat and its scene-authored orientation; the orbit reads
		# the facing from the game's own helper, so "front" is Q's front.
		staged.insert(1, {"label": "q", "node": q_actor, "facing": q_actor.get_facing_direction()})
	for entry in staged:
		var node := entry["node"] as Node3D
		if node == null:
			_failures.append("%s: the actor is missing from the room." % entry["label"])
			continue
		node.visible = true
		for plate in node.find_children("*", "Label3D", true, false):
			(plate as Label3D).visible = false
	return staged


func _orbit(entry: Dictionary) -> void:
	var node := entry["node"] as Node3D
	var label := String(entry["label"])
	var facing := entry["facing"] as Vector3
	var head := _head_origin(node)
	if head == Vector3.INF:
		_failures.append("%s: no skeleton head bone to aim at." % label)
		return
	var phi := atan2(facing.x, facing.z)
	var basis := Basis(Vector3.UP, phi)
	for yaw_degrees: float in CLOSE_YAWS:
		await _shot(
			node,
			label,
			"%s_%s" % [label, YAW_LABELS[yaw_degrees]],
			head,
			basis * _orbit_direction(yaw_degrees),
			CLOSE_DISTANCE,
			CLOSE_FOV
		)
	for yaw_degrees: float in WIDE_YAWS:
		await _shot(
			node,
			label,
			"%s_wide_%s" % [label, YAW_LABELS[yaw_degrees]],
			head - Vector3.UP * 0.35,
			basis * _orbit_direction(yaw_degrees),
			WIDE_DISTANCE,
			WIDE_FOV
		)


func _orbit_direction(yaw_degrees: float) -> Vector3:
	var radians := deg_to_rad(yaw_degrees)
	return Vector3(sin(radians), 0.0, cos(radians))


func _head_origin(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		for index in bones.get_bone_count():
			if bones.get_bone_name(index).to_lower().contains("head"):
				var posed := bones.global_transform * bones.get_bone_global_pose(index)
				_note("%s head at %s" % [node.name, str(posed.origin.snappedf(0.001))])
				return posed.origin
	return Vector3.INF


func _shot(
	node: Node3D,
	label: String,
	file_name: String,
	aim: Vector3,
	direction: Vector3,
	distance: float,
	fov: float
) -> void:
	_camera.fov = fov
	_camera.position = aim + direction * distance + Vector3.UP * 0.06
	_camera.look_at(aim, Vector3.UP)
	_camera.current = true
	await _frames(12)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or Vector2i(image.get_width(), image.get_height()) != SIZE:
		_failures.append("%s is not a rendered %s frame." % [file_name, str(SIZE)])
		return
	var mean := 0.0
	var sample := image.duplicate() as Image
	sample.resize(40, 24, Image.INTERPOLATE_BILINEAR)
	for y in sample.get_height():
		for x in sample.get_width():
			var pixel := sample.get_pixel(x, y)
			mean += (pixel.r + pixel.g + pixel.b) / 3.0
	mean /= float(sample.get_width() * sample.get_height())
	if mean < 0.04:
		_failures.append("%s renders black; the orbit clipped into geometry." % file_name)
		return
	var base := _out.path_join(file_name)
	var png := base + ".png"
	var jpg := base + ".jpg"
	var error := image.save_png(ProjectSettings.globalize_path(png))
	if error == OK:
		error = image.save_jpg(ProjectSettings.globalize_path(jpg), 0.92)
	if error != OK:
		_failures.append("%s: %s" % [file_name, error_string(error)])
		return
	_note("shot=%s mean_luma=%.3f png_sha256=%s" % [file_name, mean, FileAccess.get_sha256(png)])


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _note(line: String) -> void:
	print("ARTNOTE: [brow-review] %s" % line)
