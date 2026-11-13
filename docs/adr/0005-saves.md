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

*Amended for Save and quit:* the pause menu's **Save and quit** writes a save on request,
but only where the same condition holds — `Session.is_at_rest()`: the prologue is behind
the player (`next_step()` is empty), no beat holds the lock, no conversation is open, the
slice is not over, and the player has control. Such a moment has nothing in flight, so the
file is the same kind of file a checkpoint writes (flags, knowledge, seed, room and the
exact position). Anywhere else the menu does not write: it says that the next Continue
will load the last save (naming its room and time) or that there is none, and asks before
leaving, with the focus on *Cancel*. A write that fails is reported the same way and never
leaves silently. Leaving switches the world's autosave off first, so the frame before the
scene changes cannot put a different checkpoint on disk.

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
(the copy is proved by reading it back before it is named as one; a copy of the same
bytes is left alone rather than rewritten, and the original is left in place until the
next successful save overwrites it) and
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

**Continue** (zh-CN 从上次继续) carries one line under it: the room and the time of the
save it loads (`MenuStyle.save_caption()`, e.g. "Corridor · 2026-11-12 14:03"), so the
player knows what they are going back to before they press it. The pause menu shows the
same line under its heading. The title takes it from the one `inspect_save()` it already
makes at boot; the pause menu, which redraws during play, reads it with
`SaveManager.peek_save()` (9) instead of `read_save()`, so opening it can neither restore
nor quarantine anything.

The same New game is offered in the **pause menu** (Esc / Start during play) and as
**Start again** on the end-of-slice card. Every one of them asks first, with the focus on
*Cancel*; cancelling (Esc, B, the Cancel button, a click outside) changes nothing — not
the file, not the flags, not the knowledge.

### 8. Starting a new game: one ordered transaction

All three entry points call `Session.start_new_game()` (`scripts/ui/game_session.gd`),
which runs these steps in this order, returns a report naming them, and emits
`new_game_failed` with that report when it could not finish:

1. **Writes stop**: `Save.suspend_writes(true)` *first*, then the old director's
   `autosave_enabled = false` and `Save.unbind_world()`. Unbinding alone is not enough —
   a save with no world bound still writes the flags — and neither is the director's
   switch: a node that is no longer the world can still hold a reference. The writer
   itself refuses now.
2. **Unpause** (the pause menu may have paused the tree).
3. **Copy the session to memory**: every flag and every knowledge entry. This is the
   second way back, for the case where the file is fine but the hand-off is not.
4. **Stage the save, never delete it**: `Save.stage_save()` moves the file to a unique
   `save.json.<nonce>.staged` and proves the bytes arrived. The save path is now empty,
   which is what a new run means, and the previous run is still on disk under a name the
   transaction remembers.
5. **Free the old world** and wait two frames, so nothing in it can run a checkpoint.
6. **Clear the session**: `GameState.clear()`, `NarrativeState.clear()`, and release any
   held input actions. Location, objective and every story flag live in `GameState`, so
   they go with it.
7. **Verify**: no save at the save path, no flags, no knowledge entries — and the
   quarantined copy of an unreadable save, if there was one, still the same bytes (6).
   Recovery is deliberately impossible here: it is suppressed while writes are suspended.
8. **Enter the opening** and check the hand-off twice: `change_scene_to_file()`'s return
   code *and* whether `current_scene` actually changed. Writes stay suspended through
   this step, because the new world's `_ready` asks `has_save()` and a recovery pass at
   that moment would put the staged copy back and resume the run being replaced.
9. **Commit**: discard the staged copy (proved gone), then every other `.tmp`/`.bak`/
   `.staged` file beside the save (`Save.discard_strays()`; anything that will not go is
   named in `leftovers`), then release writes. Those files belong to the run the player
   just chose to end; left behind, the first moment the save path is empty — the new run
   quit before its first checkpoint — would *recover* one of them, and the title would
   offer to continue the old run.

With no save at all, step 4 is `no_save` and the rest is the same.

**If anything fails before 9, nothing is half-done.** Steps 1–3 are reversible, so a
failure at 4 puts the world and its autosave back and leaves the player in the run they
were in. A failure after 5 restores the session from the memory copy *and* puts the
staged save back where the game reads it, and takes the player to the title screen — the
one screen that is always safe to be on — with the progress on disk and Continue
offered. The report says which step failed (`reason`: `busy`, `save_stage_failed`,
`state_left`, `scene_change_failed`), why (`detail`), where the save is (`save_path`,
`staged_path`, `recovery_path`), what was put back (`rollback`), and what could not be
cleaned up (`leftovers`). A second press while the first transaction is between two
awaits is refused with `busy` and runs none of the steps again.

**What the player sees** (#146). The `detail` is for the log; the screen shows
`NewGameFailureText.describe(report)` (`scripts/ui/new_game_failure_text.gd`): a localised
line for the reason, whether the save is safe (or where its copy is), and that they can try
again. A failure before the world is freed is shown by the screen that started it — the
pause menu reopens (paused, New game focused), the end card keeps Start again focused, the
title stays — and that screen calls `Session.mark_new_game_failure_shown()`. A failure after
it lands on a title screen that did not exist when `new_game_failed` was emitted, so the
title reads `Session.take_unshown_new_game_failure()` in `_ready`: the report is handed over
once, and no later title shows it again. The screens keep the report rather than the text,
so a language switch renders it again; `busy` is answered the same way, without a signal.

Tests: `tests/opening_resume_test.gd` (title menu by save state, cancel keeps
everything, confirm from the title and from the pause menu, an unreadable save, the next
boot carrying no old flag, entry, room or seed, a save that cannot be moved, an opening
that cannot load, and a second click), `tests/opening_flow_test.gd` (Start again from
the end card after the whole slice, on the controller) and
`tests/new_game_failure_ui_test.gd` (each failure from the pause menu, the end card and the
title, through real key, pad and mouse input: the message, the focus, the bytes on disk, a
busy refusal, the language switch and the largest text size).

### 9. Writing a save is a swap, and it is proved

The write path (`SaveManager.write_payload()`) never rewrites the file in place:

1. The new save is written to `save.json.<nonce>.tmp` with a name nothing else in this
   run will pick, then **read back and compared byte for byte**. `store_string()`
   returning is not evidence that the bytes are there — a full disk, a truncated write
   and a directory that lies all look like success at that call.
2. It is renamed onto `save.json`. Some platforms refuse to rename onto a file that
   exists; then the fallback **moves the old save aside** to `save.json.<nonce>.bak`,
   proves that copy, installs the new save, and removes the backup. If the install
   fails, the backup is renamed back. `SAVE_PATH` is never passed to `remove()` during a
   write: the player's only copy is not deleted to make room for a better one.
3. Files a crash left behind (`.tmp`, `.bak`, `.staged`) are cleaned up, and any that
   could not be removed are named in the result's `leftovers` and logged, not ignored.
   A `.bak`/`.staged` may be *restored* on the next read, but only when there is no save
   at all, and never while a new game holds the files (8). Because of that, a committed
   new game removes every `.bak`/`.staged` the old run left (`discard_strays()`, step 9
   of 8): a leftover that outlived the new game would be "recovered" the first time the
   save path is empty again, and bring back the run the player chose to end.
   `peek_save()`, the read the menus use for their captions, does no recovery and no
   quarantine at all; it only reports whether a readable save exists and where and when
   it was made.

`delete_save()` returns `{ok, removed, leftovers}` and reports a filesystem refusal
instead of silently doing nothing. It does not remove `save.broken.json` unless the
caller asks with `{"broken": true}`.

**What this is not.** Godot's ordinary file API — `FileAccess`, `DirAccess` — offers no
compare-and-swap, no atomic multi-file transaction, no `fsync` and no locking. This
design therefore does not claim to be safe against two processes writing the same
`user://` file at the same time, nor against power loss between a rename and the
directory entry reaching the disk. What it does claim, and what the tests check, is
narrower and true: a write whose own calls fail, or whose bytes do not come back, never
destroys the save that was already there, and the result says so.

### 10. Preferences are not progress

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
  rebuilt from the file, and a write that cannot land leaves that file untouched) and
  `tests/save_validation_test.gd` (bad envelopes, versions, flag types and knowledge
  sources, plus every failure of a write, a rename, a backup and a delete, injected
  deterministically).
