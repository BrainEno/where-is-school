# Prologue art migration: the biology-classroom experiment in the real classroom

- **Status:** In review (draft PR #203). Changes the shipping classroom (`scenes/locations/classroom/classroom.tscn`), the camera rig and the character looks.
- **Source:** the approved experiment, [BIOLOGY_CLASSROOM_EXPERIMENT.md](BIOLOGY_CLASSROOM_EXPERIMENT.md) (PR #200). The experiment stays where it is, under `scenes/dev/` (never exported). The game loads nothing from it; the two shaders it shares with the game live under `assets/materials/classroom/shaders/` and the experiment includes them.
- **Check:** `tests/prologue_art_test.gd` (Godot CI step `prologue_art`, under Xvfb so the shaders are compiled), plus the updated `classroom_visual_slice_test.gd` and `classroom_anomaly_test.gd`.
- **Evidence:** `tests/capture_prologue_art.gd` through `.github/workflows/prologue-art-capture.yml` (the real `main.tscn`, the game's own camera, 1600×900, opengl3 on Xvfb). The baseline frames come from commit `00ed8dc` (run 43853974466), before any art change.

## 1. What was migrated

| Part | In the experiment | In the game |
|---|---|---|
| Floor | `concrete.gdshader`, poured against an answer sheet (ruled grooves, red margin) | `floor_concrete.tres` on `Floor/Paint`; the same shader body (`concrete.gdshaderinc`), margin at x −6.2 by the window wall |
| Platform | darker concrete, no ruling | `platform_concrete.tres` on the stage and its step |
| Light | low warm sun through the window side, violet shade, linear tonemap | `WorldEnvironment`: linear, background (0.11, 0.09, 0.15), ambient (0.44, 0.38, 0.52) × 1.0; `Sun` (−42°, −106°) warm × 1.35; the ceiling fittings and the back fill are off |
| Walls | flat colour fields, cool lilac-grey | the painted textures are kept (the slice's hierarchy and texture budget), tinted cool: side walls (0.83, 0.88, 0.99), front wall (0.92, 0.96, 1.0) |
| Curtain | deep blue (0.17, 0.21, 0.42) | `curtain_blackout.tres` |
| The cut | floor-to-ceiling opening, a blank sheet in it | the west wall's sill and header removed: the hole is z 0.95–3.45, y 0–3.2. `Anomalies/VoidOpening/BlankSheet` (`void_sheet.tres`, unlit paper) fills it once the curtain is drawn |
| Paper | the whole frame turns into a pencil drawing | **local** (owner's requirement): `Anomalies/PaperZone` turns only the room within 2.6 m of the cut into the drawing |
| Characters | ink (0.16, 0.14, 0.2), hard two-step terminator | `q_look.tres`, `protagonist_look.tres`: outline ink (0.16, 0.14, 0.2), width 0.010, `edge_softness` 0.03 |
| Camera | fixed shots per zone | the game keeps its following camera (owner: no fixed camera); important interactions get a **focus** (§3) |

## 2. The paper anomaly (`PaperZone`)

`scripts/environment/paper_zone.gd` + `assets/materials/classroom/shaders/paper_zone.gdshader`.

- **Local by construction.** Only meshes whose world box reaches the zone (a vertical cylinder of `radius` round the cut, plus the torn front's margin) get the overlay. The shader masks itself by the same world-space distance, so a mesh half inside is drawn only where it is inside, and the edge meets itself across meshes. The pencil (rules, margin, three hatching families) is laid out in world metres on each face's plane: it does not slide when the camera moves.
- **Removable.** The overlay is a `material_overlay`; authored materials are never touched. A mesh that already has an overlay (the desks' wash and ink) keeps it: it gets a copy of the chain with the paper appended. `set_drawn(false)` restores every overlay exactly.
- **People are never drawn.** `excluded_paths` keeps `Actors` out; the player and the companion are not in the room's tree.
- **Driven by the story.** `ClassroomAnomalies._show_void()` (the curtain's state, used by the draw, the restore from the story flags and the refused-fall reset) calls `set_drawn`. Animated when the curtain is drawn in play (2.2 s spread, 0.9 s lift), instant on a restore. No dialogue changed.
- **Portable.** No screen or depth texture: the same on Forward+, Mobile and Compatibility.

## 3. Camera focus

`scripts/world/camera_shot.gd`, `scripts/world/camera_focus_director.gd`, `CameraRig.focus_on / release_focus / clear_focus`.

- An `Interactable` may carry a `camera_shot`. In the classroom: Q (`q_talk`), the curtain, the window and the blackboard. Shots live in `assets/camera/shots/`.
- **When:** engaged when the player activates such an interactable, held while the player is locked by what it started (beat, conversation, inspection), released when control comes back. Walking, hovering and highlighting never move the camera. A location change drops the shot at once (`LocationFlow._stand_player_up`).
- **How:** relative to the default framing - the view centre moves part of the way to the subject, the camera comes closer, swings a few degrees and narrows the lens. A critically damped spring glides each shot's weight (no overshoot); two shots cross-fade without dipping home. `frame_point` (ExitWatch) still has the last word on what is centred. Movement keys stay on the default axes.
- **Walls:** a shot centres the rig between the player and the subject, so `CameraOccluderFader` casts one more ray, to the player's own eye, while a focus holds: a wall behind the player is faded as it would be in the default framing.
- **Default pose unchanged:** with no shot the rig is exactly what it was (`camera_rig_test`, `doorway_watch_test`).

## 4. Known limits

- The wall textures still carry the old window opening in `paint_classroom_textures.py` (`WEST_VOID_OPENING`, y 0.50–2.75); the quads that would show it were removed, so it is never drawn. `floor.png` is no longer sampled but is still produced by the script.
- The paper's hatching in `light()` is faded by camera distance per vertex (no derivatives there); on the large floor quad that is an approximation.
- Q's known model issues (shoulder skin gap, low-poly hands, PR #202) are unchanged.
