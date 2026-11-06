class_name PrologueQConversation
extends RefCounted
## Beat B — Q starts talking.
##
## Authoring notes (not shown in game):
## - Q talks about ordinary things: the last lesson of the term, the exam that has
##   not been handed back, whether a teacher will show up. He never explains the
##   world and never offers the protagonist a task.
## - He is overfamiliar but not sinister: he misreads the protagonist's silence as
##   agreement, which is what makes him a little tiring.
## - Every claim he makes is recorded as HEARD, never as fact. The confrontation
##   he describes is a threat in Q's mouth, not an event in the world.
## - The protagonist's uncertainty about Q is available, never compulsory.

# Character ids used by PrologueFlow when building the dialogue panel.
const Q := &"q"
const SELF := &"self"

const START := &"q_start"
const SMALLTALK := &"q_smalltalk"
const SILENCE := &"q_silence"
const PUSHBACK := &"q_pushback"
const EXAM := &"q_exam"
const TEACHER := &"q_teacher"
const OUTRO := &"q_outro"


static func build() -> DialogueScript:
	var script := DialogueScript.new(&"prologue_q")
	script.define_character(
		Q, "Q", "Q",
		Color(0.86, 0.72, 0.48),
		"隔壁座位的同学", "the classmate in the next seat"
	)

	# --- Opening: he starts talking on his own, no marker, no prompt ----------
	var start := DialogueNode.new(START)
	start.say(
		Q,
		"醒了？你刚才整个人都趴下去了，我以为你又要睡到第二节。",
		"You're up. You went down completely just now — I thought you'd sleep through second period again.",
		NarrativeProvenance.Kind.HEARD
	)
	start.say(
		Q,
		"（他侧坐着，一条腿伸到过道上。像是这个位子本来就是他的。）",
		"(He sits sideways, one leg out in the aisle. Like this seat was always his.)",
		NarrativeProvenance.Kind.OBSERVED,
		&"stage"
	)
	start.say(
		Q,
		"跟我猜的一样。你连书包都没拉开。",
		"Just like I said. You haven't even opened your bag.",
		NarrativeProvenance.Kind.HEARD
	)
	start.note(
		"我刚刚是真的睡着了。可是我不记得自己是怎么趴下去的。",
		"I really was asleep just now. But I don't remember putting my head down.",
		NarrativeProvenance.Kind.RECOLLECTED,
		&"interior"
	)
	start.choose(
		&"q_choice_agree",
		"「第二节？现在第几节？」",
		"\"Second period? What period is it now?\"",
		SMALLTALK,
		[PrologueFlags.Q_ALLOWED_SMALLTALK],
		[{
			"id": &"heard_time_uncertain",
			"kind": "heard",
			"zh": "Q 说我睡掉了不只一节课。",
			"en": "Q says I slept through more than one period.",
		}]
	)
	start.choose(
		&"q_choice_pushback",
		"「你讲话的方式，好像我们很熟。」",
		"\"You talk like we know each other well.\"",
		PUSHBACK,
		[PrologueFlags.Q_PUSHBACK],
		[{
			"id": &"heard_q_knows_me",
			"kind": "heard",
			"zh": "Q 认为我们很熟。",
			"en": "Q is certain we know each other well.",
		}],
		"这个位子靠窗。桌面上有一道旧笔痕。是我划的吗。我不知道。",
		"This seat is by the window. There's an old pen groove on the desk. Did I make it. I don't know."
	)
	start.choose(
		&"q_choice_silent",
		"（不回答，先看看他到底要讲什么。）",
		"(Say nothing and see how much he fills in by himself.)",
		SILENCE,
		[PrologueFlags.Q_ALLOWED_SMALLTALK],
		[],
		"我没说话。这样也算回答吗。反正他当成是了。",
		"I didn't say anything. Does that count as an answer. He took it as one anyway."
	)
	script.add(start)

	# --- Silence: Q fills the gap by himself ------------------------------
	var silence := DialogueNode.new(SILENCE)
	silence.note(
		"我没接话。他等了一会儿。然后就把我的沉默当成同意了。",
		"I didn't answer. He waited a while. Then he just took my silence as a yes.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	silence.say(
		Q,
		"对，就是这样。你每次睡醒都这个表情。",
		"Right, exactly. You always make that face when you wake up.",
		NarrativeProvenance.Kind.HEARD
	)
	silence.choose(
		&"q_silence_let_it_go",
		"（让他说。）",
		"(Let him talk.)",
		SMALLTALK,
		[],
		[],
		"我先让他讲。我现在不太想开口。不太想。",
		"I let him keep going. I don't really want to talk yet. Not really."
	)
	silence.choose(
		&"q_silence_cut_in",
		"「你怎么知道我刚睡醒？」",
		"\"How do you know I just woke up?\"",
		SMALLTALK,
		[],
		[{
			"id": &"observed_q_watching",
			"kind": "observed",
			"zh": "我醒来的时候，Q 已经在看着我了。",
			"en": "Q was already looking at me when I woke up."
		}],
		"他答不上来。或者不想答。他换了个话题。换得有点快。",
		"He couldn't answer. Or didn't want to. He changed the subject. Kind of fast."
	)
	script.add(silence)

	# --- Smalltalk branch -----------------------------------------------------
	var smalltalk := DialogueNode.new(SMALLTALK)
	smalltalk.say(
		Q,
		"第三节。你上节课是真能睡，趴下去就没动静了，我叫你两次。",
		"Third period. You really went out last class — down and nothing. I called you twice.",
		NarrativeProvenance.Kind.HEARD
	)
	smalltalk.say(
		Q,
		"不用紧张，今天这节是生物。最后一学期了，老师通常会放水。",
		"Relax, this one's biology. It's the last term, teachers usually go soft.",
		NarrativeProvenance.Kind.HEARD
	)
	smalltalk.say(
		Q,
		"……不过是 B 的课，就很难说。",
		"...Then again, it's B's class, so who knows.",
		NarrativeProvenance.Kind.HEARD
	)
	smalltalk.record(
		&"heard_last_term",
		NarrativeProvenance.Kind.HEARD,
		"Q 说这是最后一学期。",
		"Q says this is the final term."
	)
	smalltalk.choose(
		&"q_smalltalk_remember",
		"「最后一学期……对。」（假装记得。）",
		"\"Final term... right.\" (Pretend to remember.)",
		EXAM,
		[],
		[{
			"id": &"recollection_final_term",
			"kind": "recollected",
			"zh": "「最后一学期」听起来对，但我想不起来这学期是从哪天开始的。",
			"en": "\"Final term\" sounds right, but I can't remember when this term started.",
		}],
		"最后一学期。这四个字我念了一遍。是我知道的，还是他说的。",
		"Final term. I say the words to myself. Do I know that. Or did he just say it."
	)
	smalltalk.choose(
		&"q_smalltalk_admit",
		"「我不太记得你了。对不起。」",
		"\"I don't really remember you. Sorry.\"",
		EXAM,
		[PrologueFlags.ADMITTED_FORGOT_Q],
		[{
			"id": &"said_forgot_q",
			"kind": "observed",
			"zh": "我告诉 Q，我不太记得他。",
			"en": "I told Q that I don't really remember him.",
		}],
		"说出来了。尴尬的不是他。是我。",
		"I said it. He wasn't the embarrassed one. I was."
	)
	smalltalk.choose(
		&"q_smalltalk_deflect",
		"「B 的课。她人怎样？」",
		"\"B's class. What is she like?\"",
		TEACHER,
		[PrologueFlags.ASKED_ABOUT_B],
		[],
		"我问太快了。快得连我自己都听得出来，我在换话题。",
		"I asked too fast. Fast enough that even I could hear myself changing the subject."
	)
	script.add(smalltalk)

	# --- Pushback branch ------------------------------------------------------
	var pushback := DialogueNode.new(PUSHBACK)
	pushback.say(
		Q,
		"熟啊。你上学期坐我前面，桌子歪的那一张就是你的。",
		"Of course we're close. Last term you sat in front of me. The crooked desk was yours.",
		NarrativeProvenance.Kind.HEARD
	)
	pushback.say(
		Q,
		"这种事我记得很清楚。你反而不记得我，有点过分。",
		"I remember this kind of thing clearly. You not remembering me — that's a little harsh.",
		NarrativeProvenance.Kind.HEARD
	)
	pushback.note(
		"他是真的不高兴了。不是装的。这个比被他说谎难办。",
		"He's actually upset. Not pretending. That's harder than if he were lying.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	pushback.choose(
		&"q_pushback_back_off",
		"「好，我坐前面。然后呢？」",
		"\"Fine. I sat in front. Then what?\"",
		EXAM,
		[],
		[{
			"id": &"recollection_seat",
			"kind": "recollected",
			"zh": "他说的那张歪桌子，我好像有一点印象。只有一点。",
			"en": "I might have a vague impression of the crooked desk he described. Only vague.",
		}],
		"我让他以为我有一点印象。就给这么一点。",
		"I let him think I remember a little. Just that much."
	)
	pushback.choose(
		&"q_pushback_stay_cold",
		"「你记得很清楚，我记得很模糊。事情就是这样。」",
		"\"You remember it clearly. I remember it vaguely. That's how it is.\"",
		EXAM,
		[],
		[],
		"他没说话。电扇转过去，又转回来。",
		"He didn't say anything. The fan turned away, then back."
	)
	script.add(pushback)

	# --- The exam ------------------------------------------------------------
	var exam := DialogueNode.new(EXAM)
	exam.say(
		Q,
		"上次那张生物考卷，你觉得会发回来吗？",
		"Do you think we'll ever get that biology paper back?",
		NarrativeProvenance.Kind.HEARD
	)
	exam.say(
		Q,
		"都过多久了。教务处说要重算，讲到现在也没有下文。",
		"How long has it been? The office said they'd recalculate it, and then nothing.",
		NarrativeProvenance.Kind.HEARD
	)
	exam.record(
		&"heard_exam_pending",
		NarrativeProvenance.Kind.HEARD,
		"Q 说上次的生物考卷被送去重算，还没有结果。",
		"Q says the last biology paper was sent back for recalculation and there is still no result."
	)
	exam.say(
		Q,
		"分数我倒觉得无所谓。不过你那天被叫去问话，回来脸很白。",
		"I don't think the score matters much. But you got called in that day, and you came back looking pale.",
		NarrativeProvenance.Kind.HEARD
	)
	exam.note(
		"被叫去问话。有这回事吗。他讲得太顺了。顺到我开始想，是不是我忘了。",
		"Called in. Did that happen. He says it so smoothly. Smooth enough that I start thinking maybe I'm the one who forgot.",
		NarrativeProvenance.Kind.RECOLLECTED,
		&"interior"
	)
	exam.choose(
		&"q_exam_doubt",
		"「我没印象被叫去问话。」",
		"\"I don't remember being called in.\"",
		TEACHER,
		[PrologueFlags.DOUBTED_EXAM_ACCOUNT],
		[{
			"id": &"said_doubt_exam",
			"kind": "observed",
			"zh": "我告诉 Q，我不记得被叫去问话。",
			"en": "I told Q that I don't remember being called in."
		}],
		"我没说他撒谎。我说的是我没印象。这两个不一样。大概吧。",
		"I didn't say he lied. I said I don't remember. Those aren't the same. I think."
	)
	exam.choose(
		&"q_exam_accept",
		"「大概是吧。那天很乱。」",
		"\"Probably. That day was a mess.\"",
		TEACHER,
		[PrologueFlags.ACCEPTED_EXAM_ACCOUNT],
		[{
			"id": &"recollection_exam_day",
			"kind": "recollected",
			"zh": "我顺着他的话，假装那一天是「很乱」。我真的不知道那天是什么样子。",
			"en": "I agreed, and let the day be \"a mess\". I have no idea what that day was actually like."
		}],
		"很乱。这么说最省事。省事到我自己都觉得难听。",
		"A mess. Easiest thing to say. So easy it sounded bad in my own mouth."
	)
	exam.choose(
		&"q_exam_skip",
		"（先不接话，把这个问题放着。）",
		"(Let the question sit. Don't take it.)",
		TEACHER,
		[],
		[],
		"我没接。这个问题放着。放着的东西不会自己走掉。",
		"I let it sit. Left-over things don't go away by themselves."
	)
	script.add(exam)

	# --- B, indirectly -------------------------------------------------------
	var teacher := DialogueNode.new(TEACHER)
	teacher.say(
		Q,
		"B 啊。她不凶，她是那种……会记在心里的。",
		"B? She's not mean. She's the type who... keeps things.",
		NarrativeProvenance.Kind.HEARD
	)
	teacher.say(
		Q,
		"上学期有人被她叫去办公室，回来一句话都不讲。不是骂，是一句一句问。",
		"Last term she called someone to the office and they came back without a word. She doesn't shout. She asks one question at a time.",
		NarrativeProvenance.Kind.HEARD
	)
	teacher.say(
		Q,
		"她那把木尺也很恐怖。不是拿来打的，是拿来敲桌子的，敲一下全班都安静。",
		"Her wooden set square is the worst part. She doesn't hit anyone with it — she taps the desk with it and the whole room shuts up.",
		NarrativeProvenance.Kind.HEARD
	)
	teacher.say(
		Q,
		"总之今天如果她来，你就……不要第一个讲话。",
		"Anyway, if she shows up today, just... don't be the first one to talk.",
		NarrativeProvenance.Kind.HEARD
	)
	teacher.set_flags([PrologueFlags.HEARD_SET_SQUARE])
	teacher.record(
		&"heard_b_questions",
		NarrativeProvenance.Kind.HEARD,
		"Q 说 B 不吼人，她一句一句地问。",
		"Q says B doesn't shout. She asks you one question at a time."
	)
	teacher.choose(
		&"q_teacher_not_first",
		"「不要第一个讲话。好。」",
		"\"Don't be the first to talk. Okay.\"",
		OUTRO,
		[],
		[],
		"我干嘛要听他的。",
		"Why am I listening to him."
	)
	teacher.choose(
		&"q_teacher_square",
		"「木尺？她还在用那个？」",
		"\"A wooden set square? She still uses that?\"",
		OUTRO,
		[],
		[{
			"id": &"recollection_square",
			"kind": "recollected",
			"zh": "木尺敲桌子的声音，我好像听过。也可能只是被他讲到有画面。",
			"en": "The sound of a wooden set square on a desk feels familiar. Or he just described it well enough to give me one.",
		}],
		"「还在用」这三个字是我自己说的。我怎么会用「还」？",
		"I said \"still\" myself. Why would I say \"still\"?"
	)
	teacher.choose(
		&"q_teacher_dismiss",
		"「她来不来都一样。我没差。」",
		"\"It makes no difference whether she comes. I don't care.\"",
		OUTRO,
		[],
		[],
		"说完了。这种话说出来，通常就是有差。",
		"Said it. People only say that when it does matter."
	)
	script.add(teacher)

	# --- Outro: the conversation hands control back -------------------------
	var outro := DialogueNode.new(OUTRO)
	outro.set_flags([PrologueFlags.Q_INTRO_SEEN])
	outro.say(
		Q,
		"我先看一下我的书。你也是，至少把课本拿出来放桌上，看起来比较像有在准备。",
		"I'm going to look at my book. You should too — put your textbook on the desk at least. It looks better.",
		NarrativeProvenance.Kind.HEARD
	)
	outro.say(
		Q,
		"……虽然我觉得今天她不一定会来。",
		"...Though I don't think she's coming today.",
		NarrativeProvenance.Kind.HEARD
	)
	script.add(outro)

	return script
