extends SceneTree
## The prologue's art migration (the biology-classroom experiment brought into the real
## classroom), checked in the real game: `main.tscn`, the classroom entered through the
## location host, the real opening sequence, interaction controller and camera rig.
##
## 1. **Shaders and isolation.** The classroom's own copies of the experiment's concrete and
##    paper load (and, with a renderer, parse and expose their uniforms), and nothing in
##    the game - shader includes too, which the experiment's own isolation scan does not
##    read - names the experiment's folder.
## 2. **The cut and the blank sheet.** The west wall is open from floor to wall top, the
##    blank sheet fills the cut and is hidden with the void until the curtain is drawn.
## 3. **The paper anomaly is local.** Drawing it covers the floor and the curtain at the
##    cut and nothing past its radius (the east wall, the front of the room); no person is
##    ever covered; an overlay the room authored is kept (copied, paper appended), and
##    giving the paper back restores every overlay exactly. Animated, it spreads.
##    Story-driven: the curtain's own `draw_curtain` turns it on and off.
## 4. **Camera focus.** The rig glides to a shot and back with no overshoot, two shots
##    cross-fade without dipping to the default, the controls keep the default axes, and a
##    released rig is exactly the default pose. In the game, talking to Q pulls the
##    camera in for the conversation and gives it back when control returns; an
##    interaction without a shot leaves the camera alone; an activation that never locks
##    the player is released.
##
## Godot CI runs it under Xvfb (`prologue_art`) so the shaders are compiled for real.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const SHADERS := {
	"res://assets/materials/classroom/shaders/concrete.gdshader": [
		"base_color", "ruled_lines", "margin_x", "formwork", "joint_spacing",
	],
	"res://assets/materials/classroom/shaders/paper_zone.gdshader": [
		"zone_centre", "zone_radius", "reveal", "base_value", "blank_sheet", "rule_spacing",
	],
}
const ISOLATION_ROOTS: Array[String] = [
	"res://scenes/", "res://scripts/", "res://data/", "res://assets/", "res://addons/",
]
const ISOLATION_EXTENSIONS: Array[String] = [
	"gd", "tscn", "tres", "json", "cfg", "gdshader", "gdshaderinc",
]
const VOID_SHEET := "res://assets/materials/classroom/void_sheet.tres"
## The cut through the west wall: z 0.95..3.45, floor to wall top.
const CUT := AABB(Vector3(-7.0, 0.0, 0.95), Vector3(0.2, 3.2, 2.5))
## Interactables that frame their moment, and the shot each carries.
const SHOTS := {
	&"q_talk": "res://assets/camera/shots/q_talk.tres",
	&"curtain": "res://assets/camera/shots/curtain.tres",
	&"window": "res://assets/camera/shots/window.tres",
	&"blackboard": "res://assets/camera/shots/blackboard.tres",
}
## Stand in front of Q, facing him (-z).
const Q_SPOT := Vector3(-3.3, 0.0, 4.2)

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _director: InnerVoiceDirector = null
var _interaction: InteractionController = null
var _rig: CameraRig = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "prologue_art_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	Harness.stage = "shaders"
	_check_shaders()
	Harness.stage = "isolation"
	_check_isolation()

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await process_frame
	await process_frame
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	_director = _main.get_node_or_null("InnerVoiceDirector") as InnerVoiceDirector
	_rig = _main.get_node_or_null("CameraRig") as CameraRig
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if (
		_host == null or _player == null or _dialogue == null or _sequence == null
		or _director == null or _interaction == null or _rig == null
	):
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_sequence.allow_player_control()
	if _host.get_current_path() != CLASSROOM or _host.get_current() == null:
		if not _host.load_location(CLASSROOM, &"PlayerStart", _player):
			Harness.finish(self, ["The classroom could not be entered."], "")
			return
	await _settle(30.0, "the classroom to settle")

	Harness.stage = "the cut"
	_check_cut()
	Harness.stage = "paper zone"
	await _check_paper_zone()
	Harness.stage = "paper follows the curtain"
	await _check_paper_follows_curtain()
	Harness.stage = "camera rig focus"
	await _check_rig_focus()
	Harness.stage = "camera focus in the game"
	await _check_focus_in_game()

	var save := root.get_node_or_null(^"Save")
	if save != null and save.has_method("forget_all"):
		save.forget_all()
	print("::notice title=prologue art::%s" % " | ".join(_notes))
	_main.queue_free()
	await process_frame
	Harness.finish(
		self,
		_failures,
		(
			"the classroom draws the experiment's concrete and paper, the cut is open floor to "
			+ "wall top with the blank sheet in it, the paper stays local and comes off again, and "
			+ "the camera focuses on Q's conversation and gives the framing back."
		)
	)


# --- 1. shaders and isolation ---------------------------------------------------------


func _check_shaders() -> void:
	var real_renderer := DisplayServer.get_name() != "headless"
	for path: String in SHADERS:
		var shader := load(path) as Shader
		if shader == null:
			_failures.append("%s does not load." % path)
			continue
		if not real_renderer:
			continue
		var names: Array[String] = []
		for uniform: Dictionary in shader.get_shader_uniform_list():
			names.append(String(uniform.get("name", "")))
		for wanted: String in SHADERS[path]:
			if not names.has(wanted):
				_failures.append("%s does not expose '%s' (did it fail to parse?)." % [path, wanted])
	if not real_renderer:
		_notes.append("shader uniforms skipped (headless)")


func _check_isolation() -> void:
	var scanned := 0
	for directory: String in ISOLATION_ROOTS:
		for path: String in _files_under(directory):
			if path.begins_with("res://scenes/dev/"):
				continue
			scanned += 1
			if FileAccess.get_file_as_string(path).contains("biology_classroom/"):
				_failures.append("%s names the experiment's folder." % path)
	_notes.append("isolation: %d files" % scanned)


func _files_under(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if ISOLATION_EXTENSIONS.has(file_name.get_extension()):
			found.append(directory.path_join(file_name))
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		found.append_array(_files_under(directory.path_join(sub)))
	return found


# --- 2. the cut -----------------------------------------------------------------------


func _check_cut() -> void:
	var room := _room()
	for gone: String in [
		"WallWest/SillShell", "WallWest/HeaderShell", "WallWest/PaintSill", "WallWest/PaintHeader",
	]:
		if room.get_node_or_null(NodePath(gone)) != null:
			_failures.append("'%s' is back: the cut is floor to wall top." % gone)
	var west := room.get_node(^"WallWest") as Node3D
	for node in west.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		if (mesh.global_transform * mesh.get_aabb()).intersects(CUT.grow(-0.02)):
			_failures.append("'%s' closes part of the cut." % mesh.name)
	var sheet := room.get_node_or_null(^"Anomalies/VoidOpening/BlankSheet") as MeshInstance3D
	if sheet == null:
		_failures.append("The cut has no blank sheet in it.")
		return
	var material := sheet.material_override as ShaderMaterial
	if material == null or material.resource_path != VOID_SHEET or not bool(material.get_shader_parameter("blank_sheet")):
		_failures.append("The blank sheet does not draw %s as a blank sheet." % VOID_SHEET)
	var box := sheet.global_transform * sheet.get_aabb()
	if (
		box.position.z > CUT.position.z + 0.05 or box.end.z < CUT.end.z - 0.05
		or box.position.y > 0.05 or box.end.y < 3.15
		or box.get_center().x < CUT.position.x or box.get_center().x > CUT.end.x
	):
		_failures.append("The blank sheet %s does not fill the cut %s." % [str(box), str(CUT)])
	if sheet.is_visible_in_tree():
		_failures.append("The blank sheet shows before the curtain is drawn.")


# --- 3. the paper zone ----------------------------------------------------------------


func _check_paper_zone() -> void:
	var zone := _zone()
	if zone == null:
		_failures.append("The classroom has no Anomalies/PaperZone.")
		return
	if absf(zone.global_position.x + 6.9) > 0.05 or absf(zone.global_position.z - 2.2) > 0.05:
		_failures.append("The paper zone %s is not centred on the cut." % str(zone.global_position))
	if zone.radius > 3.2:
		_failures.append("The paper zone's radius %.2f m is not local." % zone.radius)
	if zone.is_drawn() or not zone.get_covered_meshes().is_empty():
		_failures.append("The paper is on before the curtain was touched.")

	var meshes := _room_meshes()
	var before := {}
	for mesh in meshes:
		before[mesh] = mesh.material_overlay
	zone.set_drawn(true)
	var covered := zone.get_covered_meshes()
	_notes.append("paper covers %d of %d meshes" % [covered.size(), meshes.size()])
	if covered.is_empty():
		_failures.append("Drawing the paper covered nothing.")
	if not is_equal_approx(zone.get_reveal(), 1.0):
		_failures.append("An instant draw left the paper at %.2f." % zone.get_reveal())
	var actors := _room().get_node_or_null(^"Actors")
	var floor_paint := _room().get_node_or_null(^"Floor/Paint") as MeshInstance3D
	var curtain := _room().get_node_or_null(^"Anomalies/BackCurtain") as WindowCurtain
	for mesh in meshes:
		var carries := zone.carries_paper(mesh.material_overlay)
		var box := mesh.global_transform * mesh.get_aabb()
		if carries and not zone.reaches(box):
			_failures.append("'%s' carries the paper but lies outside the zone." % _relative(mesh))
		if carries and actors != null and actors.is_ancestor_of(mesh):
			_failures.append("The person '%s' was drawn on the paper." % _relative(mesh))
		if carries and box.position.x > 0.0:
			_failures.append("'%s', in the east half of the room, carries the paper." % _relative(mesh))
		if carries and covered.find(mesh) < 0:
			_failures.append("'%s' carries the paper without the zone knowing." % _relative(mesh))
		var authored: Material = before[mesh]
		if carries and authored != null and (mesh.material_overlay == authored or zone.carries_paper(authored)):
			# The authored overlay is kept in front of the paper, as a copy.
			_failures.append("'%s''s shared overlay was changed instead of copied." % _relative(mesh))
	if floor_paint == null or not zone.carries_paper(floor_paint.material_overlay):
		_failures.append("The floor at the cut is not on the paper.")
	if curtain != null:
		for panel in curtain.get_fabric_meshes():
			if not zone.carries_paper(panel.material_overlay):
				_failures.append("The curtain panel '%s' is not on the paper." % panel.name)
	for material in zone.get_overlay_materials():
		if not is_equal_approx(float(material.get_shader_parameter("zone_radius")), zone.radius):
			_failures.append("A paper overlay's radius disagrees with the zone.")
			break

	zone.set_drawn(false)
	for mesh in meshes:
		if mesh.material_overlay != before[mesh]:
			_failures.append("'%s' did not get its own overlay back." % _relative(mesh))
	if not zone.get_covered_meshes().is_empty() or zone.get_reveal() > 0.0:
		_failures.append("Giving the paper back left some of it on.")

	# Animated, it spreads from the cut and comes off again.
	zone.set_drawn(true, true)
	await _seconds(0.5)
	var early := zone.get_reveal()
	await _seconds(PaperZone.REVEAL_SECONDS)
	var late := zone.get_reveal()
	if not (early > 0.0 and early < 1.0 and is_equal_approx(late, 1.0)):
		_failures.append("The paper does not spread (%.2f after 0.5 s, %.2f at the end)." % [early, late])
	zone.set_drawn(false, true)
	await _seconds(PaperZone.LIFT_SECONDS + 0.4)
	if not zone.get_covered_meshes().is_empty():
		_failures.append("The animated release left paper on %d meshes." % zone.get_covered_meshes().size())
	for mesh in meshes:
		if is_instance_valid(mesh) and mesh.material_overlay != before[mesh]:
			_failures.append("'%s' did not get its overlay back after the animated release." % _relative(mesh))
			break


## The curtain's own state change drives the paper (the story, not a test hook).
func _check_paper_follows_curtain() -> void:
	var anomalies := _room().get_node_or_null(^"Anomalies") as ClassroomAnomalies
	var zone := _zone()
	if anomalies == null or zone == null:
		_failures.append("The classroom's anomalies or paper zone are missing.")
		return
	if anomalies.get_paper_zone() != zone:
		_failures.append("The anomalies do not know their paper zone.")
	await anomalies.draw_curtain(false)
	var sheet := _room().get_node_or_null(^"Anomalies/VoidOpening/BlankSheet") as MeshInstance3D
	if not zone.is_drawn() or zone.get_covered_meshes().is_empty():
		_failures.append("Drawing the curtain did not put the room round the cut on paper.")
	if sheet != null and not sheet.is_visible_in_tree():
		_failures.append("Drawing the curtain did not show the blank sheet in the cut.")
	# The refused fall's reset is the one way the story puts the curtain back.
	anomalies.reset_curtain_after_failed_transition()
	if zone.is_drawn() or not zone.get_covered_meshes().is_empty():
		_failures.append("Closing the curtain left the paper on.")
	if sheet != null and sheet.is_visible_in_tree():
		_failures.append("Closing the curtain left the blank sheet showing.")


# --- 4. camera focus ------------------------------------------------------------------


func _check_rig_focus() -> void:
	var room := _room()
	var q := room.find_interactable(&"q_talk")
	var curtain := room.find_interactable(&"curtain")
	if q == null or curtain == null or q.camera_shot == null or curtain.camera_shot == null:
		_failures.append("Q or the curtain carries no camera shot.")
		return
	for id: StringName in SHOTS:
		var item := room.find_interactable(id)
		if item == null or item.camera_shot == null or item.camera_shot.resource_path != SHOTS[id]:
			_failures.append("'%s' does not carry %s." % [id, SHOTS[id]])
	for item in room.find_children("*", "Interactable", true, false):
		var interactable := item as Interactable
		if interactable.camera_shot != null and not SHOTS.has(interactable.interact_id):
			_failures.append("'%s' frames itself, which only the important moments do." % interactable.interact_id)

	_player.teleport(Transform3D(Basis.IDENTITY, Q_SPOT))
	await _frames(3)
	var right := _rig.planar_right()
	var forward := _rig.planar_forward()
	var shot := q.camera_shot
	_rig.focus_on(q, shot)
	var peak := 0.0
	var previous := 0.0
	var monotonic := true
	for _index in int(shot.glide_seconds * 60.0 * 2.5):
		await physics_frame
		var weight := _rig.get_focus_weight()
		if weight + 0.0001 < previous:
			monotonic = false
		previous = weight
		peak = maxf(peak, weight)
	if not monotonic or peak > 1.0:
		_failures.append("The glide into a shot is not smooth (peak %.3f, monotonic %s)." % [peak, monotonic])
	if not is_equal_approx(_rig.get_focus_weight(), 1.0):
		_failures.append("The rig never arrived at the shot (%.3f)." % _rig.get_focus_weight())
	if not is_equal_approx(_rig.camera.fov, shot.fov):
		_failures.append("The shot's lens is %.1f, not %.1f." % [_rig.camera.fov, shot.fov])
	var default_distance := _rig.offset.length()
	var focused_distance := _rig.camera.position.length()
	if focused_distance > default_distance * 0.95:
		_failures.append("The shot did not bring the camera closer (%.2f of %.2f)." % [focused_distance, default_distance])
	if _rig.planar_right().distance_to(right) > 0.001 or _rig.planar_forward().distance_to(forward) > 0.001:
		_failures.append("A shot turned the movement axes under the player.")
	if not _sees(_player.global_position + Vector3.UP * 0.9) or not _sees(q.global_position):
		_failures.append("The shot of Q loses the player or Q.")

	# Straight on to the curtain: the two shots cross-fade, the view never dips home.
	_rig.focus_on(curtain, curtain.camera_shot)
	var lowest := 1.0
	for _index in int(curtain.camera_shot.glide_seconds * 60.0 * 2.0):
		await physics_frame
		lowest = minf(lowest, _rig.get_focus_weight())
	if lowest < 0.6:
		_failures.append("Moving from one shot to the next dipped back to the default (%.2f)." % lowest)
	if _rig.get_focus_subject() != curtain:
		_failures.append("The rig is not holding the curtain's shot.")

	_rig.release_focus()
	for _index in int(curtain.camera_shot.release_seconds * 60.0 * 2.5):
		await physics_frame
	_expect_default_pose("after a release")
	_rig.focus_on(q, shot)
	await _frames(10)
	_rig.clear_focus()
	_expect_default_pose("after a clear")


func _check_focus_in_game() -> void:
	var focus := _sequence.get_camera_focus()
	if focus == null:
		_failures.append("The opening sequence has no camera focus director.")
		return
	_player.teleport(Transform3D(Basis.IDENTITY, Q_SPOT))
	await _frames(3)
	var q := _room().find_interactable(&"q_talk")
	_interaction.set_enabled(true)
	_interaction.request_activation(q)
	await process_frame
	var engaged := false
	var peak := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 30000:
		if _rig.get_focus_subject() == q:
			engaged = true
		peak = maxf(peak, _rig.get_focus_weight())
		if not _dialogue.is_busy() and not _sequence.is_beat_active():
			break
		# Read slowly enough for the glide to arrive.
		if _dialogue.is_busy() and Engine.get_physics_frames() % 40 == 0:
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await physics_frame
	if not engaged or peak < 0.9:
		_failures.append("Talking to Q did not bring the camera in (engaged %s, peak %.2f)." % [engaged, peak])
	await _settle(20.0, "Q's conversation")
	if focus.get_subject() != null or _rig.get_focus_subject() != null:
		_failures.append("The camera kept Q's shot after the conversation gave control back.")
	await _seconds(q.camera_shot.release_seconds * 2.5)
	_expect_default_pose("after talking to Q")

	# A moment without a shot never moves the camera.
	_interaction.set_enabled(true)
	_interaction.request_activation(_room().find_interactable(&"timetable"))
	var moved := 0.0
	for _index in 30:
		moved = maxf(moved, _rig.get_focus_weight())
		await physics_frame
	await _settle(20.0, "the timetable")
	if moved > 0.0:
		_failures.append("Reading the timetable moved the camera (%.2f)." % moved)

	# An activation that never locks the player is released on the next frame.
	focus.engage(q)
	await process_frame
	await process_frame
	if focus.get_subject() != null:
		_failures.append("A shot with no lock behind it was kept.")
	await _seconds(q.camera_shot.release_seconds * 2.5)
	_expect_default_pose("after an unlocked activation")


func _expect_default_pose(label: String) -> void:
	if _rig.get_focus_weight() > 0.0:
		_failures.append("%s the focus weight is %.4f, not 0." % [label.capitalize(), _rig.get_focus_weight()])
	if not _rig.camera.position.is_equal_approx(_rig.offset):
		_failures.append("%s the camera is at %s, not the default offset." % [label.capitalize(), str(_rig.camera.position)])
	if not is_equal_approx(_rig.camera.fov, _rig.fov):
		_failures.append("%s the lens is %.2f, not %.1f." % [label.capitalize(), _rig.camera.fov, _rig.fov])
	var expected := _player.global_position + _rig.offset
	if _rig.get_frame_weight() <= 0.0 and _rig.camera.global_position.distance_to(expected) > 0.05:
		_failures.append("%s the camera is not back on the player." % label.capitalize())


func _sees(point: Vector3) -> bool:
	var camera := _rig.camera
	if camera.is_position_behind(point):
		return false
	var screen := camera.unproject_position(point)
	var size := camera.get_viewport().get_visible_rect().size
	return screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= size.x and screen.y <= size.y


# --- helpers --------------------------------------------------------------------------


func _room() -> LocationRoot:
	return _host.get_current()


func _zone() -> PaperZone:
	return _room().get_node_or_null(^"Anomalies/PaperZone") as PaperZone


func _room_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in _room().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			meshes.append(mesh)
	return meshes


func _relative(node: Node) -> String:
	return String(_room().get_path_to(node))


func _settle(timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while (
		_dialogue.is_busy()
		or _sequence.is_beat_active()
		or _director.pending_count() > 0
		or _director.is_firing()
	):
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			_failures.append("Timed out waiting for %s." % label)
			return false
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
	await process_frame
	await process_frame
	return true


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame
