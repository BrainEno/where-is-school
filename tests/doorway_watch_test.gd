extends SceneTree
## #174: when the classroom door refuses the player, the person its text says is watching
## them really turns and watches - and stops again.
##
## The window is set to the game's 1600x900 (a headless run starts at 64x64): the
## framing claim is about what the player sees.
##
## The real main scene, with the prologue's beats off (`autostart = false`) and Q's first
## talk already behind the player (`met_q`), so the door is blocked (`class_dismissed` is
## not set) and nothing else moves Q. Q is put where the opening leaves him (at
## `QOpeningTalk`, facing the player's seat). The door is tried through the same dispatcher
## a key press or click uses (`InteractionController.request_activation`), which routes it
## through `OpeningSequence` and `LocationFlow` exactly as in play.
##
## The claims, in the order the issue lists them:
##
## 1. **Approach.** Walking up to the door turns nobody: the watch begins with the text.
## 2. **Trigger.** In the frame the blocked text appears, the door's watcher - Q, the one
##    `blocked_watcher_ids` names - starts watching, and no other actor does (N is not in
##    the room yet; the seated student is scenery). Within 0.35 s the head has turned most
##    of the way, the skeleton itself reports the turn (bones moved, not just a number),
##    and the face points at the player's eyes - not 180° away. Q stays exactly where he
##    stood. Q is outside the game camera's frame at the door, so the view glides to show
##    both of them while the text is up.
## 3. **Follow.** After the text, with the player still in the doorway, the gaze follows
##    them to a different spot, and the view is back on the player.
## 4. **Leave.** Walking out of the doorway ends the watch: the head eases back to the
##    animation and the body is at the yaw it had, in the same place.
## 5. **Body.** A watch the neck cannot make (the player behind Q) turns the body by the
##    remainder only, and gives it back afterwards; a beat that turns the actor in the
##    meantime keeps its own facing.
## 6. **Story.** A beat taking the room, or the door opening, ends a watch at once.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
## Two places in the doorway, approached from different sides, and one well out of it.
const DOORWAY_A := Vector3(4.6, 0.0, -2.2)
const DOORWAY_B := Vector3(5.4, 0.0, -4.6)
const AWAY := Vector3(0.5, 0.0, -0.9)
const APPROACH := Vector3(3.2, 0.0, -1.2)
## The player's eyes, as `ExitWatch` aims at them.
const EYE := 1.6

var _failures: Array[String] = []
var _notes: Array[String] = []
var _world: Node = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _room: LocationRoot = null
var _door: LocationExit = null
var _q: NpcActor = null
var _watch: ExitWatch = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "doorway_watch_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	var state: Node = autoloads["game_state"]
	if state == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")
	# Q's first talk is over and the lesson has not been dismissed: the door is blocked.
	state.set_flag(StoryFlags.MET_Q, true)
	state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")

	# The game's view, not the headless default: whether a face is on screen depends on it.
	root.size = Vector2i(1600, 900)
	_world = (load(MAIN) as PackedScene).instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_world)
	await process_frame
	await process_frame
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_player = _world.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	_room = (_world.get_node(^"LocationHost") as LocationHost).get_current()
	var voices := _world.get_node_or_null(^"InnerVoiceDirector")
	if voices != null:
		voices.set_process(false)
	_sequence.allow_player_control()
	_sequence.sync_player_locks()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	_watch = _world.get_node_or_null(^"OpeningSequence/ExitWatch") as ExitWatch
	if _room == null or _watch == null:
		Harness.finish(self, ["The classroom or the director's ExitWatch is missing."], "")
		return
	_door = _room.find_interactable(&"classroom_door") as LocationExit
	_q = _room.find_actor(&"q")
	if _door == null or _q == null:
		Harness.finish(self, ["The classroom door or Q is missing."], "")
		return
	if _door.is_open():
		_failures.append("The door is open before the class is dismissed; nothing to test.")
	if _door.blocked_watcher_ids.size() != 1 or _door.blocked_watcher_ids[0] != &"q":
		_failures.append("The classroom door names %s as its watchers, not Q alone." % str(_door.blocked_watcher_ids))
	# Where the opening leaves Q: at his talk marker, turned to the player's seat.
	var talk := _room.find_child("QOpeningTalk", true, false) as Marker3D
	var seat := _room.find_child("PlayerStart", true, false) as Marker3D
	if talk != null and seat != null:
		_q.global_position = talk.global_position
		_q.face_towards(seat.global_position)
	await _seconds(0.3)

	await _check_approach()
	await _check_trigger()
	await _check_follow()
	await _check_leave()
	await _check_body_turn()
	await _check_story_release()

	print("::notice title=doorway watch::%s" % " | ".join(_notes))
	_world.queue_free()
	await process_frame
	Harness.finish(
		self, _failures,
		"the blocked door turns Q, and only Q, to watch the player, follows them, and lets go."
	)


func _check_approach() -> void:
	var yaw := _q.rotation.y
	_stand(APPROACH)
	await _seconds(0.4)
	_stand(DOORWAY_A)
	await _seconds(0.4)
	if _q.is_watching() or _watch.is_watching():
		_failures.append("Approach: Q is watching before the door was tried.")
	if absf(angle_difference(_q.rotation.y, yaw)) > 0.0001:
		_failures.append("Approach: Q turned before the door was tried.")


func _check_trigger() -> void:
	var others := _other_actor_poses()
	var place := _q.global_position
	var yaw := _q.rotation.y
	var camera := _player.camera_rig.camera
	# What the player sees is the game's 1600x900 view; a headless default (64x64) would
	# judge the framing of a square window nobody plays in.
	if camera.get_viewport().get_visible_rect().size != Vector2(1600.0, 900.0):
		_failures.append("Trigger: the view is %s, not the game's 1600x900." % str(camera.get_viewport().get_visible_rect().size))
	var q_seen_before := camera.is_position_in_frustum(_q.global_position + Vector3.UP * EYE)
	_interaction.request_activation(_door)
	await process_frame
	if not _dialogue.is_busy():
		_failures.append("Trigger: trying the door did not present its blocked text.")
	if not _q.is_watching():
		_failures.append("Trigger: Q was not watching in the frame the blocked text appeared.")
	var watchers := _watch.get_watchers()
	if watchers.size() != 1 or watchers[0] != _q:
		_failures.append("Trigger: the door's watchers are %s, not Q alone." % str(watchers))
	await _seconds(0.35)
	var gaze := _q.get_gaze()
	if gaze == null:
		_failures.append("Trigger: Q has no head-turn modifier (no skeleton found).")
		return
	var wanted := clampf(gaze.get_desired_yaw_degrees(), -gaze.reach_degrees, gaze.reach_degrees)
	var applied := gaze.get_applied_yaw_degrees()
	_notes.append("trigger: wanted %.1f°, applied %.1f° after 0.35 s, head %.1f°, bones %s" % [
		wanted, applied, gaze.get_measured_head_turn_degrees(), ",".join(gaze.get_bone_names())
	])
	if absf(wanted) < 5.0:
		_failures.append("Trigger: Q already faced the player (%.1f°); the turn is not visible." % wanted)
	if absf(applied) < absf(wanted) * 0.8 or signf(applied) != signf(wanted):
		_failures.append("Trigger: 0.35 s after the text Q had turned %.1f° of %.1f°." % [applied, wanted])
	_check_head_moved(gaze, "Trigger")
	_check_face(gaze, "Trigger")
	if _q.global_position != place:
		_failures.append("Trigger: Q moved from %s to %s." % [str(place), str(_q.global_position)])
	if absf(angle_difference(_q.rotation.y, yaw)) > 0.0001:
		_failures.append("Trigger: Q's body turned for an angle the head can make.")
	var after := _other_actor_poses()
	for key: String in others:
		if not after.has(key) or not (after[key] as Transform3D).is_equal_approx(others[key]):
			_failures.append("Trigger: '%s' moved or turned; only the door's watcher may react." % key)
	for actor in get_nodes_in_group(&"npc_actor"):
		if actor != _q and (actor as NpcActor).is_watching():
			_failures.append("Trigger: '%s' is watching too." % (actor as NpcActor).npc_id)
	# The picture shows it: both faces are in the game camera's view while the text is up.
	await _seconds(0.2)
	var q_seen := camera.is_position_in_frustum(_q.global_position + Vector3.UP * EYE)
	var player_seen := camera.is_position_in_frustum(_player.global_position + Vector3.UP * EYE)
	_notes.append("camera %s: Q in view before %s, during %s; player in view %s; moved %.1f of the way" % [
		str(camera.get_viewport().get_visible_rect().size), q_seen_before, q_seen, player_seen,
		_watch.get_frame_share()
	])
	if not q_seen or not player_seen:
		_failures.append("Trigger: the game camera does not show both Q (%s) and the player (%s)." % [q_seen, player_seen])


func _check_follow() -> void:
	await _close_text()
	if not _q.is_watching():
		_failures.append("Follow: the watch ended with the text while the player still stood in the doorway.")
		return
	await _seconds(0.45)
	if _player.camera_rig.get_frame_weight() > 0.001:
		_failures.append("Follow: the view did not go back to the player after the text.")
	var gaze := _q.get_gaze()
	if gaze == null:
		_failures.append("Follow: Q has no head-turn modifier.")
		return
	var first := gaze.get_applied_yaw_degrees()
	_stand(DOORWAY_B)
	await _seconds(0.5)
	if not _q.is_watching():
		_failures.append("Follow: moving within the doorway (%.2f m zone) ended the watch." % _watch.get_zone_radius())
		return
	var wanted := clampf(gaze.get_desired_yaw_degrees(), -gaze.reach_degrees, gaze.reach_degrees)
	var second := gaze.get_applied_yaw_degrees()
	_notes.append("follow: %.1f° -> %.1f° (wanted %.1f°)" % [first, second, wanted])
	if absf(second - wanted) > 2.0:
		_failures.append("Follow: the gaze is %.1f°, the player is at %.1f°." % [second, wanted])
	if absf(second - first) < 3.0:
		_failures.append("Follow: the gaze did not move with the player (%.1f° -> %.1f°)." % [first, second])
	_check_face(gaze, "Follow")


func _check_leave() -> void:
	var place := _q.global_position
	var yaw := _q.rotation.y
	_stand(AWAY)
	await process_frame
	await process_frame
	if _q.is_watching() or _watch.is_watching():
		_failures.append("Leave: Q kept watching after the player walked out of the doorway.")
	await _seconds(0.5)
	var gaze := _q.get_gaze()
	if gaze != null and (gaze.get_weight() > 0.0 or not is_zero_approx(gaze.get_applied_yaw_degrees())):
		_failures.append("Leave: Q's head is still turned (%.1f°)." % gaze.get_applied_yaw_degrees())
	if _q.global_position != place or absf(angle_difference(_q.rotation.y, yaw)) > 0.0001:
		_failures.append("Leave: Q is not where and how he stood before the door was tried.")


func _check_body_turn() -> void:
	# Q turned away from the doorway: the player is behind him, past the neck's reach.
	_stand(DOORWAY_A)
	_q.face_towards(_q.global_position + Vector3(-1.0, 0.0, 0.4))
	var rest := _q.rotation.y
	await _seconds(0.2)
	_q.watch(_player, EYE)
	await _seconds(1.4)
	var gaze := _q.get_gaze()
	if gaze == null:
		_failures.append("Body: Q has no head-turn modifier.")
		_q.stop_watching()
		return
	var body := rad_to_deg(angle_difference(rest, _q.rotation.y))
	_notes.append("body: turned %.1f°, head %.1f°" % [body, gaze.get_applied_yaw_degrees()])
	if absf(body) < 10.0:
		_failures.append("Body: the player is behind Q and the body did not turn (%.1f°)." % body)
	if absf(absf(gaze.get_applied_yaw_degrees()) - gaze.reach_degrees) > 2.0:
		_failures.append("Body: the head is not at its reach while the body helps (%.1f°)." % gaze.get_applied_yaw_degrees())
	_check_face(gaze, "Body")
	_q.stop_watching()
	await _seconds(1.6)
	if absf(angle_difference(_q.rotation.y, rest)) > 0.003:
		_failures.append("Body: the body did not return to its facing (%.2f° off)." % rad_to_deg(angle_difference(_q.rotation.y, rest)))
	# A beat turning the actor during a watch keeps its facing afterwards.
	_q.watch(_player, EYE)
	await _seconds(0.6)
	var seat := _room.find_child("PlayerStart", true, false) as Marker3D
	_q.face_towards(seat.global_position)
	var beat_yaw := _q.rotation.y
	_q.stop_watching()
	await _seconds(1.0)
	if absf(angle_difference(_q.rotation.y, beat_yaw)) > 0.0001:
		_failures.append("Body: letting go undid the facing a beat gave Q in the meantime.")


func _check_story_release() -> void:
	_stand(DOORWAY_A)
	await _seconds(0.3)
	# A beat takes the room once the text is closed: the story owns Q again.
	_interaction.request_activation(_door)
	await process_frame
	await _close_text()
	if not _q.is_watching():
		_failures.append("Story: the second try did not start a watch.")
	await _sequence.begin_beat()
	await process_frame
	await process_frame
	if _q.is_watching():
		_failures.append("Story: Q kept watching after a beat took the room.")
	_sequence.end_beat()
	await _seconds(0.3)
	# The door opening ends a watch too.
	_interaction.request_activation(_door)
	await process_frame
	if not _q.is_watching():
		_failures.append("Story: the third try did not start a watch.")
	var state := root.get_node(^"GameState")
	state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	await process_frame
	await process_frame
	if _q.is_watching():
		_failures.append("Story: Q kept watching after the door opened.")
	await _close_text()


## The head's pose moved by the turn the gaze reports.
func _check_head_moved(gaze: NpcGaze, label: String) -> void:
	var applied := gaze.get_applied_yaw_degrees()
	var measured := gaze.get_measured_head_turn_degrees()
	if absf(measured - applied) > 1.5:
		_failures.append("%s: the head bone turned %.1f°, the gaze says %.1f°." % [label, measured, applied])


## The face (the body's facing turned by the head) points at the player's eyes.
func _check_face(gaze: NpcGaze, label: String) -> void:
	var face := _q.get_facing_direction().rotated(Vector3.UP, deg_to_rad(gaze.get_applied_yaw_degrees()))
	var to_player := _player.global_position + Vector3.UP * EYE - _q.global_position
	to_player.y = 0.0
	var error := rad_to_deg(face.angle_to(to_player.normalized()))
	if error > 6.0:
		_failures.append("%s: Q looks %.1f° away from the player." % [label, error])


func _other_actor_poses() -> Dictionary:
	var poses := {}
	# The people of this room (the main scene's companion stand-in is hidden here).
	for actor in get_nodes_in_group(&"npc_actor"):
		if actor != _q and _room.is_ancestor_of(actor):
			poses[str((actor as Node).get_path())] = (actor as Node3D).global_transform
	var student := _room.find_child("SeatedStudent", true, false) as Node3D
	if student != null:
		poses[str(student.get_path())] = student.global_transform
	return poses


func _stand(at: Vector3) -> void:
	var facing := (_door.global_position - at)
	facing.y = 0.0
	_player.teleport(Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP), at))


func _close_text() -> void:
	var waited := 0
	while _dialogue.is_busy() and waited < 600:
		_dialogue.advance_presentation()
		await process_frame
		waited += 1
	if _dialogue.is_busy():
		_failures.append("The blocked text never closed.")


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout
