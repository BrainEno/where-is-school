class_name StoryFlags
extends RefCounted
## Stable identifiers for the opening slice's gameplay flags.
##
## GameState stores these as named values. The ids are save-data contracts:
## rename one only with a migration plan. Flag values may be bool, String, or
## int; the type each flag carries is documented next to the constant.

# --- Beat bookkeeping -------------------------------------------------------
## bool: the first conversation with Q has started.
const MET_Q: StringName = &"met_q"
## bool: Q's first conversation (`q_wake`) has run to its last line. `met_q` is written by
## its first line; this one is written by `OpeningSequence` when that conversation
## finishes, and is `false` (present, not absent) while it is still on screen. It is the
## gate for anything that presents the biology teacher B - the imagined `expected_b` scene
## included: the player hears about the lesson and its teacher from Q first (#171).
## Absent in saves written before #171; `BPresence` then reads `met_q` instead (a
## checkpoint is never taken in the middle of a conversation) and writes nothing back.
const Q_FIRST_TALK_DONE: StringName = &"q_first_talk_done"
## bool: B has been brought into the room by an explicit story trigger
## (`OpeningSequence.present_b()`). No beat of this slice sets it: B is talked about, and
## imagined, but never on stage. A room that ever holds an actor with npc_id `b` keeps it
## hidden and disabled until this is set and Q's first conversation counts as finished
## (`BPresence.is_introduced()`) (#171).
const B_ON_STAGE: StringName = &"b_on_stage"
## bool: the schoolbag has been searched and the textbook is missing.
const TEXTBOOK_MISSING: StringName = &"textbook_missing"
## bool: the bag step's fallback ran out before the bag was searched. Closes the bag
## step without claiming a search: `textbook_missing` stays false and nothing is
## recorded. Absent (false) in saves written before #144; the director then reads the
## later steps' flags instead (`OpeningSequence.is_step_done()`).
const BAG_WAIT_EXPIRED: StringName = &"bag_wait_expired"
## bool: the player inspected the wooden set square.
const SAW_SET_SQUARE: StringName = &"saw_set_square"
## bool: the subjective expectation beat has been presented.
const EXPECTATION_PLAYED: StringName = &"expectation_played"
## bool: the expectation beat was passed over because the player had not chosen to
## picture B (before round 7: because the bag had not been searched) when its turn came.
## Closes the step without claiming the scene was seen. Absent (false) in saves written
## before #144, like `bag_wait_expired`.
const EXPECTATION_SKIPPED: StringName = &"expectation_skipped"
## bool: the imagined lesson ended before its recollection of the set square
## (`expected_b`, `rec_1`): the player stepped out of the fantasy at one of B's questions.
## Later lines that lean on that remembered sound (`q_after_dismissal`) stay closed. Absent
## (false) in saves written before round 7, when the scene always reached it.
const EXPECTATION_LEFT_EARLY: StringName = &"expectation_left_early"
## bool: the second bell has rung.
const BELL_RUNG: StringName = &"bell_rung"
## bool: substitute N has reached the front of the classroom.
const N_ARRIVED: StringName = &"n_arrived"
## bool: N has allowed the class to leave for free activity.
const CLASS_DISMISSED: StringName = &"class_dismissed"
## bool: the player left the classroom for the walkway.
const LEFT_CLASSROOM: StringName = &"left_classroom"
## bool: the player has stepped out of the teaching block into the front yard (前操场).
const FRONT_YARD_ARRIVED: StringName = &"front_yard_arrived"
## bool: the player walked the north grove (北面枯树小道) between the two yards (round 26).
const NORTH_GROVE_VISITED: StringName = &"north_grove_visited"
## bool: the player went out through the school gate's side door into the street.
const LEFT_SCHOOL: StringName = &"left_school"
## bool: the first street conversation has played.
const STREET_ARRIVED: StringName = &"street_arrived"
## bool: the camera has been noted during a first wall look. Later looks skip
## that observation but keep the opening and route-tab response. Absent in old saves.
const STREET_WALL_SEEN: StringName = &"street_wall_seen"
## bool: the first residential-area conversation has played.
const RESIDENTIAL_ARRIVED: StringName = &"residential_arrived"
## bool: the green animal has been seen at least once.
const ANIMAL_SEEN: StringName = &"animal_seen"
## bool: the player has walked from the residential courtyard into the alley.
const ALLEY_ARRIVED: StringName = &"alley_arrived"
## bool: the player has reached the open playground.
const PLAYGROUND_ARRIVED: StringName = &"playground_arrived"
## bool: one of the playground checks has been attempted at least once.
const PLAYGROUND_CHECKED: StringName = &"playground_checked"
## bool: the shed door's boundary check passed - the gap by the hinges was found (`pg_shed`).
const PLAYGROUND_SHED_OPEN: StringName = &"playground_shed_open"
## bool: the shed door's boundary check failed - the door held, the hasp was looked at (`pg_shed`).
const PLAYGROUND_SHED_LOOKED: StringName = &"playground_shed_looked"
## bool: the duty rota on the shed was read in full - nine rows (`pg_shed`).
const PLAYGROUND_ROTA_READ: StringName = &"playground_rota_read"
## bool: the duty rota was miscounted - rain had smudged two rows together (`pg_shed`).
const PLAYGROUND_ROTA_SMUDGED: StringName = &"playground_rota_smudged"
## bool: reaching behind the stuck ball found the ledge and what lies on it (`pg_ball`).
const PLAYGROUND_TAG_FOUND: StringName = &"playground_tag_found"
## bool: the ball stayed stuck - either of `pg_ball`'s checks failed.
const PLAYGROUND_BALL_STUCK: StringName = &"playground_ball_stuck"
## bool: the shadow by the shed was measured against the gap (`pg_ball`).
const PLAYGROUND_SHADOW_MEASURED: StringName = &"playground_shadow_measured"
## bool: the player stayed at their desk after N announced the free period.
const FREE_PERIOD_STAYED: StringName = &"free_period_stayed"
## bool: the player chose to get up and leave after N announced the free period.
const FREE_PERIOD_LEAVING: StringName = &"free_period_leaving"
## bool: Q is walking with the player. Set the first time the classroom is left.
const Q_COMPANION: StringName = &"q_companion"
## bool: the player paused at the corridor window to let part of the period pass.
const CORRIDOR_WAITED: StringName = &"corridor_waited"
## String: the directory tab points to the glass doors (glass) or the stairs (stair).
## Missing in old saves and before marking: the tab is centered.
const CORRIDOR_DIRECTORY_TAB: StringName = &"corridor_directory_tab"
## bool: optional local mechanisms, restored at their final poses on Continue and return.
const CORRIDOR_SCREEN_RAISED: StringName = &"corridor_screen_raised"
const CORRIDOR_BELL_TESTED: StringName = &"corridor_bell_tested"
## Optional school doors: aligned opens the latch; unclear enables the manual correction.
const ANNEX_ARCHIVE_ALIGNED: StringName = &"annex.archive.aligned"
const ANNEX_ARCHIVE_UNCLEAR: StringName = &"annex.archive.unclear"
const ANNEX_PLAN_ROOM_ALIGNED: StringName = &"annex.plan_room.aligned"
const ANNEX_PLAN_ROOM_UNCLEAR: StringName = &"annex.plan_room.unclear"
const ANNEX_PROJECTION_ROOM_ALIGNED: StringName = &"annex.projection_room.aligned"
const ANNEX_PROJECTION_ROOM_UNCLEAR: StringName = &"annex.projection_room.unclear"
const ANNEX_COMPUTER_ROOM_ALIGNED: StringName = &"annex.computer_room.aligned"
const ANNEX_COMPUTER_ROOM_UNCLEAR: StringName = &"annex.computer_room.unclear"
const ANNEX_VACANT_OFFICE_ALIGNED: StringName = &"annex.vacant_office.aligned"
const ANNEX_VACANT_OFFICE_UNCLEAR: StringName = &"annex.vacant_office.unclear"
const ANNEX_PRINCIPAL_OFFICE_ALIGNED: StringName = &"annex.principal_office.aligned"
const ANNEX_PRINCIPAL_OFFICE_UNCLEAR: StringName = &"annex.principal_office.unclear"
## bool: the player chose to examine the curtain before touching it. Either result
## leaves this preparation in place; it is not evidence that the curtain is safe.
## Absent (false) in old saves: never infer preparation from a saved dice result.
const CURTAIN_EDGES_EXAMINED: StringName = &"curtain_edges_examined"
## bool: the opening has been requested by dialogue. Kept across a refused forced fall.
const CURTAIN_FALL_PENDING: StringName = &"curtain_fall_pending"
## bool: the back-window curtain hangs open on the void; the classroom loads that way.
const CURTAIN_DRAWN: StringName = &"curtain_drawn"
## bool: the curtain is open but the protagonist caught their balance and stayed in class.
## Absent in earlier saves, where the only way to leave the curtain open was to fall.
const CURTAIN_EDGE_HELD: StringName = &"curtain_edge_held"
## bool: the player hurt their ankle on their last landing. Written only on arrival.
const CURTAIN_LANDING_INJURED: StringName = &"curtain_landing_injured"
## int: whole seconds of play left on the dazed look after a hurt landing
## (`ConcussionView`). Written as `ConcussionView.DURATION` at the roof contact of that
## landing (more after a second fall off the container) and counted down while the game
## runs (not while paused); the yard tap lowers or clears it. 0 or absent means the
## protagonist sees normally again. Absent in saves written before round 7.
const CONCUSSION_SECONDS_LEFT: StringName = &"concussion_seconds_left"
## String: how the protagonist chose to get off the container roof while the resident
## stood in his doorway (`roof_way_down.gd`): "ladder", "jump", or "stay" (not yet).
const ROOF_WAY_DOWN: StringName = &"roof_way_down"
## String: the last use of the yard tap while dazed (`yard_tap.gd`): "drink", "wash" or
## "leave". Written by the tap's choice; the tap applies it as it is written.
const TAP_USE: StringName = &"tap_use"
## bool: the protagonist has the padlock key of the building site's hoarding gate, picked
## out of the chalk star inside the building (`site_key`). It opens the porch door's way
## back out to the yard (`site_interior`) and turns the yard's gate into a two-way exit
## (`site_gate.gd`). Absent in saves written before round 11.
const SITE_GATE_KEY: StringName = &"site_gate_key"

# --- Dialogue choice consequences ------------------------------------------
## bool: the protagonist admitted not remembering Q.
const ASKED_Q_IDENTITY: StringName = &"asked_q_identity"
## bool: the protagonist asked Q for the date.
const ASKED_Q_DATE: StringName = &"asked_q_date"
## bool: the protagonist stayed silent instead of answering Q.
const STAYED_SILENT: StringName = &"stayed_silent"
## bool: the protagonist denied remembering the biology exam.
const DENIED_EXAM_MEMORY: StringName = &"denied_exam_memory"
## bool: the protagonist told Q the textbook is gone.
const TOLD_Q_ABOUT_TEXTBOOK: StringName = &"told_q_about_textbook"
## bool: the protagonist accused Q of taking the textbook.
const ACCUSED_Q: StringName = &"accused_q"
## bool: Q already asked what the protagonist found in the bag.
const Q_BOOK_TALK_DONE: StringName = &"q_book_talk_done"
## bool: the protagonist told Q they would borrow a book from the class next door
## (`q_wake`, option `borrow`). Until the lesson is over it turns the classroom's rear
## door from a locked door into a one-off inference check (`classroom_anomalies.gd`).
const BORROW_FROM_NEXT_CLASS: StringName = &"borrow_from_next_class"
## bool: the rear-door check succeeded and the protagonist left before the lesson. It
## closes the rest of the prologue (bell, substitute) the way `class_dismissed` does,
## without claiming that N ever dismissed anyone.
const SKIPPED_CLASS: StringName = &"skipped_class"
## bool: after Q described B (`q_wake`, `q_b_looks`, option `imagine_b`) the protagonist
## chose to picture her. The imagined lesson `expected_b` plays as soon as Q's talk ends;
## without it the expectation step is closed as skipped and the scene never plays.
const IMAGINE_B_CHOSEN: StringName = &"imagine_b_chosen"
## bool: the player asked the substitute about B.
const ASKED_N_ABOUT_B: StringName = &"asked_n_about_b"
## bool: the player asked the substitute about spare textbooks.
const ASKED_N_ABOUT_TEXTBOOK: StringName = &"asked_n_about_textbook"
## bool: the player talked to the classmate in the classroom (`StudentTalk`, `student`).
const STUDENT_TALKED: StringName = &"student_talked"

# --- Small runtime values used by presentation ------------------------------
## String: locale key of the single objective line the HUD shows, e.g.
## "objective.check_bag". Literal text is never stored, so the objective
## re-translates the moment the player switches language.
const OBJECTIVE_KEY: StringName = &"objective_key"
## StringName: id of the location the player is currently in.
const CURRENT_LOCATION: StringName = &"current_location"

## Every constant above, in declaration order. `tools/check_story_flags.py` keeps it
## complete, so code that needs the whole registry can rely on it.
const ALL_FLAGS: Array[StringName] = [
	MET_Q,
	Q_FIRST_TALK_DONE,
	B_ON_STAGE,
	TEXTBOOK_MISSING,
	BAG_WAIT_EXPIRED,
	SAW_SET_SQUARE,
	EXPECTATION_PLAYED,
	EXPECTATION_SKIPPED,
	EXPECTATION_LEFT_EARLY,
	BELL_RUNG,
	N_ARRIVED,
	CLASS_DISMISSED,
	LEFT_CLASSROOM,
	FRONT_YARD_ARRIVED,
	LEFT_SCHOOL,
	STREET_ARRIVED,
	STREET_WALL_SEEN,
	RESIDENTIAL_ARRIVED,
	ANIMAL_SEEN,
	ALLEY_ARRIVED,
	PLAYGROUND_ARRIVED,
	PLAYGROUND_CHECKED,
	PLAYGROUND_SHED_OPEN,
	PLAYGROUND_SHED_LOOKED,
	PLAYGROUND_ROTA_READ,
	PLAYGROUND_ROTA_SMUDGED,
	PLAYGROUND_TAG_FOUND,
	PLAYGROUND_BALL_STUCK,
	PLAYGROUND_SHADOW_MEASURED,
	FREE_PERIOD_STAYED,
	FREE_PERIOD_LEAVING,
	Q_COMPANION,
	CORRIDOR_WAITED,
	CORRIDOR_DIRECTORY_TAB,
	CORRIDOR_SCREEN_RAISED,
	CORRIDOR_BELL_TESTED,
	ANNEX_ARCHIVE_ALIGNED,
	ANNEX_ARCHIVE_UNCLEAR,
	ANNEX_PLAN_ROOM_ALIGNED,
	ANNEX_PLAN_ROOM_UNCLEAR,
	ANNEX_PROJECTION_ROOM_ALIGNED,
	ANNEX_PROJECTION_ROOM_UNCLEAR,
	ANNEX_COMPUTER_ROOM_ALIGNED,
	ANNEX_COMPUTER_ROOM_UNCLEAR,
	ANNEX_VACANT_OFFICE_ALIGNED,
	ANNEX_VACANT_OFFICE_UNCLEAR,
	ANNEX_PRINCIPAL_OFFICE_ALIGNED,
	ANNEX_PRINCIPAL_OFFICE_UNCLEAR,
	CURTAIN_EDGES_EXAMINED,
	CURTAIN_FALL_PENDING,
	CURTAIN_DRAWN,
	CURTAIN_EDGE_HELD,
	CURTAIN_LANDING_INJURED,
	CONCUSSION_SECONDS_LEFT,
	ROOF_WAY_DOWN,
	TAP_USE,
	SITE_GATE_KEY,
	ASKED_Q_IDENTITY,
	ASKED_Q_DATE,
	STAYED_SILENT,
	DENIED_EXAM_MEMORY,
	TOLD_Q_ABOUT_TEXTBOOK,
	ACCUSED_Q,
	Q_BOOK_TALK_DONE,
	BORROW_FROM_NEXT_CLASS,
	SKIPPED_CLASS,
	IMAGINE_B_CHOSEN,
	ASKED_N_ABOUT_B,
	ASKED_N_ABOUT_TEXTBOOK,
	STUDENT_TALKED,
	OBJECTIVE_KEY,
	CURRENT_LOCATION,
]


## The opened curtain alone no longer means Q was left behind. Preserve that reading
## for saves from before the protagonist could catch their balance and stay upstairs.
static func has_curtain_landing(state: Node) -> bool:
	return state != null and state.get_flag(CURTAIN_DRAWN, false) == true \
		and state.get_flag(CURTAIN_EDGE_HELD, false) != true


## Flag that records a single dialogue choice was taken. Dialogue content marks
## a choice as `once` by pointing at this helper, and the runtime writes it.
static func choice_flag(conversation_id: StringName, choice_id: StringName) -> StringName:
	return StringName("choice:%s:%s" % [String(conversation_id), String(choice_id)])


## Flag that records an inspection was read at least once, so repeat text and
## repeat behaviour stay consistent across visits.
static func inspection_seen_flag(inspection_id: StringName) -> StringName:
	return StringName("seen:%s" % String(inspection_id))


## Flag that keeps the result of one dialogue check, as a Dictionary. Storing the
## whole result (die, total, branch) is what stops a check from being re-rolled by
## walking back into the same node: the recorded outcome is replayed instead.
static func check_record_flag(conversation_id: StringName, node_id: StringName) -> StringName:
	return StringName("check:%s:%s" % [String(conversation_id), String(node_id)])


## Flag that marks a passive inner-voice rule as spent. `once` rules use it.
static func passive_fired_flag(rule_id: StringName) -> StringName:
	return StringName("voice:%s" % String(rule_id))


## Counter flag: how many times one inner voice has spoken unprompted this session.
static func passive_count_flag(ability_id: StringName) -> StringName:
	return StringName("voice_count:%s" % String(ability_id))
