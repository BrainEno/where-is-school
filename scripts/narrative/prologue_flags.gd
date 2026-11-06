extends RefCounted
class_name PrologueFlags
## Stable story-flag identifiers for the biology-class prologue.
##
## These strings are a save-data contract: rename them only with an explicit
## migration. Gameplay code asks about the prologue through this class so that
## a typo is a compile-time error instead of a silently missing flag.

# --- Beat A: waking ---------------------------------------------------------
const AWAKE := &"prologue.awake"
const PLAYER_HAS_CONTROL := &"prologue.player_has_control"

# --- Beat B: Q --------------------------------------------------------------
const Q_TALKED := &"prologue.q.talked"
const Q_ATTITUDE := &"prologue.q.attitude"
const Q_ATTITUDE_NEUTRAL := &"neutral"
const Q_ATTITUDE_WARM := &"warm"
const Q_ATTITUDE_GUARDED := &"guarded"
const Q_ATTITUDE_DEFLECTIVE := &"deflective"
const Q_ADMITTED_FORGOTTEN := &"prologue.q.admitted_forgetting"
const Q_MENTIONED_LAST_EXAM := &"prologue.q.mentioned_last_exam"
const Q_MENTIONED_REHEARSAL := &"prologue.q.mentioned_rehearsal"

# --- Beat C: schoolbag ------------------------------------------------------
const BAG_EXAMINED := &"prologue.bag.examined"
const TEXTBOOK_MISSING := &"prologue.textbook.missing"
const TEXTBOOK_SEARCH_PERSISTED := &"prologue.textbook.search_persisted"

# --- Beat D: room inspection ------------------------------------------------
const SET_SQUARE_EXAMINED := &"prologue.set_square.examined"
const TEACHER_DESK_EXAMINED := &"prologue.teacher_desk.examined"
const CHALKBOARD_EXAMINED := &"prologue.chalkboard.examined"
const TIMETABLE_EXAMINED := &"prologue.timetable.examined"
const WINDOW_EXAMINED := &"prologue.window.examined"

# --- Beat E: anticipation ---------------------------------------------------
const ANTICIPATION_ENTERED := &"prologue.anticipation.entered"
const ANTICIPATION_EXITED := &"prologue.anticipation.exited"

# --- Beat F: absence and substitution ---------------------------------------
const BELL_RUNG := &"prologue.bell.rung"
const LESSON_STARTED := &"prologue.lesson.started"
const B_ABSENT_CONFIRMED := &"prologue.b.absent_confirmed"
const N_ENTERED := &"prologue.n.entered"
const N_CLASS_PERMITTED := &"prologue.n.class_permitted"
const LESSON_ENDED := &"prologue.lesson.ended"

# --- Beat G: exit -----------------------------------------------------------
const CLASSROOM_EXITED := &"prologue.classroom.exited"
const GATE_REACHED := &"prologue.gate.reached"


static func all() -> Array[StringName]:
	return [
		AWAKE,
		PLAYER_HAS_CONTROL,
		Q_TALKED,
		Q_ATTITUDE,
		Q_ADMITTED_FORGOTTEN,
		Q_MENTIONED_LAST_EXAM,
		Q_MENTIONED_REHEARSAL,
		BAG_EXAMINED,
		TEXTBOOK_MISSING,
		TEXTBOOK_SEARCH_PERSISTED,
		SET_SQUARE_EXAMINED,
		TEACHER_DESK_EXAMINED,
		CHALKBOARD_EXAMINED,
		TIMETABLE_EXAMINED,
		WINDOW_EXAMINED,
		ANTICIPATION_ENTERED,
		ANTICIPATION_EXITED,
		BELL_RUNG,
		LESSON_STARTED,
		B_ABSENT_CONFIRMED,
		N_ENTERED,
		N_CLASS_PERMITTED,
		LESSON_ENDED,
		CLASSROOM_EXITED,
		GATE_REACHED,
	]
