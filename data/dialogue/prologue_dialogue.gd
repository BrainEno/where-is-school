extends RefCounted
class_name PrologueDialogue
## Authored dialogue content for the biology-class prologue.
##
## All text here is new placeholder prose written for this game. It is not
## adapted from, and does not paraphrase, any unpublished manuscript. Replace it
## only with game dialogue the owner has approved.
##
## Speaker ids come from CharacterDirectory. Record ids come from PrologueRecords.
## Flags come from PrologueFlags. Content never touches the scene tree.

const Q := &"q"
const N := &"n"
const B := &"b"
const YOU := &"protagonist"


# --- Q's opening conversation ----------------------------------------------
#
# Q opens the game without being approached: Q is already talking when the
# player regains control. The conversation establishes the terms of the scene
# through ordinary chatter, and lets the player push back or go quiet.

static func q_conversation() -> DialogueScript:
	var script := DialogueScript.create(&"q_opening", "Q at the next desk")

	script.add(
		DialogueNode.create(&"q_start")
		.with_aside("Someone is already halfway through a sentence when the room comes back.")
		.with_speaker_line(Q, "—and then the whole second row moved up, which is why your desk is where it is. So it's not your fault. Legally.")
		.with_next(&"q_main")
	)

	script.add(
		DialogueNode.create(&"q_main")
		.with_speaker_line(Q, "Oh, you're up. Good. I've been talking to the back of your head for ten minutes.")
		.with_speaker_line(Q, "Third period. First week. Biology.")
		.with_flag(PrologueFlags.Q_TALKED, true)
		.with_next(&"q_first_choice")
	)

	script.add(
		DialogueNode.create(&"q_first_choice")
		.with_speaker_line(Q, "You have that face on. The one that means you're deciding whether to be normal today.")
		.with_choice(
			DialogueChoice.make(&"q_play_along", "“Third period. Right. Morning.”", &"q_play_along_reply")
			.with_flag(PrologueFlags.Q_ATTITUDE, PrologueFlags.Q_ATTITUDE_DEFLECTIVE)
			.with_hint("Hand Q something to work with.")
		)
		.with_choice(
			DialogueChoice.make(&"q_ask_name", "“Remind me who you are.”", &"q_name_reply")
			.with_flag(PrologueFlags.Q_ATTITUDE, PrologueFlags.Q_ATTITUDE_GUARDED)
			.with_record(PrologueRecords.ID_Q_UNFAMILIAR)
			.with_hint("You do not have a face to attach to him.")
		)
		.with_choice(
			DialogueChoice.make(&"q_silent", "（Say nothing, just look at him.)", &"q_silence_reply")
			.with_flag(PrologueFlags.Q_ATTITUDE, PrologueFlags.Q_ATTITUDE_GUARDED)
			.with_hint("Let the silence do the work.")
		)
	)

	# --- 1. deflection ---
	script.add(
		DialogueNode.create(&"q_play_along_reply")
		.with_speaker_line(YOU, "Third period. Right. Morning.")
		.with_speaker_line(Q, "Ha. You're doing the voice.")
		.with_speaker_line(Q, "Anyway. About last term's exam.")
		.with_next(&"q_exam")
	)

	# --- 2. honest non-recognition ---
	script.add(
		DialogueNode.create(&"q_name_reply")
		.with_aside("The name is right there, at the front of your mouth. It is the rest of Q that will not connect.")
		.with_speaker_line(YOU, "Remind me who you are.")
		.with_speaker_line(Q, "Q! Come on. Really?")
		.with_speaker_line(Q, "Q. Long time. You sat behind me all last term. I copied your handwriting badly for a whole paper and got a C for it.")
		.with_speaker_line(Q, "That's a joke. It was a B.")
		.with_flag(PrologueFlags.Q_ADMITTED_FORGOTTEN, true)
		.with_record(PrologueRecords.ID_Q_RECOGNITION)
		.with_next(&"q_exam")
	)

	# --- 3. silence ---
	script.add(
		DialogueNode.create(&"q_silence_reply")
		.with_aside("You look at Q and say nothing. About four seconds into the silence it starts to cost something.")
		.with_speaker_line(Q, "Okay. Right. Low blood sugar. I have a biscuit if you want. It's mostly crumbs now.")
		.with_speaker_line(Q, "Forget I said the face thing.")
		.with_record(PrologueRecords.ID_Q_RECOGNITION)
		.with_next(&"q_exam")
	)

	# --- shared: the exam and the missing paper ---
	script.add(
		DialogueNode.create(&"q_exam")
		.with_speaker_line(Q, "The last biology exam. Did you ever see your paper again?")
		.with_speaker_line(Q, "Because I heard she keeps the ones she can't mark. Like, keeps them. In the cupboard.")
		.with_choice(
			DialogueChoice.make(&"q_exam_blank", "“I left most of it empty.”", &"q_exam_blank_reply")
			.with_record(PrologueRecords.ID_Q_EXAM)
			.with_flag(PrologueFlags.Q_MENTIONED_LAST_EXAM, true)
		)
		.with_choice(
			DialogueChoice.make(&"q_exam_deny", "“That was two years ago.”", &"q_exam_deny_reply")
			.with_record(PrologueRecords.ID_Q_EXAM_DENIED)
			.with_flag(PrologueFlags.Q_MENTIONED_LAST_EXAM, true)
			.with_hint("Say it with more confidence than you have.")
		)
		.with_choice(
			DialogueChoice.make(&"q_exam_evade", "“Whose paper was it?”", &"q_exam_evade_reply")
			.with_record(PrologueRecords.ID_Q_EXAM_EVADED)
			.with_flag(PrologueFlags.Q_MENTIONED_LAST_EXAM, true)
		)
	)

	script.add(
		DialogueNode.create(&"q_exam_blank_reply")
		.with_speaker_line(Q, "Yeah. Half the labels empty, and the diagram filled in wrong. I saw.")
		.with_speaker_line(Q, "Don't take that as me looking. Everyone looks.")
		.with_next(&"q_reputation")
	)

	script.add(
		DialogueNode.create(&"q_exam_deny_reply")
		.with_speaker_line(Q, "Two years ago? It was June. There were cicadas.")
		.with_speaker_line(Q, "You're doing the thing where you move the date until it stops being your problem.")
		.with_speaker_line(Q, "I do it too. It doesn't work on her.")
		.with_next(&"q_reputation")
	)

	script.add(
		DialogueNode.create(&"q_exam_evade_reply")
		.with_speaker_line(Q, "Yours. Obviously yours. I was in the row behind.")
		.with_speaker_line(Q, "Although. Huh. It was a while ago.")
		.with_aside("He does not sound quite sure. Neither do you.")
		.with_next(&"q_reputation")
	)

	# --- B's reputation, conveyed as gossip rather than exposition ---
	script.add(
		DialogueNode.create(&"q_reputation")
		.with_speaker_line(Q, "She's got third period on the timetable, so. She'll be in at the bell.")
		.with_speaker_line(Q, "She remembers faces. She remembers reasons, too, which is worse.")
		.with_speaker_line(Q, "If you don't have the textbook, don't do the thing where you say you forgot it.")
		.with_record(PrologueRecords.ID_Q_REPUTATION)
		.with_next(&"q_reputation_choice")
	)

	script.add(
		DialogueNode.create(&"q_reputation_choice")
		.with_choice(
			DialogueChoice.make(&"q_ask_what_happens", "“What does she actually do?”", &"q_what_happens_reply")
			.with_record(PrologueRecords.ID_Q_REPUTATION_WHAT)
		)
		.with_choice(
			DialogueChoice.make(&"q_ask_set_square", "“She still uses that set square?”", &"q_set_square_reply")
			.with_record(PrologueRecords.ID_Q_REPUTATION_RULER)
		)
		.with_choice(
			DialogueChoice.make(&"q_stop_talking", "“I'd rather find out by myself.”", &"q_stop_reply")
			.with_flag(PrologueFlags.Q_ATTITUDE, PrologueFlags.Q_ATTITUDE_WARM)
		)
	)

	script.add(
		DialogueNode.create(&"q_what_happens_reply")
		.with_speaker_line(Q, "Nothing dramatic. She stands at your desk and waits until the room notices.")
		.with_speaker_line(Q, "Then she asks a question she already knows the answer to. That's the whole trick.")
		.with_next(&"q_rehearsal")
	)

	script.add(
		DialogueNode.create(&"q_set_square_reply")
		.with_speaker_line(Q, "The ruler? She hasn't hit anyone with it since. I don't think.")
		.with_speaker_line(Q, "It lives on her desk. You're not supposed to look at it, so everyone looks at it.")
		.with_next(&"q_rehearsal")
	)

	script.add(
		DialogueNode.create(&"q_stop_reply")
		.with_speaker_line(Q, "Suit yourself. I'll be enjoying this from here.")
		.with_speaker_line(Q, "Seriously though. Rehearse it once so you don't do it for the first time in front of her.")
		.with_next(&"q_rehearsal")
	)

	script.add(
		DialogueNode.create(&"q_rehearsal")
		.with_speaker_line(Q, "Anyway. Bag's under your chair. Check it before the bell, not after.")
		.with_flag(PrologueFlags.Q_MENTIONED_REHEARSAL, true)
		.with_record(PrologueRecords.ID_Q_REHEARSAL)
		.with_next(&"q_end")
	)

	script.add(
		DialogueNode.create(&"q_end")
		.with_aside("Q turns to the row behind and starts talking to the desks as if they had been listening all along.")
		.with_next(&"")
	)

	script.start_id = &"q_start"
	return script


# --- Q's short barks for repeated interactions ------------------------------

static func q_repeat() -> DialogueScript:
	var script := DialogueScript.create(&"q_repeat", "Q, again")
	script.add(
		DialogueNode.create(&"q_repeat_start")
		.with_speaker_line(Q, "I'm not going anywhere. Neither is the bell.")
		.with_next(&"")
	)
	script.start_id = &"q_repeat_start"
	return script


static func q_after_bell() -> DialogueScript:
	var script := DialogueScript.create(&"q_after_bell", "Q, after the bell")
	script.add(
		DialogueNode.create(&"q_after_bell_start")
		.with_speaker_line(Q, "Not now. She's coming up the stairs.")
		.with_aside("Q says it with the flat confidence of someone repeating a thing they have said before.")
		.with_next(&"")
	)
	script.start_id = &"q_after_bell_start"
	return script


# --- Beat E: the rehearsal ------------------------------------------------
#
# The protagonist's expectation. Every line is marked imagined so the UI can
# present it differently, and the flow flags it so nothing can be mistaken for an
# event. The imagined B says nothing that the protagonist has not already been
# told; the whole scene is the protagonist's own material.

static func anticipation() -> DialogueScript:
	var script := DialogueScript.create(&"anticipation", "Rehearsal")

	script.add(
		DialogueNode.create(&"ant_start")
		.with_imagined()
		.with_cue(&"enter_anticipation")
		.with_flag(PrologueFlags.ANTICIPATION_ENTERED, true)
		.with_aside("The room goes a little flatter, the way it does when you stop listening to it.")
		.with_aside("You try the morning once, in your head, with the volume down.")
		.with_next(&"ant_b_enters")
	)

	script.add(
		DialogueNode.create(&"ant_b_enters")
		.with_imagined()
		.with_aside("The door opens and stays open. Everyone who was talking is suddenly very interested in their own desk.")
		.with_imagined_by(B, "Third period. Back row. I see the arrangement has changed.")
		.with_next(&"ant_first_choice")
	)

	script.add(
		DialogueNode.create(&"ant_first_choice")
		.with_imagined()
		.with_imagined_by(B, "Your desk was empty last Thursday. Was it not.")
		.with_choice(
			DialogueChoice.make(&"ant_admit", "（In your head: “I don't remember Thursday.”)", &"ant_admit_reply")
			.with_record(PrologueRecords.ID_IMAGINED_CORRECTION)
		)
		.with_choice(
			DialogueChoice.make(&"ant_deny", "（In your head: “I was here. I think I was here.”)", &"ant_deny_reply")
			.with_record(PrologueRecords.ID_IMAGINED_DENIAL)
		)
		.with_choice(
			DialogueChoice.make(&"ant_silent", "（In your head: nothing at all. Just the desk.)", &"ant_silence_reply")
			.with_record(PrologueRecords.ID_IMAGINED_SILENCE)
		)
	)

	script.add(
		DialogueNode.create(&"ant_admit_reply")
		.with_imagined()
		.with_imagined_by(B, "Then we'll do this the long way. Textbook out.")
		.with_aside("In the rehearsal you have no bag. You have not had one the whole time.")
		.with_next(&"ant_close")
	)

	script.add(
		DialogueNode.create(&"ant_deny_reply")
		.with_imagined()
		.with_imagined_by(B, "You were not. Somebody was. That is not the same as you.")
		.with_aside("You cannot tell whether that is her answer or yours.")
		.with_next(&"ant_close")
	)

	script.add(
		DialogueNode.create(&"ant_silence_reply")
		.with_imagined()
		.with_aside("She waits. The room waits with her. Eventually the waiting is the punishment and she knows it.")
		.with_imagined_by(B, "Well. We'll find out.")
		.with_next(&"ant_close")
	)

	script.add(
		DialogueNode.create(&"ant_close")
		.with_imagined()
		.with_record(PrologueRecords.ID_IMAGINED_CONFRONTATION)
		.with_aside("Then, in the rehearsal, the bell goes early. Which is not how bells work.")
		.with_aside("You stop. You can hear the yard again — someone moving a bucket along concrete.")
		.with_cue(&"exit_anticipation")
		.with_flag(PrologueFlags.ANTICIPATION_EXITED, true)
		.with_next(&"")
	)

	script.start_id = &"ant_start"
	return script


# --- Beat F: the substitute ----------------------------------------------

static func n_lesson() -> DialogueScript:
	var script := DialogueScript.create(&"n_lesson", "N takes the third period")

	script.add(
		DialogueNode.create(&"n_start")
		.with_aside("The door opens at a slightly wrong moment — too early for a teacher, too late for a student.")
		.with_speaker_line(N, "Sorry. Sorry. Third period? Biology, third period?")
		.with_speaker_line(N, "I'm not — she's not in today. I'm covering. There should be a sheet.")
		.with_flag(PrologueFlags.N_ENTERED, true)
		.with_flag(PrologueFlags.B_ABSENT_CONFIRMED, true)
		.with_record(PrologueRecords.ID_N_INTRODUCTION)
		.with_record(PrologueRecords.ID_B_ABSENT)
		.with_next(&"n_first_choice")
	)

	script.add(
		DialogueNode.create(&"n_first_choice")
		.with_aside("The sheet is not where she left it. N looks at the desk the way you look at a drawer you did not open.")
		.with_speaker_line(N, "It's usually. Under the. Okay. We can start without it.")
		.with_choice(
			DialogueChoice.make(&"n_ask_b", "“Is she coming in later?”", &"n_ask_b_reply")
			.with_record(PrologueRecords.ID_N_INTRODUCTION)
		)
		.with_choice(
			DialogueChoice.make(&"n_ask_textbook", "“Do we need the textbook for this?”", &"n_textbook_reply")
			.with_record(PrologueRecords.ID_BAG_EMPTY_TEXTBOOK)
		)
		.with_choice(
			DialogueChoice.make(&"n_say_nothing", "（Wait for her to find the sheet.)", &"n_wait_reply")
		)
	)

	script.add(
		DialogueNode.create(&"n_ask_b_reply")
		.with_speaker_line(N, "Mr— no. She's on some kind of. It's not my place to say.")
		.with_speaker_line(N, "I'll be truthful, I don't actually know. They told me at seven this morning.")
		.with_next(&"n_sheet")
	)

	script.add(
		DialogueNode.create(&"n_textbook_reply")
		.with_speaker_line(N, "Um. Yes. Probably. Page forty-something.")
		.with_speaker_line(N, "I don't have a copy. Which is. Not ideal. I know.")
		.with_next(&"n_sheet")
	)

	script.add(
		DialogueNode.create(&"n_wait_reply")
		.with_aside("She leafs through the folder twice. The second time is just to have something to do with her hands.")
		.with_speaker_line(N, "Right. Okay. Does anyone know what she does on the first lesson back?")
		.with_aside("Nobody says anything. Somebody's chair creaks. Q is suddenly very interested in the inside of a pencil case.")
		.with_next(&"n_sheet")
	)

	script.add(
		DialogueNode.create(&"n_sheet")
		.with_aside("She finds the sheet halfway through the folder, under something else.")
		.with_speaker_line(N, "This is — sorry, this is a seating plan. There's two names crossed out.")
		.with_speaker_line(N, "I'm not going to sort out the seating plan on my first day. Let's just.")
		.with_next(&"n_permission")
	)

	script.add(
		DialogueNode.create(&"n_permission")
		.with_speaker_line(N, "Look. If the rest of you are going to do something that isn't this, then do it quietly. I have to log the period either way.")
		.with_speaker_line(N, "You can be out in the corridor, or in the yard. Not off the site. Not yet.")
		.with_speaker_line(N, "Actually — I'd better come with you for the corridor. Later. In a minute.")
		.with_aside("The door stays open. Nobody gets up immediately. Then somebody does, and then it's a room that is allowed to leave.")
		.with_flag(PrologueFlags.N_CLASS_PERMITTED, true)
		.with_flag(PrologueFlags.LESSON_ENDED, true)
		.with_record(PrologueRecords.ID_N_RELEASE)
		.with_next(&"n_end")
	)

	script.add(
		DialogueNode.create(&"n_end")
		.with_aside("N sits down at the teacher's desk, then stands up again, then sits down.")
		.with_next(&"")
	)

	script.start_id = &"n_start"
	return script


# --- Q's parting line ----------------------------------------------------

static func q_parting() -> DialogueScript:
	var script := DialogueScript.create(&"q_parting", "Q, on the way out")
	script.add(
		DialogueNode.create(&"q_parting_start")
		.with_speaker_line(Q, "Told you. Nothing happens on the first week.")
		.with_speaker_line(Q, "Gate's open, by the way. It's always open after third.")
		.with_speaker_line(Q, "I'd say see you tomorrow, but you'll be back here in about four minutes. Everyone is.")
		.with_aside("Q says it cheerfully, already turning away, as if the four minutes were a small joke they expect you to get.")
		.with_next(&"")
	)
	script.start_id = &"q_parting_start"
	return script


static func scripts() -> Array[DialogueScript]:
	return [
		q_conversation(),
		q_repeat(),
		q_after_bell(),
		anticipation(),
		n_lesson(),
		q_parting(),
	]
