class_name PrologueBeats
extends RefCounted
## The authored beats of the biology-class prologue: waking up, Q coming over, the bag,
## the imagined lesson, the bell and the substitute teacher.
##
## Split out of `OpeningSequence` (issue #223). The director still decides *which* beat
## runs (`PrologueSteps`, from the story flags), holds the beat lock, plays conversations
## and owns the story clock; every wait here goes through `wait_seconds()` on it, so the
## pause menu stops the beats as it stops everything else. The director keeps its
## `_beat_*` entry points as one-line calls into this object, because they are what the
## headless tests drive.
##
## Each beat checks its own flag first and returns when the story says it already
## happened: a resumed game never sees a beat twice.

const WAKE_FADE_SECONDS := 3.0
const WAKE_SETTLE_SECONDS := 2.0
const EXPECTATION_LEAD_IN := 0.8
const EXPECTATION_DISCLAIMER_SECONDS := 2.8
## What the imagined lesson records when it reaches its recollection (`expected_b`, `rec_1`).
const RECOLLECTION_ENTRY: StringName = &"recall_set_square_sound"
const BELL_LEAD_IN := 6.0
## How much of the bell the player hears alone before Q says anything about it.
##
## `assets/audio/bell_second.wav` is 7.4 s: the four-note phrase, then the corridor's quieter
## answer. Speaking at 1.0 s cut the phrase in half and made the bell read as an alert sound;
## this lands on the second phrase, which is when someone in the room would talk over it.
## `tests/bell_sound_test.py` pins the buffer length this assumes.
const BELL_SPEAK_AFTER_SECONDS := 4.6
## Hard fallback so a player who never opens the bag still reaches the lesson.
const BAG_WAIT_LIMIT := 95.0
## How often a flag wait looks again, in story seconds.
const FLAG_POLL_SECONDS := 0.25

## The `OpeningSequence` (untyped, as `LocationFlow`'s host is).
var _director: Node = null
var _ui: GameUI = null
var _player: PlayerController = null
var _locations: LocationHost = null
var _bell_audio: AudioStreamPlayer = null
var _wake_audio: AudioStreamPlayer = null
var _flow: LocationFlow = null
var _game_state: Node = null
## Held for the life of the beats: the walk awaits, and a temporary RefCounted could be
## freed while its coroutine is suspended.
var _q_approach := QIntroApproach.new()


func _init(director: Node, ui: GameUI, player: PlayerController, locations: LocationHost,
		bell_audio: AudioStreamPlayer, wake_audio: AudioStreamPlayer, flow: LocationFlow,
		game_state: Node) -> void:
	_director = director
	_ui = ui
	_player = player
	_locations = locations
	_bell_audio = bell_audio
	_wake_audio = wake_audio
	_flow = flow
	_game_state = game_state


func _hud() -> GameHud:
	return _ui.hud if _ui != null else null


func _has_flag(flag: StringName) -> bool:
	return bool(_game_state.get_flag(flag, false))


## Waits until `flag` is set or `limit_seconds` of story time have passed. Also stops when
## the player has skipped class: nothing the prologue waits for can happen after that.
func wait_for_flag(flag: StringName, limit_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < limit_seconds:
		if _has_flag(flag) or _has_flag(StoryFlags.SKIPPED_CLASS):
			return
		await _director.wait_seconds(FLAG_POLL_SECONDS)
		elapsed += FLAG_POLL_SECONDS


## Beat A: wake up. Fade in and settle into an upright seated pose; the first deliberate
## movement is what starts the existing get-up transition.
func wake() -> void:
	_wake_audio.play()
	await _ui.fade.fade_from_black(WAKE_FADE_SECONDS)
	var pose_tween := _player.settle_wake_seated_pose(WAKE_SETTLE_SECONDS)
	_player.settle_camera_roll(WAKE_SETTLE_SECONDS)
	if pose_tween != null:
		await pose_tween.finished
	await _director.wait_seconds(0.4)
	_director.allow_player_control()
	if _hud() != null:
		_hud().set_objective("objective.get_bearings")


## Beat B: Q comes over before speaking. The room owns Q's initial placement and
## may provide a QOpeningTalk marker for the final composition (#159). This beat
## never changes the protagonist's wake/seat pose, camera or location (#121).
func q_wake() -> void:
	if _has_flag(StoryFlags.MET_Q):
		return
	# Hold the existing beat lock during the approach as well as during dialogue:
	# an early E/click must not start a second q_wake while Q is coming over.
	await _director.begin_beat()
	if _has_flag(StoryFlags.MET_Q):
		_director.end_beat()
		return
	await _director.wait_seconds(0.9)
	if await _q_approach.run(_locations.get_current(), _player, _director):
		await _director.play_conversation(&"q_wake")
	# The player chose to picture B when Q described her (`q_b_looks`, `imagine_b`):
	# the imagined lesson starts the moment Q's talk ends, inside the same beat. The choice
	# sits in `q_wake` after Q has described B, so it already implies the #171 order; it
	# does not wait on `q_first_talk_done`, which another listener of the same
	# `conversation_finished` emission writes.
	if _has_flag(StoryFlags.IMAGINE_B_CHOSEN) and not _has_flag(StoryFlags.EXPECTATION_PLAYED):
		await _imagine_b()
	_director.end_beat()


## Beats C/D: the player looks around; nobody prompts them about the bag.
## If they check the bag, Q is just beside the desk. Let him ask before the imagined
## lesson starts, rather than making the player catch him in its short lead-in.
## If they never check, the fallback claims neither a search nor a conversation. A
## player who left through the rear door meanwhile closed the step that way instead.
func bag() -> void:
	await wait_for_flag(StoryFlags.TEXTBOOK_MISSING, BAG_WAIT_LIMIT)
	if _has_flag(StoryFlags.SKIPPED_CLASS):
		return
	if not _has_flag(StoryFlags.TEXTBOOK_MISSING):
		_game_state.set_flag(StoryFlags.BAG_WAIT_EXPIRED, true)
		return
	if not _director.is_b_introduced() or _has_flag(StoryFlags.Q_BOOK_TALK_DONE):
		return
	# Wait for the bag text to close. If the player managed to ask Q in the
	# meantime, the shared reply has already played and should not start again.
	await _director.begin_beat()
	if not _has_flag(StoryFlags.Q_BOOK_TALK_DONE):
		await _director.play_conversation(&"q_after_bag")
	_director.end_beat()


## Beat E: expectation, clearly framed as imagination. It plays only when the player
## chose to picture B after Q described her, and normally that already happened at the
## end of the Q beat. This step is the fallback for a run that stopped in between (a Q talk
## started from the room rather than the approach, or a reload): it plays the scene once
## if it was chosen and never played. Otherwise the step is recorded as skipped
## (`expectation_skipped`), so it stays closed for the rest of the run.
func expectation() -> void:
	if _has_flag(StoryFlags.EXPECTATION_PLAYED):
		return
	# B speaks in this scene, so it also waits for Q to have told the player about the
	# lesson first (#171). A Q talk that never finished passes the scene over.
	if not _has_flag(StoryFlags.IMAGINE_B_CHOSEN) or not _director.is_b_introduced():
		_game_state.set_flag(StoryFlags.EXPECTATION_SKIPPED, true)
		return
	await _director.wait_seconds(EXPECTATION_LEAD_IN)
	await _director.begin_beat()
	await _imagine_b()
	_director.end_beat()


## The imagined lesson itself, inside a beat the caller holds: the title card, the
## subjective conversation (whose hubs always offer a way out), the disclaimer.
func _imagine_b() -> void:
	if _director.has_method("set_score_imagining"):
		_director.set_score_imagining(true)
	_ui.overlay.show_localized_overlay("overlay.expect_title", "overlay.expect_body")
	await _director.wait_seconds(0.7)
	await _director.play_conversation(&"expected_b")
	# Every hub offers a way out of the fantasy; leaving before the recollection
	# (`rec_1`) means the set-square sound was never remembered.
	var narrative := _director.get_node_or_null(^"/root/NarrativeState")
	if narrative != null and not narrative.has_entry(RECOLLECTION_ENTRY):
		_game_state.set_flag(StoryFlags.EXPECTATION_LEFT_EARLY, true)
	_ui.overlay.show_localized_overlay("overlay.deny_title", "overlay.deny_body")
	await _director.wait_seconds(EXPECTATION_DISCLAIMER_SECONDS)
	await _ui.overlay.hide_overlay()
	_game_state.set_flag(StoryFlags.EXPECTATION_PLAYED, true)
	if _director.has_method("set_score_imagining"):
		_director.set_score_imagining(false)


func bell() -> void:
	if _has_flag(StoryFlags.BELL_RUNG):
		return
	await _director.begin_beat()
	_game_state.set_flag(StoryFlags.BELL_RUNG, true)
	_bell_audio.play()
	_hud().set_objective("objective.bell")
	# Q speaks into the bell's tail rather than over its head. The phrase is 7.4 s long -
	# four struck bars, then the corridor answering - so the wait is most of it: long enough
	# that the player hears a bell and not an alarm, short enough that nobody is left standing
	# in a silent room wondering whether the beat stalled.
	await _director.wait_seconds(BELL_SPEAK_AFTER_SECONDS)
	await _director.play_conversation(&"bell_moment")
	_director.end_beat()


func substitute() -> void:
	# The class is already dismissed: N's lesson is over, and the player may not even be
	# in the room N is in any more. Nothing to look for. The same once they skipped it.
	if _has_flag(StoryFlags.CLASS_DISMISSED) or _has_flag(StoryFlags.SKIPPED_CLASS):
		return
	var location := _locations.get_current()
	if location == null:
		push_error("OpeningSequence: no location loaded for the substitute beat.")
		return
	var actor := location.find_actor(NPresence.ACTOR_ID)
	if actor == null:
		push_error("OpeningSequence: the classroom has no actor with npc_id 'n'.")
		return
	var points := location.get_waypoint_path(NPresence.ENTRY_PATH)
	if points.size() < 2:
		push_error("OpeningSequence: 'NEntryPath' needs at least two markers.")
		return

	# A resumed game may already have walked N in; the flag says so, and walking the
	# same path again would put a second N at the front of the room. `NPresence` has
	# already put that N at the lectern, when the room was entered.
	if not _has_flag(StoryFlags.N_ARRIVED):
		await _director.begin_beat()
		actor.place_at(points[0], points[1])
		_director.end_beat()

		await actor.walk_along(points.slice(1))
		# N walks in while the player still has the controls; the rear door may have been
		# taken meanwhile, and N's class must not start in the corridor.
		if _has_flag(StoryFlags.SKIPPED_CLASS):
			return

	await _director.begin_beat()
	_game_state.set_flag(StoryFlags.N_ARRIVED, true)
	await _director.wait_seconds(0.4)
	await _director.play_conversation(&"n_class")
	_director.end_beat()
	_flow.update_exit_prompt()

