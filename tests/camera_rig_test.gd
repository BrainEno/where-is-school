extends SceneTree
## The camera has one home, one field of view, and no leftovers.
##
## The audit's #58 found three things in one place, and this covers all three:
##
## 1. **The camera was the player's child.** It inherited the body's transform, so
##    the framing could only change by moving the body, and a cut or a shake had
##    nowhere to live. It lives on a `CameraRig` now, a sibling of the player.
## 2. **The field of view had two sources.** `player.tscn` said 58, the player
##    script overwrote it with 60, and the scene value was dead config. The rig is
##    the only place a fov is written; this check fails if a second one reappears.
## 3. **The occluder fader kept a history.** It appended blockers to a list and only
##    cleared the list on a frame with nothing in the way, so a wall that blocked
##    once and was replaced by another wall stayed dithered for the rest of the
##    level. The fader now rebuilds its set every frame; the fixture below walks a
##    blocker A -> blocker B -> nothing and asserts A comes back.
##
## The fader fixture runs before the main scene is loaded, in an empty world, so the
## ray only ever meets the two boxes the fixture puts in front of it.

const Harness = preload("res://tests/test_harness.gd")

## Long enough for `fade_speed = 6.0` to move `transparency` the whole way twice.
const FADE_FRAMES := 40

var _failures: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _rig: CameraRig = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "camera_rig_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	await _check_occluder_fader()

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _physics_frames(3)

	_player = _main.get_node_or_null("Player") as PlayerController
	_rig = _main.get_node_or_null("CameraRig") as CameraRig
	if _player == null or _rig == null:
		Harness.finish(self, ["Main has no Player or no CameraRig."], "")
		return

	_check_one_camera()
	_check_single_fov()
	await _check_follows_the_body()
	await _check_teleport_arrives_together()

	_main.queue_free()
	await process_frame
	Harness.finish(
		self, _failures,
		"one camera on a rig, one fov, the view snaps on a teleport, and a faded wall comes back."
	)


# --- the rig ----------------------------------------------------------------


func _check_one_camera() -> void:
	var named := _player.get_node_or_null(^"Camera3D")
	_expect(named == null, "The player still carries a Camera3D; the camera is the rig's.")
	var viewport_camera := root.get_viewport().get_camera_3d()
	_expect(viewport_camera != null, "The viewport has no current camera.")
	if viewport_camera != null and _rig.camera != null:
		_expect(
			viewport_camera == _rig.camera,
			"The viewport's camera is not the rig's camera."
		)


## The field of view is authored in the scene, on the rig, and nowhere else. If a
## script starts writing `fov` from somewhere other than the rig, this is the check
## that notices before an author spends an afternoon editing a number that does
## nothing.
func _check_single_fov() -> void:
	_expect(_rig.camera != null, "The rig has no Camera3D child.")
	if _rig.camera == null:
		return
	_expect(
		is_equal_approx(_rig.camera.fov, _rig.fov),
		"The camera's fov (%.1f) disagrees with the rig's (%.1f)." % [_rig.camera.fov, _rig.fov]
	)
	for property_name in ["camera_fov", "camera_offset", "camera_target_height"]:
		_expect(
			not _has_property(_player, property_name),
			"PlayerController still exposes '%s'; the framing belongs to the rig." % property_name
		)


func _check_follows_the_body() -> void:
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.0, 1.25)))
	await _physics_frames(3)
	_expect(
		_player.global_position.distance_to(_rig.global_position) < 0.01,
		"The rig is %.2f m away from the player it frames."
		% _player.global_position.distance_to(_rig.global_position)
	)
	var expected := _player.global_position + _rig.offset
	_expect(
		_rig.camera.global_position.distance_to(expected) < 0.05,
		"The camera is at %s instead of the rig's offset position %s."
		% [str(_rig.camera.global_position), str(expected)]
	)
	# And it is aimed at the body, not past it: the look direction has to reach the
	# point the rig says it targets.
	var eye := _player.global_position + Vector3(0.0, _rig.target_height, 0.0)
	var to_eye := (eye - _rig.camera.global_position).normalized()
	var forward := -_rig.camera.global_basis.z
	_expect(
		forward.dot(to_eye) > 0.999,
		"The camera is not aimed at the player: dot %.3f." % forward.dot(to_eye)
	)


## A teleport that moves the body and leaves the camera behind for a frame is a
## frame rendered from inside the wall the player just left.
func _check_teleport_arrives_together() -> void:
	var destination := Vector3(2.0, 0.0, -1.5)
	_player.teleport(Transform3D(Basis.IDENTITY, destination))
	# No frame is awaited on purpose.
	_expect(
		_rig.camera.global_position.distance_to(destination + _rig.offset) < 0.05,
		"The camera did not follow the teleport until a later frame."
	)


# --- the occluder fader -----------------------------------------------------


## Two boxes take turns blocking a camera's view of a target. The first one has to
## come back to full opacity when the second one takes over - that is exactly what
## the fader used to fail to do.
func _check_occluder_fader() -> void:
	var fixture := Node3D.new()
	fixture.name = "FaderFixture"
	root.add_child(fixture)

	var target := Node3D.new()
	target.name = "Target"
	fixture.add_child(target)

	var camera := Camera3D.new()
	camera.name = "FixtureCamera"
	camera.position = Vector3(0.0, 5.0, 5.0)
	fixture.add_child(camera)
	camera.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)

	var fader := CameraOccluderFader.new()
	fader.name = "FixtureFader"
	# The fader targets `../..` from itself, which is the fixture root - the same
	# relationship the game scene has, where the rig stands where the player stands.
	camera.add_child(fader)
	await _physics_frames(2)

	var first := _make_blocker(fixture, Vector3(0.0, 3.0, 2.5), "First")
	var second := _make_blocker(fixture, Vector3(0.0, 3.0, 3.5), "Second")
	# Only the first one is in the way to begin with.
	second.position = Vector3(40.0, 3.0, 3.5)

	await _physics_frames(FADE_FRAMES)
	var first_mesh := first.get_node(^"Mesh") as GeometryInstance3D
	_expect(
		first_mesh.transparency > 0.3,
		"A wall between the camera and the target was not faded (%.2f)." % first_mesh.transparency
	)

	# Hand the blocking over without ever giving the fader an unobstructed frame,
	# which is the case a corridor produces all the time.
	first.position = Vector3(-40.0, 3.0, 2.5)
	second.position = Vector3(0.0, 3.0, 2.5)
	await _physics_frames(FADE_FRAMES)
	var second_mesh := second.get_node(^"Mesh") as GeometryInstance3D
	_expect(
		second_mesh.transparency > 0.3,
		"The new blocker was not faded (%.2f)." % second_mesh.transparency
	)
	_expect(
		first_mesh.transparency < 0.05,
		("A wall that stopped blocking stayed dithered (%.2f): the fader kept a history "
		+ "instead of the current set.") % first_mesh.transparency
	)

	# And nothing in the way at all restores the last one too.
	second.position = Vector3(40.0, 3.0, 2.5)
	await _physics_frames(FADE_FRAMES)
	_expect(
		second_mesh.transparency < 0.05,
		"A wall stayed dithered after the view cleared (%.2f)." % second_mesh.transparency
	)

	fixture.queue_free()
	await process_frame


func _make_blocker(parent: Node3D, position: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.add_to_group(&"camera_occluder")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var mesh_box := BoxMesh.new()
	mesh_box.size = Vector3(3.0, 3.0, 1.0)
	mesh.mesh = mesh_box
	body.add_child(mesh)
	parent.add_child(body)
	return body


# --- helpers ----------------------------------------------------------------


func _has_property(object: Object, property_name: String) -> bool:
	for entry: Dictionary in object.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
