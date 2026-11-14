class_name LocationFlow
extends RefCounted
## Everything that happens because of a *place*: taking an exit, changing location,
## announcing the arrival, ending the slice at a milestone, and the one door whose
## prompt depends on the story.
##
## This was the middle third of `opening_sequence.gd`, which is why adding a room
## once meant editing a script called "opening". The prologue still owns the beat
## lock - a transition is a beat like any other, and two things must never hold it -
## so this object borrows `begin_beat()`/`end_beat()` from its host instead of
## keeping a second copy of that state.
##
## Location-specific facts come from `LocationCatalog`, never from a `match` on an
## id. What is left here is genuinely generic: blocked exits, fade, load, arrival
## bookkeeping, the end card.
##
## A finished transition and a finished arrival line are **save points**: the player
## is standing in a room, no beat holds the lock, and nothing is mid-flight. The file
## itself is `SaveManager`'s business; this only says when the moment is right, by
## asking the host for a checkpoint (ADR 0005 §4).

## The only exit whose prompt is rewritten by the story.
const COMPLETION_DOOR_ID := &"classroom_door"
const EXIT_GROUP := &"location_exit"
## How long a transition's `on_failure` may take, in story time (seconds), before the
## refused transition gives the room back anyway. A recovery that never finishes - a
## coroutine whose script error stopped it after its first `await` never completes - must
## not leave the screen black and the beat held for the rest of the session.
const FAILURE_RECOVERY_LIMIT := 5.0

var _host: Node = null
var _locations: LocationHost = null
var _catalog: LocationCatalog = null
var _game_state: Node = null
var _ui: GameUI = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _companion: CompanionController = null
var _hud: GameHud = null
## The people a refusing exit names turn and watch the player (#174).
var _watch: ExitWatch = null

var _finished := false


func _init(
	host: Node,
	locations: LocationHost,
	catalog: LocationCatalog,
	game_state: Node,
	ui: GameUI,
	player: PlayerController,
	dialogue: DialogueController,
	companion: CompanionController
) -> void:
	_host = host
	_locations = locations
	_catalog = catalog
	_game_state = game_state
	_ui = ui
	_player = player
	_dialogue = dialogue
	_companion = companion
	if _ui != null:
		_hud = _ui.hud
	# A node, because a watch follows the player every frame; a child of the host, so it
	# goes when the host does.
	if _host != null:
		_watch = ExitWatch.new()
		_watch.name = "ExitWatch"
		_watch.setup(_player, _dialogue, _host)
		_host.add_child(_watch)


## True once the milestone card is up: the slice is over and nothing should start.
func is_finished() -> bool:
	return _finished


## The watch a refusing exit starts, for tests and diagnostics (null without a host).
func get_exit_watch() -> ExitWatch:
	return _watch


# --- Exits ------------------------------------------------------------------


## Routes one activated exit. Closed doors show their blocked text; milestone ends
## show the card; everything else is a transition.
##
## The returned coroutine is the whole visit: awaiting it means the player is
## standing in the room the exit named, or back where they started if the load was
## refused. Callers that do not care (the interaction handler) simply drop it.
func handle_exit(exit: LocationExit) -> void:
	if not String(exit.blocked_inspection_id).is_empty() and not exit.is_open():
		_dialogue.present_inspection(exit.blocked_inspection_id)
		# Same frame as the text: whoever it says is watching is seen to be.
		if _watch != null:
			_watch.begin(exit, _locations.get_current() if _locations != null else null)
		return
	if not exit.is_open():
		push_warning(
			"LocationFlow: exit '%s' is closed and has no blocked text." % exit.interact_id
		)
		return
	if exit.is_milestone_end:
		await _finish_slice(exit)
		return
	await _transition_to(exit)


func _transition_to(exit: LocationExit) -> void:
	# Loading the next location frees this one, and `exit` with it, so everything the
	# transition needs afterwards is copied first.
	await transition_to(
		exit.destination_scene,
		exit.destination_spawn,
		exit.destination_id,
		{"label": "exit '%s'" % exit.interact_id}
	)


## Takes the player to `destination_spawn` in `destination_scene`, the same way an exit
## does: one beat, fade, load, arrival bookkeeping, fade back, the arrival line, a save
## point. Exits come through here; so does a room that leaves by other means (the biology
## classroom's curtain, which is a fall rather than a door - see `StagedInteractable`).
##
## `destination_id` is the location id the scene must turn out to have; the load is
## refused otherwise and the player stays where they were. Returns whether the player is
## now in the new room.
##
## `options` (all optional):
##   "label": String               names the cause in error messages.
##   "beat_held": bool             the caller already holds the beat (a staged moment
##                                 that ends by leaving); it is ended here either way.
##   "departure": Callable         awaited before the fade: the room's own way of leaving,
##                                 played while the room still exists. It may pose the
##                                 player's body and roll the camera; both are put back
##                                 before the new room fades in.
##   "fade_out": float             seconds of fade to black after the departure (0.7).
##   "arrival_flags": Dictionary   flag -> value, written once the new room is loaded.
##   "arrival_conversation": StringName
##                                 plays instead of the room's own arrival line, whether
##                                 or not that line has been heard.
##   "on_failure": Callable        the caller's recovery when the destination is refused
##                                 (missing scene, wrong id, no spawn, unplaceable player).
##                                 Called at most once, and only on that path: after the
##                                 departure's pose and camera have been put back, while
##                                 the screen is still black, the beat is still held and
##                                 the old room is still current - so it can put the room
##                                 back the way the departure found it before anyone sees
##                                 it. It takes no arguments and may be a coroutine; it is
##                                 awaited, for at most `FAILURE_RECOVERY_LIMIT` seconds of
##                                 story time. The fade back and the beat release happen
##                                 whatever it does. It must not start a transition or
##                                 take the beat. Nothing else is rolled back for it:
##                                 `arrival_flags` were never written, and the room's own
##                                 state is the caller's business. The return value is
##                                 still `false`; callers must not call it again.
func transition_to(
	destination_scene: String,
	destination_spawn: StringName,
	destination_id: StringName,
	options: Dictionary = {}
) -> bool:
	var label := String(options.get("label", destination_scene))
	if not bool(options.get("beat_held", false)):
		await _host.begin_beat()
	var departure: Callable = options.get("departure", Callable())
	var posed := departure.is_valid()
	if posed:
		await departure.call()
	await _ui.fade.fade_to_black(float(options.get("fade_out", 0.7)))
	# `destination_id` is passed as the expected id, so the load fails unless the
	# scene really is the place the caller named.
	var loaded := _locations.load_location(
		destination_scene, destination_spawn, _player, destination_id
	)
	if posed:
		_stand_player_up()
	if not loaded:
		# Nothing has moved: the old location is still current, the player is still
		# standing in it, and CURRENT_LOCATION still describes it.
		push_error(
			"LocationFlow: could not enter '%s' from %s; staying put." % [destination_scene, label]
		)
		var on_failure: Callable = options.get("on_failure", Callable())
		if on_failure.is_valid():
			await _recover_from_refusal(on_failure, label)
		await _ui.fade.fade_from_black(0.5)
		_host.end_beat()
		return false

	var entered := _locations.get_current()
	if entered != null:
		destination_id = entered.location_id
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, destination_id)
	var arrival_flags: Dictionary = options.get("arrival_flags", {})
	for flag: Variant in arrival_flags:
		_game_state.set_flag(StringName(String(flag)), arrival_flags[flag])
	_apply_arrival(destination_id)
	if _hud != null:
		_hud.clear_prompt()
	update_exit_prompt()
	# Story time, like every authored wait: a pause opened mid-transition holds this
	# beat where it is (see `OpeningSequence.wait_seconds()`).
	await _host.get_tree().create_timer(0.3, false).timeout
	await _ui.fade.fade_from_black(0.9)
	# The arrival line plays after the transition beat releases the lock, otherwise
	# the beat that plays the conversation would wait for itself.
	_host.end_beat()
	_play_arrival_beat(destination_id, StringName(options.get("arrival_conversation", &"")))
	return true


## Runs a refused transition's `on_failure` once and waits for it, but never longer than
## `FAILURE_RECOVERY_LIMIT` seconds of story time (a timer that stops under the pause menu,
## like every authored wait). The callback is started from a small runner rather than
## awaited directly: a coroutine that dies after an `await` never completes, and awaiting
## it here would hold the beat and the black screen forever.
func _recover_from_refusal(on_failure: Callable, label: String) -> void:
	var state := {"done": false}
	var runner := func() -> void:
		await on_failure.call()
		state["done"] = true
	runner.call()
	if bool(state["done"]):
		return
	var limit := _host.get_tree().create_timer(FAILURE_RECOVERY_LIMIT, false)
	while not bool(state["done"]):
		if limit.time_left <= 0.0:
			push_error(
				(
					"LocationFlow: the failure recovery for %s did not finish within %.1f s; "
					+ "giving the room back anyway."
				)
				% [label, FAILURE_RECOVERY_LIMIT]
			)
			return
		await _host.get_tree().process_frame


## Undoes whatever a departure did to the body and the view: upright, unrolled, the
## camera back on the player.
func _stand_player_up() -> void:
	if _player == null:
		return
	_player.set_wake_pose(0.0)
	if _player.visual != null:
		_player.visual.position.x = 0.0
		_player.visual.position.z = 0.0
	_player.set_camera_roll(0.0)
	if _player.camera_rig != null:
		_player.camera_rig.release_frame(0.0)


## The part of arriving that is data: the objective line, the flags this room sets,
## and the companion finally starting to follow.
func _apply_arrival(location_id: StringName) -> void:
	# Leaving the room is what starts the companion, not the dialogue choice: a player
	# who stays at the desk and walks out ten minutes later gets the same Q.
	if _companion != null and not _companion.is_joined():
		if location_id != &"classroom" and _has_flag(StoryFlags.CLASS_DISMISSED):
			_companion.join()

	var entry := _catalog.get_entry(location_id) if _catalog != null else null
	if entry == null:
		# A room the catalog does not describe still works; it just says nothing
		# about itself, which is a reasonable thing for a debug room to do.
		return
	for flag: StringName in entry.arrival_flags:
		_game_state.set_flag(flag, true)
	if not entry.objective.is_empty() and _hud != null:
		_hud.set_objective(entry.objective)


## The first line a location says about itself, once - or, when the way in was not an
## ordinary one, the line the caller asked for instead (`override`).
func _play_arrival_beat(location_id: StringName, override: StringName = &"") -> void:
	# The checkpoint comes last in every branch: after the line that this room had to
	# say, so the flags it set are in the file, and outside the beat, so nothing that
	# owns the lock is serialised half-applied.
	if not String(override).is_empty():
		await _host.begin_beat()
		await _host.play_conversation(override)
		_host.end_beat()
		_checkpoint(location_id)
		return
	var entry := _catalog.get_entry(location_id) if _catalog != null else null
	if entry == null or String(entry.arrival_conversation).is_empty():
		_checkpoint(location_id)
		return
	if String(entry.arrival_flag).is_empty() or _has_flag(entry.arrival_flag):
		_checkpoint(location_id)
		return
	await _host.begin_beat()
	await _host.play_conversation(entry.arrival_conversation)
	_host.end_beat()
	_checkpoint(location_id)


func _checkpoint(location_id: StringName) -> void:
	if _host != null and _host.has_method("autosave"):
		_host.autosave("arrival:%s" % String(location_id))


# --- The end of the implemented slice --------------------------------------


func _finish_slice(exit: LocationExit) -> void:
	_finished = true
	_host.sync_player_locks()
	# The last checkpoint of the build: everything the ending decided is in the file
	# before the card goes up.
	if _host.has_method("autosave"):
		_host.autosave(&"slice_end")
	await _ui.fade.fade_to_black(1.0)
	var title := exit.end_card_title
	var body := exit.end_card_body
	if not exit.end_card_key.is_empty():
		var title_key := "%s.title" % exit.end_card_key
		var body_key := "%s.body" % exit.end_card_key
		if L10n.has_key(title_key):
			title = L10n.t(title_key)
		if L10n.has_key(body_key):
			body = L10n.t(body_key)
	_ui.end_card.present(title, body, L10n.t("ui.end_hint"))


# --- The one story-dependent prompt ---------------------------------------


## The classroom door is the only exit whose prompt changes with the story.
##
## This used to match on `destination_id == "corridor"`, which also matched the
## street's return exit once the street existed: walking out of the school and
## standing at that door showed "Leave the classroom" in the middle of the street.
## The door is identified by its own id now, and the street exit keeps the prompt its
## scene gives it.
func update_exit_prompt() -> void:
	if _host == null or not _host.is_inside_tree():
		return
	var dismissed := _has_flag(StoryFlags.CLASS_DISMISSED)
	var door: LocationExit = null
	for node in _host.get_tree().get_nodes_in_group(EXIT_GROUP):
		var candidate := node as LocationExit
		if candidate != null and candidate.interact_id == COMPLETION_DOOR_ID:
			door = candidate
			break
	if door == null:
		return
	if dismissed:
		door.set_prompt("prompt.door_leave")
	else:
		door.clear_prompt_override()


func _has_flag(flag: StringName) -> bool:
	if _game_state == null:
		return false
	return bool(_game_state.get_flag(flag, false))
