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

### 7. Boot behaviour: the title screen decides (amended for #62 / #95)

*Originally:* the project booted straight into `main.tscn` and resumed any readable
save, because there was no menu to ask. That is superseded now that a menu exists.

The project boots into `scenes/ui/title_screen.tscn`. `Session.inspect_save()` reads
the file once (without applying it) and the menu follows from the answer:

| Save state | Entries | Notes |
|---|---|---|
| none | **Start** / Settings / Quit | Start enters the opening; nothing to confirm |
| readable | **Continue** / New game / Settings / Quit | Continue enters `main.tscn`, whose director resumes the file exactly as before |
| unreadable | New game / Settings / Quit | the reason is shown on the title screen; there is no Continue, and reading it already copied it to `save.broken.json` (6) |

The same New game is offered in the **pause menu** (Esc / Start during play) and as
**Start again** on the end-of-slice card. Every one of them asks first, with the focus on
*Cancel*; cancelling (Esc, B, the Cancel button, a click outside) changes nothing — not
the file, not the flags, not the knowledge.

### 8. Starting a new game: one ordered path

All three entry points call `Session.start_new_game()` (`scripts/ui/game_session.gd`),
which runs these steps in this order and returns a report of them:

1. **Silence the old world**: its `OpeningSequence.autosave_enabled = false`, then
   `Save.unbind_world()`. Unbinding alone is not enough — a save with no world bound
   still writes the flags — so the director's own switch comes first.
2. **Unpause** (the pause menu may have paused the tree).
3. **Free the old world** and wait two frames, so nothing in it can run a checkpoint
   after the file is gone.
4. **Delete the save** with `Save.delete_save()`. Because that call also removes
   `save.broken.json`, its bytes are read first and written back: a quarantined copy
   is the player's, and starting over does not silently discard it (6).
5. **Clear the session**: `GameState.clear()`, `NarrativeState.clear()`, and release
   any held input actions. Location, objective and every story flag live in
   `GameState`, so they go with it.
6. **Verify**: no save file, no flags, no knowledge entries — otherwise the report is
   not `ok` and an error is logged.
7. **Enter the opening**: `main.tscn` is loaded fresh. Its `DialogueController` takes a
   new dice seed from the clock, and with no file the director starts at the wake.

Tests: `tests/opening_resume_test.gd` (title menu by save state, cancel keeps
everything, confirm from the title and from the pause menu, an unreadable save, and
the next boot carrying no old flag, entry, room or seed) and
`tests/opening_flow_test.gd` (Start again from the end card after the whole slice,
on the controller).

### 9. Preferences are not progress

`user://settings.cfg` holds the preferences, owned by `Settings`
(`scripts/autoload/settings_manager.gd`): `[text]` size and speed, `[audio]` master,
music and sfx, `[display] ui_scale`, `[input]` one encoded list per rebound action, and
`[settings] version`. `[display] locale` in the same file belongs to `Loc` and is never
written or removed by `Settings` — every write re-reads the file first and changes only
its own key. New game does not touch this file. Unknown values fall back to the default
and are reported; a binding list with any undecodable entry is ignored as a whole, so an
action is never left half-bound or unbound.

- **Revisit when saves can be taken mid-beat:** the checkpoint restriction in 4
  should then be lifted by making beats resumable, not by loosening the format.
- **Revisit when there is more than one slot:** `inspect_save()` and the confirmation
  wording assume one.

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
