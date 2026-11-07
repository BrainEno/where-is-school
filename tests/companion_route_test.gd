extends SceneTree
## The free-period route, played through the real scenes: classroom → walkway →
## yard, with Q walking along.
##
## What this proves, and what it deliberately does not:
##
## - the classroom door is the way out, and leaving it is what starts the
##   companion — not the dialogue choice;
## - Q is a single person: an authored Q in a location hides the companion, and no
##   transition ever produces two of them;
## - Q follows, stops when the player stops, waits instead of teleporting when left
##   far behind, and can be asked along again through one ordinary interaction;
## - the walkway has optional things to do that are not needed to leave it, one of
##   which makes a noise, and Q comments on some of them only while it is with you;
## - the yard is reached through the walkway's end door, from the school side.
##
## Following is measured, not faked: the player is moved and Q has to close the gap
## on its own. See the note at the end about what a headless run cannot say.

const Harness = preload("res://tests/test_harness.gd")

const TIME_SCALE := 4.0
const OVERALL_TIMEOUT_SECONDS := 220.0
const FOLLOW_TOLERANCE := 0.6

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _sequence: OpeningSequence = null
var _companion: CompanionController = null
var _game_state: Node = null
var _narrative: Node = null
var _started_at_msec := 0
var _seen_nodes: Array[StringName] = []
var _check_count := 0
## Where Q stood when the following check began, so a failure can say how far it moved
## rather than only where it ended up.
var _walk_q_start := Vector3.ZERO


func _initialize() -> void:
	Harness.arm_watchdog(self, 260.0, "companion_route_test.gd")
	call_deferred("_run")


func _run() -> void:
	_started_at_msec = Time.get_ticks_msec()
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

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_companion = _main.get_node_or_null("Companion") as CompanionController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _dialogue == null or _host == null or _player == null \
			or _interaction == null or _sequence == null or _companion == null:
		Harness.finish(self, ["Main did not expose the nodes this route needs."], "")
		return
	_dialogue.line_presented.connect(_on_line_presented)
	_dialogue.check_resolved.connect(_on_check_resolved)
	if _sequence != null:
		# The authored beats are skipped here, so the player has to be handed control
		# explicitly; otherwise the interaction controller stays switched off.
		_sequence.allow_player_control()
	Engine.time_scale = TIME_SCALE

	# The classroom is loaded by the director in _ready; the beats are not replayed.
	if _host.get_current() == null:
		_failures.append("The classroom was not loaded.")
		Harness.finish(self, _failures, "")
		return
	_game_state.set_flag(StoryFlags.N_ARRIVED, true)
	_game_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	await _settle(20.0, "the classroom to settle")

	if not _check_q_is_not_duplicated("before leaving the classroom"):
		return
	if _companion.is_joined():
		_failures.append("Q joined before the player left the classroom.")

	await _leave_classroom()
	await _check_companion_present()
	await _check_corridor_activities()
	await _check_following()
	await _check_waiting_and_resuming()
	await _walk_out_to_the_yard()

	Harness.finish(
		self, _failures,
		"Q follows through the free period, and the yard is reached through the walkway."
	)


# --- the walk ---------------------------------------------------------------


func _leave_classroom() -> void:
	var classroom := _host.get_current()
	var door := classroom.find_interactable(&"classroom_door")
	if door == null:
		_failures.append("The classroom door is missing.")
		return
	if not (door as LocationExit).is_open():
		_failures.append("The classroom door stayed shut after the class was dismissed.")
		return
	_interaction.request_activation(door)
	if not await _pump_until(
		func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "corridor",
		60.0, "the walkway to load"
	):
		return
	await _settle(30.0, "the walkway to settle")
	if not _flag(StoryFlags.LEFT_CLASSROOM):
		_failures.append("Leaving the classroom did not set its flag.")


func _check_companion_present() -> void:
	if not _companion.is_joined():
		_failures.append("Q did not join the player on the way out of the classroom.")
		return
	if not _companion.is_with_player():
		_failures.append("Q joined but is not with the player in the walkway.")
	if not _flag(StoryFlags.Q_COMPANION):
		_failures.append("Joining did not write the companion flag.")
	if not _check_q_is_not_duplicated("in the walkway"):
		return
	var distance := _companion.global_position.distance_to(_player.global_position)
	if distance > _companion.follow_distance + 1.0:
		_failures.append("Q appeared %.1f m from the player instead of beside them." % distance)


func _check_corridor_activities() -> void:
	var corridor := _host.get_current()
	if corridor == null:
		_failures.append("The walkway is not loaded.")
		return
	# Optional, and not a checklist: the walkway offers several things, and the door
	# out is not one of the things that has to be done first.
	for interact_id: StringName in [&"corridor_speaker", &"corridor_trolley", &"corridor_wait"]:
		if corridor.find_interactable(interact_id) == null:
			_failures.append("The walkway is missing '%s'." % interact_id)

	var exit := corridor.find_interactable(&"to_schoolyard") as LocationExit
	if exit == null:
		_failures.append("The walkway has no way out to the yard.")
	elif not String(exit.destination_scene).ends_with("playground/playground.tscn"):
		_failures.append("The walkway's yard door does not lead to the yard.")
	elif String(exit.destination_spawn) != "FromCorridor":
		_failures.append("The yard door does not use the yard's school-side spawn.")

	# The speaker: a noise cue plus a reaction, and Q's line only because Q is here.
	_seen_nodes.clear()
	await _activate(&"corridor_speaker", "the wall speaker")
	await _settle(30.0, "the speaker conversation")
	if not _seen_nodes.has(&"cs_q_q"):
		_failures.append("Q did not say anything about the speaker it was standing next to.")
	var cue := corridor.get_node_or_null(^"SpeakerCue")
	if cue == null:
		_failures.append("The wall speaker has no cue node.")
	elif int(cue.call("get_play_count")) < 1:
		_failures.append("The wall speaker made no sound when it was listened to.")

	# The cleaning trolley: an ordinary obstruction, no dice.
	_seen_nodes.clear()
	var before := _check_count
	await _activate(&"corridor_trolley", "the cleaning trolley")
	await _settle(30.0, "the trolley conversation")
	if not _seen_nodes.has(&"ct_q_q"):
		_failures.append("Q did not comment on the trolley.")
	if _check_count != before:
		_failures.append("An ordinary corridor prop rolled dice.")

	# Waiting at the railing: nothing is gained, and that is the point.
	await _activate(&"corridor_wait", "the railing")
	await _settle(30.0, "the railing conversation")
	if not _flag(StoryFlags.CORRIDOR_WAITED):
		_failures.append("Waiting at the railing was not recorded.")
	if not _narrative.has_entry(&"corridor_waited"):
		_failures.append("Waiting at the railing left no record at all.")


func _check_following() -> void:
	# Walk the player up the walkway in small steps, so Q has to keep up with real
	# movement rather than with one teleport.
	var start := _player.global_position
	_walk_q_start = _companion.global_position
	for step in 6:
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), start + Vector3(0, 0, 0.5 * step)))
		await _frames(10)
	var distance := _companion.global_position.distance_to(_player.global_position)
	if distance > _companion.follow_distance + FOLLOW_TOLERANCE:
		_failures.append("Q fell %.1f m behind a walking player. %s" % [distance, _q_state()])
	var moved := _companion.global_position.distance_to(start)
	if moved < 1.0:
		_failures.append("Q did not move at all while the player walked away. %s" % _q_state())
	if _companion.is_waiting():
		_failures.append("Q gave up following a player who was only a few metres ahead. %s" % _q_state())


func _check_waiting_and_resuming() -> void:
	var ask := _main.get_node_or_null(^"Companion/AskAlong") as Interactable
	if ask == null:
		_failures.append("The companion has no 'ask along' interaction.")
		return
	if ask.can_interact():
		_failures.append("Q can be asked along while already walking with the player.")
	# Leave Q far behind: Q must stop and wait instead of sliding along the floor.
	# The walkway is only ~16 m long, so the give-up threshold is lowered for this
	# check rather than teleporting the player out of the level (which drops them
	# through the floor and measures a fall, not a companion rule).
	var normal_give_up := _companion.give_up_distance
	_companion.give_up_distance = 4.0
	# Move back down the walkway, away from the street end: the floor ends at the
	# gate, and a companion test must not measure a fall.
	var far := _player.global_position + Vector3(0, 0, -5.0)
	_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(1.0)), far))
	await _frames(20)
	if _player.global_position.y < -1.0:
		_failures.append("The test put the player outside the walkway and they fell (y=%.2f)." % _player.global_position.y)
		_companion.give_up_distance = normal_give_up
		return
	if not _companion.is_waiting():
		_failures.append(
			"Q kept chasing a player who was more than %.0f m away. %s"
			% [_companion.give_up_distance, _q_state()]
		)
		_companion.give_up_distance = normal_give_up
		return
	if not ask.can_interact():
		_failures.append("Q cannot be asked along while waiting.")
		_companion.give_up_distance = normal_give_up
		return
	await _activate(&"q_ask_along", "asking Q along")
	await _settle(30.0, "the 'ask along' conversation")
	if _companion.is_waiting():
		_failures.append("Q stayed in waiting mode after being asked along.")
	await _frames(120)
	var distance := _companion.global_position.distance_to(_player.global_position)
	_companion.give_up_distance = normal_give_up
	if distance > _companion.follow_distance + FOLLOW_TOLERANCE:
		_failures.append("Q did not close the gap after being asked along (%.1f m; Q at %s, player at %s)." % [
			distance, _companion.global_position, _player.global_position
		])


## Everything that would explain a follower failure, in one line: where Q and the player
## are, how far apart, whether Q is even allowed to walk, and what it last decided.
func _q_state() -> String:
	return (
		"[q=%s q_start=%s player=%s facing_back=%s gap=%.2f joined=%s visible=%s"
		+ " waiting=%s nav=%s regions=%d route=%d repath=%d note='%s' place='%s']"
	) % [
		str(_companion.global_position), str(_walk_q_start), str(_player.global_position),
		str(_player.global_basis.z), _companion.global_position.distance_to(_player.global_position),
		str(_companion.is_joined()), str(_companion.visible), str(_companion.is_waiting()),
		str(_companion.is_navigation_ready()), _companion.get_navigation_region_count(),
		_companion.get_route().size(), _companion.get_repath_count(),
		_companion.get_last_chase_note(), _companion.get_placement_report(),
	]


func _walk_out_to_the_yard() -> void:
	var corridor := _host.get_current()
	var exit := corridor.find_interactable(&"to_schoolyard") as LocationExit
	if exit == null:
		_failures.append("The yard door disappeared.")
		return
	# Stand at the door and use it, the way the player would.
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -7.2)))
	await _frames(3)
	_interaction.request_activation(exit)
	if not await _pump_until(
		func() -> bool: return String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, "")) == "playground",
		60.0, "the yard to load"
	):
		return
	await _settle(45.0, "the yard arrival beat")
	var yard := _host.get_current()
	if yard == null or String(yard.location_id) != "playground":
		_failures.append("The yard door did not load the playground.")
		return
	if not _flag(StoryFlags.PLAYGROUND_ARRIVED):
		_failures.append("Arriving in the yard through the walkway did not play its arrival line.")
	# The yard is the same open space as before: the old anchors are still there.
	for interact_id: StringName in [&"pg_hoop_near", &"pg_shed_door", &"pg_ball_look", &"pg_bench_look"]:
		if yard.find_interactable(interact_id) == null:
			_failures.append("The yard lost '%s'." % interact_id)
	for interact_id: StringName in [&"pg_tyre_look", &"pg_container_look"]:
		if yard.find_interactable(interact_id) == null:
			_failures.append("The yard has no anchor for '%s'." % interact_id)
	if yard.find_interactable(&"pg_to_corridor") == null:
		_failures.append("The yard has no way back into the walkway.")
	# Arriving from the school side, not from the estate gate at the far end.
	var expected := Vector3(-3.0, 0.0, -17.6)
	if _player.global_position.distance_to(expected) > 1.0:
		_failures.append(
			"The player did not arrive at the yard's school-side spawn (%s)." % _player.global_position
		)
	if not await _check_q_is_not_duplicated("in the yard"):
		return
	if not _companion.is_with_player():
		_failures.append("Q did not come through the door into the yard.")
	await _frames(30)
	var distance := _companion.global_position.distance_to(_player.global_position)
	if distance > _companion.follow_distance + FOLLOW_TOLERANCE:
		_failures.append("Q is %.1f m behind after the transition instead of beside the player." % distance)


# --- helpers ----------------------------------------------------------------


## Exactly one Q may ever be visible: the authored actor in the classroom, or the
## companion everywhere else. Two Qs is the failure this test exists for.
func _check_q_is_not_duplicated(where: String) -> bool:
	var visible_qs: Array[String] = []
	for node: Node in get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor == null or String(actor.npc_id) != "q":
			continue
		if actor.is_visible_in_tree():
			visible_qs.append(String(actor.get_path()))
	if visible_qs.size() == 1:
		return true
	_failures.append("%s: expected one visible Q, found %d (%s)." % [
		where, visible_qs.size(), ", ".join(visible_qs)
	])
	return false


func _activate(interact_id: StringName, label: String) -> void:
	var location := _host.get_current()
	var interactable: Interactable = null
	if location != null:
		interactable = location.find_interactable(interact_id)
	if interactable == null:
		interactable = _main.get_node_or_null(NodePath("Companion/AskAlong")) as Interactable
	if interactable == null or String(interactable.interact_id) != String(interact_id):
		_failures.append("Could not find '%s' (%s)." % [String(interact_id), label])
		return
	_interaction.request_activation(interactable)
	await _frames(2)


func _pump_until(predicate: Callable, timeout_seconds: float, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while not bool(predicate.call()):
		if Time.get_ticks_msec() - _started_at_msec > int(OVERALL_TIMEOUT_SECONDS * 1000.0):
			_failures.append("The route exceeded its time budget while waiting for %s." % label)
			return false
		if _dialogue.is_busy():
			if _dialogue.has_pending_choices():
				_dialogue.select_choice(0)
			else:
				_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
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


func _flag(flag: StringName) -> bool:
	var value: Variant = _game_state.get_flag(flag, false)
	return value == true


func _on_line_presented(line: Dictionary) -> void:
	var node_id := StringName(String(line.get("node_id", "")))
	if not String(node_id).is_empty():
		_seen_nodes.append(node_id)


func _on_check_resolved(_result: Dictionary) -> void:
	_check_count += 1
