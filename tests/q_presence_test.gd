extends SceneTree
## Q stays where the story left him: at his authored start before the first talk, at
## `QOpeningTalk` after it, and at his own desk after the bell. The `q_talk` hotspot
## follows through room re-entry and a continued save.
##
## Every location is a fresh instance of its scene, and the classroom authors Q at his
## starting spot because the opening walks him to the aisle. Before `QPresence`, a room
## built again after `met_q` showed him back at the start, ~1.3 m away, and his hotspot
## with him; `doorway_watch_test` had to put him at the marker by hand to test the room as
## the player sees it.
##
## The real main scene, driven through the same calls the UI makes:
##
## 1. **Before.** A fresh classroom: Q and `q_talk` at their authored spots.
## 2. **The beat.** The real Q beat walks him to the landing and his talk begins; the end
##    of that walk is the reference every later check is held to.
## 3. **Re-entering after class, twice.** The open door frees the room and the walkway
##    leads back: one new Q, seated at B1 facing the front, with his hotspot and pointer
##    boxes still on him. The after-dismissal talk still opens from his new position.
## 4. **No double carry.** The room being re-announced and the flags being replaced leave
##    Q and the hotspot exactly where they are.
## 5. **Continue.** A save written in the classroom after the intro, loaded into a fresh
##    world: Q at the landing from the first frame.
## 6. **Pre-#171 save.** A save with `met_q` and no `q_first_talk_done` reads the same.
## 7. **Before the talk.** A save from before `met_q`: Q at his authored spot, and the beat
##    still walks him over (it is not skipped or pre-empted).
## 8. **No landing.** A room whose marker is gone keeps its Q where he is.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const SESSION_SCRIPT := "res://scripts/ui/game_session.gd"
const TIME_SCALE := 4.0
## The authored spots of `scenes/locations/classroom/classroom.tscn`, which
## `classroom_visual_slice_test` holds the room to.
const AUTHORED_Q := Vector3(-3.3, 0.0, 3.1)
const AUTHORED_TALK := Vector3(-3.3, 0.8, 3.1)
## The beat lands on the navigation map's closest point to the marker (within 0.15 m, as
## `q_intro_lifecycle_support` holds it); a rebuilt room lands on the marker itself.
const BEAT_TOLERANCE_METRES := 0.15
const AT_LANDING_METRES := 0.05
const FACING_DOT := 0.98
const TALK_GAP_METRES := 0.1

var _failures: Array[String] = []
var _notes: Array[String] = []
var _state: Node = null
var _world: Node = null
var _sequence: OpeningSequence = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
## Where the beat left Q, and the way he faced: what a rebuilt room is compared with.
var _beat_point := Vector3.INF
var _beat_facing := Vector3.ZERO


func _initialize() -> void:
	Harness.arm_watchdog(self, 280.0, "q_presence_test.gd")
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
	await _check_continue(true, "Continue")
	await _check_continue(false, "Pre-#171 save")
	await _check_before_the_talk()
	await _check_no_landing()

	Engine.time_scale = 1.0
	paused = false
	await _free_world()
	Harness.clear_session_state(self)
	print("::notice title=Q presence::%s" % " | ".join(_notes))
	Harness.finish(
		self, _failures,
		"Q keeps his intro landing before the bell and his seat after class: re-entry, hotspots and continued saves."
	)


# --- Cases ------------------------------------------------------------------


## 1-4: the beat, then the room left and entered twice.
func _check_play_through() -> void:
	Harness.clear_session_state(self)
	await _boot(false)
	if _world == null:
		return

	# 1. Before.
	var q := _find_q()
	if q == null:
		_failures.append("Before: the classroom has no Q.")
		return
	_expect(
		q.global_position.distance_to(AUTHORED_Q) < 0.01,
		"Before: Q is at %s, not his authored spot %s." % [str(q.global_position), str(AUTHORED_Q)]
	)
	_expect_talk_at(AUTHORED_TALK, "Before")

	# 2. The beat, exactly as the opening runs it.
	_sequence._beat_q_wake()
	if not await _pump_until(
		func() -> bool: return bool(_state.get_flag(StoryFlags.MET_Q, false)), 30.0, "met_q"
	):
		return
	_beat_point = q.global_position
	_beat_facing = q.get_facing_direction()
	var landing := _landing()
	_expect(
		not landing.is_empty() and _flat(_beat_point - landing["point"]) <= BEAT_TOLERANCE_METRES,
		"Beat: Q stopped at %s, not at the room's QOpeningTalk." % str(_beat_point)
	)
	_expect(
		_flat(_beat_point - AUTHORED_Q) > 0.5,
		"Beat: Q only moved %.2f m; the fixture no longer shows the walk."
		% _flat(_beat_point - AUTHORED_Q)
	)
	_expect_talk_on(q, "Beat")
	await _settle(40.0, "Q's first talk to close")
	_notes.append("beat: Q %.2f m from his authored spot" % _flat(_beat_point - AUTHORED_Q))

	# The rest of the morning, written as flags: the door is open after the class.
	for flag: StringName in [
		StoryFlags.TEXTBOOK_MISSING, StoryFlags.EXPECTATION_PLAYED, StoryFlags.BELL_RUNG,
		StoryFlags.N_ARRIVED, StoryFlags.CLASS_DISMISSED,
	]:
		_state.set_flag(flag, true)

	# 3. Leave and come back, twice.
	var first_q_id := q.get_instance_id()
	for visit in [1, 2]:
		var label := "Re-entry %d" % visit
		var old_q := q
		if not await _use_exit(&"classroom_door", &"corridor", label):
			return
		await _frames(3)
		_expect(not is_instance_valid(old_q), "%s: the old classroom's Q was not freed." % label)
		if not await _use_exit(&"back_to_classroom", &"classroom", label):
			return
		q = _find_q()
		if q == null:
			_failures.append("%s: the classroom has no Q." % label)
			return
		_expect(q.get_instance_id() != first_q_id, "%s: the classroom was not built again." % label)
		_expect_at_desk(q, label)
		_expect_talk_on(q, label)
		_expect(_visible_q_count() == 1, "%s: %d Qs are visible, not one." % [label, _visible_q_count()])
		await _frames(3)
		_expect_pick_boxes_on(q, label)
		await _seconds(0.5)
		_expect_at_desk(q, "%s, half a second later" % label)

	# ...and a talk with him still opens from his seat.
	var talk := _host.get_current().find_interactable(&"q_talk")
	if talk != null:
		_interaction.request_activation(talk)
		await _frames(2)
		_expect(
			_dialogue.is_busy()
			and _dialogue.get_runtime().get_active_conversation_id() == &"q_after_dismissal",
			"Re-entry: talking to Q at his spot did not open q_after_dismissal."
		)
		await _settle(30.0, "Q's after-dismissal talk to close")

	# 4. No double carry.
	var where := q.global_position
	var talk_where := talk.global_position if talk != null else Vector3.ZERO
	_host.location_entered.emit(_host.get_current(), _host.get_current_spawn())
	_state.replace_snapshot(_state.get_snapshot())
	await _frames(2)
	_expect(
		q.global_position.distance_to(where) < 0.0001,
		"Repeat: Q moved %.3f m when the room was announced again." % q.global_position.distance_to(where)
	)
	_expect(
		talk == null or talk.global_position.distance_to(talk_where) < 0.0001,
		"Repeat: q_talk was carried again (%.3f m) without Q moving." % (
			talk.global_position.distance_to(talk_where) if talk != null else 0.0
		)
	)


## 5 and 6: a save written in the classroom after Q's first talk, continued.
func _check_continue(with_talk_done: bool, label: String) -> void:
	# The previous case's world goes first: its director still listens to the flags, and
	# `BPresence` answers `met_q` being *written* with `q_first_talk_done = false` (a talk
	# begun, not finished). That is right in play and would put the flag into this
	# fixture's save; a real pre-#171 file is applied with `replace_snapshot()`, which
	# writes nothing.
	await _free_world()
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.MET_Q, true)
	if with_talk_done:
		_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)
	_state.set_flag(StoryFlags.OBJECTIVE_KEY, "objective.check_bag")
	await _boot(false)
	if _world == null:
		return
	# A fresh world with the flags already set is the same room a continue builds; it is
	# checked too, because the boot path and the load path enter the room differently.
	var booted := _find_q()
	if booted != null:
		_expect_at_landing(booted, "%s, booted with the flags" % label)
	var save := root.get_node_or_null(^"Save")
	if save == null:
		_failures.append("%s: there is no Save autoload." % label)
		return
	await _seconds(0.2)
	var result: Dictionary = save.save_game()
	if result.get("ok", false) != true:
		_failures.append("%s: the save was not written: %s" % [label, str(result)])
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
		bool(_state.get_flag(StoryFlags.MET_Q, false)),
		"%s: the save did not bring met_q back." % label
	)
	_expect(
		_state.has_flag(StoryFlags.Q_FIRST_TALK_DONE) == with_talk_done,
		"%s: the load wrote q_first_talk_done; loading must not add flags." % label
	)
	var q := _find_q()
	if q == null:
		_failures.append("%s: the classroom has no Q." % label)
		return
	_expect_at_landing(q, label)
	_expect_talk_on(q, label)
	_expect(_visible_q_count() == 1, "%s: %d Qs are visible." % [label, _visible_q_count()])


## 7: before `met_q`, the room is the opening's, and so is the walk.
func _check_before_the_talk() -> void:
	Harness.clear_session_state(self)
	await _boot(false)
	if _world == null:
		return
	var save := root.get_node_or_null(^"Save")
	var written: Dictionary = _sequence.autosave("wake") if save != null else {}
	_expect(written.get("ok", false), "Before the talk: the checkpoint was not written.")
	await _free_world()
	_state.clear()
	await _boot(true)
	if _world == null:
		return
	var q := _find_q()
	if q == null:
		_failures.append("Before the talk: the classroom has no Q.")
		return
	_expect(
		q.global_position.distance_to(AUTHORED_Q) < 0.01,
		"Before the talk: a save without met_q put Q at %s, not his authored spot."
		% str(q.global_position)
	)
	_expect_talk_at(AUTHORED_TALK, "Before the talk")
	_sequence._beat_q_wake()
	await _pump_until(
		func() -> bool: return bool(_state.get_flag(StoryFlags.MET_Q, false)), 30.0,
		"the walk after a pre-talk save"
	)
	_expect(
		_flat(q.global_position - AUTHORED_Q) > 0.5,
		"Before the talk: the beat did not walk Q over after the save was continued."
	)
	_expect_talk_on(q, "Before the talk, after the walk")
	await _settle(40.0, "the walked Q's talk to close")


## 8: a room with a Q and no landing is left as authored.
func _check_no_landing() -> void:
	Harness.clear_session_state(self)
	await _boot(false)
	if _world == null:
		return
	var room := _host.get_current()
	var marker := room.find_child("QOpeningTalk", true, false)
	if marker == null:
		_failures.append("No landing: the classroom has no QOpeningTalk to take away.")
		return
	marker.get_parent().remove_child(marker)
	marker.free()
	_state.set_flag(StoryFlags.MET_Q, true)
	_state.replace_snapshot(_state.get_snapshot())
	await _frames(2)
	var q := _find_q()
	_expect(
		q != null and q.global_position.distance_to(AUTHORED_Q) < 0.01,
		"No landing: Q was moved in a room that authors no QOpeningTalk."
	)
	_expect_talk_at(AUTHORED_TALK, "No landing")


# --- Helpers ----------------------------------------------------------------


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
		var save := root.get_node_or_null(^"Save")
		if save != null and save.has_method("unbind_world"):
			save.unbind_world()
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


func _find_q() -> NpcActor:
	var room := _host.get_current() if _host != null else null
	return room.find_actor(&"q") if room != null else null


## Visible Qs anywhere in the tree: the room's and the roaming companion's.
func _visible_q_count() -> int:
	var count := 0
	for node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == &"q" and not actor.is_queued_for_deletion() \
				and actor.is_visible_in_tree():
			count += 1
	return count


## The current room's landing as `QPresence` reads it.
func _landing() -> Dictionary:
	return QPresence.landing_in(_host.get_current() if _host != null else null)


func _expect_at_landing(q: NpcActor, label: String) -> void:
	if q == null or not is_instance_valid(q) or not q.is_inside_tree():
		_failures.append("%s: Q is gone." % label)
		return
	var landing := _landing()
	if landing.is_empty():
		_failures.append("%s: the classroom lost its QOpeningTalk." % label)
		return
	var gap := q.global_position.distance_to(landing["point"])
	if gap > AT_LANDING_METRES:
		_failures.append("%s: Q is at %s, %.2f m from QOpeningTalk %s." % [
			label, str(q.global_position), gap, str(landing["point"])
		])
	var to_seat: Vector3 = landing["facing"] - q.global_position
	to_seat.y = 0.0
	var facing := q.get_facing_direction().dot(to_seat.normalized())
	if facing < FACING_DOT:
		_failures.append("%s: Q does not face the protagonist's seat (dot %.2f)." % [label, facing])
	if _beat_point != Vector3.INF:
		var from_beat := _flat(q.global_position - _beat_point)
		if from_beat > BEAT_TOLERANCE_METRES:
			_failures.append(
				"%s: Q is %.2f m from where the beat left him." % [label, from_beat]
			)
		if q.get_facing_direction().dot(_beat_facing) < FACING_DOT:
			_failures.append("%s: Q faces another way than the beat left him." % label)


func _expect_at_desk(q: NpcActor, label: String) -> void:
	var chair := _host.get_current().get_node(^"Furniture/DeskQ/Chair") as PushableChair
	var gap := q.global_position.distance_to(chair.home_mark())
	var facing := q.get_facing_direction().dot(-chair.global_basis.z)
	_expect(gap < 0.03 and facing > FACING_DOT, "%s: Q is %.3f m from B1, facing dot %.3f." % [label, gap, facing])
	_expect(q.get_character_animator().is_seated() and not chair.is_pushed_back(),
		"%s: Q is standing or his chair is still out." % label)


func _expect_talk_on(q: NpcActor, label: String) -> void:
	var talk := _host.get_current().find_interactable(&"q_talk") if _host != null else null
	if talk == null:
		_failures.append("%s: the classroom has no q_talk." % label)
		return
	var gap := _flat(talk.global_position - q.global_position)
	if gap > TALK_GAP_METRES:
		_failures.append("%s: q_talk is %.2f m from Q - left behind at %s." % [
			label, gap, str(talk.global_position)
		])
	# The beat carries it by Q's whole offset, floor height included; a few centimetres of
	# floor collider are fine, a hotspot that sank or floated is not.
	if absf(talk.global_position.y - AUTHORED_TALK.y) > 0.05:
		_failures.append("%s: q_talk changed height (%.2f)." % [label, talk.global_position.y])


func _expect_talk_at(point: Vector3, label: String) -> void:
	var talk := _host.get_current().find_interactable(&"q_talk") if _host != null else null
	if talk == null:
		_failures.append("%s: the classroom has no q_talk." % label)
	elif talk.global_position.distance_to(point) > 0.01:
		_failures.append("%s: q_talk is at %s, not %s." % [label, str(talk.global_position), str(point)])


## The pointer boxes are local to `q_talk`; rebuilt around Q, their centres are on him.
func _expect_pick_boxes_on(q: NpcActor, label: String) -> void:
	var talk := _host.get_current().find_interactable(&"q_talk")
	if talk == null:
		return
	var shapes := talk.get_pick_shapes()
	if shapes.is_empty():
		_failures.append("%s: q_talk has no pointer boxes around Q." % label)
		return
	# A box per outline mesh, each centred on its own mesh (an arm, the head), so the
	# centres spread a little around Q. The ghost this guards against is ~1.3 m away, at
	# the authored spot.
	var centre := Vector3.ZERO
	var counted := 0
	for shape in shapes:
		if not is_instance_valid(shape):
			continue
		centre += shape.global_position
		counted += 1
		var gap := _flat(shape.global_position - q.global_position)
		if gap > 0.9:
			_failures.append("%s: a q_talk pointer box is %.2f m from Q - a ghost hotspot." % [label, gap])
			return
	if counted > 0 and _flat(centre / counted - q.global_position) > 0.45:
		_failures.append("%s: q_talk's pointer boxes are centred %.2f m from Q." % [
			label, _flat(centre / counted - q.global_position)
		])


func _flat(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


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
		func() -> bool:
			return not _dialogue.is_busy() and not _sequence.is_beat_active() \
				and _player.is_control_enabled(),
		timeout_seconds, label
	)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
