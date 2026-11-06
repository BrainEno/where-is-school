extends RefCounted
class_name PrologueRecords
## Every entry the prologue can write into the NarrativeLedger, declared in one
## place with an explicit knowledge kind.
##
## Keeping this table out of gameplay scripts means the *epistemology* of the
## scene is reviewable in a single file: a writer or designer can read it and see
## which lines the game will ever treat as fact.
##
## All summary text here is new placeholder prose written for the game. None of
## it is adapted from unpublished manuscript material.

## Record ids are a save-data contract; rename only with a migration.
const ID_WAKE := &"prologue.wake"
const ID_DISORIENTED := &"prologue.disorientation"
const ID_Q_EXAM := &"prologue.q.last_exam"
const ID_Q_EXAM_DENIED := &"prologue.q.last_exam_denied"
const ID_Q_EXAM_EVADED := &"prologue.q.last_exam_evaded"
const ID_Q_REPUTATION := &"prologue.q.b_reputation"
const ID_Q_REHEARSAL := &"prologue.q.rehearsal"
const ID_Q_REPUTATION_WHAT := &"prologue.q.reputation_what"
const ID_Q_REPUTATION_RULER := &"prologue.q.reputation_ruler"
const ID_Q_RECOGNITION := &"prologue.q.recognition"
const ID_Q_UNFAMILIAR := &"prologue.q.unfamiliar"
const ID_BAG_EMPTY_TEXTBOOK := &"prologue.bag.textbook_absent"
const ID_SET_SQUARE := &"prologue.prop.set_square"
const ID_TEACHER_DESK := &"prologue.prop.teacher_desk"
const ID_CHALKBOARD := &"prologue.prop.chalkboard"
const ID_TIMETABLE := &"prologue.prop.timetable"
const ID_WINDOW := &"prologue.prop.window"
const ID_OWN_DESK := &"prologue.prop.own_desk"
const ID_HALL_SOUND := &"prologue.hall_sound"
const ID_IMAGINED_CONFRONTATION := &"prologue.imagined.confrontation"
const ID_IMAGINED_CORRECTION := &"prologue.imagined.correction"
const ID_IMAGINED_DENIAL := &"prologue.imagined.denial"
const ID_IMAGINED_SILENCE := &"prologue.imagined.silence"
const ID_IMAGINED_BELL := &"prologue.imagined.bell"
const ID_BELL := &"prologue.event.bell"
const ID_B_ABSENT := &"prologue.event.b_absent"
const ID_N_INTRODUCTION := &"prologue.event.n_introduction"
const ID_N_RELEASE := &"prologue.event.n_release"
const ID_CORRIDOR := &"prologue.event.corridor"
const ID_GATE := &"prologue.event.gate"


static func all_entries() -> Array[Dictionary]:
	return [
		_entry(ID_WAKE, NarrativeRecord.Kind.OBSERVED,
			"Woke at a classroom desk",
			"Face-down on the desk, a headache, a room already filling up."),
		_entry(ID_DISORIENTED, NarrativeRecord.Kind.RECALLED,
			"Window, second row, the sea",
			"I cannot place when I last sat here. If I ever did.",
			&"protagonist"),
		_entry(ID_Q_EXAM, NarrativeRecord.Kind.HEARD,
			"Q on last term's exam",
			"He says I left most of it blank, and the teacher kept the paper.",
			&"q"),
		_entry(ID_Q_EXAM_DENIED, NarrativeRecord.Kind.RECALLED,
			"You moved the date on purpose",
			"You told Q it was two years ago. You are not sure you believed it either.",
			&"protagonist"),
		_entry(ID_Q_EXAM_EVADED, NarrativeRecord.Kind.HEARD,
			"Q was less sure than Q sounded",
			"Asked whose paper it was, Q hesitated. So did you.",
			&"q"),
		_entry(ID_Q_REPUTATION, NarrativeRecord.Kind.HEARD,
			"Q on what the teacher is like",
			"He says she remembers faces and reasons, and does not accept either as an excuse.",
			&"q"),
		_entry(ID_Q_REPUTATION_WHAT, NarrativeRecord.Kind.HEARD,
			"Q on how the teacher handles a desk",
			"She stands and waits until the room notices. The question is the punishment.",
			&"q"),
		_entry(ID_Q_REPUTATION_RULER, NarrativeRecord.Kind.OBSERVED,
			"Q on the set square",
			"Q says it has not been used on anyone since. Q does not sound certain.",
			&"q"),
		_entry(ID_Q_REHEARSAL, NarrativeRecord.Kind.HEARD,
			"Q's advice on rehearsing an apology",
			"He suggests saying my lines out loud first. He sounds experienced.",
			&"q"),
		_entry(ID_Q_RECOGNITION, NarrativeRecord.Kind.RECALLED,
			"Something about Q's shoulders",
			"A shape I might have known once. That is as far as it goes.",
			&"protagonist"),
		_entry(ID_Q_UNFAMILIAR, NarrativeRecord.Kind.RECALLED,
			"Q's name will not settle",
			"I have a name. I do not have a face to attach to it.",
			&"protagonist"),
		_entry(ID_BAG_EMPTY_TEXTBOOK, NarrativeRecord.Kind.OBSERVED,
			"Biology textbook missing",
			"Everything else is in the bag. The biology textbook is not.",
			&"schoolbag"),
		_entry(ID_SET_SQUARE, NarrativeRecord.Kind.OBSERVED,
			"Damaged wooden set square",
			"The short leg is split, and someone has sanded it badly rather than thrown it out.",
			&"set_square"),
		_entry(ID_TEACHER_DESK, NarrativeRecord.Kind.OBSERVED,
			"The teacher's desk",
			"Clean apart from one drift of chalk dust, and all of it facing the room.",
			&"teacher_desk"),
		_entry(ID_CHALKBOARD, NarrativeRecord.Kind.OBSERVED,
			"Chalkboard",
			"Biology, third period, written in a square, unhurried hand.",
			&"chalkboard"),
		_entry(ID_TIMETABLE, NarrativeRecord.Kind.OBSERVED,
			"Term timetable",
			"One sheet, one class, already marked over. Pen changes hands halfway down.",
			&"timetable"),
		_entry(ID_OWN_DESK, NarrativeRecord.Kind.RECALLED,
			"Your own desk",
			"A scratched-out date and a hand-shaped worn patch. Neither is evidence of anything.",
			&"protagonist"),
		_entry(ID_WINDOW, NarrativeRecord.Kind.OBSERVED,
			"Window and grounds",
			"Fence, a strip of wet asphalt, the iron gate, and then ordinary roofs.",
			&"window"),
		_entry(ID_HALL_SOUND, NarrativeRecord.Kind.HEARD,
			"Someone in the corridor",
			"A bag dropping. Two voices. A door not quite closing.",
			&"corridor"),
		_entry(ID_IMAGINED_CONFRONTATION, NarrativeRecord.Kind.IMAGINED,
			"Rehearsal: the empty-desk question",
			"I tried out how it would go if she asked why the desk was empty.",
			&"protagonist"),
		_entry(ID_IMAGINED_CORRECTION, NarrativeRecord.Kind.IMAGINED,
			"Rehearsal: my answer",
			"I practised one sentence and heard it land badly.",
			&"protagonist"),
		_entry(ID_IMAGINED_DENIAL, NarrativeRecord.Kind.IMAGINED,
			"Rehearsal: insisting you were there",
			"I tried saying I had been here. It did not sound like evidence.",
			&"protagonist"),
		_entry(ID_IMAGINED_SILENCE, NarrativeRecord.Kind.IMAGINED,
			"Rehearsal: saying nothing",
			"I practised the silence. In the rehearsal, the silence is the answer.",
			&"protagonist"),
		_entry(ID_IMAGINED_BELL, NarrativeRecord.Kind.IMAGINED,
			"Rehearsal: the bell",
			"I imagined the bell as an interruption, not as a rescue.",
			&"protagonist"),
		_entry(ID_BELL, NarrativeRecord.Kind.OBSERVED,
			"The bell",
			"One tone, repeated once. Nobody in the room reacted much.",
			&"school"),
		_entry(ID_B_ABSENT, NarrativeRecord.Kind.OBSERVED,
			"The lesson started without the expected teacher",
			"Her chair stayed empty. Nobody went to the cupboard for the set square.",
			&"classroom"),
		_entry(ID_N_INTRODUCTION, NarrativeRecord.Kind.HEARD,
			"The substitute's introduction",
			"She called the class by period number, not by name, and apologised twice.",
			&"n"),
		_entry(ID_N_RELEASE, NarrativeRecord.Kind.HEARD,
			"The substitute's permission",
			"Free activity for the rest of the period, with the door left open.",
			&"n"),
		_entry(ID_CORRIDOR, NarrativeRecord.Kind.OBSERVED,
			"The corridor",
			"Bags, a bucket, a window over a strip of weedy concrete.",
			&"corridor"),
		_entry(ID_GATE, NarrativeRecord.Kind.OBSERVED,
			"The gate",
			"Open a hand's width, held by a block of wood. Nobody is guarding it.",
			&"school_gate"),
	]


static func entry_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry in all_entries():
		result.append(StringName(entry["id"]))
	return result


static func entry_for(record_id: StringName) -> Dictionary:
	for entry in all_entries():
		if StringName(entry["id"]) == record_id:
			return entry
	return {}


static func _entry(
	record_id: StringName,
	kind: NarrativeRecord.Kind,
	title: String,
	body: String,
	source_id: StringName = &""
) -> Dictionary:
	return {
		"id": record_id,
		"kind": kind,
		"title": title,
		"body": body,
		"source": source_id,
	}
