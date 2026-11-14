extends SceneTree
## #166: the substitute teacher N stays in the classroom once the story has brought her in -
## through her own conversation, the pause menu, leaving and re-entering the room, and a
## save being continued - and is still hidden before that.
##
## Every location is a fresh instance of its scene (`LocationHost` frees the room it leaves
## and instantiates the one it enters), and the classroom scene authors N hidden at her
## off-stage spot, because the opening walks her in. So N on screen is only ever the
## result of the story having run, and a room built again has to be told so.
##
## The real main scene, driven through the same calls the UI makes (lines are continued,
## doors used through `InteractionController.request_activation`):
##
## 1. **Before.** With the bell rung and the substitute beat pending, N is hidden - at
##    boot and after a pause - and there is exactly one N.
## 2. **Entrance.** The beat shows her before `n_arrived` (she is seen walking in), and she
##    ends at the end of `NEntryPath` - the lectern's TeacherStand, which
##    `classroom_visual_slice_test` holds to the current lectern - facing the room.
## 3. **Her conversation.** While `n_class` is on screen and after it closes, she is still
##    there, in the same place.
## 4. **Pause.** Pausing and resuming the tree changes nothing about her.
## 5. **Leaving.** Taking the door frees that classroom and its N (the room is unloaded,
##    not hidden).
## 6. **Re-entering.** Coming back from the walkway builds the room again: one N, visible,
##    at the stand, facing the room, still - twice in a row.
## 7. **No second entrance.** Running the substitute beat again, and the room being
##    re-announced, neither moves her nor makes another N.
## 8. **The rest of the slice.** The door is open, Q comes along, and the walkway leads on
##    to the street.
## 9. **Continue.** A real save written in the classroom after the class, loaded into a
##    fresh world: N is at the stand from the first frame.
## 10. **Arrived, not dismissed.** A run that stopped after N walked in but before she let
##    the class go: N is at the stand at boot, the beat does not walk her in again, and her
##    conversation still dismisses the class.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const TIME_SCALE := 4.0
## How close to the stand counts as "at" it, and how closely she must face the room.
const AT_STAND_METRES := 0.05
const FACING_DOT := 0.97

var _failures: Array[String] = []
var _notes: Array[String] = []
var _state: Node = null
var _world: Node = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "n_presence_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	if _state == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	Harness.ensure_autoload(self, "Session", SESSION_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")
	Engine.time_scale = TIME_SCALE

	await _check_play_through()
	await _check_continue()
	await _check_arrived_not_dismissed()

	Engine.time_scale = 1.0
	paused = false
	await _free_world()
	# The save file is shared by every check in the job; leave none behind.
	Harness.clear_session_state(self)
	print("::notice title=N presence::%s" % " | ".join(_notes))
	Harness.finish(
		self, _failures,
		"N stays at the lectern once she has come in: through her talk, a pause, re-entry and a continued save."
	)


# --- Cases ------------------------------------------------------------------


## 1-8: one run from the bell to the street, with the room left and entered twice.
func _check_play_through() -> void:
	Harness.clear_session_state(self)
	_set_flags_before_substitute()
	await _boot(false)
	if _world == null:
		return
	if _sequence.next_step() != &"substitute":
		_failures.append("The fixture is at step '%s', not the substitute beat." % _sequence.next_step())
		return
	var room := _host.get_current()

	# 1. Before the entrance.
	var n := _find_n()
	if n == null:
		_failures.append("Before: the classroom has no N.")
		return
	_expect(_count_n() == 1, "Before: %d Ns in the tree, not one." % _count_n())
	_expect(not n.visible, "Before: N is visible before the substitute beat has run.")
	paused = true
	await _frames(5)
	paused = false
	await _seconds(0.5)
	_expect(not n.visible, "Before: N became visible after a pause, with the beat not run.")

	# 2. The entrance.
	var first_n_id := n.get_instance_id()
	_sequence.start()
	var seen_walking := await _pump_until(
		func() -> bool: return n.visible, 30.0, "N to appear"
	)
	if seen_walking:
		_expect(
			not bool(_state.get_flag(StoryFlags.N_ARRIVED, false)),
			"Entrance: N was not seen until n_arrived; she should be seen walking in."
		)
		_expect(
			_distance_to_stand(n) > 0.5,
			"Entrance: N first appeared %.2f m from the stand - not at the door." % _distance_to_stand(n)
		)
	await _pump_until(
		func() -> bool: return bool(_state.get_flag(StoryFlags.N_ARRIVED, false)),
		60.0, "n_arrived"
	)
	_expect_at_stand(n, "Entrance")
	var in_talk := await _pump_until(
		func() -> bool: return _dialogue.is_busy(), 20.0, "N's conversation to open", false
	)
	if in_talk:
		_expect_at_stand(n, "During her conversation")

	# 3. After her conversation.
	await _pump_until(
		func() -> bool: return bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false)),
		90.0, "the class to be dismissed"
	)
	await _settle(60.0, "N's conversation to close")
	await _seconds(0.5)
	_expect_at_stand(n, "After her conversation")
	_expect(_count_n() == 1, "After her conversation: %d Ns." % _count_n())

	# 4. Pause.
	paused = true
	await _frames(10)
	paused = false
	await _seconds(0.3)
	_expect_at_stand(n, "After a pause")

	# 5 and 6: leave and come back, twice.
	for visit in [1, 2]:
		var label := "Re-entry %d" % visit
		var old_room := room
		var old_n := n
		if not await _use_exit(&"classroom_door", &"corridor", label):
			return
		await _frames(3)
		_expect(
			not is_instance_valid(old_room) and not is_instance_valid(old_n),
			"%s: the classroom (and its N) was not unloaded when the player left." % label
		)
		_expect(_count_n() == 0, "%s: %d Ns are left in the tree on the walkway." % [label, _count_n()])
		if not await _use_exit(&"back_to_classroom", &"classroom", label):
			return
		room = _host.get_current()
		n = _find_n()
		if n == null:
			_failures.append("%s: the classroom has no N." % label)
			return
		_expect(n.get_instance_id() != first_n_id, "%s: the classroom was not built again." % label)
		_expect(_count_n() == 1, "%s: %d Ns in the tree, not one." % [label, _count_n()])
		_expect_at_stand(n, label)
		await _seconds(1.0)
		_expect_at_stand(n, "%s, a second later" % label)
		if visit == 1:
			_notes.append("re-entry: N visible %s at %s, %.3f m from the stand" % [
				str(n.visible), str(n.global_position), _distance_to_stand(n)
			])

	# 7. No second entrance.
	var where := n.global_position
	await _sequence.call("_beat_substitute")
	_host.location_entered.emit(room, _host.get_current_spawn())
	await _seconds(0.5)
	_expect(_count_n() == 1, "Repeat: %d Ns after the beat ran again." % _count_n())
	_expect(
		n.global_position.distance_to(where) < 0.001,
		"Repeat: N moved %.3f m when the beat ran again." % n.global_position.distance_to(where)
	)
	_expect_at_stand(n, "Repeat")

	# 8. The rest of the slice.
	var door := room.find_interactable(&"classroom_door") as LocationExit
	_expect(door != null and door.is_open(), "Flow: the classroom door is not open after the class.")
	if not await _use_exit(&"classroom_door", &"corridor", "Flow"):
		return
	var companion := _world.get_node_or_null(^"Companion") as CompanionController
	_expect(companion == null or companion.is_joined(), "Flow: Q did not come along out of the classroom.")
	if not await _use_exit(&"school_gate", &"street", "Flow"):
		return
	_expect(_count_n() == 0, "Flow: an N followed the player into the street.")


## 9: a save written in the classroom after the class, continued in a fresh world.
func _check_continue() -> void:
	if _world == null:
		return
	# A world standing in the classroom after the class, saved the way the director saves.
	Harness.clear_session_state(self)
	_set_flags_before_substitute()
	for flag: StringName in [StoryFlags.N_ARRIVED, StoryFlags.CLASS_DISMISSED]:
		_state.set_flag(flag, true)
	await _boot(false)
	if _world == null:
		return
	await _seconds(0.3)
	var save := root.get_node_or_null(^"Save")
	if save == null:
		_failures.append("Continue: there is no Save autoload.")
		return
	var result: Dictionary = save.save_game()
	if result.get("ok", false) != true:
		_failures.append("Continue: the save was not written: %s" % str(result))
		return
	await _free_world()
	_state.clear()
	var narrative := root.get_node_or_null(^"NarrativeState")
	if narrative != null:
		narrative.clear()
	await _boot(true)
	if _world == null:
		return
	_expect(
		bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false)),
		"Continue: the save did not bring class_dismissed back."
	)
	var n := _find_n()
	if n == null:
		_failures.append("Continue: the classroom has no N.")
		return
	_expect(_count_n() == 1, "Continue: %d Ns." % _count_n())
	_expect_at_stand(n, "Continue")
	await _seconds(1.0)
	_expect_at_stand(n, "Continue, a second later")


## 10: N walked in, the class not yet dismissed (a run that stopped in between).
func _check_arrived_not_dismissed() -> void:
	Harness.clear_session_state(self)
	_set_flags_before_substitute()
	_state.set_flag(StoryFlags.N_ARRIVED, true)
	await _boot(false)
	if _world == null:
		return
	var n := _find_n()
	if n == null:
		_failures.append("Arrived: the classroom has no N.")
		return
	_expect_at_stand(n, "Arrived, at boot")
	var farthest := [0.0]
	var watch_n := n
	_sequence.start()
	await _pump_until(
		func() -> bool:
			if is_instance_valid(watch_n):
				farthest[0] = maxf(farthest[0], _distance_to_stand(watch_n))
			return bool(_state.get_flag(StoryFlags.CLASS_DISMISSED, false)),
		60.0, "the arrived N to dismiss the class"
	)
	await _settle(30.0, "the arrived N's conversation to close")
	_expect(
		farthest[0] < AT_STAND_METRES,
		"Arrived: the beat walked N in again (she was %.2f m from the stand)." % farthest[0]
	)
	_expect(_count_n() == 1, "Arrived: %d Ns." % _count_n())
	_expect_at_stand(n, "Arrived, after her conversation")


# --- Helpers ----------------------------------------------------------------


func _set_flags_before_substitute() -> void:
	for flag: StringName in [
		StoryFlags.MET_Q, StoryFlags.Q_FIRST_TALK_DONE, StoryFlags.TEXTBOOK_MISSING,
		StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG,
	]:
		_state.set_flag(flag, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.bell")


## Boots the real main scene. `restore` keeps the save file so the director continues it.
func _boot(restore: bool) -> void:
	await _free_world()
	if not restore:
		var save := root.get_node_or_null(^"Save")
		if save != null and save.has_method("forget_all"):
			save.forget_all()
	_world = (load(MAIN) as PackedScene).instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	root.add_child(_world)
	await _frames(3)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	_interaction = _player.get_node(^"InteractionController") as InteractionController
	var voices := _world.get_node_or_null(^"InnerVoiceDirector")
	if voices != null:
		voices.set_process(false)
	_sequence.allow_player_control()
	_sequence.sync_player_locks()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()
	var room := _host.get_current()
	if room == null or String(room.location_id) != "classroom":
		_failures.append("Boot: the world did not open in the classroom (%s)." % (
			String(room.location_id) if room != null else "no room"
		))
		await _free_world()


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await _frames(3)
	_world = null


func _use_exit(exit_id: StringName, destination: StringName, label: String) -> bool:
	await _settle(30.0, "%s: control before '%s'" % [label, exit_id])
	var room := _host.get_current()
	var exit := room.find_interactable(exit_id) if room != null else null
	if exit == null:
		_failures.append("%s: the %s has no '%s'." % [
			label, String(room.location_id) if room != null else "world", exit_id
		])
		return false
	_interaction.request_activation(exit)
	var arrived := await _pump_until(
		func() -> bool:
			var current := _host.get_current()
			return current != null and current.location_id == destination,
		45.0, "%s: '%s' to reach the %s" % [label, exit_id, destination]
	)
	if arrived:
		await _settle(45.0, "%s: the %s to settle" % [label, destination])
	return arrived


## The current room's N, or null.
func _find_n() -> NpcActor:
	var room := _host.get_current() if _host != null else null
	return room.find_actor(&"n") if room != null else null


## How many Ns exist in the whole tree (not only in the current room).
func _count_n() -> int:
	var count := 0
	for node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == &"n" and not actor.is_queued_for_deletion():
			count += 1
	return count


## The end of N's entry path in the current room, and the way its last leg points.
func _stand() -> Dictionary:
	var room := _host.get_current() if _host != null else null
	if room == null:
		return {}
	var points := room.get_waypoint_path(&"NEntryPath")
	if points.size() < 2:
		return {}
	var last := points[points.size() - 1]
	var leg := last - points[points.size() - 2]
	leg.y = 0.0
	return {"point": last, "facing": leg.normalized()}


func _distance_to_stand(n: NpcActor) -> float:
	var stand := _stand()
	if stand.is_empty():
		return INF
	return n.global_position.distance_to(stand["point"])


func _expect_at_stand(n: NpcActor, label: String) -> void:
	if n == null or not is_instance_valid(n):
		_failures.append("%s: N is gone (freed)." % label)
		return
	if not n.is_inside_tree():
		_failures.append("%s: N is out of the scene tree." % label)
		return
	if not n.is_visible_in_tree():
		_failures.append("%s: N is in the room but hidden (visible %s)." % [label, str(n.visible)])
	var stand := _stand()
	if stand.is_empty():
		_failures.append("%s: the classroom lost its NEntryPath." % label)
		return
	var distance := n.global_position.distance_to(stand["point"])
	if distance > AT_STAND_METRES:
		_failures.append("%s: N is at %s, %.2f m from the lectern's stand %s." % [
			label, str(n.global_position), distance, str(stand["point"])
		])
	var facing := n.get_facing_direction().dot(stand["facing"])
	if facing < FACING_DOT:
		_failures.append("%s: N does not face the room (dot %.2f with the last leg)." % [label, facing])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## Continues whatever is on screen until `predicate` holds.
func _pump_until(
	predicate: Callable, timeout_seconds: float, label: String, required: bool = true
) -> bool:
	var started := Time.get_ticks_msec()
	while not bool(predicate.call()):
		if _dialogue != null and _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			if required:
				_failures.append("Timed out waiting for %s." % label)
			return false
	return true


func _settle(timeout_seconds: float, label: String) -> bool:
	return await _pump_until(
		func() -> bool: return not _dialogue.is_busy() and _player.is_control_enabled(),
		timeout_seconds, label
	)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


## Real seconds of frames (the clock is scaled, so this is more story time).
func _seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
