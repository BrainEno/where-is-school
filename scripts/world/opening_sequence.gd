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

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")

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
## When the biology teacher B may be presented, and whether a room's B is shown (#171).
var _b_presence: BPresence = null
## Puts N back at the lectern in a room built after she has walked in (#166).
var _n_presence: NPresence = null
## Puts Q back on his talk spot in a room built after his first talk (`met_q`).
var _q_presence: QPresence = null
## Camera focus on important interactions (see `CameraShot`).
var _focus: CameraFocusDirector = null
## What using an interactable does: an exit, a staged moment, a conversation, a text.
var _interactions: OpeningInteractions = null
## The authored beats themselves (`PrologueBeats`); the `_beat_*` methods call into it.
var _beats: PrologueBeats = null
## Checkpoints, the boot-time restore and the unreadable-save notice (`OpeningSave`).
var _saves := OpeningSave.new()
## Autosave is on by default: the game has no menu, so a checkpoint the player did not
## ask for is the only thing standing between them and losing the session (ADR 0005).
var autosave_enabled: bool = true

## The prologue, in order. Each step is identified by the flag that proves it is
## done; see `next_step()` and `PrologueSteps`.
const STEPS: Array[StringName] = PrologueSteps.STEPS


func _ready() -> void:
	if not _resolve_nodes():
		return
	_dialogue.presentation_active_changed.connect(_on_presentation_active_changed)
	_dialogue.camera_focus_requested.connect(_on_camera_focus_requested)
	_dialogue.line_presented.connect(_on_line_presented)
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
		OfflineDiagnostics.note("assets.load_failed", {"kind": "locations"})
		push_error("OpeningSequence: %s" % _catalog.describe_errors())
	_focus = CameraFocusDirector.new(_player.camera_rig)
	_locations.player_recovered.connect(_on_player_recovered)
	_flow = LocationFlow.new(
		self, _locations, _catalog, _game_state(), _ui, _player, _dialogue, _companion
	)
	# Connected before the save is read and the first room is loaded, so both are seen.
	_b_presence = BPresence.new(_game_state(), _locations, _dialogue)
	_n_presence = NPresence.new(_game_state(), _locations)
	_q_presence = QPresence.new(_game_state(), _locations)
	_interactions = OpeningInteractions.new(
		self, _dialogue, _flow, _focus, _companion, _game_state()
	)
	_beats = PrologueBeats.new(
		self, _ui, _player, _locations, _bell_audio, _wake_audio, _flow, _game_state()
	)

	_saves.bind(self, get_parent())

	# A save, if the host has one, is applied *before* anything is asked about the
	# story: `next_step()` reads flags, so restoring after it would resume from the
	# wrong step. A file that cannot be trusted is refused loudly and the run starts
	# from the beginning - the file itself is kept (ADR 0005 §6).
	var restored := _saves.restore()
	if _saves.restored:
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
	if not _saves.problem.is_empty():
		_saves.announce_problem(_ui, self)
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
# What a save contains and why is ADR 0005; the director decides *when* the world is at a
# checkpoint, and `OpeningSave` does the rest. The bytes are `SaveManager`'s business.


func can_save() -> bool:
	return _saves.can_save()


## Writes a checkpoint. Only called at beat boundaries - after a step finished, after a
## location was entered, when the prologue handed over - so nothing mid-flight ever
## has to be serialisable.
func autosave(why: String = "") -> Dictionary:
	return _saves.autosave(why, autosave_enabled)


## Puts a restored session on screen: the room the save names, the player where they
## stood, then a fade in and the first pending step.
func _start_from_save(world: Dictionary) -> void:
	_ui.fade.set_opaque()
	_restore_resume_look()
	if not _saves.load_world(world, _catalog, _locations, _player, _game_state()):
		_load_start_location()
	sync_player_locks()
	if autostart:
		_fade_in_and_start()


func _fade_in_and_start() -> void:
	await _ui.fade.fade_from_black(0.6)
	start()


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
		var step := STEPS[index]
		index += 1
		# Asked again for every step, not only for the first: a step the flags already
		# prove is over is never run a second time, whatever the steps before it did.
		if is_step_done(step):
			continue
		await _run_step(step)
		# A step boundary is the one moment where nothing is mid-flight, which is what
		# makes it a legal save point (ADR 0005 §4). It is also what makes quitting in
		# the middle of the prologue cost the player one beat instead of the run.
		autosave(String(step))
	_after_opening()


## Index into `STEPS` of the first step the flags say is not done; `STEPS.size()`
## when the prologue is over.
func _first_pending_step() -> int:
	return PrologueSteps.first_pending(_has_flag)


## True when `step` is behind the player: its own proof is set, or the proof of any step
## after it is. Progress only moves forward; the table is `PrologueSteps`.
func is_step_done(step: StringName) -> bool:
	return PrologueSteps.is_done(step, _has_flag)


## Re-applies the one exit prompt the story rewrites. The work lives in
## `LocationFlow`, but the director is the node a test (and any future debug tool)
## already holds, so this stays as the entry point it always was.
func update_exit_prompt() -> void:
	if _flow != null:
		_flow.update_exit_prompt()


## The step that comes next, or `&""` when the prologue is over. Public because it
## is the question a save system, a debug overlay, and a test all want to ask.
func next_step() -> StringName:
	return PrologueSteps.next(_has_flag)


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


# The beats are `PrologueBeats`; these are the entry points `_run_step()` and the
# headless tests call.


## Beat A: wake up, then hand over control.
func _beat_wake() -> void:
	await _beats.wake()


## Beat B: Q walks over (`QIntroApproach`) and starts talking.
func _beat_q_wake() -> void:
	await _beats.q_wake()


## Beats C/D: the bag, its reminder, and the fallback for a bag never searched.
func _beat_bag() -> void:
	await _beats.bag()


## Beat E: the imagined lesson, or its recorded skip.
func _beat_expectation() -> void:
	await _beats.expectation()


func _beat_bell() -> void:
	if is_step_done(&"bell"):
		return
	await _beats.bell()
	# Q finishes his bell lines before moving back to his desk. Settle the room
	# before the director saves the bell checkpoint or starts N's entrance.
	await begin_beat()
	await _q_presence.return_to_classroom_seats(_player)
	end_beat()


## N walks in and dismisses the class.
func _beat_substitute() -> void:
	await _beats.substitute()


## True once Q's first conversation has run to its end: the gate for presenting B.
func is_b_introduced() -> bool:
	return _b_presence != null and _b_presence.is_introduced()


## True when a room's B may be visible: introduced, then explicitly brought in.
func is_b_on_stage() -> bool:
	return _b_presence != null and _b_presence.is_on_stage()


## The explicit story trigger for B's entrance; see `BPresence.present()`. No beat of
## this slice calls it - B is talked about and imagined, never on stage.
func present_b(position_point: Vector3, facing_point: Vector3 = Vector3.ZERO) -> bool:
	return _b_presence != null and _b_presence.present(position_point, facing_point)


# --- Interaction routing ----------------------------------------------------


## Routed by `OpeningInteractions`: exits, staged moments, conversations and texts.
func _on_activation_requested(interactable: Interactable) -> void:
	if _interactions != null:
		_interactions.activate(interactable)


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
	# N's walk leaves the player in control (including the rear-door route). Check
	# the seats once more under the lesson lock, also for older post-bell saves.
	if conversation_id == &"n_class" and _beat_active \
			and _has_flag(StoryFlags.BELL_RUNG) and not is_step_done(&"substitute"):
		await _q_presence.return_to_classroom_seats(_player)
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
## the menu or the settings for `PrologueBeats.BAG_WAIT_LIMIT` seconds came back to a bag step that
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


func _on_player_recovered() -> void:
	_focus.clear()
	if _player.camera_rig != null:
		_player.camera_rig.release_frame(0.0)
	# The next scan can find a target at the recovered position, not in the void.
	_interaction.set_enabled(false)
	_hud.clear_prompt()
	sync_player_locks()


func _on_presentation_active_changed(active: bool) -> void:
	if not active and _focus != null:
		# The beat can still hold the player (e.g. the bell after the last line).
		# A dialogue glance ends with the presentation, not with that larger lock.
		_focus.end_glance()
	sync_player_locks()


func sync_player_locks() -> void:
	if _player == null or _interaction == null:
		return
	var locked := _beat_active or _dialogue.is_busy() or is_slice_finished() or not _control_allowed
	_player.set_control_enabled(not locked)
	_interaction.set_enabled(not locked)
	if locked and _hud != null:
		_hud.clear_prompt()
	if _focus != null:
		_focus.on_lock_changed(locked)


## A conversation's `camera_focus` effect: glance at that interactable of the current
## room while the next line is read. A target the room does not have is an authoring
## mistake; the line still plays, just without the look.
func _on_camera_focus_requested(target: StringName) -> void:
	if _focus == null or _locations == null:
		return
	var location := _locations.get_current()
	var subject: Interactable = location.find_interactable(target) if location != null else null
	if subject == null:
		push_warning("OpeningSequence: camera_focus target '%s' is not in this room." % target)
		return
	_focus.glance(subject)


func _on_line_presented(_line: Dictionary) -> void:
	if _focus != null:
		_focus.on_line_presented()


## The camera focus director (tests and location changes use it).
func get_camera_focus() -> CameraFocusDirector:
	return _focus


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


## Waits until `flag` is set or `limit_seconds` of story time have passed (the bag
## step's fallback clock; `PrologueBeats.wait_for_flag`).
func _wait_for_flag(flag: StringName, limit_seconds: float) -> void:
	await _beats.wait_for_flag(flag, limit_seconds)


func _has_flag(flag: StringName) -> bool:
	return bool(_game_state().get_flag(flag, false))


func _game_state() -> Node:
	return get_node(^"/root/GameState")
