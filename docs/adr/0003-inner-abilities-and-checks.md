# ADR 0003 — Inner voices and dice checks

- Status: **Proposed. Not accepted.** This is an engineering proposal for
  playtesting, not a decision the owner has signed off.
- Date: 2026-11
- Supersedes: nothing. Extends ADR 0002 (dialogue and narrative state).
- Superseded by: nothing yet.

> **Status update, Phase 6a (2026-11).** The owner has since decided that the one
> provisional voice is to be **extended into several voices** (see
> `docs/NARRATIVE_BIBLE.md` § Inner voices, `docs/TECHNICAL_ROADMAP.md` Phase 6a).
> Read the roster statements below as the state of *this* proposal when it was
> written: one ability ships, and the number of voices is still not a design this
> document decides. The engineering half changed in Phase 6a without changing any
> number: the registry, the profiles, the checks and the passive director now work
> with any number of voices, so "one voice" is a content fact rather than an
> assumption in the code. The formula, the difficulties and every value in the
> tables are still provisional.

## How to read this document

There are two kinds of statement below, and they are kept apart on purpose.

**Owner-confirmed constraints** (these came from the brief and are not negotiable
here):

1. a check may be **visible** (numbers shown) or **hidden** (only the reaction is
   shown), and the difference must be real, not cosmetic;
2. there is **one provisional ability** in this milestone — not a roster, not a
   character sheet, not levels, and not permanent canon;
3. every number is **provisional** and expected to be retuned after playtesting;
4. checks are authored **in dialogue data**, not in a second system with its own
   authoring format;
5. a failed check must leave the player something to do. No dead ends, no soft
   locks.

**Engineering proposals** (this document's own content, open to being overruled):
the voice's name and character, the exact formula, the difficulty values, and the
passive-rule list.

## Context

The protagonist needed a way to notice things that is neither a silent stat check
nor the author telling him the answer. Two earlier constraints shaped the code: the
dialogue layer is hand-built, and everything narrative already routes through it
(ADR 0002). A second system for "ability encounters" would have meant two ways to
author a scene, two ways to test one, and two places for a translation to go wrong.

An earlier draft of this ADR proposed four voices (counting, space, memory, people)
and a d10. Both were withdrawn after review: four voices could not be demonstrated
in the content that exists, and the d10's flat distribution made a single die decide
more of the scene than the fiction could justify. What follows replaces both.

## Decision (proposal)

### 1. One voice, and it is provisional

```json
"orientation": {
  "value": 3,
  "speaker": "voice_orientation",
  "max_passive": 2
}
```

**Orientation** (路感) is a sense of where things are in relation to each other:
heights, seams, what lines up and what does not. It is confident about shapes and
has nothing to say about people, which keeps it from becoming a lie detector or a
personality test. Its failure lines are written as one real detail seen from the
wrong angle — a different question, not a retry.

The name, the personality and the value of 3 are proposals. The single-voice scope
is not.

### 2. Passive and active, on one data model

**Passive** — a rule in `data/abilities/abilities.json`:

```json
{
  "id": "playground_hoop_orientation",
  "ability": "orientation",
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
  "speaker": "voice_orientation",
  "text": "Hold on. Look at where that pole stands.",
  "check": {
    "ability": "orientation", "difficulty": 9, "kind": "hidden",
    "success": "vh_ok", "failure": "vh_bad"
  }
}
```

**Active** — the player reaches a check by choosing an approach in a conversation:

```json
{"id": "frame", "text": "Try the door against its frame.", "next": "ps_boundary_check"}
```

and that node carries `kind: "visible"`, so the numbers are shown. Choosing *how* to
look is the player's decision, made in the fiction ("try the frame" vs "read the
sheet"), not in a menu of skills. With one voice this still works: the choice is
about the approach, not about which stat to use.

Both halves produce the same result dictionary, are validated by the same graph
validator, and are checked for translation parity by the same test.

### 3. The formula (provisional)

```
2d6 + ability value + situational modifier  >=  difficulty   -> success
```

- **2d6**: a bell curve centred on 7, so the voice's value and the authored
  difficulty matter more than one lucky roll, and a +1 means something. The cost is
  that probabilities are not obvious to a player; the game never shows them, and
  the slice keeps every difficulty inside a narrow band for that reason.
- **ability value** comes from `abilities.json` (3 in this milestone). Small on
  purpose: 0-6 is a person, 10 is a caricature.
- **situational modifier** is declared per check (`modifiers: [{flag, value}]`) and
  summed from flags. Missing flags contribute nothing.
- **difficulty** is authored per check in 1..30 and clamped by the resolver. With
  2d6 + 3, the useful band is 7..11: 7 is "usually", 9 is "two times out of three",
  11 is "worth trying anyway". Current content uses 7, 8 and 9.
- The result is a dictionary: `ability`, `ability_value`, `dice`, `die` (the 2d6
  sum), `dice_count`, `die_faces`, `modifier`, `total`, `difficulty`, `margin`,
  `success`, `key`, and `reused`.

Both edges are part of the contract and are tested: a 2 can still succeed against a
low difficulty, and a 12 cannot save an unreachable one.

### 4. One roll, one key, one session

`CheckResolver` is seeded once per session (from the clock in the game, injected in
tests). The dice for a check come from `hash(session seed, check key)`, where the
key is `conversation/node`. Consequences, all deliberate:

- the same check always falls the same way **within a session**, so walking out and
  back in is not a reroll;
- a fixed seed reproduces a whole run, which is what keeps CI deterministic;
- the designer cannot know what a specific check will roll, so difficulty tuning
  stays statistical rather than "make this one pass".

On top of that, the runtime records the resolved result in a story flag
(`check:<conversation>:<node>`) and **replays the record** on re-entry, marked
`reused`. Content also hides an already-attempted approach from the choice list
(`conditions.not_flags: ["check:pg_shed:ps_boundary_check"]`), so the player is not
offered a button that would only repeat text.

`repeatable: true` exists for a check the author wants to be retryable; it bypasses
the record but not the key, so the dice stay the same. It is unused in this slice.

### 5. Visible and hidden

Both use the same resolver and the same record flag. The difference is presentation
and it is enforced by a test, not by convention:

- **visible** — the check overlay appears with the ability name, the two dice, the
  modifier, the total and the difficulty, and the verdict. A reused result says so
  instead of animating a second time.
- **hidden** — nothing numeric appears. The player only sees which line comes next.
  A hidden check inside a passive conversation is the only way an inner voice can
  volunteer something.

The overlay is a receipt for a decision the player made. It is never the decision.

### 6. Subjective scenes cannot touch this

A conversation marked `subjective` is something the protagonist is imagining. It may
not set flags or objectives, may not record observed or reported knowledge, and — as
of this milestone — may not carry a `check` or a `once` choice, because both write
story state (the dice record, the "this was taken" record). This is refused twice:
the graph validator rejects the content at load time with the conversation, node and
choice named; the runtime refuses to write anything if invalid content reaches it
anyway. `tests/subjective_isolation_test.gd` asserts both halves by comparing a whole
GameState snapshot before and after.

### 7. What this costs

- A single voice cannot show off range. That is the price of being able to test the
  system honestly with the content that exists.
- 2d6 makes a +1 modifier meaningful, which means modifiers now need to be authored
  carefully; a stacked +3 would swamp the dice.
- Every number here is provisional. Retuning difficulties is a content edit, not a
  code change, which is why the resolver exposes the sum and the faces separately.

## Alternatives considered

- **d10, flat.** Simple to explain, but a single die decides more than the fiction
  does, and a +1 is nearly meaningless. Withdrawn.
- **d20, flat.** Worse for the same reason.
- **3d6.** Better curve, more arithmetic to explain for no visible gain at this
  scale. 2d6 is the compromise.
- **Four voices.** They could not be demonstrated: three of them had no scene that
  needed them, and a system whose breadth is untested is a system whose breadth is
  unknown. One voice, used in six places, is testable.
- **No dice at all.** Cheap, but then the voice's value is decoration and the
  failure branches never run.

## Status of the numbers

Every value in this document is a starting point for playtesting:

| thing | value | provisional |
| --- | --- | --- |
| formula | `2d6 + value + modifier >= difficulty` | yes |
| ability value | 3 | yes |
| difficulties | 7, 8, 9 in shipped content | yes |
| passive session cap | 2 | yes |
| voice name / character | Orientation / 路感 | yes |

The only thing here that is not provisional is the shape: one voice, two kinds of
roll, one resolver, data-authored checks, no dead ends.
