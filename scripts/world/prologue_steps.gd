class_name PrologueSteps
extends RefCounted
## The prologue's steps and the story flags that prove each one is over.
##
## Split out of `OpeningSequence` (issue #223). The director *runs* the steps; this table
## is the only thing that says where the player is in them, and it remembers nothing of
## its own: every answer is read from the flags it is given. Starting the game and resuming
## a save are therefore the same question, and a test can ask it without a scene.

## The prologue, in order. Each step is identified by the flag that proves it is done.
const STEPS: Array[StringName] = [
	&"wake", &"q_wake", &"bag", &"expectation", &"bell", &"substitute",
]


## Index into `STEPS` of the first step the flags say is not done; `STEPS.size()` when
## the prologue is over. `has_flag(flag) -> bool` reads the story.
static func first_pending(has_flag: Callable) -> int:
	for index in STEPS.size():
		if not is_done(STEPS[index], has_flag):
			return index
	return STEPS.size()


## The step that comes next, or `&""` when the prologue is over.
static func next(has_flag: Callable) -> StringName:
	var index := first_pending(has_flag)
	if index >= STEPS.size():
		return &""
	return STEPS[index]


## True when `step` is behind the player: its own proof is set, or the proof of any
## step after it is.
##
## Progress only moves forward. The steps run in order, so a later step's flag is proof
## that every step before it closed, whichever way it closed - and a reload can never
## put a finished step back in front of the player. That is also what keeps saves
## written before `bag_wait_expired` / `expectation_skipped` existed working: a player
## who let the bag step run out has `bell_rung` and `class_dismissed`, and those are
## enough. An unknown step counts as done, so it is never run.
static func is_done(step: StringName, has_flag: Callable) -> bool:
	var index := STEPS.find(step)
	if index < 0:
		return true
	for later in range(index, STEPS.size()):
		if is_proved(STEPS[later], has_flag):
			return true
	return false


## True when the flag that proves `step` itself happened is set.
##
## This table is the prologue's only memory. Two steps share `met_q` because the
## wake has no flag of its own and cannot outlive Q's first line. The bag step closes
## either way the player can close it - the bag searched, or the fallback run out - and
## the expectation beat is either played or skipped because the bag was not searched;
## each of those has its own flag, so nothing the player did not do is ever claimed.
## `substitute` ends at `class_dismissed` rather than at `n_arrived`, because N arriving
## without the conversation that dismisses the class would leave the door locked forever.
static func is_proved(step: StringName, has_flag: Callable) -> bool:
	match step:
		&"wake", &"q_wake":
			return bool(has_flag.call(StoryFlags.MET_Q))
		&"bag":
			return bool(has_flag.call(StoryFlags.TEXTBOOK_MISSING)) \
				or bool(has_flag.call(StoryFlags.BAG_WAIT_EXPIRED))
		&"expectation":
			return bool(has_flag.call(StoryFlags.EXPECTATION_PLAYED)) \
				or bool(has_flag.call(StoryFlags.EXPECTATION_SKIPPED))
		&"bell":
			return bool(has_flag.call(StoryFlags.BELL_RUNG))
		&"substitute":
			return bool(has_flag.call(StoryFlags.CLASS_DISMISSED))
	return true
