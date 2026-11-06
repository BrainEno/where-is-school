class_name PrologueAnticipation
extends RefCounted
## Beat E — anticipation, and the optional subjective sequence.
##
## This file contains two different things, and the distinction matters:
##
## 1. A short conversation (nodes reached from `anticipation_start`) in which the
##    protagonist weighs what Q said. Everything here happens in the real room.
## 2. An IMAGINED sequence (nodes prefixed `imagine_`) presented with a separate
##    visual treatment. It is the protagonist rehearsing a confrontation with B.
##    Its lines use NarrativeProvenance.Kind.IMAGINED, PrologueFlow records it in
##    the ledger as imagined, and it changes no world state: no door opens, no
##    object moves, no NPC arrives, no flag about B's behavior is written.
##
## The imagined sequence deliberately contains no violence option and no
## explanation of what B is really like. It is one guessed version of a person.

const SELF := &"self"
const B_IMAGINED := &"b_imagined"

const START := &"anticipation_start"
const DECLINED := &"anticipation_declined"
const IMAGINE_START := &"imagine_start"
const IMAGINE_MIDDLE := &"imagine_middle"
const IMAGINE_END := &"imagine_end"


static func build() -> DialogueScript:
	var script := DialogueScript.new(&"prologue_anticipation")
	script.define_character(
		B_IMAGINED, "B（想象）", "B (imagined)",
		Color(0.80, 0.60, 0.52),
		"我猜她会说的话", "what I guess she would say"
	)

	# --- The real room: decide whether to rehearse --------------------------
	var start := DialogueNode.new(START)
	start.note(
		"钟还没响。Q 在假装看书。他那本书翻在同一页，翻很久了。",
		"The bell hasn't rung yet. Q is pretending to read. His book has been on the same page for a long time.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	start.note(
		"如果 B 进来，她会先看谁。从讲台走到我这里，几步。我在脑子里先走了一遍。走完才发现，我在排练。",
		"If B comes in, who does she look at first. From the teacher's desk to my desk, how many steps. I walk it once in my head. Then I notice I'm rehearsing.",
		NarrativeProvenance.Kind.RECOLLECTED,
		&"interior"
	)
	start.choose(
		&"anticipation_rehearse",
		"（想一下如果真的发生，会是什么样子。）",
		"(Think through what it would actually look like.)",
		IMAGINE_START,
		[PrologueFlags.CONFRONTATION_IMAGINED]
	)
	start.choose(
		&"anticipation_refuse",
		"（不要想。想了也只会更紧张。）",
		"(Don't. Thinking about it will only make it worse.)",
		DECLINED,
		[PrologueFlags.CONFRONTATION_DECLINED]
	)
	start.choose(
		&"anticipation_rational",
		"（Q 说她不一定会来。他每次讲话都这样。）",
		"(Q said she might not come. He talks like that every time.)",
		DECLINED,
		[PrologueFlags.EXPECTATION_CHECKED],
		[{
			"id": &"reasoned_q_unreliable",
			"kind": "observed",
			"zh": "我提醒自己：Q 的说法只是 Q 的说法。",
			"en": "I reminded myself: Q's account is only Q's account."
		}]
	)
	script.add(start)

	# --- Declined: the room stays the room --------------------------------
	var declined := DialogueNode.new(DECLINED)
	declined.note(
		"我用小指刮了一下桌上那道笔痕。比看起来深。",
		"I scrape the pen groove with my little finger. Deeper than it looks.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	declined.note(
		"我什么都没想。教室里有电扇。有翻纸的声音。有 Q 假装在看的那一页。",
		"I don't imagine anything. There's a fan. There's paper turning. There's the page Q pretends to read.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(declined)

	# --- Imagined sequence, part one --------------------------------------
	var imagine_start := DialogueNode.new(IMAGINE_START)
	imagine_start.note(
		"（想象。）门被推开。不是 N，是 B。她没有马上走进来，先站在门口数人数。",
		"(Imagined.) The door opens. Not N — B. She doesn't come in at once. She stands in the doorway and counts.",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_start.say(
		B_IMAGINED,
		"（我猜她会说：）「靠窗第二个。你上次的答案，是你自己写的吗？」",
		"(She might say:) \"Second seat by the window. Those answers last time — did you write them yourself?\"",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_start.note(
		"她会把那把木尺放在讲桌上，不敲，只是放。然后等我回答。等她问第二个问题的时候，我就会发现第一个问题我答不出来。",
		"She would set the wooden set square on the desk. Not tap it — just set it down. Then wait. By her second question I would realize I couldn't answer the first.",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_start.go_to(IMAGINE_MIDDLE)
	script.add(imagine_start)

	var imagine_middle := DialogueNode.new(IMAGINE_MIDDLE)
	imagine_middle.note(
		"（想象。）我站起来。椅子往后刮了一声。我的答案排好了，却全部都是关于流程的：谁签的名、表格送去哪里、我什么时候被告知的。",
		"(Imagined.) I stand. The chair scrapes. My answers are lined up, and every one of them is about procedure: who signed, where the form went, when I was told.",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_middle.say(
		B_IMAGINED,
		"（我猜她会说：）「我不是问流程。我是问你。」",
		"(She might say:) \"I'm not asking about procedure. I'm asking you.\"",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_middle.note(
		"（想象。）这一句是我自己补上去的。我没有听过她这样说。我甚至不确定她会不会这样说。",
		"(Imagined.) I supplied that line myself. I have never heard her say it. I'm not even sure she would.",
		NarrativeProvenance.Kind.IMAGINED,
		&"imagined"
	)
	imagine_middle.choose(
		&"imagine_answer_plain",
		"（在想象里，我回答：「是我写的。」）",
		"(In the imagining, I answer: \"I wrote them.\")",
		IMAGINE_END,
		[],
		[],
		"在想象里我答得很稳。醒着的我知道那是想象。",
		"In the imagining I answer steadily. The awake part of me knows that was an imagining."
	)
	imagine_middle.choose(
		&"imagine_answer_silent",
		"（在想象里，我什么都没说。）",
		"(In the imagining, I say nothing at all.)",
		IMAGINE_END,
		[],
		[],
		"在想象里也一样。沉默比回答容易。",
		"Even in an imagining. Silence is easier than answering."
	)
	imagine_middle.choose(
		&"imagine_stop",
		"（停。不要往下想了。）",
		"(Stop. Don't take this any further.)",
		IMAGINE_END,
		[],
		[{
			"id": &"put_down_imagination",
			"kind": "observed",
			"zh": "我自己把那个画面停下了。",
			"en": "I was the one who stopped that scene."
		}]
	)
	script.add(imagine_middle)

	# --- Returning to the room --------------------------------------------
	var imagine_end := DialogueNode.new(IMAGINE_END)
	imagine_end.set_flags([PrologueFlags.IMAGINATION_PLAYED])
	imagine_end.record(
		&"imagined_confrontation",
		NarrativeProvenance.Kind.IMAGINED,
		"我想象过 B 走进来、问我考卷的事。这只是想象。",
		"I imagined B walking in and asking about the papers. That was only an imagining."
	)
	imagine_end.note(
		"（回到教室。）电扇还在转。Q 的课本还是那一页。讲台上没有木尺。",
		"(Back in the room.) The fan is still turning. Q's book is on the same page. There's no set square on the teacher's desk.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	imagine_end.note(
		"我把手放回桌面。笔痕还在原来的地方。什么都没有发生。",
		"I put my hand back on the desk. The groove is where it was. Nothing happened.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	script.add(imagine_end)

	return script
