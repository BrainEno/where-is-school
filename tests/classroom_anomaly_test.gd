extends SceneTree
## The biology classroom's impossible thing (docs/ART_BIBLE.md, location studies) and its
## doors (issue #159), played through the real main scene, director and dialogue.
##
## Claims under test:
##
## 1. **Placed, and decoration only.** The back window is a real hole through the west wall
##    - no glass, no view, no frame, no backdrop - with a floor-to-ceiling blackout curtain
##    drawn over it; the front window (Window0) stays ordinary and shows the washing. Both
##    doors are on the east wall: the grey front door and the white rear door, one model in
##    the classroom's materials. There is no staircase in the room. None of it collides.
## 2. **The lesson is not over.** Before N lets the class go the curtain is only looked at
##    and the rear door does not give: nothing changes, no flag is written.
## 3. **The rear door never opens.** After the class is dismissed it still only says that
##    it never opens unless special means are used: no beat, no camera, no flag, no
##    staircase, and the leaf has not moved.
## 3b. **The projection screen is furniture.** It is rolled up when the room loads; its
##    pull rolls it all the way down over the board and, used again, back up, with the
##    prompt following. No conversation, no inspection, no story flag, nothing saved.
## 4. **The curtain.** Leaving it drawn changes nothing. Drawing it aside (after an
##    orientation check that is visible and recorded) uncovers the void, and the
##    protagonist falls: the next room is the yard, at `FromSchool`, with the landing line
##    instead of the yard's ordinary arrival; the provisional `curtain_fall_pending` flag is
##    spent; the body is upright and the view level.
## 5. **The room remembers.** Walking back into the classroom finds the curtain open on the
##    void and the rear door still shut, and the curtain does not throw the player out a
##    second time.
## 6. **A refused fall is recoverable** (issue #148). Through the real curtain, director,
##    handler, departure and `LocationFlow`, with only the destination in the request the
##    handler hands back replaced by this test: a missing scene, a missing spawn and a
##    destination that refuses (wrong id). Each time the production `on_failure` runs once,
##    behind the black and inside the beat; the classroom is not replaced; no arrival
##    state, landing line or landing record is written; `curtain_fall_pending` stays and
##    `curtain_drawn` does not; the curtain is closed over the opening again with the retry
##    prompt; the body is upright, the view level and unframed, control is back and the
##    beat was released once. Three failures in a row accumulate nothing. Choosing "Leave
##    it drawn" on the retry does not fall. The failed state goes to disk, the world is
##    freed, memory cleared and Continue brings back the same room, flags, curtain and
##    route - and from there the real curtain falls into the yard, once.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const TIME_SCALE := 4.0
## Real seconds for the whole file; godot-ci.yml gives it 300 and the watchdog 290.
const BUDGET_SECONDS := 270.0
## The shared window panorama. Only its last third (s 3.0..4.5 m, window 0) has the washing
## painted into it (art/classroom/paint_classroom_textures.py, `window_view`).
const PANORAMA := "res://assets/materials/classroom/textures/window_view.png"
const WASHING_OFFSET := 0.6667
const DOOR_WHITE := "res://assets/materials/classroom/door_white.tres"
const DOOR_GRAY := "res://assets/materials/classroom/door_gray.tres"
const REAR_DOOR_TEXT := "这扇门从来不会打开，除非使用特殊的手段。"
const REAR_DOOR_TEXT_EN := "This door never opens, unless special means are used."
## The hole through the west wall (art/classroom/paint_classroom_textures.py,
## `WEST_VOID_OPENING`): z 0.95..3.45, y 0.50..2.75, through x -7.0..-6.8.
const VOID_HOLE := AABB(Vector3(-7.0, 0.5, 0.95), Vector3(0.2, 2.25, 2.5))
## Window1's old glass, view, frame and tie-back curtain. None of it may come back.
const REMOVED_WINDOW_PARTS: Array[String] = [
	"WindowGlow1", "WindowGlass1", "WindowFrameTop1", "WindowFrameBottom1",
	"WindowFrameLeft1", "WindowFrameRight1", "WindowMullion1",
	"WallWest/CurtainRod1", "WallWest/CurtainPanel1L", "WallWest/CurtainPanel1R",
]
const CHECK_KEY := "classroom_curtain/cc_edges_check"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
## A scene nobody ships, for the refused-fall fixture (never written anywhere).
const MISSING_SCENE := "user://classroom_anomaly_fixtures/no_such_yard.tscn"
## Story time runs faster through the refused falls: nothing in them walks.
const FAILURE_TIME_SCALE := 8.0
## The spot in front of the back window every curtain check stands on.
const CURTAIN_SPOT := Vector3(-5.9, 0.0, 2.2)
## In front of the rear door, facing it (+x).
const REAR_DOOR_SPOT := Vector3(5.9, 0.0, 3.55)
## On the platform in front of the screen's pull, facing the board (-z).
const SCREEN_SPOT := Vector3(-2.9, 0.17, -3.45)

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _interaction: InteractionController = null
var _sequence: OpeningSequence = null
var _director: InnerVoiceDirector = null
var _game_state: Node = null
var _narrative: Node = null
var _started := 0
var _conversations: Array[StringName] = []
var _inspections: Array[StringName] = []
## `location_entered` emissions of the current world's host.
var _entered := 0
var _lap_started := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 290.0, "classroom_anomaly_test.gd")
	call_deferred("_run")


func _run() -> void:
	_started = Time.get_ticks_msec()
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

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
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if (
		_host == null
		or _player == null
		or _dialogue == null
		or _sequence == null
		or _director == null
		or _interaction == null
	):
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_connect_world()
	# The prologue is not run here (autostart is off), so nothing hands the player control
	# the way the game does when it ends; without this every beat would end with control
	# still withheld and "control is back" could not be checked.
	_sequence.allow_player_control()
	Engine.time_scale = TIME_SCALE

	if _host.get_current_path() != CLASSROOM or _host.get_current() == null:
		if not _host.load_location(CLASSROOM, &"PlayerStart", _player):
			Harness.finish(self, ["The classroom could not be entered."], "")
			return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	await _settle(30.0, "the classroom to settle")

	Harness.stage = "placement"
	_check_placement()
	Harness.stage = "during the lesson"
	await _check_lesson()
	Harness.stage = "rear door"
	await _check_rear_door()
	Harness.stage = "projector screen"
	await _check_projector_screen()
	Harness.stage = "curtain left drawn"
	await _check_curtain_left()
	_lap("before the refused falls")
	Harness.stage = "refused fall: missing scene"
	await _check_refused_fall("a missing scene", {"scene": MISSING_SCENE})
	Harness.stage = "refused fall: missing spawn"
	await _check_refused_fall("a missing spawn", {"spawn": &"NoSuchMarker"})
	Harness.stage = "refused fall: destination refuses"
	await _check_refused_fall("a destination that refuses", {"id": &"not_the_playground"})
	Harness.stage = "retry, then leave it drawn"
	await _check_retry_left_drawn()
	_lap("refused falls")
	Harness.stage = "refused fall survives the disk"
	await _check_refused_state_on_disk()
	_lap("disk round trip")
	Harness.stage = "curtain and fall"
	await _check_fall()
	Harness.stage = "the room remembers"
	await _check_return()
	_lap("fall and return")

	var save := root.get_node_or_null(^"Save")
	if save != null and save.has_method("forget_all"):
		# The arrival checkpoints wrote a save; the next test in the job must not boot into it.
		save.forget_all()
	Engine.time_scale = 1.0
	print("::notice title=classroom anomalies::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		(
			"the curtained window opens on nothing and drops the player into the yard and is "
			+ "remembered; the rear door on the east wall never opens; nothing collides."
		)
	)


# --- 1. placement -------------------------------------------------------------------


func _room() -> LocationRoot:
	return _host.get_current()


func _anomalies() -> Node:
	return _room().get_node_or_null(^"Anomalies") if _room() != null else null


func _curtain() -> WindowCurtain:
	return _room().get_node_or_null(^"Anomalies/BackCurtain") as WindowCurtain


func _door() -> ClassroomDoorDressing:
	return _room().get_node_or_null(^"WallEast/RearDoor") as ClassroomDoorDressing


func _front_door() -> ClassroomDoorDressing:
	return _room().get_node_or_null(^"WallEast/FrontDoor") as ClassroomDoorDressing


func _void() -> Node3D:
	return _room().get_node_or_null(^"Anomalies/VoidOpening") as Node3D


## Global transforms of the rear door's leaf meshes, to prove it never moved.
func _leaf_pose() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for leaf in _door().get_leaf_meshes():
		pose.append(leaf.global_transform)
	return pose


## True when the room has no staircase and no swinging door anywhere in it.
func _no_staircase() -> bool:
	var room := _room()
	if room.get_node_or_null(^"Anomalies/Staircase") != null:
		return false
	for node in room.find_children("*", "Node3D", true, false):
		if node is SuspendedStair or node is SwingDoor:
			return false
	return true


func _check_placement() -> void:
	var curtain := _curtain()
	var door := _door()
	var front_door := _front_door()
	var void_marker := _void()
	if (
		_anomalies() == null
		or curtain == null
		or door == null
		or front_door == null
		or void_marker == null
	):
		_failures.append(
			"The classroom lost one of Anomalies, its curtain, void marker or east-wall doors."
		)
		return
	for scope: Node in [_anomalies(), door, front_door]:
		for node in scope.find_children("*", "CollisionObject3D", true, false):
			_failures.append(
				"'%s' collides; the curtain and doors are decoration." % _room().get_path_to(node)
			)

	# The ordinary window shows the washing.
	var front := (
		(_room().get_node(^"WindowGlow0") as MeshInstance3D).material_override as BaseMaterial3D
	)
	if (
		front == null
		or front.albedo_texture == null
		or front.albedo_texture.resource_path != PANORAMA
		or absf(front.uv1_offset.x - WASHING_OFFSET) > 0.01
	):
		_failures.append("The ordinary window does not show the washing on the line.")

	# The back window is a hole: nothing of Window1 is left, and nothing drawn under the
	# west wall reaches into the opening. The wall's collision stays whole.
	for removed: String in REMOVED_WINDOW_PARTS:
		if _room().get_node_or_null(NodePath(removed)) != null:
			_failures.append("Window1's '%s' is still in the room." % removed)
	var west := _room().get_node(^"WallWest") as Node3D
	var hole := VOID_HOLE.grow(-0.02)
	for node in west.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		if box.intersects(hole):
			_failures.append(
				"'%s' %s covers the hole in the west wall." % [mesh.name, str(box)]
			)
	var west_shapes := west.find_children("*", "CollisionShape3D", true, false)
	if west_shapes.size() != 1:
		_failures.append("The west wall has %d collision shapes, not one." % west_shapes.size())
	else:
		var west_box := (west_shapes[0] as CollisionShape3D).shape as BoxShape3D
		if west_box == null or not west_box.size.is_equal_approx(Vector3(0.2, 3.2, 10.0)):
			_failures.append("The west wall's collision is no longer the whole wall.")
	if void_marker.visible:
		_failures.append("The void is uncovered before the curtain was touched.")
	if absf(void_marker.global_position.z - 2.2) > 0.05:
		_failures.append("The void marker %s is not in the opening." % str(void_marker.global_position))

	# The blackout curtain: closed, and covering the opening with room to spare.
	if curtain.is_open():
		_failures.append("The back-window curtain starts open.")
	var fabric := curtain.get_fabric_aabb()
	_notes.append("curtain %s" % str(fabric))
	if (
		fabric.position.z > VOID_HOLE.position.z - 0.2
		or fabric.end.z < VOID_HOLE.end.z + 0.2
		or fabric.position.y > 0.12
		or fabric.end.y < 3.0
	):
		_failures.append(
			(
				"The closed curtain %s does not hang floor to ceiling over the opening %s."
				% [str(fabric), str(VOID_HOLE)]
			)
		)
	if fabric.position.x < -6.8 or fabric.end.x > -6.35:
		_failures.append("The curtain %s is not hung just off the west wall." % str(fabric))

	# The doors: both on the east wall, in their openings, one model; the rear one white.
	for pair: Array in [[front_door, -3.55, DOOR_GRAY], [door, 3.55, DOOR_WHITE]]:
		var dressing := pair[0] as ClassroomDoorDressing
		var box := _subtree_aabb(dressing)
		_notes.append("%s %s" % [dressing.name, str(box)])
		if (
			box.position.x < 6.65
			or box.end.x > 7.0
			or absf(box.get_center().z - float(pair[1])) > 0.1
			or box.size.z > 1.25
			or box.end.y > 2.25
			or box.position.y < -0.01
		):
			_failures.append("%s %s is not in its east-wall opening." % [dressing.name, str(box)])
		var leaves := dressing.get_leaf_meshes()
		if leaves.is_empty():
			_failures.append("%s has no leaf." % dressing.name)
		for leaf in leaves:
			if leaf.material_override == null or leaf.material_override.resource_path != pair[2]:
				_failures.append("%s's '%s' is not %s." % [dressing.name, leaf.name, pair[2]])
				break
	if not _no_staircase():
		_failures.append("There is a staircase or a swinging door in the classroom.")

	var curtain_interactable := _room().find_interactable(&"curtain") as StagedInteractable
	if curtain_interactable == null or not curtain_interactable.is_staged():
		_failures.append("The curtain interactable is missing or has no stage handler.")
	var rear := _room().find_interactable(&"rear_door")
	if rear == null or rear is StagedInteractable or rear.inspection_id != &"classroom_rear_door":
		_failures.append("The rear door is not a plain inspection of classroom_rear_door.")


# --- 2. during the lesson -----------------------------------------------------------


func _check_lesson() -> void:
	var before: Dictionary = _game_state.get_snapshot()
	_conversations.clear()
	await _activate(&"curtain")
	await _settle(40.0, "the curtain during the lesson")
	if not _conversations.has(&"classroom_curtain_lesson"):
		_failures.append(
			"During the lesson the curtain played %s, not its lesson line." % str(_conversations)
		)
	_inspections.clear()
	await _activate(&"rear_door")
	await _settle(40.0, "the rear door during the lesson")
	if not _inspections.has(&"classroom_rear_door"):
		_failures.append("During the lesson the rear door did not say it does not give.")
	if _curtain().is_open() or not _no_staircase():
		_failures.append("Something moved during the lesson.")
	for flag: StringName in [
		StoryFlags.CURTAIN_FALL_PENDING, StoryFlags.CURTAIN_DRAWN, StoryFlags.REAR_DOOR_OPENED
	]:
		if _flag(flag):
			_failures.append("'%s' was set during the lesson." % flag)
	if _game_state.get_snapshot().size() > before.size() + 2:
		_notes.append("lesson wrote %d flags" % (_game_state.get_snapshot().size() - before.size()))


# --- 3. the rear door ---------------------------------------------------------------


func _check_rear_door() -> void:
	_game_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_player.teleport(Transform3D(Basis(Vector3.UP, -PI * 0.5), REAR_DOOR_SPOT))
	await _frames(4)
	var before := _leaf_pose()
	var rig := _player.camera_rig
	var framed := false
	_conversations.clear()
	_inspections.clear()
	await _activate(&"rear_door")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		if rig != null and rig.get_frame_weight() > 0.1:
			framed = true
		if not _dialogue.is_busy() and _inspections.size() > 0:
			break
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	await _settle(20.0, "the rear door after the lesson")
	if _inspections != [&"classroom_rear_door"]:
		_failures.append(
			"After the lesson the rear door presented %s, not its one inspection." % str(_inspections)
		)
	if not _conversations.is_empty():
		_failures.append("The rear door started a conversation: %s." % str(_conversations))
	if _flag(StoryFlags.REAR_DOOR_OPENED):
		_failures.append("The rear door recorded itself as opened.")
	if framed:
		_failures.append("The camera went somewhere when the rear door was tried.")
	if not _no_staircase():
		_failures.append("Trying the rear door put a staircase in the room.")
	if _narrative.has_entry(&"saw_suspended_stair"):
		_failures.append("The staircase was recorded.")
	_check_rear_door_text()
	var after := _leaf_pose()
	for index in mini(before.size(), after.size()):
		if not before[index].is_equal_approx(after[index]):
			_failures.append("The rear door's leaf moved.")
			break


## The words the door says, in both languages, and nothing left of the "open" text.
func _check_rear_door_text() -> void:
	for pair: Array in [["zh-CN", REAR_DOOR_TEXT], ["en", REAR_DOOR_TEXT_EN]]:
		var path := "res://data/inspections/%s/classroom.json" % pair[0]
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			_failures.append("%s could not be read." % path)
			continue
		var entry: Variant = (data as Dictionary).get("classroom_rear_door")
		if not (entry is Dictionary) or (entry as Dictionary).get("text") != pair[1]:
			_failures.append("%s: classroom_rear_door does not say '%s'." % [path, pair[1]])
		if (data as Dictionary).has("classroom_rear_door_open"):
			_failures.append("%s still has classroom_rear_door_open." % path)


# --- 3b. the projection screen -----------------------------------------------------


func _check_projector_screen() -> void:
	var room := _room()
	var screen := room.get_node_or_null(^"WallNorth/ProjectorScreen") as ProjectorScreen
	var pull := room.find_interactable(&"projector_screen") as StagedInteractable
	if screen == null or pull == null:
		_failures.append("The projection screen or its staged pull is missing.")
		return
	if not pull.is_staged():
		_failures.append("The screen's pull has no stage handler (ScreenControl did not bind).")
		return
	if not screen.is_rolled_up():
		_failures.append("The projection screen was not rolled up when the room loaded.")
	if pull.get_prompt() != "prompt.projector_screen_down":
		_failures.append("The rolled-up screen's prompt is '%s'." % pull.get_prompt())
	var flags_before: Dictionary = _game_state.get_snapshot().duplicate(true)
	_player.teleport(Transform3D(Basis.IDENTITY, SCREEN_SPOT))
	await _frames(4)
	_conversations.clear()
	_inspections.clear()
	for want_down: bool in [true, false]:
		await _activate(&"projector_screen")
		await _settle(20.0, "the screen to roll %s" % ("down" if want_down else "up"))
		if want_down and not screen.is_unrolled():
			_failures.append(
				"Pulling the screen left it at %.2f, not all the way down." % screen.get_unroll_amount()
			)
		if not want_down and not screen.is_rolled_up():
			_failures.append(
				"Pulling the screen again left it at %.2f, not rolled up." % screen.get_unroll_amount()
			)
		var want_prompt := "prompt.projector_screen_up" if want_down else "prompt.projector_screen_down"
		if pull.get_prompt() != want_prompt:
			_failures.append("After a pull the screen's prompt is '%s'." % pull.get_prompt())
	if not _conversations.is_empty() or not _inspections.is_empty():
		_failures.append(
			"The screen started %s / %s; it should only move." % [str(_conversations), str(_inspections)]
		)
	if _game_state.get_snapshot() != flags_before:
		_failures.append("Pulling the screen changed the story state.")


# --- 4. the curtain -----------------------------------------------------------------


func _check_curtain_left() -> void:
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-5.9, 0.0, 2.2)))
	await _frames(4)
	_conversations.clear()
	await _activate(&"curtain")
	if not await _choose(&"leave", "the curtain's first choice"):
		return
	await _settle(30.0, "leaving the curtain")
	if not _conversations.has(&"classroom_curtain"):
		_failures.append("After the lesson the curtain played %s." % str(_conversations))
	if _flag(StoryFlags.CURTAIN_FALL_PENDING) or _curtain().is_open() or _void().visible:
		_failures.append("Leaving the curtain drawn still opened it.")
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != "classroom":
		_failures.append("Leaving the curtain drawn left the classroom.")


## One refused fall through the real curtain (claim 6). The interaction, the director, the
## room's own `_stage_curtain`, its departure and its `on_failure` are all production; the
## test only wraps the handler so that, in the request the handler returns, `tamper`
## replaces the destination and the production recovery is observed on its way through.
func _check_refused_fall(label: String, tamper: Dictionary) -> void:
	var room := _room()
	var anomalies := _anomalies() as ClassroomAnomalies
	var staged := room.find_interactable(&"curtain") as StagedInteractable if room != null else null
	if anomalies == null or staged == null or not staged.is_staged():
		_failures.append("%s: the curtain or its staged handler is unavailable." % label)
		return
	var ui := _main.get_node_or_null("GameUI") as GameUI
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), CURTAIN_SPOT))
	await _frames(4)
	var stood_at := _player.global_position
	var original: Callable = staged.stage_handler
	var requests: Array[Dictionary] = []
	var recoveries: Array[Dictionary] = []
	staged.stage_handler = func(director: Node) -> Dictionary:
		var request: Dictionary = await original.call(director)
		var transition: Dictionary = request.get("transition", {})
		requests.append({"transition": not transition.is_empty()})
		if transition.is_empty():
			return request
		var production: Callable = transition.get("on_failure", Callable())
		if (
			production.get_object() != anomalies
			or production.get_method() != &"reset_curtain_after_failed_transition"
		):
			_failures.append("%s: the fall's on_failure is not the room's own reset." % label)
		transition["on_failure"] = func() -> void:
			recoveries.append(
				{
					"beat": _sequence.is_beat_active(),
					"alpha": ui.fade.color.a if ui != null else -1.0,
					"room": _host.get_current(),
					"void": _void().visible,
				}
			)
			await production.call()
		for key: String in tamper:
			transition[key] = tamper[key]
		return request

	var entered_before := _entered
	var location_before := String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, ""))
	_conversations.clear()
	Engine.time_scale = FAILURE_TIME_SCALE
	await _activate(&"curtain")
	var chose := await _choose(&"draw", "%s: drawing the curtain" % label)
	var releases := 0
	var was_held := true
	var max_pitch := 0.0
	var saw_void := false
	var started := Time.get_ticks_msec()
	while chose and Time.get_ticks_msec() - started < 40000 and not _over_budget():
		var held := _sequence.is_beat_active()
		if was_held and not held:
			releases += 1
			if not recoveries.is_empty():
				# The staged moment's beat is over. Later beats (an inner voice) are not it.
				was_held = false
				break
		was_held = held
		if _player.visual != null:
			max_pitch = maxf(max_pitch, _player.visual.rotation_degrees.x)
		if _void() != null and _void().visible:
			saw_void = true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	if was_held:
		_failures.append("%s: the staged moment's beat was never released." % label)
	await _settle(20.0, "%s: the refused fall" % label)
	Engine.time_scale = TIME_SCALE
	staged.stage_handler = original
	if not chose:
		return

	# The real handler staged the fall, the real departure posed the body, and the
	# production recovery ran once, behind the black, inside the beat, in this room.
	if requests.size() != 1 or not bool(requests[0]["transition"]):
		_failures.append("%s: the curtain handler did not stage a fall (%s)." % [label, str(requests)])
	if not saw_void:
		_failures.append("%s: the void never showed before the refused fall." % label)
	if max_pitch < 20.0:
		_failures.append("%s: the body never leaned out (pitch %.1f)." % [label, max_pitch])
	if recoveries.size() != 1:
		_failures.append("%s: on_failure ran %d time(s), not once." % [label, recoveries.size()])
	else:
		var seen: Dictionary = recoveries[0]
		if not bool(seen["beat"]):
			_failures.append("%s: on_failure ran after the beat was released." % label)
		if float(seen["alpha"]) < 0.99:
			_failures.append("%s: on_failure ran with the room already fading back in." % label)
		if seen["room"] != room:
			_failures.append("%s: on_failure ran when the classroom was no longer current." % label)
		if not bool(seen["void"]):
			_failures.append("%s: on_failure ran before the departure had drawn the curtain." % label)
	if releases != 1:
		_failures.append("%s: the beat was released %d time(s), not once." % [label, releases])

	# Nothing moved: the same classroom, the same story location, no arrival.
	if _host.get_current() != room:
		_failures.append("%s: the classroom was replaced." % label)
	if _entered != entered_before:
		_failures.append("%s: location_entered was emitted %d time(s)." % [label, _entered - entered_before])
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != location_before:
		_failures.append("%s: CURRENT_LOCATION changed." % label)
	_expect_refused_state(label)
	for id: StringName in [&"classroom_fall_landing", &"playground_arrival"]:
		if _conversations.has(id):
			_failures.append("%s: '%s' played after a refused fall." % [label, id])
	var moved := Vector2(
		_player.global_position.x - stood_at.x, _player.global_position.z - stood_at.z
	).length()
	if moved > 0.1:
		_failures.append("%s: the player was moved %.2f m by a refused fall." % [label, moved])
	_notes.append("%s: recovered once, beat released %d, lean %.0f deg" % [label, releases, max_pitch])


## What a refused fall leaves behind, wherever it is checked from: the flags, the room and
## the player all say "still in the classroom, the fall still to come".
func _expect_refused_state(label: String) -> void:
	if not _flag(StoryFlags.CURTAIN_FALL_PENDING):
		_failures.append("%s: curtain_fall_pending was spent." % label)
	if _flag(StoryFlags.CURTAIN_DRAWN):
		_failures.append("%s: curtain_drawn was committed." % label)
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != "classroom":
		_failures.append("%s: CURRENT_LOCATION is not the classroom." % label)
	if _flag(StoryFlags.PLAYGROUND_ARRIVED):
		_failures.append("%s: the yard's arrival flag was written." % label)
	if _narrative.has_entry(&"fell_into_playground"):
		_failures.append("%s: the landing was recorded." % label)
	if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) == "objective.playground":
		_failures.append("%s: the objective moved to the yard." % label)
	var room := _room()
	if room == null or room.location_id != &"classroom":
		_failures.append("%s: the player is not in the classroom." % label)
		return
	if _curtain().is_open() or _curtain().get_open_amount() > 0.001:
		_failures.append("%s: the curtain is still open (%.2f)." % [label, _curtain().get_open_amount()])
	if _void().visible:
		_failures.append("%s: the void is still marked uncovered." % label)
	var curtain := room.find_interactable(&"curtain")
	if curtain == null or curtain.get_prompt_override() != "prompt.curtain_retry":
		_failures.append("%s: the curtain does not offer to be tried again." % label)
	var visual := _player.visual
	if (
		visual != null
		and (
			absf(visual.rotation_degrees.x) > 0.5
			or not visual.position.is_equal_approx(Vector3(0.0, 0.9, 0.0))
		)
	):
		_failures.append(
			"%s: the body is not upright (pitch %.1f, at %s)."
			% [label, visual.rotation_degrees.x, str(visual.position)]
		)
	var rig := _player.camera_rig
	if rig != null and (absf(rig.get_roll()) > 0.5 or rig.get_frame_weight() > 0.01):
		_failures.append(
			"%s: the view is rolled %.1f deg / framed %.2f." % [label, rig.get_roll(), rig.get_frame_weight()]
		)
	if _sequence.is_beat_active() or _dialogue.is_busy():
		_failures.append("%s: a beat or a conversation is still running." % label)
	if not _player.is_control_enabled() or not _interaction.is_enabled():
		_failures.append("%s: the player has no control or cannot interact." % label)


## After a refusal the curtain asks again; "Leave it drawn" this time must not fall, and
## leaves exactly the refused state behind.
func _check_retry_left_drawn() -> void:
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), CURTAIN_SPOT))
	await _frames(4)
	var room := _room()
	if ConversationRouter.select(&"classroom_curtain", _game_state.get_snapshot()) != &"classroom_curtain":
		_failures.append("After a refused fall the curtain routes to another conversation.")
	_conversations.clear()
	Engine.time_scale = FAILURE_TIME_SCALE
	await _activate(&"curtain")
	var chose := await _choose(&"leave", "the retried curtain")
	await _settle(30.0, "leaving the retried curtain")
	Engine.time_scale = TIME_SCALE
	if not chose:
		return
	if not _conversations.has(&"classroom_curtain"):
		_failures.append("The retried curtain played %s." % str(_conversations))
	if _conversations.has(&"classroom_curtain_void"):
		_failures.append("Leaving the curtain drawn on a retry still showed the void.")
	if _host.get_current() != room:
		_failures.append("Leaving the curtain drawn on a retry left the classroom.")
	_expect_refused_state("leaving it drawn on the retry")


## The refused state on disk (claim 6): written through the real save, the world freed,
## memory cleared, and Continue - the title screen's own call - brings it back. The test
## then carries on in that world: the fall that follows is the retry.
func _check_refused_state_on_disk() -> void:
	var save := root.get_node_or_null(^"Save")
	var session := Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if save == null or session == null:
		_failures.append("Save / Session are unavailable for the disk round trip.")
		return
	var written: Dictionary = save.save_game()
	if not bool(written.get("ok", false)):
		_failures.append("The refused state was not saved: %s" % str(written))
		return
	var info: Dictionary = save.peek_save()
	if StringName(String(info.get("location_id", ""))) != &"classroom":
		_failures.append("The save on disk does not describe the classroom: %s" % str(info))
	var old_world := _main
	_sequence.set("autosave_enabled", false)
	old_world.queue_free()
	await _frames(3)
	save.unbind_world()
	_game_state.clear()
	_narrative.clear()
	if is_instance_valid(old_world):
		_failures.append("The world with the refused fall was not freed.")
	var result: Dictionary = session.continue_game()
	if not bool(result.get("ok", false)):
		_failures.append("Continue failed: %s" % str(result))
		return
	if not await _adopt_current_world():
		return
	await _settle(40.0, "the continued classroom")
	var label := "after Continue"
	_expect_refused_state(label)
	if not _narrative.has_entry(&"drew_back_curtain") or not _narrative.has_entry(&"saw_void_window"):
		_failures.append("%s: what the player saw before the refusal was not restored." % label)
	if ConversationRouter.select(&"classroom_curtain", _game_state.get_snapshot()) != &"classroom_curtain":
		_failures.append("%s: the curtain routes to another conversation." % label)
	if not _flag(StoryFlags.CLASS_DISMISSED) or _flag(StoryFlags.REAR_DOOR_OPENED):
		_failures.append("%s: the rest of the story did not come back." % label)
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), CURTAIN_SPOT))
	await _frames(4)


## Points this test at the world Continue made (the current scene).
func _adopt_current_world() -> bool:
	for _index in 600:
		await process_frame
		var scene := current_scene
		if scene == null or scene.get_node_or_null("OpeningSequence") == null:
			continue
		_main = scene
		_host = scene.get_node_or_null("LocationHost") as LocationHost
		_player = scene.get_node_or_null("Player") as PlayerController
		_dialogue = scene.get_node_or_null("DialogueController") as DialogueController
		_sequence = scene.get_node_or_null("OpeningSequence") as OpeningSequence
		_director = scene.get_node_or_null("InnerVoiceDirector") as InnerVoiceDirector
		_interaction = (
			_player.get_node_or_null("InteractionController") as InteractionController
			if _player != null
			else null
		)
		if (
			_host == null or _player == null or _dialogue == null or _sequence == null
			or _director == null or _interaction == null
		):
			_failures.append("The continued world did not expose the nodes this test needs.")
			return false
		_connect_world()
		for _settle_frame in 30:
			if _host.get_current() != null:
				break
			await process_frame
		return _host.get_current() != null
	_failures.append("Continue never produced a world.")
	return false


func _check_fall() -> void:
	var seed_value := -1
	for candidate in 4000:
		if CheckResolver.new(candidate).dice_total_for(CHECK_KEY) >= 12:
			seed_value = candidate
			break
	if seed_value >= 0:
		_dialogue.set_check_resolver(CheckResolver.new(seed_value))
	_conversations.clear()
	var entered_before := _entered
	await _activate(&"curtain")
	if not await _choose(&"edges", "the look at the hem"):
		return
	if not await _choose(&"draw", "drawing the curtain"):
		return
	var record: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"classroom_curtain", &"cc_edges_check"), null
	)
	if not (record is Dictionary):
		_failures.append("The curtain's orientation check was not recorded.")
	elif not _narrative.has_entry(&"curtain_hangs_still"):
		_failures.append("A passed check at the curtain recorded nothing.")
	# The fall: the void is shown, the room goes, the yard comes.
	var saw_void := false
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 60000:
		var room := _room()
		if (
			room != null
			and String(room.location_id) == "classroom"
			and _void() != null
			and _void().visible
			and _curtain().get_open_amount() > 0.5
		):
			saw_void = true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		if (
			String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground"
			and _flag(StoryFlags.PLAYGROUND_ARRIVED)
			and not _dialogue.is_busy()
			and not _sequence.is_beat_active()
		):
			break
		await process_frame
	await _settle(40.0, "the landing")
	if not saw_void:
		_failures.append("Drawing the curtain never uncovered the void.")
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != "playground":
		_failures.append("The fall did not end in the yard.")
		return
	for id: StringName in [&"classroom_curtain_void", &"classroom_fall_landing"]:
		if _conversations.count(id) != 1:
			_failures.append(
				"The fall played '%s' %d time(s) (%s)." % [id, _conversations.count(id), str(_conversations)]
			)
	if _entered - entered_before != 1:
		_failures.append("The fall entered a location %d time(s), not once." % (_entered - entered_before))
	if _conversations.has(&"playground_arrival"):
		_failures.append(
			"The yard's ordinary arrival line ('the gate you came through') played after a fall."
		)
	if _flag(StoryFlags.CURTAIN_FALL_PENDING):
		_failures.append("curtain_fall_pending was not spent by the fall.")
	if not _flag(StoryFlags.CURTAIN_DRAWN):
		_failures.append("The fall forgot that the curtain was drawn.")
	for entry: StringName in [&"drew_back_curtain", &"saw_void_window", &"fell_into_playground"]:
		if not _narrative.has_entry(entry):
			_failures.append("The fall did not record '%s'." % entry)
	if String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, "")) != "objective.playground":
		_failures.append("Landing in the yard did not change the objective.")
	var marker := _room().get_node_or_null(^"SpawnPoints/FromSchool") as Node3D
	if marker == null:
		marker = _room().find_child("FromSchool", true, false) as Node3D
	if marker != null:
		var offset := _player.global_position - marker.global_position
		offset.y = 0.0
		if offset.length() > 1.5:
			_failures.append("The player landed %.1f m from FromSchool." % offset.length())
	var visual := _player.visual
	if (
		visual != null
		and (
			absf(visual.rotation_degrees.x) > 0.5
			or not visual.position.is_equal_approx(Vector3(0.0, 0.9, 0.0))
		)
	):
		_failures.append(
			(
				"The body is still falling in the yard (pitch %.1f, at %s)."
				% [visual.rotation_degrees.x, str(visual.position)]
			)
		)
	if _player.camera_rig != null and absf(_player.camera_rig.get_roll()) > 0.5:
		_failures.append(
			"The view is still rolled %.1f degrees in the yard." % _player.camera_rig.get_roll()
		)


# --- 5. the room remembers ----------------------------------------------------------


func _check_return() -> void:
	if not _host.load_location(CLASSROOM, &"FromCorridor", _player):
		_failures.append("The classroom could not be entered again.")
		return
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	await _settle(30.0, "the classroom again")
	if not _curtain().is_open() or not _void().visible:
		_failures.append("Back in the classroom the curtain is closed over the void again.")
	if not _no_staircase() or _flag(StoryFlags.REAR_DOOR_OPENED):
		_failures.append("Back in the classroom the rear door opened or a staircase appeared.")
	var curtain: Interactable = _room().find_interactable(&"curtain")
	if curtain != null and curtain.get_prompt_override() != "prompt.curtain_drawn":
		_failures.append(
			"The drawn curtain still offers to be drawn ('%s')." % curtain.get_prompt_override()
		)
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-5.9, 0.0, 2.2)))
	await _frames(4)
	_conversations.clear()
	await _activate(&"curtain")
	await _settle(40.0, "the drawn curtain")
	await _frames(20)
	if not _conversations.has(&"classroom_curtain_drawn"):
		_failures.append("The drawn curtain played %s." % str(_conversations))
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != "classroom":
		_failures.append("The drawn curtain threw the player out a second time.")


# --- helpers ------------------------------------------------------------------------


func _connect_world() -> void:
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _conversations.append(id))
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _inspections.append(id))
	_host.location_entered.connect(
		func(_location: LocationRoot, _spawn: StringName) -> void: _entered += 1
	)


## Real seconds since the last lap, into the notes (the CI step has one limit for the file).
func _lap(label: String) -> void:
	var now := Time.get_ticks_msec()
	if _lap_started == 0:
		_lap_started = _started
	_notes.append("%s %.1f s" % [label, (now - _lap_started) / 1000.0])
	_lap_started = now


func _activate(id: StringName) -> void:
	var room := _room()
	var target: Interactable = room.find_interactable(id) if room != null else null
	if target == null:
		_failures.append("No '%s' interactable to use." % id)
		return
	_interaction.set_enabled(true)
	_interaction.request_activation(target)
	await process_frame


## Advances lines until the runtime offers choices, then picks `choice_id`.
func _choose(choice_id: StringName, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while not _dialogue.has_pending_choices():
		if Time.get_ticks_msec() - started > 30000 or _over_budget():
			_failures.append("Timed out waiting for choices at %s." % label)
			return false
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	var ids := _dialogue.get_runtime().get_available_choice_ids()
	var index := ids.find(choice_id)
	if index < 0:
		_failures.append("%s offers %s, not '%s'." % [label, str(ids), choice_id])
		return false
	_dialogue.select_choice(index)
	await process_frame
	return true


func _settle(timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while (
		_dialogue.is_busy()
		or _sequence.is_beat_active()
		or _director.pending_count() > 0
		or _director.is_firing()
	):
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0) or _over_budget():
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


func _over_budget() -> bool:
	return Time.get_ticks_msec() - _started > int(BUDGET_SECONDS * 1000.0)


func _flag(flag: StringName) -> bool:
	return _game_state.get_flag(flag, false) == true


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame


## World box of every mesh under `node`; `include_hidden` measures a hidden subtree too.
func _subtree_aabb(node: Node, include_hidden: bool = false) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		if not include_hidden and not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
