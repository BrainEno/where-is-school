# First Vertical Slice — Prototype Brief

## Goal

Build a short playable experience that tests whether movement, environmental observation, literary dialogue, and a subjective memory sequence can work together. This is the first comparable implementation task for competing coding agents after the engineering foundation is merged.

## Player-facing experience

The protagonist wakes at a desk in a school classroom. Q, a talkative classmate who seems to know the protagonist but is not remembered by them, starts a conversation about the final term and the protagonist's previous biology exam. The player can respond with different attitudes toward Q, memory, and the expected biology lesson.

The protagonist searches their schoolbag and discovers that the biology textbook is missing. A worn wooden set square associated with the absent biology teacher B is present as an inspectable object or visible classroom detail. The protagonist's imagined confrontation with B should be conveyed as subjective text/voice or a bounded authored sequence, not mistaken for an event that objectively occurs.

When the bell rings, B does not arrive. N, an inexperienced substitute, appears and eventually allows students to leave for free activity. The slice ends after the protagonist leaves the classroom and reaches a clear next objective at or beyond the school grounds. The full residential-street route and green-animal encounter may be reserved for a subsequent slice if scope requires it.

## Required content

- One compact classroom with readable collision and navigation.
- Q as the first conversational NPC; a temporary portrait placeholder is acceptable.
- At least three inspectable objects with distinct descriptions. Include the schoolbag/textbook search and the wooden set square or its damaged/taped detail.
- One conversation with at least three meaningful player choices.
- A representation of the protagonist's unstable recollection that distinguishes Q's claims from the protagonist's memory and speculation.
- A clear beat in which B is absent and N substitutes for her; do not implement B as an opening-scene NPC.
- A short route or exit beat that gives the player a next question or objective.
- At least one choice or discovery changes a named story flag.

## Required systems

- Player movement and camera control with a consistent perspective.
- Contextual interaction feedback and input.
- Dialogue presentation supporting long text, speaker identity, choices, and a backlog/history.
- Explicit, testable story-state changes.
- A way to present subjective memory/imagination without silently converting it into objective world state.
- Scene transition behavior that preserves the intended story state.
- Basic settings for text speed and text size, or a clearly scoped follow-up issue if not feasible in the first pass.

## Out of scope

- A complete implementation of all A/B/C/D memory paths; their exact content is undecided.
- B's full onstage appearance or a definitive explanation of her character.
- The complete green-animal sequence if it would compromise the first slice's scope.
- The elliptical building and a complete school-version transition system.
- Combat, enemy AI, weapons, crafting, survival meters, or procedural generation.
- Full inventory/quest systems.
- Voice acting and cinematic facial animation.
- All planned chapters or a definitive explanation of the world.
- Final production art for every prop and NPC.
- Online services, analytics, or paid dependencies.

## Acceptance criteria

1. A clean clone opens in the pinned Godot version with no missing resources or script parse errors.
2. The project launches into the intended classroom starting space.
3. The player can traverse the classroom without getting trapped by collision or camera framing.
4. Every required interactable can be reached, targeted, and inspected.
5. Dialogue choices have distinct, observable consequences (text, flags, relationship, route, or environment).
6. Q's dialogue communicates familiarity and useful context without turning him into a supernatural guide or a checklist of exposition.
7. The player can distinguish Q's account, protagonist memory, and imagined confrontation.
8. B's absence and N's substitution are clear and reproducible.
9. Returning to an earlier area does not silently lose required story state.
10. Long text is readable at the default resolution and can be reviewed in a backlog.
11. Headless import and smoke checks pass; manual test steps and limitations are recorded.
12. No fake tests, silent error suppression, broken placeholder buttons, or unrelated rewrites are introduced.

## Deliverables

- A focused PR against the merged foundation.
- Screenshots or a short capture of the playable flow.
- Exact engine version and validation commands/results.
- A concise architecture note explaining the ownership of interaction, dialogue, subjective recollection, and story state.
- Known limitations and recommended next steps.
