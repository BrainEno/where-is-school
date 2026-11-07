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

## World and later spaces

- The same school may have multiple contradictory versions.
- Corridors, staircases, classrooms, yards, and nearby residential spaces can connect in unstable ways.
- The cause of these changes remains unknown.
- The elliptical building is a later-discovered structure connecting versions of the school. Do not place it in the opening sequence.
- Other candidate spaces include laboratories, toilets, gyms, unfinished stairwells, container yards, and port-like areas. Their order is not fixed.

## Dialogue and implementation guidance

- Write new game dialogue; use only short, explicitly approved dialogue references.
- Q's speech should feel conversational and sometimes trivial, with information emerging incidentally.
- N's dialogue should convey uncertainty and limited classroom authority without becoming a comic caricature.
- B's eventual dialogue should not simply validate or disprove Q's account.
- Choices should alter tone, knowledge, relationship, access, or interpretation.
- Keep long dialogue interleaved with movement, inspection, silence, and player decisions.


## Playground prototype: inner viewpoints

The open playground is an ordinary, readable place with a few quiet discrepancies,
not an explanation of the world. Four independent anchors can be visited in any
order. The green animal's species, origin and fate remain undecided; no encounter
is used as a quest lock.

Thread connects details, Resonance associates sensations with familiarity, and
Shelter looks for room or safety. These are subjective functions, not characters
with superior knowledge: they can leap to incompatible or mistaken conclusions.
An active choice or a sparse passive reaction may offer a useful thought after
either success or setback. Thoughts are recorded as imagined, separate from
observations. The names, phrasing and balance await author approval; see ADR 0003.
