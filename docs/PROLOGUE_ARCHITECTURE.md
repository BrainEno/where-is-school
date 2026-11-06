# Prologue Architecture — Biology Class Slice

This note covers only what the prologue slice adds. `docs/ARCHITECTURE.md` remains
the authority on overall boundaries; where the two disagree, the older document
wins and this one is wrong.

## 1. Ownership map

| Concern | Owner | File |
|---|---|---|
| Story flags (runtime) | existing `GameState` autoload | `scripts/autoload/game_state.gd` |
| Flag identifiers | `PrologueFlags` (constants only) | `scripts/narrative/prologue_flags.gd` |
| Knowledge record | `NarrativeLedger` autoload + `NarrativeRecord` | `scripts/narrative/narrative_ledger.gd` |
| Declared records | `PrologueRecords` (data table) | `data/prologue/prologue_records.gd` |
| State read/write façade | `PrologueState` (static helpers) | `scripts/narrative/prologue_state.gd` |
| Dialogue model | `DialogueScript` / `DialogueNode` / `DialogueLine` / `DialogueChoice` | `scripts/dialogue/` |
| Dialogue runtime | `DialogueSession` (no UI, no world) | `scripts/dialogue/dialogue_session.gd` |
| Dialogue content | `PrologueDialogue` | `data/dialogue/prologue_dialogue.gd` |
| Speaker metadata | `CharacterDirectory` | `scripts/dialogue/character_directory.gd` |
| Inspection content | `PrologueInspections` | `data/prologue/prologue_inspections.gd` |
| Beat orchestration | `PrologueFlow` | `scripts/prologue/prologue_flow.gd` |
| Location loading / respawn | `SceneDirector` | `scripts/prologue/scene_director.gd` |
| Room geometry and markers | `ClassroomLocation` + `.tscn` | `scripts/locations/`, `scenes/locations/` |
| Targeting | `InteractionSensor` + `Interactable3D` | `scripts/interaction/` |
| UI | `DialoguePanel`, `PrologueHud`, `InspectionCard`, `NoteBook` | `scripts/ui/`, `scenes/ui/` |
| Cue audio | `AudioCues` (procedural, no assets) | `scripts/audio/audio_cues.gd` |
| Top-level composition | `PrologueRoot` | `scripts/main/prologue_root.gd`, `scenes/main/main.tscn` |

Three rules hold the design together:

1. **Content never applies itself.** Dialogue nodes and choices *declare* flags and
   record ids. `DialogueSession` emits them as requests. `PrologueFlow` is the only
   code that writes them.
2. **Only one thing counts as a fact.** `NarrativeRecord.Kind.OBSERVED` is the sole
   kind `NarrativeLedger.has_observed()` accepts. Q's statements are `HEARD`, the
   protagonist's gaps are `RECALLED`, and the imagined confrontation is `IMAGINED`.
3. **Presentation cannot mutate state.** `DialoguePanel`, `PrologueHud`,
   `InspectionCard` and `NoteBook` are read-only views driven by signals. The
   rehearsal's cool lighting happens in `ClassroomLocation.set_rehearsal_lighting()`,
   which touches light colours and nothing else.

## 2. Interaction

Props are `Area3D` nodes in the `interactable` group carrying an `interact_id`,
a prompt and a `focus_priority`. They know nothing else.

`InteractionSensor` runs on the player, and picks the best target each physics
frame: within `reach`, inside a forward cone derived from the camera, scored by
`focus_priority * 10 + alignment * 2 - distance * 0.05`. Priority is what makes a
0.5 m set square on a desk targetable next to a 2 m teacher's desk.

`PrologueFlow._handle_interact_id()` is the only place an id becomes behaviour:
inspection, conversation, or door. Unknown ids push a warning rather than failing
silently.

Collision deserves a note. The classroom's camera-facing walls are 0.5 m parapets
so the fixed 2.5D camera can see in, with full-height *invisible* collision behind
them — except at the door, where the guard is split to leave a real 1.1 m gap.
`tests/integration/test_classroom_scene.gd` point-queries both the doorway and the
wall to prove it.

## 3. Dialogue

`DialogueScript` is an ordered graph of `DialogueNode`s. A node is a run of lines,
then either choices or one automatic continuation. Each choice owns:

* its own reply lines (spoken *before* the jump, so a reply is never silently
  identical to another),
* its own flags and record ids,
* an optional availability requirement.

`DialogueSession` validates the whole graph before starting (`DialogueScript.validate()`)
and refuses to half-play invalid content. It emits `line_presented`,
`choices_presented`, `flags_requested`, `records_requested`, `cue_requested` and
`session_finished`; it has no reference to a node tree, so unit tests drive a whole
conversation in ten lines.

The panel supports speaker name + role + accent, portraits, long text with a
character-reveal speed that can be skipped, choices by click or `1`–`4`, and a `Tab`
backlog that is also written for reply lines. Backlog entries carry the "imagined"
marker, so the transcript preserves the difference too.

## 4. Subjective recollection

The rehearsal is not special-cased prose; it is a *mode*:

* `DialogueNode.with_imagined()` and `DialogueLine.imagined` flag the content.
* `DialoguePanel` switches to a cooled, dimmed frame with a standing caption
  ("Rehearsal — nothing here is happening in the room").
* `DialogueSession.records_requested` records are checked in
  `PrologueFlow._apply_records()`: any non-`IMAGINED` record requested while the
  session is imagining is **refused with a pushed error**. The player cannot
  observe something inside their own head.
* Location lighting shifts, and the objective line is untouched.

`tests/integration/test_prologue_flow.gd::_test_rehearsal_isolation()` records the
player's global position, the ledger's id list and the whole `GameState` snapshot
before the rehearsal, plays the entire rehearsal choosing option 0 at every prompt,
and asserts all three are unchanged. That is the acceptance criterion, executable.

## 5. Narrative state

`NarrativeLedger` keeps an ordered, capped (256) list of `NarrativeRecord`s with a
`kind`, a title, a body and a source id. It exposes `has_observed()` (OBSERVED
only), `records_of_kind()` and `to_dict()`. `NoteBook` renders the four groups —
*Seen*, *Heard*, *Remembered*, *Imagined* — straight from that API, so the player
can audit the difference without a narrator explaining it.

Story flags live in the existing `GameState`, with identifiers in `PrologueFlags`.
Everything is namespaced `prologue.*`; the values are a save-data contract.

Repeat interactions are read-only by construction: `PrologueFlow._inspect()` checks
the ledger before writing, swaps in the entry's shorter `repeat` text, and skips
flag writes on the second visit. Content with no record id (`own_desk`, the door)
never writes anything.

## 6. Beat order

`PrologueRoot` loads the classroom through `SceneDirector`, wires `PrologueFlow` to
the room's markers, and starts `PrologueFlow.begin()`. The flow walks:

```
wake (fade, seated pose, control returns)
  → Q conversation (starts itself, four choice points)
  → explore (schoolbag, five more inspectables, optional door)
  → rehearsal (once, gated on "bag checked" AND "Q talked")
  → lesson clock: bell → empty chair → N enters → N permits free activity
  → door unlocks → corridor → yard → gate (milestone end)
```

Thresholds are `Area3D` bodies watched by `PrologueRoot._on_threshold_crossed()`;
location changes fade, load, respawn via a named `Marker3D`, then fade back.

## 7. Deliberate omissions

* No save/load. `GameState` still exposes `get_snapshot()` for a future
  `SaveManager`; nothing serialises yet.
* No street, green animal, or gate exterior. The milestone ends at the gate.
* No B onstage, in any form.
* No text-size settings UI yet (the `DialoguePanel` exposes `set_body_font_size()`
  and `set_text_speed()` for the settings screen that will call them).
* No third-party dialogue addon. Dialogic was not installed because the slice
  needed conditional choices, backlog and explicit epistemic kinds, and a ~400-line
  project-owned runtime delivered them with tests and no plugin risk. That is a
  scoped decision for the slice, not a rejection of the spike in
  `docs/TECHNICAL_ROADMAP.md`.

## 8. Visual evidence and offline previews

This slice is authored on machines without a GPU (the headless sandbox and the
CI runner have no Vulkan/OpenGL driver), so an in-engine screenshot cannot be
taken there. Rather than ship a mocked-up illustration, two project-owned tools
produce honest evidence straight from the shipped data:

```bash
godot --headless --path . --script res://tools/preview_capture.gd
godot --headless --path . --script res://tools/dialogue_transcript.gd
```

* **`tools/preview_capture.gd`** reads the live scene graph — every mesh
  transform, vertex array and material colour — and projects it through the
  actual `Camera3D` of the player rig with a small software rasteriser
  (near-plane clipping, back-face culling, per-pixel z-buffer). It writes the
  wake view and a top-down plan to `user://preview/`. It proves framing,
  composition, prop placement and occlusion. It does **not** prove lighting,
  shadows, tone mapping or fog, and must not be presented as a render.
* **`tools/dialogue_transcript.gd`** plays the real `DialogueSession` over the
  real content and writes the conversation, the inspection cards and the
  resulting ledger to plain text.

Committed output lives in `docs/captures/`:
`classroom_wake_view.png`, `classroom_plan.png`, `classroom_layout.json`
(generated from the live scene, so it drifts loudly if geometry moves) and
`dialogue_transcript.txt`. Regenerate them after any layout or content change.
