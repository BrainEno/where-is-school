# First Vertical Slice — Prototype Brief

## Goal

Build a short playable experience that tests whether movement, environmental observation, literary dialogue, and one spatial transformation work together. This is the first comparable task for competing coding agents after the engineering foundation is merged.

## Player-facing experience

The player arrives in a residential block where the school entrance is difficult to identify. They follow an uncertain route through a stairwell and reach a damp classroom. They speak with one person, inspect a few objects, and discover that the classroom's relationship to the corridor has changed.

Target duration: approximately 10–20 minutes once authored content is present.

## Required content

- One compact residential approach or entrance space.
- One stairwell/corridor connecting to the classroom.
- One classroom with readable collision and navigation.
- One NPC with a portrait or a clearly marked temporary portrait placeholder.
- At least three inspectable objects with distinct descriptions.
- One conversation with at least three meaningful player choices.
- At least one choice or discovery changes a named story flag.
- One spatial transition or authored environment change that responds to story state.
- A short ending beat that gives the player a next question or objective.

## Required systems

- Player movement and camera control with a consistent perspective.
- Contextual interaction feedback and input.
- Dialogue presentation supporting long text, speaker identity, choices, and a backlog/history.
- Explicit, testable story-state changes.
- Scene transition behavior that preserves the intended story state.
- Basic settings for text speed and text size, or a clearly scoped follow-up issue if not feasible in the first pass.

## Out of scope

- Combat, enemy AI, weapons, crafting, survival meters, or procedural generation.
- Full inventory/quest systems.
- Voice acting and cinematic facial animation.
- All planned chapters or a definitive explanation of the world.
- Final production art for every prop and NPC.
- Online services, analytics, or paid dependencies.

## Acceptance criteria

1. A clean clone opens in the pinned Godot version with no missing resources or script parse errors.
2. The project launches into the intended starting space.
3. The player can traverse the full route without getting trapped by collision or camera framing.
4. Every required interactable can be reached, targeted, and inspected.
5. Dialogue choices have distinct, observable consequences (text, flags, relationship, route, or environment).
6. The spatial change is understandable and reproducible.
7. Returning to an earlier area does not silently lose required story state.
8. Long text is readable at the default resolution and can be reviewed in a backlog.
9. Headless import and smoke checks pass; manual test steps and limitations are recorded.
10. No fake tests, silent error suppression, broken placeholder buttons, or unrelated rewrites are introduced.

## Deliverables

- A focused PR against the merged foundation.
- Screenshots or a short capture of the playable flow.
- Exact engine version and validation commands/results.
- A concise architecture note explaining the ownership of interaction, dialogue, and story state.
- Known limitations and recommended next steps.
