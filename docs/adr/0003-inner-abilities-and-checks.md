# ADR 0003 — Hybrid Inner Abilities and Visible/Hidden Checks

- **Status:** Accepted for playground slice
- **Date:** 2026-11-07

## Context

The project needs a first RPG core that:

- gives the protagonist inner voices without copying Disco Elysium's 24-skill set;
- lets some inner reactions happen automatically (passive) and some only when the player chooses (active);
- shows dice transparently when the player initiates a check (visible) and keeps it hidden when a passive voice reacts (hidden);
- stays testable and deterministic.

Existing systems: `DialogueGraph`/`DialogueRuntime`/`DialogueLibrary` for data-driven dialogue, `GameState`/`NarrativeState` for flags and knowledge, `InspectionLibrary` for examinations, `LocationHost`/`LocationRoot` for spatial routing.

## Decision

### 1. Hybrid ability model (own design, 4 abilities)

Four inner abilities, not a full tree:

| id | name (en / zh-CN) | tone | example role |
|---|---|---|---|
| `keen_eye` | Keen Eye / 细察 | precise, detached | notices spatial anomalies, connects visual details |
| `recollection` | Recollection / 回想 | uncertain, associative | surfaces incomplete memories |
| `gut_feeling` | Gut Feeling / 直觉 | urgent, impressionistic | reads unspoken tension |
| `steadiness` | Steadiness / 定力 | calm, grounding | resists over-interpretation |

Each `InnerAbility` (Resource) has:

- stable `ability_id`
- `name_key` / `description_key` (locale keys)
- `base_value` + `level` → `get_value()`
- `active_allowed` / `passive_allowed`
- `tone` for writers

Data lives in `data/abilities/abilities.json` (1 file, 4 entries). Locale strings live in `data/locale/<locale>.json`. This keeps the set small and expandable without a skill-tree UI.

### 2. Active vs Passive

- **Active:** player picks a choice that carries a `check` block (`ability`, `difficulty`, `visible:true`). The runtime runs the check immediately, stores `check_success:<id>` in `GameState`, and displays roll/total/difficulty/outcome inline in `DialoguePanel`.
- **Passive:** evaluated on entering `playground` (via `Rpg.evaluate_passives()` in `OpeningSequence._trigger_playground_passives()`). Rules in `PassiveTrigger` may specify `use_hidden_check`. Passive lines are subtle and infrequent (once per session).

Inner abilities may mislead or contradict each other. Failure still records narrative value; no hard locks.

### 3. Dice — both modes, one engine

Formula: `total = d20 (1..20) + ability_value + modifier` ; `success = total >= difficulty` ; `margin = total - difficulty`.

- Same `CheckEngine` for visible and hidden. Only presentation differs.
- RNG injectable (`RandomNumberGenerator` seeded for tests). Production uses randomize; tests set seed for determinism and re-run assertions for boundary/success/failure.
- Anti-spam: `CheckEngine` stores result under `check:<id>` and `StoryFlags.check_success_flag(check_id)`; re-rolling without `allow_reroll` returns stored result with `already_attempted:true`. UI appends `(already)`.

### 4. Integration points

- `DialogueGraph.DialogueNode` / `DialogueChoice` now have optional `check: DialogueCheck` (parsed in `_parse_check`, validated difficulty 1..30, unknown field rejected).
- `DialogueRuntime._run_check()` resolves ability value via `Rpg` registry (fallback temp engine), rolls, emits `check_performed`, and writes flags for branching (`all_flags` / `not_flags` on subsequent nodes).
- `DialogueParity._compare_check()` ensures both languages have identical checks (id/ability/difficulty/modifier/visible).
- `InspectionLibrary` unchanged for passive presentation; passives that need checks are driven by `RpgManager`.
- Bilingual content: new chapter `playground` in `data/dialogue/<locale>/playground.json` and `data/inspections/<locale>/playground.json` plus `alley`/`estate_gate`; parity validates them.

### 5. Data structures

```gdscript
CheckResult { check_id, ability_id, visible, roll, ability_value, modifier, total, difficulty, success, margin, already_attempted }
AbilityRegistry -> InnerAbility[]
CheckEngine.roll(check_id, ability_id, ability_value, difficulty, modifier, visible, allow_reroll)
PassiveTrigger { trigger_id, ability_id, location_ids, frequency, use_hidden_check, difficulty, success/failure keys }
```

### 6. Success / failure / repeat

- Content authors write paired nodes gated by `check_success:<id>` to branch.
- Both branches record distinct `NarrativeEntry`s and set `PLAYGROUND_*_SEEN` flags, so progress isn't blocked on failure.
- Example: `playground_shed` success records `playground_shed_timetable`; failure records `playground_shed_wet_ledger`. Both advance.

### 7. Open items (owner decision needed)

- Exact ability names/tones (current are placeholders; author may rename `keen_eye`).
- Full playground art beyond graybox (materials, lighting, Q placement).
- SaveManager persistence for `check:<id>` and ability levels (currently in-memory snapshot).
- Whether passive triggers should ever use visible presentation.

## Consequences

- Small, own-system RPG core without copying DE names/UI/assets.
- Deterministic: same seed + same modifiers → same outcome.
- Visible checks are explainable; hidden checks share code but are silent.
- Anti-spam prevents save-scumming by re-activating.
- All new dialogue branches are parity-checked; CI remains honest about import and capture failures (see workflow fix).

## Revisit when

- More abilities or levels are required (expand JSON, not engine).
- Save/load needs versioned schema.
- Passive frequency policy changes.
