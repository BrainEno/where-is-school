class_name OpeningSequence
extends Node
## Authored beat director for the biology-class prologue.
##
## It owns *sequencing*: waking up, letting Q start talking, waiting for the
## schoolbag discovery, presenting the expectation beat, ringing the bell,
## bringing the substitute in, and moving the player to the walkway.
##
## It deliberately does not own: movement (PlayerController), dialogue content or
## graph walking (DialogueController/DialogueRuntime), knowledge categories
## (NarrativeState), or location contents (LocationRoot scenes). Beats take a
## lock so two authored sequences can never run at once; anything the player
## triggers while a beat runs simply waits for the interaction to be re-enabled.

@export var player_path: NodePath = ^"../Player"
@export var interaction_path: NodePath = ^"../Player/InteractionController"
@export var ui_path: NodePath = ^"../GameUI"
@export var dialogue_path: NodePath = ^"../DialogueController"
@export var location_host_path: NodePath = ^"../LocationHost"
## Set to false to load the classroom without starting the authored beats
## (used by the headless smoke test).
@export var autostart: bool = true
@export var bell_audio_path: NodePath = ^"../BellAudio"
@export var wake_audio_path: NodePath = ^"../WakeAudio"

const CLASSROOM_SCENE := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR_SCENE := "res://scenes/locations/corridor/corridor.tscn"
const STREET_SCENE := "res://scenes/locations/street/street.tscn"
const RESIDENTIAL_SCENE := "res://scenes/locations/residential/residential.tscn"
const CLASSROOM_START := &"PlayerStart"
const CORRIDOR_START := &"FromClassroom"

const WAKE_FADE_SECONDS := 3.0
const WAKE_SETTLE_SECONDS := 2.0
const EXPECTATION_LEAD_IN := 0.8
const EXPECTATION_DISCLAIMER_SECONDS := 2.8
const BELL_LEAD_IN := 6.0
const BAG_REMINDER_SECONDS := 40.0
## Hard fallback so a player who never opens the bag still reaches the lesson.
const BAG_WAIT_LIMIT := 95.0

var _player: PlayerController = null
var _interaction: InteractionController = null
var _ui: GameUI = null
var _dialogue: DialogueController = null
var _locations: LocationHost = null
var _bell_audio: AudioStreamPlayer = null
var _wake_audio: AudioStreamPlayer = null
var _hud: GameHud = null
var _passive_voices: PassiveVoices = null

var _beat_active := false
var _control_allowed := false
var _slice_finished := false


func _ready() -> void:
	if not _resolve_nodes():
		return
	_dialogue.presentation_active_changed.connect(_on_presentation_active_changed)
	_game_state().story_flag_changed.connect(_on_story_flag_changed)
	_interaction.activation_requested.connect(_on_activation_requested)
	_interaction.target_changed.connect(_on_target_changed)
	_passive_voices = PassiveVoices.new(_game_state(), _dialogue.get_runtime().get_check_engine())

	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)
	_dialogue.locale_applied.connect(_on_locale_changed)

	_ui.fade.set_opaque()
	_player.set_wake_pose(1.0)
	_player.set_camera_roll(_player.wake_camera_roll)
	_sync_player_locks()

	if not _locations.load_location(CLASSROOM_SCENE, CLASSROOM_START, _player):
		push_error("OpeningSequence: the classroom location failed to load.")
		return
	_game_state().set_flag(StoryFlags.CURRENT_LOCATION, &"classroom")
	if autostart:
		start()


## Starts the authored opening beats. Safe to call once, after _ready.
func start() -> void:
	_run_opening()


func _resolve_nodes() -> bool:
	_player = get_node_or_null(player_path) as PlayerController
	_interaction = get_node_or_null(interaction_path) as InteractionController
	_ui = get_node_or_null(ui_path) as GameUI
	_dialogue = get_node_or_null(dialogue_path) as DialogueController
	_locations = get_node_or_null(location_host_path) as LocationHost
	_bell_audio = get_node_or_null(bell_audio_path) as AudioStreamPlayer
	_wake_audio = get_node_or_null(wake_audio_path) as AudioStreamPlayer
	if _ui != null:
		_hud = _ui.hud

	var missing: Array[String] = []
	if _player == null:
		missing.append("player_path '%s'" % player_path)
	if _interaction == null:
		missing.append("interaction_path '%s'" % interaction_path)
	if _ui == null:
		missing.append("ui_path '%s'" % ui_path)
	if _dialogue == null:
		missing.append("dialogue_path '%s'" % dialogue_path)
	if _locations == null:
		missing.append("location_host_path '%s'" % location_host_path)
	if _bell_audio == null:
		missing.append("bell_audio_path '%s'" % bell_audio_path)
	if _wake_audio == null:
		missing.append("wake_audio_path '%s'" % wake_audio_path)
	if not missing.is_empty():
		push_error("OpeningSequence: missing node reference(s): %s" % ", ".join(missing))
		return false
	return true


# --- Authored beats ---------------------------------------------------------


func _run_opening() -> void:
	# Beat A: wake up. Slow fade in, camera roll settling, body straightening.
	_wake_audio.play()
	await _ui.fade.fade_from_black(WAKE_FADE_SECONDS)
	_player.settle_wake_pose(WAKE_SETTLE_SECONDS)
	_player.settle_camera_roll(WAKE_SETTLE_SECONDS)
	await get_tree().create_timer(0.4).timeout
	_control_allowed = true
	_sync_player_locks()
	_hud.set_objective("objective.get_bearings")

	# Beat B: Q starts talking without being asked.
	await get_tree().create_timer(0.9).timeout
	await _begin_beat()
	await _play_conversation(&"q_wake")
	_end_beat()

	# Beat C/D: the player searches the bag and is free to look around.
	_start_bag_reminder()
	await _wait_for_flag(StoryFlags.TEXTBOOK_MISSING, BAG_WAIT_LIMIT)

	# Beat E: expectation, clearly framed as imagination.
	if _has_flag(StoryFlags.TEXTBOOK_MISSING) and not _has_flag(StoryFlags.EXPECTATION_PLAYED):
		await get_tree().create_timer(EXPECTATION_LEAD_IN).timeout
		await _beat_expectation()

	# Beat F: the bell rings, B does not arrive, N takes the lesson.
	await get_tree().create_timer(BELL_LEAD_IN).timeout
	await _beat_bell()
	await _beat_substitute()


func _beat_expectation() -> void:
	await _begin_beat()
	_ui.overlay.show_localized_overlay("overlay.expect_title", "overlay.expect_body")
	await get_tree().create_timer(0.7).timeout
	await _play_conversation(&"expected_b")
	_ui.overlay.show_localized_overlay("overlay.deny_title", "overlay.deny_body")
	await get_tree().create_timer(EXPECTATION_DISCLAIMER_SECONDS).timeout
	await _ui.overlay.hide_overlay()
	_game_state().set_flag(StoryFlags.EXPECTATION_PLAYED, true)
	_end_beat()


func _beat_bell() -> void:
	await _begin_beat()
	if _has_flag(StoryFlags.BELL_RUNG):
		_end_beat()
		return
	_game_state().set_flag(StoryFlags.BELL_RUNG, true)
	_bell_audio.play()
	_hud.set_objective("objective.bell")
	await get_tree().create_timer(1.0).timeout
	await _play_conversation(&"bell_moment")
	_end_beat()


func _beat_substitute() -> void:
	var location := _locations.get_current()
	if location == null:
		push_error("OpeningSequence: no location loaded for the substitute beat.")
		return
	var actor := location.find_actor(&"n")
	if actor == null:
		push_error("OpeningSequence: the classroom has no actor with npc_id 'n'.")
		return
	var points := location.get_waypoint_path(&"NEntryPath")
	if points.size() < 2:
		push_error("OpeningSequence: 'NEntryPath' needs at least two markers.")
		return

	await _begin_beat()
	actor.place_at(points[0], points[1])
	_end_beat()

	await actor.walk_along(points.slice(1))

	await _begin_beat()
	_game_state().set_flag(StoryFlags.N_ARRIVED, true)
	await get_tree().create_timer(0.4).timeout
	await _play_conversation(&"n_class")
	_end_beat()
	_update_exit_prompt()


func _start_bag_reminder() -> void:
	if _has_flag(StoryFlags.TEXTBOOK_MISSING):
		return
	await get_tree().create_timer(BAG_REMINDER_SECONDS).timeout
	if _has_flag(StoryFlags.TEXTBOOK_MISSING) or _has_flag(StoryFlags.BELL_RUNG) or _slice_finished:
		return
	await _begin_beat()
	await _play_conversation(&"q_bag_reminder")
	_end_beat()


# --- Interaction routing ----------------------------------------------------


func _on_activation_requested(interactable: Interactable) -> void:
	if _dialogue.is_busy() or _slice_finished:
		return

	var exit := interactable as LocationExit
	if exit != null:
		_handle_exit(exit)
		return

	if not String(interactable.conversation_route).is_empty():
		var conversation := ConversationRouter.select(
			interactable.conversation_route, _game_state().get_snapshot()
		)
		if String(conversation).is_empty():
			push_error(
				"OpeningSequence: no conversation rule matched route '%s'."
				% interactable.conversation_route
			)
			return
		await _begin_beat()
		var interaction_id := interactable.interact_id
		await _play_conversation(conversation)
		_end_beat()
		await _play_passive_reaction(interaction_id)
		return

	if not String(interactable.inspection_id).is_empty():
		var interaction_id := interactable.interact_id
		if _dialogue.present_inspection(interactable.inspection_id):
			while _dialogue.is_busy():
				await _dialogue.presentation_active_changed
			await _play_passive_reaction(interaction_id)
		return

	push_error(
		"OpeningSequence: interactable '%s' declares no inspection, conversation, or exit."
		% interactable.interact_id
	)


## Reactions are contextual and deliberately sparse. They are ordinary
## subjective JSON conversations, not a second narration or a factual claim.
func _play_passive_reaction(interaction_id: StringName) -> void:
	if _passive_voices == null:
		return
	var conversation := _passive_voices.after_interaction(interaction_id)
	if String(conversation).is_empty():
		return
	await _begin_beat()
	await _play_conversation(conversation)
	_end_beat()


func _on_target_changed(interactable: Interactable) -> void:
	if _dialogue.is_busy() or _beat_active or _slice_finished:
		_hud.clear_prompt()
		return
	_hud.set_prompt_text(_dialogue.get_interact_prompt(interactable))


func _handle_exit(exit: LocationExit) -> void:
	if not String(exit.blocked_inspection_id).is_empty() and not exit.is_open():
		_dialogue.present_inspection(exit.blocked_inspection_id)
		return
	if not exit.is_open():
		push_warning("OpeningSequence: exit '%s' is closed and has no blocked text." % exit.interact_id)
		return
	if exit.is_milestone_end:
		_finish_slice(exit)
		return
	await _transition_to(exit)


func _transition_to(exit: LocationExit) -> void:
	# Loading the next location frees this one, and `exit` with it, so everything
	# the transition needs afterwards is copied first.
	var destination_scene := exit.destination_scene
	var destination_spawn := exit.destination_spawn
	var destination_id := exit.destination_id
	var exit_id := exit.interact_id
	await _begin_beat()
	await _ui.fade.fade_to_black(0.7)
	var loaded := _locations.load_location(destination_scene, destination_spawn, _player)
	if not loaded:
		push_error(
			"OpeningSequence: could not enter '%s' from exit '%s'." % [destination_scene, exit_id]
		)
		await _ui.fade.fade_from_black(0.5)
		_end_beat()
		return

	if not String(destination_id).is_empty():
		_game_state().set_flag(StoryFlags.CURRENT_LOCATION, destination_id)
	if destination_id == &"corridor":
		_game_state().set_flag(StoryFlags.LEFT_CLASSROOM, true)
		_hud.set_objective("objective.leave_classroom")
	elif destination_id == &"street":
		_game_state().set_flag(StoryFlags.LEFT_SCHOOL, true)
		_hud.set_objective("objective.outside")
	elif destination_id == &"residential":
		_hud.set_objective("objective.residential")
	elif destination_id in [&"estate_passage", &"playground"]:
		_hud.set_objective("objective.explore")
	_hud.clear_prompt()
	_update_exit_prompt()
	await get_tree().create_timer(0.3).timeout
	await _ui.fade.fade_from_black(0.9)
	# The arrival line plays after the transition beat releases the lock, otherwise
	# the beat that plays the conversation would wait for itself.
	_end_beat()
	await _play_arrival_beat(destination_id)


## One short conversation the first time the player reaches an outdoor location.
## Outside the school nothing hands out a task: the beat only says where you are.
func _play_arrival_beat(destination_id: StringName) -> void:
	var conversation := &""
	var flag := &""
	match String(destination_id):
		"street":
			conversation = &"street_arrival"
			flag = StoryFlags.STREET_ARRIVED
		"residential":
			conversation = &"residential_arrival"
			flag = StoryFlags.RESIDENTIAL_ARRIVED
		_:
			return
	if _has_flag(flag) or String(conversation).is_empty():
		return
	await _begin_beat()
	await _play_conversation(conversation)
	_end_beat()


func _finish_slice(exit: LocationExit) -> void:
	_slice_finished = true
	_sync_player_locks()
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


# --- Presentation plumbing --------------------------------------------------


func _play_conversation(conversation_id: StringName) -> void:
	if not _dialogue.play_conversation(conversation_id):
		return
	await _dialogue.conversation_finished


func _begin_beat() -> void:
	while _beat_active or _dialogue.is_busy():
		await get_tree().process_frame
	_beat_active = true
	_sync_player_locks()


func _end_beat() -> void:
	_beat_active = false
	_sync_player_locks()
	# Locking the player clears the prompt; unlocking has to put it back, because
	# the target itself may not change again for a while.
	if _interaction != null and _hud != null and not _slice_finished:
		_on_target_changed(_interaction.get_current_target())


func _on_presentation_active_changed(_active: bool) -> void:
	_sync_player_locks()


func _sync_player_locks() -> void:
	if _player == null or _interaction == null:
		return
	var locked := _beat_active or _dialogue.is_busy() or _slice_finished or not _control_allowed
	_player.set_control_enabled(not locked)
	_interaction.set_enabled(not locked)
	if locked and _hud != null:
		_hud.clear_prompt()


## A language switch re-renders whatever is on screen (the dialogue controller does
## that) and re-resolves the contextual prompt, which is owned here.
func _on_locale_changed(_locale: String) -> void:
	if _interaction == null or _hud == null:
		return
	_on_target_changed(_interaction.get_current_target())


func _on_story_flag_changed(flag: StringName, _previous: Variant, value: Variant) -> void:
	if flag == StoryFlags.OBJECTIVE_KEY:
		_hud.set_objective(String(value))
	elif flag == StoryFlags.CLASS_DISMISSED:
		_update_exit_prompt()


func _update_exit_prompt() -> void:
	var dismissed := _has_flag(StoryFlags.CLASS_DISMISSED)
	for node in get_tree().get_nodes_in_group("location_exit"):
		var exit := node as LocationExit
		if exit == null:
			continue
		if exit.destination_id == &"corridor":
			if dismissed:
				exit.set_prompt("prompt.door_leave")
			else:
				exit.clear_prompt_override()


func _wait_for_flag(flag: StringName, limit_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < limit_seconds:
		if _has_flag(flag):
			return
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25


func _has_flag(flag: StringName) -> bool:
	return bool(_game_state().get_flag(flag, false))


func _game_state() -> Node:
	return get_node(^"/root/GameState")
