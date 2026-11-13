extends SceneTree
## The ground mark a click leaves must live exactly as long as the walk it stands for.
##
## The bug this test was written for: after a click on the floor the character walked
## there and stopped, and the ring stayed on the floor. Taking the keys afterwards, opening
## a conversation or walking through a door did not remove it either; it followed the
## player into the next room. `PointerNavigator._on_path_cancelled()` took the mark down,
## but `_on_path_finished()` did nothing for a plain floor click, and a click that landed
## within arrival distance finished its walk *inside* `request_path_to()`, before the mark
## was drawn, so even an arrival handler would have run too early.
##
## Every case drives the game through the inputs a player has - a click at a screen
## position, a movement key, a scripted beat that locks control, a location change - and
## reads the mark's state from the mark itself (`DestinationCue`), not from pixels:
##
## 1. a floor click draws the mark, and arriving fades it (it is not cut, and it is gone
##    shortly after);
## 2. a movement key during the walk cancels the walk and removes the mark at once, and
##    the mark stays gone while the keys drive the character;
## 3. moving with the keys after an arrival leaves no old mark on the floor;
## 4. three clicks in a row leave one mark, at the last point, and none after arriving;
## 5. a click within arrival distance answers without leaving a mark behind;
## 6. a click on an object walks there with the amber mark, activates it once on arrival
##    (the automatic interaction is unchanged), and the mark is gone for the conversation;
## 7. a scripted beat that locks control mid-walk removes the mark;
## 8. a location change removes the mark - mid-walk, on the frame of an arrival while the
##    mark is still fading, and with a refusal still on screen.

const Harness = preload("res://tests/test_harness.gd")
const PROBE_SCENE := "res://scenes/interaction/interactable.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
## Near the back of the classroom: open floor all round, and the front of the room in view.
const START := Vector3(0.0, 0.0, 3.0)
const WALK_LIMIT_SECONDS := 10.0
const DIALOGUE_LIMIT_SECONDS := 12.0
## Longer than `DestinationCue.DISMISS_SECONDS` at any time scale this test uses.
const FADE_LIMIT_SECONDS := 1.0

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _interaction: InteractionController = null
var _navigator: PointerNavigator = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _location: LocationRoot = null

var _activated: Array[StringName] = []
var _approaches_activated: Array[StringName] = []
var _silenced: Array[Interactable] = []

## What the mark looked like at the moment `path_finished` was emitted, read from a
## handler connected after the navigator's, so it sees what the navigator just did.
var _finish_seen := 0
var _finish_cue_shown := false
var _finish_cue_visible := false
var _finish_cue_role := ""


func _initialize() -> void:
	Harness.arm_watchdog(self, 300.0, "destination_cue_lifecycle_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
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
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
		_navigator = _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if _host == null or _player == null or _interaction == null or _navigator == null \
			or _dialogue == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	if not _navigator.marker_enabled:
		Harness.finish(self, ["The player's PointerNavigator has its marker turned off."], "")
		return

	_player.path_finished.connect(_on_path_finished)
	_interaction.activation_requested.connect(_on_activation)
	_navigator.approach_activated.connect(_on_approach_activated)
	_sequence.allow_player_control()
	Engine.time_scale = 4.0
	await _frames(4)

	_location = _host.get_current()
	if _location == null:
		Harness.finish(self, ["The classroom is not loaded."], "")
		return
	# The room's own hotspots cover much of its floor. They step aside so that "a click on
	# the floor" is a click on the floor; the object case puts its own probe down.
	_silence_authored(true)
	if not await _wait_for_floor():
		Harness.finish(self, _failures, "")
		return

	await _check_arrival_fades_the_mark()
	await _check_keys_cancel_the_walk_and_the_mark()
	await _check_keys_after_arrival_leave_no_mark()
	await _check_consecutive_clicks_leave_one_mark()
	await _check_click_where_standing_leaves_no_mark()
	await _check_object_click_still_approaches_and_activates()
	await _check_control_lock_removes_the_mark()
	await _check_location_change_removes_the_mark()

	Engine.time_scale = 1.0
	Harness.finish(
		self, _failures,
		"the ground mark appears on a click and is gone after an arrival, a key, a newer click, a lock and a location change."
	)


# --- 1. arrival ---------------------------------------------------------------


func _check_arrival_fades_the_mark() -> void:
	Harness.stage = "arrival"
	await _reset_to_start()
	var screen: Variant = _reachable_ground_screen(2.0, 4.5)
	if screen == null:
		_failures.append("arrival: no floor point 2-4.5 m away was clickable.")
		return
	var point: Vector3 = _navigator.get_ground_point_at(screen)
	_navigator.click_at_screen_position(screen)
	await _physics_frames(2)
	if not _player.is_path_active():
		_failures.append("arrival: a floor click did not start a walk (%s)." % _navigator.get_last_rejection())
		return
	var cue := _navigator.get_cue()
	if cue == null:
		_failures.append("arrival: a floor click drew no mark at all.")
		return
	if _navigator.get_cue_role() != WorldCue.ROLE_DESTINATION or not cue.is_shown():
		_failures.append("arrival: the mark of a floor click has role '%s'." % _navigator.get_cue_role())
	if _flat_distance(cue.global_position, point) > 0.15:
		_failures.append("arrival: the mark is %.2f m from the clicked point." % _flat_distance(cue.global_position, point))
	await _wait_seconds(0.4)
	if not _cue_drawn():
		_failures.append("arrival: the mark was gone before the walk ended.")

	_finish_seen = 0
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS):
		_failures.append("arrival: the character never arrived.")
		return
	if _finish_seen != 1:
		_failures.append("arrival: the walk ended with %d path_finished signal(s), not one." % _finish_seen)
		return
	if _finish_cue_shown:
		_failures.append(
			"arrival: the mark was still shown (role '%s') when the walk finished." % _finish_cue_role
		)
	if not _finish_cue_visible:
		_failures.append("arrival: the mark was cut on arrival instead of fading out.")
	if not await _wait_until(func() -> bool: return not _cue_drawn(), FADE_LIMIT_SECONDS):
		_failures.append(
			"arrival: the mark is still on the floor %.1f s after arriving (role '%s', opacity %.2f)."
			% [FADE_LIMIT_SECONDS, _navigator.get_cue_role(), cue.get_opacity()]
		)
	if _flat_distance(_player.global_position, point) > 1.0:
		_failures.append("arrival: the character stopped %.2f m from the clicked point." % _flat_distance(_player.global_position, point))


# --- 2. keys during the walk ------------------------------------------------------


func _check_keys_cancel_the_walk_and_the_mark() -> void:
	Harness.stage = "keys mid-walk"
	await _reset_to_start()
	if not await _start_floor_walk("keys mid-walk", 3.0, 5.5):
		return
	await _wait_seconds(0.25)
	if not _player.is_path_active():
		_failures.append("keys mid-walk: the walk ended before a key could interrupt it.")
		return
	Input.action_press("move_forward")
	await _physics_frames(2)
	if _player.is_path_active():
		_failures.append("keys mid-walk: holding a movement key did not cancel the automatic walk.")
	if _cue_drawn():
		_failures.append("keys mid-walk: the mark stayed on the floor after a key took over.")
	var drawn_frames := 0
	for _index in 20:
		await physics_frame
		if _cue_drawn():
			drawn_frames += 1
	Input.action_release("move_forward")
	if drawn_frames > 0:
		_failures.append("keys mid-walk: the mark was drawn on %d frame(s) while the keys drove the character." % drawn_frames)
	if _player.is_path_active():
		_failures.append("keys mid-walk: an automatic walk came back while the keys were held.")
	await _physics_frames(4)


# --- 3. keys after an arrival ----------------------------------------------------


func _check_keys_after_arrival_leave_no_mark() -> void:
	Harness.stage = "keys after arrival"
	await _reset_to_start()
	if not await _start_floor_walk("keys after arrival", 2.0, 4.0):
		return
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS):
		_failures.append("keys after arrival: the character never arrived.")
		return
	var start := _player.global_position
	var drawn_frames := 0
	Input.action_press("move_back")
	for _index in 30:
		await physics_frame
		if _cue_drawn():
			drawn_frames += 1
	Input.action_release("move_back")
	if _flat_distance(_player.global_position, start) < 0.1:
		_failures.append("keys after arrival: the movement key did not move the character.")
	if drawn_frames > 0:
		_failures.append(
			"keys after arrival: the old mark was on the floor for %d of 30 frame(s) of keyboard movement (role '%s')."
			% [drawn_frames, _navigator.get_cue_role()]
		)
	await _physics_frames(4)


# --- 4. several clicks ---------------------------------------------------------


func _check_consecutive_clicks_leave_one_mark() -> void:
	Harness.stage = "consecutive clicks"
	await _reset_to_start()
	var points: Array[Vector3] = []
	for index in 3:
		var avoid: Vector3 = points[points.size() - 1] if not points.is_empty() else Vector3.ZERO
		var screen: Variant = _reachable_ground_screen(1.8, 5.0, avoid)
		if screen == null:
			_failures.append("consecutive clicks: no floor point for click %d." % (index + 1))
			return
		var point: Vector3 = _navigator.get_ground_point_at(screen)
		_navigator.click_at_screen_position(screen)
		await _physics_frames(3)
		if not _player.is_path_active():
			_failures.append("consecutive clicks: click %d did not leave a walk running (%s)." % [index + 1, _navigator.get_last_rejection()])
			return
		points.append(point)
		var cues := _cue_nodes()
		if cues.size() != 1:
			_failures.append("consecutive clicks: after click %d there are %d mark node(s), not one." % [index + 1, cues.size()])
		var drawn := 0
		for node: Node3D in cues:
			if node.visible and (node as DestinationCue).get_opacity() > 0.01:
				drawn += 1
		if drawn != 1:
			_failures.append("consecutive clicks: after click %d, %d mark(s) are drawn." % [index + 1, drawn])
		var cue := _navigator.get_cue()
		if cue == null or _flat_distance(cue.global_position, point) > 0.15:
			_failures.append("consecutive clicks: after click %d the mark is not at the newest point." % (index + 1))
		if _flat_distance(_player.get_path_target(), point) > 0.6:
			_failures.append("consecutive clicks: after click %d the walk is not heading for the newest point." % (index + 1))
		await _wait_seconds(0.15)
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS):
		_failures.append("consecutive clicks: the character never arrived at the last point.")
		return
	if not await _wait_until(func() -> bool: return not _cue_drawn(), FADE_LIMIT_SECONDS):
		_failures.append("consecutive clicks: a mark is still on the floor after the last walk arrived.")


# --- 5. a click where the character already stands ---------------------------------


func _check_click_where_standing_leaves_no_mark() -> void:
	Harness.stage = "click where standing"
	await _reset_to_start()
	# Walk somewhere first: where a walk ends is, by definition, on the navigation mesh
	# and within arrival distance of a point the map hands out, which START need not be.
	if not await _start_floor_walk("click where standing", 1.8, 4.0):
		return
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS):
		_failures.append("click where standing: the walk there never arrived.")
		return
	await _wait_until(func() -> bool: return not _cue_drawn(), FADE_LIMIT_SECONDS)
	await _wait_seconds(0.3)
	var screen: Variant = _ground_screen_near_player(_player.arrival_radius * 0.9)
	if screen == null:
		_failures.append(
			"click where standing: no clickable floor within %.2f m of the character at %s (%s)."
			% [_player.arrival_radius * 0.9, str(_player.global_position), str(_near_stats)]
		)
		return
	_navigator.click_at_screen_position(screen)
	if not _navigator.was_last_click_accepted():
		_failures.append("click where standing: a click at the character's feet was refused (%s)." % _navigator.get_last_rejection())
		return
	await _physics_frames(3)
	if _player.is_path_active():
		_failures.append("click where standing: a click within arrival distance started a walk.")
	if _cue_drawn() or (_navigator.get_cue() != null and _navigator.get_cue().is_shown()):
		_failures.append(
			"click where standing: a walk that was already over left a mark (role '%s')." % _navigator.get_cue_role()
		)
	await _wait_seconds(0.6)
	if _cue_drawn():
		_failures.append("click where standing: the mark is still on the floor 0.6 s later.")


# --- 6. a click on an object --------------------------------------------------


func _check_object_click_still_approaches_and_activates() -> void:
	Harness.stage = "object click"
	await _reset_to_start()
	var spot: Variant = _open_floor_point(_interaction.max_distance + 0.8, 5.0)
	if spot == null:
		_failures.append("object click: no open floor for the probe.")
		return
	var probe := _make_probe(&"cue_lifecycle_probe", (spot as Vector3) + Vector3.UP * 0.9)
	await _physics_frames(4)
	_activated.clear()
	_approaches_activated.clear()
	if not _click_target(probe):
		_failures.append("object click: the probe could not be clicked (%s)." % _navigator.get_last_rejection())
		_free_probe(probe)
		return
	await _physics_frames(2)
	if not _navigator.is_approaching() or _navigator.get_pending_target() != probe:
		_failures.append("object click: clicking an object out of reach did not start an approach.")
		_free_probe(probe)
		return
	if _navigator.get_cue_role() != WorldCue.ROLE_TARGET or not _cue_drawn():
		_failures.append("object click: the approach is marked '%s', not with the target mark." % _navigator.get_cue_role())
	if not await _wait_until(func() -> bool: return not _approaches_activated.is_empty(), WALK_LIMIT_SECONDS):
		_failures.append("object click: the probe was never activated on arrival.")
		_free_probe(probe)
		return
	if _activated != ([&"cue_lifecycle_probe"] as Array[StringName]):
		_failures.append("object click: activations on arrival were %s, not the probe once." % str(_activated))
	if _navigator.is_approaching() or _navigator.get_pending_target() != null:
		_failures.append("object click: approach state was left over after the activation.")
	if _cue_drawn() or (_navigator.get_cue() != null and _navigator.get_cue().is_shown()):
		_failures.append("object click: the target mark stayed after the object was used.")
	# The inspection is a conversation: control is locked while it is open.
	var drawn_during_dialogue := false
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _cue_drawn():
			drawn_during_dialogue = true
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(DIALOGUE_LIMIT_SECONDS * 1000.0):
			_failures.append("object click: the inspection would not close.")
			break
	if drawn_during_dialogue:
		_failures.append("object click: a mark was on the floor during the conversation.")
	await _physics_frames(10)
	if _activated.size() != 1:
		_failures.append("object click: the probe was activated %d time(s) in total." % _activated.size())
	_free_probe(probe)
	await _physics_frames(2)


# --- 7. control locked mid-walk --------------------------------------------------


func _check_control_lock_removes_the_mark() -> void:
	Harness.stage = "control lock"
	await _reset_to_start()
	if not await _start_floor_walk("control lock", 3.0, 5.5):
		return
	await _wait_seconds(0.2)
	if not _player.is_path_active():
		_failures.append("control lock: the walk ended before the lock.")
		return
	await _sequence.begin_beat()
	await _physics_frames(2)
	if _player.is_control_enabled():
		_failures.append("control lock: a scripted beat did not lock the player.")
	if _player.is_path_active():
		_failures.append("control lock: the walk survived the lock.")
	if _cue_drawn():
		_failures.append("control lock: the mark stayed on the floor under a scripted beat.")
	await _wait_seconds(0.3)
	_sequence.end_beat()
	await _physics_frames(4)
	if _cue_drawn():
		_failures.append("control lock: the old mark came back when control returned.")
	if _player.is_path_active():
		_failures.append("control lock: the old walk resumed when control returned.")


# --- 8. location change --------------------------------------------------------


func _check_location_change_removes_the_mark() -> void:
	Harness.stage = "location change"
	# (a) mid-walk.
	await _reset_to_start()
	if not await _start_floor_walk("location change mid-walk", 3.0, 5.5):
		return
	await _wait_seconds(0.2)
	if not await _enter_corridor("mid-walk"):
		return
	if _cue_drawn():
		_failures.append("location change mid-walk: the classroom's mark was drawn in the corridor.")
	if _player.is_path_active() or _navigator.get_pending_target() != null or _navigator.is_approaching():
		_failures.append("location change mid-walk: walk or approach state crossed into the corridor.")
	await _physics_frames(10)
	if _cue_drawn():
		_failures.append("location change mid-walk: an old mark appeared in the corridor afterwards.")

	# (b) on the frame of an arrival, while the mark is still fading. At time scale 1 the
	# fade lasts 0.14 s of real time, so the room changes while it is still running.
	if not await _back_to_classroom():
		return
	if not await _start_floor_walk("location change on arrival", 2.0, 4.0):
		return
	Engine.time_scale = 1.0
	var arrived := await _wait_until(
		func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS * 4.0
	)
	var entered := false
	if arrived:
		entered = await _enter_corridor("on arrival")
	Engine.time_scale = 4.0
	if not arrived:
		_failures.append("location change on arrival: the character never arrived.")
		return
	if not entered:
		return
	if _cue_drawn():
		_failures.append(
			"location change on arrival: the arrival's mark was carried into the corridor (role '%s', opacity %.2f)."
			% [_navigator.get_cue_role(), _navigator.get_cue().get_opacity() if _navigator.get_cue() != null else 0.0]
		)

	# (c) with a refusal still on screen.
	if not await _back_to_classroom():
		return
	var refused: Variant = _refused_screen()
	if refused == null:
		_failures.append("location change after a refusal: no unwalkable spot on screen to click.")
		return
	_navigator.click_at_screen_position(refused)
	await process_frame
	if _navigator.was_last_click_accepted() or _navigator.get_cue_role() != WorldCue.ROLE_REFUSED:
		_failures.append(
			"location change after a refusal: the click was not refused (role '%s')." % _navigator.get_cue_role()
		)
		return
	if not await _enter_corridor("after a refusal"):
		return
	if _cue_drawn():
		_failures.append("location change after a refusal: the classroom's refusal was drawn in the corridor.")
	# The corridor itself still gets a mark of its own: a later click works normally.
	await _settle_dialogue()
	_sequence.allow_player_control()
	if not await _wait_for_floor():
		return
	if not await _start_floor_walk("corridor click", 1.8, 4.5):
		return
	if not _cue_drawn() or _navigator.get_cue_role() != WorldCue.ROLE_DESTINATION:
		_failures.append("location change: a floor click in the corridor drew no mark.")
	if not await _wait_until(func() -> bool: return not _player.is_path_active(), WALK_LIMIT_SECONDS):
		_failures.append("location change: the corridor walk never arrived.")
		return
	if not await _wait_until(func() -> bool: return not _cue_drawn(), FADE_LIMIT_SECONDS):
		_failures.append("location change: the corridor's mark stayed after its walk arrived.")


func _enter_corridor(label: String) -> bool:
	if not _host.load_location(CORRIDOR, &"FromClassroom", _player, &"corridor"):
		_failures.append("location change %s: entering the corridor failed." % label)
		return false
	_location = _host.get_current()
	# Read before a frame runs as well as after: the old room's mark must not be on the
	# first frame of the new one either.
	if _cue_drawn():
		_failures.append("location change %s: the old mark was drawn on the corridor's first frame." % label)
	await _physics_frames(2)
	return true


func _back_to_classroom() -> bool:
	var scene := "res://scenes/locations/classroom/classroom.tscn"
	if not _host.load_location(scene, &"", _player, &"classroom"):
		_failures.append("location change: returning to the classroom failed.")
		return false
	_location = _host.get_current()
	_silence_authored(true)
	await _physics_frames(2)
	await _settle_dialogue()
	if not await _wait_for_floor():
		return false
	await _reset_to_start()
	return true


# --- helpers ----------------------------------------------------------------


func _on_path_finished() -> void:
	_finish_seen += 1
	var cue := _navigator.get_cue()
	_finish_cue_shown = cue != null and cue.is_shown()
	_finish_cue_visible = cue != null and cue.visible and cue.get_opacity() > 0.01
	_finish_cue_role = _navigator.get_cue_role()


func _on_activation(interactable: Interactable) -> void:
	_activated.append(interactable.interact_id)


func _on_approach_activated(interactable: Interactable) -> void:
	_approaches_activated.append(interactable.interact_id)


## Whether the mark is on screen: present, visible and not faded out.
func _cue_drawn() -> bool:
	var cue := _navigator.get_cue()
	if cue == null or not is_instance_valid(cue):
		return false
	return cue.visible and cue.get_opacity() > 0.01


## Every DestinationCue in the scene tree, wherever it was put.
func _cue_nodes() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is DestinationCue and not node.is_queued_for_deletion():
			found.append(node as Node3D)
		stack.append_array(node.get_children())
	return found


func _start_floor_walk(label: String, min_distance: float, max_distance: float) -> bool:
	var screen: Variant = _reachable_ground_screen(min_distance, max_distance)
	if screen == null:
		_failures.append("%s: no floor point %.1f-%.1f m away was clickable." % [label, min_distance, max_distance])
		return false
	_navigator.click_at_screen_position(screen)
	await _physics_frames(2)
	if not _player.is_path_active():
		_failures.append("%s: a floor click did not start a walk (%s)." % [label, _navigator.get_last_rejection()])
		return false
	if not _cue_drawn():
		_failures.append("%s: a floor click drew no mark." % label)
	return true


func _reset_to_start() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	await _settle_dialogue()
	_navigator.cancel()
	_sequence.allow_player_control()
	_player.teleport(Transform3D(Basis.IDENTITY, START))
	await _physics_frames(3)
	# Whatever the previous case left fading is allowed to finish before the next starts.
	await _wait_until(func() -> bool: return not _cue_drawn(), FADE_LIMIT_SECONDS)


## The navigation mesh is baked deferred: the first frames of a room can see no floor.
func _wait_for_floor() -> bool:
	for _attempt in 20:
		if _reachable_ground_screen(1.8, 5.0) != null:
			return true
		await _physics_frames(10)
	var room := String(_location.name) if _location != null else "the room"
	_failures.append("No clickable floor appeared in %s." % room)
	return false


## A screen position whose click would land on walkable floor between these distances,
## with a route to it and no object under the pointer. Scanned, not guessed.
func _reachable_ground_screen(min_distance: float, max_distance: float, avoid: Vector3 = Vector3.ZERO) -> Variant:
	var rect := _player.get_viewport().get_visible_rect().size
	var map := _player.navigation_agent.get_navigation_map()
	for x_step in 16:
		for y_step in 12:
			var screen := Vector2(
				rect.x * (0.08 + 0.84 * float(x_step) / 15.0),
				rect.y * (0.15 + 0.7 * float(y_step) / 11.0)
			)
			var point: Variant = _navigator.get_ground_point_at(screen)
			if point == null:
				continue
			var world: Vector3 = point
			var distance := _flat_distance(_player.global_position, world)
			if distance < min_distance or distance > max_distance:
				continue
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			if not avoid.is_zero_approx() and _flat_distance(world, avoid) < 1.2:
				continue
			if NavigationServer3D.map_get_path(map, _player.global_position, world, true).size() < 2:
				continue
			return screen
	return null


## A walkable floor point between these distances with nothing interactable over it.
func _open_floor_point(min_distance: float, max_distance: float) -> Variant:
	var screen: Variant = _reachable_ground_screen(min_distance, max_distance)
	if screen == null:
		return null
	return _navigator.get_ground_point_at(screen)


## How many probes around the player survived each question, for the failure message.
var _near_stats := {}


## A screen position whose click lands on walkable floor within `radius` of the player.
func _ground_screen_near_player(radius: float) -> Variant:
	var camera := _player.get_viewport().get_camera_3d()
	_near_stats = {"probes": 0, "free": 0, "ground": 0, "near": 0}
	if camera == null:
		return null
	for ring: float in [0.0, radius * 0.25, radius * 0.5, radius * 0.75]:
		for index in 12:
			var angle := TAU * float(index) / 12.0
			var world := _player.global_position + Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
			var screen := camera.unproject_position(world)
			_near_stats["probes"] = int(_near_stats["probes"]) + 1
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			_near_stats["free"] = int(_near_stats["free"]) + 1
			var point: Variant = _navigator.get_ground_point_at(screen)
			if point == null:
				continue
			_near_stats["ground"] = int(_near_stats["ground"]) + 1
			if _flat_distance(point as Vector3, _player.global_position) <= radius:
				_near_stats["near"] = int(_near_stats["near"]) + 1
				return screen
	return null


## A screen position a click would refuse: no walkable ground under it and no object.
func _refused_screen() -> Variant:
	var rect := _player.get_viewport().get_visible_rect().size
	for y_step in 10:
		for x_step in 12:
			var screen := Vector2(
				rect.x * (0.05 + 0.9 * float(x_step) / 11.0),
				rect.y * (0.03 + 0.5 * float(y_step) / 9.0)
			)
			if _interaction.get_target_at_screen_position(screen, false) != null:
				continue
			if _navigator.get_ground_point_at(screen) != null:
				continue
			return screen
	return null


func _make_probe(interact_id: StringName, position: Vector3) -> Interactable:
	var packed: PackedScene = load(PROBE_SCENE)
	var probe := packed.instantiate() as Interactable
	probe.name = String(interact_id)
	probe.interact_id = interact_id
	probe.prompt_text = "Probe"
	probe.inspection_id = &"classroom_own_desk"
	probe.radius = 0.7
	_location.add_child(probe)
	probe.global_position = position
	return probe


func _free_probe(probe: Interactable) -> void:
	if is_instance_valid(probe):
		probe.queue_free()


## A click on an object, at a screen position where the pointer is actually over it.
func _click_target(target: Interactable) -> bool:
	var rect := _player.get_viewport().get_visible_rect().size
	for x_step in 24:
		for y_step in 16:
			var screen := Vector2(
				rect.x * (0.02 + 0.96 * float(x_step) / 23.0),
				rect.y * (0.02 + 0.96 * float(y_step) / 15.0)
			)
			if _interaction.get_target_at_screen_position(screen, false) != target:
				continue
			_navigator.click_at_screen_position(screen)
			return _navigator.was_last_click_accepted()
	return false


## Takes the room's authored interactables out of the pointer's way (collision only).
func _silence_authored(silence: bool) -> void:
	if not silence:
		for item: Interactable in _silenced:
			if is_instance_valid(item):
				item.collision_layer = Interactable.INTERACTION_LAYER
		_silenced.clear()
		return
	for node: Node in _location.find_children("*", "Area3D", true, false):
		var item := node as Interactable
		if item == null:
			continue
		item.collision_layer = 0
		_silenced.append(item)


## Closes whatever conversation is open (an arrival line, an inspection).
func _settle_dialogue() -> void:
	var started := Time.get_ticks_msec()
	while _dialogue.is_busy():
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await process_frame
		if Time.get_ticks_msec() - started > int(DIALOGUE_LIMIT_SECONDS * 1000.0):
			_failures.append("A conversation would not close.")
			return


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _wait_until(condition: Callable, limit_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while not condition.call():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			return false
	return true


## Waits this many seconds of game time (the test runs at `Engine.time_scale` 4).
func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
