# ADR 0003 — Inner voices and dice checks

- Status: accepted, implemented in this round
- Date: 2026-11
- Supersedes: nothing. Extends ADR 0002 (dialogue and narrative state).
- Owners: engineering; the ability *characterisation* is a design decision recorded
  here as implementation interpretation and still open to the author.

## Context

The protagonist needed a way to notice things that is neither a silent stat check
nor the author telling him the answer. The owner fixed three constraints before any
code was written, and none of them were renegotiated:

1. the system is **hybrid** — passive abilities that fire on their own, plus active
   abilities the player picks;
2. dice are **both** — some rolls are shown to the player, some are hidden;
3. the scope is small: no skill tree, no inventory, no character sheet.

A fourth constraint came from the project's own history: the dialogue layer is
hand-built and everything else already routes through it (ADR 0002). A second
system for "ability encounters" would have meant two ways to author a scene, two
ways to test one, and two places for a translation to go wrong.

## Decision

### 1. An inner voice is an author, not a stat

Four voices ship: The Ledger (counting, dates, quantities), The Boundary (space,
distance, fit), Echo (memory, recognition), The Onlooker (people, tone, intent).
Each has a value between 0 and 10, a speaker profile so its lines appear in the
dialogue panel like anyone else's, and a bias that the content is allowed to prove
wrong:

- The Ledger would rather be wrong than vague, and says so in its failure lines.
- The Boundary notices when a space does not close, and sometimes notices a gap
  that is not the interesting thing about the gap.
- Echo is fast, generous, and recognises places it has never been.
- The Onlooker is confident about other people's reasons and cannot check them.

A voice is therefore not objective narration. Its lines use the same four knowledge
categories as everything else, and the failure branches are written so a mistaken
voice still leaves the protagonist with one real detail — a different question, not
a retry.

### 2. Passive and active, on one data model

**Passive** — a rule in `data/abilities/abilities.json`:

```json
{
  "id": "playground_hoop_boundary",
  "ability": "boundary",
  "trigger": {"kind": "inspection", "id": "pg_hoop"},
  "conversation": "voice_hoop",
  "once": true
}
```

`trigger.kind` is one of `inspection`, `location`, `conversation_end`. The rule
points at an ordinary conversation whose first node is a **hidden check**, so the
dice still come from one place:

```json
{
  "id": "vh_1",
  "speaker": "voice_boundary",
  "text": "Let me look at that.",
  "check": {
    "ability": "boundary", "difficulty": 9, "kind": "hidden",
    "success": "vh_ok", "failure": "vh_bad"
  }
}
```

**Active** — the player reaches a check by choosing an approach in a conversation:

```json
{"id": "frame", "text": "Try the door against its frame.", "next": "ps_boundary_check"}
```

and `ps_boundary_check` is a check node with `kind: "visible"`, so the numbers are
shown. Choosing *which* voice to use is the player's decision, made in the fiction
("try the frame" vs "read the sheet"), not in a menu of skills.

Both halves produce the same result dictionary, are validated by the same graph
validator, and are translated by the same parity checker.

### 3. The formula

```
d10 + ability value + situational modifier  >=  difficulty   -> success
```

- **d10**: one die, ten outcomes, understandable without a table. A d20 gives a
  flatter curve than four 0-10 abilities can support at this scale; 3d6 would need
  a probability explanation in a game that never shows one.
- **ability value** comes from `abilities.json` (currently 2-4). Values are small
  so the die dominates: the voice tilts the odds, it does not decide them.
- **situational modifier** is declared per check (`modifiers: [{flag, value}]`) and
  summed from flags. Missing flags contribute nothing, so content can offer a bonus
  for something the player may never have done.
- **difficulty** is authored per check in 1..30; the resolver clamps so a hand
  edited file can never produce a negative target. Typical values in this slice are
  8-12, i.e. between "the voice usually manages it" and "the voice usually does
  not".
- The result is a dictionary: `ability`, `ability_value`, `die`, `die_faces`,
  `modifier`, `total`, `difficulty`, `margin`, `success`, `key`, and `reused`.

Boundary behaviour is part of the contract and is tested: a 1 can still succeed
with a strong voice against a low difficulty, and a 10 cannot save a difficulty
above the maximum reachable total.

### 4. One die, one key, one session

`CheckResolver` is seeded once per session (from the clock in the game, injected in
tests). The face for a check is `hash(session seed, check key)`, where the key is
`conversation/node`. Consequences, all deliberate:

- the same check always falls the same way **within a session**, so walking out and
  back in is not a reroll;
- a fixed seed reproduces a whole run, which is what keeps CI deterministic;
- the designer cannot know what a specific check will roll, so difficulty tuning
  stays statistical rather than "make this one pass".

On top of that, the runtime records the resolved result in a story flag
(`check:<conversation>:<node>`) and **replays the record** on re-entry, marked
`reused`. The reroll is prevented twice, at two different layers, because the
exploit (leave, return, roll again) is the one players find first. Content also
hides an already-attempted approach from the choice list
(`conditions.not_flags: ["check:pg_shed/ps_boundary_check"]`), so the player is not
offered a button that would only repeat text.

`repeatable: true` exists for a check the author wants to be retryable; it bypasses
the record but not the key, so the die stays the same. It is unused in this slice
on purpose: a retry that cannot change the outcome is a lie, and one that can is a
slot machine.

### 5. Visible and hidden

| | visible | hidden |
|---|---|---|
| Who started it | the player chose the approach | a rule fired on an event |
| What is on screen | voice, value, die, difficulty, outcome | only the line the roll produced |
| Where it lives | check node after a choice | first node of a passive conversation |
| How often | once per attempt, attempts are filtered | rationed (below) |
| What the player learns | that the voice tried and how well | what the voice claims |

The rule of thumb for content: **if the player committed to something, show the
dice; if the voice volunteered, hide them.** Showing numbers for an unrequested
interjection turns a character beat into an audit; hiding numbers for a chosen
attempt makes the choice feel decorative.

### 6. Frequency control for passive voices

Unprompted lines are the fastest way to make an inner-voice system unbearable, so
`InnerVoiceDirector` enforces five rules:

1. triggers are events (`inspection`, `location`, `conversation_end`), never timers;
2. a rule fires once unless content says otherwise (`once` → `voice:<rule>` flag);
3. each voice has a per-session cap (`max_passive`, default 2) counted in
   `voice_count:<ability>`, independent of which rule fired;
4. one unprompted line cannot follow another: at least one other presentation must
   happen in between (`_since_voice`);
5. a passive line waits for an authored beat and a running conversation to finish,
   and stays silent after the end card.

At most one request is queued (`MAX_PENDING`), so three things read in a row cannot
stack three voices on top of each other.

### 7. Success and failure both have to be worth reading

- A **failed** check never blocks required story. Nothing in this slice needs a
  successful roll to continue: the shed's failure branch yields a different
  observation and a new question, and the yard stays walkable.
- A **passed** check does not hand over an explanation of the school. It yields a
  concrete detail (a missing hasp screw, a rota dated next week, a stamped tag) that
  raises a question rather than answering one.
- Neither branch explains the anomaly, identifies the animal, or gives the
  protagonist a diagnosis. The voices are wrong often enough that the player cannot
  use them as an oracle.

### 8. Integration points

- `DialogueGraph` parses and validates `check` blocks (unknown ability, bad
  difficulty, unknown kind, missing branch, a check that also offers choices, a
  check with a `next`).
- `DialogueRuntime` resolves the check when the node is entered, emits
  `check_resolved(result)` after the line, records the result, and continues to the
  branch. No NPC script and no scene script ever rolls a die.
- `DialogueController` presents visible results in `CheckOverlay`, gives the
  overlay's ability name from the translated registry (voices are not people, so
  their names are not in the character resources), and forwards `inspection_presented`
  so passive rules can react to reading.
- `InnerVoiceDirector` owns triggering, rationing and queueing, and nothing else.
- `DialogueLibrary` refuses a check that names a voice that does not exist;
  `tests/content_integrity_test.gd` links scenes to inspections, routes and prompt
  keys.

## Alternatives considered

- **Pure passive (Disco-like skills that interject).** No player agency; the
  player would be watching a character sheet argue with itself. Rejected by the
  owner before this ADR.
- **Pure active (choose a skill from a menu).** Turns the fiction into a
  character-creation screen every time something is looked at.
- **Two random implementations, one for each mode.** The one thing the brief
  forbade outright, and the one thing that would drift first.
- **2d6 / 3d6 bell curve.** More predictable, but needs explaining; a d10 with
  small values is roughly the same spread at this scale and is explainable in a
  sentence.
- **Opposed rolls against a world stat.** Invents a world model (how observant is a
  shed?) that this story does not need.

## Open questions for the author

1. **Where the player meets the voices.** Right now they appear only when they
   speak; there is no screen that lists the four and their values. That is
   deliberate for this slice, but a first-time player may not realise the words come
   from *his own* faculties rather than from an NPC. A one-off introduction beat is
   the obvious fix; it needs a decision about whether it is diegetic.
2. **Failure branches and the knowledge log.** A failed check's line is currently
   presented with the voice's own speaker and recorded as `observed` when it points
   at something present, which can read as more certain than the voice deserves.
   Whether failures should always record as `recalled` (hedged) is an author
   decision, not an engineering one.
3. **Difficulty as characterisation.** The Ledger is value 3 and Echo value 2 in
   this slice. The numbers are placeholders chosen for a 40-60% success rate at
   difficulties 8-12; they should follow whatever the author decides each voice is
   actually good at.
4. **Whether a failed attempt should ever be retryable** after the situation
   changes (a bell rings, someone arrives). The current answer is no, because the
   die is fixed by the key; if the story wants "try again later", the content needs
   a second check node, not a `repeatable` flag.
5. **Whether an unprompted line may ever set a story flag.** Today a passive
   conversation is authored exactly like any other and *could* set one. The
   convention in this slice is that it does not, so a player who never triggers it
   loses nothing but texture.
6. **The cap.** Two unprompted lines per voice per session is a guess. It needs a
   human playtest on Windows, which this round did not have.
