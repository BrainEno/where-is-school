# The imagined lesson (teacher B in `expected_b`)

> **Status:** experiment in the shipped classroom. The art layer is done; the gameplay layer
> (B's questioning, the protagonist's answers in three directions, the 「异想天开」 check and
> the exit) is built with placeholder text that waits for the author's wording.
> **Owner:** implementation PR author; art direction is the owner's.

The owner wants the prologue's central set piece to be the scene the protagonist *imagines*
after Q describes the biology teacher (`q_b_looks`): B questions him, he answers normally or
plays mad, and the exchange folds into imaginings inside imaginings. A fixed "stop
imagining" option, available at any time, takes him out but costs him clues.

This round does only the art, as the owner decided:

1. teacher B's model (by an earlier agent) is placed in the imagined scene;
2. she is distorted boldly with the modern/postmodern experiments of PR #196 and PR #200,
   so that she reads as a fantasy or dream;
3. the scene is clearly in a different style from the classroom but is still the classroom;
4. a Munch-like wave filter is put over it.

The author's `expected_b` lines are unchanged (AGENTS.md, writer-text rule). The gameplay
layer is listed under *Not yet* below.

## When it is on

The imagined lesson follows exactly what already showed B's painted wall impression: the
dialogue controller's `subjective_changed` while the `expected_b` conversation is on screen
(`BPresence._on_subjective_changed()` → `ClassroomPresentation.set_b_impression_visible()`),
including the recollection line in the middle, and off at the end, skipped or not. It is
not saved: a reload, a re-entered room and a skipped conversation all show the plain room.
`tests/b_reveal_timing_test.gd` checks the switch together with the wall impression.

It is presentation only: no collision, no interactable, no `NpcActor`. Her real entrance is
still `BPresence.present()` with an actor of npc_id `b`, which no room has yet.

## What it shows

`scenes/locations/classroom/imagined_lesson.tscn` (script `imagined_lesson.gd`), instanced
in `classroom.tscn` as `ImaginedLesson`.

### B, distorted

Her shipped GLB (`assets/models/teacher_b/teacher_b.glb`, moved out of `scenes/dev/`, which
exports exclude) stands in the aisle beside the protagonist's desk, facing his seat, at 1.8×
her size: a seated pupil's view of a teacher who has just said 「你给我站起来」. She plays her
own `explain` and `idle` from `teacher_b_motion.tres`.

`assets/shaders/imagined/dream_figure.gdshader` replaces her look. The shape
(`dream_figure.gdshaderinc`, shared with the ink hull and so with the shadow):

| Distortion | Reference |
|---|---|
| the head swells out of the collar, breathing | Munch's skull-faces; a teacher remembered as mostly a face |
| everything above the waist is drawn out upwards | El Greco / expressionist elongation; she towers |
| the body twists about its axis, more towards the crown | the figure as a brush stroke |
| an S-wave runs up the body and travels in time | the figure on the bridge in *The Scream*, drawn in the same strokes as the sky |
| the crown leans over him and sinks | menace |

The surface takes the PR #196 colour-field room and PR #200 cut-paper figures further: every
vertex colour is turned round the colour wheel and saturated (warm skin goes sulphur-green,
the olive blouse teal), light is two flat steps on a painted direction (deep ultramarine
shadow) rather than the room's lamps, Munch's bands run round her body in bind-pose space and
drift upwards, and a vermilion rim burns on her silhouette. `dream_ink.gdshader` gives her a
thick woodcut line that swells and starves.

### Her after-images

Two more instances stand at the front, behind the lectern and in front of the blackboard,
flat ink silhouettes (`echo` = 1) on a slower wave, a little behind her in time: the teacher
who is everywhere in the room at once. They cast no shadow.

### The room, repainted

`assets/shaders/imagined/munch_wave.gdshader` is a canvas-item filter on a full-screen rect
in a canvas layer (layer -1, group `world_filter`) under the interaction outline (layer 0)
and the game UI (layer 1), so the outline cue and the dialogue stay crisp and legible. It
reads the finished frame (`hint_screen_texture`): no depth buffer, no extra viewport, nothing
renderer-specific; it runs the same on Compatibility, Mobile and Forward+.

1. A vortex sits on B; the script projects her chest to the screen every frame. The room
   is wound round her in a ring; the eye of it is calm and holds her whole figure, so she
   stays readable.
2. Bands: horizontal undulations far from her (Munch's sky over the fjord), rings close to
   her. The picture is pushed back and forth across them in a travelling wave and smeared
   along them in short strokes.
3. Value is mapped onto a Scream palette (night blue, fjord blue, bile green, blood, orange,
   sulphur) with the band position added, so the colours themselves run in stripes. Close to
   40 % of the original colour stays underneath (more inside the eye, where B keeps her own
   expressionist colours): the desks, windows, blackboard and lights are where
   they were. It is the same place, in another style.
4. Edges get a wavering ink; the corners fall into night blue.

`set_active()` spreads the change outwards from her as an orange ring (1.6 s) and draws
it back (0.9 s). The room's geometry, materials and lights are never touched.

## Cost

Three skinned instances of a 49,466-triangle model and one full-screen pass with nine screen
reads, only while the scene is on; when it is off everything is hidden and not processing.
The model adds about 1 MiB to the pack; the owner raised the pack's hard limit from 16 to
24 MiB for it (`tools/verify_build.py`, warning line unchanged at 8 MiB; 32 MiB since round 16). B is now a
registered runtime character in `art/character_rig_audit/runtime_model_manifest.json`.

## Evidence

- `tests/imagined_lesson_test.gd` (CI): off by default; three figures from the shipped GLB
  with the shipped motion library, every mesh on the dream shader and ink; the lead larger
  than life and facing the seat; no collision, interactable or actor; the filter a
  screen-reading canvas item under the UI with no depth read; fades in and fully out.
- `.github/workflows/imagined-lesson-capture.yml`: the same test with `-- --capture`, on
  Compatibility, Forward+ and Mobile: the plain room, the dream twice a second apart, and a
  close shot of her. A shader compile error fails the job.

## Not yet

Round 7 built the questioning's **structure** with placeholder text (the author's lines are
unchanged; every new line reads 「待做·…」 / "TODO · …" and waits for the author):

- **Entry.** Q describes B (`q_wake`, `q_b_looks`); the player picks 「待做·去想象B」 or
  「待做·不去想」. Picturing her starts the scene as soon as Q's talk ends; there is no later
  automatic play. The scene no longer waits for the bag.
  Q describes B only on the author's branches that go on looking for the book (`search`, or
  `ask` then `keep_searching`); a talk that ends in silence, the grabbed book or the borrow
  plan never offers the choice, and the scene is passed over.
- **Hubs.** Each of B's four authored lines (`b_e_1`–`b_e_4`) offers three directions:
  `normal` (正常应对), `absurd` (荒诞/装疯) and `exit` (跳出幻想). Each direction is 2–4
  rounds of protagonist/B placeholders; a B line between rounds offers `go_on` and `exit`,
  and two of them cross over between normal and absurd. The directions rejoin B's next
  authored line; the last hub reaches the authored recollection `rec_1` and `b_e_5`.
- **「异想天开」.** In the absurd direction after "where's your textbook" a visible check of
  the new inner voice `whimsy` (value 3, placeholder) splits it: high (the protagonist steers
  the fantasy, 3 rounds) or low (B's authority wins, 1 round, then back to normal). The rules
  were changed for it: a `whimsy` check is the only check a subjective conversation may roll
  (`DialogueGraph.IMAGINATION_ABILITIES`), and it records only its own roll.
- **Leaving.** `exit` goes to two placeholder lines and ends the scene; leaving before
  `rec_1` writes `expectation_left_early`, which keeps the later lines that lean on the
  remembered set-square sound (`q_after_dismissal`) closed.
- **Clues.** Two placeholder imagined records mark where clues will sit:
  `imagined_b_clue_normal` (end of the normal direction at hub 3) and
  `imagined_b_clue_whimsy` (end of the high branch).

Still waiting for the author:

- all placeholder wording, the clue texts and which hub carries which clue;
- nested imaginings: an answer that opens a further fantasy inside this one (the
  `dream`/`reach` controls are built so a nested layer can deepen the filter).
