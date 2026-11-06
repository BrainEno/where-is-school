class_name StreetObservations
extends RefCounted
## Second milestone — the residential street outside the school gate.
##
## Two things happen here, and they are deliberately different in kind:
##
## 1. The release. The protagonist stands outside and notices that the
##    anticipation, the corridor, and the gate have all been survived without
##    anything being resolved. Nothing is explained.
## 2. A green animal is briefly visible near the planter and then is not. The
##    game must not name a species, decide what it was, or confirm that it
##    happened. The player may choose to trust the sighting or to doubt it, and
##    both readings are recorded with their own provenance.
##
## Written independently for the game. No manuscript description is used.

const SELF := &"self"

const START := &"street_start"


static func build() -> DialogueScript:
	var script := DialogueScript.new(&"prologue_street")
	script.define_character(
		SELF, "我", "me",
		Color(0.84, 0.82, 0.76),
		"内心", "interior"
	)

	var start := DialogueNode.new(START)
	start.set_flags([PrologueFlags.STREET_ENTERED])
	start.record(
		&"observed_street",
		NarrativeProvenance.Kind.OBSERVED,
		"校门外是一条普通的巷子。电动车停在楼下，对面有人在阳台晒衣服。",
		"Outside the gate is an ordinary lane. Scooters are parked under the arcade; someone across the street is hanging laundry."
	)
	start.note(
		"钟声在背后。隔一道墙就变得很小。学校的声音出不了校门。",
		"The bell is behind me. One wall away and it's already small. The school's sound doesn't leave the gate.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	start.note(
		"没有人追出来。没有人叫我的名字。我以为会有一个人。",
		"No one follows me out. No one calls my name. I had assumed there would be someone.",
		NarrativeProvenance.Kind.RECOLLECTED,
		&"interior"
	)
	start.choose(
		&"street_keep_walking",
		"（往外走。不要回头。）",
		"(Keep walking out. Don't look back.)",
		&"street_walk",
		[PrologueFlags.STREET_RELEASE_NOTED],
		[],
		"我没回头。不是勇敢。是回头就等于承认我在意。",
		"I didn't look back. Not because I'm brave. Because looking back would mean admitting I care."
	)
	start.choose(
		&"street_look_back",
		"（回头看一次校门。）",
		"(Look back at the gate once.)",
		&"street_walk",
		[],
		[{
			"id": &"observed_gate_from_outside",
			"kind": "observed",
			"zh": "从外面看，校门比里面看的时候矮。",
			"en": "From the outside, the gate looks lower than it did from within."
		}],
		"从里面看那扇门很高。从外面看，就是两个水泥柱子。",
		"From inside the gate looked tall. From outside it is two concrete pillars."
	)
	script.add(start)

	var walk := DialogueNode.new(&"street_walk")
	walk.note(
		"我沿着楼下走。前面的巷子接出去就是马路。马路上有公交车。这条路是能走完的。",
		"I walk along under the buildings. The lane opens onto a road. There are buses on it. This road can be walked to the end.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	walk.note(
		"花台旁边，有一小团绿色的东西停了一下。",
		"Beside the planter, something small and green stops for a moment.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	walk.choose(
		&"street_look_closer",
		"（停下来，看清楚。）",
		"(Stop and look properly.)",
		&"street_animal",
		[]
	)
	walk.choose(
		&"street_keep_going",
		"（不停。今天看过的东西已经够了。）",
		"(Don't stop. I've looked at enough things today.)",
		&"street_leave_it",
		[],
		[],
		"我没停。有些东西看清楚以后，就要开始解释。",
		"I didn't stop. Some things, once you see them clearly, demand an explanation."
	)
	script.add(walk)

	# --- The animal --------------------------------------------------------
	var animal := DialogueNode.new(&"street_animal")
	animal.set_flags([PrologueFlags.ANIMAL_GLIMPSED])
	animal.record(
		&"observed_green_animal",
		NarrativeProvenance.Kind.OBSERVED,
		"花台边有一只绿色的动物。我没有看清楚它是什么。",
		"There was a green animal by the planter. I did not see clearly what it was."
	)
	animal.note(
		"它是绿的，比猫长一点，比狗小很多。四只脚。它看着我这边，但没有看我的脸。",
		"It was green, longer than a cat, much smaller than a dog. Four legs. It was facing my way, but not at my face.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	animal.note(
		"我往前走一步。它就不见了。不是跑掉——我没有看到它跑。树丛没有动。",
		"I take one step forward. It's gone. Not gone by running. I didn't see it run. The bushes didn't move.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	animal.choose(
		&"animal_trust_eyes",
		"（我看到了。就是这样。）",
		"(I saw it. That's all.)",
		&"street_after_animal",
		[],
		[],
		"我不打算给它分类。它是绿的。它在花台旁边。然后它不在了。",
		"I'm not going to classify it. It was green. It was by the planter. Then it wasn't there."
	)
	animal.choose(
		&"animal_doubt_eyes",
		"（我今天太累了。那可能只是塑胶袋。）",
		"(I'm tired today. It was probably a plastic bag.)",
		&"street_after_animal",
		[PrologueFlags.DOUBTED_ANIMAL],
		[{
			"id": &"doubted_green_animal",
			"kind": "recollected",
			"zh": "我告诉自己那可能只是塑胶袋。我没有真的相信。",
			"en": "I told myself it was probably a plastic bag. I didn't really believe it."
		}]
	)
	animal.choose(
		&"animal_look_again",
		"（再看一次。蹲下来看。）",
		"(Look again. Crouch down.)",
		&"street_look_again",
		[],
		[]
	)
	script.add(animal)

	var look_again := DialogueNode.new(&"street_look_again")
	look_again.set_flags([PrologueFlags.ANIMAL_NOT_FOUND_AGAIN])
	look_again.note(
		"花台里只有土、烟头、几片被风吹进去的卷子。没有绿色的动物。",
		"Only soil in the planter. Cigarette ends. A couple of test papers blown in. No green animal.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	look_again.note(
		"我蹲在那里。像在找一个自己弄丢的东西。",
		"I crouch there. Like I'm looking for something I put down myself.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	# Looking a second time must not swallow the question of what the animal was:
	# the same three readings are still available afterwards.
	look_again.choose(
		&"again_trust_eyes",
		"（没看到就没看到。我第一次确实看到了。）",
		"(Not seeing it now doesn't undo seeing it. I saw it the first time.)",
		&"street_after_animal",
		[],
		[],
		"我不打算给它分类。它是绿的。它在花台旁边。然后它不在了。",
		"I'm not going to classify it. It was green. It was by the planter. Then it wasn't there."
	)
	look_again.choose(
		&"again_doubt_eyes",
		"（我今天太累了。那可能只是塑胶袋。）",
		"(I'm tired today. It was probably a plastic bag.)",
		&"street_after_animal",
		[PrologueFlags.DOUBTED_ANIMAL],
		[{
			"id": &"doubted_green_animal",
			"kind": "recollected",
			"zh": "我告诉自己那可能只是塑胶袋。我没有真的相信。",
			"en": "I told myself it was probably a plastic bag. I didn't really believe it."
		}]
	)
	look_again.choose(
		&"again_leave_it",
		"（不看了。站起来，走。）",
		"(Stop looking. Stand up. Walk.)",
		&"street_after_animal",
		[],
		[],
		"我站起来。膝盖比我预期的酸。",
		"I stand up. My knees ache more than I expected."
	)
	script.add(look_again)

	var leave_it := DialogueNode.new(&"street_leave_it")
	leave_it.note(
		"走出去的时候，花台旁边什么都没有。也可能有。只是我没看。",
		"On my way out there's nothing by the planter. Or there is, and I didn't look.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	leave_it.go_to(&"street_after_animal")
	script.add(leave_it)

	# --- Closing beat ------------------------------------------------------
	var after := DialogueNode.new(&"street_after_animal")
	after.note(
		"马路上有公交车过去。我还有时间，还有明天的一节课。",
		"A bus goes past on the road. I still have time. And there's still tomorrow's lesson.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	after.note(
		"我把书包的拉链拉好。里面没有生物课本。明天也一样。",
		"I zip my bag shut. No biology textbook in it. Same tomorrow.",
		NarrativeProvenance.Kind.OBSERVED,
		&"interior"
	)
	after.set_flags([PrologueFlags.EXIT_REACHED])
	script.add(after)

	return script
