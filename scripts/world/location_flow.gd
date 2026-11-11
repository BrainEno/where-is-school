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
## Known limitation, unchanged by the split: a transition is a coroutine and its
## progress is not saved. A save taken mid-fade would reload into the room it was
## leaving. Fixing that needs the save system (#60), which needs this.

## The only exit whose prompt is rewritten by the story.
const COMPLETION_DOOR_ID := &"classroom_door"
const EXIT_GROUP := &"location_exit"

var _host: Node = null
var _locations: LocationHost = null
var _catalog: LocationCatalog = null
var _game_state: Node = null
var _ui: GameUI = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _companion: CompanionController = null
var _hud: GameHud = null

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


## True once the milestone card is up: the slice is over and nothing should start.
func is_finished() -> bool:
	return _finished


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
	var destination_scene := exit.destination_scene
	var destination_spawn := exit.destination_spawn
	var destination_id := exit.destination_id
	var exit_id := exit.interact_id
	await _host.begin_beat()
	await _ui.fade.fade_to_black(0.7)
	# `destination_id` is passed as the expected id, so the load fails unless the
	# scene really is the place the exit named.
	var loaded := _locations.load_location(
		destination_scene, destination_spawn, _player, destination_id
	)
	if not loaded:
		# Nothing has moved: the old location is still current, the player is still
		# standing in it, and CURRENT_LOCATION still describes it.
		push_error(
			"LocationFlow: could not enter '%s' from exit '%s'; staying put."
			% [destination_scene, exit_id]
		)
		await _ui.fade.fade_from_black(0.5)
		_host.end_beat()
		return

	var entered := _locations.get_current()
	if entered != null:
		destination_id = entered.location_id
	_game_state.set_flag(StoryFlags.CURRENT_LOCATION, destination_id)
	_apply_arrival(destination_id)
	if _hud != null:
		_hud.clear_prompt()
	update_exit_prompt()
	await _host.get_tree().create_timer(0.3).timeout
	await _ui.fade.fade_from_black(0.9)
	# The arrival line plays after the transition beat releases the lock, otherwise
	# the beat that plays the conversation would wait for itself.
	_host.end_beat()
	_play_arrival_beat(destination_id)


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


## The first line a location says about itself, once.
func _play_arrival_beat(location_id: StringName) -> void:
	var entry := _catalog.get_entry(location_id) if _catalog != null else null
	if entry == null or String(entry.arrival_conversation).is_empty():
		return
	if String(entry.arrival_flag).is_empty() or _has_flag(entry.arrival_flag):
		return
	await _host.begin_beat()
	await _host.play_conversation(entry.arrival_conversation)
	_host.end_beat()


# --- The end of the implemented slice --------------------------------------


func _finish_slice(exit: LocationExit) -> void:
	_finished = true
	_host.sync_player_locks()
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
