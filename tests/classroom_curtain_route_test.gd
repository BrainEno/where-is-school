extends SceneTree
## Round 21 bug: with the curtain open and the edge already held, the player clicked the
## curtain from across the room (inside the interaction's reach, but with a chair on the
## straight line to the cut), chose "step down through the opening" and nothing happened:
## the staged walk only knew straight lines and quietly gave up. This plays that case
## through the real main scene, interaction, director and dialogue: from a spot where the
## straight line to the lip is blocked, choosing the step must still walk round the desks
## and land the player in the yard.

const Harness = preload("res://tests/test_harness.gd")
const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const TIME_SCALE := 3.0
const WAIT := 60.0

var _check := Harness.Checker.new()
var _state: Node
var _main: Node
var _host: LocationHost
var _player: PlayerController
var _dialogue: DialogueController
var _interaction: InteractionController
var _sequence: OpeningSequence
var _conversations: Array[StringName] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "classroom_curtain_route_test.gd")
	call_deferred("_run")


func _run() -> void:
	_state = Harness.ensure_state_autoloads(self)["game_state"]
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_state.set_flag(StoryFlags.CURTAIN_DRAWN, true)
	_state.set_flag(StoryFlags.CURTAIN_EDGE_HELD, true)
	if await _boot():
		Engine.time_scale = TIME_SCALE
		await _step_from_across_the_room()
	Engine.time_scale = 1.0
	var save := root.get_node_or_null(^"Save")
	if save != null and save.has_method("forget_all"):
		save.forget_all()
	Harness.clear_session_state(self)
	Harness.finish(
		self,
		_check.failures,
		"the step through the open cut walks round the desks from anywhere the curtain is in reach."
	)


func _boot() -> bool:
	_main = MAIN.instantiate()
	var sequence_node := _main.get_node_or_null(^"OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await process_frame
	await process_frame
	_host = _main.get_node_or_null(^"LocationHost") as LocationHost
	_player = _main.get_node_or_null(^"Player") as PlayerController
	_dialogue = _main.get_node_or_null(^"DialogueController") as DialogueController
	_sequence = _main.get_node_or_null(^"OpeningSequence") as OpeningSequence
	if _player != null:
		_interaction = _player.get_node_or_null(^"InteractionController") as InteractionController
	if (
		_host == null
		or _player == null
		or _dialogue == null
		or _sequence == null
		or _interaction == null
	):
		_check.fail("Main did not expose the nodes this test needs.")
		return false
	_dialogue.conversation_started.connect(func(id: StringName) -> void: _conversations.append(id))
	_sequence.allow_player_control()
	if not _host.load_location(CLASSROOM, &"FromCorridor", _player):
		_check.fail("The classroom could not be entered.")
		return false
	for _index in 20:
		await physics_frame
	return true


func _step_from_across_the_room() -> void:
	var room := _host.get_current() as LocationRoot
	var curtain: Interactable = room.find_interactable(&"curtain") if room != null else null
	var approach := (
		room.get_node_or_null(^"Anomalies/VoidApproach") as Marker3D if room != null else null
	)
	if not _check.expect(
		curtain != null and approach != null, "No curtain interactable or VoidApproach mark."
	):
		return
	var spot: Variant = await _blocked_spot(curtain, approach.global_position)
	if spot == null:
		(
			_check
			. fail(
				(
					"Found no spot in reach of the curtain with a desk or chair on the straight line to the cut;"
					+ " the classroom layout changed and this test no longer covers the bug."
				)
			)
		)
		return
	var start: Vector3 = spot
	print("::notice title=curtain route::stepping from (%.2f, %.2f)" % [start.x, start.z])
	_check.expect(
		not Motion.route_to(_player, approach.global_position).is_empty(),
		"The navigation map has no route from (%.2f, %.2f) to the cut." % [start.x, start.z]
	)
	_interaction.set_enabled(true)
	_interaction.request_activation(curtain)
	var seen := {"chose": false}
	var arrived := await Harness.wait_until(
		func() -> bool:
			if _dialogue.is_busy():
				if _dialogue.has_pending_choices():
					var ids: Array = _dialogue.get_runtime().get_available_choice_ids()
					var index := ids.find(&"step") if not seen["chose"] else -1
					if index >= 0:
						seen["chose"] = true
					_dialogue.select_choice(maxi(index, 0))
				else:
					_dialogue.advance_presentation()
			var current := _host.get_current() as LocationRoot
			return current != null and current.location_id == &"playground",
		WAIT
	)
	_check.expect(
		_conversations.has(&"classroom_curtain_step"),
		"The curtain did not offer the step (%s)." % str(_conversations)
	)
	_check.expect(seen["chose"], "The step through the opening was never offered as a choice.")
	(
		_check
		. expect(
			arrived,
			(
				"From (%.2f, %.2f), with the straight line to the cut blocked, choosing the step never reached the yard."
				% [start.x, start.z]
			)
		)
	)


## A floor spot the player can stand on, with the curtain in reach and in sight, from which
## the capsule's straight line to the lip runs into furniture. The player is left there.
func _blocked_spot(curtain: Interactable, mark: Vector3) -> Variant:
	var map := _player.navigation_agent.get_navigation_map()
	var x := -5.4
	while x <= -3.4:
		var z := 0.0
		while z <= 3.2:
			var candidate := Vector3(x, 0.0, z)
			z += 0.2
			var snapped := NavigationServer3D.map_get_closest_point(map, candidate)
			if Vector2(snapped.x - candidate.x, snapped.z - candidate.z).length() > 0.05:
				continue
			if not _interaction.is_in_reach_at(snapped, curtain):
				continue
			var eye := Vector3(snapped.x, snapped.y + _interaction.eye_height, snapped.z)
			if not _interaction.has_line_of_sight_from(eye, curtain):
				continue
			_player.teleport(Transform3D(Basis.IDENTITY, Vector3(snapped.x, 0.0, snapped.z)))
			await physics_frame
			await physics_frame
			var travel := mark - _player.global_position
			travel.y = 0.0
			if _player.test_move(_player.global_transform.translated(Vector3.UP * 0.035), travel):
				_player.face_toward(Vector3.LEFT)
				return _player.global_position
		x += 0.2
	return null
