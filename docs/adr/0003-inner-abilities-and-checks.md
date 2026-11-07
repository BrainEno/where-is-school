# ADR 0003 — Small hybrid inner-ability checks

Status: accepted for this vertical slice; ability identities and final prose are provisional pending author review.

## Context and interpretation

The owner's confirmed choices are **hybrid** inner abilities, **both** visible and
hidden checks, and an **open** playground. No repository document defines final
ability names or a full skill taxonomy. Implement three *provisional*,
non-character voices, not a borrowed 24-skill system. Q remains an ordinary
classmate and is not involved in this slice's check mechanics.

## Decision

`data/abilities/abilities.json` defines stable ids (`measure`, `trace`, `echo`),
level, names, descriptions and short voice cues in en/zh-CN. Measure compares
spatial distances and may overstate certainty. Trace notices material wear but
cannot identify its cause. Echo follows familiarity; recognition is not evidence.
Each is an internal suggestion, **never an omniscient statement**. Their reactions
are tagged `recalled` in the authored dialogue so they are not recorded as
observed facts. This is intentionally a small set, without XP, a skill tree or
progression UI; those remain author decisions.

`AbilityChecks.resolve(id, spec, visible)` uses one seeded/injectable
`RandomNumberGenerator` and one formula:

    total = uniform 1d12 + level + situational modifier (default 0)
    success iff total >= difficulty

Results are dictionaries with stable id, ability, die, bonus, modifier,
difficulty, total, success and visible. A `check.<id>` flag in GameState stores
the first full result. Later uses return the stored result and do not consume
RNG, even across locations. Save/load is not yet implemented; GameState snapshots
already include these values. Difficulty, result targets and ability id are data,
not hard-coded in NPC scripts.

### Active / visible

A dialogue `choice.check` names ability, difficulty, success and failure node ids.
`DialogueGraph` validates both targets; `DialogueParity` compares check metadata
across languages. The `DialogueRuntime` shows the ability, its bonus and DC on
the choice; on selection it displays the die, sum, DC and result before the first
outcome line. A locale switch re-renders that line without rolling again. The
success and failure nodes have distinct authored text; neither blocks the route.
Every option is still a normal dialogue choice driven by the existing runtime.

### Passive / hidden

The passive table maps stable interact ids to ability, difficulty and two
conversation ids. `OpeningSequence` asks the shared check core once when the
player interacts; it plays the corresponding authored conversation through
`DialogueController` (no numbers shown). A `passive_shown.<id>` flag prevents
repeated commentary. Later interaction with the same prop shows its normal
inspection, not a reroll. Both outcomes leave the path open. Passive checks are
*conditional on interaction*; no proximity-triggered spam.

### Boundaries and unresolved questions

Neither a passive success nor an active success grants objective knowledge about
why spaces connect. Failure gives a different detail, not an empty button or a
soft lock. The game's four narrative-source categories remain unchanged. The
ability set, its voices/levels, and whether future checks should have more
modifiers, frequency limits or progression are **provisional**. The precise
meaning of the playground's spatial mismatch is not decided. No manuscript prose
is used. Later saves will need versioned migrations for ability and check ids.

## Tests

`tests/ability_checks_test.gd`: load, levels, eligibility, both display modes,
seed replay, both outcomes, inclusive boundary, caching and once-only passive.
`tests/dialogue_validation_test.gd`: choice predicates and check metadata parity.
`tests/opening_flow_test.gd`: existing prologue through the courtyard, alley,
service yard, passive reaction, independent playground anchors and the new end.
