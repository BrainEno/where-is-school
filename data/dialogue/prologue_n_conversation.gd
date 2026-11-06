class_name PrologueNConversation
extends RefCounted
## Beat F — the bell rings, B does not come, N substitutes.
##
## Authoring notes (not shown in game):
## - N is new at this. Her inexperience shows in logistics, not in a joke voice:
##   she has the wrong room list, she reads the register twice, she loses the
##   sentence she was in the middle of.
## - She is not a saint and not a villain. She gives the class away partly because
##   she cannot hold it, and she is honest about that in a small way.
## - When asked about B she hesitates. Her answer is incomplete because she is
##   junior, not because she is hiding a revelation.
## - Everything she says is recorded as HEARD.

const N := &"n"
const Q := &"q"

const START := &"n_start"
const REGISTER := &"n_register"
const ASK_B := &"n_ask_b"
const OWN_CLASS := &"n_own_class"
const HOLD_BACK := &"n_hold_back"
const RELEASE := &"n_release"
const LEAVE := &"n_leave"


static func build() -> DialogueScript:
	var script := DialogueScript.new(&"prologue_n")
	script.define_character(
		N, "N", "N",
		Color(0.68, 0.78, 0.76),
		"代课老师", "the substitute teacher"
	)
	# Q is only present to leave the room; he speaks one line at the end.
	script.define_character(
		Q, "Q", "Q",
		Color(0.86, 0.72, 0.48),
		"隔壁座位的同学", "the classmate in the next seat"
	)

	# --- Entering -----------------------------------------------------------
	var start := DialogueNode.new(START)
	start.set_flags([PrologueFlags.N_ARRIVED])
	start.say(
		N,
		"不好意思，不好意思。这间是……三年级的生物课，对吧？",
		"Sorry — sorry. This is... third year biology, correct?",
		NarrativeProvenance.Kind.HEARD
	)
	start.say(
		N,
		"我是今天代课的。姓 N。你们老师……B 老师，她今天临时有事。",
		"I'm substituting today. Surname N. Your teacher — Ms. B — had something come up.",
		NarrativeProvenance.Kind.HEARD
	)
	start.note(
		"「临时有事」。四个字。什么都没说。",
		"\"Something came up.\" Four words. Nothing in them.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	start.say(
		N,
		"我念一下名字。有到的举手就好，不用答有。",
		"I'll read the names. Just raise your hand if you're here. You don't have to say anything.",
		NarrativeProvenance.Kind.HEARD
	)
	start.say(
		N,
		"……啊，这张是上学期的。你们等我一下。",
		"...Ah. This one is from last term. Give me a moment.",
		NarrativeProvenance.Kind.HEARD
	)
	start.choose(
		&"n_open_ask_b",
		"「B 老师还会来吗？」",
		"\"Is Ms. B coming at all?\"",
		ASK_B,
		[PrologueFlags.ASKED_ABOUT_B],
		[]
	)
	start.choose(
		&"n_open_help",
		"「名单在讲桌抽屉，左边那格。」",
		"\"The list is in the desk drawer. Left side.\"",
		REGISTER,
		[PrologueFlags.N_OFFERED_HELP],
		[{
			"id": &"observed_register_drawer",
			"kind": "observed",
			"zh": "讲桌左边抽屉里有一叠纸。",
			"en": "There is a stack of paper in the left drawer of the teacher's desk."
		}],
		"我怎么知道在那里。这个比不知道还难受。",
		"How do I know that. Worse than not knowing."
	)
	start.choose(
		&"n_open_wait",
		"（安静坐着，看她怎么处理。）",
		"(Sit still and watch how she handles it.)",
		REGISTER,
		[],
		[],
		"她翻纸的声音。比整个教室都大。",
		"The sound of her pages. Louder than the whole room."
	)
	script.add(start)

	# --- She admits the register is a mess -----------------------------------
	var register := DialogueNode.new(REGISTER)
	register.say(
		N,
		"谢谢。啊，真的在。",
		"Thank you. Oh — it really is there.",
		NarrativeProvenance.Kind.HEARD
	)
	register.say(
		N,
		"我不是本科的。我是……代理，先来顶一下。所以如果你们问我太难的问题，我可能会答不出来。",
		"I'm not a biology teacher. I'm... covering. So if you ask me something too hard, I might not be able to answer.",
		NarrativeProvenance.Kind.HEARD
	)
	register.note(
		"她先把自己说小。这样谁都不好怪她。这个做法我认得。认得，是因为我也这样。",
		"She makes herself small first. Then nobody can blame her. I know that move. I know it because I do it too.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	register.go_to(OWN_CLASS)
	script.add(register)

	# --- Asking about B -----------------------------------------------------
	var ask_b := DialogueNode.new(ASK_B)
	ask_b.say(
		N,
		"……我这边只写「教师请假，代课一日」。其他的我没有收到。",
		"...All I have is \"teacher on leave, substitute for one day\". I wasn't given anything else.",
		NarrativeProvenance.Kind.HEARD
	)
	ask_b.say(
		N,
		"你是课代表吗？",
		"Are you the class representative?",
		NarrativeProvenance.Kind.HEARD
	)
	ask_b.choose(
		&"n_ask_not_rep",
		"「不是。只是问一下。」",
		"\"No. Just asking.\"",
		OWN_CLASS,
		[],
		[],
		"她松了一口气。学生不是课代表。不用回答太多。",
		"She looks relieved. I'm not the representative. She doesn't have to answer much."
	)
	ask_b.choose(
		&"n_ask_insist",
		"「她请假，跟考卷的事有关系吗？」",
		"\"Does her leave have anything to do with the exam papers?\"",
		OWN_CLASS,
		[],
		[{
			"id": &"observed_n_hesitation",
			"kind": "observed",
			"zh": "我提到考卷时，N 停了一下才回答。",
			"en": "When I mentioned the papers, N paused before answering."
		}],
		"她停了一下才回答。那一下比回答有内容。",
		"She paused before answering. The pause had more in it."
	)
	ask_b.choose(
		&"n_ask_leave_it",
		"「算了。当我没问。」",
		"\"Never mind. Forget I asked.\"",
		OWN_CLASS,
		[],
		[],
		"我不想从她这里拿答案。至少现在不想。",
		"I don't want the answer from her. Not now."
	)
	script.add(ask_b)

	# --- She tries to teach -------------------------------------------------
	var own_class := DialogueNode.new(OWN_CLASS)
	own_class.say(
		N,
		"那我先带一下进度。课本打开，第五单元……你们上到第五单元了吗？",
		"Let me at least cover the material. Open your books — unit five. Have you done unit five?",
		NarrativeProvenance.Kind.HEARD
	)
	own_class.note(
		"没有人回答。我的手放在桌上。桌上没有课本。",
		"Nobody answers. My hand is on the desk. There's no book under it.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	own_class.say(
		N,
		"好。没关系。那我们……先看一下。",
		"Okay. That's fine. Then we'll just... take a look.",
		NarrativeProvenance.Kind.HEARD
	)
	own_class.note(
		"（后面有人在传东西。她假装没看到，然后又看了一眼。）",
		"(Someone at the back is passing something around. She pretends not to see it, then looks anyway.)",
		NarrativeProvenance.Kind.OBSERVED,
		&"stage"
	)
	own_class.choose(
		&"n_class_sympathy",
		"「老师，你不用勉强。」",
		"\"You don't have to force it, teacher.\"",
		HOLD_BACK,
		[PrologueFlags.N_READ_SYMPATHETIC],
		[]
	)
	own_class.choose(
		&"n_class_skeptic",
		"「所以我们今天到底要做什么？」",
		"\"So what are we actually doing today?\"",
		HOLD_BACK,
		[PrologueFlags.N_READ_SKEPTICAL],
		[],
		"我知道自己口气不好。我没改。",
		"I can hear my own voice. I don't fix it."
	)
	own_class.choose(
		&"n_class_quiet",
		"（继续等她讲完。）",
		"(Keep waiting for her to finish.)",
		HOLD_BACK,
		[PrologueFlags.N_READ_QUIET],
		[]
	)
	script.add(own_class)

	# --- The release --------------------------------------------------------
	var hold_back := DialogueNode.new(HOLD_BACK)
	hold_back.say(
		N,
		"……其实我今天准备得不够。",
		"...Honestly, I didn't prepare enough for today.",
		NarrativeProvenance.Kind.HEARD
	)
	hold_back.say(
		N,
		"与其让大家在这里坐着，不如你们去自习。走廊、图书馆都可以，不要出校门就好。",
		"Rather than have everyone sit here, go self-study. The corridor, the library — anywhere but off campus.",
		NarrativeProvenance.Kind.HEARD
	)
	hold_back.say(
		N,
		"我还是会在教室。有事来找我。如果……如果你们老师问，就说有上课。",
		"I'll stay in the room. Come find me if you need anything. And if — if your teacher asks, say we had class.",
		NarrativeProvenance.Kind.HEARD
	)
	hold_back.set_flags([PrologueFlags.N_LET_CLASS_GO])
	hold_back.record(
		&"heard_free_activity",
		NarrativeProvenance.Kind.HEARD,
		"N 让大家去自习，但不能出校门。",
		"N let the class go for self-study, but we are not to leave the school gate."
	)
	hold_back.choose(
		&"n_release_go",
		"（收东西，走出去。）",
		"(Pack up and go.)",
		RELEASE,
		[],
		[],
		"没有钟声。也没有宣布。课就这样没了。",
		"No bell. No announcement. The lesson just stops existing."
	)
	hold_back.choose(
		&"n_release_ask_again",
		"「她今天真的不会来？」",
		"\"She's really not coming today?\"",
		RELEASE,
		[],
		[{
			"id": &"heard_b_absent_confirmed",
			"kind": "heard",
			"zh": "N 再确认了一次：B 今天请假。",
			"en": "N confirmed again: B is on leave today."
		}],
		"我又问了一次。答案一样。我的感觉不一样。",
		"I ask again. Same answer. Different feeling."
	)
	script.add(hold_back)

	# --- Release: the room empties ------------------------------------------
	var release := DialogueNode.new(RELEASE)
	release.say(
		N,
		"那个……靠窗的同学。你的课本呢？",
		"Um — the student by the window. Where's your textbook?",
		NarrativeProvenance.Kind.HEARD
	)
	release.say(
		N,
		"没关系。去自习吧。",
		"Never mind. Go study.",
		NarrativeProvenance.Kind.HEARD
	)
	release.note(
		"她认得我。因为我坐在第一个会被看到的位置。不是因为她认识我。",
		"She knows me. Because I sit where you get seen first. Not because she knows me.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	release.go_to(LEAVE)
	script.add(release)

	# The last beat of the conversation is the protagonist deciding to go, not the
	# teacher's permission. It is what marks the room as open.
	var leave := DialogueNode.new(LEAVE)
	leave.say(
		Q,
		"那我先走了。你自己看一下要带什么，你每次都忘东忘西。",
		"I'm going then. Check what you're taking — you always leave something behind.",
		NarrativeProvenance.Kind.HEARD
	)
	leave.note(
		"Q 把椅子推回桌子下面。很自然。像他每天都这么做。",
		"Q pushes his chair back under the desk. Easily. Like he does it every day.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	leave.note(
		"教室突然很空。刚才那些不耐烦，那些预演。一个都没用上。",
		"The room is suddenly empty. The impatience. The rehearsal. None of it gets used.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	leave.set_flags([PrologueFlags.LEFT_CLASSROOM])
	script.add(leave)

	return script
