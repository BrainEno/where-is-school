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
## bool: the expectation beat was passed over because the bag had not been searched
## when its turn came. Closes the step without claiming the scene was seen. Absent
## (false) in saves written before #144, like `bag_wait_expired`.
const EXPECTATION_SKIPPED: StringName = &"expectation_skipped"
## bool: the second bell has rung.
const BELL_RUNG: StringName = &"bell_rung"
## bool: substitute N has reached the front of the classroom.
const N_ARRIVED: StringName = &"n_arrived"
## bool: N has allowed the class to leave for free activity.
const CLASS_DISMISSED: StringName = &"class_dismissed"
## bool: the player left the classroom for the walkway.
const LEFT_CLASSROOM: StringName = &"left_classroom"
## bool: the player walked out of the school building into the street.
const LEFT_SCHOOL: StringName = &"left_school"
## bool: the first street conversation has played.
const STREET_ARRIVED: StringName = &"street_arrived"
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
## bool: the player stayed at their desk after N announced the free period.
const FREE_PERIOD_STAYED: StringName = &"free_period_stayed"
## bool: the player chose to get up and leave after N announced the free period.
const FREE_PERIOD_LEAVING: StringName = &"free_period_leaving"
## bool: Q is walking with the player. Set the first time the classroom is left.
const Q_COMPANION: StringName = &"q_companion"
## bool: the player used the walkway railing to let part of the period pass.
const CORRIDOR_WAITED: StringName = &"corridor_waited"
## bool: the curtain conversation ended with the protagonist drawing the back-window
## curtain aside; the classroom's fall is owed. Set by dialogue (`classroom_curtain`),
## cleared by the fall itself once the player has landed in the yard.
## PROVISIONAL: a placeholder until the curtain scene's narrative owner (Agent 04) takes
## the dialogue over; the id is what the classroom code listens for, so keep it or
## migrate both together.
const CURTAIN_FALL_PENDING: StringName = &"curtain_fall_pending"
## bool: the back-window curtain hangs open on the void; the classroom loads that way.
const CURTAIN_DRAWN: StringName = &"curtain_drawn"
## bool: the rear door has been opened and the staircase hangs in the classroom.
const REAR_DOOR_OPENED: StringName = &"rear_door_opened"

# --- Dialogue choice consequences ------------------------------------------
## bool: the protagonist admitted not remembering Q.
const ASKED_Q_IDENTITY: StringName = &"asked_q_identity"
## bool: the protagonist asked Q for the date.
const ASKED_Q_DATE: StringName = &"asked_q_date"
## bool: the protagonist stayed silent instead of answering Q.
const STAYED_SILENT: StringName = &"stayed_silent"
## bool: the protagonist denied remembering the biology exam.
const DENIED_EXAM_MEMORY: StringName = &"denied_exam_memory"
## bool: the protagonist insisted the exam was only one page.
const CLAIMED_ONE_PAGE_EXAM: StringName = &"claimed_one_page_exam"
## bool: the protagonist challenged Q's interest.
const CHALLENGED_Q: StringName = &"challenged_q"
## bool: the protagonist asked whether B is strict.
const ASKED_IF_B_STRICT: StringName = &"asked_if_b_strict"
## bool: the protagonist pointed out that B may be late.
const NOTED_B_LATE: StringName = &"noted_b_late"
## bool: the protagonist told Q the textbook is gone.
const TOLD_Q_ABOUT_TEXTBOOK: StringName = &"told_q_about_textbook"
## bool: the protagonist accused Q of taking the textbook.
const ACCUSED_Q: StringName = &"accused_q"
## bool: the player asked the substitute about B.
const ASKED_N_ABOUT_B: StringName = &"asked_n_about_b"
## bool: the player asked the substitute about spare textbooks.
const ASKED_N_ABOUT_TEXTBOOK: StringName = &"asked_n_about_textbook"
## bool: the player noticed that N is a substitute.
const NOTICED_N_SUBSTITUTE: StringName = &"noticed_n_substitute"

# --- Small runtime values used by presentation ------------------------------
## String: locale key of the single objective line the HUD shows, e.g.
## "objective.check_bag". Literal text is never stored, so the objective
## re-translates the moment the player switches language.
const OBJECTIVE_KEY: StringName = &"objective_key"
## StringName: id of the location the player is currently in.
const CURRENT_LOCATION: StringName = &"current_location"

const ALL_FLAGS: Array[StringName] = [
	MET_Q,
	Q_FIRST_TALK_DONE,
	B_ON_STAGE,
	TEXTBOOK_MISSING,
	BAG_WAIT_EXPIRED,
	SAW_SET_SQUARE,
	EXPECTATION_PLAYED,
	EXPECTATION_SKIPPED,
	BELL_RUNG,
	N_ARRIVED,
	CLASS_DISMISSED,
	LEFT_CLASSROOM,
	ASKED_Q_IDENTITY,
	ASKED_Q_DATE,
	STAYED_SILENT,
	DENIED_EXAM_MEMORY,
	CLAIMED_ONE_PAGE_EXAM,
	CHALLENGED_Q,
	ASKED_IF_B_STRICT,
	NOTED_B_LATE,
	TOLD_Q_ABOUT_TEXTBOOK,
	ACCUSED_Q,
	ASKED_N_ABOUT_B,
	ASKED_N_ABOUT_TEXTBOOK,
	NOTICED_N_SUBSTITUTE,
	OBJECTIVE_KEY,
	CURRENT_LOCATION,
	# Free period and the companion.
	FREE_PERIOD_STAYED,
	FREE_PERIOD_LEAVING,
	Q_COMPANION,
	CORRIDOR_WAITED,
	# The biology classroom's two anomalies.
	CURTAIN_FALL_PENDING,
	CURTAIN_DRAWN,
	REAR_DOOR_OPENED,
	# Outdoor beats.
	ALLEY_ARRIVED,
	PLAYGROUND_ARRIVED,
]


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
