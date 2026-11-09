# Narrative Bible — Game-facing Reference

> This document is a production reference, not a literary manuscript. It intentionally records only the information needed to design scenes, dialogue systems, and interactions. Private prose, extended descriptions, and unpublished endings belong outside this repository.

## Core premise

An adult protagonist wakes in a classroom occupying the position of a student again. Their return has no confirmed explanation. The school and its surrounding spaces do not maintain a stable geography, and accounts of past events may contradict one another.

The game should preserve uncertainty. Do not confirm that the world is a dream, a diagnosis, a simulation, a conventional parallel universe, or the product of a single hidden cause.

## Narrative principles

- Separate what a character says, what the protagonist remembers, what the protagonist imagines, and what the player directly observes.
- Do not treat a vivid memory as objective proof.
- Let ordinary dialogue and environmental details carry information without turning every character into an exposition device.
- Keep immediate player goals understandable even when the larger situation is not.
- Do not explain every object as a symbol or resolve every anomaly.
- Do not add material from private manuscripts to this document. Record only scene requirements and implementation-facing facts.

## Opening sequence: Biology Class

The opening takes place in a classroom at the beginning of a final school term. The protagonist wakes at a desk with a headache and incomplete memory. The scene should not immediately identify itself as a flashback or explain why the protagonist is a student again.

### Scene beats

1. **Wake and conversation:** Q, a familiar-but-unremembered classmate, starts talking. The exchange establishes the term, a previous failed/blank biology exam, and the expected arrival of teacher B.
2. **Missing textbook:** the protagonist checks their schoolbag. The biology textbook is absent. This is a simple playable interaction that builds anticipation.
3. **Expected confrontation:** Q describes B as strict and punitive. The protagonist can form subjective expectations or imagined responses. These must not be presented as events that actually happened.
4. **Teacher absent:** the bell rings, but B does not arrive. N, an inexperienced substitute, takes the class and eventually permits free activity.
5. **Exit:** the protagonist leaves the classroom and moves through the school grounds. The immediate tone is release mixed with uncertainty.
6. **Beyond the gate:** the route passes through ordinary streets and a residential area. The environment should remain recognizable before becoming subtly strange.
7. **Animal observation:** a green, visibly unusual animal attracts the protagonist's attention. The player can inspect it, but its exact species and eventual fate are not established.

The first playable slice may end at the school exit. The street route and animal encounter can be a later slice if required by scope.

## Character functions

### Protagonist

An adult occupying a student role. The player should be able to express avoidance, curiosity, irritation, compliance, and defiance. Do not assign a diagnosis or a definitive explanation for the return.

### Q — classmate

- Talkative, overweight, overfamiliar, and socially casual.
- Acts as though he knows the protagonist well; the protagonist does not remember him.
- Shares useful context through ordinary chatter, not formal exposition.
- Not a supernatural guide, deliberate liar, or quest terminal.

### B — biology teacher

- A woman whose authority is associated with the institutional teacher role.
- Absent during the opening lesson; her presence is conveyed through Q's account, classroom expectations, and a recurring prop.
- Her eventual characterization should combine authority with ordinary human pettiness.
- Do not decide whether her role-playing is fully conscious.
- Do not make her a supernatural mastermind, a simple monster, a harmless joke, or a fraud whose authority instantly collapses.

### N — substitute teacher

- Young and inexperienced relative to the expected authority of B.
- Struggles to command the room and eventually allows students to leave for free activity.
- Not automatically more truthful, kind, or morally correct than B.

## Props and interaction references

| Item | Game-facing use |
|---|---|
| Biology textbook | Missing-item search; gives the player a concrete opening objective. |
| Wooden set square | Inspectable classroom prop associated with B; communicates authority and possible physical punishment. |
| Schoolbag and stationery | Small environmental interactions that establish the protagonist's immediate situation. |
| Classroom desk and teacher's desk | Establish the spatial and social division between student and teacher. |
| Green animal | Optional later inspection scene focused on observation without certain classification. |

Descriptions should be newly written for the game. Do not transplant manuscript phrasing into item text.

## Memory choices

A/B/C are intended as active directions for recollection, but their subjects are undecided. D means postponing active recollection and continuing with immediate events. D is not a permanently exclusive fourth campaign.

An initial choice may influence scene order and which evidence appears first. It should not automatically lock the player out of all other memories. Keep remembered claims distinct from independently observable evidence.

## Inner voices

Three separate statements, kept apart because they are at three different stages.

**1. What exists now.** **One provisional voice is implemented**, not a cast. It
speaks in the protagonist's own register and is presented as an inner voice, not as a
character or an NPC:

> **Orientation** (路感) — a sense of where things are in relation to each other:
> heights, seams, what lines up and what does not. Confident about shapes, silent
> about people.

That voice ships in `data/abilities/` and is described in ADR 0003, which is a
**proposal**, not an accepted decision. Its name, its value (3), the 2d6 formula and
every difficulty in the content are provisional and expected to change after
playtesting. It is still the only voice in the game, and this document describes no
other.

**2. What has been decided.** The owner has decided (2026-11) that the one provisional
voice is to be **extended into several voices** rather than kept as it is. That
decision is about direction, and the technical foundation for it now exists: the
ability registry, the character profiles, the dialogue runtime, the dice core and the
passive director all work with any number of voices, each with its own id, speaker,
value, passive cap and two-language prose (see `docs/ARCHITECTURE.md` §5c). Adding a
voice is a data change plus its prose, not a code change.

**3. What is not decided.** Everything about the voices themselves:

- how many there are;
- their names, in either language;
- their personalities, values, biases and what each is good at;
- which events make each of them speak unprompted;
- every line any of them says.

None of that is written, implied or reserved here. The multi-voice work in Phase 6a
was technical: it ships no second voice, no placeholder name and no draft dialogue, so
nothing in the game or in this document anticipates a design the owner has not made.

Nothing in this section records a decision the owner has not made.

Rules for writing them:

- A voice is **partial and biased**, never an oracle. It may misjudge, insist, or
  contradict another voice, and the prose should let the player notice.
- A voice's failure is written as its own mistake, not as the world withholding
  information: the line still leaves one concrete thing to look at.
- No voice explains the school, identifies the animal, diagnoses the protagonist,
  or settles whether a memory happened.
- A voice never states a fact about another character's interior life as fact. This
  is why the implemented voice is about space rather than about people, and the rule
  applies unchanged to any voice added later.
- Voices speak unprompted only on events, are capped per session, and never
  chatter while the player is walking or thinking (ADR 0003 §6).
- The player choosing a voice to attempt something is a decision about *how to
  look*, expressed in the fiction ("try the frame", "read the sheet"), not a skill
  menu.

## The open yard

The slice now ends in an open school yard behind the residential estate: a painted
court with two hoops, an equipment shed, a bench with a bag left on it, a climbing
frame, a notice board, a tap, and a gap in the fence at the far end. It is walked
freely in any order; the story does not lock any of it.

- It must read as an ordinary school space first. The oddity is a few specific
  findings (a hasp with no purchase, a rota dated next week, a hoop that was moved,
  a stamped tag under the shed), not decoration.
- Nothing in the yard explains the anomaly, and nothing there names the animal. The
  animal remains in the residential courtyard and remains unclassified.
- Failures are content: each failed attempt yields a different detail and a new
  question, and no required beat depends on a successful roll.
- Empty middle ground is deliberate: later people and events go there.

## World and later spaces

- The same school may have multiple contradictory versions.
- Corridors, staircases, classrooms, yards, and nearby residential spaces can connect in unstable ways.
- The cause of these changes remains unknown.
- The elliptical building is a later-discovered structure connecting versions of the school. Do not place it in the opening sequence.
- Other candidate spaces include laboratories, toilets, gyms, unfinished stairwells, container yards, and port-like areas. Their order is not fixed.
- Built so far: the classroom, the walkway, the street, the residential courtyard,
  the alley behind the flats, and the school yard (playground). The end of the
  built slice is the gap in the yard's far fence.

## Dialogue and implementation guidance

- Write new game dialogue; use only short, explicitly approved dialogue references.
- Q's speech should feel conversational and sometimes trivial, with information emerging incidentally.
- N's dialogue should convey uncertainty and limited classroom authority without becoming a comic caricature.
- B's eventual dialogue should not simply validate or disprove Q's account.
- Choices should alter tone, knowledge, relationship, access, or interpretation.
- Keep long dialogue interleaved with movement, inspection, silence, and player decisions.
