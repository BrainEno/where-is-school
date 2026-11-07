# ADR 0003: Inner abilities and checks

- **Status:** implemented as a small vertical-slice prototype; voice names,
  wording, tuning and presentation remain subject to author review.
- **Scope:** the open playground and its optional interactions; no combat,
  equipment, full skill tree, full memory chapters or external service.

## Decision

Use the author's **hybrid** direction: three stable, rated inner abilities can
speak in context without a choice (passive) and can also be selected by the
player in dialogue (active). Their fictional functions are deliberately different:

| Stable ID | Default (0–4) | Function and bias |
|---|---:|---|
| `pattern` / Thread / 线索 | 2 | Connects details; can force a pattern where there isn't one. |
| `resonance` / Resonance / 回响 | 1 | Associates a sensation with familiarity; can mistake association for memory. |
| `guard` / Shelter / 守护 | 2 | Looks for room and safety; can overestimate danger. |

They are parts of a subjective perspective, not separate omniscient authorities.
They may be wrong or disagree; even a successful check means a useful angle,
not truth. Their lines live in bilingual dialogue JSON and use `imagined` entries
in `NarrativeState`. Physical observations remain separate `observed` entries.
Nothing in this system establishes the cause of the spatial instability or the
species, origin, or eventual fate of the green animal. Q stays an ordinary
classmate, not a guide or quest terminal; B does not appear here.

## Shared check and result contract

For each check, roll one uniform d6 and compute **total = die (1–6) + ability
rating (0–4)**. **Success means total >= difficulty**, including equality;
difficulties are integers 2–10. Defaults are fixed for this slice; the API can
set a valid rating, but there is no progression UI or point spending yet.
`InnerCheckEngine(state, rng)` accepts a Godot `RandomNumberGenerator` or an
object with `randi_range(min, max)`; production randomizes a fresh generator,
while tests inject fixed rolls or equal seeds.

`attempt(id, ability, difficulty, visibility)` returns a dictionary with `id`,
`ability`, `rating`, `difficulty`, `roll`, `total`, `success`, `visibility`
(`active` or `passive`) and `reused`. It stores the original result in
`GameState` under `inner:check:<id>`; an identical later attempt returns the
same result with `reused = true` and draws no die. Reusing an ID with different
rules is an error. The result and ability ratings are part of a GameState
snapshot, not a disk save. There is no implemented persistent save system.

For **active** checks, choices show ability, rating and target before selection;
the resulting line shows ability, rating, die, total, target and outcome. The
result stays the same when changing language mid-line. Success and setback have
separate authored, useful thoughts; neither opens a mandatory route. Choices
are once-only; leaving without choosing does not spend a check. Cached results
are the second line of defense against unlimited rerolls even if future UI or
content exposes the same check again.

For **passive** checks, the same engine rolls privately; no die, target or result
is shown to the player. The triggered conversation is subjective and differs on
success versus setback. Track and practice-ring reactions require their
inspection's `seen:<id>` flag. Only playground interactions advance the serial;
a reaction requires a gap of three serial positions from the preceding one
(two other interactions in between), and each rule can roll only once per
session. A rule skipped while cooling down remains eligible on a later visit.
Checks and pacing metadata (`inner:*`, `choice:*`) are bookkeeping, not claims
about the physical world; subjective dialogue effects still cannot write world
flags/objectives or record observed/reported knowledge.

## Ownership and data

- `InnerAbilities`: small extensible catalog, stable IDs, defaults, range and
  locale keys. `data/locale` translates names and roles.
- `InnerCheckEngine`: the sole roll/caching algorithm for active and passive
  checks. Inject the RNG for tests; do not call global randomness in dialogue.
- `PassiveVoices`: declarative trigger rules, prerequisites, once-only and
  interaction-count pacing. `OpeningSequence` requests a reaction only after an
  existing interaction presentation completes.
- `DialogueGraph` validates optional `check` objects on choices and both targets;
  `DialogueParity` checks the whole definition across languages;
  `DialogueLibrary` rejects repeated check IDs within a language.
  `DialogueRuntime` resolves the selected branch and emits the result title;
  `DialogueController`, `DialoguePanel` and the backlog remain the presenters.
- All new narrative sentences are in `data/dialogue/{en,zh-CN}/playground.json`
  and observations in `data/inspections/{en,zh-CN}/playground.json`. Their
  structural IDs match. See `data/dialogue_schema/README.md` for authoring.

## Revisit, failure and limits

The playground anchors are independent and may be approached in any order.
Failure is not a dead end: for example, Thread may find its four-seat inference
premature, while success notices paint curving around the bench; Resonance may
feel a false familiarity rather than identifying a writer. In both cases the
player can keep exploring. Passive failure also has an authored line rather
than forcing a retry. Re-entering a location preserves session flags and notes.
The only end card is an explicitly labelled, optional far-edge interaction.

## Outstanding author questions

1. Approve or rename the three functions, names and translations; calibrate
   how often they interrupt free movement and whether their disagreement feels
   sufficiently subtle.
2. Decide whether passive setbacks should sometimes be silent, and whether
   difficulty/rating defaults and the visible die cadence suit the tone.
3. Decide future progression, save migration, accessibility, presentation and
   whether any ability can change over a longer story. None is assumed here.
4. Review all new bilingual prose and the graybox route; neither the cause of
   anomalies nor animal identity/fate is decided by this prototype.
