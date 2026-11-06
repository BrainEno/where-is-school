extends RefCounted
class_name PrologueInspections
## Inspection text for the classroom, keyed by inspectable id.
##
## All descriptions are short, original, and written for the game. They are
## deliberately plain: the room should read as an ordinary, slightly
## uncomfortable workplace before it reads as anything else.
##
## Each entry may declare:
##   title       — headline in the inspection card / notes
##   text        — the description itself
##   record      — ledger record id (see PrologueRecords)
##   flag        — story flag set on first inspection (see PrologueFlags)
##   repeat      — shorter line for repeat inspections
##   once_only   — if true, repeat inspections return [member repeat]

const ENTRIES: Dictionary = {
	&"schoolbag": {
		"title": "Schoolbag",
		"text": "Under the chair, strap first, the way you leave it when you are already late. Inside: a pencil case, a folded handout, a bus card with the corner chewed. Everything you would have brought. Everything except the biology textbook.",
		"repeat": "Strap first under the chair. The textbook is not in it.",
		"record": PrologueRecords.ID_BAG_EMPTY_TEXTBOOK,
		"flag": PrologueFlags.BAG_EXAMINED,
		"extra_flag": PrologueFlags.TEXTBOOK_MISSING,
	},
	&"set_square": {
		"title": "Wooden set square",
		"text": "A wooden right angle, older than the desks, with a split running up the short leg. Someone has sanded the split instead of throwing the thing away, and sanded it badly. It sits on the teacher's desk at an angle that could only be deliberate.",
		"repeat": "Split short leg, badly sanded. Still placed at the same angle.",
		"record": PrologueRecords.ID_SET_SQUARE,
		"flag": PrologueFlags.SET_SQUARE_EXAMINED,
	},
	&"teacher_desk": {
		"title": "The teacher's desk",
		"text": "Two meters of dark wood, set square and square to the room. One drift of chalk dust that nobody has wiped. The exercise books are stacked on the far corner, all facing out, spines aligned. Nothing on this desk is for the person who sits behind it.",
		"repeat": "Everything on it faces the room. Including the chair, which is pushed in.",
		"record": PrologueRecords.ID_TEACHER_DESK,
		"flag": PrologueFlags.TEACHER_DESK_EXAMINED,
	},
	&"chalkboard": {
		"title": "Chalkboard",
		"text": "BIOLOGY, THIRD PERIOD — written in a square, unhurried hand. Under it, in a different colour, TERM BEGINS. Both look written on the same day. Somebody has erased the middle of the board and given up.",
		"repeat": "BIOLOGY, THIRD PERIOD. TERM BEGINS. The middle is still blank.",
		"record": PrologueRecords.ID_CHALKBOARD,
		"flag": PrologueFlags.CHALKBOARD_EXAMINED,
	},
	&"timetable": {
		"title": "Timetable",
		"text": "One sheet in a plastic sleeve by the door: this class, this term. Biology is third period most days. Thursday has been crossed out in pen and written back in with a different pen. Nobody has initialled it.",
		"repeat": "Third period most days. Thursday still has two hands on it.",
		"record": PrologueRecords.ID_TIMETABLE,
		"flag": PrologueFlags.TIMETABLE_EXAMINED,
	},
	&"window": {
		"title": "Window",
		"text": "The glass has a grey bloom on the inside you can rub off with a thumb. Below: a strip of wet asphalt, the side of a skip, the tops of two heads going nowhere. Beyond the boundary wall the roofs are ordinary and close together.",
		"repeat": "Wet asphalt, a skip, roofs. Ordinary, and close together.",
		"record": PrologueRecords.ID_WINDOW,
		"flag": PrologueFlags.WINDOW_EXAMINED,
	},
	&"own_desk": {
		"title": "Your desk",
		"text": "Varnish worn to the wood in a hand-shaped patch. A previous occupant has scratched a date into the corner and then scratched it out. Your handwriting would fit the same size of space.",
		"repeat": "The scratched-out date is still there. You still cannot read it.",
		"record": PrologueRecords.ID_OWN_DESK,
		"flag": &"",
	},
	&"door_locked": {
		"title": "The door",
		"text": "Third period has not started yet. Leaving now would be a decision, and you have not finished making the smaller one in front of you.",
		"repeat": "",
		"record": &"",
		"flag": &"",
	},
	&"door_open": {
		"title": "The door",
		"text": "Open. The corridor outside is the same colour as this room, which is somehow worse than it being different.",
		"repeat": "",
		"record": &"",
		"flag": &"",
	},
}


static func get_entry(inspect_id: StringName) -> Dictionary:
	return ENTRIES.get(inspect_id, {})


static func has_entry(inspect_id: StringName) -> bool:
	return ENTRIES.has(inspect_id)


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in ENTRIES.keys():
		result.append(key)
	return result
