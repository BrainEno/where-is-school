class_name ClassroomInspections
extends RefCounted
## Beat C and D — inspecting things in the room.
##
## Each inspectable object owns a small DialogueScript so an inspection can be a
## single paragraph or a short back-and-forth, and can read differently once the
## player already knows something. Content lives here, not in the prop scenes.
##
## Rules honoured in this file:
## - Descriptions are short, original, and about ordinary furniture and
##   surfaces. No supernatural decoration.
## - The student desks and the teacher's desk are described as different kinds of
##   territory (one is marked and shared, the other is clean and watched).
## - B is never present. She is inferred from an object nobody has put away.

const SELF := &"self"
const Q := &"q"

# Inspection ids double as story-flag names in PrologueFlags.
const BAG := &"bag"
const SET_SQUARE := &"set_square"
const TEACHER_DESK := &"teacher_desk"
const TIMETABLE := &"timetable"
const CHAIR := &"chair"
const WINDOW := &"window"


static func script_for(inspection_id: StringName, flags: Dictionary) -> DialogueScript:
	match inspection_id:
		BAG:
			return _bag(flags)
		SET_SQUARE:
			return _set_square(flags)
		TEACHER_DESK:
			return _teacher_desk(flags)
		TIMETABLE:
			return _timetable(flags)
		CHAIR:
			return _chair(flags)
		WINDOW:
			return _window(flags)
	push_error("ClassroomInspections has no script for inspection id '%s'." % inspection_id)
	return null


## Human-readable label for the interaction prompt.
static func label_zh(inspection_id: StringName) -> String:
	return {
		BAG: "书包",
		SET_SQUARE: "木尺",
		TEACHER_DESK: "讲桌",
		TIMETABLE: "课表",
		CHAIR: "椅子",
		WINDOW: "窗户",
	}.get(inspection_id, "")


static func label_en(inspection_id: StringName) -> String:
	return {
		BAG: "schoolbag",
		SET_SQUARE: "set square",
		TEACHER_DESK: "teacher's desk",
		TIMETABLE: "timetable",
		CHAIR: "chair",
		WINDOW: "window",
	}.get(inspection_id, "")


static func _one_node(script: DialogueScript, node: DialogueNode) -> DialogueScript:
	script.add(node)
	return script


# --- Beat C: the schoolbag ----------------------------------------------
static func _bag(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_bag")
	# Q can appear in this inspection if the player chooses to tell him.
	script.define_character(
		Q, "Q", "Q",
		Color(0.86, 0.72, 0.48),
		"隔壁座位的同学", "the classmate in the next seat"
	)
	var node := DialogueNode.new(&"bag_first")
	node.note(
		"书包是旧的，拉链头磨到发亮。里面有一支笔、一块饭盒压出来的空位、一张对折太多次的通知单。",
		"The bag is old; the zipper pull is worn shiny. Inside: a pen, a dent where a lunchbox used to sit, a notice folded too many times.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.note(
		"没有生物课本。我又翻了一遍。还是那些东西。还是那个空位。",
		"No biology textbook. I go through it again. Same things. Same gap.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.set_flags([PrologueFlags.BAG_EXAMINED, PrologueFlags.TEXTBOOK_MISSING])
	node.record(
		&"observed_textbook_missing",
		NarrativeProvenance.Kind.OBSERVED,
		"我检查了书包：里面没有生物课本。",
		"I checked my bag: there is no biology textbook in it."
	)
	node.choose(
		&"bag_tell_q",
		"（跟 Q 说：「我的生物课本不在。」）",
		"(Tell Q: \"My biology book isn't here.\")",
		&"bag_told_q",
		[PrologueFlags.BAG_OFFERED_TO_Q]
	)
	node.choose(
		&"bag_stay_quiet",
		"（先不要把这件事说出来。）",
		"(Keep it to myself for now.)",
		&"bag_kept_close",
		[PrologueFlags.BAG_KEPT_CLOSE]
	)
	script.add(node)

	var told := DialogueNode.new(&"bag_told_q")
	told.say(
		Q,
		"不在？你那本不是跟我的同一版吗。还是你根本没领？",
		"Not there? Didn't you get the same edition as me? Or did you never pick it up?",
		NarrativeProvenance.Kind.HEARD
	)
	told.say(
		Q,
		"你上学期那本书好像是跟别人借的。我记得你借了很久。",
		"I think you borrowed someone's last term. You had it for a long time.",
		NarrativeProvenance.Kind.HEARD
	)
	told.note(
		"「借了很久」。我没办法确认。也没办法否认。",
		"\"For a long time.\" I can't confirm it. I can't deny it either.",
		NarrativeProvenance.Kind.RECOLLECTED,
		&"interior"
	)
	told.record(
		&"heard_borrowed_textbook",
		NarrativeProvenance.Kind.HEARD,
		"Q 说我上学期的课本是跟别人借的。",
		"Q says the textbook I had last term belonged to someone else."
	)
	script.add(told)

	var quiet := DialogueNode.new(&"bag_kept_close")
	quiet.note(
		"我把拉链拉回去。现在只有我知道这件事。",
		"I close the zipper. Right now it's only mine.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(quiet)
	return script


# --- Beat D: the wooden set square --------------------------------------
static func _set_square(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_set_square")
	var first := DialogueNode.new(&"square_first")
	first.note(
		"讲桌角落有一把木制三角板，比一般的教具小一点。边角有缺口，长边的漆掉了一整条，露出来的地方被手指摸得光滑。",
		"A wooden set square at the corner of the teacher's desk. Smaller than the usual ones. A chip in the corner. A whole strip of varnish gone from the long edge, worn smooth where fingers hold it.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	first.note(
		"它不在抽屉里。它就摆在桌上。像放在这里，等人回来拿。",
		"It isn't in a drawer. It's lying out. Like someone left it there to come back for.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	first.set_flags([PrologueFlags.SQUARE_EXAMINED])
	first.record(
		&"observed_set_square",
		NarrativeProvenance.Kind.OBSERVED,
		"讲桌上有一把缺角的木尺，没有收起来。",
		"There is a chipped wooden set square on the teacher's desk, not put away."
	)

	var heard := bool(flags.get(String(PrologueFlags.HEARD_SET_SQUARE), false))
	if heard:
		first.note(
			"Q 说她会用这个敲桌子。木头上没有敲出来的痕迹。也许他记错了。也许她其实不敲。",
			"Q said she taps the desk with this. There are no dents in the wood. Maybe he has it wrong. Maybe she doesn't tap it much.",
			NarrativeProvenance.Kind.RECOLLECTED,
			&"interior"
		)
	else:
		first.note(
			"我没拿起来。它就在桌上。我就看了看。",
			"I don't pick it up. It's on the desk. I just look at it.",
			NarrativeProvenance.Kind.OBSERVED,
			&"interior"
		)
	script.add(first)
	return script


# --- Beat D: the teacher's desk -----------------------------------------
static func _teacher_desk(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_teacher_desk")
	var node := DialogueNode.new(&"teacher_desk_first")
	node.note(
		"讲桌比学生的桌子高一阶，桌面干净到反光，只有一点粉笔灰。抽屉关得很正。",
		"The teacher's desk sits a step higher than ours. The top is clean enough to shine. A little chalk dust. The drawer is shut straight.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.note(
		"我们的桌上什么都有：涂改液、胶带、刻上去的字。这张桌子上什么都没有。",
		"Our desks have everything on them. Correction fluid, tape, carved names. This one has nothing.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.set_flags([PrologueFlags.TEACHER_DESK_EXAMINED])
	node.record(
		&"observed_teacher_desk",
		NarrativeProvenance.Kind.OBSERVED,
		"讲桌很干净，和学生的桌子明显不同。",
		"The teacher's desk is clean, and clearly not the same kind of surface as the student desks."
	)
	node.choose(
		&"teacher_desk_open",
		"（拉开抽屉。）",
		"(Open the drawer.)",
		&"teacher_desk_drawer"
	)
	node.choose(
		&"teacher_desk_leave",
		"（不碰她的东西。）",
		"(Leave her things alone.)",
		&"teacher_desk_back_off"
	)
	script.add(node)

	var drawer := DialogueNode.new(&"teacher_desk_drawer")
	drawer.note(
		"左边抽屉里是一叠点名册。橡皮筋绑的。最上面那张是上学期的日期。",
		"The left drawer has a stack of attendance lists. Rubber band around them. The top one is dated last term.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	drawer.note(
		"右边抽屉锁着。我没使劲。",
		"The right drawer is locked. I don't force it.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	drawer.record(
		&"observed_locked_drawer",
		NarrativeProvenance.Kind.OBSERVED,
		"讲桌右边的抽屉锁着；左边是上学期的点名单。",
		"The right drawer of the teacher's desk is locked; the left holds last term's attendance sheets."
	)
	script.add(drawer)

	var back_off := DialogueNode.new(&"teacher_desk_back_off")
	back_off.note(
		"我把手收回来。不是因为规矩。是因为不想在她的桌上留下手印。",
		"I pull my hand back. Not because of rules. Because I don't want to leave a print on her desk.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(back_off)
	return script


# --- Beat D: the timetable ----------------------------------------------
static func _timetable(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_timetable")
	var node := DialogueNode.new(&"timetable_first")
	node.note(
		"门边的课表用胶带贴着，边角卷起来。今天那一格印着「生物」，旁边有人用铅笔写了一个很小的「B」。",
		"The timetable by the door is taped up. Corners curling. Today's cell says \"Biology\". Someone pencilled a very small \"B\" next to it.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.note(
		"下面两格是空的。最后一学期了。课表也懒得印满。",
		"Two cells below are blank. Last term. Even the timetable stopped bothering.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.set_flags([PrologueFlags.TIMETABLE_EXAMINED])
	node.record(
		&"observed_timetable",
		NarrativeProvenance.Kind.OBSERVED,
		"课表上今天这一格是生物，旁边有人用铅笔写了「B」。",
		"Today's timetable cell is biology, with a pencilled \"B\" next to it."
	)
	node.choose(
		&"timetable_pencil",
		"（用指甲刮那个铅笔的 B。）",
		"(Scrape at the pencilled B with a fingernail.)",
		&"timetable_scrape"
	)
	node.choose(
		&"timetable_leave",
		"（算了。就留着。）",
		"(Leave it there.)",
		&"timetable_leave_it"
	)
	script.add(node)

	var scrape := DialogueNode.new(&"timetable_scrape")
	scrape.note(
		"刮不掉。写得很久了。铅笔已经压进纸里。",
		"It won't come off. It's been there a long time. The pencil is pressed into the paper.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(scrape)

	var leave_it := DialogueNode.new(&"timetable_leave_it")
	leave_it.note(
		"不是我的字。我没必要动它。",
		"Not my handwriting. No reason to touch it.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(leave_it)
	return script


# --- Beat D: my chair ---------------------------------------------------
static func _chair(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_chair")
	var node := DialogueNode.new(&"chair_first")
	node.note(
		"椅子是折叠式的，铁管焊得不太平，坐着会微微往左偏。椅背上有一块掉漆，刚好在靠背正中央。",
		"A folding chair with a slightly uneven weld; it leans left when you sit. A patch of paint is missing from the middle of the backrest.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.note(
		"我刚才睡在这张椅子上。姿势应该很难看。脖子有点酸。这个我能确定。",
		"I was asleep in this chair a moment ago. In what must have been a bad position. My neck aches. That part I'm sure of.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.set_flags([PrologueFlags.CHAIR_EXAMINED])
	node.record(
		&"observed_chair",
		NarrativeProvenance.Kind.OBSERVED,
		"我的椅子会往左偏；脖子有点酸。",
		"My chair leans left; my neck aches."
	)
	script.add(node)
	return script


# --- Beat D: the window -------------------------------------------------
static func _window(flags: Dictionary) -> DialogueScript:
	var script := DialogueScript.new(&"inspect_window")
	var node := DialogueNode.new(&"window_first")
	node.note(
		"窗框是旧的铝框，玻璃上有一层擦不掉的雾。外面是对面公寓的后阳台，晒着衣服，有人把洗衣机的水管接到墙外。",
		"An old aluminium frame. A haze on the glass that won't wipe off. Outside is the back balcony of the building opposite. Laundry. Somebody ran a washing machine hose out through the wall.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.note(
		"放学钟还没响。可是三楼走廊上已经有人在走动。也可能是我听错了。",
		"The closing bell hasn't rung. But there's already movement in the third-floor corridor. Or I'm hearing things.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	node.set_flags([PrologueFlags.WINDOW_EXAMINED])
	node.record(
		&"observed_window",
		NarrativeProvenance.Kind.OBSERVED,
		"窗外是对面公寓的后阳台，晒着衣服。",
		"Outside the window is the back balcony of the apartment opposite, with laundry hanging."
	)
	script.add(node)
	return script
