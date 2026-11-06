class_name PrologueFlags
extends RefCounted
## Stable story-flag identifiers for the Biology Class prologue.
##
## Flags live in GameState (the existing autoload) so that scene transitions and
## future save/load keep working through one owner. They are declared here once so
## dialogue data, interaction code, and tests cannot drift apart through typos.
##
## Treat every identifier below as a save-data contract: rename only with a
## migration plan.

# --- Beat A: waking/sitting up -------------------------------------------
const AWAKENED := &"prologue.awakened"
const CONTROL_RETURNED := &"prologue.control_returned"

# --- Beat B: Q opens the conversation ------------------------------------
const Q_INTRO_SEEN := &"prologue.q_intro_seen"
## Player pushed back on Q's overfamiliarity at least once.
const Q_PUSHBACK := &"prologue.q_pushback"
## Player let Q talk without objecting.
const Q_ALLOWED_SMALLTALK := &"prologue.q_allowed_smalltalk"
## Protagonist admitted, out loud, that they do not remember Q.
const ADMITTED_FORGOT_Q := &"prologue.admitted_forgot_q"
## Player challenged Q's account of the last biology exam.
const DOUBTED_EXAM_ACCOUNT := &"prologue.doubted_exam_account"
## Player accepted Q's account as probably true.
const ACCEPTED_EXAM_ACCOUNT := &"prologue.accepted_exam_account"

# --- Beat C: the schoolbag -----------------------------------------------
const BAG_EXAMINED := &"prologue.bag_examined"
const TEXTBOOK_MISSING := &"prologue.textbook_missing"
const BAG_OFFERED_TO_Q := &"prologue.bag_offered_to_q"
const BAG_KEPT_CLOSE := &"prologue.bag_kept_close"
## Q mentioned that B keeps a set square. (Heard, not confirmed.)
const HEARD_SET_SQUARE := &"prologue.heard_set_square"

# --- Beat D: classroom inspection ---------------------------------------
const SQUARE_EXAMINED := &"prologue.square_examined"
const TEACHER_DESK_EXAMINED := &"prologue.teacher_desk_examined"
const TIMETABLE_EXAMINED := &"prologue.timetable_examined"
const CHAIR_EXAMINED := &"prologue.chair_examined"
const WINDOW_EXAMINED := &"prologue.window_examined"

# --- Beat E: anticipation ------------------------------------------------
## The player chose to imagine what B would do.
const CONFRONTATION_IMAGINED := &"prologue.confrontation_imagined"
## The player chose to decline the daydream.
const CONFRONTATION_DECLINED := &"prologue.confrontation_declined"
## The imagined sequence finished playing (it is never an objective fact).
const IMAGINATION_PLAYED := &"prologue.imagination_played"
## The player voiced the rational reading: B is simply absent.
const EXPECTATION_CHECKED := &"prologue.expectation_checked"

# --- Beat F: the bell, B's absence, N's substitution --------------------
const BELL_RUNG := &"prologue.bell_rung"
const B_ABSENCE_NOTED := &"prologue.b_absence_noted"
const N_ARRIVED := &"prologue.n_arrived"
const N_LET_CLASS_GO := &"prologue.n_let_class_go"
## Tone the player took with N: sympathetic, skeptical, or quiet.
const N_READ_SYMPATHETIC := &"prologue.n_read_sympathetic"
const N_READ_SKEPTICAL := &"prologue.n_read_skeptical"
const N_READ_QUIET := &"prologue.n_read_quiet"
const ASKED_ABOUT_B := &"prologue.asked_about_b"
const N_OFFERED_HELP := &"prologue.n_offered_help"

# --- Beat G: leaving the classroom, corridor, exit ----------------------
const LEFT_CLASSROOM := &"prologue.left_classroom"
const CORRIDOR_ENTERED := &"prologue.corridor_entered"
const EXIT_SEEN := &"prologue.exit_seen"
const EXIT_REACHED := &"prologue.exit_reached"

# --- Second milestone: the residential street and the green animal -------
const STREET_ENTERED := &"prologue.street_entered"
const STREET_RELEASE_NOTED := &"prologue.street_release_noted"
const ANIMAL_GLIMPSED := &"prologue.animal_glimpsed"
## The player tried to see it again and could not.
const ANIMAL_NOT_FOUND_AGAIN := &"prologue.animal_not_found_again"
## The player chose to doubt their own eyes.
const DOUBTED_ANIMAL := &"prologue.doubted_animal"


## Every declared flag. Used by tests to assert the registry stays consistent and
## by the debug overlay. Keep this list complete when adding constants above.
static func all() -> Array[StringName]:
	return [
		AWAKENED,
		CONTROL_RETURNED,
		Q_INTRO_SEEN,
		Q_PUSHBACK,
		Q_ALLOWED_SMALLTALK,
		ADMITTED_FORGOT_Q,
		DOUBTED_EXAM_ACCOUNT,
		ACCEPTED_EXAM_ACCOUNT,
		BAG_EXAMINED,
		TEXTBOOK_MISSING,
		BAG_OFFERED_TO_Q,
		BAG_KEPT_CLOSE,
		HEARD_SET_SQUARE,
		SQUARE_EXAMINED,
		TEACHER_DESK_EXAMINED,
		TIMETABLE_EXAMINED,
		CHAIR_EXAMINED,
		WINDOW_EXAMINED,
		CONFRONTATION_IMAGINED,
		CONFRONTATION_DECLINED,
		IMAGINATION_PLAYED,
		EXPECTATION_CHECKED,
		BELL_RUNG,
		B_ABSENCE_NOTED,
		N_ARRIVED,
		N_LET_CLASS_GO,
		N_READ_SYMPATHETIC,
		N_READ_SKEPTICAL,
		N_READ_QUIET,
		ASKED_ABOUT_B,
		N_OFFERED_HELP,
		LEFT_CLASSROOM,
		CORRIDOR_ENTERED,
		EXIT_SEEN,
		EXIT_REACHED,
		STREET_ENTERED,
		STREET_RELEASE_NOTED,
		ANIMAL_GLIMPSED,
		ANIMAL_NOT_FOUND_AGAIN,
		DOUBTED_ANIMAL,
	]
