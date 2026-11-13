extends SceneTree
## The biology classroom's two impossible things (docs/ART_BIBLE.md, location studies),
## played through the real main scene, director and dialogue.
##
## Claims under test:
##
## 1. **Placed, and decoration only.** The back window (Window1) has the curtain drawn over
##    it; the front window (Window0) stays ordinary and shows the washing. The rear door is
##    hung on the back wall between the west wall and the back board, and fades with that
##    wall. The staircase hangs over the front of the teacher's desk, out of reach, touching
##    nothing. None of it collides.
## 2. **The lesson is not over.** Before N lets the class go the curtain is only looked at
##    and the rear door does not give: nothing changes, no flag is written.
## 3. **The rear door.** Once the class is dismissed it swings open on plaster, and the
##    staircase is in the room. The camera goes to it and comes back. The staircase thins
##    out while it would hide the player, and is exactly its authored self again after.
## 4. **The curtain.** Leaving it drawn changes nothing. Drawing it aside (after an
##    orientation check that is visible and recorded) shows the void instead of glass and
##    a view, and the protagonist falls: the next room is the yard, at `FromSchool`, with
##    the landing line instead of the yard's ordinary arrival; the provisional
##    `curtain_fall_pending` flag is spent; the body is upright and the view level.
## 5. **The room remembers.** Walking back into the classroom finds the curtain open on the
##    void, the rear door open and the staircase there, and the curtain does not throw the
##    player out a second time.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const TIME_SCALE := 4.0
const BUDGET_SECONDS := 220.0
## The shared window panorama. Only its last third (s 3.0..4.5 m, window 0) has the washing
## painted into it (art/classroom/paint_classroom_textures.py, `window_view`).
const PANORAMA := "res://assets/materials/classroom/textures/window_view.png"
const WASHING_OFFSET := 0.6667
const VOID_MATERIAL := "res://assets/materials/classroom/void_opening.tres"
const CHECK_KEY := "classroom_curtain/cc_edges_check"

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


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "classroom_anomaly_test.gd")
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
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _conversations.append(id))
	_dialogue.inspection_presented.connect(func(id: StringName) -> void: _inspections.append(id))
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
	Harness.stage = "staircase see-through"
	await _check_see_through()
	Harness.stage = "curtain left drawn"
	await _check_curtain_left()
	Harness.stage = "curtain failure recovery"
	await _check_curtain_failure_recovery()
	Harness.stage = "curtain and fall"
	await _check_fall()
	Harness.stage = "the room remembers"
	await _check_return()

	Engine.time_scale = 1.0
	print("::notice title=classroom anomalies::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		(
			"the curtained window opens on nothing and drops the player into the yard; the "
			+ "rear door puts an unsupported staircase over the teacher's desk; both are "
			+ "decoration, both are remembered."
		)
	)


# --- 1. placement -------------------------------------------------------------------


func _room() -> LocationRoot:
	return _host.get_current()


func _anomalies() -> Node:
	return _room().get_node_or_null(^"Anomalies") if _room() != null else null


func _curtain() -> WindowCurtain:
	return _room().get_node_or_null(^"Anomalies/BackCurtain") as WindowCurtain


func _door() -> SwingDoor:
	return _room().get_node_or_null(^"WallSouthLeft/RearDoor") as SwingDoor


func _stair() -> SuspendedStair:
	return _room().get_node_or_null(^"Anomalies/Staircase") as SuspendedStair


func _void() -> MeshInstance3D:
	return _room().get_node_or_null(^"Anomalies/VoidOpening") as MeshInstance3D


func _check_placement() -> void:
	var curtain := _curtain()
	var door := _door()
	var stair := _stair()
	var void_mesh := _void()
	if (
		_anomalies() == null
		or curtain == null
		or door == null
		or stair == null
		or void_mesh == null
	):
		_failures.append(
			"The classroom lost one of Anomalies, its curtain, void, staircase or rear door."
		)
		return
	for scope: Node in [_anomalies(), door]:
		for node in scope.find_children("*", "CollisionObject3D", true, false):
			_failures.append(
				"'%s' collides; the anomalies are decoration." % _room().get_path_to(node)
			)

	# The ordinary window shows the washing; the curtained one is closed over Window1.
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
	if curtain.is_open():
		_failures.append("The back-window curtain starts open.")
	var fabric := curtain.get_fabric_aabb()
	_notes.append("curtain %s" % str(fabric))
	if (
		fabric.position.z > 0.55
		or fabric.end.z < 2.05
		or fabric.position.y > 1.15
		or fabric.end.y < 2.38
	):
		_failures.append(
			(
				"The closed curtain %s does not cover the back window (z 0.5-2.1, y 1.1-2.4)."
				% str(fabric)
			)
		)
	if fabric.position.x < -4.5 or fabric.end.x > -4.2:
		_failures.append("The curtain %s is not hung against the west wall." % str(fabric))
	if void_mesh.visible or not (_room().get_node(^"WindowGlass1") as Node3D).visible:
		_failures.append("The back window starts as the void instead of glass.")
	if (
		void_mesh.material_override == null
		or void_mesh.material_override.resource_path != VOID_MATERIAL
	):
		_failures.append("The void opening does not draw void_opening.tres.")

	# The rear door: on the back wall, fading with it, between the west wall and the board.
	if door.get_parent() != _room().get_node(^"WallSouthLeft"):
		_failures.append(
			"The rear door is not hung on WallSouthLeft, so it would not fade with it."
		)
	var door_box := _subtree_aabb(door)
	_notes.append("door %s" % str(door_box))
	if door_box.position.x < -4.5 or door_box.end.x > -3.46:
		_failures.append(
			"The rear door %s overlaps the west wall or the back board." % str(door_box)
		)
	if door_box.position.z < 3.3 or door_box.end.z > 3.6 or door_box.end.y > 2.4:
		_failures.append("The rear door %s is not set into the back wall." % str(door_box))
	if absf(door.get_angle()) > 0.5 or door.is_open():
		_failures.append("The rear door starts open.")

	# The staircase: hidden, and once shown, out of reach over the front of the desk.
	if stair.visible or stair.is_revealed():
		_failures.append("The staircase is in the room before the rear door was opened.")
	var stair_box := _subtree_aabb(stair, true)
	_notes.append("stair %s" % str(stair_box))
	if stair_box.position.y < 1.8:
		_failures.append(
			"The staircase comes down to %.2f m; it should stop in the air." % stair_box.position.y
		)
	if stair_box.end.y > 3.25:
		_failures.append("The staircase rises above the walls (%.2f m)." % stair_box.end.y)
	if stair_box.position.x < 1.05 or stair_box.end.x > 2.95:
		_failures.append("The staircase %s is not over the teacher's desk." % str(stair_box))
	if stair_box.position.z < -2.42 or stair_box.position.z > -1.6:
		_failures.append(
			"The staircase %s does not end just in front of the desk." % str(stair_box)
		)
	for id: StringName in [&"curtain", &"rear_door"]:
		var interactable := _room().find_interactable(id) as StagedInteractable
		if interactable == null or not interactable.is_staged():
			_failures.append("The '%s' interactable is missing or has no stage handler." % id)


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
	if _curtain().is_open() or _door().is_open() or _stair().visible:
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
	_player.teleport(Transform3D(Basis(Vector3.UP, PI), Vector3(-3.9, 0.0, 2.3)))
	await _frames(4)
	_conversations.clear()
	var rig := _player.camera_rig
	var framed := false
	await _activate(&"rear_door")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 40000:
		if rig != null and rig.get_frame_weight() > 0.9:
			framed = true
		if _dialogue.is_busy():
			_dialogue.advance_presentation()
		if (
			_flag(StoryFlags.REAR_DOOR_OPENED)
			and not _dialogue.is_busy()
			and not _sequence.is_beat_active()
		):
			break
		await process_frame
	await _settle(30.0, "the rear door beat")
	if not _flag(StoryFlags.REAR_DOOR_OPENED):
		_failures.append("Opening the rear door after the lesson did not record it.")
	if not _door().is_open() or absf(_door().get_angle() - _door().open_degrees) > 1.0:
		_failures.append("The rear door is at %.1f degrees, not open." % _door().get_angle())
	if not _stair().visible or not _stair().is_revealed():
		_failures.append("The staircase did not appear when the rear door opened.")
	if not _conversations.has(&"classroom_rear_door"):
		_failures.append("The rear door beat did not play its lines.")
	if not _narrative.has_entry(&"saw_suspended_stair"):
		_failures.append("The staircase was not recorded.")
	if not framed:
		_failures.append("The camera never went to the staircase.")
	if rig != null and rig.get_frame_weight() > 0.01:
		_failures.append(
			"The camera did not come back to the player (weight %.2f)." % rig.get_frame_weight()
		)
	var treads := _stair().get_treads()
	for tread in treads:
		if not tread.visible:
			_failures.append("Tread '%s' never arrived." % tread.name)
			break
	# The leaf swung into the room; nothing behind it but the wall it is set into.
	var hinge := _door().get_hinge()
	if hinge == null or hinge.get_child_count() < 5:
		_failures.append("The rear door's leaf did not move as one piece under its hinge.")
	_inspections.clear()
	await _activate(&"rear_door")
	await _settle(30.0, "the open rear door")
	if not _inspections.has(&"classroom_rear_door_open"):
		_failures.append("The open rear door does not describe what it shows now.")


# --- the staircase gets out of the way ----------------------------------------------


func _check_see_through() -> void:
	var stair := _stair()
	var authored: Dictionary = {}
	for piece in stair.get_pieces():
		authored[piece] = piece.material_override
	var hiding_spot := Vector3.INF
	var x := 0.0
	while x <= 3.5 and hiding_spot == Vector3.INF:
		var z := -2.3
		while z <= 0.0:
			_player.teleport(Transform3D(Basis(), Vector3(x, 0.0, z)))
			if stair.is_hiding(_player):
				hiding_spot = Vector3(x, 0.0, z)
				break
			z += 0.25
		x += 0.25
	if hiding_spot == Vector3.INF:
		_notes.append("no standing spot is behind the staircase")
	else:
		await _frames(30)
		if stair.get_opacity() > stair.see_through_alpha + 0.05:
			_failures.append(
				(
					"Behind the staircase at %s it stayed at %.2f opacity."
					% [str(hiding_spot), stair.get_opacity()]
				)
			)
		_notes.append(
			"behind the stair at %s: opacity %.2f" % [str(hiding_spot), stair.get_opacity()]
		)
	_player.teleport(Transform3D(Basis(), Vector3(0.0, 0.0, 0.85)))
	await _frames(40)
	if stair.get_opacity() < 0.999:
		_failures.append(
			"The staircase stayed thinned (%.2f) after the player left." % stair.get_opacity()
		)
	for piece: MeshInstance3D in authored:
		if piece.material_override != authored[piece]:
			_failures.append("'%s' did not get its authored material back." % piece.name)
			break


# --- 4. the curtain -----------------------------------------------------------------


func _check_curtain_left() -> void:
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-3.6, 0.0, 1.3)))
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


func _check_curtain_failure_recovery() -> void:
	var anomalies := _anomalies() as ClassroomAnomalies
	if anomalies == null:
		_failures.append("ClassroomAnomalies is unavailable for the failure-recovery check.")
		return
	_game_state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, true)
	_game_state.set_flag(StoryFlags.CURTAIN_DRAWN, false)
	await anomalies.draw_curtain(false)
	if _flag(StoryFlags.CURTAIN_DRAWN):
		_failures.append("Drawing the curtain committed CURTAIN_DRAWN before a destination loaded.")
	if not _curtain().is_open() or not _void().visible:
		_failures.append("The curtain failure fixture did not reach its open/void state.")
	anomalies.reset_curtain_after_failed_transition()
	if _curtain().is_open() or _void().visible:
		_failures.append("A refused fall did not restore the closed curtain and ordinary window.")
	if not _flag(StoryFlags.CURTAIN_FALL_PENDING) or _flag(StoryFlags.CURTAIN_DRAWN):
		_failures.append("A refused fall consumed pending state or committed the drawn state.")
	var curtain := _room().find_interactable(&"curtain")
	if curtain == null or curtain.get_prompt_override() != "prompt.curtain_retry":
		_failures.append("A refused fall did not leave an explicit curtain retry prompt.")


func _check_fall() -> void:
	var seed_value := -1
	for candidate in 4000:
		if CheckResolver.new(candidate).dice_total_for(CHECK_KEY) >= 12:
			seed_value = candidate
			break
	if seed_value >= 0:
		_dialogue.set_check_resolver(CheckResolver.new(seed_value))
	_conversations.clear()
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
			and not (room.get_node(^"WindowGlass1") as Node3D).visible
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
		_failures.append("Drawing the curtain never showed the void in place of the window.")
	if String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) != "playground":
		_failures.append("The fall did not end in the yard.")
		return
	for id: StringName in [&"classroom_curtain_void", &"classroom_fall_landing"]:
		if not _conversations.has(id):
			_failures.append("The fall did not play '%s' (%s)." % [id, str(_conversations)])
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
	if (
		not _curtain().is_open()
		or not _void().visible
		or (_room().get_node(^"WindowGlass1") as Node3D).visible
	):
		_failures.append(
			"Back in the classroom the curtain is closed again or the window has glass."
		)
	if not _door().is_open() or not _stair().visible:
		_failures.append("Back in the classroom the rear door is shut or the staircase is gone.")
	var curtain: Interactable = _room().find_interactable(&"curtain")
	if curtain != null and curtain.get_prompt_override() != "prompt.curtain_drawn":
		_failures.append(
			"The drawn curtain still offers to be drawn ('%s')." % curtain.get_prompt_override()
		)
	_player.teleport(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-3.6, 0.0, 1.3)))
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
