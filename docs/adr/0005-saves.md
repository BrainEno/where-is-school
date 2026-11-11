# ADR 0005 — Save Format, Versioning and Restore Policy

- **Status:** Accepted for the prototype (two product points below are marked for
  revisiting once a menu exists)
- **Date:** 2026-11-06

## Context

The audit (#60) found the obvious gap: quitting loses the whole session. Two state
singletons had been deferring persistence to "a future SaveManager" and nobody owned
it, while `NarrativeState.restore_snapshot()` accepted anything shaped roughly like
a snapshot and downgraded an unknown knowledge source to `observed` — the one
transformation ADR 0002 exists to prevent.

The prologue is now a list of flag-gated steps (ADR 0004's prerequisite, #59), so
"what happens next" is a function of the flags. What is still not data is the
*place*: which room, which spawn marker, where in the room the player stood, and
the dice seed. A save therefore has to carry four things and nothing else.

There is no menu, no title screen, and no slot picker. That constrains the design
more than the file format does.

## Decision

### 1. One slot, one file, an envelope with a version

`user://save.json`:

```json
{
  "format": "where-is-school/save",
  "version": 1,
  "saved_at_unix": 1770000000,
  "payload": { "flags": {}, "entries": [], "check_seed": 0, "world": {} }
}
```

`format` is a constant that identifies the writer; a file without it is not ours to
guess about. `version` is an integer the reader compares before it looks at
`payload`. `saved_at_unix` is for the player and for bug reports, never for logic.

**Consequences of one slot:** the file is small (a few KB), the player never has to
choose, and autosave can never grow the disk. Multiple slots are a **menu feature**,
not a save-format feature: when a menu exists, the slot becomes a file name and
nothing else in this ADR changes.

### 2. Flags are stored with their type, not as bare JSON

JSON has no integers, and the story flags include counters and check results. A
flag written as `1` and read back as `1.0` breaks `voice_count:*` comparisons and
turns `check:*` totals into floats. Every value is therefore encoded as a tagged
pair:

```
{"t": "b", "v": true}      {"t": "i", "v": 3}        {"t": "f", "v": 1.5}
{"t": "s", "v": "text"}    {"t": "a", "v": [...]}    {"t": "d", "v": {...}}
{"t": "n"}                 // null
```

Arrays and dictionaries encode their members the same way, so a check record
(`{"die": 7, "total": 9, "success": true}`) survives byte-for-byte. A value of a
type the codec does not know is a **payload error**, not something to coerce.

### 3. What is saved, and what is deliberately not

| Saved | Why |
|---|---|
| `flags` | progress; the director's only memory (#59) |
| `entries` | what the protagonist knows, and how they know it (ADR 0002) |
| `check_seed` | so the same check, re-entered after a load, shows the same dice |
| `world.location_id`, `world.spawn`, `world.position`, `world.facing` | which room, which marker, and where the body stood |

Not saved: anything mid-flight. A save taken during a fade, a beat or an open
conversation would have to describe half-applied state; instead the save points are
**beat boundaries** (see 4), so no such state can exist when the file is written.
Camera, pose, UI and the dialogue backlog are presentation, not progress, and are
rebuilt on load.

### 4. When the game saves

- On arriving in a location (`LocationFlow` finishes a transition).
- When the prologue hands control to the player.

Both are points where no conversation is open and no beat holds the lock. There is
no "save anywhere" button: it would need every in-flight system to be
serialisable, and the player loses nothing today because the two checkpoints above
are exactly the moments where progress is meaningful.

### 5. Loading is all-or-nothing, except per-entry knowledge

Reading happens in two tiers:

1. **Structure** — envelope fields, version, payload shape, every flag value's
   type. Any failure refuses the whole file and applies nothing. A save is never
   half-loaded.
2. **Knowledge entries** — one entry with an unknown source, an empty id or empty
   text is *rejected on its own* (ADR 0002: never downgrade to `observed`) and
   reported in the load result, and the rest of the save still loads. This is the
   only downgrade path, and it is loud: the rejected ids appear in the log and in
   `SaveManager.last_result`.

Because validation runs before application, a refused load leaves the session
untouched — starting a new game is then a decision, not a fallback.

### 6. A file we cannot read is kept, not deleted

An unreadable or unknown-version save is copied to `user://save.broken.json`
(the original is left in place until the next successful save overwrites it) and
the reason is shown to the player on the end-of-slice card, in both languages,
including what to do about it. "Silently starting fresh" is the failure mode this
ADR exists to prevent: the audit's second acceptance criterion.

Version policy: a file with a **newer** version is refused with "this save was
written by a newer build"; an **older** version is migrated by a registered
function per step (`_migrate_v1_to_v2`, …) or refused if none exists. v1 has no
predecessor, so nothing migrates yet; the seam and the refusal are implemented and
tested with a synthetic v0/v2 file.

### 7. Boot behaviour: resume, because there is no menu

The project boots straight into `main.tscn`; there is no title screen to offer
"continue" versus "new game". So: **if a readable save exists, the game resumes it**;
if it does not, the prologue starts from the beginning. A new game is
`SaveManager.delete_save()` — an API the future menu will call.

- **Revisit when a menu exists:** resume-versus-choose becomes a menu decision.
- **Revisit when saves can be taken mid-beat:** the checkpoint restriction in 4
  should then be lifted by making beats resumable, not by loosening the format.

## Consequences

- Progress survives a quit from the second location onward, and from any point in
  the prologue that a checkpoint has passed.
- The save file is readable, diffable, and describes itself; a bug report can carry
  one.
- A corrupt save is a visible, actionable event rather than a mystery reset.
- `NarrativeState.restore_snapshot()` now validates like `record()` does and emits
  `entries_restored` instead of pretending a restore is a clear.
- The seed is part of the session, not of the resolver: `DialogueController` owns it
  and gives it to the file.
- Tests: `tests/save_roundtrip_test.gd` (a real scene is saved, torn down and
  rebuilt from the file) and `tests/save_validation_test.gd` (bad envelopes,
  versions, flag types and knowledge sources).
