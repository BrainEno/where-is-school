# First Vertical Slice — Prototype Brief

## Goal

Build a short playable classroom sequence that tests movement, environmental interaction, literary dialogue, and the presentation of subjective recollection.

## Player-facing flow

1. The protagonist wakes at a desk.
2. Q starts a conversation and establishes the immediate classroom situation.
3. The player searches the schoolbag and discovers the biology textbook is missing.
4. The player can inspect a small number of classroom props, including a wooden set square.
5. The protagonist anticipates a confrontation, but subjective imagination must remain distinct from objective scene events.
6. B is absent. N, an inexperienced substitute, takes the class and eventually permits students to leave.
7. The player exits the classroom and reaches a clear next objective.

The prototype should not reproduce unpublished manuscript passages. Write short, original placeholder dialogue for implementation tests; replace it only with game dialogue explicitly approved by the owner.

## Required content

- One compact classroom with readable collision and navigation.
- Q as the first conversational NPC; a temporary portrait placeholder is acceptable.
- A schoolbag interaction that establishes the missing textbook.
- At least three inspectable classroom props with concise, newly written descriptions.
- One conversation with at least three meaningful player choices.
- A subjective recollection/imagination presentation that cannot silently alter objective world state.
- A clear beat in which B is absent and N substitutes for her.
- A short exit route or transition.
- At least one choice or discovery changes a named story flag.

## Required systems

- Player movement and consistent camera control.
- Contextual interaction feedback and input.
- Dialogue presentation supporting speaker identity, choices, and backlog/history.
- Explicit, testable story-state changes.
- A presentation layer for subjective recollection.
- Scene transition behavior that preserves story state.
- Basic text-size and text-speed settings, or a scoped follow-up issue.

## Out of scope

- Complete A/B/C/D memory paths.
- B's full onstage appearance or definitive character explanation.
- The full street and green-animal sequence.
- The elliptical building or complete school-version transition system.
- Combat, enemy AI, weapons, crafting, survival meters, procedural generation.
- Full inventory/quest systems, voice acting, cinematic facial animation.
- Online services, analytics, paid dependencies, or unpublished manuscript content.

## Acceptance criteria

1. A clean clone opens in the pinned Godot version without missing resources or parse errors.
2. The project launches into the intended classroom.
3. The player can navigate the classroom without collision or camera traps.
4. Required interactables can be reached, targeted, and inspected.
5. Dialogue choices have distinct observable consequences.
6. Q communicates familiarity and context without functioning as a quest terminal.
7. The player can distinguish dialogue claims, recollection, and subjective imagination.
8. B's absence and N's substitution are clear and reproducible.
9. Required story state persists when revisiting an area.
10. Long text is readable and reviewable in a backlog.
11. Headless import and smoke checks pass; manual checks and limitations are recorded.
12. No fake tests, silent error suppression, broken placeholder buttons, unrelated rewrites, or private manuscript text are introduced.

## Deliverables

- A focused PR against the merged foundation.
- Screenshots or a short capture of the playable flow.
- Exact engine version and validation commands/results.
- A concise architecture note covering interaction, dialogue, subjective recollection, and story state.
- Known limitations and recommended next steps.
