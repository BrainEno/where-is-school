class_name OpeningSequence
extends Node
## Authored beat director for the biology-class prologue.
##
## It owns *sequencing*: waking up, letting Q start talking, waiting for the
## schoolbag discovery, presenting the expectation beat, ringing the bell,
## bringing the substitute in - and then handing the player over to the places they
## walk through.
##
## The position in that sequence is **not remembered anywhere**: each step names the
## story flag that proves it is done, and the director runs the first step whose flag
## is not set. Starting the game and resuming from a save are therefore the same
## call, and a headless test can ask "what would happen if the player already knew the
## textbook was missing?" without simulating the ten minutes before it.
##
## A save is a snapshot of this same data plus the place the player is standing in
## (ADR 0005): the director is what captures it, and what restores it at boot before
## the first step is chosen. Because the steps are flag-gated, "restore then start" is
## all a resume needs.
##
## It deliberately does not own: movement (PlayerController), dialogue content or
## graph walking (DialogueController/DialogueRuntime), knowledge categories
## (NarrativeState), location contents (LocationRoot scenes), or anything that
## happens because of a *place* - exits, transitions and arrival lines live in
## `LocationFlow`, and what a room declares about itself lives in
## `data/story/locations.json`. Beats take a lock so two authored sequences can never
## run at once; anything the player triggers while a beat runs simply waits for the
## interaction to be re-enabled.

@export var player_path: NodePath = ^"../Player"
@export var interaction_path: NodePath = ^"../Player/InteractionController"
@export var ui_path: NodePath = ^"../GameUI"
@export var dialogue_path: NodePath = ^"../DialogueController"
@export var location_host_path: NodePath = ^"../LocationHost"
## Set to false to load the classroom without starting the authored beats
## (used by the headless smoke test).
@export var autostart: bool = true
@export var companion_path: NodePath = ^"../Companion"
@export var bell_audio_path: NodePath = ^"../BellAudio"
@export var wake_audio_path: NodePath = ^"../WakeAudio"

const WAKE_FADE_SECONDS := 3.0
const WAKE_SETTLE_SECONDS := 2.0
const EXPECTATION_LEAD_IN := 0.8
const EXPECTATION_DISCLAIMER_SECONDS := 2.8
const BELL_LEAD_IN := 6.0
const BAG_REMINDER_SECONDS := 40.0
## Hard fallback so a player who never opens the bag still reaches the lesson.
const BAG_WAIT_LIMIT := 95.0

## The card that reports an unreadable save. It is the only surface this build has for
## a message that is not dialogue, and it goes away by itself.
const SAVE_NOTICE_SECONDS := 9.0
const SAVE_ERROR_TITLE_KEY := "save.error.title"
const SAVE_ERROR_ADVICE_KEY := "save.error.advice"
const SAVE_ERROR_QUARANTINE_KEY := "save.error.quarantined"

var _player: PlayerController = null
var _interaction: InteractionController = null
var _ui: GameUI = null
var _dialogue: DialogueController = null
var _locations: LocationHost = null
var _companion: CompanionController = null
var _bell_audio: AudioStreamPlayer = null
var _wake_audio: AudioStreamPlayer = null
var _hud: GameHud = null

var _beat_active := false
var _control_allowed := false

## What every location declares about itself (`data/story/locations.json`).
var _catalog: LocationCatalog = null
## Exits, transitions, arrival lines and the end card.
var _flow: LocationFlow = null
## The save file (autoload `Save`), when the host has one.
var _save: Node = null
## Autosave is on by default: the game has no menu, so a checkpoint the player did not
## ask for is the only thing standing between them and losing the session (ADR 0005).
var autosave_enabled: bool = true
## True when this session came out of a save file rather than a new game.
var _restored_from_save := false
## What the save reader said when it refused the file, kept for the on-screen report.
var _save_problem: Dictionary = {}

## The prologue, in order. Each step is identified by the flag that proves it is
## done; see `next_step()`.
const STEPS: Array[StringName] = [
	&"wake", &"q_wake", &"bag", &"expectation", &"bell", &"substitute",
]


func _ready() -> void:
	if not _resolve_nodes():
		return
	_dialogue.presentation_active_changed.connect(_on_presentation_active_changed)
	_game_state().story_flag_changed.connect(_on_story_flag_changed)
	_interaction.activation_requested.connect(_on_activation_requested)
	_interaction.target_changed.connect(_on_target_changed)

	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.locale_changed.connect(_on_locale_changed)
	_dialogue.locale_applied.connect(_on_locale_changed)

	_catalog = LocationCatalog.load_all()
	if not _catalog.is_valid():
		# Not fatal: a room the catalog cannot describe still runs, it just announces
		# nothing. The error is loud because it is always an authoring mistake.
		push_error("OpeningSequence: %s" % _catalog.describe_errors())
	_flow = LocationFlow.new(
		self, _locations, _catalog, _game_state(), _ui, _player, _dialogue, _companion
	)

	_bind_save()

	# A save, if the host has one, is applied *before* anything is asked about the
	# story: `next_step()` reads flags, so restoring after it would resume from the
	# wrong step. A file that cannot be trusted is refused loudly and the run starts
	# from the beginning - the file itself is kept (ADR 0005 §6).
	var restored := _restore_save()
	if _restored_from_save:
		# A save with no `world` block still restored the flags; `_start_from_save` puts
		# the player at the start marker because there is no place to put them back in.
		_start_from_save(restored)
		return

	# The wake is only a *pending* step, not a fact. A game that resumes with the
	# prologue already behind it must not start black, slumped and rolled, which is
	# exactly what happened when the director always ran the wake first.
	if next_step() == &"wake":
		_ui.fade.set_opaque()
		_player.set_wake_pose(1.0)
		_player.set_camera_roll(_player.wake_camera_roll)
	else:
		_prepare_resume()
	sync_player_locks()

	if not _load_start_location():
		return
	if not _save_problem.is_empty():
		_announce_save_problem()
	if autostart:
		start()


## Loads the room the catalog declares as the start of the game. Shared by a new game
## and by a save that has no `world` block (nothing to place).
func _load_start_location() -> bool:
	var start_entry := _catalog.get_start()
	if start_entry == null:
		push_error("OpeningSequence: the location catalog declares no start location.")
		return false
	# The expected id is part of the transaction: a scene that declares a different
	# location must fail here rather than put the player in one room and the story in
	# another.
	if not _locations.load_location(
		start_entry.scene, start_entry.spawn, _player, start_entry.location_id
	):
		push_error(
			"OpeningSequence: the start location '%s' failed to load." % start_entry.location_id
		)
		return false
	_game_state().set_flag(
		StoryFlags.CURRENT_LOCATION, _locations.get_current().location_id
	)
	return true


## Starts the authored prologue. Safe to call once, after `_ready`.
##
## This is also the resume entry point: the steps are chosen from the story flags, so
## a save that restores the flags restores the position. The name is `start` because
## from the director's point of view there is nothing else to call.
func start() -> void:
	_run_opening()


## Puts the world back into the state the wake beat would have left behind, for a
## game that resumes after it. Everything here is derived from "the wake is done",
## not remembered separately.
func _prepare_resume() -> void:
	_restore_resume_look()
	_ui.fade.set_clear()


## The visible half of a resume: stand up, un-roll the view, hand over control and put
## the saved objective back on the HUD. Separate from the fade because a save being
## restored at boot fades in *after* the room is placed.
func _restore_resume_look() -> void:
	_control_allowed = true
	_player.set_wake_pose(0.0)
	_player.set_camera_roll(0.0)
	# The HUD shows whatever the saved objective says. A flag that is already set
	# never emits `story_flag_changed`, so nothing else would put it on screen.
	var objective := String(_game_state().get_flag(StoryFlags.OBJECTIVE_KEY, ""))
	if _hud != null and not objective.is_empty():
		_hud.set_objective(objective)


# --- Saving and restoring ---------------------------------------------------
#
# What a save contains and why is ADR 0005; what lives here is the half only the
# director can do - deciding that the world is at a checkpoint, and putting a restored
# room back on screen. The bytes are `SaveManager`'s business.


## Connects to the save autoload, if this host has one. A test that never creates it
## gets a director that simply does not save.
func _bind_save() -> void:
	var save := get_node_or_null(^"/root/Save")
	if save == null:
		return
	_save = save
	if _save.has_method("bind_world"):
		# The room, the player and the dialogue controller are children of the same
		# node the director is on; that node is what a save describes.
		_save.bind_world(get_parent())


func can_save() -> bool:
	return _save != null


## Writes a checkpoint. Only called at beat boundaries - after a step finished, after a
## location was entered, when the prologue handed over - so nothing mid-flight ever
## has to be serialisable.
func autosave(why: String = "") -> Dictionary:
	if not autosave_enabled or _save == null or not _save.has_method("save_game"):
		return {}
	var result: Dictionary = _save.save_game()
	if result.get("ok", false) != true:
		push_error(
			"OpeningSequence: the checkpoint after '%s' was not written: %s"
			% [why, String(result.get("detail", ""))]
		)
	return result


## Reads the save and applies it, if there is one. Returns the `world` block (which may
## be empty) and sets `_restored_from_save`. A file that cannot be trusted is refused
## with the reason kept for `_announce_save_problem()`; the session is untouched.
func _restore_save() -> Dictionary:
	_restored_from_save = false
	if _save == null or not _save.has_method("load_game") or not _save.has_save():
		return {}
	var result: Dictionary = _save.load_game()
	if result.get("ok", false) != true:
		_save_problem = result
		push_error(
			"OpeningSequence: the save was refused (%s): %s"
			% [String(result.get("reason", "")), String(result.get("detail", ""))]
		)
		return {}
	_restored_from_save = true
	var world: Variant = result.get("world", {})
	return world if world is Dictionary else {}


## Puts a restored session on screen: the room the save names, the player where they
## stood, then a fade in and the first pending step.
func _start_from_save(world: Dictionary) -> void:
	_ui.fade.set_opaque()
	_restore_resume_look()
	if not _load_saved_world(world):
		_load_start_location()
	sync_player_locks()
	if autostart:
		_fade_in_and_start()


func _load_saved_world(world: Dictionary) -> bool:
	if world.is_empty():
		return false
	var location_id := StringName(String(world.get("location_id", "")))
	var entry := _catalog.get_entry(location_id) if _catalog != null else null
	if entry == null:
		push_error(
			"OpeningSequence: the save names location '%s', which the catalog does not describe."
			% location_id
		)
		return false
	var spawn := StringName(String(world.get("spawn", "")))
	if not _locations.load_location(entry.scene, spawn, _player, location_id):
		push_error(
			"OpeningSequence: the save's location '%s' (spawn '%s') could not be entered."
			% [location_id, spawn]
		)
		return false
	_game_state().set_flag(StoryFlags.CURRENT_LOCATION, location_id)
	if world.has("position"):
		_player.teleport(_saved_transform(world))
	return true


## Position and facing as a transform. `teleport()` reads the facing off the basis, so
## the player comes back looking where they were looking.
func _saved_transform(world: Dictionary) -> Transform3D:
	var position := _vec3(world.get("position", null))
	var basis := Basis.IDENTITY
	var facing := _vec3(world.get("facing", null))
	if facing.length_squared() > 0.0001:
		basis = Basis.looking_at(facing, Vector3.UP)
	return Transform3D(basis, position)


func _vec3(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.ZERO
	var items: Array = value
	return Vector3(float(items[0]), float(items[1]), float(items[2]))


func _fade_in_and_start() -> void:
	await _ui.fade.fade_from_black(0.6)
	start()


## Tells the player, on screen, that their save could not be read and what happened to
## it. A silent reset is the failure mode ADR 0005 exists to prevent.
func _announce_save_problem() -> void:
	if _ui == null or _ui.end_card == null:
		return
	var detail := String(_save_problem.get("detail", ""))
	var body := "%s\n%s" % [detail, L10n.t(SAVE_ERROR_ADVICE_KEY)]
	var hint := ""
	var quarantined_to := String(_save_problem.get("quarantined_to", ""))
	if not quarantined_to.is_empty():
		hint = L10n.t(SAVE_ERROR_QUARANTINE_KEY, {"path": quarantined_to})
	_ui.end_card.present(L10n.t(SAVE_ERROR_TITLE_KEY), body, hint)
	await wait_seconds(SAVE_NOTICE_SECONDS)
	_ui.end_card.dismiss()


## Hands control to the player without running the authored beats.
##
## The beats normally release the player during the wake, so a start that skips them
## (a test, or a future debug entry point) would otherwise leave the player frozen
## and the interaction controller switched off. This is the supported way to say
## "the room is live, nothing authored is happening".
func allow_player_control() -> void:
	_control_allowed = true
	sync_player_locks()


func _resolve_nodes() -> bool:
	_player = get_node_or_null(player_path) as PlayerController
	_interaction = get_node_or_null(interaction_path) as InteractionController
	_ui = get_node_or_null(ui_path) as GameUI
	_dialogue = get_node_or_null(dialogue_path) as DialogueController
	_locations = get_node_or_null(location_host_path) as LocationHost
	_companion = get_node_or_null(companion_path) as CompanionController
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


## Runs the prologue from wherever the flags say it is.
##
## The loop is deliberately dumb: it asks `next_step()` once per iteration and runs
## what it gets. Nothing between iterations is remembered, so an interrupted run and
## a fresh run with the same flags do the same thing - which is what "recoverable"
## means here, before there is a save file to prove it.
func _run_opening() -> void:
	var index := _first_pending_step()
	while index < STEPS.size():
		await _run_step(STEPS[index])
		# A step boundary is the one moment where nothing is mid-flight, which is what
		# makes it a legal save point (ADR 0005 §4). It is also what makes quitting in
		# the middle of the prologue cost the player one beat instead of the run.
		autosave(String(STEPS[index]))
		index += 1
	_after_opening()


## Index into `STEPS` of the first step the flags say is not done; `STEPS.size()`
## when the prologue is over.
func _first_pending_step() -> int:
	for index in STEPS.size():
		if not is_step_done(STEPS[index]):
			return index
	return STEPS.size()


## True when the flag that proves `step` happened is set.
##
## This table is the prologue's only memory. Two steps share `met_q` because the
## wake has no flag of its own and cannot outlive Q's first line; `substitute` ends
## at `class_dismissed` rather than at `n_arrived`, because N arriving without the
## conversation that dismisses the class would leave the door locked forever.
func is_step_done(step: StringName) -> bool:
	match step:
		&"wake", &"q_wake":
			return _has_flag(StoryFlags.MET_Q)
		&"bag":
			return _has_flag(StoryFlags.TEXTBOOK_MISSING)
		&"expectation":
			return _has_flag(StoryFlags.EXPECTATION_PLAYED)
		&"bell":
			return _has_flag(StoryFlags.BELL_RUNG)
		&"substitute":
			return _has_flag(StoryFlags.CLASS_DISMISSED)
	return true


## Re-applies the one exit prompt the story rewrites. The work lives in
## `LocationFlow`, but the director is the node a test (and any future debug tool)
## already holds, so this stays as the entry point it always was.
func update_exit_prompt() -> void:
	if _flow != null:
		_flow.update_exit_prompt()


## The step that comes next, or `&""` when the prologue is over. Public because it
## is the question a save system, a debug overlay, and a test all want to ask.
func next_step() -> StringName:
	var index := _first_pending_step()
	if index >= STEPS.size():
		return &""
	return STEPS[index]


func _run_step(step: StringName) -> void:
	match step:
		&"wake":
			await _beat_wake()
		&"q_wake":
			await _beat_q_wake()
		&"bag":
			await _beat_bag()
		&"expectation":
			await _beat_expectation()
		&"bell":
			await _beat_bell()
		&"substitute":
			await _beat_substitute()
		_:
			push_error("OpeningSequence: unknown step '%s'." % step)


## After the prologue: what the player can see has to match the flags they arrived
## with, whether they got here by playing or by resuming.
func _after_opening() -> void:
	if _flow != null:
		_flow.update_exit_prompt()
	autosave(&"opening_done")


## Beat A: wake up. Slow fade in, camera roll settling, body straightening.
func _beat_wake() -> void:
	_wake_audio.play()
	await _ui.fade.fade_from_black(WAKE_FADE_SECONDS)
	_player.settle_wake_pose(WAKE_SETTLE_SECONDS)
	_player.settle_camera_roll(WAKE_SETTLE_SECONDS)
	await wait_seconds(0.4)
	_control_allowed = true
	sync_player_locks()
	if _hud != null:
		_hud.set_objective("objective.get_bearings")


## Beat B: Q starts talking without being asked.
func _beat_q_wake() -> void:
	await wait_seconds(0.9)
	await begin_beat()
	await play_conversation(&"q_wake")
	end_beat()


## Beats C/D: the bag reminder runs in the background while the player looks around.
## The step ends when the bag has been searched - or when the fallback limit runs
## out, because a player who never opens the bag still has to reach the lesson.
func _beat_bag() -> void:
	_start_bag_reminder()
	await _wait_for_flag(StoryFlags.TEXTBOOK_MISSING, BAG_WAIT_LIMIT)


## Beat E: expectation, clearly framed as imagination. Skipped when the bag was
## never searched, which is what the fallback above produces.
func _beat_expectation() -> void:
	if not _has_flag(StoryFlags.TEXTBOOK_MISSING) or _has_flag(StoryFlags.EXPECTATION_PLAYED):
		return
	await wait_seconds(EXPECTATION_LEAD_IN)
	await begin_beat()
	_ui.overlay.show_localized_overlay("overlay.expect_title", "overlay.expect_body")
	await wait_seconds(0.7)
	await play_conversation(&"expected_b")
	_ui.overlay.show_localized_overlay("overlay.deny_title", "overlay.deny_body")
	await wait_seconds(EXPECTATION_DISCLAIMER_SECONDS)
	await _ui.overlay.hide_overlay()
	_game_state().set_flag(StoryFlags.EXPECTATION_PLAYED, true)
	end_beat()


func _beat_bell() -> void:
	if _has_flag(StoryFlags.BELL_RUNG):
		return
	await begin_beat()
	_game_state().set_flag(StoryFlags.BELL_RUNG, true)
	_bell_audio.play()
	_hud.set_objective("objective.bell")
	await wait_seconds(1.0)
	await play_conversation(&"bell_moment")
	end_beat()


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

	# A resumed game may already have walked N in; the flag says so, and walking the
	# same path again would put a second N at the front of the room.
	if not _has_flag(StoryFlags.N_ARRIVED):
		await begin_beat()
		actor.place_at(points[0], points[1])
		end_beat()

		await actor.walk_along(points.slice(1))

	await begin_beat()
	_game_state().set_flag(StoryFlags.N_ARRIVED, true)
	await wait_seconds(0.4)
	await play_conversation(&"n_class")
	end_beat()
	_flow.update_exit_prompt()


func _start_bag_reminder() -> void:
	if _has_flag(StoryFlags.TEXTBOOK_MISSING):
		return
	await wait_seconds(BAG_REMINDER_SECONDS)
	if _has_flag(StoryFlags.TEXTBOOK_MISSING) or _has_flag(StoryFlags.BELL_RUNG) or is_slice_finished():
		return
	await begin_beat()
	await play_conversation(&"q_bag_reminder")
	end_beat()


# --- Interaction routing ----------------------------------------------------


func _on_activation_requested(interactable: Interactable) -> void:
	if _dialogue.is_busy() or is_slice_finished():
		return

	var exit := interactable as LocationExit
	if exit != null:
		_handle_exit(exit)
		return

	# A room that stages its own moment (see StagedInteractable) is asked before the
	# object's declared route or text, which are then the room's to use.
	var staged := interactable as StagedInteractable
	if staged != null and staged.is_staged():
		# A staged moment owns the room while it runs (a door is still swinging, a
		# curtain still moving), even between its lines, when no dialogue is busy.
		if _beat_active:
			return
		_run_staged(staged)
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
		await begin_beat()
		await play_conversation(conversation)
		end_beat()
		if interactable.interact_id == &"q_ask_along" and _companion != null:
			_companion.resume_following()
		return

	if not String(interactable.inspection_id).is_empty():
		_dialogue.present_inspection(interactable.inspection_id)
		return

	push_error(
		"OpeningSequence: interactable '%s' declares no inspection, conversation, or exit."
		% interactable.interact_id
	)


## One staged moment: the room's handler runs inside a beat, then whatever it asked for
## afterwards (see `StagedInteractable`) - a text once the beat is over, or a transition
## that keeps the same beat, so the player never gets a frame of control in between.
func _run_staged(staged: StagedInteractable) -> void:
	await begin_beat()
	var request: Dictionary = await staged.perform(self)
	var transition: Dictionary = request.get("transition", {})
	if not transition.is_empty() and _flow != null:
		var options := transition.duplicate()
		options["beat_held"] = true
		if not options.has("label"):
			options["label"] = "staged '%s'" % staged.interact_id
		var transitioned: bool = await _flow.transition_to(
			String(transition.get("scene", "")),
			StringName(String(transition.get("spawn", ""))),
			StringName(String(transition.get("id", ""))),
			options
		)
		if not transitioned:
			var on_failure: Callable = transition.get("on_failure", Callable())
			if on_failure.is_valid():
				on_failure.call()
		return
	end_beat()
	var inspection := StringName(String(request.get("inspection", "")))
	if not String(inspection).is_empty():
		_dialogue.present_inspection(inspection)


## The body a staged moment may pose (StagedInteractable handlers run in the room and
## have no other way to reach it).
func get_player() -> PlayerController:
	return _player


func _on_target_changed(interactable: Interactable) -> void:
	if _dialogue.is_busy() or _beat_active or is_slice_finished():
		_hud.clear_prompt()
		return
	_hud.set_prompt_text(_dialogue.get_interact_prompt(interactable))


## Awaits the whole visit: the caller is done when the player is standing in the new
## room (or back where they were, if the load was refused).
func _handle_exit(exit: LocationExit) -> void:
	if _flow == null:
		return
	await _flow.handle_exit(exit)


# --- Presentation plumbing --------------------------------------------------


func play_conversation(conversation_id: StringName) -> void:
	if not _dialogue.play_conversation(conversation_id):
		return
	# `DialogueRuntime.start()` walks the graph before it returns, and three of its
	# exits finish the conversation inside that walk: a node id that does not exist,
	# a first node whose conditions are not met with nothing left after it, and the
	# step limit. In all three `conversation_finished` is emitted *before*
	# `play_conversation()` returns, so awaiting it here would wait forever — and
	# every caller awaits this inside a beat, so the player lock would never clear.
	# Ask the controller what is on screen instead of trusting the signal to be
	# ahead of us.
	if not _dialogue.is_busy():
		return
	await _dialogue.conversation_finished


## Waits `seconds` of *story* time: the clock stops while the tree is paused.
##
## `SceneTree.create_timer()` keeps counting through a pause unless it is told not to,
## and every wait in the prologue used that default. The pause menu pauses the tree, so
## the beats went on timing themselves behind it: a player who spent the bag step in
## the menu or the settings for `BAG_WAIT_LIMIT` seconds came back to a bag step that
## had already given up, and the expectation beat - which needs the bag to have been
## searched - was gone for the rest of the run. Q's bag reminder could likewise start
## its conversation while the menu was still open. The fades never had this problem:
## they are node tweens, and those already stop with the tree. Every authored wait goes
## through here so the two clocks agree.
func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


## True while an authored beat (arrival lines, scripted conversation) owns the
## frame. Passive inner voices wait for this to clear instead of talking over it.
func is_beat_active() -> bool:
	return _beat_active


## True once the end card is up: the slice is over and nothing should start.
func is_slice_finished() -> bool:
	return _flow != null and _flow.is_finished()


func begin_beat() -> void:
	while _beat_active or _dialogue.is_busy():
		await get_tree().process_frame
	_beat_active = true
	sync_player_locks()


func end_beat() -> void:
	_beat_active = false
	sync_player_locks()
	# Locking the player clears the prompt; unlocking has to put it back, because
	# the target itself may not change again for a while.
	if _interaction != null and _hud != null and not is_slice_finished():
		_on_target_changed(_interaction.get_current_target())


func _on_presentation_active_changed(_active: bool) -> void:
	sync_player_locks()


func sync_player_locks() -> void:
	if _player == null or _interaction == null:
		return
	var locked := _beat_active or _dialogue.is_busy() or is_slice_finished() or not _control_allowed
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
		if _flow != null:
			_flow.update_exit_prompt()


func _wait_for_flag(flag: StringName, limit_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < limit_seconds:
		if _has_flag(flag):
			return
		await wait_seconds(0.25)
		elapsed += 0.25


func _has_flag(flag: StringName) -> bool:
	return bool(_game_state().get_flag(flag, false))


func _game_state() -> Node:
	return get_node(^"/root/GameState")
